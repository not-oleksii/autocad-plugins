;;; ---- Settings ---------------------------------------------------------------
;;; What the «Лист» button (PDFLIST) pastes and what goes in the name cell, kept per user with setenv
;;; so an update keeps them; nothing about exporting is a setting (docs/adr/0009). Other files may call:
;;;   pa:setting pa:set-setting  read and write one setting
;;;   pa:template      a template of *pa-templates*
;;;   pa:chosen pa:chosen-kind pa:list-file pa:text-file  what PDFLIST pastes
;;;   pa:docs pa:doc-sizes pa:doc-orients pa:doc-id pa:doc-file  the documents it may paste
;;;   pa:doc-name pa:form-name pa:chosen-shown  how they read in the dialog and in messages
;;;   pa:last-marka pa:remember-marka  the марка pasted last, which PDFLIST offers again
;;;   pa:prefix-of pa:line2-of pa:prefix pa:line2  the name cell's first words and second line
;;;   pa:name-text pa:name-line pa:name-shown  the name cell's text, and as the dialog and messages show it
;;;   pa:prefix-error  why a custom prefix can't be used, or nil
;;;
;;; Settings and their values:
;;;   Paste       what PDFLIST pastes: a лист as list_<standard>_<size><orientation>, e.g.
;;;               list_spdbv_A3l, or the pages of a текстовий документ as text_<standard>, e.g. text_skd
;;;   Marka       the марка pasted last
;;;   Prefix      std (the label "prefix", Джгут), custom or none
;;;   PrefixText  the custom prefix, kept when another choice is made
;;;   Line2       std (the label "list-line2", Складальне креслення), custom or none
;;;   Line2Text   the custom second line
;;; A document is list_<standard> or text_<standard>.

(setq *pa-setting-defaults*
  '(("Paste" . "list_spdbv_A3l") ("Marka" . "") ("Prefix" . "std") ("PrefixText" . "")
    ("Line2" . "std") ("Line2Text" . "")))

(defun pa:setting (key / v)
  (setq v (getenv (strcat "PDFALL_" key)))
  (if (and v (/= v "")) v (cdr (assoc key *pa-setting-defaults*))))

(defun pa:set-setting (key value)
  ;; An empty value would read back as the default, so it is stored as a single space.
  (setenv (strcat "PDFALL_" key) (if (= value "") " " value)))

;;; ---- Templates --------------------------------------------------------------

(defun pa:template (file) (assoc file *pa-templates*))

(setq *pa-docs* '("list_skd" "list_spdb" "list_spdbv" "text_skd" "text_spdb"))

(defun pa:docs () *pa-docs*)

(defun pa:doc-kind (doc) (if (wcmatch doc "text_*") "text" "list"))
(defun pa:doc-std (doc) (substr doc 6))

(defun pa:doc-sizes (doc / out)
  ;; The sizes the document has, A1 first: a текстовий документ is A4 only.
  (foreach tp *pa-templates*
    (if (and (= (cadr tp) (pa:doc-kind doc)) (= (caddr tp) (pa:doc-std doc)) (not (member (cadddr tp) out)))
      (setq out (cons (cadddr tp) out))))
  (acad_strlsort out))

(defun pa:doc-id (doc size orient)
  ;; The value of the Paste setting for the document in that size and orientation.
  (if (= (pa:doc-kind doc) "text") doc (strcat doc "_" size orient)))

(defun pa:doc-file (id / tp)
  ;; The template of what the Paste setting id pastes (of its first page), without .dwg; nil when
  ;; there is none.
  (if (setq tp (cond ((pa:template (strcat "PDFALL_" id))) ((pa:template (strcat "PDFALL_" id "_1")))))
    (car tp)))

(defun pa:doc-orients (doc size / out tp)
  ;; "l" and "p" as the document has them in that size.
  (foreach o '("l" "p")
    (if (setq tp (pa:template (pa:doc-file (pa:doc-id doc size o))))
      (if (= o (if (> (nth 5 tp) (nth 6 tp)) "l" "p")) (setq out (cons o out)))))
  (reverse out))

(defun pa:chosen (/ id)
  ;; The Paste setting, or its default when there is no such template any more.
  (setq id (pa:setting "Paste"))
  (if (pa:doc-file id) id (cdr (assoc "Paste" *pa-setting-defaults*))))

(defun pa:chosen-kind () (if (wcmatch (pa:chosen) "text_*") "text" "list"))

(defun pa:list-file () (strcat (pa:doc-file (pa:chosen)) ".dwg"))

(defun pa:text-file (page)
  ;; The template of page "1" or "2" of the chosen текстовий документ.
  (strcat "PDFALL_" (pa:chosen) "_" page ".dwg"))

(defun pa:std-name (std)
  (cond ((= std "skd") (pa:msg "std.skd" nil)) ((= std "spdb") (pa:msg "std.spdb" nil)) ((pa:msg "std.spdbv" nil))))

(defun pa:orient-name (o) (if (= o "l") (pa:msg "orient.l" nil) (pa:msg "orient.p" nil)))

(defun pa:doc-name (doc)
  ;; "Лист СКД" or "Текстовий документ СКД", as the dialog lists them.
  (if (= (pa:doc-kind doc) "text")
    (pa:msg "settings.doc-text" (list "std" (pa:std-name (pa:doc-std doc))))
    (pa:msg "settings.doc-list" (list "std" (pa:std-name (pa:doc-std doc))))))

(defun pa:form-name (file / tp)
  ;; A лист template as it reads in a message, e.g. "СКД A3 горизонтальний".
  (setq tp (pa:template (vl-filename-base file)))
  (strcat (pa:std-name (caddr tp)) " " (cadddr tp) " "
          (pa:orient-name (if (> (nth 5 tp) (nth 6 tp)) "l" "p"))))

(defun pa:chosen-shown (/ id)
  ;; What PDFLIST pastes, as a message shows it: "лист СКД A3 горизонтальний".
  (setq id (pa:chosen))
  (if (wcmatch id "text_*")
    (pa:msg "paste.text" (list "std" (pa:std-name (pa:doc-std id))))
    (pa:msg "paste.list" (list "form" (pa:form-name (pa:list-file))))))

;;; ---- The марка --------------------------------------------------------------

(defun pa:last-marka ()
  ;; The марка pasted or set last, or nil.
  (cond (*pdfall-marka*)
        ((/= (vl-string-trim " " (pa:setting "Marka")) "") (vl-string-trim " " (pa:setting "Marka")))))

(defun pa:remember-marka (marka)
  (pa:set-setting "Marka" marka)
  (setq *pdfall-marka* marka))

;;; ---- The name cell ----------------------------------------------------------

(defun pa:prefix-of (choice text)
  ;; The prefix for the choice std, custom (with the custom text) or none.
  (cond ((= choice "none") "") ((= choice "custom") (vl-string-trim " " text)) ((pa:label "prefix"))))

(defun pa:line2-of (choice text)
  (cond ((= choice "none") "") ((= choice "custom") (vl-string-trim " " text)) ((pa:label "list-line2"))))

(defun pa:prefix () (pa:prefix-of (pa:setting "Prefix") (pa:setting "PrefixText")))
(defun pa:line2 () (pa:line2-of (pa:setting "Line2") (pa:setting "Line2Text")))

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

(defun pa:name-line (prefix marka line2)
  ;; The name cell's text in one line: "Джгут 1ЧП Складальне креслення".
  (vl-string-trim " " (strcat prefix " " marka " " line2)))

(defun pa:name-shown (kind marka)
  ;; The name cell of a pasted рамка of kind, in one line as a message shows it.
  (pa:name-line (pa:prefix) marka (if (= kind "list") (pa:line2) "")))

(defun pa:name-text (kind marka / p l)
  ;; What the name cell of a pasted рамка of kind says, as MTEXT contents: the prefix, the марка
  ;; and, on a лист, the second line on a line of its own.
  (setq p (pa:prefix) l (if (= kind "list") (pa:line2) ""))
  (strcat (if (= p "") "" (strcat (pa:mtext-escape p) " ")) (pa:mtext-escape marka)
          (if (= l "") "" (strcat "\\P" (pa:mtext-escape l)))))
