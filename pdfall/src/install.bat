@echo off
rem Double-click to install or update PDFALL. Close AutoCAD first.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
echo.
pause
