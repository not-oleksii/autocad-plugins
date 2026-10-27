@echo off
rem Builds dist\PDFALL.zip to give to colleagues: PDFALL.bundle (pdfall.lsp, merge.exe, PDFALL.pc3,
rem the frame templates, the ribbon tab, the guide) plus what every plugin's zip has: install.bat,
rem uninstall.bat, the messages.json they read, the shared updater and the guide guide.html
rem (..\common\package.ps1).
rem The same files are left unzipped in dist\.
rem Needs once: py -3 -m pip install pyinstaller pypdf
setlocal
set SRC=%~dp0src
set DIST=%~dp0dist
set COMMON=%~dp0..\common
set WORK=%TEMP%\pdfall-build

if not exist "%WORK%" mkdir "%WORK%"
rem First, since it is quick: the messages against the code, the joined pdfall.lsp and messages.json.
py -3 "%COMMON%\build_lisp.py" "%~dp0." "%WORK%\lisp" || goto :fail
py -3 -m PyInstaller --noconfirm --onefile --console --name merge --distpath "%WORK%\exe" --workpath "%WORK%" --specpath "%WORK%" --add-data "%WORK%\lisp\messages.json;." "%SRC%\merge_blueprints.py" || goto :fail

if exist "%DIST%" rmdir /s /q "%DIST%"
mkdir "%DIST%\PDFALL.bundle\Contents" || goto :fail
copy /y "%SRC%\PackageContents.xml" "%DIST%\PDFALL.bundle\" >nul || goto :fail
for %%f in ("%WORK%\lisp\pdfall.lsp" "%SRC%\PDFALL.pc3" "%WORK%\exe\merge.exe") do (
  copy /y "%%~f" "%DIST%\PDFALL.bundle\Contents\" >nul || goto :fail
)
copy /y "%SRC%\templates\*.dwg" "%DIST%\PDFALL.bundle\Contents\" >nul || goto :fail
powershell -NoProfile -ExecutionPolicy Bypass -File "%SRC%\ribbon.ps1" -Out "%DIST%\PDFALL.bundle\Contents" || goto :fail
powershell -NoProfile -ExecutionPolicy Bypass -File "%COMMON%\package.ps1" -Plugin "%~dp0." -Built "%WORK%\lisp" -Dist "%DIST%" || goto :fail

echo.
echo Built %DIST%\PDFALL.zip
echo To install on this PC, close AutoCAD and run dist\install.bat.
goto :eof

:fail
echo Build failed.
exit /b 1
