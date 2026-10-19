;;; ---- PDFNUM -----------------------------------------------------------------
;;; Fills in empty Аркуш and Аркушів cells. A number that is already written is never changed.
;;; Defines c:PDFNUM; nothing here is called from the other files.

(defun pa:empty-cells (r / out)
  ;; The counter cells of a рамка that have no number yet: ((role . label) ...), Аркуш before
  ;; Аркушів, so the report reads in cell order.
  (foreach c (pa:get 'counters r)
    (if (null (caddr c)) (setq out (cons (cons (car c) (cadr c)) out))))
  (append (vl-remove-if '(lambda (c) (= (car c) 'total)) out)
          (vl-remove-if-not '(lambda (c) (= (car c) 'total)) out)))

(defun pa:number-style (records / o e d)
  ;; The look of a number someone already wrote in a counter cell of a специфікація, so new numbers
  ;; match it: ((8 . layer) (7 . style) (40 . height) ...), or nil if there is none.
  (foreach r records
    (if (= (pa:get 'kind r) "spec")
      (foreach c (pa:get 'counters r)
        ;; (nth 4 nil) is an error in AutoLISP, so the entry is checked first
        (if (and (null d)
                 (setq o (cadddr c))
                 (setq e (nth 4 o))
                 (= "TEXT" (cdr (assoc 0 (entget e)))))
          (setq d (entget e))))))
  (if d (pa:text-style d)))

(defun pa:text-style (d)
  ;; Layer, style, height, width, colour and slant (51): title blocks lean their text 15 degrees.
  (vl-remove nil (mapcar '(lambda (k) (assoc k d)) '(8 7 40 41 51 62))))

(defun pa:gap (a b) (distance (list (car a) (cadr a)) (list (car b) (cadr b))))

(defun pa:label-style (z zone / o)
  ;; The look of the label z, or of the nearest plain text of its title block if z is inside a block.
  (if (and (nth 4 z) (= "TEXT" (cdr (assoc 0 (entget (nth 4 z))))))
    (pa:text-style (entget (nth 4 z)))
    (progn
      (foreach x zone
        (if (and (nth 4 x) (= "TEXT" (cdr (assoc 0 (entget (nth 4 x)))))
                 (or (null o) (< (pa:gap z x) (pa:gap z o))))
          (setq o x)))
      (if o (pa:text-style (entget (nth 4 o))) (list (cons 40 2.5))))))

(defun pa:cell-x (cells x y / left right)
  ;; The middle of the title-block cell around x at height y, from its edge lines; x if none are found.
  (foreach s cells
    (if (and (<= (cadr s) y (caddr s)) (< (abs (- (car s) x)) 30.0))
      (if (< (car s) x)
        (if (or (null left) (> (car s) left)) (setq left (car s)))
        (if (or (null right) (< (car s) right)) (setq right (car s))))))
  (if (and left right) (/ (+ left right) 2.0) x))

(defun pa:fill-cell (r cell n style / f z x y d e)
  ;; Writes number n into the empty cell. Returns nil when it can't.
  (setq f (pa:get 'frame r)
        z (cdr cell)
        e (nth 4 z))
  (if (= (pa:get 'kind r) "list")
    ;; On a лист the number follows the label in the same text: "Аркуш 2".
    (if e
      (progn
        (setq d (entget e))
        (entmod (subst (cons 1 (strcat (cdr (assoc 1 d)) " " (itoa n))) (assoc 1 d) d))))
    ;; On a специфікація it goes in the cell under the label: 5 mm lower, 7.5 mm in the corner cell.
    ;; x and y are measured from the рамка's bottom-right corner until the text is made.
    (progn
      (setq y (- (cadr z) (if (= (car cell) 'corner) 7.5 5.0))
            x (+ (pa:cell-x (pa:get 'cells r) (car z) y) (caddr f))
            y (+ y (cadr f)))
      (entmake (append (list '(0 . "TEXT") (list 10 x y 0.0) (list 11 x y 0.0) '(72 . 1) '(73 . 2)
                             (cons 1 (itoa n)))
                       (cond (style) ((pa:label-style z (pa:get 'zone r)))))))))

(defun pa:position< (a b / ya yb)
  ;; Upper row first, then left to right.
  (setq ya (cadr (pa:get 'll a)) yb (cadr (pa:get 'll b)))
  (if (> (abs (- ya yb)) 100.0) (> ya yb) (< (car (pa:get 'll a)) (car (pa:get 'll b)))))

(defun pa:number (marka kind items style / n used i done what)
  ;; Fills the empty cells of one kind of one марка, numbering its рамки by position.
  (setq items (vl-sort items 'pa:position<)
        n (length items)
        used (vl-remove nil (mapcar '(lambda (r) (pa:get 'sheet r)) items))
        i 0)
  (foreach r items
    (setq i (1+ i) done nil)
    (foreach cell (pa:empty-cells r)
      (setq what (if (= (car cell) 'total) (pa:msg "pdfnum.total" (list "n" n)) (pa:msg "pdfnum.sheet" (list "n" i))))
      (cond
        ((and (/= (car cell) 'total) (member i used))
         (pa:warn (pa:msg "pdfnum.number-used" (list "marka" marka "kind" (pa:kind-of kind) "n" i "where" (pa:where r)))))
        ((pa:fill-cell r cell (if (= (car cell) 'total) n i) style)
         (setq done (cons what done)))
        (T (pa:warn (pa:msg "pdfnum.in-block" (list "marka" marka "what" what "where" (pa:where r)))))))
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
  (princ (strcat "\n" (pa:msg "reading" (list "cmd" "PDFNUM"))))
  (setq drawing (pa:read-drawing)
        records (car drawing)
        style (pa:number-style records))
  (command "_.UNDO" "_BE")
  (foreach m (pa:markas records)
    (pa:number m "list" (pa:of m "list" records) style)
    (pa:number m "spec" (pa:of m "spec" records) style))
  (command "_.UNDO" "_E")
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
