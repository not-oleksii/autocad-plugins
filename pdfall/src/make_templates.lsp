;;; Loaded by make_templates.ps1 into the console AutoCAD, with the built pdfall.lsp, in one form of
;;; examples\formats at a time. (pdfall-template id form out) turns the open drawing into the
;;; template out\<id>.dwg and writes its outline to out\<id>.txt for 62-previews.lsp.
;;; form is "list", "first" (the first page of a специфікація or текстовий документ) or "next" (a
;;; later page): it says where the name cell is.

;; The forms' placeholders, which the templates leave empty (docs/adr/0009).
(setq *pt-placeholders* '("ДВНЗ \"ПДАБА\"" "Група-" "н"))

;; A point inside the name cell of each form, from the рамка's bottom-right corner.
(setq *pt-name-points* '(("list" -90.0 32.5) ("first" -90.0 17.5) ("next" -70.0 12.5)))

(defun pt:fail (msg) (princ (strcat "\nTEMPLATE-FAIL " msg)) (exit))

;; (x1 y1 x2 y2) of every LINE and LWPOLYLINE segment in Model space.
(defun pt:segs (/ ss i d out pts)
  (setq ss (ssget "_X" '((410 . "Model") (0 . "LINE,LWPOLYLINE"))) i (if ss (sslength ss) 0))
  (while (> i 0)
    (setq i (1- i) d (entget (ssname ss i)))
    (cond
      ((= (cdr (assoc 0 d)) "LINE")
       (setq out (cons (list (cadr (assoc 10 d)) (caddr (assoc 10 d)) (cadr (assoc 11 d)) (caddr (assoc 11 d))) out)))
      (T
       (setq pts nil)
       (foreach g d (if (= (car g) 10) (setq pts (cons (cdr g) pts))))
       (setq pts (reverse pts))
       (if (= 1 (logand 1 (cdr (assoc 70 d)))) (setq pts (append pts (list (car pts)))))
       (while (cadr pts)
         (setq out (cons (list (caar pts) (cadar pts) (caadr pts) (cadadr pts)) out) pts (cdr pts))))))
  out)

;; The cell around the point (px py): (left bottom right top) from the nearest lines on each side.
(defun pt:cell (segs px py / left right bottom top)
  (foreach s segs
    (cond
      ((and (< (abs (- (car s) (caddr s))) 0.01) (<= (min (cadr s) (cadddr s)) py (max (cadr s) (cadddr s))))
       (if (< (car s) px)
         (if (or (null left) (> (car s) left)) (setq left (car s)))
         (if (or (null right) (< (car s) right)) (setq right (car s)))))
      ((and (< (abs (- (cadr s) (cadddr s))) 0.01) (<= (min (car s) (caddr s)) px (max (car s) (caddr s))))
       (if (< (cadr s) py)
         (if (or (null bottom) (> (cadr s) bottom)) (setq bottom (cadr s)))
         (if (or (null top) (< (cadr s) top)) (setq top (cadr s)))))))
  (if (and left right bottom top) (list left bottom right top)))

(defun pt:frame (/ texts hsegs vsegs cellsegs rowsegs pa-owner frames)
  ;; The рамка of the drawing as (llx lly urx ury), found as PDFALL finds it.
  (pa:walk-model)
  (setq frames (pa:find-frames))
  (if (/= (length frames) 1) (pt:fail (strcat (itoa (length frames)) " рамки found")))
  (car frames))

(defun pt:drop-placeholders (/ ss i d n)
  (setq ss (ssget "_X" '((410 . "Model") (0 . "TEXT"))) i (if ss (sslength ss) 0) n 0)
  (while (> i 0)
    (setq i (1- i) d (entget (ssname ss i)))
    (if (member (cdr (assoc 1 d)) *pt-placeholders*)
      (progn (entdel (ssname ss i)) (setq n (1+ n)))))
  n)

(defun pt:r (v) (rtos v 2 1))

(defun pdfall-template (id form out / f p c segs ll dropped fh)
  (setq f (pt:frame)
        ll (list (car f) (cadr f) 0.0)
        dropped (pt:drop-placeholders)
        segs (pt:segs)
        p (cdr (assoc form *pt-name-points*))
        c (pt:cell segs (+ (caddr f) (car p)) (+ (cadr f) (cadr p))))
  (if (null c) (pt:fail (strcat id ": no name cell")))
  ;; The name: centred in its cell (attachment 5), exactly as wide and high as the cell, so it stays
  ;; on one line and wraps only when it is too long for it (docs/adr/0003).
  (entmake (list '(0 . "MTEXT") '(100 . "AcDbEntity") '(8 . "0") '(100 . "AcDbMText")
                 (list 10 (/ (+ (car c) (caddr c)) 2.0) (/ (+ (cadr c) (cadddr c)) 2.0) 0.0)
                 '(40 . 5.0) (cons 41 (- (caddr c) (car c))) (cons 46 (- (cadddr c) (cadr c)))
                 '(71 . 5) '(72 . 5) (cons 1 (pa:label "placeholder")) '(7 . "основная надпись") '(75 . 0)))
  (princ (strcat "\nTEMPLATE " id ": " (rtos (- (caddr f) (car f)) 2 0) "x" (rtos (- (cadddr f) (cadr f)) 2 0)
                 ", name cell " (rtos (- (caddr c) (car c)) 2 1) "x" (rtos (- (cadddr c) (cadr c)) 2 1)
                 ", placeholders dropped " (itoa dropped)))
  ;; The outline, from the рамка's lower-left corner: w h, the name cell, then every line longer than 1 mm.
  (setq fh (open (strcat out "/" id ".txt") "w"))
  (write-line (strcat (pt:r (- (caddr f) (car f))) " " (pt:r (- (cadddr f) (cadr f)))) fh)
  (write-line (strcat (pt:r (- (car c) (car f))) " " (pt:r (- (cadr c) (cadr f))) " "
                      (pt:r (- (caddr c) (car f))) " " (pt:r (- (cadddr c) (cadr f)))) fh)
  (foreach s segs
    (if (> (distance (list (car s) (cadr s)) (list (caddr s) (cadddr s))) 1.0)
      (write-line (strcat (pt:r (- (car s) (car f))) " " (pt:r (- (cadr s) (cadr f))) " "
                          (pt:r (- (caddr s) (car f))) " " (pt:r (- (cadddr s) (cadr f)))) fh)))
  (close fh)
  (command "_.-WBLOCK" (strcat out "/" id ".dwg") "" ll (ssget "_X" '((410 . "Model"))) "")
  (princ (strcat "\nTEMPLATE-DONE " id)))
