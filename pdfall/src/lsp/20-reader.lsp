;;; ---- Reader -----------------------------------------------------------------
;;; Reads the рамки drawn in Model space and their title blocks. Other files may call:
;;;   pa:read-drawing  -> (records problems)
;;;   pa:get pa:put    a record's fields
;;;   pa:markas pa:of  the марки of the records, and the records of one kind of one марка
;;;
;;; A record is one рамка:
;;;   ((kind . "list"|"spec") (ll x y 0) (ur x y 0) (frame llx lly urx ury)
;;;    (marka . s) (sheet . n) (total . n) (zone ...) (counters ...) (cells ...))
;;; zone holds the texts of its title block as (x y comparable as-typed owner), counters its
;;; Аркуш, Аркушів and Арк. cells as pa:title-cells returns them, cells the short vertical lines
;;; around it as (x y1 y2); x and y are measured from the рамка's bottom-right corner.
;;; owner is the TEXT or MTEXT entity when it sits directly in Model space (so PDFNUM can edit it),
;;; nil when it is inside a block.

;;; ---- Geometry ---------------------------------------------------------------

(setq *pa-tol* 0.5)

(defun pa:near (a b) (< (abs (- a b)) *pa-tol*))

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
;;; Fills hsegs, vsegs, cellsegs and texts, which are local to pa:read-drawing.

(defun pa:add-seg (p q / dx dy)
  (setq dx (abs (- (car q) (car p))) dy (abs (- (cadr q) (cadr p))))
  (cond
    ((and (< dy *pa-tol*) (or (pa:near dx 420.0) (pa:near dx 210.0)))
     (setq hsegs (cons (list (min (car p) (car q)) (max (car p) (car q)) (cadr p)) hsegs)))
    ((and (< dx *pa-tol*) (pa:near dy 297.0))
     (setq vsegs (cons (list (car p) (min (cadr p) (cadr q)) (max (cadr p) (cadr q))) vsegs)))
    ;; short vertical lines: the cell edges of title blocks, used by PDFNUM to centre numbers
    ((and (< dx *pa-tol*) (< 2.0 dy 60.0))
     (setq cellsegs (cons (list (car p) (min (cadr p) (cadr q)) (max (cadr p) (cadr q))) cellsegs)))))

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
  ;; Rectangles of 420x297 or 210x297 with all four sides drawn: (llx lly urx ury).
  (foreach b hsegs
    (foreach tp hsegs
      (if (and (pa:near (car tp) (car b))
               (pa:near (cadr tp) (cadr b))
               (pa:near (- (caddr tp) (caddr b)) 297.0)
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

(defun pa:title-zone (f kind / all v top)
  ;; The texts of a рамка's title block, with x and y measured from the рамка's bottom-right corner.
  (foreach tx texts
    (setq v (cons (- (car tx) (caddr f)) (cons (- (cadr tx) (cadr f)) (cddr tx))))
    (if (and (<= -192.0 (car v) 0.0) (<= 0.0 (cadr v) 60.0))
      (setq all (cons v all))))
  ;; The title block is 55 mm high on a лист, 40 mm on a первый аркуш специфікації, 15 mm after that.
  (setq top (cond ((= kind "list") 60.0)
                  ((vl-some '(lambda (z) (and (<= (cadr z) 45.0) (= (car (pa:words (caddr z))) (pa:label "total"))))
                            all)
                   45.0)
                  (T 20.0)))
  (vl-remove-if '(lambda (z) (> (cadr z) top)) all))

(defun pa:cells (f / out)
  ;; The cell edges around a рамка's title block, measured like its zone.
  (foreach s cellsegs
    (setq s (list (- (car s) (caddr f)) (- (cadr s) (cadr f)) (- (caddr s) (cadr f))))
    (if (and (<= -222.0 (car s) 30.0) (<= -10.0 (caddr s)) (<= (cadr s) 60.0))
      (setq out (cons s out))))
  out)

(defun pa:title-cells (zone / roles w role o out)
  ;; The counter cells of a title block, as (role label n entry):
  ;;   role   sheet (Аркуш), total (Аркушів) or corner (Арк. on a later аркуш of a специфікація)
  ;;   label  the zone entry of the label
  ;;   n      the number in the cell, nil when it is empty
  ;;   entry  the zone entry of the number when it is written under the label; nil when it follows
  ;;          the label in the same text, as PDFNUM writes it on a лист ("Аркуш 2")
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
       (setq o (pa:below-entry z zone)
             out (cons (list role z (if o (atoi (caddr o))) o) out)))))
  (reverse out))

(defun pa:read-title (zone counters / w names sheet total)
  ;; Returns (names sheet total). names holds (марка-for-comparing марка-as-typed) for every
  ;; name-cell candidate; comparing turns Latin lookalike letters into Cyrillic.
  (foreach c counters
    (if (caddr c) (if (= (car c) 'total) (setq total (caddr c)) (setq sheet (caddr c)))))
  (foreach z zone
    (setq w (pa:words (car (pa:split (caddr z) "\n"))))
    (if (and (cadr w)
             (not (member (car w) (pa:label "not-names")))
             (pa:marka-p (cadr w)))
      (setq names (cons (list (cadr w) (cadr (pa:words (car (pa:split (cadddr z) "\n"))))) names))))
  (list names sheet total))

;;; ---- Records ----------------------------------------------------------------

(defun pa:get (key r) (cdr (assoc key r)))
(defun pa:put (key val r) (subst (cons key val) (assoc key r) r))

(defun pa:read-drawing (/ texts hsegs vsegs cellsegs pa-owner frames kind zone counters title names r
                          records problems)
  ;; Walks Model space and reads every рамка's title block. Returns (records problems): one record
  ;; per рамка with a readable марка, and (message . record) for every рамка without one, in the
  ;; order found; the record is nil when there is no рамка at all.
  (pa:walk-model)
  (setq frames (pa:find-frames))
  (if (null frames)
    (setq problems (list (cons (pa:msg "reader.no-frames" nil) nil))))
  (foreach f frames
    (setq kind (if (pa:near (- (caddr f) (car f)) 420.0) "list" "spec")
          zone (pa:title-zone f kind)
          counters (pa:title-cells zone)
          title (pa:read-title zone counters)
          names (car title)
          r (list (cons 'kind kind)
                  (list 'll (car f) (cadr f) 0.0)
                  (list 'ur (caddr f) (cadddr f) 0.0)
                  (cons 'frame f)
                  ;; the марка exactly as typed: it may mix Latin and Cyrillic letters, like X1A1Р
                  (cons 'marka (cadar names))
                  (cons 'sheet (cadr title))
                  (cons 'total (caddr title))
                  (cons 'zone zone)
                  (cons 'counters counters)
                  (cons 'cells (pa:cells f))))
    (cond
      ((null names) (setq problems (cons (cons (pa:msg "reader.no-marka" nil) r) problems)))
      ((vl-some '(lambda (x) (/= (car x) (caar names))) names)
       (setq problems
         (cons (cons (pa:msg "reader.many-markas"
                             (list "markas" (vl-string-right-trim " " (apply 'strcat (mapcar '(lambda (x) (strcat (cadr x) " ")) names)))))
                     r)
               problems)))
      (T (setq records (cons r records)))))
  (list records (reverse problems)))

(defun pa:markas (records / out)
  ;; The марки of the records, sorted.
  (foreach r records
    (if (not (member (pa:get 'marka r) out)) (setq out (cons (pa:get 'marka r) out))))
  (acad_strlsort out))

(defun pa:of (marka kind records)
  ;; The records of one kind of one марка.
  (vl-remove-if-not '(lambda (r) (and (= (pa:get 'marka r) marka) (= (pa:get 'kind r) kind))) records))
