# 字幕工坊 - 实施计划

## Task 1: 修复 Android 播放器位置/状态回调
- **Status**: `done`
- **Completion evidence**:
  - MlAudioPlayerPlugin.kt 整文件重写：ticker 末尾无条件续期；prepared/playWhenPrepared 消除竞态；play/pause/completion 回推 onState；seek/loop 补发 onPosition；dispose 改名 releasePlayer。
  - debug+release arm64 APK 均构建成功（Kotlin 编译零错误，期间修复了 MlMediaPickerPlugin KDoc 中 `audio/*` 的 `/*` 嵌套注释问题）。
  - TR-1.1/TR-1.2 真机证据已随 Task 7 交付（HBN-AL00 兼容层屏蔽三方 logcat，以连续截图举证：位置 00:02→00:18 持续推进、II/▶ 状态翻转、暂停冻结、完成态，见 verify-shots/04~16）。
- **Priority**: `high`
- **Depends On**: None
- **Description**:
  - 修 [MlAudioPlayerPlugin.kt](file:///d:/ai/prj/trae/HuaWei/MyLangLean/app/android/app/src/main/kotlin/com/mylanglean/app/MlAudioPlayerPlugin.kt) 定时器：ticker 每次运行末尾无条件 `postDelayed`（player 为 null 时也续期），消除「首帧空转后永久死亡」。
  - 消除 prepare 竞态：load 期间记录 `playWhenPrepared`；若 play 在 prepared 前到达则延迟到 onPrepared 中 start；prepared/播放/暂停/完成时通过 `onState` 回推 `playing/paused/completed`（保持 Dart 侧现有字符串协议，`playing` 已被识别）。
  - A/B 回跳时也补发一次 onPosition，避免跳变瞬间 UI 停滞。
- **Acceptance Criteria Addressed**: AC-1, AC-8
- **Test Requirements**:
  - `rule` TR-1.1: 代码走查确认 ticker 无提前 return 断链路径；构建 debug APK 成功，播放时 logcat（或临时调试日志）可见持续递增 onPosition；证据：Kotlin 代码片段 + logcat 摘录
  - `rule` TR-1.2: 加载后立即点播放（含 prepare 慢的极端情况）不出现静默不响；播放/暂停按钮图标随状态翻转；证据：真机操作截图
- **Notes**: 不动 OHOS/Dart 协议；只在 Kotlin 侧补齐状态字符串。

## Task 2: 播放页无字幕兜底与本地字幕解析
- **Status**: `done`
- **Completion evidence**:
  - Episode 增 transcriptPath/hasTranscriptFile/copyWith；AssetTranscriptRepository → LocalAwareTranscriptRepository（sidecar 存在读文件、坏 JSON 抛 TranscriptException、asset:// 回退内置）。
  - PlayerState 增 transcriptError，字幕失败不阻塞播放；播放页新增「无字幕/字幕损坏」中文空态；total 用 mediaDuration。
  - `flutter test`：transcript_import_test.dart 5 用例全过（fixture test/fixtures/tool_sample_transcript.json）。TR-2.2 真机空态已验证（verify-shots/22、23：无字幕视频中文空态，不转圈）。
- **Priority**: `high`
- **Depends On**: None
- **Description**:
  - `Episode` 增加可空字段 `transcriptPath`（本地字幕文件绝对路径），copy/构造兼容。
  - 重写 `AssetTranscriptRepository.transcriptFor`（可更名 LocalAwareTranscriptRepository，provider 同步换名）：episode.transcriptPath 非空则用 `File.readAsString` 解析本地 JSON（解析失败抛带中文上下文的异常）；否则回退内置示例。
  - 播放控制器捕获无字幕/坏字幕：PlayerState 增加 `transcriptError`；播放页把永久 CircularProgressIndicator 替换为「该内容没有字幕 / 字幕文件损坏」提示页（含去关联字幕的引导按钮可选）。
  - 新增 dart 测试：从工具样例 JSON（Task 5 产物，先放一份固定 fixture `test/fixtures/tool_sample_transcript.json`）解析成功。
- **Acceptance Criteria Addressed**: AC-2, AC-5, AC-8
- **Test Requirements**:
  - `rule` TR-2.1: `flutter test` 新增用例通过：本地 JSON 经 Transcript.fromJson 后 duration/segments/words 与 fixture 一致；坏 JSON 抛出异常
  - `rule` TR-2.2: 无字幕条目进入播放页显示中文空态，不出现无限转圈；证据：测试/截图

## Task 3: Android 文件选择与应用存储能力
- **Status**: `done`
- **Completion evidence**:
  - MlMediaPickerPlugin.kt 重写：pickAudio/pickFile/filesDir 三方法，SAF 选完复制进 filesDir/imports，同名自动 _1，返回 sizeBytes；Dart 侧按扩展名过滤。
  - media_picker_service.dart android/mock/ohos 三实现补齐（ohos pickFile 抛 UnimplementedError）。
  - Kotlin 编译通过（APK 产物已更新）；官方 flutter analyze 无 error/warning（仅既有 withOpacity info）。TR-3.1 真机选 .json/.mp3/.mp4 复制进 filesDir/imports 已验证（run-as 见副本，同名自动 _1）；注：SAF Downloads 历史视图不显示 .json，经设备存储根路径可见。
- **Priority**: `high`
- **Depends On**: None
- **Description**:
  - [MlMediaPickerPlugin.kt](file:///d:/ai/prj/trae/HuaWei/MyLangLean/app/android/app/src/main/kotlin/com/mylanglean/app/MlMediaPickerPlugin.kt) 新增方法 `pickFile`（参数允许扩展名列表，如 json）：仍走 SAF ACTION_OPEN_DOCUMENT + `*/*`，复制到 `filesDir/imports` 后返回 path/title/size；`pickAudio` 内部复用同一实现。
  - 新增方法 `filesDir`：返回 `activity.filesDir.absolutePath`，供 Dart 侧持久化索引。
  - Dart 侧 [media_picker_service.dart](file:///d:/ai/prj/trae/HuaWei/MyLangLean/app/lib/pal/media_picker_service.dart) 与 android/mock/ohos 三实现补齐 `pickFile({List<String> exts})` 与 `filesDir()`（mock 用 Directory.systemTemp；ohos 抛 UnimplementedError 安全兜底）。
- **Acceptance Criteria Addressed**: AC-5, AC-8
- **Test Requirements**:
  - `rule` TR-3.1: Kotlin 编译通过；真机选一个 .json 返回 filesDir/imports 下绝对路径（日志或实际导入验证）；证据：构建输出 + Task 6 联调记录
  - `rule` TR-3.2: `flutter analyze` 无新增 error；证据：analyze 输出

## Task 4: 本地媒体库持久化与导入配对流程
- **Status**: `done`
- **Completion evidence**:
  - data/local_library_store.dart：library_index.json 索引、LocalMediaEntry、坏索引 .corrupt-时间戳 隔离；local_library_store_test.dart 2 用例全过。
  - PersistentLibraryRepository：addLocalMedia（含 transcriptPath/title/language/durationMs）、attachTranscript、removeLocalMedia（best-effort 删文件）；main.dart Android 启动时 filesDir 异步注入。
  - library_page.dart：选媒体→询问是否选字幕（json 预校验 segments 非空并提取 duration/language）→配对入库；条目 PopupMenu（关联/替换字幕、删除确认）+字幕/视频图标。
  - TR-4.2 真机杀进程重启持久化已验证（20/21 + library_index.json 内容核对）；TR-4.3 交互序列：导入→配对弹框（选择字幕/暂不）→自动播放→条目图标/菜单→删除确认，均有截图（18~27），三步内可完成。
- **Priority**: `high`
- **Depends On**: Task 2, Task 3
- **Description**:
  - 新增 `LocalLibraryStore`（Dart）：索引文件 `<filesDir>/library_index.json`，条目字段 id/title/mediaPath/transcriptPath/durationMs/language/importedAt；异步 load/save，文件损坏时备份后空库启动。
  - `LibraryRepository` 接口演进：`addLocalMedia(String mediaPath, {String? transcriptPath, String? title})`、`attachTranscript(episodeId, path)`、`removeLocalMedia(episodeId)`；保留订阅相关方法。Android 实际使用持久化实现（构造时注入 filesDir 与初始加载）；其余平台维持内存实现（接口默认实现或内存类保留）。
  - [library_page.dart](file:///d:/ai/prj/trae/HuaWei/MyLangLean/app/lib/features/library/library_page.dart)：导入流程改为「选媒体 → 弹框询问是否选字幕（选择/跳过）」；条目增加「关联/替换字幕」与「删除」操作（弹出菜单）；列表显示有无字幕图标；启动时 await 加载索引再渲染。
  - provider 初始化改为异步（Provider 内 Completer 或 `provider` 初始化的小 bootstrap），main.dart 可在 runApp 前预热。
- **Acceptance Criteria Addressed**: AC-5, AC-6, AC-8
- **Test Requirements**:
  - `rule` TR-4.1: dart 单测：用临时目录模拟 filesDir，add→重新 new 一个 store load→条目与 transcriptPath 均在；坏索引文件不崩
  - `rule` TR-4.2: 真机：导入媒体+字幕、杀进程重进条目仍在、播放的是导入字幕；证据：重启前后两张截图 + 播放页截图
  - `rubric` TR-4.3: 导入交互顺畅度；scale 1-5；anchors 1=看不懂怎么配对/频繁报错，3=能完成但提示含糊，5=三步内完成且取消/跳过都有明确反馈；threshold >= 4；证据：操作录屏/截图序列

## Task 5: 字幕工坊核心库（识别 + schema 导出 + 校验）
- **Status**: `done`
- **Completion evidence**:
  - TR-5.1：`pytest tests/test_schema.py` 6 项全绿。
  - TR-5.2：small 模型真实识别 sample.mp3 → .tools/studio-out/sample.mll.json（4 句 43 词，离线加载工作区内 .tools/hf-cache 模型缓存）；schema roundtrip 与 App fixture 兼容（transcript_import_test 通过）。
  - TR-5.3：.tools/studio-out/quality_report.txt —— WER=0.00%，词边界起始误差 mean=0.056s / p90=0.092s，43/43 落在 0.5s 内，rubric=5/5 PASS。
  - 模型获取：huggingface.co 不可达；hf-mirror.com 对 huggingface_hub 客户端连接超时，改用 scripts/download-whisper-model.ps1（Invoke-WebRequest 重试，手工落 HF 缓存结构）下载 tiny+small。
- **Priority**: `high`
- **Depends On**: None
- **Description**:
  - 新建 `tools/subtitle-studio/`：`requirements.txt`（faster-whisper，走清华镜像）、`mll_subtitles/__init__.py`、`transcriber.py`、`schema.py`、`studio.py`、`启动字幕工坊.bat`。
  - `schema.py`：dataclass Segment/Word/Transcript；`from_whisper(segments, language, duration)` 产出 schema（词 w 去首尾空格、保留前后顺序；segment.start/end 取其词边界并集；p 取 word.probability）；`validate()` 规则——非空、s<e、词时间单调、句时间单调、duration≥末词 e；`save_json()` 输出 App 一致格式（indent=2, ensure_ascii=False）。
  - `transcriber.py`：封装 faster-whisper（model_size/language/compute_type=int8、HF_ENDPOINT 镜像可被环境变量覆盖）；后台回调式进度日志；对音频/视频路径直接 transcribe（PyAV 解码）。
  - 纯逻辑测试 `tests/test_schema.py`（用构造的伪 whisper 段，不下载模型）：转换、校验拦截非法时间、导出 JSON 可被 fixture 对比。
  - pip 安装 faster-whisper 到 `.tools/venvs/mll`；模型下载验证 small（若网络/时间不足，tiny 验证流程并记录）。
- **Acceptance Criteria Addressed**: AC-2, AC-3
- **Test Requirements**:
  - `rule` TR-5.1: `pytest tests/test_schema.py`（venv python）全绿；证据：命令输出
  - `rule` TR-5.2: 用 `app/assets/audio/sample.mp3` 跑一次真实识别导出到 `.tools/studio-out/sample.json`，Python 校验通过且 dart fixture 测试（Task 2）可消费；证据：输出文件 + 测试输出
  - `rubric` TR-5.3: 识别质量（AC-3 同维）；以 edge-tts 已知文稿+边界为基准计算 WER 与边界偏差；threshold >= 4；证据：`.tools/studio-out/quality_report.txt`

## Task 6: 字幕工坊 GUI 与一键启动
- **Status**: `done`
- **Completion evidence**:
  - TR-6.1：tests/gui_smoke.py 走真实 GUI 代码路径（载入→改词 Real!→+0.05s 微调→加中文译文→拆句/合并→validate→导出→重载断言改动持久化），GUI_SMOKE_OK，产物 .tools/studio-out/sample.edited.mll.json。
  - TR-6.2/TR-6.3：bat 启动到主窗口（模型 small、语言自动检测、句表/词编辑/译文/日志区完整），截图 .tools/studio-out/studio_gui.png。注：bat 文件名含中文，从自动化进程传参时会被 ANSI 损坏；资源管理器双击正常，用户使用不受影响。
  - 独立评审追加修复（见 review.md B1/B2/I5）：加词/删词 stale commit 守卫、拆句重叠校验、实时校验、精度选择（int8/float32，CLI --compute-type）、非法时间不丢词、保留置信度 p、导出默认媒体同目录、合并保留译文、无音轨中文错误；gui_smoke 已加对应回归断言。
- **Priority**: `high`
- **Depends On**: Task 5
- **Description**:
  - `studio.py`（tkinter）：顶部「打开媒体 / 模型档位 / 语言 / 开始识别」；中部按句分段的词表（Treeview 或可滚动表单网格）：列 词文本、开始、结束、置信度，行内编辑 + ±0.05s 微调按钮；句级字段（译文、合并/拆分句、增删词）；底部状态栏与日志区；识别在后台线程执行，通过队列刷新 UI。
  - 「导出字幕」：validate 不通过时逐条定位错误；通过则默认写到媒体同目录同名 `.mll.json`（文件名可改）。
  - `启动字幕工坊.bat`：定位仓库根 `.tools\venvs\mll\Scripts\python.exe`；缺失依赖时 `pip install -r requirements.txt -i 清华`；默认 `set HF_ENDPOINT=https://hf-mirror.com`；启动 studio.py；出错暂停显示日志。
  - GUI 自检：在无模型环境也能打开窗口（识别按钮才触发加载）。
- **Acceptance Criteria Addressed**: AC-4, AC-7
- **Test Requirements**:
  - `rule` TR-6.1: 手工执行 AC-4 三处编辑（改词、改时、加译文），导出 JSON 含改动且 validate 通过；证据：导出片段
  - `rubric` TR-6.2: AC-7 同维易用性；按 AC-7 anchors 评分；threshold >= 4；证据：首次启动截图（含装依赖日志）+ 主窗口截图 + 操作序列
  - `rule` TR-6.3: bat 在当前机器双击可启动（命令行模拟执行到主窗口 mainloop 前不报错）；证据：执行日志

## Task 7: 端到端联调、出包与双端质量门
- **Status**: `done`
- **Completion evidence**:
  - TR-7.2：官方 Flutter 3.47 `flutter test` 13/13 通过；`flutter analyze` 无 error/warning（15 条均为既有 withOpacity info，非本次改动）；OH fork（3.22.0）`dart analyze` 零问题（其 `flutter analyze` 因本机缺 node/npm/ohpm 在 hvigor 安装钩子崩溃，与代码无关；Android 出包使用工作区标准版 `.tools\flutter`）；pytest 7/7、GUI 回归冒烟通过（含评审修复）。
  - 产物：.tools/mylanglean-debug-arm64.apk（含全部修复，出包后临时节流 Log.d 已移除并用标准版 Flutter 重建重装）、.tools/mylanglean-release-arm64.apk（17.3MB，构建于加临时日志之前，与最终代码一致）。
  - 评审修复的 App 侧问题：循环点跨节目复位（I1）、媒体加载/解码失败中文空态+errorStream（I2）、SAF 后台线程复制+半成品清理（I3）、prepared 前 seek 缓存（I4）、NO_PICKER 中文错误、playEpisode 交错 token。
  - TR-7.1 真机证据（HBN-AL00，HarmonyOS 4.2 Android12 兼容层，序列号 2MN0224730027764；该兼容层屏蔽三方 app logcat，故按「连续截图+设备内索引文件」举证，不用 dumpsys 全局计数替代）：
    - **AC-1**（内置示例）：verify-shots/04~16 —— 00:02→00:18 位置持续推进、词 enjoy/alive./genuinely 橙色逐词高亮、句边框随句移动、暂停后位置与高亮冻结多帧一致、结尾 ▶ 完成态。
    - **AC-5**：导入 my-voice-lesson.mp3 并配对字幕工坊产物 my-voice-lesson.mll.json（18-imported.png 自动播放 00:04、字幕逐词高亮）；条目显示「本地文件·已配对字幕」（19-library-entry.png）；`am force-stop` 后重启条目仍在（20-after-restart.png），点入播放正常（21-replay-after-restart.png 词高亮）；设备内 `files/library_index.json` 两条目字段完整、imports/ 下媒体与字幕副本齐全；菜单「关联字幕」toast「字幕已关联」（24-video-linked-sub.png）；「删除」确认框明示媒体与字幕一并删除（截图在案），确认后索引条目与 mp4/mll_1.json 文件均消失、另一条目完好（27-after-delete.png + run-as ls）。
    - **AC-6**：scripts/make_test_video.py 用 PyAV 合成 H.264+AAC 黑画面 mp4（.tools/studio-out/sample-black.mp4），导入选「暂不」→ 22/23-video-nosub：仅播音轨（II 态、00:09→00:14 推进、不渲染画面），中文空态「这段内容还没有字幕…可在电脑上用「字幕工坊」生成字幕，再到「我的内容」导入或关联字幕文件」；事后关联字幕 → 25/26-video-sub：mp4 音轨上逐词高亮（Listen@00:03、podcast@00:09）。
    - 最终包回归：28-final-build-launch.png、29-final-build-play.png（重装后数据保留、播放高亮正常）。
  - 已知非阻断观察：①SAF 的 Downloads 历史提供方不列出 .json，需经「Show roots → HBN-AL00 → Download」真实路径选取（系统行为，已在操作记录注明）；②本地视频条目入库时 durationMs=0，播放时长由 MediaPlayer onPrepared 给出，功能无影响（review 低风险清单已记）；③logcat 在该设备不可用属系统限制。
- **Priority**: `high`
- **Depends On**: Task 1, Task 2, Task 4, Task 6
- **Description**:
  - 用字幕工坊处理真实素材（含 sample.mp3 复测、一段短视频/外部音频），产出 JSON 与媒体一并推入手机（adb push 或手动）。
  - 真机验证 AC-1/5/6：安装新 debug APK → 导入配对 → 杀进程重启 → 播放截图/logcat → 无字幕空态 → 关联字幕后恢复。
  - 执行 `scripts/verify-android-playback.ps1` 并扩展（导入路径的 UI 操作可手工补充记录）。
  - 双端 analyze/test（官方 + OH fork），构建 debug+release arm64，复制到 `.tools/mylanglean-{debug,release}-arm64.apk`。
  - 更新项目记忆：工具位置、用法、已验证结论。
- **Acceptance Criteria Addressed**: AC-1, AC-2, AC-5, AC-6, AC-8
- **Test Requirements**:
  - `rule` TR-7.1: AC-1/AC-5/AC-6 各有真机证据（截图+logcat）；本设备兼容层屏蔽三方 logcat，已用连续截图（状态图标+进度数字+高亮词）与设备内索引/文件核对替代并注明；设备不可用时任务保持 in_progress 并注明 blocked 条件，不以自测顶替
  - `rule` TR-7.2: 官方 flutter analyze 无 error、测试全绿、OH analyze 零问题、两个 APK 产物时间戳更新；证据：命令输出

## Task 8: 工坊一键机翻 + App 三态补全（v1.2）
- **Status**: `done`
- **Completion evidence**（2026-09-29，全程无人工干预）:
  - 端点实测：Google gtx 超时、有道旧端点/Edge auth 404；**MyMemory 1.1s 可达且译文正确**，定为默认主通道，gtx 留作海外降级（可插拔链 + 每通道 2 次重试）。
  - 新增 `mll_subtitles/translator.py`（标准库 urllib，零新增依赖）：normalize_lang、mymemory/google/libre 三 provider、translate_text 降级链、translate_transcript（跳过已有/force/失败保留/暂停节流/同语拒绝）；env：MLL_TRANSLATE_PROVIDER、MLL_TRANSLATOR_EMAIL、MLL_LIBRETRANSLATE_URL。
  - GUI（studio.py）：控制条增「译成 zh-CN/en/ja/ko/fr/de/es/ru」+「一键翻译」+「全部重译」；Treeview 增「译文」列（✓）；后台线程 + queue 事件（translate_done/translate_error）+ 三按钮 busy 防重入；失败弹框列出句号、成功部分保留。顺手修复树重建后异步重发选择事件冲掉状态条的问题（idx==current_seg 忽略）。
  - CLI（cli.py）：支持直接翻译已有 .mll.json；-t/--translate-to、--retranslate、--provider；部分失败退出码 3 但保存成功部分。
  - App：transcript.dart 加 hasTranslation/translatedCount/hasTranslations；karaoke_subtitle.dart 双语无译文横幅（可关闭）+ 部分缺译逐句占位；盲听重做为 _BlindListenView（显示当前句/看译文/单句循环/继续盲听，随播放自动换句）。
  - 自动化：pytest **15/15**（新增 test_translator.py 8 项，假 provider/假 HTTP 无网络）；gui_smoke 增三轮翻译回归（补译保留人工译文→只补缺句→强制重译）GUI_SMOKE_OK；flutter test **18/18**（新增 subtitle_modes_test.dart 5 用例）；flutter analyze 回到基线 15 条既有 withOpacity info（新代码用 withValues）。
  - 真机（HBN-AL00，标准版 flutter + JDK17 构建 app-debug.apk 安装）：CLI 真实翻译 sample 4/4 → sample.zh.mll.json 推送 /sdcard/Download/mll-test/ → 条目菜单「替换字幕」SAF 选取 → toast「字幕已关联」。截图：dev-s4（旧无译文字幕→双语横幅）、dev-s8（双语 EN+ZH 逐词高亮）、dev-s10（盲听全隐+显示当前句按钮）、dev-s11（揭示后自动跟到末句 Shadow it…）、dev-s12（看译文「跟踪它，记录它，让它成为你的。」）、dev-s13（原文纯英文）。
- **Priority**: `high`
- **Depends On**: Task 5, Task 6, Task 7
- **Acceptance Criteria Addressed**: AC-9, AC-10（spec v1.2 新增），并强化 F4/FR-3
- **Notes**: schema v1 不冻结变更（translation 字段早已存在）；requirements.txt/启动 bat 无需改动。
