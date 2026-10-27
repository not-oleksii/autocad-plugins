# AutoCAD plugins

AutoCAD 2024 plugins, one folder each. Every plugin builds a zip with an `install.bat` that colleagues double-click.

| Plugin | What it does |
| --- | --- |
| [pdfall](pdfall/README.md) (in Ukrainian; the step-by-step guide for colleagues is `Instruktsiia.html` in the zip; developers: [DEVELOPING.md](pdfall/DEVELOPING.md); changes: [CHANGELOG.md](pdfall/CHANGELOG.md)) | `PDFALL`: plots every лист, специфікація and текстовий документ in Model space (any A0–A5 рамка) to PDF, with the day's date in its Дата cell, and merges them per марка. `PDFNUM`: fills in empty Аркуш/Аркушів cells. `PDFLIST`, `PDFSPEC`: paste an empty рамка; `PDFSETTINGS`: which document `PDFLIST` pastes and name-cell text they paste |

## Download

Take the zip from the newest release of the plugin on the [Releases](https://github.com/not-oleksii/autocad-plugins/releases) page. Installing any plugin also installs **Оновити плагіни AutoCAD** in the Start menu, which updates every installed plugin from there and installs the others ([docs/adr/0001](docs/adr/0001-one-updater-for-every-plugin.md)).

## Contributing

Work on a branch and open a pull request; its template asks for the version impact, a changelog line and the test plan. This repository is public, so never commit real drawings, PDFs or names from title blocks: each plugin keeps its sample drawings in an `examples\` folder that git ignores.

## Adding a plugin

Give it its own folder with the same layout as `pdfall`:

- `src\` holds the plugin itself: `plugin.json` (its name, LISP prefix and debug command), `PackageContents.xml`, `lsp\*.lsp` (one module per file, numbered; `00-settings.lsp` first, with `*<name>-version*`), `messages.json` and `ribbon.ps1`;
- `build.bat` builds the plugin's `<NAME>.bundle` in `dist\` and ends with `common\package.ps1`, which adds the installer and the updater and makes `dist\<NAME>.zip`;
- `release.ps1` runs `common\release.ps1 -Plugin <folder>`;
- `tests\` holds the tests;
- `CHANGELOG.md` lists what changed in each version, `GLOSSARY.md` its terms (see [CONTEXT-MAP.md](CONTEXT-MAP.md)) and `docs\adr` its decisions.

What every plugin shares is in `common\` ([docs/adr/0002](docs/adr/0002-share-code-between-plugins.md)): the LISP helpers (`common\lsp`, built into each plugin under its own prefix), the texts they show (`common\messages.json`), the build check, the installer, the updater, the ribbon builder and the release script. Put a helper there only when it holds no plugin's knowledge; a plugin that needs another's knowledge calls its public function ([docs/adr/0003](docs/adr/0003-plugins-talk-through-one-function.md)).

It installs as a `<NAME>.bundle` in `%APPDATA%\Autodesk\ApplicationPlugins`; see [pdfall/docs/adr/0002-install-as-a-bundle.md](pdfall/docs/adr/0002-install-as-a-bundle.md). Tag its releases `<name>-v<version>` with the zip `<NAME>-<version>.zip`: that is how the updater finds it ([docs/adr/0001](docs/adr/0001-one-updater-for-every-plugin.md)).
