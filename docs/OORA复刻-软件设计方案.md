# OORA 复刻版（MyLangLean）软件设计方案

> 版本：v1.2 ｜ 日期：2026-09-29（v1.1 2026-09-28；v1.0 初稿 2026-09-27）
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
| F6 | 账户额度 | 游客设备ID免登（字幕试看 5 分钟）、登录注册、每月 100 分钟转录额度 | ✅ | 订阅 | 服务端 JWT/额度/幂等计费冒烟通过；App 端为 Mock |
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
| 本地存储 | JSON 文件索引（`filesDir/library_index.json`） | MVP 零原生依赖；坏索引 `.corrupt-时间戳` 隔离；二期可换 Drift |
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
│ Data 层  mock_catalog / mock_repositories      │
│          local_library_store（JSON 索引）       │
│          persistent_library_repository         │
├──────────────────────────────────────────────┤
│ PAL 层  audio_player / recorder / picker       │
│  ohos(ArkTS) · android(Kotlin) · mock(桌面)    │
└──────────────────────────────────────────────┘
```

工程目录（实际）：
```
MyLangLean/
├─ app/                    Flutter 客户端（同一套 lib/ 出 HAP/APK，桌面走 mock）
│  ├─ lib/core/            主题、路由、常量、home_shell
│  ├─ lib/domain/          entities（podcast/episode/transcript/recording/quota）
│  ├─ lib/data/            mock 数据 + 本地库（local_library_store / persistent_*）
│  ├─ lib/pal/             ★平台抽象 + android/ohos/mock 三实现 + providers
│  ├─ lib/features/        discover/library/player(+widgets)/shadowing/history/auth
│  ├─ android/             Gradle 工程 + Kotlin 插件（出 APK）
│  ├─ ohos/                hvigor 工程 + ArkTS 插件（出 HAP，生成物不入库）
│  ├─ assets/{data,audio}/ 内置示例字幕与音频
│  └─ test/                4 个测试文件 + fixtures/
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

## 6. 服务端 API（FastAPI，已实现骨架）

| 方法 | 路径 | 说明 | 额度 |
|---|---|---|---|
| POST | /api/v1/auth/device | 游客设备 JWT | - |
| POST | /api/v1/auth/login | 登录，返回 JWT | - |
| GET | /api/v1/quota | 当月已用/总额（秒） | - |
| POST | /api/v1/transcriptions | 上传/URL 创建转写任务 | 按秒扣 |
| GET | /api/v1/transcriptions/{id} | 轮询状态/结果 | - |
| POST | /api/v1/translate | 批量翻译（带缓存） | - |
| POST | /api/v1/score | 评分 | - |
| GET | /api/v1/discover/proxy | PodcastIndex 代理（隐藏密钥） | - |

`server/` 自带 `tests/smoke_test.py`（游客→转写→轮询→额度→翻译→评分）；默认 `MLL_ASR_BACKEND=stub` 无 GPU 可跑通，生产切 `faster_whisper`（Dockerfile/compose 已备）。

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
| transcriber.py | faster-whisper 封装（tiny/small 档、int8/float32 精度、语言可指定、PyAV 直接解音视频）；启动时把 HF_HOME 指向工作区 `.tools/hf-cache`（import faster_whisper **之前**设置） |
| translator.py | **（v1.2 新增）** 免 key 机器翻译：可插拔 provider 链（默认 `mymemory,google`，均标准库 urllib；另支持自建 LibreTranslate），每通道 2 次重试+自动降级、句间 0.4s 节流；**默认跳过已有非空译文（断点续译、人工译文不被覆盖）**，`force=True` 才重译；源语言=目标语言直接拒绝；env 可配 `MLL_TRANSLATE_PROVIDER` / `MLL_TRANSLATOR_EMAIL`（MyMemory 提额）/ `MLL_LIBRETRANSLATE_URL` |
| schema.py | Segment/Word/Transcript dataclass、from_whisper 映射、validate、save_json（indent=2, ensure_ascii=False，与 App 同格式）；`translation` 字段 v1 即存在，机翻直接写入无需改 schema 版本 |
| studio.py | tkinter GUI：打开媒体/模型档/语言/识别；按句 Treeview 词表（词/起止/置信度行内编辑、±0.05s 微调），**「译文」列以 ✓ 标识已译句**；句译文、加词/删词/拆句/合并；后台线程识别+队列刷新；实时校验；**控制条增「译成」目标语言（zh-CN/en/ja/ko/fr/de/es/ru）+「一键翻译」（仅补缺译句）+「全部重译」，后台线程翻译、日志区进度、失败句保留成功部分并可续跑**；导出默认媒体同目录同名 `.mll.json` |
| cli.py | 命令行批处理（含 --compute-type）；**v1.2 起输入可以是已有 `.mll.json`（只翻译模式，输出默认 `*.zh-CN.mll.json`）；`-t/--translate-to`、`--retranslate`、`--provider`；部分失败退出码 3 但已保存成功部分** |
| eval_quality.py | 质量评估：WER + 词边界误差（mean/p90/0.5s 命中率） |
| tests/ | test_schema.py（7 项）、**test_translator.py（8 项：语言码归一、gtx 响应解析、MyMemory 解析/额度、降级链、重试、跳过/覆盖/失败保留/同语拒绝，全程假 provider 无网络）**、gui_smoke.py（真实事件驱动：改词/微调/译文/拆并句/导出 + **一键翻译三轮回归：补译保留人工译文、只补缺句、强制重译**，含 B1/B2 断言） |
| frozen_entry.py / requirements-build.txt | **（v1.2 追加）PyInstaller 打包入口与构建依赖**：入口先走 GUI `main()`；带 `--selfcheck` 无窗口模式导入 tkinter/PyAV/ctranslate2/faster_whisper 并写 `studio-selfcheck.log`，构建机自动验收冻结包。`scripts/build-studio-exe.ps1` 一键出 onefile `SubtitleStudio.exe`（约 93MB，内嵌运行时，目标机免安装），`scripts/check-studio-exe-gui.ps1` 启动 GUI 截图举证。冻结态模型缓存：exe 同级 `hf-cache\`（便携，只读时退 `%LOCALAPPDATA%\MyLangLeanSubtitleStudio`），并显式固定 `HF_XET_CACHE/HF_XET_LOG_DIR` 防止 hf-xet 原生扩展往盘根乱建目录 |

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
..\.tools\flutter\bin\flutter.bat analyze                 # 仅 15 条既有 withOpacity info
..\.tools\flutter\bin\flutter.bat test                    # 18/18
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
.\.tools\venvs\mll\Scripts\python.exe -m pytest tools\subtitle-studio\tests   # 15 passed
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
```

---

## 13. 质量门与验收结论（2026-09-28）

自动化：官方 `flutter test` **18/18**、`flutter analyze` 0 error/0 warning（仅 15 条既有 info）；OH fork `dart analyze` 零问题；字幕工坊 pytest **15/15**（含 translator 8 项）+ GUI 真实事件冒烟通过（含一键翻译三轮回归）；服务端 smoke 通过。
v1.2 增补真机验收（2026-09-29，同一台 HBN-AL00）：工坊 CLI 经 MyMemory 真实翻译 sample 4/4 成功 → adb 推送 → 条目「替换字幕」SAF 关联 → 播放页三态截图：**双语**（dev-s8，每句英文下中文译文+逐词高亮，无横幅）、**旧无译文字幕**（dev-s4，双语下中文引导横幅出现）、**盲听**（dev-s10 全隐 → s11 显示当前句且自动跟到末句 → s12 看译文出现「跟踪它，记录它…」）、**原文**（dev-s13，纯英文）。

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
