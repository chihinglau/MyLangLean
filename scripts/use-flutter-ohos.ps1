# ============================================================
#  Session-only switch: use Flutter-OH (HarmonyOS) in THIS shell.
#  Does NOT modify system environment. Dot-source it:
#    . .\scripts\use-flutter-ohos.ps1
# ============================================================
param(
  [string]$FlutterRoot = 'D:\dev\flutter_ohos',
  [string]$CacheRoot   = 'D:\caches'
)
$env:FLUTTER_ROOT = $FlutterRoot
$env:PUB_CACHE    = Join-Path $CacheRoot 'pub-cache'
$env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'
$env:Path = (Join-Path $FlutterRoot 'bin') + ';' + $env:Path
Write-Host '[env] Flutter-OH activated for this session:' $FlutterRoot -ForegroundColor Green
flutter --version
