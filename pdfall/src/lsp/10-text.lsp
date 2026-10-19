;;; ---- Text -------------------------------------------------------------------
;;; String helpers that every other file may use:
;;;   pa:split pa:words pa:digit-p pa:digits-p pa:marka-p pa:cyr

(defun pa:cyr (s)
  ;; Latin letters that look identical to Cyrillic ones, turned into the Cyrillic letter.
  (vl-string-translate "ABCEHIKMOPTXYaceiopxy" "АВСЕНІКМОРТХУасеіорху" s))

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
