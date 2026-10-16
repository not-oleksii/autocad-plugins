# Install as a per-user bundle that trusts itself

PDFALL is installed as `PDFALL.bundle` in `%APPDATA%\Autodesk\ApplicationPlugins`, and `install.ps1` adds the bundle's `Contents` folder to `TRUSTEDPATHS` in every AutoCAD 2024+ profile in the registry. AutoCAD trusts plug-ins without asking only from `%ProgramFiles%\Autodesk\ApplicationPlugins`, but writing there needs admin rights that colleagues may not have. The alternatives (the Startup Suite plus adding a Trusted Location by hand, or answering "Load" at every start) were exactly the manual steps colleagues kept getting wrong. The bundle carries `merge.exe` (the Python merge packed with PyInstaller), so nobody needs Python.

## Consequences

- AutoCAD must be closed while installing: it rewrites its profile in the registry on exit and would overwrite the change.
- A profile created after installing doesn't trust the bundle until `install.bat` is run again.
- The installer removes `pdfall.lsp` from the Startup Suite, because an older copy loaded there would replace the bundle's command.
