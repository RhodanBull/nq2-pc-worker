@echo off
setlocal
cd /d "%~dp0\..\.."
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0nq2-telegram-bridge.ps1" %*
exit /b %ERRORLEVEL%
