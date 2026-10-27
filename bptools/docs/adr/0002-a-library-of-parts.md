# A library of parts, one drawing per вигляд

Front views missing or unlike the real роз'єм were one of the problems BPTOOLS set out to fix. Each part is now drawn once, correctly, and pasted with «Вставити деталь» (BPPART) instead of being redrawn.

- **One block per вигляд**, named «<part> — <вигляд>», such as «D-Sub DB-09F — з лицьового боку». The вигляди are з лицьового боку, з монтажного боку and з боку контактів (`*bptools-views*`); a part has the ones it needs (the D-Sub parts have the first two). The base point is the centre of the face, the lines are on layer 0 coloured by block, so the part takes the layer it is pasted on, and the pin numbers are preset attributes in the «Номер контакту» styles. The part's name and the «Вигляд з …» note stay outside the block, as labels the user places.
- **Pasted, never mirrored.** BPPART turns a вигляд in 90° steps and scales it 1:1 to 5:1, then stands every pin number upright at its style's height, so numbers read the same on every part of a лист. A mirrored face would have its pin numbers in the wrong places, so there is no mirroring; the other side is its own вигляд.
- **The source is `src\parts\library.dwg`**, the parts drawn by hand, plus the D-Sub parts that `src\make_parts.lsp` computes from the shell's dimensions, pitch and pin count, with pin 1 at the right of a female face seen from the front and at the left from the back. A hand-drawn block of the same name wins over a generated one.
- **`src\make_parts.ps1` turns the library into what BPTOOLS ships**: one drawing per вигляд, `src\parts\<file>.dwg` with an ASCII file name, and the catalog `src\lsp\45-parts.lsp`, which lists every вигляд with its outline for the preview. Both are committed, as PDFALL's templates are, and run again only when a part changes. BPPART inserts a вигляд from its drawing by name (`<block>=<file>`), so a drawing receives only the blocks it uses.
- **The library ships in the bundle**, so every colleague has the same parts, and a new part arrives with a release.

## Considered options

- **One dynamic block per part** with a visibility state per вигляд. Rejected: a лист often shows two вигляди of one part side by side, and copies of a dynamic block lose their state more easily than separate blocks.
- **A shared network folder** for the library. Rejected: parts could differ between PCs, which is the problem the library is meant to remove.
- **Inserting the whole library drawing** to get one block. Rejected: every drawing would carry every part.
- **Tool palettes.** Rejected: they would have to be set up on every PC.

## Consequences

- Adding a part is: draw it in `library.dwg` as DEVELOPING.md says, run `make_parts.ps1`, release.
- A block already in a drawing is used as it is; a part corrected in the library reaches old drawings only when its block is redefined there.
- The D-Sub dimensions in `make_parts.lsp` are the usual ones for those shells; a new size must be checked against the роз'єм itself.
