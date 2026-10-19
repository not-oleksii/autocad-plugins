# AutoCAD plugins

AutoCAD 2024 plugins, one folder each. Every plugin builds a zip with an `install.bat` that colleagues double-click.

| Plugin | What it does |
| --- | --- |
| [pdfall](pdfall) | `PDFALL`: plots every лист and специфікація in Model space to PDF and merges them per марка. `PDFNUM`: fills in empty Аркуш/Аркушів cells. `PDFLIST`, `PDFSPEC`: paste an empty лист or специфікація рамка |

## Adding a plugin

Give it its own folder with the same layout as `pdfall`:

- `src\` holds the plugin itself and its `PackageContents.xml`;
- `build.bat` builds `dist\<NAME>.zip`;
- `tests\` holds the tests.

Install it as a `<NAME>.bundle` in `%APPDATA%\Autodesk\ApplicationPlugins`; see [pdfall/docs/adr/0002-install-as-a-bundle.md](pdfall/docs/adr/0002-install-as-a-bundle.md).
