;;; PDFALL: plot every лист, специфікація and текстовий документ drawn in Model space to PDF, then merge them.
;;; PDFNUM: fill in the empty Аркуш and Аркушів cells of their title blocks.
;;; PDFLIST, PDFSPEC: paste an empty рамка with its title block for a лист or текстовий документ,
;;; or for a специфікація; PDFSETTINGS: choose what PDFLIST pastes.
;;;
;;; Terms are defined in GLOSSARY.md, the design in docs/adr/0001-plot-from-model-space-with-lisp.md.
;;; install.bat installs it as PDFALL.bundle, which AutoCAD loads by itself at startup.
;;; Type PDFALL in a saved drawing.
;;;
;;; What it does:
;;;   1. Finds every рамка (the dash-dot edge of an A0-A5 sheet with a title block) in Model space.
;;;   2. Reads марка, Аркуш and Аркушів from each рамка's title block.
;;;   3. Checks every марка; if anything is wrong, nothing is plotted.
;;;   4. Writes "exported files\<марка>\" next to the drawing:
;;;        <марка> лист NN.pdf, <марка> лист NN без заливки.pdf, <марка> специфікація NN.pdf,
;;;        <марка> текстовий документ NN.pdf
;;;   5. Runs merge.exe on "exported files" to build Загальний and Загальний друк.
;;;
;;; The source is split into src\lsp\*.lsp, which build.bat joins in name order into one pdfall.lsp
;;; that AutoCAD loads (docs/adr/0004). Each file's header lists the functions the other files may call.

(vl-load-com)

(setq *pdfall-version* "1.9.1")

;;; ---- Settings ---------------------------------------------------------------

;; Every name the шар заливки may have. Add the new name here if you ever rename it.
(setq *pdfall-fill-layers* '("Цвет" "Колір"))

;; PDFALL.pc3 is AutoCAD PDF (General Documentation) with "open in viewer" off, so a run does
;; not open dozens of viewer windows. PDFALL copies it into the Plotters folder on its first run;
;; if that fails, the original is used.
(setq *pdfall-devices* '("PDFALL.pc3" "AutoCAD PDF (General Documentation).pc3"))
;; The sheet sizes a рамка may have, in mm as (name width height) in portrait; a рамка may be
;; either way round (docs/adr/0009).
(setq *pdfall-sizes* '(("A0" 841 1189) ("A1" 594 841) ("A2" 420 594) ("A3" 297 420) ("A4" 210 297) ("A5" 148 210)))
;; The paper a рамка is plotted on, by its canonical name, which AutoCAD doesn't translate: a Russian
;; AutoCAD doesn't know "ISO full bleed A3 (420.00 x 297.00 MM)", the English name (docs/adr/0008).
;; {size} is the name above, {w} and {h} the рамка's width and height.
(setq *pdfall-paper* "ISO_full_bleed_{size}_({w}.00_x_{h}.00_MM)")

;; How AutoCAD words Esc ("Function cancelled") in a language other than English, as a wcmatch
;; pattern. LISP can't make AutoCAD say it, so add the wording when a new language shows
;; "Помилка ...: <it>" after Esc.
(setq *pdfall-cancel-words* "*рерван*")

;; The folder holding pdfall.lsp, merge.exe and PDFALL.pc3: the installed PDFALL.bundle\Contents.
;; Set it before loading this file to run PDFALL from another folder.
(if (not *pdfall-home*)
  (setq *pdfall-home*
    (cond ((findfile "pdfall.lsp") (vl-filename-directory (findfile "pdfall.lsp")))
          ((strcat (getenv "APPDATA") "\\Autodesk\\ApplicationPlugins\\PDFALL.bundle\\Contents")))))

;; The program that combines the PDFs into Загальний and Загальний друк; nil plots without merging.
(setq *pdfall-merge* (strcat *pdfall-home* "\\merge.exe"))
