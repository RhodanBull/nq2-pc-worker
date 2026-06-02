param(
  [Parameter(Position=0)]
  [ValidateSet("status","doctor","start","quick","shortlist","full","stop","tail","report","__run")]
  [string]$Command = "status",
  [ValidateSet("quick","shortlist","full")]
  [string]$Stage = "quick",
  [int]$Workers = 0,
  [int]$TopN = 30,
  [int]$Lines = 80,
  [string]$RepoRoot = "",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
if (!$RepoRoot) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path } else { $RepoRoot = (Resolve-Path $RepoRoot).Path }
Set-Location $RepoRoot

$StateDir = Join-Path $RepoRoot "out\nq2_worker"
$LogDir = Join-Path $RepoRoot "logs"
$StatusPath = Join-Path $StateDir "status.json"
$LogPath = Join-Path $LogDir "nq2-worker.log"
$Runner = Join-Path $RepoRoot "scripts\research_fast_sweep_runner.py"
New-Item -ItemType Directory -Force -Path $StateDir,$LogDir | Out-Null

function NowIso { (Get-Date).ToUniversalTime().ToString("o") }
function Write-WorkerLog { param([string]$Message) Add-Content -Path $LogPath -Value ("[{0}] {1}" -f (NowIso), $Message) }
function Write-StatusObject {
  param([hashtable]$Data)
  $Data["updated_at"] = NowIso
  $tmp = "$StatusPath.tmp"
  ($Data | ConvertTo-Json -Depth 8) | Set-Content -Path $tmp -Encoding UTF8
  Move-Item -Force $tmp $StatusPath
}
function Read-StatusObject {
  if (!(Test-Path $StatusPath)) { return $null }
  try { return Get-Content $StatusPath -Raw | ConvertFrom-Json } catch { return $null }
}
function Test-PidRunning { param([int]$Pid) if ($Pid -le 0) { return $false }; return [bool](Get-Process -Id $Pid -ErrorAction SilentlyContinue) }
function Get-PythonCommand {
  $localPy = Join-Path $RepoRoot ".venv\Scripts\python.exe"
  if (Test-Path $localPy) { return $localPy }
  $cmd = Get-Command python -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  $cmd3 = Get-Command python3 -ErrorAction SilentlyContinue
  if ($cmd3) { return $cmd3.Source }
  throw "Python not found. Create .venv or install Python 3.11+."
}
function Stop-ProcessTree {
  param([int]$ProcessId)
  $children = Get-CimInstance Win32_Process -Filter "ParentProcessId=$ProcessId" -ErrorAction SilentlyContinue
  foreach ($child in $children) { Stop-ProcessTree -ProcessId ([int]$child.ProcessId) }
  Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
}
function Get-CurrentStatus {
  $s = Read-StatusObject
  if (!$s) { return [ordered]@{ state="idle"; running=$false; status_path=$StatusPath; log_path=$LogPath } }
  $running = $false
  if ($s.pid) { $running = Test-PidRunning -Pid ([int]$s.pid) }
  if ($s.state -eq "running" -and !$running) { $s.state = "stale" }
  return $s
}
function Print-ObjectOrJson { param($Obj) if ($Json) { $Obj | ConvertTo-Json -Depth 8 } else { $Obj | Format-List | Out-String | Write-Output } }

if ($Command -eq "doctor") {
  $py = Get-PythonCommand
  $pyver = & $py -c "import sys; print(sys.version.split()[0])"
  $cpu = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
  $gitRev = "unknown"
  try { $gitRev = (& git rev-parse --short HEAD 2>$null).Trim() } catch { }
  $cache = Join-Path $RepoRoot "out\evaluation\fast_sweep_cache.json"
  $obj = [ordered]@{
    repo_root=$RepoRoot; runner_exists=(Test-Path $Runner); python=$py; python_version=$pyver;
    logical_processors=$cpu; git_rev=$gitRev; cache_exists=(Test-Path $cache);
    status_path=$StatusPath; log_path=$LogPath
  }
  Print-ObjectOrJson $obj
  exit 0
}

if ($Command -eq "status") { Print-ObjectOrJson (Get-CurrentStatus); exit 0 }

if ($Command -eq "tail") {
  if (!(Test-Path $LogPath)) { Write-Output "No log yet: $LogPath"; exit 0 }
  Get-Content $LogPath -Tail $Lines
  exit 0
}

if ($Command -eq "report") {
  $report = Join-Path $RepoRoot "out\evaluation\fast_sweep_runner.md"
  if (!(Test-Path $report)) { Write-Output "No report yet: $report"; exit 0 }
  Get-Content $report -TotalCount $Lines
  exit 0
}

if ($Command -eq "stop") {
  $s = Read-StatusObject
  if ($s -and $s.pid -and (Test-PidRunning -Pid ([int]$s.pid))) {
    Write-WorkerLog "stop requested for pid=$($s.pid)"
    Stop-ProcessTree -ProcessId ([int]$s.pid)
    Write-StatusObject @{ state="stopped"; running=$false; pid=$s.pid; stage=$s.stage; workers=$s.workers; top_n=$s.top_n; log_path=$LogPath; status_path=$StatusPath }
    Write-Output "Stopped NQ2 worker pid=$($s.pid)"
  } else {
    Write-Output "No running NQ2 worker found."
  }
  exit 0
}

if ($Command -in @("quick","shortlist","full")) { $Stage = $Command; $Command = "start" }

if ($Command -eq "start") {
  if (!(Test-Path $Runner)) { throw "Missing runner: $Runner" }
  if ($Workers -le 0) { $Workers = [Math]::Max(1, [Math]::Min(12, ((Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors - 2))) }
  $s = Read-StatusObject
  if ($s -and $s.pid -and (Test-PidRunning -Pid ([int]$s.pid))) {
    Write-Output "NQ2 worker already running pid=$($s.pid) stage=$($s.stage). Use stop first."
    exit 0
  }
  $script = $MyInvocation.MyCommand.Path
  $argList = @("-NoProfile","-ExecutionPolicy","Bypass","-File",$script,"__run","-Stage",$Stage,"-Workers",$Workers,"-TopN",$TopN,"-RepoRoot",$RepoRoot)
  Clear-Content -Path $LogPath -ErrorAction SilentlyContinue
  Write-WorkerLog "starting stage=$Stage workers=$Workers top_n=$TopN repo=$RepoRoot"
  $p = Start-Process -FilePath "powershell.exe" -ArgumentList $argList -WorkingDirectory $RepoRoot -PassThru -WindowStyle Minimized
  Write-StatusObject @{ state="running"; running=$true; pid=$p.Id; stage=$Stage; workers=$Workers; top_n=$TopN; started_at=(NowIso); log_path=$LogPath; status_path=$StatusPath; repo_root=$RepoRoot }
  Write-Output "Started NQ2 worker pid=$($p.Id) stage=$Stage workers=$Workers."
  Write-Output "Status: .\scripts\windows\nq2-worker.cmd status"
  Write-Output "Log:    .\scripts\windows\nq2-worker.cmd tail -Lines 80"
  exit 0
}

if ($Command -eq "__run") {
  $py = Get-PythonCommand
  $env:PYTHONPATH = "src"
  Write-WorkerLog "run begin python=$py stage=$Stage workers=$Workers top_n=$TopN"
  $argsForPy = @("scripts\research_fast_sweep_runner.py", "--stage", $Stage, "--workers", [string]$Workers, "--top-n", [string]$TopN)
  $exitCode = 0
  try {
    & $py @argsForPy 2>&1 | ForEach-Object { $line = $_.ToString(); if ($line.Length -gt 0) { Write-WorkerLog $line } }
    $exitCode = $LASTEXITCODE
  } catch {
    $exitCode = 1
    Write-WorkerLog ("ERROR " + $_.Exception.Message)
  }
  if ($exitCode -eq 0) {
    Write-WorkerLog "run completed successfully"
    Write-StatusObject @{ state="completed"; running=$false; exit_code=0; pid=$PID; stage=$Stage; workers=$Workers; top_n=$TopN; completed_at=(NowIso); log_path=$LogPath; status_path=$StatusPath; repo_root=$RepoRoot }
  } else {
    Write-WorkerLog "run failed exit_code=$exitCode"
    Write-StatusObject @{ state="failed"; running=$false; exit_code=$exitCode; pid=$PID; stage=$Stage; workers=$Workers; top_n=$TopN; completed_at=(NowIso); log_path=$LogPath; status_path=$StatusPath; repo_root=$RepoRoot }
  }
  exit $exitCode
}
