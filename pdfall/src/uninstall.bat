@echo off
rem Double-click to remove PDFALL. Close AutoCAD first.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" -Uninstall
echo.
pause
