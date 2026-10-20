# PDFNUM fixes wrong numbers, and keeps a correct order

PDFNUM used to fill only empty Аркуш and Аркушів cells and never change a number already written, so a deliberate order was never overwritten. In practice the wrong numbers come from copying: a лист copied to make the next one keeps "Аркуш 2, Аркушів 2", and adding листи leaves every Аркушів short. PDFALL then refused to plot, and the numbers had to be fixed by hand, which is what PDFNUM is for.

PDFNUM now fixes them, changing as little as it can. For each kind of each марка:

- **Аркушів** becomes the count of рамки, wherever it is wrong.
- **Аркуш**: a number from 1 to the count that no earlier рамка has stays, so an order chosen on purpose is kept. A copied number, a number bigger than the count and an empty cell get the smallest free numbers, in position order (upper row first, then left to right). Листи 1, 2, 2 become 1, 2, 3.
- On a специфікація or текстовий документ, the first page (the one with Аркушів) comes first, wherever it lies.

We chose this over renumbering every рамка by position, which is simpler to explain but rewrites a drawing whose листи are numbered correctly yet laid out in another order. The cost is that a new лист put between two numbered ones gets the next free number, not its place: to renumber by position, clear the numbers first.

## Plotting despite wrong numbers

When PDFALL's check finds problems, it now asks whether to plot anyway instead of only stopping. On yes, every рамка found is plotted, with the numbers this same rule gives (`pa:sheet-numbers`) in its file name, so files without numbers, or with a copied one, still make one combined document per марка, in position order. The drawing isn't changed: numbering it is PDFNUM's job, and the user may not want that done in passing. A рамка without a марка (an empty name cell, as in a freshly pasted form) is named after the top line of its organisation cell, the one under Аркуш (`ДВНЗ "ПДАБА"` becomes `ДВНЗ_ПДАБА`), or `Без_марки` when that is empty too. The name is one word, spaces turned to `_` and forbidden characters dropped, because merge.exe reads a file's марка as the first word of its name. рамки under one such name are split into documents by their numbers: in position order, a рамка joins the first document where no рамка of its kind has the same Аркуш or another Аркушів, and with more than one document each gets `_01`, `_02`. Without numbers nothing tells two documents apart, so they stay one. A character Windows forbids in a марка becomes `_`; PDFALL names each such рамка in its warnings. A рамка with two марки takes the first. The user saw the list of problems and chose to plot, so leaving out a рамка PDFALL had found would only surprise them. PDFALL then starts merge.exe with `--force`, so it builds the combined files despite the title blocks disagreeing with the file names, without asking a second time.

## Consequences

- A changed number is edited where it is: in its own text, or in the label's ("Аркуш 2"). A number inside a block can't be changed and is reported, as before.
- The report lists every change as "Аркуш 2 → 3", and U undoes the whole run.
