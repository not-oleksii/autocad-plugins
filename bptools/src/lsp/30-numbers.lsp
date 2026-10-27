;;; ---- Numbers ----------------------------------------------------------------
;;; The number a new позиційний номер or Рис. caption is offered: the largest one in the same марка
;;; plus 1, since the специфікація and the figures belong to the whole марка, not to one лист.
;;; Which марка a point is in, PDFALL knows (../docs/adr/0003); without PDFALL, BPTOOLS counts
;;; across the whole drawing and says so once. A label outside every рамка counts with the others
;;; outside. The offer is only a default: the user may type any number. Other files may call:
;;;   bp:next-pos (pt)      the next позиційний номер for a label at pt (world coordinates)
;;;   bp:next-figure (pt)   the next Рис. number likewise
;;;   bp:figure-text (n caption)  a caption as it is written: «Рис. 7. Виконання …»

(defun bp:model (filter / ss i out)
  ;; The entities of Model space that filter selects.
  (if (setq ss (ssget "_X" (append filter '((410 . "Model")))))
    (repeat (setq i (sslength ss)) (setq out (cons (entget (ssname ss (setq i (1- i)))) out))))
  out)

(defun bp:leading-number (s / i)
  ;; The number s begins with, or nil.
  (setq i 0)
  (while (and (< i (strlen s)) (bp:digit-p (ascii (substr s (1+ i) 1)))) (setq i (1+ i)))
  (if (> i 0) (atoi (substr s 1 i))))

(defun bp:next-of (pt items / markas own)
  ;; items are (number point): the largest number of those in the марка of pt, plus 1.
  (if (and items (not pdfall:marka-at) (not *bp-whole-told*))
    (progn (princ (strcat "\n" (bp:msg "numbers.whole-drawing" nil))) (setq *bp-whole-told* T)))
  (if (and items pdfall:marka-at)
    (progn
      (setq markas (pdfall:marka-at (cons pt (mapcar 'cadr items)))
            own (car markas)
            items (vl-remove nil (mapcar '(lambda (it m) (if (= m own) it)) items (cdr markas))))
      (bp:log (list "numbers: marka" own "has" (mapcar 'car items)))))
  (1+ (apply 'max (cons 0 (mapcar 'car items)))))

(defun bp:next-pos (pt)
  ;; Every multileader whose text is a number counts, whoever drew it.
  (bp:next-of pt (vl-remove nil (mapcar '(lambda (e / n) (if (setq n (bp:leading-number (cond ((cdr (assoc 304 e))) ("")))) (list n (cdr (assoc 10 e)))))
                                        (bp:model '((0 . "MULTILEADER")))))))

(defun bp:next-figure (pt / prefix)
  ;; Every caption in the «Підпис рисунка» style that begins with Рис. and a number counts.
  (setq prefix (strcat (bp:label "figure") " "))
  (bp:next-of pt (vl-remove nil (mapcar '(lambda (e / s n)
                                           (setq s (cdr (assoc 1 e)))
                                           (if (and (wcmatch s (strcat prefix "#*")) (setq n (bp:leading-number (substr s (1+ (strlen prefix))))))
                                             (list n (cdr (assoc 10 e)))))
                                        (bp:model (list '(0 . "TEXT,MTEXT") (cons 7 (bp:kind-style "figure"))))))))

(defun bp:figure-text (n caption)
  (strcat (bp:label "figure") " " (itoa n) "." (if (= caption "") "" (strcat " " caption))))
