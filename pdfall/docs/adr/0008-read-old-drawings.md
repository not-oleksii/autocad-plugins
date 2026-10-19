# Read old drawings and plot in any AutoCAD language, without settings

Colleagues' old projects use an earlier title block and colleagues run AutoCAD in other languages, and PDFALL 1.8.0 failed on both. We made PDFALL recognise the differences by itself rather than add settings, because a setting such as "old title block" or "fill layer name" is one more thing a colleague must get right for each drawing, and it fails quietly when it is wrong. Where PDFALL can't tell, it still refuses with a message.

What PDFALL now reads:

- **The title block decides лист or специфікація; the рамка only decides the paper.** An A3 рамка is a лист. An A4 рамка is a лист when its title block has Масштаб, as a Складальний кресленик does, and a специфікація otherwise. Old drawings put a parts list on an A4 лист, and calling it a специфікація would have named it `специфікація 01` and dropped its без заливки copy.
- **A марка alone in the name cell** ("M1" rather than "Джгут M1") counts, but only inside the name cell, so a connector label near the title block isn't read as one. `Формат` joined the words that are never a product, because "Формат А3" was read as the марка А3.
- **A number written after its label in the same row** ("Аркушiв", then "1"), as well as below it. Labels are compared with Latin lookalike letters made Cyrillic, as марки are. PDFNUM writes into such a title block as a text of its own after the label, because appending to an MTEXT label would spill out of its cell.
- **No шар заливки** is a warning, not an error: the без заливки copy is the same as the filled one, so загальний друк stays complete and merge.exe needs no special case.
- **A рамка within 3 mm of 420x297 or 210x297** (one old drawing has 210x295) is plotted at 1:1 with a warning. Every рамка is now plotted at 1:1 instead of Fit, which gave 1:1 only for exact sizes.

**Paper sizes go to `-PLOT` by their canonical names** (`ISO_full_bleed_A3_(420.00_x_297.00_MM)`). AutoCAD translates the names it shows, so a Russian AutoCAD didn't know `ISO full bleed A3 (420.00 x 297.00 MM)`. `-PLOT` then quit without a word, and every answer after it ran as a command: a screen of `Неизвестная команда "M"`. PDFALL now checks that `-PLOT` is still running after the paper size (`CMDNAMES` holds English names in any language) and otherwise stops with a message.

## Consequences

- The Russian-language case couldn't be tested here: AutoCAD's `/l ru-RU` still shows English. The canonical names are accepted by the English AutoCAD, and the refused-paper path is tested with a name no AutoCAD knows.
- merge.exe confirms a lone марка only when it equals the file's марка, and never reports it as a mismatch, since any text in the title block could look like one. It now reads only the rightmost 570 points of the page's bottom edge (the title block), because old drawings put captions such as "контактів X6" near the bottom, and it skips one-letter "product" words, which are pieces of a word split by a font change.
- The 3 mm tolerance means a 417 to 423 mm line is taken as a рамка side. Title-block and table lines are much shorter, so this hasn't mattered.
