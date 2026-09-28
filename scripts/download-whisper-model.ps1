# Download a Systran/faster-whisper model from hf-mirror.com with retries and
# lay it out in the local HuggingFace hub cache (plain files, no symlinks),
# so faster-whisper can load it fully offline (HF_HUB_OFFLINE=1).
#
# Usage: powershell -File scripts\download-whisper-model.ps1 -Model tiny
param(
  [Parameter(Mandatory=$true)][string]$Model
)
$ErrorActionPreference = 'Stop'
$repo = "Systran/faster-whisper-$Model"
$base = "https://hf-mirror.com"
# Keep models in the workspace cache used by the transcriber, unless the
# environment already points HF_HOME elsewhere.
if ($env:HF_HOME) {
  $hub = Join-Path $env:HF_HOME 'hub'
} elseif ($env:HUGGINGFACE_HUB_CACHE) {
  $hub = $env:HUGGINGFACE_HUB_CACHE
} else {
  $root = Split-Path -Parent $PSScriptRoot
  $hub = Join-Path $root '.tools\hf-cache\hub'
}
$root = Join-Path $hub ("models--" + ($repo -replace '/', '--'))

function Get-WithRetry([string]$url, [int]$tries = 6) {
  for ($i = 1; $i -le $tries; $i++) {
    try { return Invoke-WebRequest -Uri $url -TimeoutSec 60 -UseBasicParsing }
    catch {
      Write-Host "  retry $i/$tries failed: $($_.Exception.Message.Split([char]10)[0])"
      Start-Sleep -Seconds (3 * $i)
    }
  }
  throw "无法下载：$url"
}

Write-Host "查询仓库信息：$repo"
$info = (Get-WithRetry "$base/api/models/$repo").Content | ConvertFrom-Json
$sha = $info.sha
$files = $info.siblings | ForEach-Object { $_.rfilename }
Write-Host "版本 $sha，文件：$($files -join ', ')"

$snap = Join-Path $root ("snapshots\" + $sha)
New-Item -ItemType Directory -Force -Path $snap | Out-Null

foreach ($f in $files) {
  $dest = Join-Path $snap ($f -replace '/', '\')
  $dir = Split-Path $dest -Parent
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  if ((Test-Path $dest) -and (Get-Item $dest).Length -gt 0) {
    Write-Host "已存在，跳过：$f"
    continue
  }
  $url = "$base/$repo/resolve/$sha/$f"
  Write-Host "下载 $f ..."
  for ($i = 1; $i -le 6; $i++) {
    try {
      Invoke-WebRequest -Uri $url -OutFile $dest -TimeoutSec 600 -UseBasicParsing
      break
    } catch {
      Write-Host "  retry $i/6: $($_.Exception.Message.Split([char]10)[0])"
      Start-Sleep -Seconds (3 * $i)
      if ($i -eq 6) { throw }
    }
  }
}

New-Item -ItemType Directory -Force -Path (Join-Path $root 'refs') | Out-Null
Set-Content -Path (Join-Path $root 'refs\main') -Value $sha -NoNewline -Encoding ascii
Write-Host "MODEL_READY $repo -> $snap"
