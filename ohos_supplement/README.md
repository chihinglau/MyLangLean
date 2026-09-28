# 鸿蒙宿主合并说明（ohos_supplement）

Flutter 工程本身不提交 `app/ohos/`（由 Flutter-OH 按模板生成）。本目录保存
**生成后需要合入/覆盖的原生文件**，对应 Dart 侧 PAL 层的三个 MethodChannel 插件。

## 目录对照

```
ohos_supplement/entry/src/main/
├─ ets/
│  ├─ entryability/EntryAbility.ets                 # 覆盖生成文件（注册3个插件）
│  └─ plugins/
│     ├─ ml_audio_player/MlAudioPlayerPlugin.ets     # ml/audio_player  AVPlayer+AVSession
│     ├─ ml_audio_recorder/MlAudioRecorderPlugin.ets # ml/audio_recorder AVRecorder+麦克风权限
│     └─ ml_media_picker/MlMediaPickerPlugin.ets     # ml/media_picker  AudioViewPicker
├─ module.json5                                      # 覆盖：权限+后台音频
└─ resources/{base,zh_CN}/element/string.json        # 合并：权限说明文案、应用名
```

## 操作步骤

```powershell
# 1. 用 Flutter-OH 在 app 工程生成 ohos 宿主
cd app
..\.tools\flutter_ohos\bin\flutter.bat create --platforms ohos .

# 2. 拷贝本目录覆盖到 app/ohos
robocopy ..\ohos_supplement\entry .\ohos\entry /E
# module.json5 / EntryAbility.ets 为覆盖；plugins/ 与 string.json 为新增合并
```

## 验证要点（HarmonyOS 4.2 真机）

1. DevEco 打开 `app/ohos`，自动签名后运行；
2. 播放在线 URL 时确认 INTERNET；锁屏后音频继续（AVSession + audioPlayback）；
3. 跟读首次录音弹出麦克风授权，拒绝时 Dart 侧收到 `requestPermission=false`；
4. 系统选择器选音频后文件被复制到 `filesDir/imports`，杀进程后路径仍有效。

## 与 Dart 的协议（勿随意变更）

| Channel | 方法（Dart→ArkTS） | 回调（ArkTS→Dart） |
|---|---|---|
| ml/audio_player | load/play/pause/seek{ms}/setRate{rate}/setLoop{a,b}/dispose | onPosition(ms) / onState(playing,paused,...) / onDuration(ms) |
| ml/audio_recorder | requestPermission / start / stop→路径 | - |
| ml/media_picker | pickAudio→{path,title,durationMs} 或 null | - |
