@echo off
rem Report naming and title-block problems in PDFs without changing anything: drag folders onto this file.
chcp 65001 >nul
py -3 "%~dp0src\merge_blueprints.py" --check %*
echo.
pause
