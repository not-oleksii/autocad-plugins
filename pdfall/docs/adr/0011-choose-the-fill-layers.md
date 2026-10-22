# Each user chooses the шари заливки

A лист без заливки is the лист plotted again with the шар заливки turned off. PDFALL used to know the шар заливки by two fixed names, `Цвет` and `Колір`, listed in `*pdfall-fill-layers*`. Colleagues fill on layers with other names, and changing that list meant editing the plugin. Now the шари заливки are a setting: a multi-select list in the PDFSETTINGS window, one or several layers. This reverses part of ADR 0009, which kept export free of settings.

- **Per user, by name.** The choice is kept with `setenv` like the other settings, as names separated by `;` (a layer name can't contain one), so an update keeps it. It applies to every drawing that has a layer of that name. `*pdfall-fill-layers*` (`Цвет`, `Колір`) is only the starting choice. We didn't save the choice in each drawing: a person fills on the same layers from drawing to drawing, and a per-drawing choice would have to be made again in every new drawing.
- **The choice replaces the defaults.** Once a user chooses, only the ticked layers count, so a `Колір` layer used for something else can be left out. Names a drawing doesn't have stay in the list, marked «немає в кресленні», so moving between drawings doesn't lose them.
- **Xrefs too.** A name also matches that layer inside an xref (`Колір` takes in `план|Колір`), because a fill that comes from an attached drawing should disappear from the лист без заливки too. The list shows an xref's layer by its own name, marked «у зовнішньому посиланні».
- **Compared in any case.** AutoCAD treats layer names without regard to case, and so does PDFALL. Its comparison lowers Cyrillic letters too, which `strcase` leaves as they are.
- **Asked, not guessed.** When a drawing has none of the chosen layers, PDFALL opens the settings window before plotting, says so at the top, and turns «Вставити» off. OK saves the choice and plots. Ticking nothing is allowed, for a drawing with no fills at all; then the листи без заливки come out the same as the filled ones, with the warning ADR 0008 describes. Cancel stops PDFALL without plotting. The window also says so when PDFSETTINGS is opened in such a drawing. Without a dialog (the console AutoCAD the tests run in), PDFALL skips the question and only warns.

## Consequences

- A drawing that has none of the chosen layers asks about them on every PDFALL run until the user ticks the right layers. For a drawing with no fills at all, that means pressing OK once more each time. We accepted this, because plotting a лист без заливки that still has its fill is the worse mistake.
- The window gets a third column, so it is wider.
- Layer 0 and Defpoints aren't offered: turning 0 off would hide the рамки themselves.
