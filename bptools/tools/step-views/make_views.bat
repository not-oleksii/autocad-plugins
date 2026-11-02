@echo off
rem Makes the 10-view DWG of every STEP model in <folder>\3D model that has none in <folder>\dwg blueprints.
rem   make_views.bat "D:\...\components library\connectors" [--dry] [--only=<regex>]
rem The first run sets up Python with OpenCascade and ezdxf in %LOCALAPPDATA%\bptools-step-views.
setlocal
set VENV=%LOCALAPPDATA%\bptools-step-views
if not exist "%VENV%\Scripts\python.exe" (
  py -3 -m venv "%VENV%" || goto :fail
  "%VENV%\Scripts\python.exe" -m pip install --quiet -r "%~dp0requirements.txt" || goto :fail
)
"%VENV%\Scripts\python.exe" "%~dp0make_views.py" %* || goto :fail
goto :eof

:fail
echo Failed.
exit /b 1
