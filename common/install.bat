@echo off
rem Double-click to install or update the plugin of this zip. Close AutoCAD first.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
echo.
pause
