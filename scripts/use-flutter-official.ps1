# ============================================================
#  Session-only switch: use official Flutter (iOS/Android/Win)
#  in THIS shell. Does NOT modify system environment.
#  Dot-source it:  . .\scripts\use-flutter-official.ps1
#  Reserved for the future iOS port.
# ============================================================
param(
  [string]$FlutterRoot = 'D:\dev\flutter_official',
  [string]$CacheRoot   = 'D:\caches'
)
$env:FLUTTER_ROOT = $FlutterRoot
$env:PUB_CACHE    = Join-Path $CacheRoot 'pub-cache-official'
# Official pub endpoints (or keep mirrors if preferred)
$env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'
$env:Path = (Join-Path $FlutterRoot 'bin') + ';' + $env:Path
Write-Host '[env] Official Flutter activated for this session:' $FlutterRoot -ForegroundColor Green
flutter --version
