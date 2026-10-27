@echo off
rem Double-click to remove the plugin of this zip. Close AutoCAD first.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" -Uninstall
echo.
pause
