# AutoCAD plugins

AutoCAD 2024 plugins, one folder each. Every plugin builds a zip with an `install.bat` that colleagues double-click.

| Plugin | What it does |
| --- | --- |
| [pdfall](pdfall/README.md) (in Ukrainian; the step-by-step guide for colleagues is `Instruktsiia.html` in the zip; developers: [DEVELOPING.md](pdfall/DEVELOPING.md); changes: [CHANGELOG.md](pdfall/CHANGELOG.md)) | `PDFALL`: plots every лист, специфікація and текстовий документ in Model space (any A0–A5 рамка) to PDF, with the day's date in its Дата cell, and merges them per марка. `PDFNUM`: fills in empty Аркуш/Аркушів cells. `PDFLIST`, `PDFSPEC`, `PDFTEXT`: paste an empty рамка; `PDFSETTINGS`: which лист format and name-cell text they paste |

## Download

Take the zip from the newest release of the plugin on the [Releases](https://github.com/not-oleksii/autocad-plugins/releases) page. Once installed, PDFALL updates itself from there through **Оновити PDFALL** in the Start menu.

## Contributing

Work on a branch and open a pull request; its template asks for the version impact, a changelog line and the test plan. This repository is public, so never commit real drawings, PDFs or names from title blocks: each plugin keeps its sample drawings in an `examples\` folder that git ignores.

## Adding a plugin

Give it its own folder with the same layout as `pdfall`:

- `src\` holds the plugin itself and its `PackageContents.xml`;
- `build.bat` builds `dist\<NAME>.zip`;
- `tests\` holds the tests;
- `CHANGELOG.md` lists what changed in each version.

Install it as a `<NAME>.bundle` in `%APPDATA%\Autodesk\ApplicationPlugins`; see [pdfall/docs/adr/0002-install-as-a-bundle.md](pdfall/docs/adr/0002-install-as-a-bundle.md). Tag its releases `<name>-v<version>`, so that they don't mix with another plugin's ([pdfall/docs/adr/0007-update-from-github-releases.md](pdfall/docs/adr/0007-update-from-github-releases.md)).
