param(
  [string]$RepoRoot = ""
)

$ErrorActionPreference = "Stop"
if (!$RepoRoot) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path } else { $RepoRoot = (Resolve-Path $RepoRoot).Path }
Set-Location $RepoRoot

$EnvPath = Join-Path $RepoRoot "config\nq2-worker.env"
$StateDir = Join-Path $RepoRoot "out\nq2_worker"
$OffsetPath = Join-Path $StateDir "telegram_offset.txt"
$BridgeLog = Join-Path $RepoRoot "logs\nq2-telegram-bridge.log"
$Worker = Join-Path $PSScriptRoot "nq2-worker.ps1"
New-Item -ItemType Directory -Force -Path $StateDir,(Split-Path $BridgeLog) | Out-Null

function Log { param([string]$Message) Add-Content -Path $BridgeLog -Value ("[{0}] {1}" -f ((Get-Date).ToUniversalTime().ToString("o")), $Message) }
function Import-EnvFile {
  param([string]$Path)
  if (!(Test-Path $Path)) { throw "Missing $Path. Copy config\nq2-worker.env.example to config\nq2-worker.env and fill token/chat id." }
  Get-Content $Path | ForEach-Object {
    $line = $_.Trim()
    if (!$line -or $line.StartsWith("#") -or !$line.Contains("=")) { return }
    $idx = $line.IndexOf("=")
    $name = $line.Substring(0,$idx).Trim()
    $value = $line.Substring($idx+1).Trim().Trim('"')
    [Environment]::SetEnvironmentVariable($name,$value,"Process")
  }
}
function Send-Telegram {
  param([string]$ChatId, [string]$Text)
  if ($Text.Length -gt 3500) { $Text = $Text.Substring(0,3500) + "`n...[truncated]" }
  $uri = "https://api.telegram.org/bot$($env:NQ2_TELEGRAM_BOT_TOKEN)/sendMessage"
  Invoke-RestMethod -Method Post -Uri $uri -Body @{ chat_id=$ChatId; text=$Text } | Out-Null
}
function Run-Worker {
  param([string[]]$WorkerArgs)
  $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Worker @WorkerArgs 2>&1
  return (($out | ForEach-Object { $_.ToString() }) -join "`n")
}
function Handle-Command {
  param([string]$ChatId, [string]$Text)
  $defaultWorkers = if ($env:NQ2_DEFAULT_WORKERS) { [int]$env:NQ2_DEFAULT_WORKERS } else { 8 }
  $fastWorkers = if ($env:NQ2_FAST_WORKERS) { [int]$env:NQ2_FAST_WORKERS } else { 12 }
  $topN = if ($env:NQ2_TOP_N) { [int]$env:NQ2_TOP_N } else { 30 }
  switch -Regex ($Text.Trim()) {
    '^/nq2_status' { return Run-Worker @("status") }
    '^/nq2_doctor' { return Run-Worker @("doctor") }
    '^/nq2_quick' { return Run-Worker @("quick","-Workers",[string]$defaultWorkers,"-TopN",[string]$topN) }
    '^/nq2_shortlist' { return Run-Worker @("shortlist","-Workers",[string]$fastWorkers,"-TopN",[string]$topN) }
    '^/nq2_full' { return Run-Worker @("full","-Workers",[string]$fastWorkers,"-TopN",[string]$topN) }
    '^/nq2_stop' { return Run-Worker @("stop") }
    '^/nq2_tail' { return Run-Worker @("tail","-Lines","80") }
    '^/nq2_report' { return Run-Worker @("report","-Lines","80") }
    default { return "Unknown command. Use /nq2_status, /nq2_quick, /nq2_shortlist, /nq2_stop, /nq2_tail, /nq2_report" }
  }
}

Import-EnvFile $EnvPath
if (!$env:NQ2_TELEGRAM_BOT_TOKEN) { throw "NQ2_TELEGRAM_BOT_TOKEN is empty in $EnvPath" }
if (!$env:NQ2_TELEGRAM_ALLOWED_CHAT_ID) { throw "NQ2_TELEGRAM_ALLOWED_CHAT_ID is empty in $EnvPath" }
$pollSeconds = if ($env:NQ2_POLL_SECONDS) { [int]$env:NQ2_POLL_SECONDS } else { 3 }
$offset = 0
if (Test-Path $OffsetPath) { try { $offset = [int](Get-Content $OffsetPath -Raw).Trim() } catch { $offset = 0 } }
Log "bridge started repo=$RepoRoot allowed_chat=$($env:NQ2_TELEGRAM_ALLOWED_CHAT_ID)"
Write-Host "NQ2 Telegram bridge running. Log: $BridgeLog"

while ($true) {
  try {
    $uri = "https://api.telegram.org/bot$($env:NQ2_TELEGRAM_BOT_TOKEN)/getUpdates?timeout=20&offset=$offset"
    $resp = Invoke-RestMethod -Method Get -Uri $uri
    foreach ($u in $resp.result) {
      $offset = [int]$u.update_id + 1
      Set-Content -Path $OffsetPath -Value $offset
      $msg = $u.message
      if (!$msg -or !$msg.text) { continue }
      $chatId = [string]$msg.chat.id
      if ($chatId -ne [string]$env:NQ2_TELEGRAM_ALLOWED_CHAT_ID) { Log "ignored unauthorized chat=$chatId"; continue }
      if (!$msg.text.StartsWith("/nq2_")) { continue }
      Log "command chat=$chatId text=$($msg.text)"
      $answer = Handle-Command -ChatId $chatId -Text $msg.text
      Send-Telegram -ChatId $chatId -Text $answer
    }
  } catch {
    Log ("ERROR " + $_.Exception.Message)
    Start-Sleep -Seconds 5
  }
  Start-Sleep -Seconds $pollSeconds
}
