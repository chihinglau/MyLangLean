# OORA 复刻版（MyLangLean）软件设计方案

> 版本：v1.5 ｜ 日期：2026-10-01（v1.5 在线底座真机全链路闭环：d1-d7 全自动 E2E + KvStore 并发写竞态/会话事件时序两缺陷修复，版本 0.4.1+5；v1.4 PC 在线底座：账户/订阅云同步/发现页联网/OTA 与评审修复闭环；v1.3 2026-09-29；v1.2 2026-09-29；v1.1 2026-09-28；v1.0 初稿 2026-09-27）
> 目标平台：HarmonyOS 4.2.0（设计目标）｜ 现阶段可运行平台：**同机 AOSP 12 兼容层（Android arm64 APK，已真机验收）**
> 预留移植：iOS 13+
> 参考产品：https://oora.yoshinn.com.cn/#product
> 本项目仅用于技术学习，不使用 OORA 的名称、图标与素材。

## 版本记录

| 版本 | 日期 | 主要变更 |
|---|---|---|
| v1.0 | 2026-09-27 | 产品拆解、技术选型、PAL 架构、服务端 API、鸿蒙适配、里程碑 |
| v1.1 | 2026-09-28 | 按实际落地更新：双 Flutter 工具链、Android PAL 三件套、本地媒体库持久化、**字幕工坊**（PC 侧逐词字幕生产工具）、HarmonyOS 消费机 HAP 安装阻断的实测结论、**第 14 章真机联调环境与调试方法**、8 条验收标准全部 PASS 的证据链 |
| v1.2 | 2026-09-29 | **字幕工坊一键机翻**（translator.py：免 key MyMemory 主通道 + Google/LibreTranslate 降级，断点续译不覆盖人工译文；GUI 目标语言/进度/重译，CLI `-t/--translate-to/--retranslate`）；**App 三态补全**：双语模式无译文横幅与逐句缺译占位、盲听升级为「显示当前句/看译文/单句循环」训练卡；pytest 15 项、flutter test 18 项全绿，HBN-AL00 真机三态截图验收；**工坊可 PyInstaller 打包为免安装单文件 SubtitleStudio.exe（约 93MB，--selfcheck + GUI 截图双重自测通过）** |
| v1.3 | 2026-09-29 | **识别无时长上限 + 歌曲/强背景音乐兜底**：实测发现 Silero VAD 会把伴奏中的演唱判为非人声（3:53 FLAC 只出 8 句、止于约 49s）；改为「VAD 首遍 → 覆盖率<60% 自动无 VAD 全音频重识别（带多语种通用音乐风格提示找回前奏演唱）→ 按词间停顿把长段整理成歌词行」；schema 入库修复零时长词时间戳；frozen_entry 增加隐藏 `--transcribe` 无界面批处理参数（冻结产物可端到端自测）。证据：歌曲 small 档 52 句覆盖 233.4s + 翻译 52/52（新 exe 直跑 EXIT=0/validate OK）、10 分 16 秒口播 134 句无截断（走单次 VAD 无额外开销）、pytest 18 项全绿 |
| v1.4 | 2026-10-01 | **PC 服务端成为 App 在线底座**：① 邮箱注册/登录/JWT 游客与管理员用户管理（禁用/重置密码/订阅查看）；② 播客/单集发布与上下架（公开目录与用户订阅默认仅见已上架，新增 `GET /admin/podcasts`）；③ 发现页在线优先 + content_version 快照信封、离线回退；④ 订阅云同步采用**待同步操作队列**（`subscriptions.pending`：离线 PUT/DELETE 重放、退订防并集复活、404 目标本地丢弃）；⑤ APK 发布/OTA：字段白名单（platform/channel/version/buildNo，非法 422）、落盘随机名防穿越、Range 206、App 侧会话隔离 + `.part` 断点续传 + SHA-256 校验 + 强制更新不可取消；⑥ 评审 24 项问题闭环（S1 路径穿越、I1 版本容错、I2 删除补偿、I3/I7 下载竞态/续传、I4 强制更新、I5 中文化、I6 XSS、I8 403 降级提示等）。新增 env：`MLL_CORS_ORIGINS`（连同 `MLL_DATA_DIR`/`MLL_ADMIN_TOKEN` 等见 server/README.md）。证据：服务端 7/7、App 83 项全绿、0 error/0 warning、live E2E 34/34、管理台浏览器上下架实测、OTA release id=4（0.4.1+5）206/sha256 一致 |
| v1.5 | 2026-10-01 | **真机全链路零干预闭环（HBN-AL00，d1-d7 全 PASS）**：覆盖安装/冷启独家内容、pm clear 游客态、注册登录订阅、禁用 403 冷启降级 SnackBar、断网退订 pending 队列与重连 DELETE 收敛防复活、OTA 0.4.1+5（对话框→152MB 下载→设备端 sha256 逐位一致→系统安装器唤起→安装后再查无更新）、pm clear 重登订阅云端恢复。真机环节新发现并修复两缺陷：**R1 KvStore 启动期并发写竞态**（固定 tmp + 无串行化导致 rename 乱序、403 降级中断 → 单调序号串行写链 `prefs.json.tmp.<seq>`，新增 2 条并发用例）；**R2 会话事件时序**（notice 早于首帧被错过、我的页不响应会话变化 → broadcast `notices`/`accountChanges` 流 + 幂等 `sessionReady` 兜底 + `accountRefreshProvider`）。版本双写点（constants.dart/pubspec）统一 0.4.1+5，OTA release **id=6**；App 测试 82/82、0 error/0 warning。沉淀 adb reverse / run-as / 华为安装器（未知来源 appops + 锁屏 PIN）/UI 自动化键盘坐标等真机经验（§14.11） |

---

## 1. 产品分析与功能拆解

### 1.1 产品定位
把「全网播客 / 本地音视频」转化为带逐词字幕、翻译、循环变速、影子跟读评分的私人外语课。
核心学习闭环：**听懂 → 模仿 → 说出**。

### 1.2 功能范围（对标 OORA）与当前状态

| 编号 | 模块 | 功能点 | MVP | 二期 | 2026-09-28 状态 |
|---|---|---|---|---|---|
| F1 | 发现内容 | 精选播客、RSS 搜索/订阅、iTunes/PodcastIndex 检索、语言/主题/难度筛选 | ✅ | | UI + Mock 目录完成；服务端代理已备 |
| F2 | 内容管理 | 本地音视频导入、播客单集下载、收藏、个人资料库 | ✅ | | **Android SAF 导入 + JSON 持久化已真机验收**；OH picker 协议预留 |
| F3 | 逐词字幕 | ASR 自动转录、逐词时间轴、播放同步卡拉OK高亮、点词定位、单句循环 | ✅ | | **App 播放高亮 + PC 字幕工坊生产链路全部真机验收** |
| F4 | 翻译理解 | 多语种互译、原文/译文对照、字幕样式（字号/显隐/盲听）、点词查词 | ✅ | | 双语切换/盲听/字号完成；**译文由字幕工坊一键机翻或人工填入口写入字幕文件（v1.2）**；无译文时双语模式显式横幅/占位提示，盲听可按需揭示当前句与译文 |
| F5 | 影子跟读 | AB 循环、0.6–1.5× 变速、录音、原声/录音波形对比、发音评分 | ✅(启发式评分) | 音素级 GOP | UI + 录音 + V1 评分（shadow_scorer）完成 |
| F6 | 账户额度 | 游客设备ID免登（字幕试看 5 分钟）、登录注册、每月 100 分钟转录额度 | ✅ | 订阅 | **v1.4 起 App 已接真实服务端**：注册/登录/JWT、游客降级、月度额度、禁用 403 提示、管理员禁用/重置密码；v1.5 真机验收 |
| F7 | 履历作品 | 练习历史、录音作品管理、成长曲线 | ✅ | 一键成片/分享 | 履历页 + 本地记录完成 |
| F8 | 播放能力 | 后台播放、锁屏控制（AVSession）、播放队列、离线播放、进度记忆 | ✅ | 跨设备同步 | Android：WAKE_LOCK 离线播放/变速/AB 完成；OH AVSession 代码已写待 NEXT 真机 |

### 1.3 关键用户流程
```
PC：音视频文件 ──字幕工坊(faster-whisper 逐词识别+人工校对)──▶ 同名 .mll.json
                                                                │
手机：发现/导入 ──SAF 选媒体──▶ 询问配对字幕──▶ 复制进应用沙箱 + library_index.json
           └──▶ 播放器(逐词高亮+翻译/盲听) ──单句循环/变速精听──▶ 录音跟读 ──▶ 评分 ──▶ 履历
```

---

## 2. 开源参考与合规

| 项目 | 地址 | 可复用内容 | 许可证 |
|---|---|---|---|
| lingopod | github.com/linshenkx/lingopod | Flutter+FastAPI 双语播客架构思路 | 以仓库为准 |
| anytime_podcast_player | github.com/amugofjava/anytime_podcast_player | RSS 订阅、播客播放组织方式 | BSD-3-Clause（保留版权声明） |
| tsacdop | github.com/tsacdop/tsacdop | 播客播放/下载结构 | BSD-3 |
| AntennaPod | github.com/AntennaPod/AntennaPod | RSS 边界 case、播放队列思路（仅学习，不拷代码） | GPL |
| faster-whisper | github.com/SYSTRAN/faster-whisper | 服务端/PC 端转写 word_timestamps（字幕工坊实测 small 档 WER 0%） | MIT |
| sherpa-onnx | github.com/k2-fsa/sherpa-onnx | 端侧离线 ASR（官方支持 OpenHarmony） | Apache-2.0 |
| PyAV | github.com/PyAV-Org/PyAV | 字幕工坊音视频解码、测试视频合成 | BSD-3 |
| Flutter-OH | gitee.com/openharmony-sig/flutter_flutter | 鸿蒙版 Flutter 引擎（本机用 3.22.0-ohos fork） | BSD-3 |
| flutter_packages | atomgit.com/openharmony-tpc/flutter_packages | 已完成鸿蒙适配的插件清单 | 各包 LICENSE |

合规：项目命名 MyLangLean；不使用 OORA 品牌素材；播客版权归原作者，仅做个人学习收听与缓存；发布前审查依赖 LICENSE。

---

## 3. 技术选型（按落地实测更新）

| 层 | 选型 | 理由 / 实测 |
|---|---|---|
| 客户端框架 | **一套 Dart 业务代码 + 两套 Flutter SDK** | 官方 Flutter stable（`.tools/flutter`，实际 3.47 段，Dart 3.13 工具链）出 **Android APK**；OH fork 3.22.0（Dart 3.4）出 HAP。pubspec 约束 `sdk: ">=3.4.0 <4.0.0"`、`flutter: ">=3.22.0"` 保证双端可编译 |
| 状态管理 | Riverpod 2 | 可测试、易隔离平台差异 |
| 路由 | go_router 14 | 声明式、深链接 |
| 网络 | dio 5 + webfeed 0.7（intl 0.17） | 纯 Dart，双平台无桥接风险 |
| 本地存储 | **KvStore（`filesDir/prefs.json` 原子 KV，v1.5 串行写链）** + JSON 文件索引（`filesDir/library_index.json`） | 零原生依赖；坏索引 `.corrupt-时间戳` 隔离；KvStore 多写单调序号串行 flush+rename（§6.4）；二期可换 Drift |
| Android 音频 | 自研 MediaPlayer 插件（PAL，channel `ml/audio_player`） | 33ms tick、AB 循环、PlaybackParams 0.6–1.5× 变速、prepare 竞态消除 |
| Android 选择器 | 自研 SAF 插件（`ml/media_picker`） | ACTION_OPEN_DOCUMENT，后台线程复制进沙箱，同名自动 `_1` |
| Android 录音 | 自研 MediaRecorder 插件（`ml/audio_recorder`） | AAC/m4a，存 filesDir/recordings |
| OH 音频/录音/选择器 | ArkTS AVPlayer/AVRecorder/AudioViewPicker 插件（`app/ohos/.../plugins/`） | 源码与协议已就绪，待 HarmonyOS NEXT 设备安装运行 |
| PC 字幕生产 | Python 3.10+ / faster-whisper / PyAV / tkinter | Windows 本地「字幕工坊」，模型缓存在工作区可离线 |
| 服务端 | FastAPI + RQ 规划 + PostgreSQL/Redis + FFmpeg | 仓库内为 stub ASR 可跑通全链路；生产切 faster_whisper |
| 翻译 | 可插拔 Provider（v1.2 已落地：免 key MyMemory→Google gtx→LibreTranslate 降级链；后续可接大模型/DeepL/有道） | ✅ 工坊 GUI+CLI |
| 评分 | V1 时长/停顿/能量启发式（`shadow_scorer.dart`）；V2 wav2vec2 GOP | 先可用后精准 |

### 3.1 双平台构建现实（重要，2026-09-28 实测）

- 工作机上**只有 OH fork 的 flutter 会在任何命令（含 `build apk`）启动时执行 hvigor 插件安装钩子**；本机无 node/npm/ohpm 时直接 tool crash。因此 **Android 出包必须用标准版 `.tools\flutter`**；OH 代码分析用 fork 的 `dart analyze`（不触发钩子）。
- 同一套 Dart 代码在 3.22 与 3.47 两版下零差异编译：已规避 `CardTheme` 构造变更（改用两版都支持的 `cardColor`），保留 withOpacity/Radio 等废弃 info 不修。
- 目标消费机 **HBN-AL00（HarmonyOS 4.2）无法安装 Stage 模型 HAP**（详见第 13 章），但其 AOSP 12 兼容层可正常安装调试 APK，**MVP 真机闭环在 Android 兼容层完成**；HarmonyOS NEXT(5.0+) 设备/云真机是 HAP 路线的下一验收点。

### 3.2 iOS 移植策略（编码时即落实）
1. 业务/UI/数据逻辑 100% 纯 Dart，禁止在业务代码直接调用平台插件；
2. 平台能力全部收口到 **PAL（Platform Abstraction Layer）** 接口；
3. 实现并存：`pal/ohos/`（MethodChannel→ArkTS）、`pal/android/`（MethodChannel→Kotlin）、`pal/mock/`（Windows 桌面虚拟时钟）、未来 `pal/ios/`；
4. 平台判断收口在 `pal/platform_info.dart`，业务层不直接引用平台枚举。

---

## 4. 客户端架构

```
┌──────────────────────────────────────────────┐
│ UI 层  pages/widgets/theme（go_router）        │
│  discover / library / player / shadowing /    │
│  history / auth；widgets/karaoke_subtitle     │
├──────────────────────────────────────────────┤
│ Feature 层  player_controller 等用例编排        │
├──────────────────────────────────────────────┤
│ Domain 层  Episode/Transcript/Recording/...    │
│            repositories 抽象                   │
├──────────────────────────────────────────────┤
│ Data 层  remote/ml_api（dio：auth/catalog/sub/quota/releases）
│          kv_store（原子串行 KV）＋ mock_catalog / mock_repositories
│          persistent_* / synced_*（auth、library：乐观更新+待同步队列）
│          fallback_catalog_repository（服务端→快照信封→Mock 三级）
├──────────────────────────────────────────────┤
│ PAL 层  audio_player / recorder / picker       │
│  ohos(ArkTS) · android(Kotlin) · mock(桌面)    │
└──────────────────────────────────────────────┘
```

工程目录（实际）：
```
MyLangLean/
├─ app/                    Flutter 客户端（同一套 lib/ 出 HAP/APK，桌面走 mock）
│  ├─ lib/core/            主题、路由、常量、home_shell（账号/通知流接线）
│  ├─ lib/domain/          entities（podcast/episode/transcript/recording/quota/user_preferences）
│  ├─ lib/data/            kv_store 原子 KV；remote/ml_api；mock + persistent_* + synced_* 仓库；
│  │                       fallback_catalog（三级回退）；practice_store
│  ├─ lib/pal/             ★平台抽象 + android/ohos/mock 三实现 + providers（含 updater_service）
│  ├─ lib/features/        discover/library/player(+widgets)/shadowing/history/auth/update
│  ├─ android/             Gradle 工程 + Kotlin 插件（出 APK；含 MlUpdater/MlUpdateFileProvider）
│  ├─ ohos/                hvigor 工程 + ArkTS 插件（出 HAP，生成物不入库）
│  ├─ assets/{data,audio}/ 内置示例字幕与音频
│  └─ test/                单元/Widget 测试（v1.5 共 82 项）+ fixtures/
├─ tools/subtitle-studio/  ★PC 字幕工坊（mll_subtitles 包 + GUI + 测试）
├─ ohos_supplement/        flutter create ohos 后要合入的 ArkTS 插件/权限说明
├─ server/                 FastAPI 服务端（auth/quota/transcriptions/translate/score/discover）
├─ scripts/                环境搭建、SDK 切换、示例素材与测试视频制备
├─ docs/                   本设计方案
└─ .trae/specs/            字幕工坊需求 spec/任务/评审记录（8 AC 验收证据索引）
```

### 4.1 PAL 关键接口

```dart
abstract interface class AudioPlayerService {
  Stream<int>      get positionMs;   // 实现侧持续回推（mock 为虚拟时钟）
  Stream<String>   get stateStream;  // playing / paused / completed / error:...
  Stream<int>      get durationMs;
  Future<void> load(String src, {required bool isLocal});
  Future<void> play();
  Future<void> pause();
  Future<void> seek(int ms);
  Future<void> setRate(double rate);
  Future<void> setLoop({required int aMs, required int bMs}); // AB 循环
  Future<void> dispose();
}

abstract interface class MediaPickerService {
  Future<String?> filesDir();
  Future<PickedFile?> pickAudio();
  Future<PickedFile?> pickFile({required List<String> allowedExts}); // .mll.json
}
```

### 4.2 Android 播放插件关键设计（[MlAudioPlayerPlugin.kt](../app/android/app/src/main/kotlin/com/mylanglean/app/MlAudioPlayerPlugin.kt)）

首轮真机暴露并修复的播放内核问题（均有评审记录）：

| 点 | 设计 |
|---|---|
| ticker 断链 | 单一 Runnable **每次运行末尾无条件 `postDelayed`**，player 为 null/未 prepared 也续期；杜绝「首帧空转后回调永久死亡」 |
| prepare 竞态 | `playWhenPrepared`：prepared 前的 play 在 `onPrepared` 中补 start，快速 load+play 不再静默 |
| prepared 前 seek | `pendingSeek` 缓存，onPrepared 中补发 seekTo + onPosition（I4） |
| 状态回推 | onState 播放 `playing` / 暂停 `paused` / 完成 `completed` / 错误 `error: MediaPlayer what=.. extra=.. source=..` |
| 跨节目隔离 | load/release 都复位 loopA/loopB/pendingSeek/playWhenPrepared（I1） |
| 错误兜底 | Dart 侧 `mediaError` 中文空态「媒体无法播放」，不无限转圈（I2） |
| 资源 | `setWakeMode(PARTIAL_WAKE_LOCK)`；asset:// 经 `AssetFileDescriptor`+offset 读 noCompress mp3 |

### 4.3 逐词字幕引擎（核心难点，已真机验证）

- 统一 JSON schema（§8），App 侧 `Transcript.fromJson` 解析，扁平词索引 + **二分查找** `wordAt(positionMs)`；
- `KaraokeSubtitle` 用 `TextSpan` 仅重绘当前词（橙色）与当前句（边框/背景），随 33ms 位置流刷新；
- 当前句自动居中；点词 seek、点句切单句循环；字幕/双语/盲听三态；字号 5 档；
- 无字幕/坏字幕：`transcriptError` → 中文空态并引导「用字幕工坊生成后导入或关联」，**不阻塞音频播放**；
- 本地 sidecar：`LocalAwareTranscriptRepository` 优先读 `episode.transcriptPath` 文件，异常给中文上下文；无 sidecar 回退 asset 内置。

### 4.4 跟读评分（V1）
AB + 变速由原生播放器保证计时；录音（AAC/m4a）与原声对齐后，`shadow_scorer.dart` 计算时长偏差/停顿/能量/语速 → 0–100 与建议；V2 规划服务端音素强制对齐 GOP。

---

## 5. 本地媒体库与导入配对（App 侧新增核心模块）

```
SAF 选媒体(uri) ──后台线程复制──▶ filesDir/imports/<name>（同名 _1）
                                      │
弹框「是否配对字幕？」──选择字幕──▶ SAF 选 .mll.json ──复制──▶ imports/<name>.mll.json
        └─暂不──────────────────────────────┘ transcriptPath=null
                                      │
                    LocalLibraryStore 写 library_index.json
                    {id,title,mediaPath,transcriptPath,durationMs,language,importedAt}
                                      │
                    PersistentLibraryRepository.addLocalMedia(...)
```

- 索引文件：`<filesDir>/library_index.json`；加载失败备份为 `.corrupt-<ts>` 后空库启动，不崩 App；
- 条目菜单：**关联/替换字幕**（事后补配，toast「字幕已关联」）、**删除**（确认框明示媒体与字幕一并删除，best-effort 清文件）；
- 列表行徽标：本地文件/视频音轨 × cc 已配对字幕/无字幕；
- main.dart Android 启动时异步注入 filesDir 后再渲染资料库；
- 视频容器：不做画面渲染，**只走 MediaPlayer 音轨**，字幕体验与音频一致（AC-6）。

---

## 6. 服务端 API（FastAPI；v1.4 起为 App 在线底座）

### 6.1 业务接口（前缀 `/api/v1`，Bearer JWT）

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | /auth/device | 游客设备 JWT（device_id 白名单 `^[A-Za-z0-9._:\-]{1,128}$`） |
| POST | /auth/register | 邮箱注册即发 JWT（密码 ≥6，重复邮箱 409 中文） |
| POST | /auth/login | 登录（错密 401、禁用 403，中文 detail） |
| GET | /me | 当前账号资料 |
| GET | /quota | 当月已用/总额（秒） |
| GET | /catalog/meta · /catalog/podcasts · /catalog/podcasts/{id} · .../episodes | 在线目录，仅已上架；响应带 content_version，LIKE 搜索转义 `\%_` |
| GET/PUT/DELETE | /me/subscriptions[/{id}] | 订阅列表（下架项不可见）/幂等订阅（目标 404）/幂等退订 204 |
| POST | /transcriptions | 上传/URL 创建转写任务 | 按秒扣 |
| GET | /transcriptions/{id} | 轮询状态/结果 |
| POST | /translate | 批量翻译（带缓存） |
| POST | /score | 评分 |
| GET | /discover/proxy | PodcastIndex 代理（隐藏密钥，未配凭据 503） |
| GET | /releases/latest | OTA 检查：platform∈{android,ohos}、channel∈{stable,beta,alpha}、current 可解析，非法 422；脏版本行绝不 500 |
| GET | /releases · /releases/download/{id} | 发布历史；APK 文件流支持 Range 206 |

### 6.2 管理接口（`X-Admin-Token`，单文件零依赖管理台 `/admin`）

用户列表/禁用启用/改名（≤64）/重置密码/查看订阅（含已下架）；播客与单集增删改、
`GET /admin/podcasts`（含已下架，上下架按钮数据源）、一键 reseed；APK multipart 发布
（扩展名 `.apk` 400 + 字段白名单 422 双校验；落盘名 `{platform}-{version}-{buildNo}-{uuid8}.apk`，
1MB 分块流式写盘并增量计算 SHA-256；删除发布连带清理磁盘文件）。

### 6.3 App 侧同步与 OTA 关键设计（v1.4）

- **订阅一致性**：本地乐观更新即时响应 UI；每次 toggle 写入 KV 操作队列
  `subscriptions.pending`（`{id,sub,t}`，同 id last-write-wins）。`syncSubscriptions`
  顺序：重放队列（PUT/DELETE；订阅 404 记为 gone 本地丢弃）→ 拉取服务端 → local-only
  回推 → 合并时排除“待删除”id，**离线退订不会被并集同步装回**；传输失败保留队列下次再收敛。
- **发现页三级回退**：服务端 → `{ts,content_version,items}` 本地快照（兼容旧裸列表）→ 内置 MockCatalog。
- **OTA 下载器（Kotlin，零三方依赖）**：单调会话 token，启动先中断 join 旧 worker；
  `.part` 按 release id 隔离，`Range: bytes=<len>-` 续传（206 校验 Content-Range，200 截断重下）；
  完成后整文件 SHA-256 与发布记录比对通过才 rename；强制更新 PopScope 禁返回、下载中无取消、
  失败仅可重试；安装走自写非导出 FileProvider 调起系统包安装器，O+ 先引导未知来源权限。
- **配置**：`MLL_DATA_DIR` / `MLL_ADMIN_TOKEN` / `MLL_JWT_SECRET` / `MLL_CORS_ORIGINS`
  （逗号分隔，默认 `*`）/ `MLL_MONTHLY_QUOTA_SEC` / `MLL_GUEST_PREVIEW_SEC` / `MLL_ASR_BACKEND`，
  完整契约见 [server/README.md](file:///d:/ai/prj/trae/HuaWei/MyLangLean/server/README.md)。

`server/` 测试：`tests/run_all.py` 一键 7 模块（test_auth/admin/catalog/subscriptions/
releases/db_seed + smoke，v1.4 起全绿）；另含 live E2E 脚本 `.tools_e2e_live.py`（每次新建
账号，注册→订阅→独家发布→上下架→禁用→OTA 共 34 项）与管理辅助脚本 `.tools_check_dev.py
<email> [show|disable|enable]`（admin token 查/禁用/启用测试账号并核对订阅数）。默认
`MLL_ASR_BACKEND=stub` 无 GPU 可跑通，生产切 `faster_whisper`（Dockerfile/compose 已备）。

### 6.4 App 在线数据层与会话可靠性（v1.5 真机修复定稿）

真机 403 降级实测暴露两个启动期可靠性缺陷，修复后定稿如下：

**① KvStore：单调序号串行写链（[kv_store.dart](../app/lib/data/kv_store.dart)）**

- 旧实现所有写共用固定 `prefs.json.tmp` 且无串行化；冷启动 ensureSession 扇出
  （set notice → remove token → 多次 persist）与其它启动写并发时，tmp 写/rename 乱序
  抛异常，连锁导致 `_clearToken` 中断、游客登录未执行（禁用账号冷启仍残留用户态）。
- 新实现：`set/remove/clear` 同步生成内存快照字符串并调 `_scheduleWrite()`；每次写分配
  单调 `_writeSeq`，落唯一临时文件 `prefs.json.tmp.<seq>`，通过 `_writeChain`（Future 链）
  **严格串行** await 写盘（`flush: true`）→ `rename` 覆盖正式文件；独立 Completer 收敛结果，
  失败删除该次 tmp 并 completeError，绝不波及后续写。
- 守护测试（`test/kv_store_test.dart`，2 项）：200 键并发写不丢值；remove 后立即 set 的
  最终顺序正确、被删键不被陈旧写复活；无 tmp 文件残留。

**② 会话状态机：幂等会话 + 广播事件（[synced_auth_repository.dart](../app/lib/data/repositories/synced_auth_repository.dart)）**

- `ensureSession()` 幂等化：`return _sessionReady ??= _ensureSession()`，启动期多处调用
  只执行一次会话检查，对外暴露 `Future<Account>? get sessionReady`。
- 两个 broadcast 流：`Stream<Account> get accountChanges`（登录/注册/游客登录/登出/
  401-403 降级统一发事件）、`Stream<String> get notices`（一次性账号通知，如禁用提示）。
- 401/403 分支：notice 落 KV（fire-and-forget，失败不阻断）+ `notices` 流即时广播 →
  `_downgradeToGuest()`：先切内存游客态并清空 dio token → best-effort remove 持久 token
  （失败不阻断）→ 游客设备登录 → 由 `_guestLogin()` 统一发 accountChanges（登出与降级
  路径不再重复发事件）。
- UI 接线（[home_shell.dart](../app/lib/core/home_shell.dart)）：首帧后订阅 `notices`
  弹 SnackBar、订阅 `accountChanges` 自增 `accountRefreshProvider`；同时
  `sessionReady.then(...)` 兜底——冷启动 403 场景下流事件可能早于页面挂载，future 完成后
  再 `consumeNotice()` 消费 KV 里的一次性通知，双保险不漏提示。我的页 `ref.watch`
  刷新版本号 provider，会话变化即从用户态重建为游客态（不再用只读 `read`）。

**③ 版本号单一事实**：App 版本存在两处显式常量（`Env.appVersion/appBuildNumber` 与
pubspec `version:`），发版必须同步；v1.5 起均为 **0.4.1+5**，OTA 自报版本与安装包一致，
`/releases/latest?current=0.4.1+5` 返回 `has_update:false`。

---

## 7. 鸿蒙 4.2 适配与消费机实测结论

### 7.1 已完成的适配代码（待 NEXT 设备运行）
- module.json5：INTERNET、MICROPHONE(user_grant)、KEEP_BACKGROUND_RUNNING(backgroundModes: audioPlayback)；
- ArkTS 三件套（`app/ohos/entry/src/main/ets/plugins/`，与 ohos_supplement 镜像）：
  AVPlayer+AVSession 播放、AVRecorder 录音、AudioViewPicker 选择；
- 自签名链路全部跑通（材料在本机 `.tools/signing/`，不入库）：三级 CA → ECDSA profile p7b → sign-app，verify-app 通过。

### 7.2 HBN-AL00 实测阻断（2026-09-28，详细证据在项目记忆与评审报告）
- 该机为 **HarmonyOS 4.2 消费机**：仅暴露 ADB（无 hdc/hdcd）；系统容器应用全是 **FA 模型 config.json（compatible API 5/target 6）**；
- Stage 模型 HAP（API12/ark12）安装必报 `code 35 MSG_ERR_INSTALL_CHECK_SYSCAP_FAILED`（logcat 见 BundleManagerGateway "install hap to open harmony container"）；
- 已排除签名与清单因素：改 compatible/target/minAPIVersion(6/9/10)、virtualMachine(ark9/10)、compileSdkType、deviceTypes 均无效；FA 改造包能过 syscap 但卡在系统 apk 内嵌签名——**检查点是模型代际**；
- 出路：① HarmonyOS NEXT(5.0+) 真机（hdc 完整）；② DevEco 云真机/远程模拟器；③ 本地模拟器（需 GUI 下载 API12 镜像）。

---

## 8. 逐词字幕 JSON（三端统一 schema，定版）

字幕工坊与 App 共用，字段不变更：

```json
{
  "version": 1,
  "language": "en",
  "duration": 18.24,
  "segments": [
    { "id": 0, "start": 0.0, "end": 2.1,
      "text": "Real voices make language feel alive.",
      "translation": "真实的声音，让语言有了生命力。",
      "words": [
        {"w": "Real",   "s": 0.0,  "e": 0.32, "p": 0.97},
        {"w": "voices", "s": 0.33, "e": 0.78, "p": 0.95}
      ]}
  ]
}
```

校验规则（工坊 `schema.validate()`，App 导入配对时也预校验）：非空；词 0≤s<e；词时间全局单调；句时间单调；**相邻句首词 s ≥ 上句末词 e（EPS 0.02，防拆句重复词破坏二分高亮）**；segment id 必须 0..n-1 连续；duration ≥ 末词 e。

---

## 9. 字幕工坊（PC 侧生产工具，本期新增）

位置：`tools/subtitle-studio/`（包 `mll_subtitles`：schema / transcriber / translator / cli / studio），启动器 `启动字幕工坊.bat`。

| 模块 | 内容 |
|---|---|
| transcriber.py | faster-whisper 封装（tiny/small 档、int8/float32 精度、语言可指定、PyAV 直接解音视频）；启动时把 HF_HOME 指向工作区 `.tools/hf-cache`（import faster_whisper **之前**设置）。**（v1.3）无时长上限**：`clip_timestamps="0"` 始终处理整段，`condition_on_previous_text=False` 防长音频重复循环；**VAD 覆盖率兜底**：VAD 首遍后末句覆盖不足 60%（文件≥20s，典型于歌曲被误判非人声）自动无 VAD 全音频重识别、钉住已检测语言并加 `_MUSIC_PROMPTS`（8 语种通用音乐风格提示，不含真实歌词防注入），两版取覆盖更长者，无 VAD 结果再过 `split_by_word_gaps` |
| translator.py | **（v1.2 新增）** 免 key 机器翻译：可插拔 provider 链（默认 `mymemory,google`，均标准库 urllib；另支持自建 LibreTranslate），每通道 2 次重试+自动降级、句间 0.4s 节流；**默认跳过已有非空译文（断点续译、人工译文不被覆盖）**，`force=True` 才重译；源语言=目标语言直接拒绝；env 可配 `MLL_TRANSLATE_PROVIDER` / `MLL_TRANSLATOR_EMAIL`（MyMemory 提额）/ `MLL_LIBRETRANSLATE_URL` |
| schema.py | Segment/Word/Transcript dataclass、from_whisper 映射、validate、save_json（indent=2, ensure_ascii=False，与 App 同格式）；`translation` 字段 v1 即存在，机翻直接写入无需改 schema 版本。**（v1.3）**`from_whisper` 入库时 `_repair_word_times` 把无 VAD 歌声路径偶发的 start==end 零时长词在 ±20ms 内修复（不跨邻词/跨句）；`split_by_word_gaps` 在词间停顿 ≥0.9s（或跨 12s 长句遇 ≥0.35s 停顿）处把大段切成歌词行，紧凑口播不受影响 |
| studio.py | tkinter GUI：打开媒体/模型档/语言/识别；按句 Treeview 词表（词/起止/置信度行内编辑、±0.05s 微调），**「译文」列以 ✓ 标识已译句**；句译文、加词/删词/拆句/合并；后台线程识别+队列刷新；实时校验；**控制条增「译成」目标语言（zh-CN/en/ja/ko/fr/de/es/ru）+「一键翻译」（仅补缺译句）+「全部重译」，后台线程翻译、日志区进度、失败句保留成功部分并可续跑**；导出默认媒体同目录同名 `.mll.json` |
| cli.py | 命令行批处理（含 --compute-type）；**v1.2 起输入可以是已有 `.mll.json`（只翻译模式，输出默认 `*.zh-CN.mll.json`）；`-t/--translate-to`、`--retranslate`、`--provider`；部分失败退出码 3 但已保存成功部分** |
| eval_quality.py | 质量评估：WER + 词边界误差（mean/p90/0.5s 命中率） |
| tests/ | test_schema.py（**10 项**：原 7 项 + v1.3 零时长词修复、词间隙拆句、紧凑语音不拆）、**test_translator.py（8 项：语言码归一、gtx 响应解析、MyMemory 解析/额度、降级链、重试、跳过/覆盖/失败保留/同语拒绝，全程假 provider 无网络）**、gui_smoke.py（真实事件驱动：改词/微调/译文/拆并句/导出 + **一键翻译三轮回归：补译保留人工译文、只补缺句、强制重译**，含 B1/B2 断言） |
| frozen_entry.py / requirements-build.txt | **（v1.2 追加）PyInstaller 打包入口与构建依赖**：入口先走 GUI `main()`；带 `--selfcheck` 无窗口模式导入 tkinter/PyAV/ctranslate2/faster_whisper 并写 `studio-selfcheck.log`，构建机自动验收冻结包；**（v1.3）`--transcribe <媒体> --out <json> [--model small] [--lang en]` 隐藏无界面批处理**（windowed 包 stdout 可能为空，日志镜像到 `<out>.log`，validate 失败退 4），可直接对冻结 exe 做端到端识别自测。`scripts/build-studio-exe.ps1` 一键出 onefile `SubtitleStudio.exe`（约 93MB，内嵌运行时，目标机免安装），`scripts/check-studio-exe-gui.ps1` 启动 GUI 截图举证。冻结态模型缓存：exe 同级 `hf-cache\`（便携，只读时退 `%LOCALAPPDATA%\MyLangLeanSubtitleStudio`），并显式固定 `HF_XET_CACHE/HF_XET_LOG_DIR` 防止 hf-xet 原生扩展往盘根乱建目录 |

环境：`.tools\venvs\mll\Scripts\python.exe`（faster-whisper 1.2.1 / av 17.1 / pytest），运行模块需 `PYTHONPATH` 指向 `tools/subtitle-studio`；**翻译功能零新增依赖（urllib 标准库）**。
模型：huggingface.co 与 hf-mirror 客户端在本机网络均不稳，用 `scripts/download-whisper-model.ps1`（Invoke-WebRequest 重试 + 手工落 hub 缓存），tiny/small 已就绪可离线。
翻译端点实测（2026-09-29，本机网络）：MyMemory 1.1s 可达且译文正确（默认主通道）；translate.googleapis.com gtx 超时（留作海外降级）；有道旧 web 端点/Edge auth 已 404 弃用。
实测质量：sample.mp3（17.6s 干净英文 TTS）small 档 **WER 0%，边界 p90 0.092s，43/43 词落在 0.5s 内，rubric 5/5**；其 4 句字幕经 MyMemory 真实翻译 4/4 成功（`.tools/studio-out/sample.zh.mll.json`），App 关联后双语/原文/盲听三态真机验收通过。

GUI 三个关键坑（已修，回归断言守护）：①Treeview `selection_set` **同步**触发 `<<TreeviewSelect>>`，重建树必须 `_suspend_commit` 守卫，否则旧行 commit 覆盖结构编辑；②拆句产生的重复词必须靠跨句重叠校验拦截，否则能导出并破坏 App wordAt 二分；③树重建后还会**异步**重发一次已选中行的选择事件，重复 commit 并把「翻译完成」状态条冲掉——`_on_select_segment` 对 `idx == current_seg` 的事件直接忽略。

### 9.1 App 三态与机翻消费（v1.2）

- 双语模式（`SubtitleMode.bilingual`）：句卡下方渲染 `seg.translation`。旧字幕全部无译文时不再静默退化成原文——顶部出现可关闭的中文横幅「当前字幕没有译文…可在电脑端字幕工坊一键翻译后重新关联」；仅部分句缺译时，缺译句原位显示浅色斜体占位「（暂无译文，可用字幕工坊补译后重新关联）」。
- 盲听模式（`hidden`）：从单行静态提示升级为训练卡——默认全隐；「显示当前句」揭示播放位置所在句并随播放自动换句（换句重新隐藏），卡内可「看译文/隐藏译文」（仅有译文时出现）、单句循环、「继续盲听」收起。
- 实体侧只增只读 getter：`TranscriptSegment.hasTranslation`、`Transcript.translatedCount/hasTranslations`；schema v1 不变。
- 证据：`app/test/subtitle_modes_test.dart` 5 个 widget/单元用例；HBN-AL00 真机连续截图 `.tools/studio-out/dev-s4/s8/s9/s10/s11/s12/s13`（横幅→双语对照→盲听→揭示→看译文→原文）。

### 9.2 无时长上限与歌曲/强背景音乐兜底（v1.3）

问题：用户用 exe 识别 3:53 的 FLAC 歌曲（Westlife《My Love》）只得到 8 句、内容止于约 49s，看似"时长被限制"。对照实验定位（tiny/small 双档）：代码从未设过时长上限——真因是 faster-whisper 的 Silero VAD 把母带伴奏中的演唱持续判为非人声，阈值从 0.5 降到 0.08 覆盖率仍只有 53%；关闭 VAD 后 42 句覆盖到 227s。此外 small 档在无 VAD 时会漏前奏上的首主歌（解码策略对照确认非 no_speech/hallucination 阈值所致），加入通用音乐风格 `initial_prompt` 后完整找回（"An empty street, an empty house…"）且无提示词串入。

策略（全部封装在 `transcribe_file`，GUI/CLI/exe 三端同路径）：

1. 首遍 VAD（口播/播客最优，单次成本）；日志始终显示总时长与"无时长上限"。
2. 文件 ≥20s 且末句覆盖 <60% → 日志告警并自动无 VAD 全音频重识别（钉住语言、加该语种通用音乐提示），两版取覆盖更长者。
3. 无 VAD 结果过 `split_by_word_gaps`：词间 ≥0.9s 停顿（长句 ≥12s 时 ≥0.35s 也切）整理成歌词行；紧凑口播零影响。
4. `_repair_word_times`：无 VAD 偶发零时长词（start==end）在 ±20ms 内修复且不跨邻词，保证 App 卡拉 OK 高亮不串行。

实测：该歌曲 small 档（**冻结 exe 直跑** `--transcribe`）52 句覆盖 233.4s、最长句 7.1s、validate OK、MyMemory 翻译 52/52（产物 `.tools/studio-out/mylove.exe.mll.json` 及 `.zh` 版）；10 分 16 秒循环口播 134 句覆盖 616.9s（VAD 单遍命中，无兜底开销）；sample.mp3 质量门仍 WER 0%/5/5；pytest 18/18、gui_smoke 通过。

---

## 10. UI/UX

- 五 Tab：发现 / 资料库 / 履历 / 我的（播放器全屏升起）；
- 深色优先；Material 3；字号 5 档并跟随系统；
- 360×640～折叠屏全适配（LayoutBuilder 断点 600/840dp）；
- 所有错误路径中文空态（无字幕、字幕损坏、媒体无法播放、无文件管理器）。

---

## 11. 开发环境（全部在 D 盘 / 工作区 .tools，零系统污染）

### 11.1 工具链布局（本工作机实测值）

| 软件 | 版本 | 位置 |
|---|---|---|
| 官方 Flutter（出 APK/analyze/test） | stable（工具 3.47 段） | `.tools/flutter` |
| Flutter-OH（出 HAP / dart analyze） | 3.22.0-ohos（Dart 3.4） | `.tools/flutter_ohos` |
| JDK（AGP/Gradle） | JDK 17.0.2 | `.tools/jdk17/jdk-17.0.2` |
| Android SDK | platforms 35/36、build-tools 35/36、platform-tools(adb) | `.tools/android-sdk` |
| DevEco Studio / OH SDK | 5.x / API 12 | `D:\HuaWei\DevEco-Studio`、`D:\HuaWei\Sdk` |
| Python venv（工坊+服务端） | 3.10/3.12 | `.tools/venvs/mll` |
| 模型缓存 | whisper tiny+small | `.tools/hf-cache`（可离线） |
| 缓存 | pub（官方/OH 分开）、gradle、pip、ohpm | `.tools/caches` |

Gradle 9.3.1 wrapper 走腾讯镜像；Maven 依赖在 settings/build.gradle.kts 配阿里云 google/central（**不要**用 GRADLE_USER_HOME/init.gradle 注入仓库，会触发 FAIL_ON_PROJECT_REPOS）。

### 11.2 会话级环境切换（不写系统变量）
- `. .\scripts\use-flutter-android.ps1`：官方 Flutter + JDK17 + Android SDK + adb 入 PATH（本会话）；
- `. .\scripts\use-flutter-ohos.ps1` / `use-flutter-official.ps1`：OH HAP / iOS 预留；
- OH 侧 analyze 需 PATH 带 DevEco 的 node/ohpm/hvigor，否则钩子找 npm 崩溃（与代码无关）。

---

## 12. 构建命令速查

```powershell
# ---- Android APK（用官方 Flutter，勿用 OH fork）----
$env:JAVA_HOME = "$PWD\.tools\jdk17\jdk-17.0.2"          # 或先 dot-source use-flutter-android.ps1
cd app
..\.tools\flutter\bin\flutter.bat pub get
..\.tools\flutter\bin\flutter.bat analyze                 # 0 error/0 warning（24 条既有 info 基线）
..\.tools\flutter\bin\flutter.bat test                    # 82/82（v1.5）
..\.tools\flutter\bin\flutter.bat build apk --debug  --target-platform android-arm64
..\.tools\flutter\bin\flutter.bat build apk --release --target-platform android-arm64
# 产物：app/build/app/outputs/flutter-apk/app-{debug,release}.apk

# ---- HarmonyOS HAP（需 node/ohpm/hvigor 在 PATH）----
..\.tools\flutter_ohos\bin\flutter.bat create --platforms ohos .   # 首次生成宿主
robocopy ..\ohos_supplement\entry .\ohos\entry /E                  # 合入自研插件/权限
..\.tools\flutter_ohos\bin\flutter.bat build hap --debug
# 产物 app/ohos/entry/build/default/outputs/default/entry-default-unsigned.hap（~109MB，签名见 .tools/signing 脚本）

# ---- 字幕工坊 ----
$env:PYTHONPATH = "$PWD\tools\subtitle-studio"
.\.tools\venvs\mll\Scripts\python.exe -m pytest tools\subtitle-studio\tests   # 18 passed
.\.tools\venvs\mll\Scripts\python.exe tools\subtitle-studio\tests\gui_smoke.py `
  .tools\studio-out\sample.mll.json .tools\studio-out\sample.smoke.json
# 识别+翻译一条龙（也支持直接翻译已有 JSON，默认跳过已有译文=断点续译）：
.\.tools\venvs\mll\Scripts\python.exe -m mll_subtitles.cli sample.mp3 -t zh-CN
.\.tools\venvs\mll\Scripts\python.exe -m mll_subtitles.cli sample.mll.json -t en --retranslate
# 或资源管理器双击 tools\subtitle-studio\启动字幕工坊.bat

# ---- 工坊打包免安装 exe（目标机无需 Python） ----
powershell -ExecutionPolicy Bypass -File scripts\build-studio-exe.ps1
# 产物 .tools\studio-exe\dist\SubtitleStudio.exe（onefile 约 93MB，首启 10-25s）
# 构建末尾自动 --selfcheck（RESULT: OK）；GUI 启动截图：
powershell -ExecutionPolicy Bypass -File scripts\check-studio-exe-gui.ps1
# 证据：.tools\studio-out\exe-gui.png（标题/一键翻译控件完整）
# 冻结 exe 无界面端到端识别（日志在 <out>.log，validate 失败退 4）：
.\.tools\studio-exe\dist\SubtitleStudio.exe --transcribe "song.flac" --out "song.mll.json" --model small
```

---

## 13. 质量门与验收结论（2026-09-28）

自动化：官方 `flutter test` **18/18**、`flutter analyze` 0 error/0 warning（仅 15 条既有 info）；OH fork `dart analyze` 零问题；字幕工坊 pytest **18/18**（schema 10 项含 v1.3 拆句/时间戳修复 + translator 8 项）+ GUI 真实事件冒烟通过（含一键翻译三轮回归）；服务端 smoke 通过。
v1.3 增补（2026-09-29，无时长上限/歌曲兜底）：**冻结 exe 直跑** 3:53 FLAC 歌曲 small 档 52 句覆盖 233.4s（修复前同文件仅 8 句止于 ~49s）、validate OK、MyMemory 52/52 翻译成功；10 分 16 秒长口播 134 句覆盖 616.9s（VAD 单遍，无额外开销）；sample.mp3 质量门回归仍 WER 0%/rubric 5/5。
v1.2 增补真机验收（2026-09-29，同一台 HBN-AL00）：工坊 CLI 经 MyMemory 真实翻译 sample 4/4 成功 → adb 推送 → 条目「替换字幕」SAF 关联 → 播放页三态截图：**双语**（dev-s8，每句英文下中文译文+逐词高亮，无横幅）、**旧无译文字幕**（dev-s4，双语下中文引导横幅出现）、**盲听**（dev-s10 全隐 → s11 显示当前句且自动跟到末句 → s12 看译文出现「跟踪它，记录它…」）、**原文**（dev-s13，纯英文）。

v1.5 在线底座真机全链路（2026-10-01，HBN-AL00 + `adb reverse tcp:8000`，uvicorn 0.0.0.0:8000，全程脚本零人工干预）：

| 环节 | 场景 | 结论 / 证据 |
|---|---|---|
| d1 | 覆盖安装 0.4.0+4 debug 包、冷启动 | PASS：发现页直接加载服务端独家频道（截图 01/02） |
| d2 | pm clear 游客冷启 | PASS：我的页「连接状态：在线」、服务器 http://127.0.0.1:8000、游客 0/100 分钟额度（截图 03） |
| d3 | 注册→搜索→订阅 | PASS：弹窗注册（昵称/邮箱/密码）并登录；搜索 1790849761 精确命中→详情页「订阅」变「已订阅」；admin API sub_count=1；资料库播客订阅 Tab 在列（截图 13） |
| d4 | 禁用账号冷启 403 降级 | PASS：冷启动即弹 SnackBar「账号已被禁用，请联系管理员」（截图 19）；prefs.json 落 guest JWT / isGuest=true / email 清空 / notice 消费后清空；我的页自动游客态；admin 重新启用+重置密码后登录恢复 |
| d5 | 断网退订→重连收敛 | PASS：移除 adb reverse 后退订本地立即消失、`subscriptions.pending=[{id,sub:false}]`、服务端 sub_count 仍=1；恢复 reverse 下拉同步→队列清空、sub_count=0、频道不复活 |
| d6 | OTA 0.4.1+5 | PASS：检查更新对话框（截图 20，版本/大小/notes 正确）→Kotlin 下载器 152,185,771 字节完整→`run-as sha256sum cache/mll-update.apk` = `4ea8b470…0b5d8d` 与 release id=6 **逐位一致**→系统安装器唤起（截图 21）；安装后 UI 自报 0.4.1、登录态保留、latest `has_update:false` |
| d7 | pm clear 云端恢复 | PASS：重登后资料库订阅 Tab 自动恢复独家频道，subscriptions=1 / pending=0（云端拉取恢复，截图 22） |

设备侧安全策略（非 App 缺陷）：华为包安装器在勾选「I understand…」风险框后还要求**输入锁屏 PIN**，自动化无法代输；最终安装以 `adb install -r -d` 覆盖同一份已通过 sha256 校验的 APK 完成，应用数据保留。修复后回归：App `flutter test` **82/82**（新增 kv_store×2，含 synced_repositories/update_flow/ml_api 等在线层用例）、analyze 0 error/0 warning/24 info（既有 withOpacity/Radio 基线）；证据截图归档 `.tools/app-shots/`，详细修复记录见 `.trae/specs/pc-backend-sync/review.md` ⑥节。

真机：**HBN-AL00（HarmonyOS 4.2 / AOSP 12 兼容层，序列号 2MN0224730027764，arm64）**，8 条验收标准全部 PASS：

| AC | 内容 | 结论 | 取证 |
|---|---|---|---|
| AC-1 | 播放位置回调/逐词高亮/暂停/完成 | PASS | 连续截图 verify-shots/04~16、29（00:02→00:18 推进，enjoy/alive./genuinely/Listen 逐词高亮，暂停冻结，▶ 完成态） |
| AC-2 | 工坊导出 schema 合法、App 可消费 | PASS | pytest 7/7、flutter test 13/13、fixture 导入测试 |
| AC-3 | 识别质量 | PASS | WER 0%、边界 p90 0.092s、rubric 5/5（quality_report） |
| AC-4 | 人工修正（改词/改时/译文/拆并/加减词） | PASS | gui_smoke 全路径 + 导出重载断言 |
| AC-5 | 导入媒体+字幕配对、杀进程持久化、事后关联/删除 | PASS | 截图 18~24、27 + 设备内 library_index.json / imports 核对 |
| AC-6 | 视频仅播音轨 + 字幕同步 | PASS | PyAV 合成 H.264+AAC mp4，截图 22/23（推进+中文空态）、25/26（关联后 Listen/podcast 高亮） |
| AC-7 | 工坊易用性 | PASS | bat 一键启动、主窗口截图、编辑操作自动化 |
| AC-8 | 工程质量（双端 analyze/test/出包） | PASS | debug 89.8MB / release 17.3MB arm64 APK |

> 该兼容层**屏蔽三方应用 logcat**（系统日志可见、应用 tag/pid 全不可见），AC-1 按预案改用「连续截图（状态图标+进度数字+高亮词）+ 设备内文件核对」举证；`dumpsys audio` 为全局计数不可按 app 过滤，未采用。

---

## 14. ★ 真机联调环境与调试方法（详细手册）

> 本章是 HBN-AL00 实测沉淀，换同类华为消费机（仅 ADB、无 hdc）同样适用。

### 14.1 设备与连接

| 项 | 值 / 做法 |
|---|---|
| 型号 / 系统 | HBN-AL00，HarmonyOS 4.2（Android 12 兼容层，API 31） |
| 序列号 | `2MN0224730027764`（单设备，adb 命令无需 -s） |
| 物理分辨率 / density | **1260×2844，density 540** |
| 包名 / Activity | `com.mylanglean.app` / `.MainActivity` |
| adb | `.tools\android-sdk\platform-tools\adb.exe`（工作区另有一份 `.tools\platform-tools\adb.exe`，用其一即可） |
| 首次连接 | 手机开开发者模式+USB 调试，插线后弹窗「允许 USB 调试」；`adb devices` 看到 `device` 而非 `unauthorized` |
| 防熄屏 | `adb shell settings put system screen_off_timeout 600000` |
| 黑屏唤醒 | `adb shell input keyevent KEYCODE_WAKEUP`；上滑解锁 `adb shell input swipe 630 2200 630 500 250` |

### 14.2 安装 / 启动 / 停止

```powershell
$adb = '.tools\android-sdk\platform-tools\adb.exe'
& $adb install -r '.tools\mylanglean-debug-arm64.apk'   # debug 包（先自行出包或拷贝到 .tools）
& $adb shell am start -n com.mylanglean.app/.MainActivity
& $adb shell am force-stop com.mylanglean.app                                 # 杀进程（验持久化）
```

debug 包可随时重装且保留应用数据（`-r`）；release 包 17.3MB 适合手工侧载。

### 14.3 取证方法一：截图（本机主力证据，logcat 不可用）

**必须二进制落盘再 pull**——PowerShell 重定向 `>` 会把 PNG 当文本编码损坏：

```powershell
& $adb shell screencap -p /sdcard/shot.png
& $adb pull /sdcard/shot.png .tools\verify-shots\NN-name.png
```

> 旁注：pull/push 的正常进度信息也走 stderr，PowerShell 里显示红色 CLIXML 噪音，忽略；看到 `1 file pushed/pulled` 即成功。禁止用 `cmd /c`（沙箱不可用）。

### 14.4 取证方法二：UI 层级 dump（半可用，有明确边界）

```powershell
& $adb shell uiautomator dump /sdcard/ui.xml
& $adb pull /sdcard/ui.xml "$env:TEMP\ui.xml"
```

- **原生页面可读**：SAF 文件选择器（com.android.documentsui）、系统弹框（配对询问、删除确认）——用 `text=` / `content-desc=` + `bounds` 算中心点点击，比按截图坐标准；
- **Flutter 页面通常读不到语义树**：dump 里没有卡片/按钮文本，播放页/资料库页要按截图算坐标；但语义偶尔开启（content-desc 形如 `my-voice-lesson.mp3&#10;本地文件&#10;已配对字幕`），开启时可直接用 bounds；
- PowerShell 取 bounds 中点示例：
  ```powershell
  $m = [regex]::Match($xml, '<node[^>]*content-desc="暂不"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"')
  $x=[int](([int]$m.Groups[1].Value+[int]$m.Groups[3].Value)/2)
  $y=[int](([int]$m.Groups[2].Value+[int]$m.Groups[4].Value)/2)
  & $adb shell input tap $x $y
  ```

### 14.5 常用坐标（1260×2844，Flutter 语义读不到时用）

| 目标 | 坐标(x,y) | 备注 |
|---|---|---|
| 播放页关闭 X | (105,207) | |
| 底部「资料库」Tab | (476,2669) | |
| 播放/暂停大圆钮 | **(634,2224)** | 勿用过低 y（曾用 2315 擦边落空） |
| 倍速按钮 / 1.0x 选项 | (201,2710) / (472,2324) | |
| 进度条轨道 | y≈1990 | seek：`input swipe 1043 1990 250 1990 250` |
| 资料库「导入音视频」FAB | (972,2236) | 原生 dump 时以 bounds 为准 |

截图在看图器中常显示为 ~1000px 宽（缩放比 ≈1.26），**坐标换算回 1260 物理宽**再 tap，或优先信 uiautomator bounds。

### 14.6 取证方法三：应用沙箱文件核对（持久化/导入证据）

debug 包可 run-as：

```powershell
& $adb shell run-as com.mylanglean.app cat files/library_index.json
& $adb shell run-as com.mylanglean.app ls -l files/imports
```

导入的媒体与配对字幕复制在 `files/imports/`（同名冲突自动 `_1`），索引字段：
`id/title/mediaPath/transcriptPath/durationMs/language/importedAt`。

### 14.7 端到端验收操作流程（AC-5/AC-6 复现）

1. **制备并推送素材**（二选一或都做）：
   ```powershell
   # 音频：直接复用内置示例；字幕：工坊产物
   & $adb shell mkdir -p /sdcard/Download/mll-test
   & $adb push app/assets/audio/sample.mp3 /sdcard/Download/mll-test/my-voice-lesson.mp3
   & $adb push .tools/studio-out/sample.mll.json /sdcard/Download/mll-test/my-voice-lesson.mll.json
   # 视频（黑画面+同一音轨，验"只播音轨"）：
   .\.tools\venvs\mll\Scripts\python.exe scripts\make_test_video.py   # 产物 .tools/studio-out/sample-black.mp4
   & $adb push .tools/studio-out/sample-black.mp4 /sdcard/Download/mll-test/
   & $adb shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d file:///sdcard/Download/mll-test/my-voice-lesson.mp3
   ```
2. App 内：资料库 → 导入音视频 → SAF 进 **Show roots → HBN-AL00（设备存储根）→ Download → mll-test** 选媒体；
3. 弹框「是否配对字幕？」：①选「选择字幕」走完整配对；②再导一次选「暂不」验无字幕空态；
4. 杀进程重进验持久化（14.2 force-stop + start，配合 14.6 看索引）；
5. 条目右上 ⋮：验「关联字幕」（事后补配）与「删除」（确认后索引+文件双清）；
6. 播放中按 14.3 在不同进度连续截图 2–3 帧（高亮词应随进度变化）。

### 14.8 SAF 选择器已知行为（系统特性，非 App 缺陷）

- **Downloads 历史聚合视图不显示 `.json`**（DownloadsProvider 不索引该 MIME），即使 picker intent 用 `*/*`；必须从 **Show roots → 设备名（HBN-AL00）→ Download/** 的真实文件路径进入；
- `.mp3/.mp4` 在历史视图与真实路径都可见；
- 无文件管理器时 SAF 无法启动：插件已捕获 ActivityNotFoundException 回传中文错误，不崩 App。

### 14.9 已观察的非缺陷现象

- 从 00:14 附近 seek/重播时偶发「▶ 图标但旧句边框残留」的瞬时帧；**从头完整播放** 00:02→00:18 的推进/高亮/暂停/完成全部稳定；
- 本地视频条目入库 `durationMs=0`（列表不展示时长），播放页时长由 `onPrepared` 给出，无功能影响；后续可在导入复制时预探测；
- OH fork 构建 HAP 的 tool crash（缺 npm）与应用代码无关，用 `dart analyze` 做 OH 侧静态门。

### 14.10 后续待覆盖

- HarmonyOS NEXT 真机/云真机：HAP 安装、AVSession 锁屏后台、麦克风动态授权、AudioViewPicker；
- 容器兼容面：mkv / HEVC / AC3（本期仅 mp3 + H.264/AAC mp4）；
- 真实素材：噪声、中英混合、长音频的识别质量与额度计费链路。

### 14.11 在线底座/OTA 真机调试经验（v1.5 沉淀）

**网络打通（App 默认连 http://127.0.0.1:8000）**

```powershell
& $adb reverse tcp:8000 tcp:8000      # 设备 127.0.0.1:8000 → 本机服务端
& $adb reverse --list                 # UsbFfs tcp:8000 tcp:8000
& $adb reverse --remove tcp:8000      # 模拟断网（App 请求立即失败，可验离线队列）
```

**应用沙箱核对（debug 包 run-as；PowerShell 重定向需用 exec-out）**

```powershell
& $adb exec-out run-as com.mylanglean.app cat files/prefs.json > prefs.json   # 勿用 shell 重定向
& $adb shell run-as com.mylanglean.app ls -l cache/                            # OTA：mll-update-<id>.part / mll-update.apk
& $adb shell run-as com.mylanglean.app sha256sum cache/mll-update.apk          # 与服务端 release.sha256 逐位比对
```

prefs.json 关键键：`auth.token`（JWT，payload `guest:true` 区分游客）、`auth.isGuest`、`auth.email`、
`auth.notice`（一次性通知，消费后清空）、`subscriptions`、`subscriptions.pending`。

**OTA / 安装器（HBN-AL00 实测）**

- 未知来源权限：O+ 首次 `canRequestPackageInstalls()` 为 false，插件拉起
  `ACTION_MANAGE_UNKNOWN_APP_SOURCES` 后本机会话结束（needPermission 事件）；可手工/自动预置：
  `adb shell am start -a android.settings.MANAGE_UNKNOWN_APP_SOURCES -d package:com.mylanglean.app`
  打开 Switch；核对 `adb shell appops get com.mylanglean.app REQUEST_INSTALL_PACKAGES`（allow）。
- 华为安装器两道关卡：先勾「I understand…」CheckBox 再点 INSTALL，随后要求**锁屏 PIN**——
  属设备安全策略，自动化测试改用 `adb install -r -d <apk>` 覆盖同一已校验包（保留数据）；
  该机型安装期间占用安装锁，GUI 安装器未退出时 adb install 会挂起/报
  `INSTALL_FAILED_ABORTED: User rejected permissions`，先 CANCEL 系统安装界面再装。
- USB 调试大文件安装时偶发「USB debugging started」重连，流式安装中断但实际可能已 Success，
  以 `dumpsys package ... versionName/versionCode` 为准。
- 安装内容 URI：`content://com.mylanglean.app.updatefile/apk`（非导出 FileProvider，
  [MlUpdateFileProvider.kt](../app/android/app/src/main/kotlin/com/mylanglean/app/MlUpdateFileProvider.kt)）。

**UI 自动化踩坑清单**

- 键盘弹起会整体上移表单：填多个输入框的正确节奏是「点框→输入→`keyevent 4` 收键盘→
  再点下一个框（此时按 dump bounds 坐标准确）」；键盘开着点“下一个框坐标”实际会落在
  软键字母上（实测误入字符 `g`、`l`）。提交按钮坐标也要在 dump 当时取（键盘开时 y≈1641、
  收键盘后 y≈2682）。
- PowerShell 正则取 bounds 中心：`[int]$g[1].Value+[int]$g[3].Value` 在数组上下文会被
  当字符串拼接，先转 `[int]` 再 `/2`，或直接用已核对的硬编码坐标。
- `screencap -p` 优先写 `/data/local/tmp/`（写 /sdcard 偶发 0 字节）；0 字节时删文件重试；
  pull 后及时 `rm` 设备临时文件。
- `uiautomator dump` 在播放/过渡动画时偶报「could not get idle state」，sleep 1-2s 重试。
- 底部 Tab 真实热区 y≈2574-2844：发现 (140,2709)、资料库 (472,2709)、我的 (1120,2720)；
  播放页 Close (95,234)；我的页「登录」按钮 (1010,547)。
- 登录态重置：pm clear 后需重新登录；测试账号密码若被改动，可用管理接口
  `PATCH /admin/users/{uid}`（`{"reset_password":...}`）重置，辅助脚本
  `server/.tools_check_dev.py`。

---

## 15. 里程碑

1. ~~环境/HelloWorld/骨架~~ 2. ~~发现+资料库~~ 3. ~~播放内核修复+本地导入~~ 4. ~~字幕工坊（识别/校对/导出）~~ 5. ~~导入配对+持久化~~ 6. ~~视频音轨+双空态~~ 7. ~~真机端到端验收（8 AC PASS）~~ 8. NEXT 设备 HAP/后台/授权验收 9. 服务端真实 ASR+额度联调 10. iOS 移植 11. 发布。

## 16. 风险与对策（更新）

| 风险 | 对策 / 现状 |
|---|---|
| 消费级 HarmonyOS 4.x 装不了 Stage HAP | 已实测定位为模型代际阻断；Android 兼容层先行交付，NEXT/云真机排期 |
| OH 适配插件差异 | PAL 隔离 + ArkTS 自研三件套（已写），Android 同构 Kotlin 插件对照 |
| Whisper GPU/网络成本 | PC 工坊 int8 + 工作区离线缓存；tiny/small 已随仓库流程文档可复现 |
| 长字幕高亮卡顿 | 局部刷新 + 句级懒加载 + 词索引二分 |
| 真实容器/语种兼容 | 14.10 已列待覆盖清单，先文档化再逐项验 |
| 版权 | 仅个人学习缓存、不分发、标注原 feed |
