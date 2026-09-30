# MyLangLean · AI 播客影子跟读（OORA 风格复刻）

> 版本：**v0.2.0（MVP 真机验收通过）** ｜ 更新日期：2026-09-28
> 现阶段可运行：**Android arm64（HBN-AL00 真机实测）** ｜ 设计目标：HarmonyOS 4.2+（HAP 待 NEXT 设备）｜ 架构预留：iOS 13+
> 参考产品：https://oora.yoshinn.com.cn/#product （本项目仅用于技术学习，不含其品牌素材）

把全网播客 / 本地音视频变成「逐词字幕 + 翻译 + AB 循环变速 + 录音跟读评分」的私人外语课。
本仓库的独特闭环：**Windows「字幕工坊」离线生产逐词字幕 → 手机导入媒体与字幕配对 → 播放时卡拉OK式逐词高亮**。

## ✨ 功能特性

| 模块 | 实现 |
|---|---|
| 发现内容 | 发现页（语言/难度筛选）、Mock 目录；FastAPI 已备 PodcastIndex 代理 |
| 资料库 | 本地音频/**视频（只播音轨）**导入、字幕配对、杀进程持久化、事后关联/删除 |
| 逐词字幕 | 扁平词索引二分定位 + 局部刷新卡拉OK高亮、点词定位、单句循环 |
| 字幕模式 | 原文 / 双语 / 盲听三态，5 档字号 |
| 精听 | 单句 AB 循环、0.6–1.5× 变速（原生 MediaPlayer 计时） |
| 跟读 | AAC 录音 + V1 启发式评分（节奏/流利/语调） |
| 字幕工坊（PC） | faster-whisper 逐词识别（tiny/small 可离线）、词/句级 GUI 校对、**一键机翻（免 key，默认 MyMemory）**、校验、一键导出 App 同 schema |
| 账户/额度 | JWT 设备游客、每月 6000 秒额度、幂等计费（服务端 smoke 全通过） |
| 容错空态 | 无字幕 / 字幕损坏 / 媒体无法播放 / 无文件管理器，全部中文引导，不无限转圈 |

## 📱 真机验收（2026-09-28，HBN-AL00）

8 条验收标准全部 PASS：播放位置流与逐词高亮、暂停冻结与完成态、SAF 导入配对、force-stop 重启持久化、
视频仅播音轨、无字幕中文空态、事后关联字幕、删除连文件清理。
完整取证流程与设备调试手册见 [docs/OORA复刻-软件设计方案.md](docs/OORA复刻-软件设计方案.md) 第 13/14 章。

> 说明：HarmonyOS 4.2 消费机无法安装 Stage 模型 HAP（系统容器为 FA 模型，syscap 校验阻断），
> 本期真机闭环运行在该机 AOSP 12 兼容层；HAP（含 AVSession 锁屏后台）待 HarmonyOS NEXT 真机/云真机验收。

## 🚀 快速开始

### 方式一：出 Android APK（推荐，普通手机可装）

```powershell
# 工具链全部位于工作区 .tools（不写系统环境）
. .\scripts\use-flutter-android.ps1          # 本会话激活官方 Flutter + JDK17 + Android SDK
cd app
flutter pub get
flutter analyze                              # 0 error / 0 warning（仅少量既有 info）
flutter test                                 # 18/18
flutter build apk --release --target-platform android-arm64
# 产物：app\build\app\outputs\flutter-apk\app-release.apk（约 17MB）
adb install -r build\app\outputs\flutter-apk\app-release.apk
```

> 注意：出 APK 必须用**官方标准版 Flutter**（`.tools/flutter`）；OH fork 在本机缺 node/npm 时会在 hvigor 钩子崩溃。

### 方式二：字幕工坊生产逐词字幕

```powershell
# 双击 tools\subtitle-studio\启动字幕工坊.bat，或：
$env:PYTHONPATH = "$PWD\tools\subtitle-studio"
.\.tools\venvs\mll\Scripts\python.exe -m pytest tools\subtitle-studio\tests   # 18 passed
.\.tools\venvs\mll\Scripts\python.exe -m mll_subtitles.cli --help

# 识别后直接翻译（-t 目标语言）；也可只翻译已有字幕 JSON（断点续译，默认跳过已有译文）
.\.tools\venvs\mll\Scripts\python.exe -m mll_subtitles.cli `
  .tools\studio-out\sample.mll.json -o .tools\studio-out\sample.zh.mll.json -t zh-CN
```

工坊 GUI：打开媒体 → 选模型档位（tiny/small，离线缓存）→ 识别 → 词/句级校对 →
「一键翻译」（译成 zh-CN/en/ja/ko 等，已有译文自动保留，失败可重跑续译）→
默认导出到媒体同目录的同名 `.mll.json`。手机端导入媒体时选择该文件配对即可。
翻译默认走免 key 的 MyMemory（海外可自动降级 Google gtx，亦可自建 LibreTranslate），
实测 sample.mp3 用 small 档：**WER 0%，词边界 p90 误差 0.092s，4 句机翻全部成功**。

**音频无时长上限**：整段音频始终全部识别（已实测 10 分钟口播 134 句、3:53 歌曲 52 句）。
默认走 VAD 人声分割；当 VAD 覆盖率不足 60%（歌曲/强背景音乐下人声会被误判为非人声，
表现为"只有前几十秒几句"）时，日志会提示并**自动切换全音频识别兜底**，同时加音乐风格
提示找回轻柔前奏上的演唱，再按词间停顿把长段整理成歌词行，保证内容不截断。CPU 上识别
耗时约与音频等长，属正常现象。

#### 打包成免安装 exe（分发给没有 Python 的电脑）

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build-studio-exe.ps1
# 产物：.tools\studio-exe\dist\SubtitleStudio.exe（约 93MB，单文件双击即用）
# 构建末尾自动跑 --selfcheck；另有 GUI 启动截图验证：
powershell -ExecutionPolicy Bypass -File scripts\check-studio-exe-gui.ps1
```

- PyInstaller onefile 内嵌 Python 3.10 + faster-whisper/ctranslate2/PyAV(ffmpeg)/tkinter，
  **目标机无需安装任何运行时**；首启自解压约 10–25 秒属正常现象（`-Directory` 可出启动更快的目录版）。
- Whisper 模型不打进 exe：首次识别时自动下载到 `exe 同级\hf-cache\`（便携）；
  目录只读时退到 `%LOCALAPPDATA%\MyLangLeanSubtitleStudio\hf-cache`；已设全局 `HF_HOME` 则沿用。
- 隐藏的无界面批处理参数（自动化/自测用，日志写在 `--out` 同名 `.log`）：
  `SubtitleStudio.exe --transcribe "x.flac" --out "x.mll.json" --model small [--lang en]`

### 方式三：桌面调试（无设备）

```powershell
cd app
..\.tools\flutter\bin\flutter.bat run -d windows   # PAL 自动走 Mock 虚拟时钟播放器
```

### 服务端（可选）

```powershell
.\.tools\venvs\mll\Scripts\python.exe -m pip install -r server\requirements.txt
cd server; ..\.tools\venvs\mll\Scripts\python.exe -m uvicorn app.main:app --reload --port 8000
```

默认 `MLL_ASR_BACKEND=stub` 即可跑通游客→转写→额度→翻译→评分全链路；生产切 faster_whisper（Dockerfile 已备）。

## 📁 项目结构

```
MyLangLean/
├─ app/                    Flutter 客户端（一套 lib/ 出 APK/HAP，桌面走 mock）
│  ├─ lib/core             主题、路由、常量
│  ├─ lib/domain           实体 + 仓库抽象
│  ├─ lib/data             Mock 数据 + 本地 JSON 索引库
│  ├─ lib/pal              ★平台抽象：android(Kotlin) / ohos(ArkTS) / mock
│  ├─ lib/features         discover / library / player / shadowing / history / auth
│  ├─ android/             Gradle + Kotlin 插件（MediaPlayer/SAF/MediaRecorder）
│  ├─ ohos/                hvigor + ArkTS 插件（AVPlayer/AVSession，生成物不入库）
│  └─ test/                18 个测试用例 + 工坊 JSON fixture
├─ tools/subtitle-studio/  ★PC 字幕工坊（mll_subtitles：schema/transcriber/translator/cli/studio）
├─ ohos_supplement/        生成 ohos 宿主后合入的 ArkTS 插件与权限
├─ server/                 FastAPI：认证/额度/转写/翻译/评分/发现代理
├─ scripts/                环境切换、模型下载、测试音视频制备、工坊 exe 打包/自检
├─ docs/                   软件设计方案（含真机联调调试手册）
└─ .trae/specs/            字幕工坊需求 spec、任务与评审/验收记录
```

## 🖱️ 典型使用流程

1. PC 上用字幕工坊打开音视频 → 识别 → 校对 → 一键翻译（或手填译文）→ 得到 `xxx.mll.json`；
2. 把媒体与 json 传到手机（adb push 到 Download，或微信/USB）；
3. App「资料库 → 导入音视频」选媒体，弹框选「选择字幕」配对；
4. 播放：逐词高亮、点词定位、单句循环、变速、盲听；
5. 跟读录音 → 评分 → 履历沉淀。

## 🛠️ 技术栈

Dart 3.4+/Flutter（Riverpod、go_router、dio、webfeed）· Kotlin MediaPlayer/SAF · ArkTS AVPlayer/AVRecorder ·
Python faster-whisper/PyAV/tkinter · FastAPI · 一套 Dart 代码 + PAL 多平台实现。

## 📜 许可证与第三方

仅用于学习；播客内容版权归原作者。参考：anytime_podcast_player(BSD-3)、tsacdop(BSD-3)、
faster-whisper(MIT)、PyAV(BSD-3)、sherpa-onnx(Apache-2.0)、Flutter-OH(BSD-3)；AntennaPod(GPL) 仅作思路参考。
