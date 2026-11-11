@echo off
setlocal
cd /d "%~dp0"
title Afraz Cost Calculator - Keep this window open
where powershell.exe >nul 2>&1
if errorlevel 1 (
  echo Windows PowerShell was not found. Windows 10 or 11 with PowerShell is required.
  pause
  exit /b 1
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0server.ps1"
echo.
echo The program has stopped. Press any key to close.
pause >nul
