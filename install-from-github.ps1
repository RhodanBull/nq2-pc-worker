param(
  [string]$RepoRoot = ".",
  [string]$RepoZipUrl = "https://github.com/RhodanBull/nq2-pc-worker/archive/refs/heads/main.zip"
)

$ErrorActionPreference = "Stop"
$targetRoot = (Resolve-Path $RepoRoot).Path
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("nq2-pc-worker-" + [Guid]::NewGuid().ToString("N"))
$zipPath = Join-Path $tempRoot "nq2-pc-worker.zip"
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

try {
  Write-Host "Downloading NQ2 PC Worker from GitHub..."
  Invoke-WebRequest -UseBasicParsing -Uri $RepoZipUrl -OutFile $zipPath
  Expand-Archive -Force -Path $zipPath -DestinationPath $tempRoot
  $source = Get-ChildItem -Path $tempRoot -Directory | Where-Object { $_.Name -like "nq2-pc-worker-*" } | Select-Object -First 1
  if (!$source) { throw "Could not find extracted nq2-pc-worker folder in $tempRoot" }
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $source.FullName "install-nq2-worker.ps1") -RepoRoot $targetRoot
} finally {
  Remove-Item -Recurse -Force $tempRoot -ErrorAction SilentlyContinue
}
