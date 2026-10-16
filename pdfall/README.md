# PDFALL

One command in AutoCAD, `PDFALL`, plots every лист and специфікація of a drawing to PDF and combines them into Загальний and Загальний друк. Terms are explained in [GLOSSARY.md](GLOSSARY.md). Why it works this way is in [docs/adr](docs/adr).

Works with AutoCAD 2024 and later. No Python or admin rights needed.

## Install (each colleague, once)

1. Close AutoCAD.
2. Unzip `PDFALL.zip` anywhere and double-click `install.bat`.
3. Start AutoCAD. The command line shows `PDFALL 1.2.0 loaded`, and the ribbon has a **PDFALL** tab with PDFALL and PDFNUM buttons.

To update, run the new `install.bat` the same way. To remove, run `uninstall.bat`.

`install.bat` copies `PDFALL.bundle` into `%APPDATA%\Autodesk\ApplicationPlugins`, where AutoCAD loads it into every drawing. It also adds that folder to *Trusted Locations*, so AutoCAD doesn't ask whether to load it, and removes any older `pdfall.lsp` from the *Startup Suite*. On its first run, PDFALL copies `PDFALL.pc3` into AutoCAD's Plotters folder. That's the *AutoCAD PDF (General Documentation)* printer with "Open in viewer when done" turned off, so a run doesn't open 30+ viewer windows. Your normal printer is not changed.

## Use

1. Open the drawing and click **PDFALL** on the PDFALL ribbon tab, or type `PDFALL`.
2. Wait for the PDFs. A merge window then opens and shows what it built. Press Enter to close it.

The PDFs go next to the drawing:

```
<drawing folder>\exported files\1ЧП\1ЧП лист 1.pdf
                                    1ЧП лист 1 без заливки.pdf
                                    1ЧП специфікація лист 1.pdf
                                    1ЧП Загальний.pdf
                                    1ЧП Загальний друк.pdf
```

## Fill in Аркуш and Аркушів: PDFNUM

Type `PDFNUM` to fill in every empty Аркуш and Аркушів cell in the drawing, then check the result and run `PDFALL`.

- Each марка's листи and специфікації are numbered separately, by position: left to right, upper row first.
- Аркушів is the number of листи (or специфікації) found for that марка.
- **A number that is already written is never changed.** If an empty cell's number is already used by another рамка, the cell is left empty and PDFNUM says so.
- On a лист the number is added to the label ("Аркуш 2"). On a специфікація it goes in the cell under the label, in the same style as numbers already written in the drawing.
- `U` undoes the whole PDFNUM in one step.

To merge PDFs that were exported by hand, drag their folder onto `merge.exe` in `%APPDATA%\Autodesk\ApplicationPlugins\PDFALL.bundle\Contents`.

## What PDFALL checks

It plots **nothing** and lists the problems (zooming to the first bad рамка) when:

- a title block has no readable марка, or names two different марки;
- the same марка is typed with different letters in different title blocks, e.g. Latin `K1` on one and Cyrillic `К1` on another. The марка is used exactly as typed, so mixed codes like X1A1Р are fine as long as every title block spells it the same way;
- the Аркуш numbers of a марка's листи (or специфікації) are not exactly 1…N, or one is missing (PDFNUM fills in missing ones);
- an Аркушів cell is empty, or disagrees with the number of рамки found;
- no шар заливки (`Цвет` or `Колір`) exists;
- an old PDF it has to replace is open in another program.

It **asks** before plotting when a layer other than `Defpoints` is off or frozen, because its objects would be missing from every PDF.

It **warns** but plots when:

- a single-sheet марка has empty Аркуш/Аркушів cells (it's treated as лист 1; PDFNUM fills them in);
- `exported files` holds a folder for a марка that's no longer in the drawing.

The layer states are restored afterwards, and the drawing is saved before plotting.

## Developing

```
src\pdfall.lsp            the PDFALL and PDFNUM commands
src\merge_blueprints.py   builds Загальний and Загальний друк (shipped as merge.exe)
src\PDFALL.pc3            the PDF printer without the viewer
src\PackageContents.xml   tells AutoCAD how to load the bundle
srcibbon.ps1            builds PDFALL.cuix (the ribbon tab) and its icons with AutoCAD's own AcCui.dll
src\install.ps1           what install.bat and uninstall.bat run
build.bat                 builds dist\PDFALL.zip
tests\run.ps1             runs the built PDFNUM, PDFALL and merge.exe on examples\ without opening AutoCAD
tests\install.ps1         tests the installer against a fake copy of the AutoCAD settings
merge.bat, check.bat      run the Python merge by hand (check.bat only reports problems)
```

To release a change:

1. Raise `*pdfall-version*` in `pdfall.lsp` and `AppVersion` in `PackageContents.xml`, keeping them equal.
2. Run `build.bat`. It needs AutoCAD 2024 installed (for the ribbon) and `py -3 -m pip install pyinstaller pypdf` once.
3. Run both tests:

   ```bash
   powershell -ExecutionPolicy Bypass -File tests/run.ps1
   ```

   ```bash
   powershell -ExecutionPolicy Bypass -File tests/install.ps1
   ```

4. Share `dist\PDFALL.zip`.

Settings live at the top of `pdfall.lsp`. The one you're most likely to change is `*pdfall-fill-layers*`, every name the шар заливки may have; add the new name there if the layer is ever renamed.

`examples\` (the sample drawing and hand-made PDFs that the tests use) is kept out of git because it contains real drawings.
