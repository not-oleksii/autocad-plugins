@echo off
rem Double-click (or use the Start menu entry the installer adds) to update PDFALL from GitHub.
rem It works from %TEMP% and runs everything on one line: the update replaces this folder and this
rem file, and cmd reads a .bat file line by line as it goes.
cd /d "%TEMP%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0update.ps1" & echo. & pause & exit /b
