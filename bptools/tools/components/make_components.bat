@echo off
rem Turns the drawings of the components library into parts for BPPART: src\parts\components and
rem src\lsp&-components.lsp (see DEVELOPING.md, "Parts from the components library").
rem   make_components.bat "D:\...\components library" [--only=<regex>]
rem The first run sets up Python with ezdxf in %LOCALAPPDATA%ptools-step-views, as step-views does.
setlocal
set VENV=%LOCALAPPDATA%ptools-step-views
if not exist "%VENV%\Scripts\python.exe" (
  py -3 -m venv "%VENV%" || goto :fail
  "%VENV%\Scripts\python.exe" -m pip install --quiet -r "%~dp0..\step-viewsequirements.txt" || goto :fail
)
set PYTHONIOENCODING=utf-8
"%VENV%\Scripts\python.exe" "%~dp0make_components.py" %* || goto :fail
goto :eof

:fail
echo Failed.
exit /b 1
