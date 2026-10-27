# Developing BPTOOLS

How BPTOOLS is built, tested and released. What it does for colleagues is in the guide [src/guide.html](src/guide.html) and, in short, [README.md](README.md) (both in Ukrainian), the terms in [GLOSSARY.md](GLOSSARY.md), and why it works this way in [docs/adr](docs/adr). It shares its installer, updater, release script and LISP helpers with PDFALL through [../common](../common) ([../docs/adr](../docs/adr)); most of what [../pdfall/DEVELOPING.md](../pdfall/DEVELOPING.md) says about texts, pull requests and releasing holds here too.

## Files

```
src\lsp\*.lsp             the commands, one module per file
src\messages.json         every text the commands and the ribbon show, the colours, the «Вигляд з …» notes
src\plugin.json           BPTOOLS's name, LISP prefix (bp) and debug command (BPDEBUG), for the shared build
src\PackageContents.xml   tells AutoCAD how to load the bundle
src\ribbon.ps1            builds BPTOOLS.cuix, the «Креслення» tab, with ..\common\ribbon.ps1
src\make_template.ps1     builds BPTOOLS.dwt in the console AutoCAD from the built bptools.lsp
src\guide.html     the guide for colleagues: zip root, bundle, Start menu (Інструкція BPTOOLS)
build.bat                 builds dist\BPTOOLS.zip
release.ps1               raises the version (-Prepare) and publishes a GitHub release, with ..\common\release.ps1
CHANGELOG.md              what changed in each version, in Ukrainian; also the release notes
tests\run.ps1             runs the built commands in the console AutoCAD, the template and the ribbon
tests\install.ps1         what BPTOOLS's zip installs (the installer itself is tested by PDFALL's tests)
```

## The LISP modules

`..\common\build_lisp.py` joins `..\common\lsp\*.lsp` (under the `bp:` prefix) and `src\lsp\*.lsp` in name order into `bptools.lsp` ([../docs/adr/0002](../docs/adr/0002-share-code-between-plugins.md)).

```
00-settings.lsp           version, the стиль оформлення (*bptools-styles*), the layer, the style names
                          <- messages.json goes here, as *bp-messages*, *bp-labels* and *bp-files*
common: 10-text, 12-log, 14-settings, 16-dialog   bp:msg ..., the debug log and c:BPDEBUG, bp:setting, the DCL helpers
15-command.lsp            bp:run, which every command goes through: the style first, one undo step, system variables put back
20-styles.lsp             bp:ensure-styles: makes the styles and puts back what was changed (ADR 0001)
30-numbers.lsp            the next позиційний номер and Рис. number in a марка, through pdfall:marka-at
40-labels.lsp             c:BPPOS, c:BPPIN, c:BPWIRE, c:BPNAME, c:BPVIEW, c:BPFIG, c:BPSTYLE
50-new.lsp                c:BPNEW
90-loaded.lsp             the line AutoCAD shows when it loads BPTOOLS
```

The style names and heights are in `00-settings.lsp`, the only LISP file where Ukrainian text may be written; the words BPTOOLS writes into drawings (the colours, the views, `Рис.`) are in the `labels` of `messages.json`.

Two things differ between the console AutoCAD the tests run in and the real one:

- **ActiveX.** The console has none. `bp:add-pos` makes a multileader with `vla-addmleader` when ActiveX is there, because `MLEADER` asks for its points in the order the user last chose; in the console it uses `MLEADER`, which there asks arrowhead first and takes one line of text. `BPNEW` needs ActiveX to open a document.
- **Dialogs.** The console has none, so BPWIRE asks at the command line instead of in its list window.

Check both by hand in AutoCAD after changing them.

## Numbers across the марка

BPTOOLS never reads title blocks: it asks PDFALL's `pdfall:marka-at` which марка each point is in ([../docs/adr/0003](../docs/adr/0003-plugins-talk-through-one-function.md)), and counts across the whole drawing when PDFALL isn't loaded. Every multileader whose text starts with a number counts as a позиційний номер, whoever drew it, and every text in the «Підпис рисунка» style that starts with `Рис. N` as a figure.

## Building and testing

`build.bat` needs AutoCAD 2024 (for the template and the ribbon). Then:

```bash
powershell -ExecutionPolicy Bypass -File tests/run.ps1
```

```bash
powershell -ExecutionPolicy Bypass -File tests/install.ps1
```

`tests/run.ps1` part 2 needs PDFALL built (`..\pdfall\build.bat`) and its sample drawing in `..\pdfall\examples`; without them it is skipped. Every test script resets BPTOOLS's settings first, since the console's profile is seeded with your own.

## Releasing

As PDFALL ([../pdfall/DEVELOPING.md](../pdfall/DEVELOPING.md#releasing)), with tags `bptools-v<version>` and the zip `BPTOOLS-<version>.zip`. The first release is `release.ps1 -Prepare 1.0.0`; until then the version is 0.0.0. Release BPTOOLS before the PDFALL that offers it, so the offer finds a release to install.
