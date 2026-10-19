;;; ---- Export date ------------------------------------------------------------
;;; PDFALL writes the day's date into the Дата cell of every рамка while it plots, and takes it out
;;; again afterwards, so the PDFs carry the date of the export and the drawing itself doesn't change.
;;; Other files may call:
;;;   pa:date-add (records)  writes the date; what it changed is kept in dated, which the command
;;;                          declares among its locals
;;;   pa:date-remove         puts every Дата cell back as it was
;;;
;;; The Дата cell is in the column of the Дата head: in the row below the head, or, on a later
;;; аркуш of a специфікація where the heads are the title block's bottom row, in its top row.
;;; An empty cell gets a new text in the look of the head at 2 mm, centred in the cell. A date that
;;; is already there (dd.mm.yy or dd.mm.yyyy) gets the new date written over it.

(defun pa:today (/ d)
  ;; dd.mm.yy: a four-digit year doesn't fit every Дата cell
  (setq d (rtos (getvar "CDATE") 2 6))
  (strcat (substr d 7 2) "." (substr d 5 2) "." (substr d 3 2)))

(defun pa:date-p (s) (wcmatch s "##`.##`.##,##`.##`.####"))

(defun pa:date-head (r / head)
  ;; The zone entry of the Дата head of a рамка's title block: the lowest, if there are several.
  (foreach z (pa:get 'zone r)
    (if (and (equal (pa:words (caddr z)) (list (pa:label "date")))
             (or (null head) (< (cadr z) (cadr head))))
      (setq head z)))
  head)

(defun pa:date-cell (r head / box)
  ;; The Дата cell under head as (left bottom right top), measured from the рамка's bottom-right
  ;; corner; nil when its edges aren't found or are too far apart to be one cell.
  ;; Rows are 5 mm. The heads sit 30 mm or more above the рамка's edge on a лист and on the first
  ;; аркуш of a специфікація, under 15 mm on a later аркуш, whose title block is three rows high.
  (setq box (pa:cell-box r (car head) (if (< (cadr head) 15.0) (+ (cadr head) 10.0) (- (cadr head) 5.0))))
  (if (and box (< (- (caddr box) (car box)) 30.0) (< (- (cadddr box) (cadr box)) 10.0))
    box))

(defun pa:date-texts (r box)
  ;; The zone entries inside box.
  (vl-remove-if-not
    '(lambda (z) (and (< (car box) (car z) (caddr box)) (< (cadr box) (cadr z) (cadddr box))))
    (pa:get 'zone r)))

(defun pa:date-add (records / today head box in f x y d)
  (setq today (pa:today))
  (foreach r records
    (setq head (pa:date-head r)
          box (if head (pa:date-cell r head))
          in (if box (pa:date-texts r box)))
    (cond
      ((null box)
       (pa:warn (pa:msg "date.no-cell" (list "marka" (pa:get 'marka r) "where" (pa:where r)))))
      ((null in)
       (setq f (pa:get 'frame r)
             x (+ (/ (+ (car box) (caddr box)) 2.0) (caddr f))
             y (+ (/ (+ (cadr box) (cadddr box)) 2.0) (cadr f)))
       (entmake (append (list '(0 . "TEXT") (list 10 x y 0.0) (list 11 x y 0.0) '(72 . 1) '(73 . 2)
                              (cons 1 today) '(40 . 2.0))
                        (vl-remove-if '(lambda (g) (= (car g) 40)) (pa:label-style head (pa:get 'zone r)))))
       (setq dated (cons (list 'new (entlast)) dated)))
      ((or (cdr in) (not (pa:date-p (cadddr (car in)))))
       (pa:warn (pa:msg "date.occupied"
                        (list "marka" (pa:get 'marka r) "text" (vl-string-translate "\n" " " (cadddr (car in)))
                              "where" (pa:where r)))))
      ((null (nth 4 (car in)))
       (pa:warn (pa:msg "date.in-block" (list "marka" (pa:get 'marka r) "where" (pa:where r)))))
      (T
       (setq d (entget (nth 4 (car in)))
             dated (cons (list 'old d) dated))
       (entmod (subst (cons 1 today) (assoc 1 d) (vl-remove-if '(lambda (g) (= (car g) 3)) d)))))))

(defun pa:date-remove ()
  (foreach a dated
    (if (= (car a) 'new) (entdel (cadr a)) (entmod (cadr a))))
  (setq dated nil))
