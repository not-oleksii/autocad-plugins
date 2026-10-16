# Plot from Model space with a LISP command, not Layouts and Publish

Every лист and специфікація is drawn side by side in Model space, many марки to one DWG, and the PDFs are made by one AutoLISP command (`PDFALL`). The command finds each рамка, reads its title block and plots the рамка as a window. We kept this instead of AutoCAD's usual approach (one paper-space Layout per sheet with saved Page Setups, plotted through Publish) for two reasons. Moving to Layouts would mean rebuilding every existing drawing. And Publish names files after the drawing and Layout, so it can neither turn off the шар заливки to make the без заливки copy nor name files from the title block.

## Consequences

- File names, orientation and paper size come from the drawing alone (title block and рамка shape), never from a person's choice in the Plot dialog.
- The command checks the whole drawing and plots nothing if any марка is inconsistent, so `exported files` never holds a half-updated set.
