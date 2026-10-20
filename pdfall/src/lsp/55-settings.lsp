;;; ---- Settings ---------------------------------------------------------------
;;; What PDFLIST and PDFTEXT paste and what goes in the name cell, kept per user with setenv so an
;;; update keeps them; nothing about exporting is a setting (docs/adr/0009). Other files may call:
;;;   pa:setting pa:set-setting  read and write one setting
;;;   pa:template pa:list-file pa:text-file  the templates to paste, from *pa-templates*
;;;   pa:list-sizes pa:list-orients  the sizes and orientations a лист standard has
;;;   pa:form-name     how a template reads in a message: "лист СКД A3 горизонтальний"
;;;   pa:prefix pa:line2 pa:name-text pa:name-shown  the name cell's text, and as a message shows it
;;;   pa:prefix-error  why a custom prefix can't be used, or nil
;;;
;;; Settings and their values:
;;;   List        the лист template as standard_size+orientation, e.g. spdbv_A3l
;;;   Text        the текстовий документ standard: skd or spdb
;;;   Prefix      std (the label "prefix", Джгут), custom or none
;;;   PrefixText  the custom prefix, kept when another choice is made
;;;   Line2       std (the label "list-line2", Складальне креслення), custom or none
;;;   Line2Text   the custom second line

(setq *pa-setting-defaults*
  '(("List" . "spdbv_A3l") ("Text" . "skd") ("Prefix" . "std") ("PrefixText" . "")
    ("Line2" . "std") ("Line2Text" . "")))

(defun pa:setting (key / v)
  (setq v (getenv (strcat "PDFALL_" key)))
  (if (and v (/= v "")) v (cdr (assoc key *pa-setting-defaults*))))

(defun pa:set-setting (key value)
  ;; An empty value would read back as the default, so it is stored as a single space.
  (setenv (strcat "PDFALL_" key) (if (= value "") " " value)))

;;; ---- Templates --------------------------------------------------------------

(defun pa:template (file) (assoc file *pa-templates*))

(defun pa:list-file (/ f)
  ;; The лист template chosen in the settings, or the default one when that isn't there any more.
  (setq f (strcat "PDFALL_list_" (pa:setting "List")))
  (strcat (if (pa:template f) f (strcat "PDFALL_list_" (cdr (assoc "List" *pa-setting-defaults*)))) ".dwg"))

(defun pa:text-file (page / std)
  ;; The template of page "1" or "2" of a текстовий документ in the chosen standard.
  (setq std (pa:setting "Text"))
  (if (not (pa:template (strcat "PDFALL_text_" std "_1"))) (setq std (cdr (assoc "Text" *pa-setting-defaults*))))
  (strcat "PDFALL_text_" std "_" page ".dwg"))

(defun pa:list-sizes (std / out)
  ;; The sizes of the листи of a standard, A1 first.
  (foreach tp *pa-templates*
    (if (and (= (cadr tp) "list") (= (caddr tp) std) (not (member (cadddr tp) out)))
      (setq out (cons (cadddr tp) out))))
  (acad_strlsort out))

(defun pa:list-orients (std size / out)
  ;; "l" and "p" as a лист of that standard and size has them.
  (foreach o '("l" "p")
    (if (pa:template (strcat "PDFALL_list_" std "_" size o)) (setq out (cons o out))))
  (reverse out))

(defun pa:std-name (std)
  (cond ((= std "skd") (pa:msg "std.skd" nil)) ((= std "spdb") (pa:msg "std.spdb" nil)) ((pa:msg "std.spdbv" nil))))

(defun pa:orient-name (o) (if (= o "l") (pa:msg "orient.l" nil) (pa:msg "orient.p" nil)))

(defun pa:form-name (file / tp)
  ;; A лист template as it reads in a message, e.g. "СКД A3 горизонтальний".
  (setq tp (pa:template (vl-filename-base file)))
  (strcat (pa:std-name (caddr tp)) " " (cadddr tp) " "
          (pa:orient-name (if (> (nth 5 tp) (nth 6 tp)) "l" "p"))))

;;; ---- The name cell ----------------------------------------------------------

(defun pa:prefix ()
  (cond ((= (pa:setting "Prefix") "none") "")
        ((= (pa:setting "Prefix") "custom") (vl-string-trim " " (pa:setting "PrefixText")))
        ((pa:label "prefix"))))

(defun pa:line2 ()
  (cond ((= (pa:setting "Line2") "none") "")
        ((= (pa:setting "Line2") "custom") (vl-string-trim " " (pa:setting "Line2Text")))
        ((pa:label "list-line2"))))

(defun pa:prefix-error (s)
  ;; Why s can't be the custom prefix, or nil. A digit would make a word of it read as the марка.
  (cond ((= (vl-string-trim " " s) "") (pa:msg "settings.prefix-empty" nil))
        ((vl-some 'pa:digit-p (vl-string->list s)) (pa:msg "settings.prefix-digit" nil))))

(defun pa:mtext-escape (s / out)
  ;; s as MTEXT shows it literally: \ { and } would be formatting codes.
  (setq out "")
  (foreach c (vl-string->list s)
    (setq out (strcat out (if (member c '(92 123 125)) "\\" "") (chr c))))
  out)

(defun pa:name-shown (marka / p l)
  ;; A лист's name cell as a message shows it: "Джгут 1ЧП / Складальне креслення".
  (setq p (pa:prefix) l (pa:line2))
  (strcat (if (= p "") "" (strcat p " ")) marka (if (= l "") "" (strcat " / " l))))

(defun pa:name-text (kind marka / p l)
  ;; What the name cell of a pasted рамка of kind says, as MTEXT contents: the prefix, the марка
  ;; and, on a лист, the second line on a line of its own.
  (setq p (pa:prefix) l (if (= kind "list") (pa:line2) ""))
  (strcat (if (= p "") "" (strcat (pa:mtext-escape p) " ")) (pa:mtext-escape marka)
          (if (= l "") "" (strcat "\\P" (pa:mtext-escape l)))))
