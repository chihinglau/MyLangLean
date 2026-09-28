#Requires -Version 5.1
# ============================================================
#  MyLangLean - one-click dev environment setup (Windows)
#  Everything is installed on D: drive. Nothing goes to C:.
#
#  Run (Administrator PowerShell recommended):
#    powershell -ExecutionPolicy Bypass -File .\scripts\setup-env.ps1
#
#  Optional parameter:
#    -InstallRoot D:\dev        (tool root; default D:\dev)
#    -HuaweiRoot  D:\HuaWei     (DevEco/SDK root; default D:\HuaWei)
#    -CacheRoot   D:\caches     (pub/gradle/pip/ohpm caches; default D:\caches)
#
#  The script is idempotent: re-running skips installed parts.
# ============================================================
param(
  [string]$InstallRoot = 'D:\dev',
  [string]$HuaweiRoot  = 'D:\HuaWei',
  [string]$CacheRoot   = 'D:\caches',
  [string]$FlutterBranch = '3.22.0-ohos',
  [string]$FlutterRepo   = 'https://atomgit.com/openharmony-tpc/flutter_flutter.git'
)
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'   # speed up Invoke-WebRequest

$Dirs = @{
  Git       = Join-Path $InstallRoot 'Git'
  Python    = Join-Path $InstallRoot 'Python312'
  Venv      = Join-Path $InstallRoot 'venvs\mylanglean'
  Flutter   = Join-Path $InstallRoot 'flutter_ohos'
  DevEco    = Join-Path $HuaweiRoot  'DevEco-Studio'
  Sdk       = Join-Path $HuaweiRoot  'Sdk'
  IdeCfg    = Join-Path $HuaweiRoot  'ide-config'
  PubCache  = Join-Path $CacheRoot   'pub-cache'
  Gradle    = Join-Path $CacheRoot   'gradle'
  PipCache  = Join-Path $CacheRoot   'pip'
  OhpmCache = Join-Path $CacheRoot   'ohpm'
  Download  = Join-Path $InstallRoot 'downloads'
}
$Dirs.Values | Sort-Object -Unique | ForEach-Object {
  if (-not (Test-Path $_)) { New-Item -ItemType Directory -Force -Path $_ | Out-Null }
}

function Add-UserPath([string]$p) {
  $cur = [Environment]::GetEnvironmentVariable('Path','User')
  if (-not $cur) { $cur = '' }
  if ($cur -notlike "*$p*") { [Environment]::SetEnvironmentVariable('Path', ($cur.TrimEnd(';') + ";$p"), 'User') }
}
function Set-UserEnv([string]$k,[string]$v){ [Environment]::SetEnvironmentVariable($k,$v,'User') }

function Download-File([string]$url, [string]$out) {
  Write-Host "  downloading: $url"
  Write-Host '  (no progress bar is shown by design; please wait... large files may take several minutes)'
  Invoke-WebRequest -Uri $url -OutFile $out -TimeoutSec 600
}

Write-Host '=== [1/6] Git (reuse existing, otherwise PortableGit to D drive) ===' -ForegroundColor Cyan
$gitExe = Join-Path $Dirs.Git 'cmd\git.exe'
$systemGit = Get-Command git.exe -ErrorAction SilentlyContinue
if (Test-Path $gitExe) {
  Write-Host 'PortableGit already present, skip.'
  $git = $gitExe
} elseif ($systemGit) {
  $git = $systemGit.Source
  Write-Host "System Git detected, reuse it: $git"
} else {
  Write-Host 'No Git found. Querying China mirror (npmmirror) for PortableGit ...'
  $base = 'https://registry.npmmirror.com/-/binary/git-for-windows'
  $dirs = (Invoke-RestMethod "$base/" -TimeoutSec 30) |
    Where-Object { $_.name -match '^v\d+\.\d+\.\d+\.windows\.\d+/$' } |
    Sort-Object { [version](($_.name -replace '^v|/$|.windows.\d+/$','')) } -Descending
  $latest = ($dirs | Select-Object -First 1).name
  Write-Host "  latest stable: $latest"
  $files = Invoke-RestMethod "$base/$latest" -TimeoutSec 30
  $asset = $files |
    Where-Object { $_.name -match '^PortableGit-.*-64-bit\.7z\.exe$' } |
    Select-Object -First 1
  if (-not $asset) { throw "PortableGit asset not found on mirror: $base/$latest" }
  $out = Join-Path $Dirs.Download 'PortableGit.exe'
  Download-File $asset.url $out
  Write-Host '  extracting (self-extracting 7z, ~1 min) ...'
  Start-Process -FilePath $out -ArgumentList '-y', "-o$($Dirs.Git)" -Wait
  $git = $gitExe
}
Write-Host "Git: $git"
& $git --version

Write-Host "=== [2/6] Flutter-OH (branch $FlutterBranch, D drive) ===" -ForegroundColor Cyan
if (Test-Path (Join-Path $Dirs.Flutter 'bin\flutter.bat')) {
  Write-Host 'Flutter-OH already present, skip.'
} else {
  if (Test-Path $Dirs.Flutter) { Remove-Item -Recurse -Force $Dirs.Flutter }
  Write-Host 'cloning from atomgit (about 1 GB, this is the longest step) ...'
  & $git clone -b $FlutterBranch --depth 1 $FlutterRepo $Dirs.Flutter
  if ($LASTEXITCODE -ne 0) { throw "git clone failed (exit $LASTEXITCODE)" }
}

Write-Host '=== [3/6] Python 3.12 (D drive) + project venv ===' -ForegroundColor Cyan
$pyExe = Join-Path $Dirs.Python 'python.exe'
# Reuse a previously provisioned venv (e.g. project-local .tools\venvs\mll).
$PrebuiltVenv = Join-Path $InstallRoot 'venvs\mll'
if (Test-Path (Join-Path $PrebuiltVenv 'Scripts\python.exe')) {
  $Dirs.Venv = $PrebuiltVenv
  Write-Host "existing venv detected, reuse it: $($Dirs.Venv)"
}
if (-not (Test-Path $pyExe) -and -not (Test-Path (Join-Path $Dirs.Venv 'Scripts\python.exe'))) {
  $pyVer = '3.12.7'
  $out = Join-Path $Dirs.Download 'python-installer.exe'
  # Prefer Huawei Cloud mirror in CN; fall back to python.org.
  $mirrors = @(
    "https://mirrors.huaweicloud.com/python/$pyVer/python-$pyVer-amd64.exe",
    "https://www.python.org/ftp/python/$pyVer/python-$pyVer-amd64.exe"
  )
  $downloaded = $false
  foreach ($url in $mirrors) {
    try { Download-File $url $out; $downloaded = $true; break }
    catch { Write-Warning "mirror failed, try next: $url" }
  }
  if (-not $downloaded) { throw 'all Python download mirrors failed' }
  Write-Host '  installing silently ...'
  Start-Process -FilePath $out -ArgumentList "/quiet","TargetDir=$($Dirs.Python)","Include_pip=1","PrependPath=0","Include_test=0" -Wait
} elseif (Test-Path $pyExe) { Write-Host 'Python 3.12 already present, skip.' }
if (-not (Test-Path (Join-Path $Dirs.Venv 'Scripts\python.exe'))) {
  & $pyExe -m venv $Dirs.Venv
}
$env:PIP_CACHE_DIR = $Dirs.PipCache
$PipIndex = 'https://pypi.tuna.tsinghua.edu.cn/simple'
$VenvPy = Join-Path $Dirs.Venv 'Scripts\python.exe'
Write-Host '  upgrading pip (tsinghua mirror) ...'
& $VenvPy -m pip install --upgrade pip -i $PipIndex
Write-Host '  installing server requirements (tsinghua mirror) ...'
& $VenvPy -m pip install -r (Join-Path $PSScriptRoot '..\server\requirements.txt') -i $PipIndex

Write-Host '=== [4/6] DevEco Studio (zip distribution, D drive) ===' -ForegroundColor Cyan
if (-not (Test-Path (Join-Path $Dirs.DevEco 'bin\deveco64.exe'))) {
  $zip = Get-ChildItem $Dirs.Download -Filter 'deveco-studio-*.zip' -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($zip) {
    Expand-Archive $zip.FullName -DestinationPath $HuaweiRoot -Force
    Get-ChildItem $HuaweiRoot -Directory -Filter 'deveco-studio-*' |
      Where-Object { $_.FullName -ne $Dirs.DevEco } |
      Rename-Item -NewName 'DevEco-Studio'
  } else {
    Write-Warning 'DevEco zip not found. Download it manually (login required) from:'
    Write-Warning '  https://developer.huawei.com/consumer/cn/deveco-studio/'
    Write-Warning "Put the file named deveco-studio-*.zip into: $($Dirs.Download)"
    Write-Warning 'Then re-run this script.'
  }
} else { Write-Host 'DevEco Studio already present, skip.' }

Write-Host '=== [5/6] User environment variables (all on D drive) ===' -ForegroundColor Cyan
Set-UserEnv 'FLUTTER_ROOT' $Dirs.Flutter
Set-UserEnv 'PUB_CACHE'    $Dirs.PubCache
Set-UserEnv 'PUB_HOSTED_URL' 'https://pub.flutter-io.cn'
Set-UserEnv 'FLUTTER_STORAGE_BASE_URL' 'https://storage.flutter-io.cn'
Set-UserEnv 'GRADLE_USER_HOME' $Dirs.Gradle
Set-UserEnv 'PIP_CACHE_DIR'   $Dirs.PipCache
Set-UserEnv 'HOS_SDK_HOME'    $Dirs.Sdk
$jbr = Join-Path $Dirs.DevEco 'jbr'
if (Test-Path $jbr) { Set-UserEnv 'JAVA_HOME' $jbr }

if (Test-Path (Join-Path $Dirs.Flutter 'bin')) { Add-UserPath (Join-Path $Dirs.Flutter 'bin') }
if (Test-Path (Join-Path $Dirs.Git 'cmd'))     { Add-UserPath (Join-Path $Dirs.Git 'cmd') }
if (Test-Path $Dirs.Python)                    { Add-UserPath $Dirs.Python }
if (Test-Path (Join-Path $Dirs.Python 'Scripts')) { Add-UserPath (Join-Path $Dirs.Python 'Scripts') }
$nodeDir = Join-Path $Dirs.DevEco 'tools\node'
$ohpmDir = Join-Path $Dirs.DevEco 'tools\ohpm\bin'
if (Test-Path $nodeDir) { Add-UserPath $nodeDir }
if (Test-Path $ohpmDir) { Add-UserPath $ohpmDir }

Write-Host '=== [6/6] DevEco config relocation (keep IDE data out of C:) ===' -ForegroundColor Cyan
$ideaProps = Join-Path $Dirs.DevEco 'bin\idea.properties'
if (Test-Path $ideaProps) {
  $cfg = @"

# ---- MyLangLean: relocate IDE config/system/log/plugins to D drive ----
idea.config.path=$($Dirs.IdeCfg -replace '\\','/')/config
idea.system.path=$($Dirs.IdeCfg -replace '\\','/')/system
idea.log.path=$($Dirs.IdeCfg -replace '\\','/')/log
idea.plugins.path=$($Dirs.IdeCfg -replace '\\','/')/plugins
"@
  if (-not (Select-String -Path $ideaProps -Pattern 'MyLangLean' -Quiet)) {
    Add-Content -Path $ideaProps -Value $cfg -Encoding UTF8
  }
  $ohpm = Join-Path $ohpmDir 'ohpm.bat'
  if (Test-Path $ohpm) { & cmd /c "`"$ohpm`" config set cache $($Dirs.OhpmCache)" }
}

Write-Host ''
Write-Host '================ SETUP FINISHED ================' -ForegroundColor Green
Write-Host 'Manual steps left:' -ForegroundColor Yellow
Write-Host "  1. Start DevEco ($($Dirs.DevEco)\bin\deveco64.exe), set SDK path to: $($Dirs.Sdk)"
Write-Host '     Install API 12 (ArkTS + Toolchains/hdc); runtime compatible API 11.'
Write-Host '  2. Open a NEW PowerShell and run:  flutter doctor -v'
Write-Host '  3. On the HarmonyOS 4.2 phone: enable Developer mode + USB debugging,'
Write-Host '     then verify with:  hdc list targets'
Write-Host '  4. Build the app:'
Write-Host '     cd app; flutter pub get; flutter build hap --debug'
