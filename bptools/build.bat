@echo off
rem Builds dist\BPTOOLS.zip to give to colleagues: BPTOOLS.bundle (bptools.lsp, the template
rem BPTOOLS.dwt, the parts library made by src\make_parts.ps1, the ribbon tab, the guide) plus what every plugin's zip has: install.bat,
rem uninstall.bat, the messages.json they read, the shared updater and the guide guide.html
rem (..\common\package.ps1). The same files are left unzipped in dist\.
rem Needs AutoCAD 2024, for the template and the ribbon.
setlocal
set SRC=%~dp0src
set DIST=%~dp0dist
set COMMON=%~dp0..\common
set WORK=%TEMP%\bptools-build

if not exist "%WORK%" mkdir "%WORK%"
rem First, since it is quick: the messages against the code, the joined bptools.lsp and messages.json.
py -3 "%COMMON%\build_lisp.py" "%~dp0." "%WORK%\lisp" || goto :fail

if exist "%DIST%" rmdir /s /q "%DIST%"
mkdir "%DIST%\BPTOOLS.bundle\Contents" || goto :fail
copy /y "%SRC%\PackageContents.xml" "%DIST%\BPTOOLS.bundle\" >nul || goto :fail
copy /y "%WORK%\lisp\bptools.lsp" "%DIST%\BPTOOLS.bundle\Contents\" >nul || goto :fail
mkdir "%DIST%\BPTOOLS.bundle\Contents\parts" || goto :fail
if exist "%SRC%\parts\*.dwg" copy /y "%SRC%\parts\*.dwg" "%DIST%\BPTOOLS.bundle\Contents\parts\" >nul
if exist "%DIST%\BPTOOLS.bundle\Contents\parts\library.dwg" del "%DIST%\BPTOOLS.bundle\Contents\parts\library.dwg"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SRC%\make_template.ps1" -Contents "%DIST%\BPTOOLS.bundle\Contents" || goto :fail
powershell -NoProfile -ExecutionPolicy Bypass -File "%SRC%\ribbon.ps1" -Out "%DIST%\BPTOOLS.bundle\Contents" || goto :fail
powershell -NoProfile -ExecutionPolicy Bypass -File "%COMMON%\package.ps1" -Plugin "%~dp0." -Built "%WORK%\lisp" -Dist "%DIST%" || goto :fail

echo.
echo Built %DIST%\BPTOOLS.zip
echo To install on this PC, close AutoCAD and run dist\install.bat.
goto :eof

:fail
echo Build failed.
exit /b 1
