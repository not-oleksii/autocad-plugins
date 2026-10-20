# Developing PDFALL

How PDFALL is built, tested and released. What it does for colleagues is in the step-by-step guide [src/Instruktsiia.html](src/Instruktsiia.html) and, in short, [README.md](README.md) (both in Ukrainian), the terms in [GLOSSARY.md](GLOSSARY.md), and why it works this way in [docs/adr](docs/adr).

## Files

```
src\lsp\*.lsp             the PDFALL, PDFNUM, PDFLIST, PDFSPEC and PDFSETTINGS commands, one module per file
src\messages.json         every text the commands, merge.exe, the installer and the ribbon show or look for
src\build_lisp.py         checks messages.json against the code, then joins src\lsp\*.lsp and it into the bundle's pdfall.lsp
src\merge_blueprints.py   builds загальний and загальний друк (shipped as merge.exe)
src\PDFALL.pc3            the PDF printer without the viewer
src\PackageContents.xml   tells AutoCAD how to load the bundle
src\ribbon.ps1            builds PDFALL.cuix (the ribbon tab) and its icons with AutoCAD's own AcCui.dll
src\templates\*.dwg       the 28 empty рамки that PDFLIST and PDFSPEC paste
src\make_templates.ps1    makes those templates and 62-previews.lsp from examples\formats (only when the forms change),
src\make_templates.lsp    with this LISP
src\install.ps1           what install.bat and uninstall.bat run
src\update.ps1            what update.bat (Start menu: Оновити PDFALL) runs: updates from the GitHub releases
src\Instruktsiia.html     the step-by-step guide for colleagues: zip root, bundle, Start menu (Інструкція PDFALL)
build.bat                 builds dist\PDFALL.zip
release.ps1               raises the version (-Prepare) and publishes a GitHub release
CHANGELOG.md              what changed in each version, in Ukrainian; also the release notes
tests\run.ps1             runs the built PDFNUM, PDFALL, merge.exe and the paste commands without opening AutoCAD,
                          on the sample drawing, the old drawings in examples\old and every template
tests\install.ps1         tests the installer and the updater against fake AutoCAD settings and a fake release list
merge.bat, check.bat      run the Python merge by hand (check.bat only reports problems)
..\.github                the pull request template and the CI check
```

`examples\` (the sample drawing, old project drawings in `examples\old`, the company's forms in `examples\formats`, and hand-made PDFs that the tests use) is kept out of git because it contains real drawings. The repository is public: never commit drawings, PDFs, names from title blocks or anything else from real projects. The templates in `src\templates` hold only the empty title-block form.

## The LISP modules

`build_lisp.py` joins `src\lsp\*.lsp` in name order into the one `pdfall.lsp` that AutoCAD loads from the bundle, so the number prefix of a file sets its place ([ADR 0004](docs/adr/0004-split-the-lisp-and-build-in-its-texts.md)). Each file's header lists the functions the other files may call.

```
00-settings.lsp   version, settings, *pdfall-home*   (opens the joined file)
                  <- messages.json goes here, as *pa-messages*, *pa-labels* and *pa-files*
10-text.lsp       pa:msg, pa:label, pa:file and the string helpers
12-log.lsp        the debug log (pa:log) and c:PDFDEBUG
20-reader.lsp     Model space -> records: pa:read-drawing; title-block cells and the look of their texts
30-command.lsp    errors, warnings, reports, restoring layers and system variables
35-date.lsp       the export date PDFALL writes into the Дата cell while it plots
40-pdfall.lsp     c:PDFALL: марка checks, PDF names, layers, plotting, merge.exe
50-pdfnum.lsp     c:PDFNUM: fills and fixes Аркуш/Аркушів (ADR 0010)
55-settings.lsp   the user's settings: which templates to paste, what goes in the name cell
60-paste.lsp      c:PDFLIST, c:PDFSPEC
62-previews.lsp   every template and its outline (made by make_templates.ps1, not edited by hand)
65-dialog.lsp     c:PDFSETTINGS, the settings dialog
90-loaded.lsp     the line AutoCAD shows when it loads PDFALL
```

`pa:read-drawing` is the one way to read a drawing. It returns `(records problems)`: a record for every рамка with a readable марка, carrying its title-block texts (`zone`), its Аркуш/Аркушів/Арк. cells (`counters`) and its cell edges (`cells`, `rows`), all measured from the рамка's bottom-right corner. The lines and texts it collects stay inside it.

### The debug log

When something works here but not on a colleague's PC, ask them to run `PDFDEBUG` → `Увімкнути`, repeat what fails, then `PDFDEBUG` → `Показати` and send `%TEMP%\PDFALL-debug.log`. The log has the AutoCAD version, language and code pages, the settings, every rectangle the reader considered and why it was or wasn't a рамка, each рамка's kind and why, all its title-block texts with their positions (the name cell marked), the марка, and each step of pasting, numbering and plotting. Add a `(pa:log (list ...))` wherever a new decision is made; it costs nothing while the log is off. Each line is flushed at once, so the last line before a hard error ("internal stack limit reached") shows where it happened. Log lines are English, so they never need messages.json.

## Texts: messages.json

Every Ukrainian word the user sees or PDFALL looks for is in `src\messages.json`, in three sections:

- `messages`: what the user reads. Free to edit; `{name}` is filled in by the program.
- `labels`: words read from title blocks (`Аркуш`, `Аркушів`, `Арк.`, the `МАРКА` placeholder, ...). Changing one stops PDFALL from reading drawings that use the old word.
- `files`: the words of the PDF names (`лист`, `без заливки`, `загальний друк`, ...), all in lower case ([ADR 0006](docs/adr/0006-one-file-name-pattern.md)). PDFALL writes them and merge.exe reads them, so changing one makes PDFs already exported unrecognisable.

The code reads them with `pa:msg`/`pa:label`/`pa:file` in LISP, `msg`/`label`/`file_word` in merge_blueprints.py and `Msg` in install.ps1 and ribbon.ps1, always with a literal key. `build.bat` runs `build_lisp.py` first, which fails the build when:

- the code uses a key that the section doesn't have;
- a message and the code that shows it disagree on its `{names}`;
- a Ukrainian string is written in `src\lsp` outside `00-settings.lsp`.

A key no code uses is only a warning. The bundle carries no JSON: the LISP texts are built into `pdfall.lsp`, merge.exe has its copy packed in, and the zip carries one next to `install.ps1`.

## Settings

Settings live in `src\lsp\00-settings.lsp`, which also opens the installed `pdfall.lsp`. The one you're most likely to change is `*pdfall-fill-layers*`, every name the шар заливки may have; add the new name there if the layer is ever renamed. `*pdfall-sizes*` are the sheet sizes a рамка may have, and `*pdfall-paper*` the pattern of their paper's canonical name, which AutoCAD doesn't translate; never replace it with the names the Plot dialog shows ([ADR 0008](docs/adr/0008-read-old-drawings.md), [ADR 0009](docs/adr/0009-every-a-size-and-settings-for-pasting.md)). `*pdfall-cancel-words*` is how AutoCAD words Esc in languages other than English (Russian: «Функция прервана»); if Esc in some other language prints `Помилка <команда>: …`, add that wording there.

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

GitHub Actions (`.github/workflows/check.yml`) can't build or test without AutoCAD, so on every pull request it only runs `build_lisp.py`'s checks: `messages.json` against the code, and the version.

## Pull requests

Work on a branch and merge through a pull request; the template (`.github/pull_request_template.md`) asks for the version impact and a test plan. A pull request that changes what colleagues get adds a line, in Ukrainian and written for them, under **Невипущене** in `CHANGELOG.md`, in the section that fits: Додано (added), Змінено (changed), Виправлено (fixed) or Вилучено (removed). It doesn't raise the version; the release does.

## Releasing

Versions follow [Semantic Versioning](https://semver.org): *major.minor.patch*, judged by what colleagues notice.

- **patch** (1.8.0 → 1.8.1): only fixes.
- **minor** (1.8.1 → 1.9.0): something new, while drawings, PDFs and habits keep working.
- **major** (1.9.0 → 2.0.0): something works differently and colleagues must know, e.g. PDF names, command names or the title-block words in `labels` change.

A release is a GitHub release tagged `pdfall-v<version>` (the prefix keeps each plugin's versions apart in this repository) with two files: `PDFALL-<version>.zip` and `PDFALL-<version>.zip.sha256`. Its notes are the version's section of `CHANGELOG.md`, plus install help after a `---` line. `update.ps1` reads the repository's releases from the GitHub API, takes the newest `pdfall-v*` that is neither a draft nor a pre-release, shows the notes of every version newer than the installed one, and installs the zip only if it matches the `.sha256` ([ADR 0007](docs/adr/0007-update-from-github-releases.md)). So a release must never be edited to point at a different zip: publish a new version instead.

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

3. Colleagues on 1.8.0 or later run **Оновити PDFALL** from the Start menu. Older installs take this zip by hand once.

`build_lisp.py` fails the build if the two version numbers differ, so a half-raised version can't be built.
