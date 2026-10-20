;;; ---- Reader -----------------------------------------------------------------
;;; Reads the рамки drawn in Model space and their title blocks. Other files may call:
;;;   pa:read-drawing  -> (records problems)
;;;   pa:get pa:put    a record's fields
;;;   pa:markas pa:of  the марки of the records, and the records of one kind of one марка
;;;   pa:paper pa:off-size  the paper a рамка is plotted on, and its size when it is a little off
;;;   pa:cell-box      the edges of the title-block cell around a point
;;;   pa:org-title     the words of the organisation cell's top line
;;;   pa:text-style pa:label-style  the look of a title-block text, to write new ones like it
;;;
;;; A record is one рамка:
;;;   ((kind . "list"|"spec"|"text") (ll x y 0) (ur x y 0) (frame llx lly urx ury) (size name w h)
;;;    (marka . s) (sheet . n) (total . n) (zone ...) (counters ...) (cells ...) (rows ...))
;;; size is the A size of the рамка in its orientation, e.g. ("A3" 420 297). zone holds the texts of
;;; its title block as (x y comparable as-typed owner), counters its Аркуш, Аркушів and Арк. cells as
;;; pa:title-cells returns them, cells the vertical cell edges around it as (x y1 y2) and rows the
;;; horizontal ones as (y x1 x2); x and y are measured from the рамка's bottom-right corner. kind
;;; follows from the title block, not the рамка's size: a лист may be any A size, and an old drawing
;;; may have an A4 лист (docs/adr/0008-read-old-drawings.md, 0009-every-a-size-and-settings-for-pasting.md).
;;; owner is the TEXT or MTEXT entity when it sits directly in Model space (so PDFNUM can edit it),
;;; nil when it is inside a block.

;;; ---- Geometry ---------------------------------------------------------------

(setq *pa-tol* 0.5)
;; How far a рамка's sides may be off 420x297 or 210x297: an old drawing has a 210x295 one.
(setq *pa-frame-tol* 3.0)

(defun pa:near (a b) (< (abs (- a b)) *pa-tol*))
(defun pa:about (a b) (< (abs (- a b)) *pa-frame-tol*))

;; A transform is (a b c d e f): x' = a*x + b*y + e, y' = c*x + d*y + f.
(setq *pa-identity* '(1.0 0.0 0.0 1.0 0.0 0.0))

(defun pa:apply (m x y)
  (list (+ (* (nth 0 m) x) (* (nth 1 m) y) (nth 4 m))
        (+ (* (nth 2 m) x) (* (nth 3 m) y) (nth 5 m))))

(defun pa:compose (m n)
  ;; m after n
  (list (+ (* (nth 0 m) (nth 0 n)) (* (nth 1 m) (nth 2 n)))
        (+ (* (nth 0 m) (nth 1 n)) (* (nth 1 m) (nth 3 n)))
        (+ (* (nth 2 m) (nth 0 n)) (* (nth 3 m) (nth 2 n)))
        (+ (* (nth 2 m) (nth 1 n)) (* (nth 3 m) (nth 3 n)))
        (+ (* (nth 0 m) (nth 4 n)) (* (nth 1 m) (nth 5 n)) (nth 4 m))
        (+ (* (nth 2 m) (nth 4 n)) (* (nth 3 m) (nth 5 n)) (nth 5 m))))

;;; ---- MText ------------------------------------------------------------------

(defun pa:hex (s / n)
  (setq n 0)
  (foreach c (vl-string->list (strcase s))
    (setq n (+ (* n 16) (if (<= 48 c 57) (- c 48) (- c 55)))))
  n)

(defun pa:plain (s / out i n c j)
  ;; MText contents without formatting codes; \P becomes a line break.
  (setq out "" i 1 n (strlen s))
  (while (<= i n)
    (setq c (substr s i 1))
    (cond
      ((= c "\\")
       (setq c (substr s (1+ i) 1))
       (cond
         ((= c "P") (setq out (strcat out "\n") i (+ i 2)))
         ((= c "~") (setq out (strcat out " ") i (+ i 2)))
         ((member c '("\\" "{" "}")) (setq out (strcat out c) i (+ i 2)))
         ((and (= c "U") (= (substr s (+ i 2) 1) "+"))
          (setq out (strcat out (chr (pa:hex (substr s (+ i 3) 4)))) i (+ i 7)))
         ((member c '("L" "l" "O" "o" "K" "k" "N")) (setq i (+ i 2)))
         ((= c "S")
          ;; stacked fraction: keep it as a/b
          (setq j (vl-string-search ";" s i))
          (if j
            (setq out (strcat out (vl-string-translate "^#" "//" (substr s (+ i 2) (- j i 1))))
                  i (+ j 2))
            (setq i (1+ n))))
         (T
          ;; \f \H \C \p \A \Q \T \W and the like run up to ";"
          (setq j (vl-string-search ";" s i))
          (setq i (if j (+ j 2) (1+ n))))))
      ((member c '("{" "}")) (setq i (1+ i)))
      (T (setq out (strcat out c) i (1+ i)))))
  out)

;;; ---- Collecting Model space -------------------------------------------------
;;; Fills hsegs, vsegs, cellsegs, rowsegs and texts, which are local to pa:read-drawing.

(defun pa:side-p (d)
  ;; Whether a line d long could be a side of a рамка of any size.
  (vl-some '(lambda (s) (or (pa:about d (cadr s)) (pa:about d (caddr s)))) *pdfall-sizes*))

(defun pa:size-of (w h)
  ;; The size of a рамка w wide and h high as (name w h) with its exact sides, w and h in the
  ;; рамка's orientation; nil when it is no size of *pdfall-sizes*.
  (vl-some '(lambda (s)
              (cond ((and (pa:about w (cadr s)) (pa:about h (caddr s))) (list (car s) (cadr s) (caddr s)))
                    ((and (pa:about w (caddr s)) (pa:about h (cadr s))) (list (car s) (caddr s) (cadr s)))))
           *pdfall-sizes*))

(defun pa:add-seg (p q / dx dy)
  (setq dx (abs (- (car q) (car p))) dy (abs (- (cadr q) (cadr p))))
  (cond
    ((and (< dy *pa-tol*) (pa:side-p dx))
     (setq hsegs (cons (list (min (car p) (car q)) (max (car p) (car q)) (cadr p)) hsegs)))
    ((and (< dx *pa-tol*) (pa:side-p dy))
     (setq vsegs (cons (list (car p) (min (cadr p) (cadr q)) (max (cadr p) (cadr q))) vsegs)))
    ;; shorter lines: the cell edges of title blocks, used by PDFNUM to centre numbers; an old title
    ;; block draws one 63 mm high, past its top
    ((and (< dx *pa-tol*) (< 2.0 dy 70.0))
     (setq cellsegs (cons (list (car p) (min (cadr p) (cadr q)) (max (cadr p) (cadr q))) cellsegs)))
    ((and (< dy *pa-tol*) (< 2.0 dx 419.0))
     (setq rowsegs (cons (list (cadr p) (min (car p) (car q)) (max (car p) (car q))) rowsegs)))))

(defun pa:pt (m p) (pa:apply m (car p) (cadr p)))

(defun pa:add-pline (d m / pts)
  (foreach g d (if (= (car g) 10) (setq pts (cons (cdr g) pts))))
  (setq pts (reverse pts))
  (if (= 1 (logand 1 (cdr (assoc 70 d)))) (setq pts (append pts (list (car pts)))))
  (while (cadr pts)
    (pa:add-seg (pa:pt m (car pts)) (pa:pt m (cadr pts)))
    (setq pts (cdr pts))))

;; texts entries are (x y comparable as-typed owner), see the zone of a record above.
(defun pa:add-string (p raw)
  (setq raw (vl-string-trim " \t\n" raw))
  (if (/= raw "")
    (setq texts (cons (list (car p) (cadr p) (pa:cyr raw) raw pa-owner) texts))))

(defun pa:rotate (p dx dy ang)
  (list (+ (car p) (- (* dx (cos ang)) (* dy (sin ang))))
        (+ (cadr p) (* dx (sin ang)) (* dy (cos ang)))))

(defun pa:add-text (d m / box r)
  ;; TEXT or ATTRIB, placed at the centre of its text box.
  (setq box (vl-catch-all-apply 'textbox (list d))
        r (cond ((cdr (assoc 50 d))) (0.0)))
  (if (or (vl-catch-all-error-p box) (null box)) (setq box '((0.0 0.0) (0.0 0.0))))
  (pa:add-string
    (pa:pt m (pa:rotate (cdr (assoc 10 d))
                        (/ (+ (caar box) (caadr box)) 2.0)
                        (/ (+ (cadar box) (cadadr box)) 2.0)
                        r))
    (cdr (assoc 1 d))))

(defun pa:add-mtext (d m / w h at col row ang s)
  ;; MTEXT, placed at the centre of its box worked out from the attachment point.
  (setq w (cond ((cdr (assoc 42 d))) (0.0))
        h (cond ((cdr (assoc 43 d))) (0.0))
        at (cond ((cdr (assoc 71 d))) (1))
        col (rem (1- at) 3)
        row (/ (1- at) 3)
        ang (if (assoc 11 d) (angle '(0.0 0.0) (cdr (assoc 11 d))) (cond ((cdr (assoc 50 d))) (0.0)))
        s "")
  (foreach g d (if (= (car g) 3) (setq s (strcat s (cdr g)))))
  (pa:add-string
    (pa:pt m (pa:rotate (cdr (assoc 10 d)) (* w (- 0.5 (* 0.5 col))) (* h (- (* 0.5 row) 0.5)) ang))
    (pa:plain (strcat s (cdr (assoc 1 d))))))

(defun pa:add-insert (e d m depth / name blk ins o sx sy r a b c dd ad)
  (setq name (cdr (assoc 2 d))
        blk (tblsearch "BLOCK" name))
  (if (and blk (= 0 (logand 4 (cdr (assoc 70 blk)))))
    (progn
      (setq ins (cdr (assoc 10 d)) o (cdr (assoc 10 blk))
            sx (cond ((cdr (assoc 41 d))) (1.0))
            sy (cond ((cdr (assoc 42 d))) (1.0))
            r (cond ((cdr (assoc 50 d))) (0.0))
            a (* (cos r) sx) b (- (* (sin r) sy)) c (* (sin r) sx) dd (* (cos r) sy))
      (pa:walk-block (cdr (assoc -2 blk))
                     (pa:compose m (list a b c dd
                                         (- (car ins) (+ (* a (car o)) (* b (cadr o))))
                                         (- (cadr ins) (+ (* c (car o)) (* dd (cadr o))))))
                     (1+ depth))
      (setq pa-owner nil)
      (if (= 1 (cdr (assoc 66 d)))
        (while (and (setq e (entnext e)) (= "ATTRIB" (cdr (assoc 0 (setq ad (entget e))))))
          (if (= 0 (logand 1 (cdr (assoc 70 ad)))) (pa:add-text ad m)))))))

(defun pa:walk-ent (e m depth / d type)
  (setq d (entget e) type (cdr (assoc 0 d))
        pa-owner (if (and (= depth 0) (member type '("TEXT" "MTEXT"))) e))
  (cond
    ((= type "LINE") (pa:add-seg (pa:pt m (cdr (assoc 10 d))) (pa:pt m (cdr (assoc 11 d)))))
    ((= type "LWPOLYLINE") (pa:add-pline d m))
    ((member type '("TEXT" "ATTRIB")) (pa:add-text d m))
    ((= type "MTEXT") (pa:add-mtext d m))
    ((and (= type "INSERT") (< depth 6)) (pa:add-insert e d m depth))))

(defun pa:walk-block (e m depth)
  (while e
    (pa:walk-ent e m depth)
    (setq e (entnext e))))

(defun pa:walk-model (/ ss i)
  (if (setq ss (ssget "_X" '((410 . "Model"))))
    (repeat (setq i (sslength ss))
      (pa:walk-ent (ssname ss (setq i (1- i))) *pa-identity* 0))))

;;; ---- Рамки and title blocks -------------------------------------------------

(defun pa:vseg-p (x y1 y2)
  (vl-some '(lambda (v) (and (pa:near (car v) x) (pa:near (cadr v) y1) (pa:near (caddr v) y2)))
           vsegs))

(defun pa:find-frames (/ out)
  ;; Rectangles of about an A size with all four sides drawn: (llx lly urx ury).
  (foreach b hsegs
    (foreach tp hsegs
      (if (and (pa:near (car tp) (car b))
               (pa:near (cadr tp) (cadr b))
               (> (caddr tp) (caddr b))
               (pa:size-of (- (cadr b) (car b)) (- (caddr tp) (caddr b)))
               (pa:vseg-p (car b) (caddr b) (caddr tp))
               (pa:vseg-p (cadr b) (caddr b) (caddr tp))
               (not (vl-some '(lambda (f) (and (pa:near (car f) (car b)) (pa:near (cadr f) (caddr b))))
                             out)))
        (setq out (cons (list (car b) (caddr b) (cadr b) (caddr tp)) out)))))
  out)

(defun pa:below-entry (z zone / v)
  ;; The text of the number written in the cell under the label z.
  (foreach o zone
    (if (and (pa:digits-p (caddr o))
             (< (abs (- (car o) (car z))) 6.0)
             (< 2.0 (- (cadr z) (cadr o)) 12.0))
      (setq v o)))
  v)

(defun pa:right-entry (z zone / v)
  ;; The text of the number written after the label z in the same cell, as old title blocks have it.
  (foreach o zone
    (if (and (pa:digits-p (caddr o))
             (< 2.0 (- (car o) (car z)) 15.0)
             (< (abs (- (cadr o) (cadr z))) 2.5))
      (setq v o)))
  v)

(defun pa:title-zone (f kind / all v top)
  ;; The texts of a рамка's title block, with x and y measured from the рамка's bottom-right corner.
  (foreach tx texts
    (setq v (cons (- (car tx) (caddr f)) (cons (- (cadr tx) (cadr f)) (cddr tx))))
    (if (and (<= -192.0 (car v) 0.0) (<= 0.0 (cadr v) 60.0))
      (setq all (cons v all))))
  ;; The title block is 55 mm high on a лист, 40 mm on the first page of a специфікація or текстовий
  ;; документ, 15 mm after that.
  (setq top (cond ((= kind "list") 60.0)
                  ((vl-some '(lambda (z) (and (<= (cadr z) 45.0) (= (car (pa:words (caddr z))) (pa:label "total"))))
                            all)
                   45.0)
                  (T 20.0)))
  (vl-remove-if '(lambda (z) (> (cadr z) top)) all))

(defun pa:title-block-p (zone)
  ;; Whether zone, a рамка's corner as pa:title-zone gives it, holds a title block: one of the labels
  ;; every form has.
  (vl-some '(lambda (z) (member (car (pa:words (caddr z)))
                                (list (pa:label "sheet") (pa:label "total") (pa:label "corner")
                                      (pa:label "date") (pa:label "scale"))))
           zone))

(defun pa:frame-kind (f zone / w h)
  ;; "list", "spec" or "text": what the рамка f holds, from its title block, whose texts up to 60 mm
  ;; are zone (docs/adr/0009). The Дата head sits 37.5 mm up on every лист's title block, 32.5 mm on a
  ;; first page and 7.5 mm on a later one; old drawings have Масштаб too. A специфікація has its
  ;; table head along the рамка's top edge (any of its column heads: a real one may lack some), a
  ;; текстовий документ doesn't. Only a лист is bigger than A4.
  (setq w (- (caddr f) (car f)) h (- (cadddr f) (cadr f)))
  (cond
    ((> (* w h) (* 1.5 210.0 297.0)) (pa:log "  kind list: bigger than A4") "list")
    ((setq w (vl-some '(lambda (z) (if (or (= (car (pa:words (caddr z))) (pa:label "scale"))
                                          (and (equal (pa:words (caddr z)) (list (pa:label "date"))) (>= (cadr z) 35.0)))
                                      z))
                      zone))
     (pa:log (list "  kind list: title-block label" (cadddr w) "at" (car w) (cadr w)))
     "list")
    ((setq w (vl-some '(lambda (tx) (if (and (< (car f) (car tx) (caddr f)) (< (- (cadddr f) 20.0) (cadr tx) (cadddr f))
                                            (member (car (pa:words (caddr tx))) (pa:label "spec-heads")))
                                       tx))
                      texts))
     (pa:log (list "  kind spec: table head" (cadddr w) "at the top"))
     "spec")
    (T (pa:log "  kind text: no scale label, date head below 35 mm, no table head at the top") "text")))

(defun pa:cells (f / out)
  ;; The vertical cell edges around a рамка's title block, as (x y1 y2) measured like its zone.
  (foreach s cellsegs
    (setq s (list (- (car s) (caddr f)) (- (cadr s) (cadr f)) (- (caddr s) (cadr f))))
    (if (and (<= -222.0 (car s) 30.0) (<= -10.0 (caddr s)) (<= (cadr s) 60.0))
      (setq out (cons s out))))
  out)

(defun pa:rows (f / out)
  ;; The horizontal cell edges around a рамка's title block, as (y x1 x2) measured like its zone.
  (foreach s rowsegs
    (setq s (list (- (car s) (cadr f)) (- (cadr s) (caddr f)) (- (caddr s) (caddr f))))
    (if (and (<= -10.0 (car s) 65.0) (<= -230.0 (caddr s)) (<= (cadr s) 30.0))
      (setq out (cons s out))))
  out)

(defun pa:cell-box (r x y / left right below above)
  ;; The title-block cell of r around the point x,y (measured from the рамка's bottom-right corner)
  ;; as (left bottom right top), from its edge lines; nil unless all four are found.
  (foreach s (pa:get 'cells r)
    (if (and (<= (cadr s) y (caddr s)) (< (abs (- (car s) x)) 30.0))
      (if (< (car s) x)
        (if (or (null left) (> (car s) left)) (setq left (car s)))
        (if (or (null right) (< (car s) right)) (setq right (car s))))))
  (foreach s (pa:get 'rows r)
    (if (<= (cadr s) x (caddr s))
      (if (< (car s) y)
        (if (or (null below) (> (car s) below)) (setq below (car s)))
        (if (or (null above) (< (car s) above)) (setq above (car s))))))
  (if (and left right below above) (list left below right above)))

(defun pa:text-style (d)
  ;; Layer, style, height, width, colour and slant (51) of a TEXT: title blocks lean their text
  ;; 15 degrees. Of an MTEXT, as old title blocks have, only layer, style, height and colour: its 41
  ;; is the width of its box, not of its letters.
  (vl-remove nil (mapcar '(lambda (k) (assoc k d))
                         (if (= (cdr (assoc 0 d)) "MTEXT") '(8 7 40 62) '(8 7 40 41 51 62)))))

(defun pa:gap (a b) (distance (list (car a) (cadr a)) (list (car b) (cadr b))))

(defun pa:label-style (z zone / o)
  ;; The look of the zone entry z, or of the nearest plain text of its title block if z is inside a
  ;; block.
  (if (and (nth 4 z) (= "TEXT" (cdr (assoc 0 (entget (nth 4 z))))))
    (pa:text-style (entget (nth 4 z)))
    (progn
      (foreach x zone
        (if (and (nth 4 x) (= "TEXT" (cdr (assoc 0 (entget (nth 4 x)))))
                 (or (null o) (< (pa:gap z x) (pa:gap z o))))
          (setq o x)))
      (if o (pa:text-style (entget (nth 4 o))) (list (cons 40 2.5))))))

(defun pa:title-cells (zone / roles w role o out)
  ;; The counter cells of a title block, as (role label n entry):
  ;;   role   sheet (Аркуш), total (Аркушів) or corner (Арк. on a later аркуш of a специфікація)
  ;;   label  the zone entry of the label
  ;;   n      the number in the cell, nil when it is empty
  ;;   entry  the zone entry of the number when it is a text of its own: under the label, or after it
  ;;          in the same row as old title blocks have it; nil when it follows the label in the same
  ;;          text, as PDFNUM writes it on a new лист ("Аркуш 2")
  (setq roles (list (cons (pa:label "sheet") 'sheet) (cons (pa:label "total") 'total)
                    (cons (pa:label "corner") 'corner)))
  (foreach z zone
    (setq w (pa:words (car (pa:split (caddr z) "\n")))
          role (cdr (assoc (car w) roles)))
    (cond
      ((and (member role '(sheet total)) (pa:digits-p (cadr w)))
       (setq out (cons (list role z (atoi (cadr w)) nil) out)))
      ((and role (null (cdr w))
            ;; only the sheet-number cell in the corner, not the "Арк." column of the changes table
            (or (/= role 'corner) (> (car z) -25.0)))
       (setq o (cond ((pa:below-entry z zone))
                     ((/= role 'corner) (pa:right-entry z zone)))
             out (cons (list role z (if o (atoi (caddr o))) o) out)))))
  (reverse out))

(defun pa:name-marka (w / i)
  ;; Where the usual марка is among the words w of a name-cell line: the first word with a letter and
  ;; a digit, after a prefix of words without digits ("Джгут", "Джгут живлення" or none), as its
  ;; position from 0. nil for a title-block label ("Формат А3", "Аркуш 2"), or when a word before it
  ;; has a digit and no letter (a date, a number).
  (if (and w (not (member (car w) (pa:label "not-names"))))
    (progn
      (setq i 0)
      (while (and w (not (pa:marka-p (car w))) (not (vl-some 'pa:digit-p (vl-string->list (car w)))))
        (setq w (cdr w) i (1+ i)))
      (if (and w (pa:marka-p (car w))) i))))

(defun pa:name-cell-p (z kind)
  ;; Whether the zone entry z is inside the name cell, wherever the forms have it.
  (and (< -125.0 (car z) -55.0) (if (= kind "list") (< 20.0 (cadr z) 45.0) (< (cadr z) 30.0))))

(defun pa:first-line-words (s) (pa:words (car (pa:split s "\n"))))

(defun pa:org-title (r / top)
  ;; The words of the first line of the topmost text in r's organisation cell, at the bottom right
  ;; under Аркуш (ДВНЗ "ПДАБА"), or nil. Every лист and first page has it at x -50..0, y 0..20; a
  ;; later page of a специфікація has only the Арк. cell there, at x -10..0.
  (if (not (assoc 'corner (pa:get 'counters r)))
    (foreach z (pa:get 'zone r)
      (if (and (< -50.0 (car z) -10.0) (< 0.0 (cadr z) 20.0)
               (pa:first-line-words (caddr z))
               (not (member (car (pa:first-line-words (caddr z))) (pa:label "not-names")))
               (or (null top) (> (cadr z) (cadr top))))
        (setq top z))))
  (if top (pa:first-line-words (cadddr top))))

(defun pa:read-title (zone counters kind / w i names top sheet total)
  ;; Returns (names sheet total). names holds (марка-for-comparing марка-as-typed) for every
  ;; name-cell candidate; comparing turns Latin lookalike letters into Cyrillic. Only texts in the
  ;; name cell count, so the organisation cell ("ТОВ Енергія-2") or a connector label drawn near the
  ;; title block isn't taken for the марка.
  (foreach c counters
    (if (caddr c) (if (= (car c) 'total) (setq total (caddr c)) (setq sheet (caddr c)))))
  (foreach z zone
    (setq w (pa:words (car (pa:split (caddr z) "\n"))))
    (if (and (pa:name-cell-p z kind) (setq i (pa:name-marka w)) (> i 0))
      (setq names (cons (list (nth i w) (nth i (pa:words (car (pa:split (cadddr z) "\n"))))) names))))
  ;; A марка with no prefix ("3Р", or an old drawing's "M1") counts only when no text has one with a
  ;; prefix.
  (if (null names)
    (foreach z zone
      (setq w (pa:words (car (pa:split (caddr z) "\n"))))
      (if (and (pa:name-cell-p z kind) (= 0 (pa:name-marka w)))
        (setq names (cons (list (car w) (car (pa:words (car (pa:split (cadddr z) "\n"))))) names)))))
  ;; A марка without a digit ("Лорем") is the last word of the name's first line: PDFLIST writes
  ;; "[prefix] марка" there and the лист's second line under it, and a prefix has no digits.
  (if (null names)
    (progn
      (foreach z zone
        (setq w (pa:first-line-words (caddr z)))
        (if (and (pa:name-cell-p z kind) w (not (member (car w) (pa:label "not-names")))
                 (or (null top) (> (cadr z) (cadr top))))
          (setq top z)))
      (if top
        (setq names (list (list (last (pa:first-line-words (caddr top))) (last (pa:first-line-words (cadddr top)))))))
      (pa:log (if top (list "  marka without a digit: last word of the top name-cell text" (cadddr top))
                  "  marka: the name cell has no text"))))
  (list names sheet total))

(defun pa:paper (r)
  ;; The paper a рамка is plotted on: its size as (name width height) in the рамка's orientation,
  ;; e.g. ("A3" 420 297).
  (pa:get 'size r))

(defun pa:off-size (r / f w h)
  ;; The рамка's size as "210x295" when it is off its paper size by more than a trace; else nil.
  (setq f (pa:get 'frame r)
        w (- (caddr f) (car f))
        h (- (cadddr f) (cadr f)))
  (if (or (not (pa:near w (cadr (pa:paper r)))) (not (pa:near h (caddr (pa:paper r)))))
    (strcat (rtos w 2 0) "x" (rtos h 2 0))))

;;; ---- Records ----------------------------------------------------------------

(defun pa:get (key r) (cdr (assoc key r)))
(defun pa:put (key val r) (subst (cons key val) (assoc key r) r))

(defun pa:log-zone (f zone kind)
  ;; Every text of a рамка's title block, as the reader sees it, for the debug log.
  (foreach z (vl-sort zone '(lambda (a b) (if (pa:near (cadr a) (cadr b)) (< (car a) (car b)) (> (cadr a) (cadr b)))))
    (pa:log (list "    text" (car z) (cadr z) (if (pa:name-cell-p z kind) "[name cell]" "")
                  (if (nth 4 z) (cdr (assoc 0 (entget (nth 4 z)))) "in-block") (vl-string-translate "\n" "|" (cadddr z))))))

(defun pa:read-drawing (/ texts hsegs vsegs cellsegs rowsegs pa-owner frames kind zone counters title names r
                          records problems)
  ;; Walks Model space and reads every рамка's title block. Returns (records problems): one record
  ;; per рамка with a readable марка, and (message . record) for every рамка without one, in the
  ;; order found; the record is nil when there is no рамка at all.
  (pa:walk-model)
  (pa:log (list "reader: lines" (length hsegs) "horizontal and" (length vsegs) "vertical of a frame's length,"
                (length cellsegs) "+" (length rowsegs) "cell edges," (length texts) "texts"))
  ;; A rectangle of an A size is a рамка only with a title block in its corner: next to a лист there
  ;; may be a table or a legend boxed 297x210.
  (setq frames (vl-remove-if-not
                 '(lambda (f / ok)
                    (setq ok (pa:title-block-p (pa:title-zone f "list")))
                    (pa:log (list "reader: rectangle" (car f) (cadr f) "-" (caddr f) (cadddr f)
                                  (car (pa:size-of (- (caddr f) (car f)) (- (cadddr f) (cadr f))))
                                  (if ok "has a title block" "skipped: no title-block label in its corner")))
                    (if (and (not ok) (pa:log-on-p)) (pa:log-zone f (pa:title-zone f "list") "list"))
                    ok)
                 (pa:find-frames)))
  (if (null frames)
    (setq problems (list (cons (pa:msg "reader.no-frames" nil) nil))))
  (foreach f frames
    ;; The title block decides the kind, not the рамка's size.
    (pa:log (list "reader: frame at" (car f) (cadr f)))
    (setq zone (pa:title-zone f "list")
          kind (pa:frame-kind f zone)
          zone (if (= kind "list") zone (pa:title-zone f kind))
          counters (pa:title-cells zone)
          title (pa:read-title zone counters kind)
          names (car title)
          r (list (cons 'kind kind)
                  (list 'll (car f) (cadr f) 0.0)
                  (list 'ur (caddr f) (cadddr f) 0.0)
                  (cons 'frame f)
                  (cons 'size (pa:size-of (- (caddr f) (car f)) (- (cadddr f) (cadr f))))
                  ;; the марка exactly as typed: it may mix Latin and Cyrillic letters, like X1A1Р
                  (cons 'marka (cadar names))
                  (cons 'sheet (cadr title))
                  (cons 'total (caddr title))
                  (cons 'zone zone)
                  (cons 'counters counters)
                  (cons 'cells (pa:cells f))
                  (cons 'rows (pa:rows f))))
    (if (pa:log-on-p)
      (progn
        (pa:log-zone f zone kind)
        (pa:log (list "  size" (pa:get 'size r) "marka" (pa:get 'marka r) "candidates" (mapcar 'cadr names)
                      "sheet" (pa:get 'sheet r) "total" (pa:get 'total r)
                      "counters" (mapcar '(lambda (c) (list (car c) (cadddr (cadr c)) (caddr c))) counters)))))
    (cond
      ((null names) (setq problems (cons (cons (pa:msg "reader.no-marka" nil) r) problems)))
      ((vl-some '(lambda (x) (/= (car x) (caar names))) names)
       (setq problems
         (cons (cons (pa:msg "reader.many-markas"
                             (list "markas" (vl-string-right-trim " " (apply 'strcat (mapcar '(lambda (x) (strcat (cadr x) " ")) names)))))
                     r)
               problems)))
      (T (setq records (cons r records)))))
  (pa:log (list "reader:" (length records) "frames read," (length problems) "problems:" (mapcar 'car problems)))
  (list records (reverse problems)))

(defun pa:markas (records / out)
  ;; The марки of the records, sorted.
  (foreach r records
    (if (not (member (pa:get 'marka r) out)) (setq out (cons (pa:get 'marka r) out))))
  (acad_strlsort out))

(defun pa:of (marka kind records)
  ;; The records of one kind of one марка.
  (vl-remove-if-not '(lambda (r) (and (= (pa:get 'marka r) marka) (= (pa:get 'kind r) kind))) records))
