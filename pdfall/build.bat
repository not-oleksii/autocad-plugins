@echo off
rem Builds dist\PDFALL.zip to give to colleagues: PDFALL.bundle (pdfall.lsp, merge.exe, PDFALL.pc3,
rem the frame templates, the ribbon tab, the updater, the guide) plus install.bat, uninstall.bat,
rem the messages.json they read and the guide Instruktsiia.html.
rem The same files are left unzipped in dist\.
rem Needs once: py -3 -m pip install pyinstaller pypdf
setlocal
set SRC=%~dp0src
set DIST=%~dp0dist
set WORK=%TEMP%\pdfall-build

if not exist "%WORK%" mkdir "%WORK%"
rem First, since it is quick: messages.json against the code, and the joined pdfall.lsp.
py -3 "%SRC%\build_lisp.py" "%WORK%\pdfall.lsp" || goto :fail
py -3 -m PyInstaller --noconfirm --onefile --console --name merge --distpath "%WORK%\exe" --workpath "%WORK%" --specpath "%WORK%" --add-data "%SRC%\messages.json;." "%SRC%\merge_blueprints.py" || goto :fail

if exist "%DIST%" rmdir /s /q "%DIST%"
mkdir "%DIST%\PDFALL.bundle\Contents" || goto :fail
rem The updater and the guide ride in the bundle too, for their Start menu entries.
for %%f in (PackageContents.xml update.bat update.ps1 messages.json Instruktsiia.html) do (
  copy /y "%SRC%\%%f" "%DIST%\PDFALL.bundle\" >nul || goto :fail
)
for %%f in ("%WORK%\pdfall.lsp" "%SRC%\PDFALL.pc3" "%WORK%\exe\merge.exe") do (
  copy /y "%%~f" "%DIST%\PDFALL.bundle\Contents\" >nul || goto :fail
)
copy /y "%SRC%\templates\*.dwg" "%DIST%\PDFALL.bundle\Contents\" >nul || goto :fail
powershell -NoProfile -ExecutionPolicy Bypass -File "%SRC%\ribbon.ps1" -Out "%DIST%\PDFALL.bundle\Contents" || goto :fail
for %%f in (install.bat install.ps1 uninstall.bat messages.json Instruktsiia.html) do (
  copy /y "%SRC%\%%f" "%DIST%\" >nul || goto :fail
)
tar -a -c -f "%DIST%\PDFALL.zip" -C "%DIST%" Instruktsiia.html PDFALL.bundle install.bat install.ps1 uninstall.bat messages.json || goto :fail

echo.
echo Built %DIST%\PDFALL.zip
echo To install on this PC, close AutoCAD and run dist\install.bat.
goto :eof

:fail
echo Build failed.
exit /b 1
