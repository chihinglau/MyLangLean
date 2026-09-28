# Build the Subtitle Studio into a double-clickable single-file Windows
# GUI exe (end users do NOT need Python installed).
#
# Usage (from repo root):
#   powershell -ExecutionPolicy Bypass -File scripts\build-studio-exe.ps1
#
# Output: .tools\studio-exe\dist\SubtitleStudio.exe
# Self-check: SubtitleStudio.exe --selfcheck  -> studio-selfcheck.log
#
# Notes: the onefile exe unpacks to a temp dir on each launch (a few
# seconds). Whisper models are NOT embedded; they download on first
# transcription into .\hf-cache next to the exe (or
# %LOCALAPPDATA%\MyLangLeanSubtitleStudio\hf-cache when that is read-only).
[CmdletBinding()]
param(
    # onedir starts faster and has fewer AV false-positives; default onefile.
    [switch]$Directory
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$studioDir = Join-Path $root 'tools\subtitle-studio'
$py = Join-Path $root '.tools\venvs\mll\Scripts\python.exe'
$outRoot = Join-Path $root '.tools\studio-exe'

if (-not (Test-Path $py)) {
    throw "Bundled Python not found: $py (initialise .tools\venvs\mll first)."
}

# 1) Ensure the build-only dependency is installed (Tsinghua mirror).
& $py -c "import PyInstaller" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host '[setup] installing PyInstaller (first run only) ...'
    & $py -m pip install -r (Join-Path $studioDir 'requirements-build.txt') `
        -i https://pypi.tuna.tsinghua.edu.cn/simple
    if ($LASTEXITCODE -ne 0) { throw 'PyInstaller installation failed.' }
}

# 2) Package. collect-all the heavy deps so every DLL / data file
#    (including the bundled VAD model) is included: ctranslate2 ships no
#    PyInstaller hook; PyAV and tokenizers are collected whole as a safety.
$modeArgs = if ($Directory) { @() } else { @('--onefile') }
$arguments = @(
    '-m', 'PyInstaller',
    '--noconfirm', '--clean',
    '--windowed',
    '--name', 'SubtitleStudio',
    '--collect-all', 'ctranslate2',
    '--collect-all', 'tokenizers',
    '--collect-all', 'faster_whisper',
    '--collect-all', 'av',
    '--distpath', (Join-Path $outRoot 'dist'),
    '--workpath', (Join-Path $outRoot 'build'),
    '--specpath', $outRoot
) + $modeArgs + @('frozen_entry.py')

Write-Host '[build] running PyInstaller (first build takes 2-5 minutes) ...'
Push-Location $studioDir
try {
    & $py @arguments
    if ($LASTEXITCODE -ne 0) { throw 'PyInstaller failed.' }
} finally {
    Pop-Location
}

# 3) Headless self-check: imports tkinter/PyAV/ctranslate2/faster_whisper.
$exe = Join-Path $outRoot 'dist\SubtitleStudio.exe'
if ($Directory) { $exe = Join-Path $outRoot 'dist\SubtitleStudio\SubtitleStudio.exe' }
$log = Join-Path (Split-Path $exe) 'studio-selfcheck.log'
if (Test-Path $log) { Remove-Item $log -Force }

Write-Host '[check] launching SubtitleStudio.exe --selfcheck ...'
# Simulate an end-user machine with no global HF_HOME/xet vars, so the
# self-check really exercises the portable cache paths baked into the exe.
Remove-Item Env:\HF_HOME -ErrorAction SilentlyContinue
Remove-Item Env:\HUGGINGFACE_HUB_CACHE -ErrorAction SilentlyContinue
Remove-Item Env:\HF_XET_CACHE -ErrorAction SilentlyContinue
Remove-Item Env:\HF_XET_LOG_DIR -ErrorAction SilentlyContinue
$p = Start-Process -FilePath $exe -ArgumentList '--selfcheck' -PassThru
if (-not $p.WaitForExit(120000)) { $p.Kill(); throw 'self-check timed out.' }
if ($p.ExitCode -ne 0 -or -not (Test-Path $log)) {
    throw "self-check failed (exit=$($p.ExitCode)); see $log"
}
Get-Content $log
$size = [math]::Round((Get-Item $exe).Length / 1MB, 1)
Write-Host ''
Write-Host "[done] $exe ($size MB)"
