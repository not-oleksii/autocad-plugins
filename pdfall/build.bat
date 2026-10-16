@echo off
rem Builds dist\PDFALL.zip to give to colleagues: PDFALL.bundle (pdfall.lsp, merge.exe, PDFALL.pc3)
rem plus install.bat and uninstall.bat. The same files are left unzipped in dist\.
rem Needs once: py -3 -m pip install pyinstaller pypdf
setlocal
set SRC=%~dp0src
set DIST=%~dp0dist
set WORK=%TEMP%\pdfall-build

py -3 -m PyInstaller --noconfirm --onefile --console --name merge --distpath "%WORK%\exe" --workpath "%WORK%" --specpath "%WORK%" "%SRC%\merge_blueprints.py" || goto :fail

if exist "%DIST%" rmdir /s /q "%DIST%"
mkdir "%DIST%\PDFALL.bundle\Contents" || goto :fail
copy /y "%SRC%\PackageContents.xml" "%DIST%\PDFALL.bundle\" >nul || goto :fail
for %%f in ("%SRC%\pdfall.lsp" "%SRC%\PDFALL.pc3" "%WORK%\exe\merge.exe") do (
  copy /y "%%~f" "%DIST%\PDFALL.bundle\Contents\" >nul || goto :fail
)
for %%f in (install.bat install.ps1 uninstall.bat) do (
  copy /y "%SRC%\%%f" "%DIST%\" >nul || goto :fail
)
tar -a -c -f "%DIST%\PDFALL.zip" -C "%DIST%" PDFALL.bundle install.bat install.ps1 uninstall.bat || goto :fail

echo.
echo Built %DIST%\PDFALL.zip
echo To install on this PC, close AutoCAD and run dist\install.bat.
goto :eof

:fail
echo Build failed.
exit /b 1
