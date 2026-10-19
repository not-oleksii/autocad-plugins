# The export date is written only into the PDFs

Every PDF carries the day it was exported in its Дата cell (dd.mm.yyyy). PDFALL writes the date into the drawing after its checks pass and it has saved the drawing, plots, and then takes the date out again: it deletes the texts it made and puts back any date it wrote over. Its `*error*` does the same, so a cancelled or failed run leaves no date behind.

We chose this over writing the date and saving it with the drawing because the DWG should only change when someone edits it. A saved date would make every export a change to the drawing, and would read as the day the drawing was last changed when it is only the day it was last plotted.

## Consequences

- The date is today's date at the start of the plotting, read from `CDATE`, the same in every PDF of one run.
- The Дата cell is found from the Дата head and the cell's lines. On a later аркуш of a специфікація, whose heads are the title block's bottom row, the date goes in the top row of the Дата column, two rows above the head; elsewhere it goes in the row below the head. Rows are taken to be 5 mm, as on the company's title blocks.
- A date already written in the cell is written over only in the PDF. One inside a block can't be edited, so that PDF keeps the old date and PDFALL warns.
- After PDFALL the drawing counts as modified even though nothing in it changed, as it already did from switching the шар заливки off and on.
