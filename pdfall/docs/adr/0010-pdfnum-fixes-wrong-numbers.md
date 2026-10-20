# PDFNUM fixes wrong numbers, and keeps a correct order

PDFNUM used to fill only empty Аркуш and Аркушів cells and never change a number already written, so a deliberate order was never overwritten. In practice the wrong numbers come from copying: a лист copied to make the next one keeps "Аркуш 2, Аркушів 2", and adding листи leaves every Аркушів short. PDFALL then refused to plot, and the numbers had to be fixed by hand, which is what PDFNUM is for.

PDFNUM now fixes them, changing as little as it can. For each kind of each марка:

- **Аркушів** becomes the count of рамки, wherever it is wrong.
- **Аркуш**: a number from 1 to the count that no earlier рамка has stays, so an order chosen on purpose is kept. A copied number, a number bigger than the count and an empty cell get the smallest free numbers, in position order (upper row first, then left to right). Листи 1, 2, 2 become 1, 2, 3.
- On a специфікація or текстовий документ, the first page (the one with Аркушів) comes first, wherever it lies.

We chose this over renumbering every рамка by position, which is simpler to explain but rewrites a drawing whose листи are numbered correctly yet laid out in another order. The cost is that a new лист put between two numbered ones gets the next free number, not its place: to renumber by position, clear the numbers first.

## Consequences

- A changed number is edited where it is: in its own text, or in the label's ("Аркуш 2"). A number inside a block can't be changed and is reported, as before.
- The report lists every change as "Аркуш 2 → 3", and U undoes the whole run.
