# Pick the марки to plot

PDFALL plotted every рамка in the drawing. With many марки to one DWG (ADR 0001), changing one document meant re-plotting all of them, and a half-finished марка elsewhere stopped the run with its errors. Now, when the drawing has two марки or more, «Друк у PDF» first opens a window listing them, all ticked, and plots only the ticked ones.

- **Whole марки, not sheets.** A ticked марка is plotted completely: its old PDFs are cleared and every лист, специфікація and текстовий документ is plotted again, so its загальний is never built from new sheets mixed with old ones carrying another date. Picking single sheets was rejected for that reason.
- **The rest is left alone.** An unticked марка isn't checked, its folder and PDFs stay as they are, and PDFALL doesn't warn that its folder is "не марка цього креслення". A рамка without a марка belongs to no ticked марка, so its problem doesn't stop a partial run, and it isn't plotted then even when plotting despite problems. It is plotted, as before, when every марка is ticked.
- **Only when there is a choice.** With one марка, PDFALL plots at once as before. The window always opens with every марка ticked, with «Усі» and «Жодної» buttons, so «Друкувати» plots what it always did; nothing is remembered from the last run, so a марка can't be forgotten unnoticed. «Друкувати» with nothing ticked asks to tick one; Cancel stops without plotting.
- **Same list as the шари заливки.** Each line is `■` or `□` with the марка and its sheets ("1ЧП — листів: 3, специфікацій: 1"), and a plain click flips it, as in ADR 0011. The list code is shared by both windows.
- **merge.exe merges only the ticked марки.** PDFALL passes `--only <марка>` for each ticked one, so the загальний and загальний друк of the others aren't rebuilt and the report lists only what was plotted. With every марка ticked the call is as before. `--only` filters the folders under one root rather than passing each марка's folder as a root, so the rename question and the numbers check still come once for the whole run.
- Without a dialog (the console AutoCAD the tests run in), every марка is plotted. The tests replace `pa:pick-dialog` with a stand-in to check a partial run.

## Consequences

- One click more for a drawing with several марки when everything should be plotted: Enter or «Друкувати» right away.
- Re-plotting one марка no longer touches the others' dates: their PDFs keep the date they were plotted on.
