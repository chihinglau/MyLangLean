# MyLangLean PC 服务端 + App 联网同步/OTA - 产品需求文档

## Overview
- **Summary**: 在现有 `server/` FastAPI MVP（内存态：游客 JWT、stub ASR、PodcastIndex 代理）基础上，建成可持久运行的 PC 端 Web 服务：用户注册与账号管理、发现内容（播客/单集）发布、用户订阅同步管理、App 安装包发布与 OTA 升级；并将 App「发现/订阅/账号」改为联网优先、离线可用，新增 App 内版本检查与下载安装。
- **Purpose**: 让一台 PC（或云主机）成为多个 App 端的数据与分发中枢；发现内容由服务端统一发布，用户跨设备订阅一致，版本迭代不再需要手工传 APK。
- **Target Users**: ① App 学习者（注册/登录、浏览与订阅、收更新）；② 运营者（管理员，通过管理台/管理 API 维护用户、内容、安装包）；③ 开发者（自测与后续迭代）。

## Goals
- 账号体系：邮箱注册（密码加盐哈希）、登录鉴权（JWT）、游客设备登录保留；管理员可列出/禁用用户。
- 内容发布：管理员可对播客/单集做增删改与上下架；App 发现页通过网络拉取服务端目录（搜索、语言/难度筛选），离线时回退内置目录与最近缓存。
- 订阅同步：App 订阅状态按账号在服务端保存与多端同步；管理员可查看任意用户订阅。
- 软件发布：管理员上传 APK（平台/版本号/构建号/更新说明/强制标志），App 启动与手动检查时获得升级信息并能在 App 内下载、调起系统安装器。
- 提供零构建步骤的运营管理台（静态 HTML + 原生 JS，由服务端托管于 `/admin`）。

## Non-Goals
- 不做邮箱验证码/找回密码/第三方登录/多角色细粒度权限（管理员用独立 Admin Token）。
- 不引入 PostgreSQL/Redis/ORM/新 Python 依赖；持久化用标准库 sqlite3，文件放本地数据目录。
- 不做 App 端 iOS 安装（仅检查接口跨平台预留；Android 实现下载安装，OH/iOS 给手动提示）。
- 不做商业订阅支付；「订阅」仅指对播客内容的关注关系。
- 不做真正的后台静默安装（Android 系统限制），调起系统 PackageInstaller 即可。
- 不重写既有 ASR/翻译/评分/额度路由（保持兼容，仅让其用户体系落到持久化存储）。

## Background & Context
- `server/` 已存在：FastAPI 0.115 + jose JWT + httpx + pydantic v2；路由 auth/quota/transcriptions/translate/score/discover(proxy)；数据全部在 `core/deps.py` 的内存 `UserStore`，登录即自动注册、密码 sha256 明文摘要。
- `app/`（Flutter，Dart SDK `>=3.4.0 <4.0.0`，同时兼容标准 Flutter 3.47 与 OH fork 3.22）已含依赖 `dio ^5.4.0`、`Env.apiBaseUrl`（默认 `http://127.0.0.1:8000`，支持 `--dart-define`）；`AndroidManifest.xml` 已有 INTERNET 权限与 `usesCleartextTraffic=true`；发现页/订阅/账号均通过 Riverpod repository 接口装配（`catalogRepositoryProvider`/`libraryRepositoryProvider`/`authRepositoryProvider`），可在不改页面代码的前提下替换实现。
- 内置目录 `MockCatalog`：8 个播客（p1-p8，en/ja/fr/de/es/ko/zh，初/中/高级）× 每播客 2 个示例单集，示例音频 `app/assets/audio/sample.mp3`（17.64s）。
- 真机为 HBN AL00（Android 12, API31, arm64），adb 可用；可用 `adb reverse tcp:8000 tcp:8000` 让手机经 localhost 访问 PC 服务，绕开防火墙/网段问题。
- Python 运行环境：`.tools/venvs/mll/Scripts/python.exe`（fastapi 0.115.5 等已装齐，TestClient 可用）。

## Functional Requirements

### 账号与管理
- **FR-1**: 邮箱+密码注册，密码以 PBKDF2-HMAC-SHA256 加盐哈希存储；重复邮箱返回 409；注册成功即发 JWT。
- **FR-2**: 登录校验密码，失败返回 401；用户被禁用后登录返回 403；JWT 解析沿用现有 secret/算法。
- **FR-3**: `GET /me` 返回当前账号资料；游客仍可经 `/auth/device` 登录（持久化游客行）。
- **FR-4**: 管理员凭 `X-Admin-Token`（`MLL_ADMIN_TOKEN`，默认开发值并在响应/文档提示）可：列出用户（含状态/注册时间/订阅数）、禁用/启用用户、重置用户密码。
- **FR-5**: 用户、订阅、内容、发布包数据持久化到 SQLite，服务重启不丢；首次启动自动建表并播种内置 8 播客×2 单节目录与一份示例音频。

### 内容发布与发现同步
- **FR-6**: 公开目录接口：`GET /catalog/podcasts`（支持 `q` 标题/作者/描述模糊搜索、`language`、`level`、分页）、`GET /catalog/podcasts/{id}`、`GET /catalog/podcasts/{id}/episodes`、`GET /catalog/meta`（语言/难度选项与内容版本号）；下架内容不出现在公开接口。
- **FR-7**: 管理员可创建/修改/删除播客与单集、上下架（字段：标题、作者、feedUrl、语言、难度、描述、artwork URL、单集音频 URL、时长、发布日期）。
- **FR-8**: App 发现页联网优先：从服务端拉取目录与单集（350ms 防抖搜索沿用），请求失败/超时时回退内置 `MockCatalog`；成功结果缓存到本地 KV，下次启动断网仍展示最近一次服务端目录。
- **FR-9**: 服务端托管示例媒体文件（`/media/...`），播种单集的 `audio_url` 为可直接播放的服务端 URL；App 播放服务端单集走现有播放器网络音频链路。

### 订阅同步
- **FR-10**: 登录/游客均可 `GET /me/subscriptions`、`PUT /me/subscriptions/{podcastId}`（幂等订阅）、`DELETE /me/subscriptions/{podcastId}`；订阅不存在/下架播客返回 404。
- **FR-11**: App 订阅操作为「本地即时生效 + 后台同步」：有网时推送变更并以服务端列表为准做对账合并；无网时本地保留，恢复后下次启动/下拉时对账。
- **FR-12**: 管理员可查看任意用户的订阅列表。

### 软件发布与 OTA
- **FR-13**: 管理员多部分上传发布包：APK 文件 + 平台（android/ohos/预留）+ 语义版本（如 0.4.1）+ 构建号 + 渠道（stable/beta）+ 更新说明 + 是否强制；服务端计算大小与 SHA-256 并落盘到数据目录。
- **FR-14**: `GET /releases/latest?platform=android&channel=stable&current=0.4.0` 返回 `has_update` 与最新发布信息（版本、构建号、说明、强制、大小、sha256、下载 URL、发布时间）；按语义版本+构建号比较，无更新时 `has_update=false`；下载接口支持断点 Range 并校验存在性。
- **FR-15**: App 启动后异步检查一次更新（24h 内不重复打扰，强制更新除外），「我的」页提供「检查更新」；有更新时弹窗展示说明，确认后 App 内下载（带进度/失败可重试），完成后经 FileProvider 调起系统安装器；无法执行的平台（OH/iOS/桌面）展示手动下载说明。

### 管理台
- **FR-16**: `/admin` 提供单文件管理台（原生 HTML/CSS/JS，无 npm 构建）：Token 登录（存 localStorage）；四个功能区——用户管理、内容发布（播客+单集）、订阅查看、版本发布（含上传 APK 与历史列表/删除）。

## Non-Functional Requirements
- **NFR-1（零新增依赖/双端兼容）**：服务端不得新增 requirements.txt 依赖（stdlib sqlite3/hashlib/email 校验用简单正则）；App 不新增 Dart 依赖、不使用 `Color.withValues` 等 3.47-only API，OH fork 3.22（Dart 3.4）下 analyze 通过。
- **NFR-2（可测性/全自动）**：服务端全部新能力可用 TestClient 自动化测试（临时数据目录），一键脚本跑通；App 逻辑用单测/widget 测试覆盖，构建 APK 并对 live 服务+真机做 E2E，全程不需人工操作。
- **NFR-3（健壮性）**：App 所有网络调用必须有超时（连接 ≤ 5s）与异常回退，服务端不可用时 App 既有功能不崩溃、可离线使用。
- **NFR-4（安全基线）**：密码不存明文；管理接口无正确 Token 一律 401；上传文件限定扩展名（.apk）并落目录隔离；SQL 全部参数化。
- **NFR-5（性能）**：目录接口为简单等值/LIKE 查询，百级数据量下 P95 < 100ms（本机 TestClient 可验证返回成功与结构，性能为人工/日志旁证）。

## Constraints
- **Technical**: Windows + PowerShell；服务端 Python（venv 已存在）；App 标准版 Flutter 在 `.tools/flutter`；真机 adb；服务监听 `0.0.0.0:8000` 以便局域网/`adb reverse` 访问；数据目录默认 `server/data/`（可用 `MLL_DATA_DIR` 覆盖）。
- **Business**: 延续中文 UI/中文沟通；本轮不做支付、不做应用商店上架。
- **Dependencies**: 仅现有 pinned 依赖；文件下载在 Android 端用 `HttpURLConnection`（系统库），不引第三方。

## Assumptions
- 单机部署、单管理员 Token 即可满足当前阶段；后续多管理员再建表扩展。
- 示例音频版权无问题（仓库自带 TTS 生成的 sample.mp3）。
- 设备允许安装未知来源（首次安装时系统弹窗；自测可经 adb install 代替人工确认，App 内流程验证到下载完成与安装器唤起）。
- 用户已预先授权本任务全自动执行（方案、开发、自测不设人工审批停顿）。

## API 契约（实现以本文档为准）

所有业务接口前缀 `/api/v1`；鉴权接口除注明外携带 `Authorization: Bearer <jwt>`；管理接口携带 `X-Admin-Token`。

账号：
- `POST /auth/device` `{device_id}` → `{access_token, token_type, is_guest}`
- `POST /auth/register` `{email, password(>=6), name?}` → `{access_token, token_type:"bearer", is_guest:false, account:{id,email,name,is_guest,created_at}}`
- `POST /auth/login` `{email,password}` → 同 register 响应
- `GET /me` → `account` 对象
- 管理：`GET /admin/users`、`PATCH /admin/users/{id}` body `{disabled?, name?, reset_password?}`、`GET /admin/users/{id}/subscriptions`

目录（公开）：
- `GET /catalog/meta` → `{languages:[{code,label}], levels:[{name,label}], content_version}`
- `GET /catalog/podcasts?q=&language=&level=&page=1&size=50` → `{items:[Podcast],page,size,total,content_version}`
- `GET /catalog/podcasts/{id}` → `Podcast`
- `GET /catalog/podcasts/{id}/episodes` → `[Episode]`
- 管理：`POST /admin/podcasts`、`PUT /admin/podcasts/{id}`、`DELETE /admin/podcasts/{id}`（连带单集）、`POST /admin/podcasts/{id}/episodes`、`DELETE /admin/episodes/{id}`、`POST /admin/catalog/reseed`

Podcast：`{id,title,author,feed_url,artwork_url,language,level,description,published}`
Episode：`{id,podcast_id,title,audio_url,duration_ms,pub_date,language}`
App 侧 Dart JSON 仍采用 camelCase（`feedUrl`/`artworkUrl`/`durationMs`/`pubDate`），故服务端对目录接口同时输出 snake_case 与 camelCase 别名字段（或统一 camelCase 输出——实现统一用 camelCase 输出以直接复用 `Podcast.fromJson/Episode.fromJson`；管理 API 入参接受两种写法）。

订阅：
- `GET /me/subscriptions` → `{items:[Podcast],content_version}`
- `PUT /me/subscriptions/{podcastId}` → 204
- `DELETE /me/subscriptions/{podcastId}` → 204

发布：
- `GET /releases/latest?platform=android&channel=stable&current=0.4.0` → `{has_update,version,build_no,notes,mandatory,size,sha256,url,published_at}`（无更新时仅 `has_update:false`）
- `GET /releases?platform=&channel=` → 发布历史列表
- `GET /releases/download/{release_id}` → APK 文件流（支持 Range）
- 管理：`POST /admin/releases`（multipart：file + 字段）、`DELETE /admin/releases/{id}`

## Acceptance Criteria

### AC-1: 服务端持久化与播种
- **Type**: `rule`
- **Given**: 使用空的临时 `MLL_DATA_DIR` 启动服务
- **When**: 首次调用任意接口后检查数据目录与库表
- **Then**: 生成 sqlite 库文件；users/podcasts/episodes/subscriptions/releases 表存在；podcasts 有 8 条、episodes 有 16 条；重启进程后数据仍在；`/media/sample.mp3` 可访问且与 app 资源一致
- **Pass Condition**: TestClient 用例断言上述全部成立
- **Evidence**: `server/tests` 用例输出 + 数据库文件存在性输出

### AC-2: 注册/登录/鉴权安全行为
- **Type**: `rule`
- **Given**: 全新数据库
- **When**: 依次执行：注册 a@x.com、重复注册、错误密码登录、正确登录、访问 /me、禁用后登录、无 Token 访问 /me
- **Then**: 200+JWT / 409 / 401 / 200+JWT / 资料正确 / 403 / 401；库中密码字段为 pbkdf2 形式且不等于明文
- **Pass Condition**: 自动化用例全部断言通过
- **Evidence**: 测试输出与库记录哈希前缀（`pbkdf2$`）

### AC-3: 管理员接口鉴权与用户管理
- **Type**: `rule`
- **Given**: 已注册用户
- **When**: 无 Token / 错误 Token / 正确 Token 调用 `GET /admin/users` 与 `PATCH /admin/users/{id}`
- **Then**: 分别 401 / 401 / 200；禁用生效；返回含订阅数统计
- **Pass Condition**: 自动化用例通过
- **Evidence**: 测试输出

### AC-4: 目录公开接口与筛选搜索
- **Type**: `rule`
- **Given**: 已播种目录
- **When**: 调用 meta、podcasts 全量、`q=coffee`、`language=ja`、`level=beginner`、下架一个播客后再查、查其单集
- **Then**: meta 含 7 种语言与 3 难度；全量 8 条；coffee 命中 1 条；ja 命中 1 条；beginner 命中 3 条（p1/p3/p5）；下架后列表与详情均 404/不出现；单集 2 条且 audio_url 可访问
- **Pass Condition**: 自动化用例通过
- **Evidence**: 测试输出

### AC-5: 订阅同步接口
- **Type**: `rule`
- **Given**: 注册用户与已发布播客
- **When**: 空列表查询 → PUT 订阅（两次幂等）→ GET 为 1 → DELETE → GET 为 0；订阅不存在 id 返回 404；管理员查看该用户订阅
- **Then**: 全部状态码与数量正确
- **Pass Condition**: 自动化用例通过
- **Evidence**: 测试输出

### AC-6: 发布包管理与版本比较
- **Type**: `rule`
- **Given**: 管理员上传一个假 APK（字节内容任意、扩展名 .apk）版本 0.4.1 build 5
- **When**: 无 Token 上传被拒；正确 Token 上传成功（size/sha256 正确）；current=0.4.0 查询 latest；current=0.4.1 查询；Range 下载首字节
- **Then**: 401 / 200；has_update true/false 正确；下载 206/200 且内容 sha256 与记录一致；强制标志与说明透传
- **Pass Condition**: 自动化用例通过
- **Evidence**: 测试输出（哈希比对）

### AC-7: 管理台可用
- **Type**: `rule`
- **Given**: 服务运行
- **When**: GET `/admin`（未带 token）
- **Then**: 返回 200 HTML（含四个功能区标记与登录输入），静态资源不依赖外网 CDN
- **Pass Condition**: TestClient 断言 + 浏览器自动化实际登录并完成一次内容发布
- **Evidence**: 测试输出 + 浏览器截图

### AC-8: App 发现联网优先与离线回退
- **Type**: `rule`
- **Given**: live 服务（adb reverse 8000）且服务端目录可被管理员新增一条独有播客
- **When**: 启动 App 打开发现页搜索该独有标题；再停掉服务重复搜索
- **Then**: 在线时结果来自服务端（出现独有播客）；离线时不崩溃且展示内置/缓存目录
- **Pass Condition**: 真机截图（在线命中、离线回退）+ App 单测覆盖回退逻辑
- **Evidence**: 截图 + flutter test 输出

### AC-9: App 注册登录与订阅多端一致
- **Type**: `rule`
- **Given**: live 服务
- **When**: App 内注册新账号→订阅一个播客→服务端查该用户订阅为 1；清数据重新登录同账号→订阅仍在
- **Then**: 服务端与 App 状态一致；登出后回退游客
- **Pass Condition**: 真机截图 + 服务端查询输出
- **Evidence**: E2E 记录

### AC-10: App OTA 全链路
- **Type**: `rule`
- **Given**: App 当前版本低于服务端 latest（服务端已发布新版本条目）
- **When**: App 检查更新→弹窗→确认下载→下载完成
- **Then**: 弹窗显示版本/说明；下载进度到达 100%；设备上安装包 sha256 与服务端一致；系统安装器被唤起（截图可见）；无更新时「已是最新」；平台不支持时给手动提示
- **Pass Condition**: 真机录屏式截图序列 + 哈希校验输出 + 单测覆盖版本比较
- **Evidence**: 截图 + adb 校验输出

### AC-11: 服务端一键测试与回归
- **Type**: `rule`
- **Given**: 干净 venv
- **When**: 运行测试脚本（直跑或 pytest 形态）
- **Then**: 所有服务端用例通过，且既有 smoke_test（转录/额度/翻译/评分）仍通过
- **Pass Condition**: 全部 PASS 退出码 0
- **Evidence**: 命令输出

### AC-12: App 质量门禁
- **Type**: `rule`
- **When**: 标准版 flutter analyze + flutter test + build apk --debug
- **Then**: 0 error / 0 warning（deprecated info 可接受，仅 withOpacity 等兼容 3.22 的保留项）；全部测试通过；APK 构建成功
- **Pass Condition**: 三条命令输出达标
- **Evidence**: 命令输出与 APK 路径

### AC-13: 联网功能的异常安全
- **Type**: `rule`
- **Given**: 服务器关闭/返回 500/超时 三种故障
- **When**: App 执行发现加载、登录、订阅、更新检查
- **Then**: 均不崩溃；发现回退、登录展示中文错误、订阅保留本地、更新检查静默失败；widget/单元测试可注入假 client 验证
- **Pass Condition**: 单测通过 + 真机断网截图
- **Evidence**: flutter test + 截图

### AC-14: 双端兼容与代码质量
- **Type**: `rubric`
- **Dimension**: 代码与既有架构的一致性（分层、命名、中文注释、无新依赖、OH 3.22 兼容）
- **Scale**: 1-5
- **Anchors**: 1 = 绕过既有接口/引入新依赖/破坏 OH 兼容；3 = 功能正确但分层混乱或重复实现；5 = 严格复用 repository/Provider 分层、零新依赖、注释与测试齐备、analyze 干净
- **Pass Threshold**: >= 4
- **Evidence**: 独立 Review 代码走查

### AC-15: E2E 完成度
- **Type**: `rubric`
- **Dimension**: 自测覆盖真实链路的完整度（管理台发布→App 发现→订阅→账号→OTA）
- **Scale**: 1-5
- **Anchors**: 1 = 只测了单接口；3 = 接口全测但无真机链路；5 = live 服务+真机+管理台浏览器全链路截图证据
- **Pass Threshold**: >= 4
- **Evidence**: review.md 证据清单

## Open Questions
- 无（用户已授权全自动决策；模糊项按 Assumptions 执行）。
