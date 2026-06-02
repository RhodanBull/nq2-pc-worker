@echo off
setlocal
cd /d "%~dp0\..\.."
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0nq2-worker.ps1" %*
exit /b %ERRORLEVEL%
