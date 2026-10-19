# Developing PDFALL

How PDFALL is built, tested and released. What it does for colleagues is in [README.md](README.md) (in Ukrainian), the terms in [GLOSSARY.md](GLOSSARY.md), and why it works this way in [docs/adr](docs/adr).

## Files

```
src\lsp\*.lsp             the PDFALL, PDFNUM, PDFLIST and PDFSPEC commands, one module per file
src\messages.json         every text the commands, merge.exe, the installer and the ribbon show or look for
src\build_lisp.py         checks messages.json against the code, then joins src\lsp\*.lsp and it into the bundle's pdfall.lsp
src\merge_blueprints.py   builds Загальний and Загальний друк (shipped as merge.exe)
src\PDFALL.pc3            the PDF printer without the viewer
src\PackageContents.xml   tells AutoCAD how to load the bundle
src\ribbon.ps1            builds PDFALL.cuix (the ribbon tab) and its icons with AutoCAD's own AcCui.dll
src\templates\*.dwg       the empty рамки that PDFLIST and PDFSPEC paste
src\make_templates.ps1    cuts those templates out of examples\*.dxf (only when the sample's title blocks change)
src\install.ps1           what install.bat and uninstall.bat run
build.bat                 builds dist\PDFALL.zip
tests\run.ps1             runs the built PDFNUM, PDFALL, merge.exe, PDFLIST and PDFSPEC without opening AutoCAD
tests\install.ps1         tests the installer against a fake copy of the AutoCAD settings
merge.bat, check.bat      run the Python merge by hand (check.bat only reports problems)
```

`examples\` (the sample drawing and hand-made PDFs that the tests use) is kept out of git because it contains real drawings.

## The LISP modules

`build_lisp.py` joins `src\lsp\*.lsp` in name order into the one `pdfall.lsp` that AutoCAD loads from the bundle, so the number prefix of a file sets its place ([ADR 0004](docs/adr/0004-split-the-lisp-and-build-in-its-texts.md)). Each file's header lists the functions the other files may call.

```
00-settings.lsp   version, settings, *pdfall-home*   (opens the joined file)
                  <- messages.json goes here, as *pa-messages*, *pa-labels* and *pa-files*
10-text.lsp       pa:msg, pa:label, pa:file and the string helpers
20-reader.lsp     Model space -> records: pa:read-drawing; title-block cells and the look of their texts
30-command.lsp    errors, warnings, reports, restoring layers and system variables
35-date.lsp       the export date PDFALL writes into the Дата cell while it plots
40-pdfall.lsp     c:PDFALL: марка checks, PDF names, layers, plotting, merge.exe
50-pdfnum.lsp     c:PDFNUM
60-paste.lsp      c:PDFLIST, c:PDFSPEC
90-loaded.lsp     the line AutoCAD shows when it loads PDFALL
```

`pa:read-drawing` is the one way to read a drawing. It returns `(records problems)`: a record for every рамка with a readable марка, carrying its title-block texts (`zone`), its Аркуш/Аркушів/Арк. cells (`counters`) and its cell edges (`cells`, `rows`), all measured from the рамка's bottom-right corner. The lines and texts it collects stay inside it.

## Texts: messages.json

Every Ukrainian word the user sees or PDFALL looks for is in `src\messages.json`, in three sections:

- `messages`: what the user reads. Free to edit; `{name}` is filled in by the program.
- `labels`: words read from title blocks (`Аркуш`, `Аркушів`, `Арк.`, the `МАРКА` placeholder, ...). Changing one stops PDFALL from reading drawings that use the old word.
- `files`: the words of the PDF names (`лист`, `без заливки`, `Загальний друк`, ...). PDFALL writes them and merge.exe reads them, so changing one makes PDFs already exported unrecognisable.

The code reads them with `pa:msg`/`pa:label`/`pa:file` in LISP, `msg`/`label`/`file_word` in merge_blueprints.py and `Msg` in install.ps1 and ribbon.ps1, always with a literal key. `build.bat` runs `build_lisp.py` first, which fails the build when:

- the code uses a key that the section doesn't have;
- a message and the code that shows it disagree on its `{names}`;
- a Ukrainian string is written in `src\lsp` outside `00-settings.lsp`.

A key no code uses is only a warning. The bundle carries no JSON: the LISP texts are built into `pdfall.lsp`, merge.exe has its copy packed in, and the zip carries one next to `install.ps1`.

## Settings

Settings live in `src\lsp\00-settings.lsp`, which also opens the installed `pdfall.lsp`. The one you're most likely to change is `*pdfall-fill-layers*`, every name the шар заливки may have; add the new name there if the layer is ever renamed.

## Templates

The рамки that PDFLIST and PDFSPEC paste are `src\templates\PDFALL_list.dwg`, `PDFALL_spec1.dwg` and `PDFALL_spec2.dwg` ([ADR 0003](docs/adr/0003-paste-frames-from-dwg-templates.md)). `make_templates.ps1` cuts them out of the sample drawing and fits the name cell's MTEXT to its cell. When editing a template in AutoCAD by hand, keep:

- the рамка's lower-left corner at the DWG's origin, and its 420x297 or 210x297 size;
- the `МАРКА` text in the name cell;
- that MTEXT anchored Middle Center at the cell's centre, exactly as wide and as high as the cell.

## Releasing

1. Raise `*pdfall-version*` in `src\lsp\00-settings.lsp` and `AppVersion` in `src\PackageContents.xml`, keeping them equal.
2. Run `build.bat`. It needs AutoCAD 2024 installed (for the ribbon) and `py -3 -m pip install pyinstaller pypdf` once.
3. Run both tests:

   ```bash
   powershell -ExecutionPolicy Bypass -File tests/run.ps1
   ```

   ```bash
   powershell -ExecutionPolicy Bypass -File tests/install.ps1
   ```

4. Share `dist\PDFALL.zip`.
