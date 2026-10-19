# One pattern for the names of the exported PDFs

Every PDF PDFALL and merge.exe write is named `<марка> <вид> <NN>[ <варіант>].pdf`:

- `<марка>` exactly as typed in the title block;
- `<вид>` is `лист` or `специфікація`, or for a combined document `загальний` or `загальний друк`, which have no number;
- `<NN>` is the sheet number with at least two digits;
- `<варіант>` is `без заливки`, only on a лист.

So a марка 1ЧП has `1ЧП лист 01.pdf`, `1ЧП лист 01 без заливки.pdf`, `1ЧП специфікація 01.pdf`, `1ЧП загальний.pdf` and `1ЧП загальний друк.pdf`. Every word of the name is lower case; the марка keeps its case because it is a code.

The names used to mix `Загальний` with `лист`, write a специфікація's sheets as `специфікація лист N` (a лист again), and leave `лист 10` ahead of `лист 2` in every tool that sorts by character. Two-digit numbers and one case fix those. The pattern also puts the three sorts of file in an order that reads the same everywhere: `загальний`, `загальний друк`, `лист …`, `специфікація …`.

## Consequences

- PDFs under the old names (`лист 1`, `специфікація лист 1`, `Загальний`) are still recognised. PDFALL deletes them before it plots a марка, and merge.exe offers to rename them to the new names, as it does for any other name that differs only in form. The old forms can be dropped from `pa:ours-p` and `parse` once nobody has them any more.
- Windows file names are not case-sensitive, so `Загальний.pdf` and `загальний.pdf` are one file there; the rename only changes how it is written.
- A марка that Windows does not allow in a file name (`\ / : * ? " < > |`) stops PDFALL before it plots, and PDFLIST and PDFSPEC refuse to write one into a name cell.
- The folder `exported files` keeps its name. It is the one English word left in the names; it is set by `files.folder` in `messages.json`.
