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
src\parts\library.dwg     the parts drawn by hand (see "Adding a part")
src\make_parts.lsp        generates the D-Sub parts, and writes the library out (with make_parts.ps1)
src\make_parts.ps1        makes src\parts\<file>.dwg, one per вигляд, and src\lsp\45-parts.lsp; run when a part changes
src\parts\*.dwg           what make_parts.ps1 made: one drawing per вигляд, shipped in the bundle's parts folder
src\parts\components\     what tools\components made from the components library: per part a drawing of its 10 views
                          and their outlines (<id>.dwg, <id>.txt), and index.tsv, which drawing each came from
src\guide.html     the guide for colleagues: zip root, bundle, Start menu (Інструкція BPTOOLS)
tools\step-views\         draws the 10 views of STEP models into DWGs (see "Views from STEP models"); not shipped
tools\components\        turns the components library's drawings into parts (see "Parts from the components library")
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
40-labels.lsp             c:BPPOS, c:BPPIN, c:BPWIRE, c:BPNAME, c:BPVIEW, c:BPFIG, c:BPSTYLE; names, views, captions
                          and notes are MTEXT one row wide, the rest TEXT
45-parts.lsp              the catalog of parts with their outlines (made by make_parts.ps1, not edited by hand)
46-components.lsp         the parts of the components library, added to the catalog (made by tools\components)
50-new.lsp                c:BPNEW
60-parts.lsp              c:BPPART: the window, the preview, pasting with rotation and scale, numbers upright (ADR 0002)
70-center.lsp             c:BPCENTER: texts centred between the outermost points of other objects
90-loaded.lsp             the line AutoCAD shows when it loads BPTOOLS
```

The style names and heights are in `00-settings.lsp`, which with the generated `45-parts.lsp` and `46-components.lsp` (`"generated"` in `plugin.json`) are the only LISP files where Ukrainian text may be written; the words BPTOOLS writes into drawings (the colours, the views, `Рис.`) are in the `labels` of `messages.json`.

Two things differ between the console AutoCAD the tests run in and the real one:

- **ActiveX.** The console has none. `bp:add-pos` makes a multileader with `vla-addmleader` when ActiveX is there, because `MLEADER` asks for its points in the order the user last chose; in the console it uses `MLEADER`, which there asks arrowhead first and takes one line of text. `BPNEW` needs ActiveX to open a document.
- **Dialogs.** The console has none, so BPWIRE and BPPART ask at the command line instead of in their windows.
- **Extents.** BPCENTER measures objects with ActiveX's bounding box; in the console it measures lines, polylines, circles, arcs, texts and multiline texts by hand.

Check both by hand in AutoCAD after changing them.

## Numbers across the марка

BPTOOLS never reads title blocks: it asks PDFALL's `pdfall:marka-at` which марка each point is in ([../docs/adr/0003](../docs/adr/0003-plugins-talk-through-one-function.md)), and counts across the whole drawing when PDFALL isn't loaded. Every multileader whose text starts with a number counts as a позиційний номер, whoever drew it, and every text in the «Підпис рисунка» style that starts with `Рис. N` as a figure.

## Adding a part

The library is `src\parts\library.dwg` plus the generated D-Sub parts ([ADR 0002](docs/adr/0002-a-library-of-parts.md)). To add a part:

1. Run `build.bat` once, so `dist` has a bptools.lsp. Open `src\parts\library.dwg` in AutoCAD (start it from `BPTOOLS.dwt` the first time; any BPTOOLS command brings in the styles).
2. Draw each вигляд the sheets need, full size in mm, as seen from that side. Pin 1 must be where it really is from that side: from the back a face is mirrored.
3. Draw the lines on layer **0** with colour **ByBlock**, so the part takes the layer it is pasted on.
4. Write each pin number as an attribute definition (ATTDEF):
   - tag `PIN<n>`, default `<n>`, mode **Preset**;
   - text style «Номер контакту», or «Номер контакту малий» where 2.5 mm doesn't fit;
   - justification **Middle center**, at the place the number should sit.
5. Make each вигляд a block. Name it «<part> — <вигляд>», with an em dash between spaces and the вигляд exactly «з лицьового боку», «з монтажного боку» or «з боку контактів», for example «JST GH 1.25 4 pin — з лицьового боку». Put the base point at the centre of the face. Leave the part's name and the «Вигляд з …» note out of the block.
6. Save `library.dwg`, run `src\make_parts.ps1`, then `build.bat` again, and check the part in BPPART's preview and pasted.
7. Commit `library.dwg`, `src\parts\*.dwg` and `src\lsp\45-parts.lsp` together, and add a line to the changelog.

Parts that follow a pattern are a line in a table of `make_parts.lsp` instead: a D-Sub shell in `*mk-dsubs*`, its top and side views in `*mk-dsub-sides*`, a single-row keyed connector (JST GH and the like) in `*mk-row-parts*`, a Futaba-style part in `*mk-futaba*`. Take the numbers from the maker's drawing and say where they came from in the comment; keep makers' datasheets in `datasheets\`, which git ignores (they are not ours to publish). A datasheet PDF that is encrypted opens with `py -3 -m pip install cryptography` and pypdf. To correct a generated part by hand, draw a block of the same name in `library.dwg`: it wins.

## Views from STEP models

`tools\step-views` draws a part from every side out of its 3D model, for the components library kept outside this repo (a folder with `3D model\` holding the makers' `.stp`/`.step` files and `dwg blueprints\` holding the drawings):

```
tools\step-views\make_views.bat "<components library>\connectors" --dry
tools\step-views\make_views.bat "<components library>\connectors"
```

`--dry` lists the models that have no drawing yet; without it each gets `dwg blueprints\<family>\<model>.DWG`. A DWG already there is never overwritten, so delete one to have it made again. `--only=<regex>` takes only the models whose path matches. The first run sets up Python with OpenCascade and ezdxf in `%LOCALAPPDATA%\bptools-step-views`; it needs `py` and AutoCAD 2024's console.

Each drawing has 10 views, hidden lines removed, at 1:1 in mm on layer 0:

```
iso        top      iso
left       front    right     back
iso        bottom   iso
```

- **Which side is the front.** `step_views.py` (one model) takes the axes as SolidWorks does: the front view looks from +Z with +Y up. The `FAMILIES` table in `make_views.py` says otherwise per family and picks the folder each family's drawings go to. For example, JST PH looks from −X and puts the back next to the front, as the drawings made by hand before.
- **One file, many sizes.** A STEP that stacks every size of a connector at one origin (JST SH «ALL», Molex PicoBlade) becomes one drawing per size, «<model> - <size>». A size is any top-level part whose name differs from the others' only in its digits.
- **Speed and fallback.** A model takes from under a second to a few minutes. If the exact hidden-line algorithm fails or takes over 30 minutes, the polygonal one is used, and the report says so. The report goes to `%TEMP%\step-views\report.tsv`.

## Parts from the components library

Every drawing in `<components library>\<kind>\dwg blueprints` (connectors and any other kind added beside it) is a part of BPPART's library ([ADR 0002](docs/adr/0002-a-library-of-parts.md)). After adding or changing drawings there:

```
tools\components\make_components.bat "<components library>"
```

It reads only the drawings that changed since the last run (by their contents, in `src\parts\components\index.tsv`), takes out the parts whose drawing was removed, and writes `src\lsp\46-components.lsp` again. Then run `build.bat`, check the part in BPPART, and commit `src\parts\components` and `46-components.lsp` together with a line in the changelog. `--only=<regex>` reads the drawings whose path matches again even when unchanged.

- **The views.** A drawing must have the layout `tools\step-views` draws: three rows, the front view in the middle row under the top view and over the bottom view, the left view left of it, the right and back views right of it (in either order: the one that mirrors the front is the back), and an isometric view in each corner. A view is everything whose lines touch; a view a drawing lacks is left out, and the run says how many groups were left over. Each becomes the block «<part> — <вигляд>» with its base point at its centre, on layer 0 coloured by block.
- **The names.** A part is named after its drawing's file. AutoCAD takes no comma, `=` and a few more in a block name, so its blocks have a point or a dash in their place (`bp:block-safe`, `block_safe`); the name written under the part keeps the file's. Two drawings of the same name in different folders get the folder's name after theirs.
- **Pin numbers.** A part whose name matches a line of `PIN_PARTS` in `make_components.py` gets them, as `PIN<n>` attributes like `make_parts.lsp`'s, beside its contacts in every orthographic view but those looking along its rows; the catalog lists them for the preview. A line gives the pins per row and the rows (1 or 2) in the name, the pitch, the axis the contacts point along, the end of the rows pin 1 is at, the end the wires leave from (a header's: its mating housing's) and for two rows the side of the odd row, as model axes (Z towards the viewer of the front view; `AXES` says how each view shows them), so the view from the other side is mirrored by itself. Views looking along the contacts number each row beside it; views from the side number the row nearer the viewer, on the side away from the wires, so the wires can be drawn. Numbers closer than their width go out in a zig-zag of as many steps as the pitch needs. The rows are taken as centred in the views. Take pin 1 from the maker's drawing (in `datasheets\`) where there is one, match it to a feature the model shows (JST's triangle, a lock, the leads), say which in the line's comment; without one, put it at the left of the front view (for two rows its top left), as the guide tells colleagues. Look at every numbered view before committing: a wrong number is worse than none.
- **Arcs.** Some of the library's drawings have arcs the wrong way round (in the views their maker mirrored), which AutoCAD draws as nearly whole circles; `fix_arcs` turns round each arc that sets off along a line meeting it, and the run says how many it turned in each drawing. A part with no line has no numbers; to give one numbers by hand instead, draw its вигляд with `PIN<n>` attributes in `library.dwg` under the same block name, as in "Adding a part".

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
