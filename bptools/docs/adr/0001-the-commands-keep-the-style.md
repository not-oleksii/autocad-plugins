# The commands keep the стиль оформлення, not a check at printing

Labels on the листи drift when several people edit a drawing: another text style here, a height of 3.11 there, a number not centred on its pin. Three ways to stop it were weighed: a template only, a check inside PDFALL's «Друк у PDF» that lists and fixes labels off the style, and commands that place each kind of label already in its style. We chose the template and the commands, and no check at printing.

- **The style is defined in BPTOOLS's code**, in `src\lsp\00-settings.lsp`: one text style per kind of label, ISOCPEUR italic at a fixed height (ГОСТ 2.304 type B; 5 mm for позиційні номери and captions, 3.5 for names, views, dimensions and notes, 2.5 for wire colours and pin numbers, 1.8 for the pins of small роз'єми), the «Розміри» dimension style, the «Позиційний номер» multileader style (the number on a shelf, a dot on the part, ГОСТ 2.109) and the «Написи» layer. The template `BPTOOLS.dwt` is built from the same code, so the two can't differ.
- **Every BPTOOLS command brings the style in first** (`bp:ensure-styles`): it makes what the drawing lacks and quietly puts back what someone changed (a height, a font, the layer turned off or locked). It touches only these names; other styles and texts of the drawing are left alone, and existing drawings are never cleaned up by themselves.
- **A label's kind is its text style.** Its height comes from the style, never typed, and BPSTYLE gives a text typed by hand the style of a kind.
- **Labels are centred on the point clicked** and go on «Написи», never on a шар заливки, so they are on the листи без заливки too.
- **No check at printing.** «Друк у PDF» stays as it is: printing is for getting the PDFs, and a list of style problems there would stop people at the moment they least want it.

## Considered options

- **A check in «Друк у PDF»** with a «Виправити» button. Rejected by the user: it would hold up every print and couple PDFALL to the style.
- **The template alone.** Rejected: colleagues keep working in old drawings, and nothing would stop a style being changed.
- **The styles kept in a library drawing**, inserted to bring them in. Not now: inserting a drawing doesn't overwrite a style that has been changed, and a style in code can be checked and restored field by field. The parts library of BPTOOLS 1.1.0 is built with the same styles.

## Consequences

- A height or a font changes in one place, `00-settings.lsp`, and reaches every drawing the next time someone uses a BPTOOLS command in it.
- A colleague who changes a BPTOOLS style by hand sees it put back; to change it for everyone, change `00-settings.lsp` and release.
- Labels drawn without BPTOOLS can still be off the style; BPSTYLE fixes them when someone notices.
