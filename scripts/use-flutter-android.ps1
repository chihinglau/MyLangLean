# ============================================================
#  Session-only switch: official Flutter + Android toolchain
#  in THIS shell. Does NOT modify system environment.
#  Dot-source it:  . .\scripts\use-flutter-android.ps1
#
#  Toolchain layout (all under workspace .tools, D: drive):
#    .tools\flutter       official Flutter stable (APK builds)
#    .tools\flutter_ohos  OH fork (HAP builds; use use-flutter-ohos.ps1)
#    .tools\jdk17         JDK 17 (AGP 9 / Gradle 9)
#    .tools\android-sdk   platforms 35/36 + build-tools + platform-tools
# ============================================================
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Tools = Join-Path $Root '.tools'

$env:FLUTTER_ROOT = Join-Path $Tools 'flutter'
$env:JAVA_HOME    = Join-Path $Tools 'jdk17\jdk-17.0.2'
$env:ANDROID_HOME = Join-Path $Tools 'android-sdk'
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
$env:GRADLE_USER_HOME = Join-Path $Tools 'caches\gradle'
$env:PUB_CACHE    = Join-Path $Tools 'caches\pub-cache-official'
$env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'
$env:Path = (Join-Path $Tools 'flutter\bin') + ';' +
            (Join-Path $env:JAVA_HOME 'bin') + ';' +
            (Join-Path $env:ANDROID_HOME 'platform-tools') + ';' + $env:Path

Write-Host '[env] Official Flutter + Android toolchain activated (this session)' -ForegroundColor Green
flutter --version
Write-Host ''
Write-Host 'Build APK:  cd app; flutter build apk --debug' -ForegroundColor Cyan
Write-Host 'Install:    adb install -r build\app\outputs\flutter-apk\app-debug.apk' -ForegroundColor Cyan
