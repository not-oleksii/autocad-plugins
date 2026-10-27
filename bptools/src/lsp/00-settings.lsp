;;; BPTOOLS: tools for drawing the листи of a джгут, so every label has the same look.
;;;   BPPOS     a позиційний номер on a leader, numbered on across the марка
;;;   BPPIN     номери контактів, one per click
;;;   BPWIRE    колір проводу, from one list
;;;   BPNAME    назва роз'єму
;;;   BPVIEW    the «Вигляд з …» note
;;;   BPFIG     the «Рис. N» caption, numbered on across the марка
;;;   BPSTYLE   gives texts already drawn the style of a kind of label
;;;   BPNEW     a new drawing from the BPTOOLS template
;;; The ribbon tab also has TEXTALIGN and MLEADERALIGN, AutoCAD's own alignment commands.
;;;
;;; Terms are defined in GLOSSARY.md, the design in docs/adr. Every command first brings the
;;; стиль оформлення into the drawing and puts back what someone changed in it (docs/adr/0001).
;;; The source is split into src\lsp\*.lsp and the helpers every plugin shares, ..\common\lsp\*.lsp,
;;; which build.bat joins in name order into one bptools.lsp (../docs/adr/0002). Each file's header
;;; lists the functions the other files may call.

(vl-load-com)

(setq *bptools-version* "0.0.0")

;;; ---- Стиль оформлення -------------------------------------------------------
;;; One text style per kind of label, ISOCPEUR italic (ГОСТ 2.304 type B), at a fixed height in mm
;;; on the sheet (рамки are drawn full size). As (kind style-name height keyword): kind is how the
;;; code names it, keyword the word BPSTYLE offers for it. Change a height here, never label by label.
(setq *bptools-styles*
  '(("pos"       "Позиційний номер"     5.0 "Позиційний")
    ("pin"       "Номер контакту"       2.5 "Контакт")
    ("pin-small" "Номер контакту малий" 1.8 "Малий")
    ("wire"      "Колір проводу"        2.5 "Колір")
    ("name"      "Назва роз'єму"        3.5 "Назва")
    ("view"      "Вигляд"               3.5 "Вигляд")
    ("figure"    "Підпис рисунка"       5.0 "Рисунок")
    ("note"      "Примітка"             3.5 "Примітка")
    ("dim"       "Розміри"              3.5 "Розміри")))

;; The font of every style: ISOCPEUR italic, which AutoCAD installs into Windows\Fonts.
(setq *bptools-font* "isocpeui.ttf")

;; The layer every label goes on: never a шар заливки, so no label is lost from the листи без заливки.
(setq *bptools-layer* "Написи")

;; The multileader style of позиційні номери (the number on a shelf, a dot on the part, ГОСТ 2.109)
;; and the dimension style, both named after their text style.
(setq *bptools-pos-style* "Позиційний номер")
(setq *bptools-dim-style* "Розміри")

;; How AutoCAD words Esc in a language other than English, as a wcmatch pattern (Russian:
;; «Функция прервана»).
(setq *bptools-cancel-words* "*рерван*")

;; The folder holding bptools.lsp and BPTOOLS.dwt: the installed BPTOOLS.bundle\Contents.
;; Set it before loading this file to run BPTOOLS from another folder.
(if (not *bptools-home*)
  (setq *bptools-home*
    (cond ((findfile "bptools.lsp") (vl-filename-directory (findfile "bptools.lsp")))
          ((strcat (getenv "APPDATA") "\\Autodesk\\ApplicationPlugins\\BPTOOLS.bundle\\Contents")))))
