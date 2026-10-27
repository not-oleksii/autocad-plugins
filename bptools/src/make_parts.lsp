;;; Makes the parts library; src\make_parts.ps1 loads it in the console AutoCAD after the built
;;; bptools.lsp, in src\parts\library.dwg (the parts drawn by hand) or an empty metric drawing.
;;;   mk:generate                adds the generated blocks the drawing doesn't have yet: the D-Sub
;;;                              faces, top and side views, and the single-row connectors
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

;;; ---- Single-row connectors with a key ---------------------------------------
;; As (part pins pitch body-width body-height key key-width key-height contact pin-1-left-from-front),
;; in mm. key is rib (a tab standing out of the top edge) or notch (a slot cut into it); contact is
;; the side of the square drawn at each contact. Seen from the back, a face is mirrored.
;; JST GH is the GHR-0nV-S housing after JST's catalogue (eGH.pdf): 1.25 pitch, width 1.25 x (pins + 1),
;; 4.15 deep with its lock, pin 1 at the right of the mating face with the lock up.
(setq *mk-row-parts*
  '(("JST GH 1.25 3 pin" 3 1.25 5.00 3.65 rib 2.50 0.50 0.70 nil)
    ("JST GH 1.25 4 pin" 4 1.25 6.25 3.65 rib 3.75 0.50 0.70 nil)))

(defun mk:row-part (spec view / name pins pitch w h key kw kh c left y top i x)
  ;; One вигляд of a single-row connector, its base point the centre of the body.
  (setq pins (nth 1 spec) pitch (nth 2 spec) w (nth 3 spec) h (nth 4 spec) key (nth 5 spec)
        kw (nth 6 spec) kh (nth 7 spec) c (nth 8 spec)
        left (if (nth 9 spec) (= view "front") (= view "back"))
        top (if (= key 'rib) (+ (/ h 2.0) kh) (- (/ h 2.0) kh)))
  (mk:pline (list (list (/ w -2.0) (/ h -2.0)) (list (/ w 2.0) (/ h -2.0)) (list (/ w 2.0) (/ h 2.0))
                  (list (/ kw 2.0) (/ h 2.0)) (list (/ kw 2.0) top) (list (/ kw -2.0) top)
                  (list (/ kw -2.0) (/ h 2.0)) (list (/ w -2.0) (/ h 2.0))))
  (setq i 0)
  (repeat pins
    (setq x (* (- i (/ (1- pins) 2.0)) pitch)
          x (if left x (- x))
          i (1+ i))
    (mk:pline (list (list (- x (/ c 2.0)) (/ c -2.0)) (list (+ x (/ c 2.0)) (/ c -2.0))
                    (list (+ x (/ c 2.0)) (/ c 2.0)) (list (- x (/ c 2.0)) (/ c 2.0))))
    (mk:number i (list x (- (/ h -2.0) *mk-number-gap*)) "pin-small")))

;; From the side, after JST's side drawing of the housing: as (part length height lock-length lock-height
;; front-length front-height), in mm, the front (mating end) to the right, the wires coming in on the
;; left, the lock on top. Its height with the lock is the face's depth, 4.15 for GH.
(setq *mk-row-sides* '(("JST GH 1.25 3 pin" 5.70 3.65 4.20 0.50 1.60 3.10)
                       ("JST GH 1.25 4 pin" 5.70 3.65 4.20 0.50 1.60 3.10)))

(defun mk:row-side (spec / len h ll lh fl fh)
  ;; Base point: the centre of the front end.
  (setq len (nth 1 spec) h (nth 2 spec) ll (nth 3 spec) lh (nth 4 spec) fl (nth 5 spec) fh (nth 6 spec))
  (mk:pline (list (list (- len) (/ h -2.0)) (list (- fl) (/ h -2.0)) (list (- fl) (/ fh -2.0)) (list 0.0 (/ fh -2.0))
                  (list 0.0 (/ fh 2.0)) (list (- fl) (/ fh 2.0)) (list (- fl) (/ h 2.0)) (list (- len) (/ h 2.0))))
  (mk:pline (list (list (- len) (/ h 2.0)) (list (+ (- len) ll) (/ h 2.0)) (list (+ (- len) ll) (+ (/ h 2.0) lh))
                  (list (- len) (+ (/ h 2.0) lh)))))

(defun mk:rows (/ name)
  ;; «Futaba - F — з лицьового боку» and the rest, from the front and the back; a block of that name
  ;; the drawing already has is kept.
  (foreach spec *mk-row-parts*
    (foreach view '("front" "back")
      (setq name (strcat (car spec) *bptools-part-dash* (mk:view-name view)))
      (if (not (tblobjname "BLOCK" name))
        (progn
          (entmake (list '(0 . "BLOCK") (cons 2 name) '(70 . 2) '(10 0.0 0.0 0.0)))
          (mk:row-part spec view)
          (entmake '((0 . "ENDBLK")))))))
  (foreach spec *mk-row-sides*
    (setq name (strcat (car spec) *bptools-part-dash* (mk:view-name "side")))
    (if (not (tblobjname "BLOCK" name))
      (progn
        (entmake (list '(0 . "BLOCK") (cons 2 name) '(70 . 2) '(10 0.0 0.0 0.0)))
        (mk:row-side spec)
        (entmake '((0 . "ENDBLK")))))))

;;; ---- D-Sub from the top and the side ----------------------------------------
;; A solder-cup D-Sub seen from above and from the side, as (part shell d-depth body-width body-height
;; body-depth cup-length cup-width), in mm: the D stands out d-depth in front of the flange, the
;; insulating body body-depth behind it, and the solder cups cup-length further. Typical sizes of a
;; solder-cup DB-15F such as DSC-115: CHECK them against the роз'єм itself.
(setq *mk-dsub-sides* '(("D-Sub DB-15F" "DB-15" 6.00 30.80 10.40 5.60 3.00 1.10)))
(setq *mk-flange-thick* 1.00)

(defun mk:rect (x1 y1 x2 y2) (mk:pline (list (list x1 y1) (list x2 y1) (list x2 y2) (list x1 y2))))

(defun mk:dsub-side (spec view / shell a wt h dd bw bh bd cl cw f n i x)
  ;; Base point: the centre of the flange's front face. From the top, x across and the front up; from
  ;; the side, the front to the right and y up. The cups shown from the top are those of the top row.
  (setq shell (assoc (nth 1 spec) *mk-dsubs*) a (nth 3 shell) wt (nth 5 shell) h (nth 6 shell)
        n (nth 2 shell)
        dd (nth 2 spec) bw (nth 3 spec) bh (nth 4 spec) bd (nth 5 spec) cl (nth 6 spec) cw (nth 7 spec)
        f *mk-flange-thick*)
  (if (= view "top")
    (progn
      (mk:rect (/ a -2.0) (- f) (/ a 2.0) 0.0)
      (mk:rect (/ wt -2.0) 0.0 (/ wt 2.0) dd)
      (mk:rect (/ bw -2.0) (- (+ f bd)) (/ bw 2.0) (- f))
      (setq i 0)
      (repeat n
        (setq x (* (- i (/ (1- n) 2.0)) *mk-pitch*) i (1+ i))
        (mk:rect (- x (/ cw 2.0)) (- (+ f bd cl)) (+ x (/ cw 2.0)) (- (+ f bd)))))
    (progn
      (mk:rect (- f) (/ *mk-flange* -2.0) 0.0 (/ *mk-flange* 2.0))
      (mk:rect 0.0 (/ h -2.0) dd (/ h 2.0))
      (mk:rect (- (+ f bd)) (/ bh -2.0) (- f) (/ bh 2.0))
      (foreach y (list (/ *mk-rows* 2.0) (/ *mk-rows* -2.0))
        (mk:rect (- (+ f bd cl)) (- y (/ cw 2.0)) (- (+ f bd)) (+ y (/ cw 2.0)))))))

(defun mk:dsub-sides (/ name)
  (foreach spec *mk-dsub-sides*
    (foreach view '("top" "side")
      (setq name (strcat (car spec) *bptools-part-dash* (mk:view-name view)))
      (if (not (tblobjname "BLOCK" name))
        (progn
          (entmake (list '(0 . "BLOCK") (cons 2 name) '(70 . 2) '(10 0.0 0.0 0.0)))
          (mk:dsub-side spec view)
          (entmake '((0 . "ENDBLK"))))))))

;;; ---- Futaba J -----------------------------------------------------------------
;; Drawn as on the user's sheets: the face upright with pin 1 at the top, the numbers to its right and
;; the key as a small square in a bottom corner (the right one of a female face seen from the front);
;; from the side, the wires come in on the left. As (part body-width body-height contact key male
;; side-blocks side-lines side-contact-length), in mm, the side blocks as (length height) from the back
;; to the front, side-lines the x of the lines across the front block from its front.
;; Typical sizes, not a maker's drawing: CHECK them against the роз'єм itself.
(setq *mk-futaba*
  '(("Futaba - F" 2.70 7.70 0.60 0.60 nil ((4.90 7.70) (9.20 7.60)) (3.60 4.80 5.60) 3.60)
    ("Futaba - M" 3.60 8.60 0.64 0.70 T ((3.00 4.90) (10.60 6.80)) nil 0.0)))
(setq *mk-futaba-pitch* 2.54)

(defun mk:futaba (spec view / w h c k male right x y len i)
  ;; Base point: the centre of the face, or from the side the centre of the front end.
  (setq w (nth 1 spec) h (nth 2 spec) c (nth 3 spec) k (nth 4 spec) male (nth 5 spec))
  (if (= view "side")
    (progn
      (setq x 0.0 len (apply '+ (mapcar 'car (nth 6 spec))))
      (foreach b (nth 6 spec)
        (mk:rect (- x len) (/ (cadr b) -2.0) (+ (- x len) (car b)) (/ (cadr b) 2.0))
        (setq x (+ x (car b))))
      (setq h (cadr (last (nth 6 spec))))
      (foreach lx (nth 7 spec)
        (entmake (list '(0 . "LINE") '(8 . "0") '(62 . 0) (list 10 (- lx) (/ h -2.0) 0.0) (list 11 (- lx) (/ h 2.0) 0.0))))
      (setq i 0)
      (repeat 3
        (setq y (* (- 1 i) *mk-futaba-pitch*) i (1+ i))
        (if (> (nth 8 spec) 0.0)
          (progn
            (mk:rect (- (car (last (nth 6 spec)))) (- y 0.25) (- (- (car (last (nth 6 spec)))) (- (nth 8 spec))) (+ y 0.25))
            (mk:number i (list (- (/ (car (nth 7 spec)) 2.0)) y) "pin")))))
    (progn
      (setq right (if male (= view "back") (= view "front")))
      (mk:rect (/ w -2.0) (/ h -2.0) (/ w 2.0) (/ h 2.0))
      (if right
        (mk:rect (- (/ w 2.0) k) (/ h -2.0) (/ w 2.0) (+ (/ h -2.0) k))
        (mk:rect (/ w -2.0) (/ h -2.0) (+ (/ w -2.0) k) (+ (/ h -2.0) k)))
      (setq i 0)
      (repeat 3
        (setq y (* (- 1 i) *mk-futaba-pitch*) i (1+ i))
        (mk:rect (/ c -2.0) (- y (/ c 2.0)) (/ c 2.0) (+ y (/ c 2.0)))
        (mk:number i (list (+ (/ w 2.0) 1.5) y) "pin")))))

(defun mk:futabas (/ name)
  (foreach spec *mk-futaba*
    (foreach view '("front" "back" "side")
      (setq name (strcat (car spec) *bptools-part-dash* (mk:view-name view)))
      (if (not (tblobjname "BLOCK" name))
        (progn
          (entmake (list '(0 . "BLOCK") (cons 2 name) '(70 . 2) '(10 0.0 0.0 0.0)))
          (mk:futaba spec view)
          (entmake '((0 . "ENDBLK"))))))))

(defun mk:generate () (mk:dsubs) (mk:dsub-sides) (mk:rows) (mk:futabas))

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

(defun mk:numbers (first / e d out)
  ;; The pin numbers of a block, its attribute definitions, as ((x y "text") ...) at their centres.
  (setq e first)
  (while e
    (setq d (entget e))
    (if (= (cdr (assoc 0 d)) "ATTDEF")
      (setq out (cons (list (mk:round (car (cdr (assoc 11 d)))) (mk:round (cadr (cdr (assoc 11 d)))) (cdr (assoc 1 d))) out)))
    (setq e (entnext e)))
  (reverse out))

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
  (write-line ";;; Made by src\\make_parts.ps1 from src\\parts\\library.dwg and the parts src\\make_parts.lsp generates;" f)
  (write-line ";;; run it again instead of editing this. Every вигляд of every part BPPART can paste, as" f)
  (write-line ";;;   (part view-key file (min-x min-y max-x max-y) (x1 y1 x2 y2 ...) ((x y \"number\") ...))" f)
  (write-line ";;; in mm from the block's base point; file is src\\parts\\<file>.dwg. BPPART draws the lines and the pin" f)
  (write-line ";;; numbers as its preview." f)
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
                        " " (vl-prin1-to-string segs) " " (vl-prin1-to-string (mk:numbers (caddr p))) ")")
                f)
    (setq n (1+ n)))
  (write-line "  ))" f)
  (close f)
  (princ (strcat "\nLIBRARY-WRITTEN=" (itoa n) "|"))
  n)
