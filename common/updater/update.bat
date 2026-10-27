@echo off
rem The shared updater's Start menu entry runs this to update the plugins from GitHub.
rem It works from %TEMP% and runs everything on one line: an install overwrites this folder and this
rem file, and cmd reads a .bat file line by line as it goes.
cd /d "%TEMP%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0update.ps1" & echo. & pause & exit /b
