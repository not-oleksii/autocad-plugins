;;; ---- Text -------------------------------------------------------------------
;;; String helpers that every other file may use:
;;;   pa:msg pa:label pa:file  the texts of messages.json
;;;   pa:split pa:words pa:digit-p pa:digits-p pa:marka-p pa:cyr
;;;   pa:lower pa:pad pa:bad-char
;;;
;;; build.bat writes messages.json into *pa-messages*, *pa-labels* and *pa-files* just before
;;; this file, and fails if the code uses a key or {name} that messages.json doesn't have, or a
;;; Ukrainian string outside 00-settings.lsp. So every key is a literal string, and pa:msg gets
;;; its values as a literal (list "name" value ...).

(defun pa:msg (key args / s k v p)
  ;; The message key with each {name} replaced by its value from args, (name value name value ...).
  ;; Numbers are written as integers.
  (setq s (cond ((cdr (assoc key *pa-messages*))) ((strcat "{" key "}"))))
  (while args
    (setq k (strcat "{" (car args) "}")
          v (cadr args)
          v (cond ((= (type v) 'INT) (itoa v)) ((numberp v) (rtos v 2 0)) (v))
          args (cddr args)
          p 0)
    ;; search on after each value, so a value that holds the {name} itself can't loop
    (while (setq p (vl-string-search k s p))
      (setq s (strcat (substr s 1 p) v (substr s (+ p 1 (strlen k))))
            p (+ p (strlen v)))))
  s)

(defun pa:label (key) (cdr (assoc key *pa-labels*)))
(defun pa:file (key) (cdr (assoc key *pa-files*)))

(defun pa:cyr (s)
  ;; Latin letters that look identical to Cyrillic ones, turned into the Cyrillic letter.
  (vl-string-translate (pa:label "lookalike-latin") (pa:label "lookalike-cyrillic") s))

(defun pa:lower (s)
  ;; s in lower case; strcase alone leaves Cyrillic letters as they are.
  (vl-string-translate (pa:label "upper") (pa:label "lower") (strcase s T)))

(defun pa:pad (n)
  ;; A sheet number as it is written in a file name: at least two digits.
  (if (< n 10) (strcat "0" (itoa n)) (itoa n)))

(defun pa:bad-char (s)
  ;; The first character of s that Windows doesn't allow in a file name, or nil.
  (vl-some '(lambda (c) (if (vl-string-position c s) (chr c)))
           (vl-string->list "\\/:*?\"<>|")))

(defun pa:split (s sep / out p)
  (while (setq p (vl-string-search sep s))
    (setq out (cons (substr s 1 p) out)
          s (substr s (+ p 1 (strlen sep)))))
  (reverse (cons s out)))

(defun pa:words (s)
  (vl-remove "" (pa:split (vl-string-translate "\t\n" "  " s) " ")))

(defun pa:digit-p (c) (<= 48 c 57))
(defun pa:letter-p (c) (and (or (<= 65 c 90) (<= 97 c 122) (>= c 192)) (/= c 8470)))

(defun pa:digits-p (s)
  (and s (/= s "") (vl-every 'pa:digit-p (vl-string->list s))))

(defun pa:marka-p (s / codes)
  ;; A марка has at least one letter and one digit, e.g. 1ЧП, К2, Х1А1Р.
  (setq codes (vl-string->list s))
  (and (vl-some 'pa:digit-p codes) (vl-some 'pa:letter-p codes)))
