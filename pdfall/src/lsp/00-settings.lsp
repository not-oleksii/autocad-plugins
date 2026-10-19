;;; PDFALL: plot every лист and специфікація drawn in Model space to PDF, then merge them.
;;; PDFNUM: fill in the empty Аркуш and Аркушів cells of their title blocks.
;;; PDFLIST, PDFSPEC: paste an empty рамка with its title block for a лист or a специфікація.
;;;
;;; Terms are defined in GLOSSARY.md, the design in docs/adr/0001-plot-from-model-space-with-lisp.md.
;;; install.bat installs it as PDFALL.bundle, which AutoCAD loads by itself at startup.
;;; Type PDFALL in a saved drawing.
;;;
;;; What it does:
;;;   1. Finds every рамка (the dash-dot 420x297 or 210x297 border) in Model space.
;;;   2. Reads марка, Аркуш and Аркушів from each рамка's title block.
;;;   3. Checks every марка; if anything is wrong, nothing is plotted.
;;;   4. Writes "exported files\<марка>\" next to the drawing:
;;;        <марка> лист NN.pdf, <марка> лист NN без заливки.pdf, <марка> специфікація NN.pdf
;;;   5. Runs merge.exe on "exported files" to build Загальний and Загальний друк.
;;;
;;; The source is split into src\lsp\*.lsp, which build.bat joins in name order into one pdfall.lsp
;;; that AutoCAD loads (docs/adr/0004). Each file's header lists the functions the other files may call.

(vl-load-com)

(setq *pdfall-version* "1.7.0")

;;; ---- Settings ---------------------------------------------------------------

;; Every name the шар заливки may have. Add the new name here if you ever rename it.
(setq *pdfall-fill-layers* '("Цвет" "Колір"))

;; PDFALL.pc3 is AutoCAD PDF (General Documentation) with "open in viewer" off, so a run does
;; not open dozens of viewer windows. PDFALL copies it into the Plotters folder on its first run;
;; if that fails, the original is used.
(setq *pdfall-devices* '("PDFALL.pc3" "AutoCAD PDF (General Documentation).pc3"))
(setq *pdfall-paper-sheet* "ISO full bleed A3 (420.00 x 297.00 MM)")
(setq *pdfall-paper-spec* "ISO full bleed A4 (210.00 x 297.00 MM)")

;; The folder holding pdfall.lsp, merge.exe and PDFALL.pc3: the installed PDFALL.bundle\Contents.
;; Set it before loading this file to run PDFALL from another folder.
(if (not *pdfall-home*)
  (setq *pdfall-home*
    (cond ((findfile "pdfall.lsp") (vl-filename-directory (findfile "pdfall.lsp")))
          ((strcat (getenv "APPDATA") "\\Autodesk\\ApplicationPlugins\\PDFALL.bundle\\Contents")))))

;; The program that combines the PDFs into Загальний and Загальний друк; nil plots without merging.
(setq *pdfall-merge* (strcat *pdfall-home* "\\merge.exe"))
