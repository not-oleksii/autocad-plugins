;;; ---- Марка text -------------------------------------------------------------
;;; PDFALL's string helpers, next to the shared ones of common\lsp\10-text.lsp (pa:msg, pa:split,
;;; pa:lower, pa:file-safe...). Other files may call:
;;;   pa:marka-p pa:marka-error  whether a word looks like a марка, and why it can't be one
;;;   pa:cyr           Latin lookalike letters turned into Cyrillic, to compare title-block texts
;;;   pa:title-name    words as one word that can name a folder and its files

(defun pa:cyr (s)
  ;; Latin letters that look identical to Cyrillic ones, turned into the Cyrillic letter.
  (vl-string-translate (pa:label "lookalike-latin") (pa:label "lookalike-cyrillic") s))

(defun pa:title-name (words / s)
  ;; words as one word that can name a folder and its files, or nil: joined by _, with the characters
  ;; Windows forbids left out, so ДВНЗ "ПДАБА" becomes ДВНЗ_ПДАБА. One word, since merge.exe reads the
  ;; марка of a file as the first word of its name.
  (if words
    (progn
      (setq s (pa:file-safe (apply 'strcat (cons (car words) (mapcar '(lambda (w) (strcat "_" w)) (cdr words))))))
      (while (vl-string-search "__" s) (setq s (vl-string-subst "_" "__" s)))
      (setq s (vl-string-trim "_" s))
      (if (/= s "") s))))

(defun pa:marka-p (s / codes)
  ;; Whether s looks like the usual марка, with a letter and a digit (1ЧП, К2, Х1А1Р), which the
  ;; reader picks out of a name cell wherever it stands. A марка may also be any other word.
  (setq codes (vl-string->list s))
  (and (vl-some 'pa:digit-p codes) (vl-some 'pa:letter-p codes)))

(defun pa:marka-error (s)
  ;; Why s can't be a марка, or nil. A марка is one word of any characters a file name may have
  ;; ("1ЧП", "Лорем"): it begins the name of every PDF, and the name cell is read up to it.
  (cond ((= s "") (pa:msg "paste.marka-empty" nil))
        ((vl-string-search " " s) (pa:msg "paste.marka-bad" nil))
        ((pa:bad-char s) (pa:msg "paste.marka-char" (list "char" (pa:bad-char s))))))
