param(
  [string]$RepoRoot = "."
)

$ErrorActionPreference = "Stop"
$SourceRoot = $PSScriptRoot
$TargetRoot = (Resolve-Path $RepoRoot).Path

if (!(Test-Path (Join-Path $TargetRoot "scripts"))) {
  throw "Target does not look like nq-trading-bot repo: missing scripts\ under $TargetRoot"
}
if (!(Test-Path (Join-Path $TargetRoot "scripts\research_fast_sweep_runner.py"))) {
  throw "Target repo is missing scripts\research_fast_sweep_runner.py. Update/copy the NQ repo first."
}

$targetScripts = Join-Path $TargetRoot "scripts\windows"
$targetConfig = Join-Path $TargetRoot "config"
New-Item -ItemType Directory -Force -Path $targetScripts,$targetConfig | Out-Null

Copy-Item -Force (Join-Path $SourceRoot "scripts\windows\nq2-worker.ps1") (Join-Path $targetScripts "nq2-worker.ps1")
Copy-Item -Force (Join-Path $SourceRoot "scripts\windows\nq2-worker.cmd") (Join-Path $targetScripts "nq2-worker.cmd")
Copy-Item -Force (Join-Path $SourceRoot "scripts\windows\nq2-telegram-bridge.ps1") (Join-Path $targetScripts "nq2-telegram-bridge.ps1")
Copy-Item -Force (Join-Path $SourceRoot "scripts\windows\nq2-telegram-bridge.cmd") (Join-Path $targetScripts "nq2-telegram-bridge.cmd")

$envExample = Join-Path $targetConfig "nq2-worker.env.example"
Copy-Item -Force (Join-Path $SourceRoot "config\nq2-worker.env.example") $envExample

Write-Host "Installed NQ2 worker into $TargetRoot" -ForegroundColor Green
Write-Host "Next:"
Write-Host "  cd $TargetRoot"
Write-Host "  .\scripts\windows\nq2-worker.cmd doctor"
Write-Host "  .\scripts\windows\nq2-worker.cmd quick -Workers 8"
Write-Host "Optional Telegram config template: $envExample"
