# MyLangLean PC 服务端 + App 联网同步/OTA - 实施计划

> 用户已预先授权全自动执行（Spec Mode 的 Approve 门禁视为已通过），按 tasks 顺序实施并自验。

## Task 1: 服务端持久化基座（SQLite + 配置 + 建表播种）
- **Status**: `pending`
- **Priority**: high
- **Depends On**: None
- **Description**:
  - `core/config.py` 增加 `data_dir`（默认 `<repo>/server/data`，env `MLL_DATA_DIR` 覆盖）、`admin_token`（默认 `dev-admin-token`）；数据目录下 `mll.db`、`releases/`、`media/`。
  - 新增 `core/db.py`：标准库 sqlite3 连接工厂（WAL、外键、Row factory）、启动建表（users/podcasts/episodes/subscriptions/releases）、轻量 repository 函数；全部参数化 SQL。
  - 新增 `core/security.py` 的 `hash_password/verify_password`（pbkdf2_hmac sha256，salt 16B hex，迭代 200k，格式 `pbkdf2$iters$salt$hash`）。
  - 播种：8 播客×2 单集（与 app `MockCatalog` 一致；单集 `audio_url=/media/sample.mp3`、duration_ms 17640、pub_date 2026-09-20/13）；首次启动把 `app/assets/audio/sample.mp3` 复制到 `data/media/sample.mp3`（源路径相对仓库根定位，找不到则生成极小占位并记录）。
  - `content_version`：用 podcasts/episodes 的 max(updated_at) 秒级时间戳字符串。
  - main.py 挂载 StaticFiles：`/media`→data/media、`/files/releases`→data/releases（或经下载路由）；启动时 init_db。
- **Acceptance Criteria Addressed**: AC-1, NFR-1, NFR-4
- **Test Requirements**:
  - `rule` TR-1.1: 临时 MLL_DATA_DIR 启动后表存在、8 播客 16 单集、media 文件可 GET 200；重启（新 TestClient/新进程模拟：重新 init）数据不丢、重复播种不产生重复行。证据：测试输出。
  - `rule` TR-1.2: 哈希函数自验：同一密码两次哈希不同盐但都 verify 成功，错误密码失败，存储串以 `pbkdf2$` 开头。证据：测试输出。

## Task 2: 账号体系（注册/登录/me）与持久化用户仓储
- **Status**: `pending`
- **Priority**: high
- **Depends On**: Task 1
- **Description**:
  - 重写 `core/deps.py` 的用户存储为基于 db 的仓储（保留 `get_principal`/`CurrentUser`/Principal 接口）；禁用用户在登录时 403；游客 upsert 落库。
  - 路由：新增 `POST /auth/register`（邮箱格式校验、密码 ≥6、昵称可选；409 重复）；改 `POST /auth/login`（真校验、401 未注册/错密码、403 disabled）；新增 `GET /me`。TokenOut 增加 account 字段；JWT payload 不变。
  - 既有 quota/transcriptions 路由改读持久用户（读不到用户时 401）。
- **Acceptance Criteria Addressed**: AC-2
- **Test Requirements**:
  - `rule` TR-2.1: 注册/重复注册/错密码/正确登录/禁用/游客/me 状态码与响应体正确（AC-2 全部分支）。证据：测试输出。

## Task 3: 目录公开 API + 管理 CRUD + 媒体播放
- **Status**: `pending`
- **Priority**: high
- **Depends On**: Task 1
- **Description**:
  - `routes_catalog.py`：`GET /catalog/meta`、`GET /catalog/podcasts`（q/language/level/page/size，仅 published）、`GET /catalog/podcasts/{id}`、`GET /catalog/podcasts/{id}/episodes`。
  - 输出 JSON 统一 camelCase 以直接匹配 App `Podcast.fromJson/Episode.fromJson`（id/title/author/feedUrl/artworkUrl/language/level/description/published；episode: id/podcastId/title/audioUrl/durationMs/pubDate/language）。
  - 管理：`POST/PUT/DELETE /admin/podcasts[/{id}]`、`POST /admin/podcasts/{id}/episodes`、`DELETE /admin/episodes/{id}`、`POST /admin/catalog/reseed`；DELETE 播客级联单集与订阅。
  - `X-Admin-Token` 依赖 `require_admin`（401 错误/缺失）。
  - 移除/保留原 discover proxy 路由（保留，标签为 PodcastIndex 代理）。
- **Acceptance Criteria Addressed**: AC-4, NFR-4
- **Test Requirements**:
  - `rule` TR-3.1: AC-4 全部分支（meta/搜索/语言/难度/下架/单集/audio 可访问）。证据：测试输出。
  - `rule` TR-3.2: 管理 CRUD 无 token 401、有 token 200；非法 level/language 返回 422。证据：测试输出。

## Task 4: 用户管理与订阅管理
- **Status**: `pending`
- **Priority**: high
- **Depends On**: Task 2, Task 3
- **Description**:
  - `GET /admin/users`（列表：id/email/name/is_guest/disabled/created_at/subscription_count）、`PATCH /admin/users/{id}`（disabled/name/reset_password）、`GET /admin/users/{id}/subscriptions`。
  - `routes_me.py`（或 subscriptions 路由）：`GET /me/subscriptions`、`PUT /me/subscriptions/{podcastId}`（幂等，目标不存在或下架 404）、`DELETE`（幂等 204）。
- **Acceptance Criteria Addressed**: AC-3, AC-5
- **Test Requirements**:
  - `rule` TR-4.1: AC-3 与 AC-5 全部分支通过。证据：测试输出。

## Task 5: 软件发布/下载/版本检查
- **Status**: `pending`
- **Priority**: high
- **Depends On**: Task 1
- **Description**:
  - `routes_releases.py`：管理端 `POST /admin/releases`（multipart：file 必填 .apk、platform/version/buildNo/channel/notes/mandatory）；落盘 `data/releases/{platform}-{version}-{buildNo}-{ts}.apk`，计算 size/sha256，写表；`GET /admin/releases`、`DELETE /admin/releases/{id}`（连带删文件）。
  - 公开 `GET /releases/latest`（按 platform+channel 取 build_no 最大；比较 current 语义版本与 build_no）、`GET /releases`、`GET /releases/download/{id}`（FileResponse，支持 Range 用 fastapi 的 FileResponse 自带能力）。
  - 语义版本比较用本地小函数（split('.',) 补齐 3 段整数比较，再比 buildNo）。
- **Acceptance Criteria Addressed**: AC-6
- **Test Requirements**:
  - `rule` TR-5.1: AC-6 全分支：401 上传、200 上传、size/sha256、has_update 真假、下载哈希一致、非 apk 拒绝 400。证据：测试输出。

## Task 6: 运营管理台（/admin 静态页）
- **Status**: `pending`
- **Priority**: medium
- **Depends On**: Task 3, Task 4, Task 5
- **Description**:
  - 单文件 `server/static/admin/index.html`（原生 CSS/JS，无外部 CDN；字体用系统栈）：顶部 Token 输入存 localStorage 并加到 `X-Admin-Token`；四个区：用户（列表/禁用/重置密码/查看订阅）、内容（播客列表/新建编辑/单集增删/上下架/reseed）、订阅（按用户邮箱查）、版本（表单上传 APK + 历史列表/删除）。
  - main.py 挂载 `/admin`→静态目录（访问 `/admin` 返回 index.html）。
- **Acceptance Criteria Addressed**: AC-7
- **Test Requirements**:
  - `rule` TR-6.1: TestClient GET /admin 200 且含四区标记；浏览器自动化完成「登录→新建播客→App 可见→上传发布包→删除」（在 E2E 任务中执行）。证据：测试输出 + 浏览器截图。

## Task 7: 服务端测试套件与运行脚本
- **Status**: `pending`
- **Priority**: high
- **Depends On**: Task 2-5
- **Description**:
  - 新增 `server/tests/conftest_helpers.py`（或每个文件自带 fixture：temp data dir + reset init + TestClient 工厂）；`test_db_seed.py/test_auth.py/test_catalog.py/test_subscriptions.py/test_releases.py/test_admin.py`，全部既可 pytest 也可 `python file.py` 直跑；新增 `server/tests/run_all.py` 顺序发现并执行所有 test_* 模块。
  - 更新保留 `smoke_test.py`（适配持久用户：先 device 登录）。
  - 新增 `server/README.md`：启动、配置项、API 摘要、测试命令。
- **Acceptance Criteria Addressed**: AC-11
- **Test Requirements**:
  - `rule` TR-7.1: `.tools/venvs/mll/python.exe server/tests/run_all.py` 全部 PASS 退出码 0；smoke 仍通过。证据：命令输出。

## Task 8: App 联网基座（ApiClient/配置/模型映射）
- **Status**: `pending`
- **Priority**: high
- **Depends On**: None（可按契约并行）
- **Description**:
  - `lib/data/remote/ml_api.dart`：`MlApi`（dio，baseUrl 从 KV `api.base_url` 读，默认 `Env.apiBaseUrl`；connectTimeout 5s、receiveTimeout 10s；Authorization 拦截器从 KV `auth.token` 读；统一错误转 `MlApiException`（含中文友好消息映射：401/403/404/网络超时））。
  - JSON 映射直接复用 `Podcast.fromJson/Episode.fromJson`；账号/订阅/更新模型放同文件或 entities。
  - `apiBaseUrlProvider`（StateProvider 由 main.dart 用 KV 值 override 初始值）；提供设置函数持久化 KV。
  - 不新增依赖；OH 兼容（dio 纯 Dart）。
- **Acceptance Criteria Addressed**: NFR-1, NFR-3, AC-13
- **Test Requirements**:
  - `rule` TR-8.1: 单测：错误映射中文消息、baseUrl KV 覆盖、Podcast/Episode JSON 解析（含缺省值）。证据：flutter test。

## Task 9: App 账号注册登录联网化
- **Status**: `pending`
- **Priority**: high
- **Depends On**: Task 8
- **Description**:
  - `AuthRepository` 接口增加 `Future<Account> register({email,password,name})`；mock/persistent 实现补齐（mock 直接本地成功，persistent 离线模拟）。
  - 新增 `RemoteAuthRepository`（或 `SyncedAuthRepository` 组合 KV + MlApi）：register/login 调服务端并保存 JWT/账号到 KV；`loginAsGuest` 调 `/auth/device`（失败时本地游客降级）；`current/quota` 读 KV 快照，登录成功后拉 `/quota` 刷新；`logout` 清 token 回游客。
  - 我的页登录 BottomSheet 增加「登录 / 注册」分段；注册模式加昵称（可选）、确认校验与服务端 409/401 中文提示、loading 态。
  - main.dart 用 SyncedAuthRepository override（持有 kv + deviceId：用现有持久仓储做离线镜像）。
- **Acceptance Criteria Addressed**: AC-9, AC-13
- **Test Requirements**:
  - `rule` TR-9.1: 注入假 MlApi（成功/409/401/断网）单测：注册登录状态落 KV、错误消息中文、游客降级可用。证据：flutter test。

## Task 10: App 发现目录联网同步 + 离线回退
- **Status**: `pending`
- **Priority**: high
- **Depends On**: Task 8
- **Description**:
  - 新增 `RemoteCatalogRepository implements CatalogRepository`：featured/search/episodesOf 调目录 API（featured 不带 q；search 带 q；筛选仍在 App 侧）。
  - `FallbackCatalogRepository`：先远程（5s 超时），异常→KV 缓存（`cache.catalog`/`cache.episodes.{id}` 带时间戳）→内置 MockCatalog；远程成功后写缓存。
  - main.dart override catalogRepositoryProvider 为 fallback 实现；页面代码不动；单集 audio_url 为相对路径 `/media/...` 时拼接 baseUrl。
- **Acceptance Criteria Addressed**: AC-8, AC-13
- **Test Requirements**:
  - `rule` TR-10.1: 单测：远程成功用远程并写缓存；远程抛错读缓存；无缓存回退 Mock（8 条）；相对 URL 拼接正确。证据：flutter test。
  - `rule` TR-10.2: widget 测试发现页在假 API 返回 1 条独有播客时能搜到、断网注入时显示内置目录不崩。证据：flutter test。

## Task 11: App 订阅同步
- **Status**: `pending`
- **Priority**: high
- **Depends On**: Task 9, Task 10
- **Description**:
  - 新增 `SyncedLibraryRepository` 组合 PersistentLibraryRepository + MlApi：`toggleSubscription` 本地即时改+KV 持久（沿用现状），有 token 时后台 PUT/DELETE（失败静默标记 dirty KV `subscriptions.dirty`）；新增 `syncSubscriptions()`：有网 GET /me/subscriptions 与本地按 id 并集对账、清 dirty；无网跳过。
  - main.dart：启动登录态恢复后异步 sync；library 页 build/下拉时触发；discover 订阅按钮后 bump 既有 refresh。
  - 游客订阅仍只本地（服务端游客也支持，但游客身份随 device 稳定；实现上游客也同步——device 登录后即有 token，默认同步，失败本地保留）。
- **Acceptance Criteria Addressed**: AC-9, AC-11(FR-11), AC-13
- **Test Requirements**:
  - `rule` TR-11.1: 单测：乐观更新立即生效；PUT 失败置 dirty 不抛错；sync 时服务端新增项进入本地、本地多的项保留（并集策略）；断网不崩。证据：flutter test。

## Task 12: App OTA 升级
- **Status**: `pending`
- **Priority**: high
- **Depends On**: Task 8
- **Description**:
  - 版本常量：`Env.appVersion` 升 `0.4.0`；pubspec version 同步 `0.4.0+4`；新增更新模型与比较纯函数（`hasUpdate(current, remote)`）。
  - `lib/pal/updater_service.dart`：MethodChannel `mylanglean/updater`，方法 `downloadAndInstall(url)`，事件流进度（success/progress/error/installUnavailable）。
  - Android：新增 `MlUpdaterPlugin.kt`（HttpURLConnection 下载到 externalCacheDir/mll-update.apk，进度 sink；完成后 FileProvider + ACTION_VIEW `application/vnd.android.package-archive` 唤起安装）；MainActivity 注册；Manifest 加 `REQUEST_INSTALL_PACKAGES` 权限；res/xml/provider_paths.xml + FileProvider `com.mylanglean.app.fileprovider`。
  - 启动后异步检查（KV `update.last_check_at`，24h 节流，mandatory 不节流）；我的页新增「检查更新」；弹窗（标题/说明/强制时不可取消）+下载进度对话框（失败重试）；平台不支持 catch MissingPluginException 显示手动提示。
- **Acceptance Criteria Addressed**: AC-10, AC-13, NFR-1
- **Test Requirements**:
  - `rule` TR-12.1: 单测：版本比较（0.4.0<0.4.1、0.4.1=0.4.1、build 号决胜、非法字符串容错）。证据：flutter test。
  - `rule` TR-12.2: widget 测试：有更新弹窗出现且含版本号；无更新显示「已是最新」SnackBar；mandatory 无关闭按钮。证据：flutter test。

## Task 13: 我的页服务与更新设置 + 质量门禁
- **Status**: `pending`
- **Priority**: medium
- **Depends On**: Task 9, Task 12
- **Description**:
  - 我的页新增「服务与更新」卡：服务器地址（点击弹编辑框，持久化 `api.base_url`，立即对 MlApi 生效）、连接状态（进入时打 /health 展示 在线/离线）、检查更新。
  - 标准版 flutter analyze（0 error/0 warning）、flutter test 全绿、build apk --debug 成功。
- **Acceptance Criteria Addressed**: AC-12, AC-14
- **Test Requirements**:
  - `rule` TR-13.1: 三命令输出达标；APK 路径存在。证据：命令输出。
  - `rubric` TR-13.2: 与既有架构一致性；1-5；锚点见 AC-14；阈值 ≥4；证据：Review 走查。

## Task 14: live 服务 + 真机 + 管理台 E2E 自测
- **Status**: `pending`
- **Priority**: high
- **Depends On**: Task 7, Task 11, Task 12, Task 13
- **Description**:
  - 用 venv 在 0.0.0.0:8000 启动 uvicorn；`adb reverse tcp:8000 tcp:8000`。
  - curl/脚本：管理员发布 1 条独有播客（如「E2E 独家英语频道」）、上传一个发布包 0.4.1（复制构建 APK 改名）。
  - 真机：发现页搜索到独有内容；注册新账号→订阅→服务端校验→清应用数据重登仍见订阅；检查更新弹窗→下载完成→校验设备 APK sha256→安装器唤起截图后取消；关服务验证离线回退。
  - 浏览器自动化：/admin 登录并完成内容发布与发布包上传，截图。
  - 证据存 `.tools/app-shots/` 与任务完成记录。
- **Acceptance Criteria Addressed**: AC-8, AC-9, AC-10, AC-7, AC-15
- **Test Requirements**:
  - `rule` TR-14.1: 上述每步有截图/命令输出佐证；sha256 一致；服务端订阅数为 1。证据：截图与输出清单。
  - `rubric` TR-14.2: E2E 完整度 1-5，锚点见 AC-15，阈值 ≥4。

## Task 15: 独立 Review、修复与文档
- **Status**: `pending`
- **Priority**: medium
- **Depends On**: Task 14
- **Description**:
  - 全新上下文独立 Review（只读）产出 review.md；actionable 发现回炉修复并复测。
  - 文档：README.md（v0.4：服务端启动、管理台、App 联网/OTA、测试数）、`docs/OORA复刻-软件设计方案.md`（版本头 v1.4、版本记录、F1/F6/OTA 章节）、server/README.md（Task 7 已建则校对）。
- **Acceptance Criteria Addressed**: AC-14, AC-15
- **Test Requirements**:
  - `rule` TR-15.1: Review 结果 pass；文档命令与实际一致（按文档命令复核一次）。证据：review.md。
