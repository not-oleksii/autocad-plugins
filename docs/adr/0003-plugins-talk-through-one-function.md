# Plugins talk through one public function

BPTOOLS numbers позиційні номери across a марка, not across a лист or the whole drawing, because one drawing holds several марки ([pdfall ADR 0001](../../pdfall/docs/adr/0001-plot-from-model-space-with-lisp.md)). Which рамка and марка a point belongs to is PDFALL's knowledge: reading the title blocks, the name cell, old drawings and Latin lookalike letters is most of its reader.

So PDFALL publishes one function, and BPTOOLS calls it:

- `(pdfall:marka-at pt)` is the марка of the рамка that point `pt` is in, exactly as typed in its title block, or `nil` when the point is in no рамка or its рамка has no марка; `(pdfall:marka-at pts)` does the same for each point of a list, reading the drawing once.
- It lives in `pdfall\src\lsp\80-public.lsp` and is named `pdfall:`, not `pa:`, to say it is meant for other plugins. Its name, arguments and result stay the same from version to version, and PDFALL's tests check them.
- A plugin that calls it works without PDFALL too: it tests `(if pdfall:marka-at ...)` and falls back to the whole drawing, and says so.

## Considered options

- **Copying PDFALL's reader into BPTOOLS.** Rejected: two copies of the same functions in one AutoCAD overwrite each other, and the copies would drift apart ([ADR 0002](0002-share-code-between-plugins.md) only shares what has no plugin's knowledge in it).
- **Numbering across the whole drawing.** Rejected: wrong whenever a drawing holds more than one марка.

## Consequences

- Changing what `pdfall:marka-at` takes or returns is a breaking change for BPTOOLS; add a new function instead.
- BPTOOLS gets PDFALL's fixes to reading drawings without a release of its own.
