# AutoCAD Blueprints

Blueprint sets that are plotted from AutoCAD as one PDF per sheet and then combined into one PDF per марка for viewing and printing.

## Language

**Марка**:
The code that names one blueprint set, such as 1ЖП, 1П, 2П, К1 or X1A1Р. Every file in the set starts with it, spelled exactly as in the title block. It may mix Latin and Cyrillic letters (X1A1Р has a Latin X and A and a Cyrillic Р), so two марки that look alike can still be different codes.
_Avoid_: blueprint, project, code

**Лист**:
One numbered drawing sheet of a марка, such as a Складальний кресленик. Usually A3 landscape, but it may be any A size from A0 to A5 in either orientation; what makes it a лист is its full title block (СКД, СПДБ or СПДБ «Вироби»), not its size. All листи of a марка are numbered together, whatever their size. The file is `<марка> лист NN.pdf`. A file with no number in its name is read as лист 1.
_Avoid_: page, drawing

**Без заливки**:
The variant of a лист plotted with the шар заливки turned off, used for printing. Every лист has one, even a лист with no fills, and in a drawing with no шар заливки it is the same as the filled лист.
_Avoid_: print version, no-fill, unfilled

**Шар заливки**:
The one layer that holds the colour fills of a лист, such as the coloured wires. Turning it off is the only difference between a лист and its без заливки variant. Old drawings have none.
_Avoid_: colour layer, fill

**Специфікація**:
A numbered specification sheet of a марка, always A4 portrait, with the specification's shorter title block. It has only one variant, and that variant appears in both combined documents. A parts list drawn on a лист does not make it a специфікація.
_Avoid_: spec, bill of materials

**Текстовий документ**:
A numbered page of a text document of a марка, A4 portrait, with the same title blocks as a специфікація (40 mm on the first page, 15 mm after) but no specification table. Numbered on its own, after the специфікації in both combined documents. The file is `<марка> текстовий документ NN.pdf`.
_Avoid_: text page, explanatory note

**Рамка**:
The border that marks out one лист, специфікація or текстовий документ in the drawing: the edge of an A0–A5 sheet in either orientation (420x297 for A3 landscape, 210x297 for A4 portrait, 594x841 for A1 portrait...). Usually dash-dot (-.-.). A рамка a few millimetres off its size (an old drawing's 210x295) is still a рамка, but PDFALL warns about it.
_Avoid_: frame, layout, format

**Шаблон рамки**:
An empty рамка with its title block, kept as a DWG (`src\templates`) and pasted by PDFLIST (лист, in the standard, size and orientation chosen in the settings), PDFSPEC (специфікація, first or later аркуш) or PDFTEXT (текстовий документ). Its name cell gets the prefix, the марка and, on a лист, the second line chosen in the settings.
_Avoid_: blank, stamp

**Orientation**:
Landscape or portrait. Follows from the рамка when plotting, never chosen separately; when pasting, it is part of the лист's format chosen in the settings.
_Avoid_: layout (in AutoCAD a Layout is a paper-space tab, which these drawings do not use)

**Title block** (основний напис):
The stamp in the bottom-right corner of every лист and специфікація. It prints the product and марка in its name cell and the sheet number and count (Аркуш, Аркушів, or Арк. on continuation sheets). A лист has the full title block (55 mm high, with Літ., Маса and Масштаб); a специфікація has a 40 mm one on its first аркуш and a 15 mm one after that. Old drawings write the numbers to the right of Аркуш and Аркушів instead of below them, and may spell those labels with Latin lookalike letters (Аркушiв).
_Avoid_: штамп, stamp

**Name cell** (клітинка назви):
The title block cell that names the product and марка: the prefix, the марка, and on a лист a second line ("Джгут 1ЧП / Складальне креслення", or only "1ЧП"). The марка is its first word with a letter and a digit. Old drawings write only the марка there ("M1"). PDFLIST and PDFSPEC write the марка there; its text fills the cell and is centred in it, so it wraps only when the марка is too long for the cell.
_Avoid_: name field, title

**Prefix** (префікс):
The words before the марка in the name cell, "Джгут" by default. Chosen in the settings: Джгут, a custom one (any words without digits), or none.
_Avoid_: product word, title

**Дата cell** (клітинка Дата):
The title block cell that holds the date: in the Дата column, in the row below its head, or in the top row on a later аркуш of a специфікація. PDFALL writes the day of the export there in every PDF, as dd.mm.yy, without changing the drawing.
_Avoid_: date field, date stamp

**Загальний**:
The combined document of a марка: every filled лист in order, followed by every специфікація and then every текстовий документ in order. Its file is `<марка> загальний.pdf`.
_Avoid_: merged, combined, full set

**Загальний друк**:
The combined print document of a марка: every лист без заливки in order, followed by every специфікація and then every текстовий документ in order. Its file is `<марка> загальний друк.pdf`.
_Avoid_: print set, merged print
