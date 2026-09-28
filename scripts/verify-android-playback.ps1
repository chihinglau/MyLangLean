# Install the fresh APK, drive the UI into the sample episode, and verify
# playback is advancing (screenshots + audio service state + logcat).
# Run from repo root after `flutter build apk --release --target-platform android-arm64`.
$ErrorActionPreference = 'Stop'
$adb = Join-Path (Resolve-Path '.tools').Path 'android-sdk\platform-tools\adb.exe'
$apk = 'app\build\app\outputs\flutter-apk\app-release.apk'
$shotsDir = '.tools\verify-shots'
New-Item -ItemType Directory -Force -Path $shotsDir | Out-Null

Write-Host 'waiting for device...'
& $adb wait-for-device
& $adb install -r $apk | Select-Object -Last 1
& $adb logcat -c
& $adb shell am start -n com.mylanglean.app/.MainActivity | Out-Null
Start-Sleep -Seconds 4

function Tap-Text([string]$needle, [int]$retries = 6) {
    for ($i = 0; $i -lt $retries; $i++) {
        & $adb shell uiautomator dump /sdcard/ui.xml *> $null
        & $adb pull /sdcard/ui.xml "$env:TEMP\ui.xml" *> $null
        $xml = Get-Content "$env:TEMP\ui.xml" -Raw
        $m = [regex]::Match(
            $xml,
            '<node[^>]*text="[^"]*' + [regex]::Escape($needle) +
            '[^"]*"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"')
        if ($m.Success) {
            $cx = [int](([int]$m.Groups[1].Value + [int]$m.Groups[3].Value) / 2)
            $cy = [int](([int]$m.Groups[2].Value + [int]$m.Groups[4].Value) / 2)
            Write-Host "tap '$needle' at $cx,$cy"
            & $adb shell input tap $cx $cy
            return $true
        }
        Start-Sleep -Milliseconds 800
    }
    throw "node not found: $needle"
}

Tap-Text 'Real English Voices'
Start-Sleep -Milliseconds 800
Tap-Text '示例单集'
# playEpisode() loads and auto-starts; give MediaPlayer time to prepare.
Start-Sleep -Seconds 4
& $adb exec-out screencap -p > "$shotsDir\play-1.png"
Start-Sleep -Seconds 4
& $adb exec-out screencap -p > "$shotsDir\play-2.png"

Write-Host '--- active audio sessions ---'
(& $adb shell dumpsys audio) | Select-String 'mylanglean|AudioTrack|player state' | Select-Object -First 8
Write-Host '--- player log (errors / media) ---'
(& $adb logcat -d) |
    Select-String 'MlAudio|MediaPlayer|AUDIO_ERROR|error:|flutter' |
    Select-Object -First 40 | ForEach-Object { $_.Line }
Write-Host "screenshots in $shotsDir"
