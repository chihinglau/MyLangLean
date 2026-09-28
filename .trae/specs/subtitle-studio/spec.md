# 字幕工坊（Windows 转字幕工具 + App 导入跟读）- 产品需求文档

## Overview
- **Summary**：修复 Android 端字幕不随播放高亮的缺陷；新增一个运行在 Windows 电脑端的「字幕工坊」图形工具，用本地 faster-whisper 把任意音频/视频转换成 App 同款逐词时间戳字幕 JSON，并支持人工修正；App 端支持手动导入「媒体 + 字幕」配对文件，播放时逐词高亮、进度条与字幕联动。
- **Purpose**：示例音频修复后用户反馈「有声音但字幕单词不联动」，且用户希望用自己的真实素材（含视频）做跟读，需要一条「电脑出字幕 → 手机导入 → 逐词跟读」的完整离线链路。
- **Target Users**：MyLangLean 单机用户自己（Windows 电脑 + HarmonyOS 4.2 安卓层/HarmonyOS 手机），以及未来所有想导入自定义素材的语言学习者。

## Goals
- 修复播放位置回调导致的字幕/进度条不更新问题，逐词高亮与语音严格同步。
- Windows 图形工具：本地 Whisper 识别（音频与视频皆可，中英等多语言），导出与 App schema 完全一致的逐词字幕 JSON；可人工编辑词、时间、分句、译文。
- App 导入：通过系统文件选择器导入媒体（音频/视频）与字幕 JSON，二者可配对；本地媒体与配对关系持久化，重启不丢。
- 导入素材在播放页复用现有卡拉 OK 字幕、点词定位、单句循环、进度条拖动联动能力。
- 全程可离线运行（模型首次下载后），工具链位于工作区 `.tools/`，工具源码位于仓库 `tools/`。

## Non-Goals
- App 内不做视频画面渲染（视频文件仅播放其音轨 + 字幕；画面播放列为后续阶段）。
- App 内不做在线 ASR / 云端字幕生成。
- 不做 SRT/VTT 导入导出（工具直接产出 App 原生 JSON 格式；通用格式兼容后续再议）。
- ~~不做字幕的机器翻译（译文列允许人工填写，留空则仅原文）。~~ **2026-09-29 修订：机翻纳入范围（FR-9），免 key 公共端点、零新增依赖、人工译文优先不被覆盖。**
- App 内不嵌翻译调用（翻译只在 PC 工坊侧生产进字幕文件；App 只消费 `translation` 字段）。
- 不做 iOS / 桌面端 Flutter 的导入适配（接口预留但只实现 Android；OHOS 保持现状内存态）。
- 不做素材的云同步、账号体系联动。

## Background & Context
- 现有字幕 schema（[transcript.dart](file:///d:/ai/prj/trae/HuaWei/MyLangLean/app/lib/domain/entities/transcript.dart)）：`version/language/duration/segments[{id,start,end,text,translation?,words[{w,s,e,p?}]}]`，时间单位秒；`TranscriptIndex.wordAt` 二分查找当前词。
- 根因已定位：[MlAudioPlayerPlugin.kt](file:///d:/ai/prj/trae/HuaWei/MyLangLean/app/android/app/src/main/kotlin/com/mylanglean/app/MlAudioPlayerPlugin.kt#L32-L45) 33ms 定时器首次触发时 `player == null` 直接 `return`，且未重新 postDelayed，定时器永久死亡 → `onPosition` 永不回调 → 进度条不动、字幕不高亮（声音正常）。另外 `load()` 后立即 `play()` 存在 prepare 未完成的竞态；Kotlin 也从不回推 `playing` 状态。
- 导入基础已存在：[MlMediaPickerPlugin.kt](file:///d:/ai/prj/trae/HuaWei/MyLangLean/app/android/app/src/main/kotlin/com/mylanglean/app/MlMediaPickerPlugin.kt) 用 SAF 选文件并复制到 `filesDir/imports`，MIME 已含常见视频容器；但只支持选媒体、无字幕选择、[mock_repositories.dart](file:///d:/ai/prj/trae/HuaWei/MyLangLean/app/lib/data/repositories/mock_repositories.dart) 的本地媒体库为纯内存、重启丢失，`AssetTranscriptRepository` 对任何单集都返回内置示例字幕。
- 播放页对「无字幕」无兜底：`transcript == null` 时永远转圈。
- 工具链现状：Python 3.10 venv 在 `.tools/venvs/mll`（已装 edge-tts）；Android 真机 HBN-AL00 通过 adb 连接（当前会话曾掉线，验收时需重新连接）。
- 用户已确认：本地 Whisper、视频先只做音轨、图形界面、需要人工修正。

## Functional Requirements
- **FR-1（缺陷修复）**：播放任意媒体期间，App 以约 30Hz 收到播放位置；播放/暂停/完成状态正确；prepare 未完成时点播放不丢指令。
- **FR-2（工具-识别）**：字幕工坊支持选择本地音频或视频文件（mp3/m4a/wav/mp4/mkv/mov 等），使用 faster-whisper（word_timestamps）输出词级时间戳；模型档位（tiny/base/small/medium）、语言（自动/指定）、计算精度可选；模型经国内镜像下载，下载后离线可用。
- **FR-3（工具-编辑）**：识别结果以「分句 + 词」表格展示，可修改词文本、每个词的起止时间（输入数值 + 微调按钮），可增删词、调整分句；可填写每句译文；时间数据实时校验（单调递增、s<e、不越界）。
- **FR-4（工具-导出）**：一键导出 App 字幕 JSON（schema v1，UTF-8，含 language/duration/segments/words），默认与媒体同目录同名；导出前强制校验通过。
- **FR-5（工具-启动）**：提供 Windows 一键启动批处理（自动使用工作区 venv、首次运行自动装依赖、配置 HF 国内镜像），无需用户懂 Python。
- **FR-6（App-导入配对）**：Android「我的内容」页导入媒体后，可继续选择字幕 JSON（可跳过）；也可对已导入条目事后「关联/替换字幕」；字幕文件复制进应用私有目录，原文件被移动/删除不影响使用。
- **FR-7（App-持久化）**：本地媒体清单（标题、媒体路径、字幕路径、时长、语言、导入时间）持久化到应用私有目录的 JSON 索引，App 重启后列表仍在；播放时优先读取条目配对的字幕文件，无配对时明确提示「无字幕」而非转圈或错配示例字幕。
- **FR-8（App-播放联动）**：导入素材播放时，逐词高亮、句子自动居中、点词跳转、拖动进度条字幕跟随、单句循环、倍速全部可用；视频容器文件播放其音轨。
- **FR-9（工具-一键机翻，v1.2 新增）**：工坊对识别/载入后的字幕按句机器翻译并写入 `segments[].translation`；目标语言可选（默认 zh-CN）；免 key 公共翻译端点（默认 MyMemory，海外自动降级 Google gtx，支持自建 LibreTranslate），零新增 Python 依赖；GUI 后台线程执行、日志区逐句进度、按钮防重入；已有非空译文默认跳过（断点续译、保护人工译文），提供「全部重译」；单句/单通道失败自动重试与降级，全部失败时保留成功部分并允许重跑续译；CLI 支持 `-t/--translate-to`、`--retranslate`、`--provider`，且可直接对已有 `.mll.json` 只翻译。
- **FR-10（App-三态完整，v1.2 新增）**：双语模式下字幕全部无译文时显示可关闭的中文引导横幅（引导用工坊翻译后重新关联），仅部分句缺译时在缺译句原位显示浅色占位；盲听模式默认隐藏全部字幕，可一键「显示当前句」（随播放位置自动切换、换句重新隐藏），并可偷看该句译文、对该句单句循环、一键收起继续盲听。

## Non-Functional Requirements
- **NFR-1**：识别准确度——清晰的英文/中英素材，small 模型下识别文本词错率 WER ≤ 10%，词边界与实际发音偏差典型 ≤ 0.5 秒。
- **NFR-2**：工具易用性——不读说明书可在一个窗口内完成「选文件 → 识别 → 导出」全流程；长任务有进度/日志、界面不卡死（后台线程）。
- **NFR-3**：离线与体积——工具依赖全部装进现有 venv；模型按需下载、可复用缓存；不污染系统环境变量。
- **NFR-4**：双端回归——官方 Flutter（3.47）analyze 无 error、既有 5 个测试通过；OH fork 分支 analyze 保持零问题；Kotlin 编译通过。
- **NFR-5**：健壮性——坏字幕 JSON、缺文件、取消选择等情况有明确中文提示，不崩溃、不白屏。

## Constraints
- **Technical**：Windows 10/11 + Python 3.10（venv 已存在）；faster-whisper（ctranslate2 + PyAV 解码视频，无需另装 ffmpeg）；GUI 用标准库 tkinter（零额外 GUI 依赖）；App 侧 Flutter 3.47 / Kotlin MediaPlayer / SAF；Android minSdk 24。
- **Business**：零预算（不用付费 API）；用户个人使用，无服务端。
- **Dependencies**：pip 清华镜像、HuggingFace hf-mirror 镜像（模型）；真机 adb 连接用于验收；HarmonyOS 4.2 走 Android 12 兼容层。

## Assumptions
- 用户电脑为 x64 Windows、性能足够 small 模型 CPU 推理（不可用时可降到 tiny/base）。
- faster-whisper 通过 PyAV 可直接解码用户提供的视频容器；极端编码失败时提示先转码（非本次交付）。
- 中文等无空格语言的 Whisper 词级 token 为字/词组粒度，App 现有按词渲染可接受。
- 内置示例单集继续使用 `assets/data/sample_transcript.json`；工具产物 schema 与其一致。

## Acceptance Criteria

### AC-1：播放位置回调与逐词高亮修复
- **Type**: `rule`
- **Given**: debug/release 新版 App 安装到真机
- **When**: 打开示例单集播放
- **Then**: logcat 持续出现 `onPosition` 且毫秒值递增；播放页进度条走动；第 2 秒左右 "voices" 词高亮、第 5 秒前后高亮进入第二句
- **Pass Condition**: logcat 抓到 ≥20 条递增 onPosition；两张不同时刻截图显示不同高亮词，且与听到的词一致
- **Evidence**: logcat 摘录 + `.tools/verify-shots/` 截图

### AC-2：字幕工坊导出 schema 合法
- **Type**: `rule`
- **Given**: 工具对一段媒体完成识别与导出
- **When**: 用 App 的 `Transcript.fromJson` 解析导出文件（dart 测试），并用 Python 校验
- **Then**: 解析成功；每词 s<e、全句时间单调递增、duration ≥ 末词 e；segments/words 非空且 language 合法
- **Pass Condition**: 新增 dart 测试通过；Python 校验脚本退出码 0
- **Evidence**: `flutter test` 输出 + 校验输出 + 样例导出文件

### AC-3：识别准确度与时间戳质量
- **Type**: `rubric`
- **Dimension**: 识别质量（文本 WER 与边界偏差）
- **Scale**: 1-5
- **Anchors**: 1 = 文本大面积错误、时间戳不可用；3 = WER ≤ 20% 且多数词边界偏差 ≤ 1s；5 = WER ≤ 10% 且 ≥90% 词边界偏差 ≤ 0.5s
- **Pass Threshold**: >= 4
- **Evidence**: 用已知文稿的 edge-tts 合成音频作基准，比对工具导出文本（WER）与基准边界（偏差分布）的脚本结果

### AC-4：人工修正真实生效
- **Type**: `rule`
- **Given**: 识别完成后在 GUI 改一个词、把某词时间 ±0.2s、增加一句译文
- **When**: 导出 JSON
- **Then**: 导出文件中对应改动逐字存在；时间仍单调合法
- **Pass Condition**: 自动/手动检查导出 JSON 包含全部三处改动
- **Evidence**: 操作说明 + 导出 JSON diff 摘录

### AC-5：App 导入媒体+字幕并持久化
- **Type**: `rule`
- **Given**: 手机上存有工具导出的媒体与同名 JSON
- **When**: 在「我的内容」导入媒体并选择该字幕，杀掉 App 重进，再播放
- **Then**: 重启后条目仍在；播放页显示导入素材自身的字幕文本（非内置示例稿）；高亮随声音走；点词可跳转
- **Pass Condition**: 重启后列表截图 + 播放页截图 + logcat 位置递增
- **Evidence**: 截图与日志；无字幕导入时显示「无字幕」提示（FR-7）也一并验证

### AC-6：视频容器按音轨播放
- **Type**: `rule`
- **Given**: 一个 mp4 视频文件及其工具字幕
- **When**: 导入并播放
- **Then**: 可听到视频音轨、字幕正常联动，无崩溃（无画面符合本期范围）
- **Pass Condition**: 播放出声音且 onPosition 递增
- **Evidence**: logcat + 现场验证（受真机/素材限制时可降为手工演示记录）

### AC-7：工具整体易用性
- **Type**: `rubric`
- **Dimension**: Windows 工具可用性
- **Scale**: 1-5
- **Anchors**: 1 = 需命令行/读文档才能跑通；3 = 能完成但步骤绕、长任务界面假死；5 = 双击 bat 即用、单窗口流程顺畅、后台识别有进度
- **Pass Threshold**: >= 4
- **Evidence**: 从干净 venv 启动批处理的完整操作录屏/截图与首次依赖安装日志

### AC-8：回归与工程质量
- **Type**: `rule`
- **Given**: 全部改动完成
- **When**: 运行双端 analyze、flutter test、Kotlin 构建
- **Then**: 官方 Flutter analyze 无 error；测试全绿；OH fork analyze 零问题；debug+release arm64 APK 构建成功
- **Pass Condition**: 四条命令输出均满足
- **Evidence**: 各命令输出摘录与 APK 时间戳

### AC-9：工坊一键机翻（v1.2 新增）
- **Type**: `rule`
- **Given**: 工坊载入一份无译文 `.mll.json`（或识别刚完成）
- **When**: 选目标语言 zh-CN 后点「一键翻译」（或 CLI `-t zh-CN`）
- **Then**: 每个缺译句写入 translation；再次运行默认全部跳过；`--retranslate`/「全部重译」覆盖；预置的人工译文在非强制运行中原样保留；单句被假 provider 置失败时成功句仍保留且失败句 id 被记录
- **Pass Condition**: translator 单测（假 provider，无网络）8 项全绿；gui_smoke 翻译三轮断言通过；真实端点在当前网络至少一条通道可用并成功翻译样例 4/4
- **Evidence**: pytest 输出 + gui_smoke 输出 + `.tools/studio-out/sample.zh.mll.json` 内容

### AC-10：App 三态完整（v1.2 新增）
- **Type**: `rule`
- **Given**: 真机分别关联「全译文 / 无译文」两份字幕
- **When**: 在播放页循环切换 双语 → 盲听 → 原文
- **Then**: 无译文字幕在双语下出现中文引导横幅（可关闭），全译文字幕不出现；盲听默认无字幕，「显示当前句」展示播放位置所在句、「看译文」展示该句译文、「继续盲听」收起；原文模式不显示任何译文
- **Pass Condition**: subtitle_modes_test.dart 5 用例通过；真机三态 + 横幅共 ≥5 张连续截图在案
- **Evidence**: flutter test 输出 + `.tools/studio-out/dev-s4/s8/s10/s11/s12/s13` 截图

## Open Questions
- [x] （已决）识别引擎 = 本地 faster-whisper；视频本期仅音轨；工具为 GUI；需人工修正。
- [x] （已决，2026-09-29）机翻 = 工坊侧免 key 公共端点（MyMemory 主通道实测可达），App 不联网翻译；断点续译、人工译文不覆盖。
- [ ] 若真机 adb 在验收窗口仍不可用，AC-1/5/6 的设备证据标记 blocked 并在设备恢复后补验，不以自测替代独立验收。
