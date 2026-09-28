# Launch the frozen SubtitleStudio.exe like a double-click (clean global env),
# wait for its window, grab a screenshot as evidence, then close it.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$exe = Join-Path $root '.tools\studio-exe\dist\SubtitleStudio.exe'
$shot = Join-Path $root '.tools\studio-out\exe-gui.png'

Remove-Item Env:\HF_HOME -ErrorAction SilentlyContinue
Remove-Item Env:\HUGGINGFACE_HUB_CACHE -ErrorAction SilentlyContinue
Remove-Item Env:\HF_XET_CACHE -ErrorAction SilentlyContinue
Remove-Item Env:\HF_XET_LOG_DIR -ErrorAction SilentlyContinue

$p = Start-Process -FilePath $exe -PassThru
# onefile: the bootloader process ($p) spawns the real app as a child;
# the window belongs to the child, so poll every process of the same name.
$gui = $null
for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Seconds 1
    $gui = Get-Process -Name SubtitleStudio -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
    if ($gui) { break }
}
if (-not $gui) {
    Stop-Process -Name SubtitleStudio -Force -ErrorAction SilentlyContinue
    throw 'GUI window did not appear within 60s.'
}
$title = $gui.MainWindowTitle
Start-Sleep -Seconds 3  # let the window finish painting

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
$bmp.Save($shot, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()

# Graceful close the real window, then kill any survivor (bootloader).
$null = $gui.CloseMainWindow()
Start-Sleep -Seconds 3
Get-Process -Name SubtitleStudio -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue

Write-Host "WINDOW_TITLE=$title"
Write-Host "SCREENSHOT=$shot"
