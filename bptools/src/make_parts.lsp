;;; Makes the parts library; src\make_parts.ps1 loads it in the console AutoCAD after the built
;;; bptools.lsp, in src\parts\library.dwg (the parts drawn by hand) or an empty metric drawing.
;;;   mk:dsubs                   adds the generated D-Sub blocks the drawing doesn't have yet
;;;   mk:write-library (src)     writes every library block, «<part> — <вигляд>», to
;;;                              src\parts\<file>.dwg and lists them with their outlines in
;;;                              src\lsp\45-parts.lsp, the catalog BPPART shows
;;; Not part of bptools.lsp: it runs only when the parts change (docs/adr/0002).

;;; ---- D-Sub ------------------------------------------------------------------
;; The shells, as (name pins pins-in-top-row flange-width hole-spacing d-top-width d-height), in mm,
;; after the common D-Sub dimensions. Check a new size against the роз'єм itself.
(setq *mk-dsubs* '(("DB-09" 9 5 30.81 24.99 16.33 7.90)
                   ("DB-15" 15 8 39.14 33.32 24.66 7.90)))
(setq *mk-pitch* 2.77      ; between pins in a row
      *mk-rows* 2.84       ; between the rows
      *mk-flange* 12.55    ; flange height
      *mk-hole* 3.05       ; mounting hole diameter
      *mk-pin* 1.0         ; pin or socket diameter
      *mk-slope* 10.0      ; the D's sides, degrees from upright
      *mk-number-gap* 1.6) ; from a pin's centre to its number's

(defun mk:pline (pts)
  ;; A closed polyline on layer 0, coloured by block.
  (entmake (append (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") '(8 . "0") '(62 . 0) '(100 . "AcDbPolyline")
                         (cons 90 (length pts)) '(70 . 1))
                   (mapcar '(lambda (p) (cons 10 p)) pts))))

(defun mk:circle (c r)
  (entmake (list '(0 . "CIRCLE") '(8 . "0") '(62 . 0) (cons 10 c) (cons 40 r))))

(defun mk:number (n p kind / s)
  ;; A pin number as a preset attribute, so BPPART can stand it upright when the part is rotated.
  (setq s (itoa n))
  (entmake (list '(0 . "ATTDEF") '(100 . "AcDbEntity") '(8 . "0") '(62 . 0) '(100 . "AcDbText")
                 (cons 10 p) (cons 40 (bp:kind-height kind)) (cons 1 s) '(50 . 0.0) '(41 . 1.0)
                 (cons 7 (bp:kind-style kind)) '(72 . 1) (cons 11 p)
                 '(100 . "AcDbAttributeDefinition") '(3 . "") (cons 2 (strcat "PIN" s)) '(70 . 8) '(74 . 2))))

(defun mk:dsub (shell male view / pins top a b wt h wb bottom left n x y i)
  ;; One вигляд of a D-Sub, its base point the centre of the face. Seen from the front, a female
  ;; роз'єм has pin 1 at the top right and a male one at the top left; from the back it is mirrored.
  (setq pins (nth 1 shell) top (nth 2 shell) a (nth 3 shell) b (nth 4 shell) wt (nth 5 shell) h (nth 6 shell)
        wb (- wt (* 2.0 h (/ (sin (* pi (/ *mk-slope* 180.0)))(cos (* pi (/ *mk-slope* 180.0))))))
        bottom (- pins top)
        left (if male (= view "front") (= view "back")))
  (mk:pline (list (list (/ a -2.0) (/ *mk-flange* -2.0)) (list (/ a 2.0) (/ *mk-flange* -2.0))
                  (list (/ a 2.0) (/ *mk-flange* 2.0)) (list (/ a -2.0) (/ *mk-flange* 2.0))))
  (mk:pline (list (list (/ wt -2.0) (/ h 2.0)) (list (/ wt 2.0) (/ h 2.0))
                  (list (/ wb 2.0) (/ h -2.0)) (list (/ wb -2.0) (/ h -2.0))))
  (mk:circle (list (/ b -2.0) 0.0) (/ *mk-hole* 2.0))
  (mk:circle (list (/ b 2.0) 0.0) (/ *mk-hole* 2.0))
  (setq n 0)
  (foreach row (list (list top (/ *mk-rows* 2.0) 1.0) (list bottom (/ *mk-rows* -2.0) -1.0))
    (setq i 0)
    (repeat (car row)
      (setq x (* (- i (/ (1- (car row)) 2.0)) *mk-pitch*)
            x (if left x (- x))
            y (cadr row)
            n (1+ n)
            i (1+ i))
      (mk:circle (list x y) (/ *mk-pin* 2.0))
      (if male (mk:circle (list x y) (/ *mk-pin* 5.0)))
      (mk:number n (list x (+ y (* (caddr row) *mk-number-gap*))) "pin-small"))))

(defun mk:view-name (key) (cadr (assoc key *bptools-views*)))

(defun mk:dsubs (/ name)
  ;; Every shell, female and male, from the front and from the back: «D-Sub DB-09F — з лицьового боку».
  ;; A block of that name the drawing already has (drawn or corrected by hand) is kept.
  (foreach shell *mk-dsubs*
    (foreach male '(nil T)
      (foreach view '("front" "back")
        (setq name (strcat "D-Sub " (car shell) (if male "M" "F") *bptools-part-dash* (mk:view-name view)))
        (if (not (tblobjname "BLOCK" name))
          (progn
            (entmake (list '(0 . "BLOCK") (cons 2 name) '(70 . 2) '(10 0.0 0.0 0.0)))
            (mk:dsub shell male view)
            (entmake '((0 . "ENDBLK")))))))))

;;; ---- The catalog ------------------------------------------------------------

(defun mk:split-name (name / p)
  ;; (part view-key) of a library block's name, or nil when the name isn't «<part> — <вигляд>».
  (vl-some '(lambda (v / tail)
              (setq tail (strcat *bptools-part-dash* (cadr v)))
              (if (and (> (strlen name) (strlen tail))
                       (= (substr name (1+ (- (strlen name) (strlen tail)))) tail))
                (list (substr name 1 (- (strlen name) (strlen tail))) (car v))))
           *bptools-views*))

(defun mk:arc-points (c r a1 a2 / n out i)
  (if (< a2 a1) (setq a2 (+ a2 (* 2 pi))))
  (setq n (max 4 (fix (/ (- a2 a1) (/ pi 8)))) i 0)
  (repeat (1+ n) (setq out (cons (polar c (+ a1 (* i (/ (- a2 a1) n))) r) out) i (1+ i)))
  (reverse out))

(defun mk:segments (first / e d out pts close add)
  ;; The outline of a block's lines, polylines, circles and arcs as (x1 y1 x2 y2 ...); its texts
  ;; and attributes are left out of the preview.
  (defun add (pts) (mapcar '(lambda (a b) (setq out (append out (list (car a) (cadr a) (car b) (cadr b))))) pts (cdr pts)))
  (setq e first)
  (while e
    (setq d (entget e))
    (cond ((= (cdr (assoc 0 d)) "LINE") (add (list (cdr (assoc 10 d)) (cdr (assoc 11 d)))))
          ((= (cdr (assoc 0 d)) "LWPOLYLINE")
           (setq pts (mapcar 'cdr (vl-remove-if-not '(lambda (p) (= (car p) 10)) d)))
           (if (= 1 (logand 1 (cdr (assoc 70 d)))) (setq pts (append pts (list (car pts)))))
           (add pts))
          ((= (cdr (assoc 0 d)) "CIRCLE") (add (mk:arc-points (cdr (assoc 10 d)) (cdr (assoc 40 d)) 0.0 (* 2 pi))))
          ((= (cdr (assoc 0 d)) "ARC") (add (mk:arc-points (cdr (assoc 10 d)) (cdr (assoc 40 d)) (cdr (assoc 50 d)) (cdr (assoc 51 d))))))
    (setq e (entnext e)))
  out)

(defun mk:file-id (part key used / s)
  ;; An ASCII file name for a part's вигляд: Cyrillic names don't survive the zip.
  (setq s (apply 'strcat (mapcar '(lambda (c) (if (or (<= 48 c 57) (<= 65 c 90) (<= 97 c 122) (= c 45)) (chr c) "_")) (vl-string->list part))))
  (while (vl-string-search "__" s) (setq s (vl-string-subst "_" "__" s)))
  (setq s (strcat (vl-string-trim "_" s) "_" key))
  (if (member s used) (setq s (strcat s "_" (itoa (length used)))))
  s)

(defun mk:round (x) (/ (fix (+ (* x 100.0) (if (minusp x) -0.5 0.5))) 100.0))

(defun mk:write-library (src / b split parts used id segs xs ys path f n)
  (setq b (tblnext "BLOCK" T))
  (while b
    (if (setq split (mk:split-name (cdr (assoc 2 b))))
      (setq parts (cons (list (cdr (assoc 2 b)) split (cdr (assoc -2 b))) parts)))
    (setq b (tblnext "BLOCK")))
  (setq parts (vl-sort parts '(lambda (a b) (< (car a) (car b)))))
  (setq f (open (strcat src "\\lsp\\45-parts.lsp") "w" "utf8"))
  (write-line ";;; ---- Parts library ----------------------------------------------------------" f)
  (write-line ";;; Made by src\\make_parts.ps1 from src\\parts\\library.dwg and the D-Sub parts of src\\make_parts.lsp;" f)
  (write-line ";;; run it again instead of editing this. Every вигляд of every part BPPART can paste, as" f)
  (write-line ";;;   (part view-key file (min-x min-y max-x max-y) (x1 y1 x2 y2 ...))" f)
  (write-line ";;; in mm from the block's base point; file is src\\parts\\<file>.dwg. BPPART draws the lines as its preview." f)
  (write-line "" f)
  (write-line "(setq *bptools-parts* '(" f)
  (setq n 0)
  (foreach p parts
    (setq id (mk:file-id (car (cadr p)) (cadr (cadr p)) used)
          used (cons id used)
          segs (mapcar 'mk:round (mk:segments (caddr p)))
          path (strcat src "\\parts\\" id ".dwg")
          xs nil ys nil)
    (while segs (setq xs (cons (car segs) xs) ys (cons (cadr segs) ys) segs (cddr segs)))
    (setq segs (mapcar 'mk:round (mk:segments (caddr p))))
    (if (findfile path) (vl-file-delete path))
    (command "_.-WBLOCK" path (car p))
    (write-line (strcat "  (" (vl-prin1-to-string (car (cadr p))) " " (vl-prin1-to-string (cadr (cadr p))) " " (vl-prin1-to-string id)
                        " " (vl-prin1-to-string (if xs (list (apply 'min xs) (apply 'min ys) (apply 'max xs) (apply 'max ys)) '(0.0 0.0 0.0 0.0)))
                        " " (vl-prin1-to-string segs) ")")
                f)
    (setq n (1+ n)))
  (write-line "  ))" f)
  (close f)
  (princ (strcat "\nLIBRARY-WRITTEN=" (itoa n) "|"))
  n)
