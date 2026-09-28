# 字幕工坊 - 独立评审与修复报告

评审方式：只读独立评审员逐文件走查 + tkinter 真实事件驱动复现 + 独立复跑全部自动化测试；随后按清单修复并回归。

## 一、评审发现与处置

### 阻断问题（已修复并回归）

| 编号 | 问题 | 修复 | 回归证据 |
|---|---|---|---|
| B1 | GUI「在末尾加词 / 删词」静默失效：`_refresh_segments` 中 `selection_set` 同步触发 `<<TreeviewSelect>>`，旧 `_row_vars` 被整体 commit 回去，覆盖刚发生的结构变更 | [studio.py](file:///d:/ai/prj/trae/HuaWei/MyLangLean/tools/subtitle-studio/mll_subtitles/studio.py) 引入 `_suspend_commit` 守卫，树重建期间屏蔽选择回调，刷新后显式 `_load_segment`；结构操作后统一 recompute_bounds | gui_smoke.py 新增「加词存活（6→7，末词=新词）、删词生效（7→6）」断言，GUI_SMOKE_OK |
| B2 | 「拆句」产生重复词且能通过校验导出（与 B1 同源），词时间全局不再单调，破坏 App wordAt 二分高亮 | 同 B1；[schema.py](file:///d:/ai/prj/trae/HuaWei/MyLangLean/tools/subtitle-studio/mll_subtitles/schema.py) validate 新增「相邻句首词 s ≥ 上句末词 e（EPS 0.02）」与「id 必须 0..n-1 连续」 | gui_smoke 拆句后**合并前**直接 validate 必须零错误、总词数不变；test_schema.py 新增 `test_validate_rejects_overlapping_segments_and_bad_ids`，pytest 7/7 |

### 重要问题（已修复）

| 编号 | 问题 | 修复 |
|---|---|---|
| I1 | 单句循环 A/B 点跨节目不复位，新节目继承旧循环窗口 | [MlAudioPlayerPlugin.kt](file:///d:/ai/prj/trae/HuaWei/MyLangLean/app/android/app/src/main/kotlin/com/mylanglean/app/MlAudioPlayerPlugin.kt)：load 与 releasePlayer 均重置 loopA/loopB |
| I2 | 媒体文件缺失/解码失败时无限转圈或静默停死，无中文兜底 | AudioPlayerService 新增 errorStream（android 实现，mock/ohos 空流）；Kotlin onError 经 `error:` 事件回传；PlayerState 新增 mediaError，load/play try-catch + playToken 防交错；播放页新增「媒体无法播放」中文空态+返回按钮 |
| I3 | SAF 复制在主线程执行，大视频 ANR 风险 | MlMediaPickerPlugin：复制移到后台线程，主线程回投结果；失败删除半成品文件 |
| I4 | prepare 完成前 seek 抛 IllegalStateException 且无兜底 | 新增 pendingSeek，onPrepared 中补发 seek 与 onPosition |
| I5 | 工具侧：计算精度不可选；无实时校验；非法时间格静默丢词；导出目录非媒体同目录；无音轨错误晦涩；合并丢译文 | GUI 增「精度 int8/float32」下拉（CLI 增 `--compute-type`）；切句/结构编辑后状态栏实时校验；非法时间保留原词时间并提示、commit 保留词置信度 p；导出 initialdir=媒体目录；transcriber 包中文解码错误；合并句用「 / 」保留双方译文 |
| 建议 | 无文件管理器时 startActivityForResult 崩 App | 捕获 ActivityNotFoundException → 中文 NO_PICKER 错误 |

### 评审已记录、本期未处理项（低风险）

- 配对预校验仅检查 segments 非空，深层 schema 错误入库后播放才报错（播放页有坏字幕空态兜底）。
- 替换/去关联字幕后 imports 目录可能留孤儿文件（不影响功能，仅占空间）。
- library_index 固定 `.tmp` 文件名（同一 filesDir 内 UI 串行操作，实际并发概率极低）。
- MouseWheel 全局绑定、filesDir 为 null 静默退内存库、OHOS 选字幕 UnimplementedError 文案可优化。
- 评测基准代表性窄（17.6s 干净英文 TTS），真实噪声/中英混合/长音频质量待测。

## 二、AC 复核结论

| AC | 结论 | 依据 |
|---|---|---|
| AC-1 位置回调/逐词高亮 | **PASS**（真机验收 2026-09-28） | 代码走查成立 + HBN-AL00 连续截图 verify-shots/04~16、29：位置 00:02→00:18 持续递增、逐词橙色高亮（enjoy/alive./genuinely/Listen 等）、暂停冻结多帧一致、结尾完成态；该设备兼容层屏蔽三方 logcat，以截图举证 |
| AC-2 导出 schema 合法 | PASS | pytest 7/7、flutter test 13/13、跨句重叠与 id 校验补齐 |
| AC-3 识别质量 | PASS | quality_report.txt：WER 0%，边界 p90 0.092s，5/5 |
| AC-4 人工修正 | PASS（修复后） | 改词/改时/译文 + 加词/删词/拆句/合并全部经真实 GUI 代码路径验证并持久化 |
| AC-5 导入配对+持久化 | **PASS**（真机验收） | 单测 2 项 + 真机：SAF 导入 mp3→配对工坊 JSON→自动播放逐词高亮（18）；force-stop 重启条目仍在且播放正常（20/21）；设备内 library_index.json 与 imports/ 副本核对一致；菜单事后「关联字幕」（24）与「删除」（27，索引+文件一并清理）均验证 |
| AC-6 视频按音轨 | **PASS**（真机验收） | PyAV 合成 H.264+AAC mp4 真机导入：仅播音轨不渲染画面、位置推进（22/23，00:09→00:14）；无字幕时显示中文空态；关联字幕后 mp4 音轨逐词高亮（25/26）。mkv/HEVC/AC3 容器兼容面仍待后续真机覆盖（见剩余风险） |
| AC-7 工具易用性 | PASS（修复后） | bat 启动截图在案；核心编辑操作已自动化验证；首次干净 venv 安装日志未录 |
| AC-8 工程质量 | PASS | 官方 analyze 无 error/warning（15 条为既有 withOpacity info）、13/13 测试；OH fork dart analyze 零问题；debug/release arm64 APK 已重新构建 |

## 三、剩余风险

1. 真机证据已于 2026-09-28 在 HBN-AL00 闭环（AC-1/2/4/5/6/7/8 PASS；AC-3 以质量报告 PASS）。唯一取证瑕疵：HarmonyOS 兼容层屏蔽三方 app logcat，AC-1 改用连续截图（图标+进度数字+高亮词）与设备内文件核对举证。
2. 真实素材（噪声、中英混合、mkv/HEVC/AC3）识别质量与解码兼容性未验证；本期真机容器仅覆盖 mp3 与 H.264+AAC mp4。
3. 本地视频条目入库时 durationMs 记为 0（时长在播放页由 MediaPlayer onPrepared 给出，列表/播放功能不受影响），后续可在导入时预探测。

## 四、产物清单

- `.tools/mylanglean-debug-arm64.apk`（89.8MB）、`.tools/mylanglean-release-arm64.apk`（17.3MB），均含本轮修复。
- `.tools/studio-out/sample.mll.json`（small 识别产物）、`sample.edited.mll.json`（人工修正导出）、`quality_report.txt`、`studio_gui.png`。
- `.tools/hf-cache/hub/`：tiny+small 模型（工作区内，可离线）。
- `scripts/download-whisper-model.ps1`：弱网环境手工模型下载（重试+落 HF 缓存结构）。
