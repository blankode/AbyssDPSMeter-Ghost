@echo off
setlocal

net session >nul 2>&1
if not "%errorlevel%"=="0" (
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Uninstall-Aion2MeterWatcher.ps1"
echo.
pause
