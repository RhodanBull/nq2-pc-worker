# NQ2 PC Worker

Safe Windows control scripts for running the NQ/Bot2 research sweeps on your local PC.

The worker does **not** place trades and only runs the existing research command
`scripts/research_fast_sweep_runner.py` inside your local `nq-trading-bot` repo.

## Install into your existing NQ repo

Open PowerShell and run:

```powershell
cd C:\Users\yanni\Documents\VSC\nq-trading-bot
powershell -ExecutionPolicy Bypass -File C:\path\to\nq2-pc-worker\install-nq2-worker.ps1 -RepoRoot .
```

Or download this repository as ZIP from GitHub, extract it, and run the same installer.

The installer copies:

- `scripts\windows\nq2-worker.ps1`
- `scripts\windows\nq2-worker.cmd`
- optional Telegram bridge files

## Basic usage

From your `nq-trading-bot` repo:

```powershell
.\scripts\windows\nq2-worker.cmd doctor
.\scripts\windows\nq2-worker.cmd quick -Workers 8
.\scripts\windows\nq2-worker.cmd status
.\scripts\windows\nq2-worker.cmd tail -Lines 80
.\scripts\windows\nq2-worker.cmd report
.\scripts\windows\nq2-worker.cmd stop
```

Recommended first run:

```powershell
.\scripts\windows\nq2-worker.cmd quick -Workers 8
```

Then, if stable:

```powershell
.\scripts\windows\nq2-worker.cmd shortlist -Workers 12 -TopN 30
```

## Files written by the worker

Inside your NQ repo:

- `logs\nq2-worker.log` — live stdout/stderr log
- `out\nq2_worker\status.json` — machine-readable status
- `out\evaluation\fast_sweep_runner.md` — latest result report from the research runner
- `out\evaluation\fast_sweep_runner.json` — latest result payload

## Optional Telegram bridge

Create a separate BotFather bot/token for this worker, then create:

```powershell
Copy-Item .\config\nq2-worker.env.example .\config\nq2-worker.env
notepad .\config\nq2-worker.env
```

Fill:

```env
NQ2_TELEGRAM_BOT_TOKEN=123456:your-token
NQ2_TELEGRAM_ALLOWED_CHAT_ID=515239321
NQ2_DEFAULT_WORKERS=8
NQ2_FAST_WORKERS=12
```

Start the bridge:

```powershell
.\scripts\windows\nq2-telegram-bridge.cmd
```

Supported Telegram commands:

- `/nq2_status`
- `/nq2_doctor`
- `/nq2_quick`
- `/nq2_shortlist`
- `/nq2_full`
- `/nq2_stop`
- `/nq2_tail`
- `/nq2_report`

Security notes:

- Only `NQ2_TELEGRAM_ALLOWED_CHAT_ID` is accepted.
- Commands are allowlisted; there is no arbitrary shell execution.
- Keep `config\nq2-worker.env` private and out of Git.
