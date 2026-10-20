;;; ---- PDFNUM -----------------------------------------------------------------
;;; Fills in empty Аркуш and Аркушів cells and fixes wrong ones (docs/adr/0010): Аркушів becomes
;;; the count of the марка's рамки of a kind; an Аркуш number that is in range and not taken by an
;;; earlier рамка stays, so a deliberate order is kept; a copied, too big or missing one gets a free
;;; number, in position order.
;;; Defines c:PDFNUM; nothing here is called from the other files.

(defun pa:ordered-cells (r)
  ;; The counter cells of a рамка, Аркуш before Аркушів, so the report reads in cell order.
  (append (vl-remove-if '(lambda (c) (= (car c) 'total)) (pa:get 'counters r))
          (vl-remove-if-not '(lambda (c) (= (car c) 'total)) (pa:get 'counters r))))

(defun pa:replace-last (s old new / p q)
  ;; s with its last old replaced by new.
  (setq p nil q 0)
  (while (setq q (vl-string-search old s q)) (setq p q q (1+ q)))
  (if p (strcat (substr s 1 p) new (substr s (+ p 1 (strlen old)))) s))

(defun pa:set-number (c n / e d)
  ;; Changes the number in the counter cell c (as pa:title-cells gives it) to n, in its own text
  ;; or in the label's ("Аркуш 2"). Returns nil when that text is inside a block.
  (if (setq e (nth 4 (cond ((cadddr c)) ((cadr c)))))
    (progn
      (setq d (entget e))
      (entmod (subst (cons 1 (pa:replace-last (cdr (assoc 1 d)) (itoa (caddr c)) (itoa n))) (assoc 1 d) d))
      T)))

(defun pa:sheet-numbers (items n / keep out)
  ;; The Аркуш number each of items gets, in their order: its own when it is 1..n and no earlier
  ;; item has it, otherwise the smallest number nobody keeps.
  (foreach r items
    (if (and (pa:get 'sheet r) (<= 1 (pa:get 'sheet r) n) (not (member (pa:get 'sheet r) keep)))
      (setq keep (cons (pa:get 'sheet r) keep) out (cons (pa:get 'sheet r) out))
      (setq out (cons nil out))))
  (setq out (reverse out))
  (mapcar '(lambda (x / k) (if x x (progn (setq k 1) (while (member k keep) (setq k (1+ k))) (setq keep (cons k keep)) k)))
          out))

(defun pa:number-style (records / o e d)
  ;; The look of a number someone already wrote in a counter cell of a специфікація or текстовий
  ;; документ, so new numbers match it: ((8 . layer) (7 . style) (40 . height) ...), or nil if there
  ;; is none.
  (foreach r records
    (if (/= (pa:get 'kind r) "list")
      (foreach c (pa:get 'counters r)
        ;; (nth 4 nil) is an error in AutoLISP, so the entry is checked first
        (if (and (null d)
                 (setq o (cadddr c))
                 (setq e (nth 4 o))
                 (= "TEXT" (cdr (assoc 0 (entget e)))))
          (setq d (entget e))))))
  (if d (pa:text-style d)))

(defun pa:cell-x (cells x y / left right)
  ;; The middle of the title-block cell around x at height y, from its edge lines; x if none are found.
  (foreach s cells
    (if (and (<= (cadr s) y (caddr s)) (< (abs (- (car s) x)) 30.0))
      (if (< (car s) x)
        (if (or (null left) (> (car s) left)) (setq left (car s)))
        (if (or (null right) (< (car s) right)) (setq right (car s))))))
  (if (and left right) (/ (+ left right) 2.0) x))

(defun pa:cell-y (rows x y / below above)
  ;; The middle of the title-block cell around y at x, from its edge lines; y if none are found, or
  ;; if they are too far apart to be one cell.
  (foreach s rows
    (if (<= (cadr s) x (caddr s))
      (if (< (car s) y)
        (if (or (null below) (> (car s) below)) (setq below (car s)))
        (if (or (null above) (< (car s) above)) (setq above (car s))))))
  (if (and below above (< (- above below) 20.0)) (/ (+ below above) 2.0) y))

(defun pa:row-number (r / z)
  ;; A number of r's title block written as a text of its own after its label, in the same row, as
  ;; old title blocks have it ("Аркушiв" then "1"): its zone entry, or nil.
  (foreach c (pa:get 'counters r)
    (if (and (cadddr c) (< (abs (- (cadr (cadddr c)) (cadr (cadr c)))) 2.5))
      (setq z (cadddr c))))
  z)

(defun pa:cell-under (r z / box)
  ;; The cell under the label z of r as (left bottom right top) when it is one 5 mm row, the number
  ;; cell a СПДБ лист has under Аркуш and Аркушів; nil under the labels of other листи, where the
  ;; organisation's cell is.
  (setq box (pa:cell-box r (car z) (- (cadr z) 5.0)))
  (if (and box (< (- (cadddr box) (cadr box)) 8.0)) box))

(defun pa:fill-cell (r cell n style / f z x y d e old box)
  ;; Writes number n into the empty cell. Returns nil when it can't.
  (setq f (pa:get 'frame r)
        z (cdr cell)
        e (nth 4 z))
  (if (and (= (pa:get 'kind r) "list") (not (pa:cell-under r z)))
    (cond
      ((null e) nil)
      ;; On a new лист the number follows the label in the same text: "Аркуш 2".
      ((and (= "TEXT" (cdr (assoc 0 (setq d (entget e))))) (null (pa:row-number r)))
       (entmod (subst (cons 1 (strcat (cdr (assoc 1 d)) " " (itoa n))) (assoc 1 d) d)))
      ;; An old title block writes it as a text of its own, after the label in the same cell, in
      ;; the look of a number already there: centred between the label and the cell's right edge.
      (T
       (setq old (pa:row-number r)
             box (pa:cell-box r (car z) (cadr z))
             x (+ (if box (/ (+ (car z) (caddr box)) 2.0) (+ (car z) 6.0)) (caddr f))
             y (+ (if box (/ (+ (cadr box) (cadddr box)) 2.0) (cadr z)) (cadr f)))
       (entmake (append (list '(0 . "TEXT") (list 10 x y 0.0) (list 11 x y 0.0) '(72 . 1) '(73 . 2)
                              (cons 1 (itoa n)))
                        (pa:text-style (entget (if (and old (nth 4 old)) (nth 4 old) e)))))))
    ;; On a специфікація, a текстовий документ and a СПДБ лист it goes in the middle of the cell under
    ;; the label, the cell found around the point 5 mm below the label (7.5 mm in the corner cell); at
    ;; that point if its edges aren't. A лист's number takes the look of its label, not of the numbers
    ;; on специфікації. x and y are measured from the рамка's bottom-right corner until the text is made.
    (progn
      (setq y (- (cadr z) (if (= (car cell) 'corner) 7.5 5.0))
            x (pa:cell-x (pa:get 'cells r) (car z) y)
            y (+ (pa:cell-y (pa:get 'rows r) x y) (cadr f))
            x (+ x (caddr f)))
      (entmake (append (list '(0 . "TEXT") (list 10 x y 0.0) (list 11 x y 0.0) '(72 . 1) '(73 . 2)
                             (cons 1 (itoa n)))
                       (cond ((and style (/= (pa:get 'kind r) "list")) style)
                             ((pa:label-style z (pa:get 'zone r)))))))))

(defun pa:position< (a b / ya yb)
  ;; Upper row first, then left to right.
  (setq ya (cadr (pa:get 'll a)) yb (cadr (pa:get 'll b)))
  (if (> (abs (- ya yb)) 100.0) (> ya yb) (< (car (pa:get 'll a)) (car (pa:get 'll b)))))

(defun pa:first-page-p (r)
  ;; Whether r is the first page of a специфікація or текстовий документ: the one with Аркушів.
  (and (vl-some '(lambda (c) (= (car c) 'total)) (pa:get 'counters r)) T))

(defun pa:first-page< (a b)
  ;; A first page before later ones, then by position.
  (if (eq (pa:first-page-p a) (pa:first-page-p b)) (pa:position< a b) (pa:first-page-p a)))

(defun pa:number (marka kind items style / n nums i done what want old)
  ;; Fills and fixes the counter cells of one kind of one марка (see the top of this file).
  (setq items (vl-sort items (if (= kind "list") 'pa:position< 'pa:first-page<))
        n (length items)
        nums (pa:sheet-numbers items n))
  (foreach r items
    (setq i (car nums) nums (cdr nums) done nil)
    (foreach c (pa:ordered-cells r)
      (setq want (if (= (car c) 'total) n i)
            old (caddr c)
            what (cond ((null old) (if (= (car c) 'total) (pa:msg "pdfnum.total" (list "n" want)) (pa:msg "pdfnum.sheet" (list "n" want))))
                       ((= (car c) 'total) (pa:msg "pdfnum.total-changed" (list "old" old "n" want)))
                       ((pa:msg "pdfnum.sheet-changed" (list "old" old "n" want)))))
      (if (/= old want)
        (progn
          (pa:log (list "pdfnum:" marka kind "frame at" (car (pa:get 'll r)) (cadr (pa:get 'll r)) (car c) old "->" want))
          (if (if old (pa:set-number c want) (pa:fill-cell r (cons (car c) (cadr c)) want style))
            (setq done (cons what done))
            (pa:warn (pa:msg "pdfnum.in-block" (list "marka" marka "what" what "where" (pa:where r))))))))
    (if done
      (setq filled (cons (pa:msg "pdfnum.filled-line"
                                 (list "marka" marka "kind" (pa:kind-name kind) "n" i
                                       "what" (vl-string-right-trim ", " (apply 'strcat (mapcar '(lambda (s) (strcat s ", "))
                                                                                            (reverse done))))))
                         filled)))))

(defun c:PDFNUM (/ *error* warnings fill-state sysvars drawing records style filled)
  (defun *error* (msg)
    (pa:restore)
    (pa:report-crash "PDFNUM" msg)
    (princ))
  (setq sysvars (list (cons "CMDECHO" (getvar "CMDECHO"))))
  (setvar "CMDECHO" 0)
  (pa:log-start "PDFNUM")
  (princ (strcat "\n" (pa:msg "reading" (list "cmd" "PDFNUM"))))
  (setq drawing (pa:read-drawing)
        records (car drawing)
        style (pa:number-style records))
  (command "_.UNDO" "_BE")
  (foreach m (pa:markas records)
    (foreach k *pa-kinds* (pa:number m k (pa:of m k records) style)))
  (command "_.UNDO" "_E")
  (pa:log (list "pdfnum: filled" (reverse filled)))
  (if filled
    (progn
      (princ (strcat "\n\n" (pa:msg "pdfnum.filled" nil)))
      (foreach s (reverse filled) (princ (strcat "\n  " s)))
      (princ (strcat "\n" (pa:msg "pdfnum.undo" nil))))
    (princ (strcat "\n\n" (pa:msg "pdfnum.nothing" nil))))
  (foreach e (cadr drawing)
    (pa:warn (pa:msg "pdfnum.skipped" (list "problem" (pa:problem e)))))
  (pa:report-warnings)
  (pa:restore)
  (princ))
