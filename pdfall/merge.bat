@echo off
rem Merge PDFs by hand with the Python source: drag folders onto this file.
rem (PDFALL itself runs the installed merge.exe.)
chcp 65001 >nul
py -3 "%~dp0src\merge_blueprints.py" %*
echo.
pause
