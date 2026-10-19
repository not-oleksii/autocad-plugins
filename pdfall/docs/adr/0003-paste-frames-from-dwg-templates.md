# Paste рамки from DWG templates cut out of a real drawing

PDFLIST and PDFSPEC insert an empty рамка with its title block from three DWG files (a лист, the first аркуш of a специфікація, a later аркуш of one), insert it exploded, and write the марка into the name cell. `make_templates.ps1` cuts the DWGs out of the sample drawing with `-WBLOCK`, keeping the рамка, the title block form and the specification table heads, and none of the drawing, dates or table rows that were in the sample.

We chose this over drawing the рамки in LISP because the title block has about 100 lines and 20 labels in two text styles and a custom linetype, and a company title block gets changed by editing it in AutoCAD, not by editing LISP. A DWG also brings its layers, styles and linetype along when it is inserted, so it works in a drawing that has none of them. We chose it over keeping the рамки as blocks because PDFNUM edits the Аркуш label as plain text, and cannot edit text inside a block.

## Consequences

- A template's lower-left corner is the DWG's origin, and its name cell holds the text `МАРКА`, which is replaced when it is pasted. Editing a template must keep both.
- The pasted рамка follows the cursor, which only `-INSERT` with a pause gives, but that prompt does not accept Enter. A run is therefore ended with Esc, which PDFLIST and PDFSPEC catch around the insert to report what they pasted.
- The block that `-INSERT` makes is deleted after it is exploded, so a changed template is picked up the next time. That uses ActiveX, which the console AutoCAD that the tests run in doesn't have, so the tests leave the block there.
- `examples\` is kept out of git, so the templates are committed in `src\templates` and `make_templates.ps1` is run only when the sample's title blocks change.
