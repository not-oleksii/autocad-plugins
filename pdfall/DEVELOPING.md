# Developing PDFALL

How PDFALL is built, tested and released. What it does for colleagues is in the step-by-step guide [src/Instruktsiia.html](src/Instruktsiia.html) and, in short, [README.md](README.md) (both in Ukrainian), the terms in [GLOSSARY.md](GLOSSARY.md), and why it works this way in [docs/adr](docs/adr). PDFALL shares its installer, updater, release script and LISP helpers with the repository's other plugins; those live in [../common](../common), and why in [../docs/adr](../docs/adr).

## Files

```
src\lsp\*.lsp             the PDFALL, PDFNUM, PDFLIST, PDFSPEC and PDFSETTINGS commands, one module per file
src\messages.json         every text the commands, merge.exe and the ribbon show or look for
src\plugin.json           PDFALL's name, LISP prefix (pa) and debug command, for the shared build
src\merge_blueprints.py   builds загальний and загальний друк (shipped as merge.exe)
src\PDFALL.pc3            the PDF printer without the viewer
src\PackageContents.xml   tells AutoCAD how to load the bundle
src\ribbon.ps1            builds PDFALL.cuix (the ribbon tab) and its icons with ..\common\ribbon.ps1
src\templates\*.dwg       the 28 empty рамки that PDFLIST and PDFSPEC paste
src\make_templates.ps1    makes those templates and 62-previews.lsp from examples\formats (only when the forms change),
src\make_templates.lsp    with this LISP
src\Instruktsiia.html     the step-by-step guide for colleagues: zip root, bundle, Start menu (Інструкція PDFALL)
build.bat                 builds dist\PDFALL.zip
release.ps1               raises the version (-Prepare) and publishes a GitHub release, with ..\common\release.ps1
CHANGELOG.md              what changed in each version, in Ukrainian; also the release notes
tests\run.ps1             runs the built PDFNUM, PDFALL, merge.exe and the paste commands without opening AutoCAD,
                          on the sample drawing, the old drawings in examples\old and every template
tests\install.ps1         tests the installer and the updater against fake AutoCAD settings and a fake release list
merge.bat, check.bat      run the Python merge by hand (check.bat only reports problems)
..\.github                the pull request template and the CI check
```

Shared with the other plugins, in `..\common` ([../docs/adr/0002](../docs/adr/0002-share-code-between-plugins.md)):

```
lsp\*.lsp                 text, settings, debug log and dialog helpers, built into pdfall.lsp under the pa: prefix
messages.json             the texts of the installer, the updater, the debug log and the dialogs' check boxes
build_lisp.py             checks both messages.json files against the code, then builds pdfall.lsp and the joined messages.json
install.ps1, *.bat        what install.bat and uninstall.bat run: the bundle, the shared updater, the Start menu
updater\                  the shared updater: «Оновити плагіни AutoCAD» (../docs/adr/0001)
package.ps1               build.bat's last step: puts those next to PDFALL.bundle and zips it all
ribbon.ps1                builds a ribbon tab with AutoCAD's own AcCui.dll
release.ps1               what release.ps1 runs
```

`examples\` (the sample drawing, old project drawings in `examples\old`, the company's forms in `examples\formats`, and hand-made PDFs that the tests use) is kept out of git because it contains real drawings. The repository is public: never commit drawings, PDFs, names from title blocks or anything else from real projects. The templates in `src\templates` hold only the empty title-block form.

## The LISP modules

`..\common\build_lisp.py` joins `..\common\lsp\*.lsp` and `src\lsp\*.lsp` in name order into the one `pdfall.lsp` that AutoCAD loads from the bundle, so the number prefix of a file sets its place ([ADR 0004](docs/adr/0004-split-the-lisp-and-build-in-its-texts.md)). The common files are written with `@:` for the prefix; PDFALL's copy of them says `pa:` ([../docs/adr/0002](../docs/adr/0002-share-code-between-plugins.md)). Each file's header lists the functions the other files may call.

```
00-settings.lsp           version, settings, *pdfall-home*   (opens the joined file)
                          <- messages.json goes here, as *pa-messages*, *pa-labels* and *pa-files*
common: 10-text.lsp       pa:msg, pa:label, pa:file and the string helpers
10-text.lsp               the марка helpers: pa:marka-p, pa:marka-error, pa:cyr, pa:title-name
common: 12-log.lsp        the debug log (pa:log) and c:PDFDEBUG
common: 14-settings.lsp   pa:setting, pa:set-setting
common: 16-dialog.lsp     writing and opening DCL dialogs, and the ■/□ lists
20-reader.lsp             Model space -> records: pa:read-drawing; title-block cells and the look of their texts
30-command.lsp            errors, warnings, reports, restoring layers and system variables
35-date.lsp               the export date PDFALL writes into the Дата cell while it plots
40-pdfall.lsp             c:PDFALL: марка checks, PDF names, layers, plotting, merge.exe
50-pdfnum.lsp             c:PDFNUM: fills and fixes Аркуш/Аркушів (ADR 0010)
55-settings.lsp           the user's settings: which templates to paste, what goes in the name cell, the шари заливки (ADR 0011)
60-paste.lsp              c:PDFLIST, c:PDFSPEC
62-previews.lsp           every template and its outline (made by make_templates.ps1, not edited by hand)
65-dialog.lsp             c:PDFSETTINGS, the settings dialog, and PDFALL's window that picks the марки (ADR 0012)
80-public.lsp             pdfall:marka-at, the one function other plugins may call (../docs/adr/0003)
90-loaded.lsp             the line AutoCAD shows when it loads PDFALL
```

`pdfall:marka-at` is a promise to BPTOOLS: keep its name, arguments and result, and add a new function rather than change it. `tests/run.ps1` checks it.

`pa:read-drawing` is the one way to read a drawing. It returns `(records problems)`: a record for every рамка with a readable марка, carrying its title-block texts (`zone`), its Аркуш/Аркушів/Арк. cells (`counters`) and its cell edges (`cells`, `rows`), all measured from the рамка's bottom-right corner. The lines and texts it collects stay inside it.

### The debug log

When something works here but not on a colleague's PC, ask them to run `PDFDEBUG` → `Увімкнути`, repeat what fails, then `PDFDEBUG` → `Показати` and send `%TEMP%\PDFALL-debug.log`. The log has the AutoCAD version, language and code pages, the settings, every rectangle the reader considered and why it was or wasn't a рамка, each рамка's kind and why, all its title-block texts with their positions (the name cell marked), the марка, and each step of pasting, numbering and plotting. Add a `(pa:log (list ...))` wherever a new decision is made; it costs nothing while the log is off. Each line is flushed at once, so the last line before a hard error ("internal stack limit reached") shows where it happened. Log lines are English, so they never need messages.json.

## Texts: messages.json

Every Ukrainian word the user sees or PDFALL looks for is in `src\messages.json`, or, when every plugin shows it (the installer, the updater, the debug log, the dialogs' check boxes), in `..\common\messages.json`. Both have three sections:

- `messages`: what the user reads. Free to edit; `{name}` is filled in by the program.
- `labels`: words read from title blocks (`Аркуш`, `Аркушів`, `Арк.`, the `МАРКА` placeholder, ...). Changing one stops PDFALL from reading drawings that use the old word.
- `files`: the words of the PDF names (`лист`, `без заливки`, `загальний друк`, ...), all in lower case ([ADR 0006](docs/adr/0006-one-file-name-pattern.md)). PDFALL writes them and merge.exe reads them, so changing one makes PDFs already exported unrecognisable.

The code reads them with `pa:msg`/`pa:label`/`pa:file` in LISP, `msg`/`label`/`file_word` in merge_blueprints.py and `Msg` in the installer, the updater and ribbon.ps1, always with a literal key. `build.bat` runs `..\common\build_lisp.py` first, which fails the build when:

- the code uses a key that the section doesn't have;
- a message and the code that shows it disagree on its `{names}`;
- a key is in both files;
- a Ukrainian string is written in LISP outside `00-settings.lsp`.

A key no code uses is only a warning. `program.merge` is how the installer names merge.exe when its window is still open; it reads `program.<exe>` by name. The bundle carries no JSON: the LISP texts are built into `pdfall.lsp`, merge.exe has the joined copy packed in, the zip carries it next to `install.ps1`, and the updater has the common one. `check.bat` runs merge_blueprints.py with `src\messages.json` alone, so merge_blueprints.py uses no common text.

## Settings

Settings live in `src\lsp\00-settings.lsp`, which also opens the installed `pdfall.lsp`. `*pdfall-fill-layers*` are the шари заливки a user starts with; each user then chooses their own in PDFSETTINGS ([ADR 0011](docs/adr/0011-choose-the-fill-layers.md)). `*pdfall-sizes*` are the sheet sizes a рамка may have, and `*pdfall-paper*` the pattern of their paper's canonical name, which AutoCAD doesn't translate; never replace it with the names the Plot dialog shows ([ADR 0008](docs/adr/0008-read-old-drawings.md), [ADR 0009](docs/adr/0009-every-a-size-and-settings-for-pasting.md)). `*pdfall-cancel-words*` is how AutoCAD words Esc in languages other than English (Russian: «Функция прервана»); if Esc in some other language prints `Помилка <команда>: …`, add that wording there.

Exporting has no settings for colleagues: PDFALL recognises every form and the old title block by itself (ADR 0008, 0009), so a drawing that differs in a new way needs a change to the reader, `src\lsp\20-reader.lsp`, and a drawing for `examples\old`. Colleagues' settings (PDFSETTINGS, `55-settings.lsp`) only choose what PDFLIST pastes (a лист or a текстовий документ), the марка it offers, and what goes in the name cell; they are kept per user with `setenv` (`PDFALL_Paste`, `PDFALL_Marka`, `PDFALL_Prefix`, ...). The dialog is the one thing the tests can't run: check it by hand in AutoCAD after changing `65-dialog.lsp`.

## Templates

The рамки that PDFLIST and PDFSPEC paste are `src\templates\PDFALL_*.dwg`, one per form of the company's (`examples\formats`): `PDFALL_list_<standard>_<size><orientation>.dwg`, `PDFALL_spec1/2.dwg` and `PDFALL_text_<standard>_1/2.dwg` ([ADR 0003](docs/adr/0003-paste-frames-from-dwg-templates.md), [ADR 0009](docs/adr/0009-every-a-size-and-settings-for-pasting.md)). When a form changes, change it in `examples\formats` and run `build.bat`, then `src\make_templates.ps1`: it drops the forms' placeholders, puts `МАРКА` in the name cell fitted to it, and writes `src\lsp\62-previews.lsp`, the list of templates with their outlines that the settings dialog draws. A new form needs a file name `make_templates.ps1` understands (`Get-Template`). When editing a template in AutoCAD by hand instead, keep:

- the рамка's lower-left corner at the DWG's origin, and its A size;
- the `МАРКА` text in the name cell;
- that MTEXT anchored Middle Center at the cell's centre, exactly as wide and as high as the cell;
- no names, dates or other project data in the title block;
- `62-previews.lsp` in step: run `make_templates.ps1` rather than editing templates by hand.

## The guide

Colleagues read `src\Instruktsiia.html`, not the Markdown files: it opens in any browser, offline, from the zip (next to `install.bat`) and from the Start menu (**Інструкція PDFALL**, the bundle's copy). Keep it one self-contained file, with no scripts, fonts or images from the internet, and update it in the same pull request as the behaviour it describes. Its name is in Latin letters because the zip `build.bat` makes stores Cyrillic file names in a way Windows Explorer garbles. `README.md` is only the short version for the GitHub page.

## Building and testing

`build.bat` needs AutoCAD 2024 installed (for the ribbon) and `py -3 -m pip install pyinstaller pypdf` once. Then run both tests:

```bash
powershell -ExecutionPolicy Bypass -File tests/run.ps1
```

```bash
powershell -ExecutionPolicy Bypass -File tests/install.ps1
```

Each accoreconsole run of `tests/run.ps1` gets its own isolated profile, but AutoCAD seeds it with the settings of your own AutoCAD, PDFALL's among them (`setenv` keeps them under `FixedProfile\General`). So every test script first resets PDFALL's settings to `*pa-setting-defaults*`; a new script must do the same, or what you chose in PDFSETTINGS (a шар заливки, say) changes its results.

`tests/install.ps1` also tests the shared updater, since PDFALL is the plugin that ships it first: the plugin list, the versions of one plugin, «Оновити все», a newer updater not being replaced by an older one, and the old **Оновити PDFALL** entry being removed. A change to `..\common` must pass every plugin's tests.

GitHub Actions (`.github/workflows/check.yml`) can't build or test without AutoCAD, so on every pull request it only runs `build_lisp.py`'s checks: the messages against the code, and the version.

## Pull requests

Work on a branch and merge through a pull request; the template (`.github/pull_request_template.md`) asks for the version impact and a test plan. A pull request that changes what colleagues get adds a line, in Ukrainian and written for them, under **Невипущене** in `CHANGELOG.md`, in the section that fits: Додано (added), Змінено (changed), Виправлено (fixed) or Вилучено (removed). It doesn't raise the version; the release does.

## Releasing

Versions follow [Semantic Versioning](https://semver.org): *major.minor.patch*, judged by what colleagues notice.

- **patch** (1.8.0 → 1.8.1): only fixes.
- **minor** (1.8.1 → 1.9.0): something new, while drawings, PDFs and habits keep working.
- **major** (1.9.0 → 2.0.0): something works differently and colleagues must know, e.g. PDF names, command names or the title-block words in `labels` change.

A release is a GitHub release tagged `pdfall-v<version>` (the prefix keeps each plugin's versions apart in this repository) with two files: `PDFALL-<version>.zip` and `PDFALL-<version>.zip.sha256`. Its notes are the version's section of `CHANGELOG.md`, plus install help after a `---` line (`release.footer`). The shared updater reads the repository's releases from the GitHub API, lists every plugin with a `<name>-v*` release that is neither a draft nor a pre-release, lets the user pick a plugin and then one of its versions with the arrow keys, newer or older, or «Оновити все» (tests drive it with `-Keys Enter,DownArrow,Enter`), and installs a zip only if it matches its `.sha256` ([ADR 0007](docs/adr/0007-update-from-github-releases.md), [../docs/adr/0001](../docs/adr/0001-one-updater-for-every-plugin.md)). So a release must never be edited to point at a different zip: publish a new version instead. Don't delete old releases either: colleagues go back to them when a new version breaks something.

1. Prepare the version in a pull request. On a branch from `main`:

   ```bash
   powershell -ExecutionPolicy Bypass -File release.ps1 -Prepare 1.9.0
   ```

   This sets the version in `00-settings.lsp` and `PackageContents.xml` and turns **Невипущене** into `## 1.9.0 - <today>`. Read the notes as a colleague would, commit, and merge the pull request.

2. Publish from the merged `main`:

   ```bash
   powershell -ExecutionPolicy Bypass -File release.ps1
   ```

   It refuses unless `main` is clean and equal to `origin/main`, the tag is new, and `CHANGELOG.md` has the version's section. Then it runs `build.bat` and both tests, writes the zip, its `.sha256` and the notes to `dist\release`, creates and pushes the annotated tag, and publishes the release with the [GitHub CLI](https://cli.github.com) (`winget install GitHub.cli`, then `gh auth login` once). Without `gh` it prints a link to a pre-filled release page; attach the two files there and publish. `-DryRun` stops before the tag.

3. Colleagues run **Оновити плагіни AutoCAD** from the Start menu; on PDFALL 1.8.0–1.11.0 it is still **Оновити PDFALL**, which installs the shared updater with 1.12.0. Older installs take the zip by hand once.

`build_lisp.py` fails the build if the two version numbers differ, so a half-raised version can't be built.
