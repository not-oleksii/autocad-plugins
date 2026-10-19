;;; PDFALL: plot every лист and специфікація drawn in Model space to PDF, then merge them.
;;; PDFNUM: fill in the empty Аркуш and Аркушів cells of their title blocks.
;;; PDFLIST, PDFSPEC: paste an empty рамка with its title block for a лист or a специфікація.
;;;
;;; Terms are defined in GLOSSARY.md, the design in docs/adr/0001-plot-from-model-space-with-lisp.md.
;;; install.bat installs it as PDFALL.bundle, which AutoCAD loads by itself at startup.
;;; Type PDFALL in a saved drawing.
;;;
;;; What it does:
;;;   1. Finds every рамка (the dash-dot 420x297 or 210x297 border) in Model space.
;;;   2. Reads марка, Аркуш and Аркушів from each рамка's title block.
;;;   3. Checks every марка; if anything is wrong, nothing is plotted.
;;;   4. Writes "exported files\<марка>\" next to the drawing:
;;;        <марка> лист N.pdf, <марка> лист N без заливки.pdf, <марка> специфікація лист N.pdf
;;;   5. Runs merge.exe on "exported files" to build Загальний and Загальний друк.

(vl-load-com)

(setq *pdfall-version* "1.4.0")

;;; ---- Settings ---------------------------------------------------------------

;; Every name the шар заливки may have. Add the new name here if you ever rename it.
(setq *pdfall-fill-layers* '("Цвет" "Колір"))

;; PDFALL.pc3 is AutoCAD PDF (General Documentation) with "open in viewer" off, so a run does
;; not open dozens of viewer windows. PDFALL copies it into the Plotters folder on its first run;
;; if that fails, the original is used.
(setq *pdfall-devices* '("PDFALL.pc3" "AutoCAD PDF (General Documentation).pc3"))
(setq *pdfall-paper-sheet* "ISO full bleed A3 (420.00 x 297.00 MM)")
(setq *pdfall-paper-spec* "ISO full bleed A4 (210.00 x 297.00 MM)")
(setq *pdfall-folder* "exported files")

;; The folder holding pdfall.lsp, merge.exe and PDFALL.pc3: the installed PDFALL.bundle\Contents.
;; Set it before loading this file to run PDFALL from another folder.
(if (not *pdfall-home*)
  (setq *pdfall-home*
    (cond ((findfile "pdfall.lsp") (vl-filename-directory (findfile "pdfall.lsp")))
          ((strcat (getenv "APPDATA") "\\Autodesk\\ApplicationPlugins\\PDFALL.bundle\\Contents")))))

;; The program that combines the PDFs into Загальний and Загальний друк; nil plots without merging.
(setq *pdfall-merge* (strcat *pdfall-home* "\\merge.exe"))

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

;;; ---- Text -------------------------------------------------------------------

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

;;; ---- Collecting Model space -------------------------------------------------
;;; Fills hsegs, vsegs and texts, which are local to c:PDFALL.

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

;; texts entries are (x y comparable as-typed owner): owner is the TEXT or MTEXT entity when it
;; sits directly in Model space (so PDFNUM can edit it), nil when it is inside a block.
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

(defun pa:below (z zone / o)
  ;; The number written in the cell under the label z.
  (if (setq o (pa:below-entry z zone)) (atoi (caddr o))))

(defun pa:title-zone (f kind / all v top)
  ;; The texts of a рамка's title block, as (x y comparable as-typed owner) with x and y measured
  ;; from the рамка's bottom-right corner.
  (foreach tx texts
    (setq v (cons (- (car tx) (caddr f)) (cons (- (cadr tx) (cadr f)) (cddr tx))))
    (if (and (<= -192.0 (car v) 0.0) (<= 0.0 (cadr v) 60.0))
      (setq all (cons v all))))
  ;; The title block is 55 mm high on a лист, 40 mm on a первый аркуш специфікації, 15 mm after that.
  (setq top (cond ((= kind "лист") 60.0)
                  ((vl-some '(lambda (z) (and (<= (cadr z) 45.0) (= (car (pa:words (caddr z))) "Аркушів")))
                            all)
                   45.0)
                  (T 20.0)))
  (vl-remove-if '(lambda (z) (> (cadr z) top)) all))

(defun pa:read-title (f kind / zone w v names sheet total)
  ;; Returns (names sheet total). names holds (марка-for-comparing марка-as-typed) for every
  ;; name-cell candidate; comparing turns Latin lookalike letters into Cyrillic.
  (setq zone (pa:title-zone f kind))
  (foreach z zone
    (setq w (pa:words (car (pa:split (caddr z) "\n"))))
    (cond
      ((and (= (car w) "Аркуш") (pa:digits-p (cadr w))) (setq sheet (atoi (cadr w))))
      ((and (= (car w) "Аркушів") (pa:digits-p (cadr w))) (setq total (atoi (cadr w))))
      ((equal w '("Аркуш")) (if (setq v (pa:below z zone)) (setq sheet v)))
      ((equal w '("Аркушів")) (if (setq v (pa:below z zone)) (setq total v)))
      ((equal w '("Арк."))
       ;; only the sheet-number cell in the corner, not the "Арк." column of the changes table
       (if (and (> (car z) -25.0) (setq v (pa:below z zone))) (setq sheet v)))
      ((and (cadr w)
            (not (member (car w) '("Аркуш" "Аркушів" "Арк." "Лист" "Листів" "Масштаб" "Маса" "Літера")))
            (pa:marka-p (cadr w)))
       (setq names (cons (list (cadr w) (cadr (pa:words (car (pa:split (cadddr z) "\n"))))) names)))))
  (list names sheet total))

;;; ---- Records ----------------------------------------------------------------
;;; One record per рамка: ((kind . "лист"|"специфікація") (ll x y 0) (ur x y 0) (marka . s) (sheet . n) (total . n))

(defun pa:get (key r) (cdr (assoc key r)))
(defun pa:put (key val r) (subst (cons key val) (assoc key r) r))

(defun pa:where (r)
  (strcat "рамка " (pa:kind-of (pa:get 'kind r)) " у точці "
          (rtos (car (pa:get 'll r)) 2 0) "," (rtos (cadr (pa:get 'll r)) 2 0)))

;; "лист" and "специфікація" as they read after "рамка" (of one) and "рамок/рамки" (of many).
(defun pa:kind-of (kind) (if (= kind "лист") "листа" "специфікації"))
(defun pa:kind-pl (kind) (if (= kind "лист") "листів" "специфікацій"))

(defun pa:err (msg r) (setq errors (cons (cons msg r) errors)))
(defun pa:warn (msg) (setq warnings (cons msg warnings)))

(defun pa:file-name (marka r unfilled)
  (strcat marka
          (if (= (pa:get 'kind r) "лист") " лист " " специфікація лист ")
          (itoa (pa:get 'sheet r))
          (if unfilled " без заливки" "")
          ".pdf"))

(defun pa:check (marka kind items / n nums out r k)
  ;; Settles and checks the sheet numbers of one kind of one марка. Returns the items, numbered.
  (setq n (length items))
  (if (= n 1)
    (progn
      (setq r (car items))
      (if (or (null (pa:get 'sheet r)) (null (pa:get 'total r)))
        (pa:warn (strcat marka " " kind ": клітинки Аркуш/Аркушів порожні, тому це лист 1."
                         " Заповніть їх командою PDFNUM.")))
      (if (null (pa:get 'sheet r)) (setq items (list (pa:put 'sheet 1 r))))))
  (foreach r items
    (if (null (pa:get 'sheet r))
      (pa:err (strcat marka ": клітинка Аркуш порожня, хоча рамок " (pa:kind-pl kind) ": " (itoa n)
                      " (PDFNUM її заповнить)")
              r)))
  (setq nums (vl-remove nil (mapcar '(lambda (r) (pa:get 'sheet r)) items)))
  (foreach r items
    (setq k (pa:get 'sheet r))
    (if (and k (> (length (vl-remove-if-not '(lambda (x) (= x k)) nums)) 1))
      (pa:err (strcat marka ": Аркуш " (itoa k) " стоїть на кількох рамках " (pa:kind-pl kind)) r))
    (if (and k (or (< k 1) (> k n)))
      (pa:err (strcat marka ": Аркуш " (itoa k) ", але рамок " (pa:kind-pl kind) " лише " (itoa n)) r)))
  (setq k 1)
  (while (<= k n)
    (if (and (not (member k nums)) (= (length nums) n))
      (pa:err (strcat marka ": жодна рамка " (pa:kind-of kind) " не має Аркуш " (itoa k)) (car items)))
    (setq k (1+ k)))
  ;; Аркушів: on every лист; on a специфікація only on its first аркуш.
  (foreach r items
    (cond
      ((and (pa:get 'total r) (/= (pa:get 'total r) n))
       (pa:err (strcat marka ": Аркушів " (itoa (pa:get 'total r)) ", але знайдено рамок "
                       (pa:kind-pl kind) ": " (itoa n))
               r))
      ((and (null (pa:get 'total r)) (> n 1)
            (or (= kind "лист") (= (pa:get 'sheet r) 1)))
       (pa:err (strcat marka ": клітинка Аркушів порожня (PDFNUM її заповнить)") r))))
  (vl-sort items '(lambda (a b) (< (cond ((pa:get 'sheet a)) (0)) (cond ((pa:get 'sheet b)) (0))))))

;;; ---- Files ------------------------------------------------------------------

(defun pa:ours-p (name marka / w)
  ;; True for the PDFs PDFALL and merge.exe write for this марка.
  (if (and (wcmatch (strcase name) "*.PDF")
           (> (strlen name) (+ (strlen marka) 5))
           (= (substr name 1 (1+ (strlen marka))) (strcat marka " ")))
    (progn
      (setq w (pa:words (substr name (+ 2 (strlen marka)) (- (strlen name) (strlen marka) 5))))
      (or (equal w '("Загальний"))
          (equal w '("Загальний" "друк"))
          (and (= (car w) "лист") (pa:digits-p (cadr w))
               (or (null (cddr w)) (equal (cddr w) '("без" "заливки"))))
          (and (= (car w) "специфікація") (= (cadr w) "лист") (pa:digits-p (caddr w))
               (null (cdddr w)))))))

(defun pa:escape (s / out)
  ;; s with wildcard characters escaped for ssget and wcmatch.
  (setq out "")
  (foreach c (vl-string->list s)
    (setq out (strcat out (if (member c (vl-string->list "#@.*?~[]-,`")) "`" "") (chr c))))
  out)

(defun pa:plot (r path / sheetp p1 p2)
  (setq sheetp (= (pa:get 'kind r) "лист")
        p1 (trans (pa:get 'll r) 0 1)
        p2 (trans (pa:get 'ur r) 0 1))
  (if (findfile path) (vl-file-delete path))
  (princ (strcat "\n  " (vl-filename-base path) "..."))
  (command "_.-PLOT" "_Y" "Model" device
           (if sheetp *pdfall-paper-sheet* *pdfall-paper-spec*)
           "_M" (if sheetp "_L" "_P") "_N" "_W" p1 p2
           "_F" "_C" "_N" "." "_Y" "_A" path "_N" "_Y")
  (if (findfile path)
    (setq plotted (1+ plotted))
    (pa:err (strcat "не вдалося записати " path) r)))

;;; ---- Layers -----------------------------------------------------------------
;;; A layer is off when its colour (62) is negative and frozen when bit 1 of its flags (70) is set.

(defun pa:layer (name) (entget (tblobjname "LAYER" name)))

(defun pa:layer-set (name color flags / d)
  (setq d (pa:layer name))
  (entmod (subst (cons 70 flags) (assoc 70 d) (subst (cons 62 color) (assoc 62 d) d))))

(defun pa:set-fill (on / d)
  (foreach n fills
    (setq d (pa:layer n))
    (if on
      (pa:layer-set n (abs (cdr (assoc 62 d))) (logand (cdr (assoc 70 d)) (~ 1)))
      (pa:layer-set n (- (abs (cdr (assoc 62 d)))) (cdr (assoc 70 d))))))

(defun pa:restore ()
  (foreach s fill-state (pa:layer-set (car s) (cadr s) (caddr s)))
  (setq fill-state nil)
  (foreach s sysvars (setvar (car s) (cdr s)))
  (setq sysvars nil))

(defun pa:hidden-layers (/ out d nm)
  ;; Layers that are off or frozen but hold objects in Model space; their objects would not print.
  (setq d (tblnext "LAYER" T))
  (while d
    (setq nm (cdr (assoc 2 d)))
    (if (and (or (minusp (cdr (assoc 62 d))) (= 1 (logand 1 (cdr (assoc 70 d)))))
             (/= (strcase nm) "DEFPOINTS")
             (not (member nm fills))
             (not (vl-string-search "|" nm))
             (ssget "_X" (list (cons 8 (pa:escape nm)) '(410 . "Model"))))
      (setq out (cons nm out)))
    (setq d (tblnext "LAYER")))
  (reverse out))

;;; ---- The command ------------------------------------------------------------

(defun pa:report-errors (header / e)
  (princ (strcat "\n\nPDFALL: " header))
  (foreach e (reverse errors)
    (princ (strcat "\n  X " (car e) (if (cdr e) (strcat "  (" (pa:where (cdr e)) ")") ""))))
  (if (setq e (vl-some 'cdr (reverse errors)))
    (progn
      (command "_.ZOOM" "_W" (trans (pa:get 'll e) 0 1) (trans (pa:get 'ur e) 0 1))
      (princ "\n  Показано першу рамку з проблемою."))))

(defun pa:report-warnings ()
  (if warnings
    (progn
      (princ "\n\nПопередження:")
      (foreach w (reverse warnings) (princ (strcat "\n  ! " w))))))

(defun pa:read-records (/ frames kind title names r records)
  ;; Walks Model space and reads every рамка's title block. Returns one record per рамка with a
  ;; readable марка; the others go to errors.
  (pa:walk-model)
  (setq frames (pa:find-frames))
  (if (null frames)
    (pa:err "у Model space немає жодної рамки (штрихпунктирної межі 420x297 або 210x297)" nil))
  (foreach f frames
    (setq kind (if (pa:near (- (caddr f) (car f)) 420.0) "лист" "специфікація")
          title (pa:read-title f kind)
          names (car title)
          r (list (cons 'kind kind)
                  (list 'll (car f) (cadr f) 0.0)
                  (list 'ur (caddr f) (cadddr f) 0.0)
                  (cons 'frame f)
                  ;; the марка exactly as typed: it may mix Latin and Cyrillic letters, like X1A1Р
                  (cons 'marka (cadar names))
                  (cons 'sheet (cadr title))
                  (cons 'total (caddr title))))
    (cond
      ((null names) (pa:err "в основному написі не знайдено марку" r))
      ((vl-some '(lambda (x) (/= (car x) (caar names))) names)
       (pa:err (strcat "в основному написі кілька марок: "
                       (apply 'strcat (mapcar '(lambda (x) (strcat (cadr x) " ")) names)))
               r))
      (T (setq records (cons r records)))))
  records)

(defun pa:markas (records / out)
  ;; The марки of the records, sorted.
  (foreach r records
    (if (not (member (pa:get 'marka r) out)) (setq out (cons (pa:get 'marka r) out))))
  (acad_strlsort out))

(defun pa:of (marka kind records)
  ;; The records of one kind of one марка.
  (vl-remove-if-not '(lambda (r) (and (= (pa:get 'marka r) marka) (= (pa:get 'kind r) kind))) records))

(defun pa:run (/ hidden ans r records markas groups base dir files locked e)
  (if (= 0 (getvar "DWGTITLED"))
    (progn (princ "\nPDFALL: спершу збережіть креслення, щоб PDF було куди покласти.") (exit)))

  (princ "\nPDFALL: читаю креслення...")
  (setq records (pa:read-records)
        markas (pa:markas records))

  ;; Check each марка.
  ;; Two марки that look the same but are typed with different letters would split one марка in two.
  (foreach m markas
    (foreach other (cdr (member m markas))
      (if (= (pa:cyr m) (pa:cyr other))
        (pa:err (strcat "'" m "' і '" other "' виглядають однаково, але набрані різними"
                        " (латинськими/кириличними) літерами; наберіть марку однаково в усіх основних написах")
                (vl-some '(lambda (r) (if (= (pa:get 'marka r) m) r)) records)))))
  (foreach m markas
    (setq groups
      (cons (list m
                  (pa:check m "лист" (pa:of m "лист" records))
                  (pa:check m "специфікація" (pa:of m "специфікація" records)))
            groups)))
  (setq groups (reverse groups))

  (if (null fills)
    (pa:err (strcat "не знайдено шар заливки (шукав: "
                    (vl-string-right-trim ", " (apply 'strcat (mapcar '(lambda (n) (strcat n ", ")) *pdfall-fill-layers*)))
                    "). Якщо його перейменували, додайте нову назву до *pdfall-fill-layers* у pdfall.lsp")
            nil))
  (if errors
    (progn
      (pa:report-errors "нічого не надруковано. Виправте це в кресленні й запустіть PDFALL ще раз:")
      (pa:report-warnings)
      (exit)))

  ;; Hidden layers would silently drop objects from every PDF.
  (if (setq hidden (pa:hidden-layers))
    (progn
      (princ "\n\nЦі шари вимкнені або заморожені, тож їхніх об'єктів НЕ буде в PDF:")
      (foreach n hidden (princ (strcat "\n  " n)))
      (initget "Так Ні")
      (setq ans (getkword "\nВсе одно друкувати? [Так/Ні] <Ні>: "))
      (if (/= ans "Так") (progn (princ "\nPDFALL: нічого не надруковано.") (exit)))))

  (if (/= 0 (getvar "DBMOD")) (command "_.QSAVE"))

  ;; Folders, and the old PDFs of every марка plotted now.
  (setq base (strcat (getvar "DWGPREFIX") *pdfall-folder*))
  (vl-mkdir base)
  (foreach m markas
    (setq dir (strcat base "\\" m))
    (vl-mkdir dir)
    (foreach name (vl-directory-files dir "*.pdf" 1)
      (if (pa:ours-p name m)
        (setq files (cons (strcat dir "\\" name) files)))))
  (foreach path files
    (if (setq e (open path "a")) (close e) (setq locked (cons path locked))))
  (if locked
    (progn
      (princ "\n\nPDFALL: нічого не надруковано. Закрийте ці файли (відкриті в переглядачі PDF?) і запустіть PDFALL ще раз:")
      (foreach path (reverse locked) (princ (strcat "\n  X " path)))
      (exit)))
  (foreach path files (vl-file-delete path))
  (foreach name (vl-directory-files base nil -1)
    (if (not (member name (append '("." "..") markas)))
      (pa:warn (strcat "'" *pdfall-folder* "\\" name "' — не марка цього креслення, залишаю як є"))))

  ;; Plot: everything with the шар заливки on, then every лист again with it off.
  (setq sysvars (append sysvars (mapcar '(lambda (v) (cons v (getvar v))) '("BACKGROUNDPLOT" "OSMODE"))))
  (setvar "BACKGROUNDPLOT" 0)
  (setvar "OSMODE" 0)
  (setq fill-state
    (mapcar '(lambda (n / d) (setq d (pa:layer n)) (list n (cdr (assoc 62 d)) (cdr (assoc 70 d))))
            fills))
  (princ "\n\nДрукую:")
  (pa:set-fill T)
  (foreach g groups
    (foreach r (cadr g) (pa:plot r (strcat base "\\" (car g) "\\" (pa:file-name (car g) r nil))))
    (foreach r (caddr g) (pa:plot r (strcat base "\\" (car g) "\\" (pa:file-name (car g) r nil)))))
  (pa:set-fill nil)
  (foreach g groups
    (foreach r (cadr g) (pa:plot r (strcat base "\\" (car g) "\\" (pa:file-name (car g) r T)))))
  (pa:restore)

  (princ (strcat "\n\nPDFALL: " (itoa plotted) " PDF у " base))
  (if errors (pa:report-errors "ці PDF не вдалося створити:"))
  (pa:report-warnings)
  (cond
    ((null *pdfall-merge*))
    ((findfile *pdfall-merge*)
     (princ "\nЗбираю Загальний і Загальний друк в окремому вікні...")
     (startapp "cmd.exe" (strcat "/c \"\"" *pdfall-merge* "\" \"" base "\"\"")))
    (T (princ (strcat "\n! " *pdfall-merge* " не знайдено, тому нічого не зібрано. Запустіть install.bat ще раз.")))))

;; AutoCAD's Plotters folder (the first one, if several are set).
(defun pa:plotters ()
  (car (pa:split (getenv "PrinterConfigDir") ";")))

;; Copy PDFALL.pc3 from *pdfall-home* into the Plotters folder if it isn't there yet.
(defun pa:install-pc3 (/ name)
  (setq name (car *pdfall-devices*))
  (if (and (not (findfile (strcat (pa:plotters) "\\" name)))
           (findfile (strcat *pdfall-home* "\\" name)))
    (vl-file-copy (strcat *pdfall-home* "\\" name) (strcat (pa:plotters) "\\" name))))

(defun c:PDFALL (/ *error* texts hsegs vsegs cellsegs pa-owner errors warnings fills fill-state sysvars
                   plotted device)
  (defun *error* (msg)
    (pa:restore)
    (if (not (wcmatch (strcase msg) "*CANCEL*,*QUIT*,*EXIT*"))
      (princ (strcat "\nПомилка PDFALL: " msg)))
    (princ))
  (pa:install-pc3)
  (setq plotted 0
        fills (vl-remove-if-not '(lambda (n) (tblsearch "LAYER" n)) *pdfall-fill-layers*)
        device (cond ((vl-some '(lambda (n) (if (findfile (strcat (pa:plotters) "\\" n)) n))
                               *pdfall-devices*))
                     ((last *pdfall-devices*))))
  (if (/= device (car *pdfall-devices*))
    (pa:warn (strcat (car *pdfall-devices*) " немає в " (pa:plotters) ", тож кожен PDF відкриється в переглядачі."
                     " Скопіюйте його туди з " *pdfall-home* ".")))
  (setq sysvars (list (cons "CMDECHO" (getvar "CMDECHO"))))
  (setvar "CMDECHO" 0)
  (pa:run)
  (pa:restore)
  (princ))

;;; ---- PDFNUM -----------------------------------------------------------------
;;; Fills in empty Аркуш and Аркушів cells. A number that is already written is never changed.

(defun pa:empty-cells (f kind / zone w out)
  ;; The counter labels of a title block that have no number yet: ((role . label) ...), where role
  ;; is sheet (Аркуш), total (Аркушів) or corner (Арк. on a later аркуш of a специфікація).
  (setq zone (pa:title-zone f kind))
  (foreach z zone
    (setq w (pa:words (car (pa:split (caddr z) "\n"))))
    (if (null (pa:below z zone))
      (cond
        ((equal w '("Аркуш")) (setq out (cons (cons 'sheet z) out)))
        ((equal w '("Аркушів")) (setq out (cons (cons 'total z) out)))
        ((and (equal w '("Арк.")) (> (car z) -25.0)) (setq out (cons (cons 'corner z) out))))))
  ;; Аркуш before Аркушів, so the report reads in cell order
  (append (vl-remove-if '(lambda (c) (= (car c) 'total)) out)
          (vl-remove-if-not '(lambda (c) (= (car c) 'total)) out)))

(defun pa:number-style (records / zone o d)
  ;; The look of a number someone already wrote under a counter label, so new numbers match it:
  ;; ((8 . layer) (7 . style) (40 . height) ...), or nil if there is none.
  (foreach r records
    (if (= (pa:get 'kind r) "специфікація")
      (progn
        (setq zone (pa:title-zone (pa:get 'frame r) "специфікація"))
        (foreach z zone
          (if (and (null d)
                   (member (car (pa:words (caddr z))) '("Аркуш" "Аркушів" "Арк."))
                   (setq o (pa:below-entry z zone))
                   (nth 4 o)
                   (= "TEXT" (cdr (assoc 0 (entget (nth 4 o))))))
            (setq d (entget (nth 4 o))))))))
  (if d (pa:text-style d)))

(defun pa:text-style (d)
  (vl-remove nil (mapcar '(lambda (k) (assoc k d)) '(8 7 40 41 62))))

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

(defun pa:cell-x (x y / left right)
  ;; The middle of the title-block cell around x at height y, from its edge lines; x if none are found.
  (foreach s cellsegs
    (if (and (<= (cadr s) y (caddr s)) (< (abs (- (car s) x)) 30.0))
      (if (< (car s) x)
        (if (or (null left) (> (car s) left)) (setq left (car s)))
        (if (or (null right) (< (car s) right)) (setq right (car s))))))
  (if (and left right) (/ (+ left right) 2.0) x))

(defun pa:fill-cell (r cell n style / f z x y d e)
  ;; Writes number n into the empty cell. Returns nil when it can't.
  (setq f (pa:get 'frame r)
        z (cdr cell)
        e (nth 4 z)
        x (+ (car z) (caddr f))
        y (+ (cadr z) (cadr f)))
  (if (= (pa:get 'kind r) "лист")
    ;; On a лист the number follows the label in the same text: "Аркуш 2".
    (if e
      (progn
        (setq d (entget e))
        (entmod (subst (cons 1 (strcat (cdr (assoc 1 d)) " " (itoa n))) (assoc 1 d) d))))
    ;; On a специфікація it goes in the cell under the label: 5 mm lower, 7.5 mm in the corner cell.
    (progn
      (setq y (- y (if (= (car cell) 'corner) 7.5 5.0))
            x (pa:cell-x x y))
      (entmake (append (list '(0 . "TEXT") (list 10 x y 0.0) (list 11 x y 0.0) '(72 . 1) '(73 . 2)
                             (cons 1 (itoa n)))
                       (cond (style) ((pa:label-style z (pa:title-zone f "специфікація")))))))))

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
    (foreach cell (pa:empty-cells (pa:get 'frame r) kind)
      (setq what (if (= (car cell) 'total) (strcat "Аркушів " (itoa n)) (strcat "Аркуш " (itoa i))))
      (cond
        ((and (/= (car cell) 'total) (member i used))
         (pa:warn (strcat marka ": Аркуш залишено порожнім, бо інша рамка " (pa:kind-of kind)
                          " вже має " (itoa i) "  (" (pa:where r) ")")))
        ((pa:fill-cell r cell (if (= (car cell) 'total) n i) style)
         (setq done (cons what done)))
        (T (pa:warn (strcat marka ": не вдалося записати " what ", бо підпис є частиною блока  ("
                            (pa:where r) ")")))))
    (if done
      (setq filled (cons (strcat marka " " kind " " (itoa i) ": "
                                 (vl-string-right-trim ", " (apply 'strcat (mapcar '(lambda (s) (strcat s ", "))
                                                                                   (reverse done)))))
                         filled)))))

(defun c:PDFNUM (/ *error* texts hsegs vsegs cellsegs pa-owner errors warnings fill-state sysvars
                   records style filled)
  (defun *error* (msg)
    (pa:restore)
    (if (not (wcmatch (strcase msg) "*CANCEL*,*QUIT*,*EXIT*"))
      (princ (strcat "\nПомилка PDFNUM: " msg)))
    (princ))
  (setq sysvars (list (cons "CMDECHO" (getvar "CMDECHO"))))
  (setvar "CMDECHO" 0)
  (princ "\nPDFNUM: читаю креслення...")
  (setq records (pa:read-records)
        style (pa:number-style records))
  (command "_.UNDO" "_BE")
  (foreach m (pa:markas records)
    (pa:number m "лист" (pa:of m "лист" records) style)
    (pa:number m "специфікація" (pa:of m "специфікація" records) style))
  (command "_.UNDO" "_E")
  (if filled
    (progn
      (princ "\n\nPDFNUM заповнив:")
      (foreach s (reverse filled) (princ (strcat "\n  " s)))
      (princ "\nЩоб скасувати, введіть U."))
    (princ "\n\nPDFNUM: порожніх клітинок Аркуш/Аркушів немає."))
  (foreach e (reverse errors)
    (pa:warn (strcat "пропущено: " (car e) (if (cdr e) (strcat "  (" (pa:where (cdr e)) ")") ""))))
  (pa:report-warnings)
  (pa:restore)
  (princ))

;;; ---- PDFLIST and PDFSPEC ----------------------------------------------------
;;; Paste an empty рамка with its title block: PDFLIST a лист (A3), PDFSPEC a специфікація (A4).
;;; The templates are the DWGs that make_templates.ps1 cuts out of a real drawing. A template is
;;; pasted exploded, so PDFNUM and PDFALL treat it like a рамка drawn by hand.

(defun pa:subst-marka (s marka / p)
  ;; s with the МАРКА that the template leaves in the name cell replaced by marka.
  (if (setq p (vl-string-search "МАРКА" s))
    (strcat (substr s 1 p) marka (substr s (+ p 6)))
    s))

(defun pa:ask-marka (/ s)
  ;; The марка exactly as typed, or the one used last when the user just presses Enter.
  (while (not s)
    (setq s (getstring (strcat "\nМарка" (if *pdfall-marka* (strcat " <" *pdfall-marka* ">") "") ": ")))
    (if (and (= s "") *pdfall-marka*) (setq s *pdfall-marka*))
    (if (not (pa:marka-p s))
      (progn (princ "\n  Марка має містити літеру й цифру, наприклад 1ЧП.") (setq s nil))))
  (setq *pdfall-marka* s))

(defun pa:paste-start ()
  (if (/= (getvar "CTAB") "Model")
    (progn (princ "\nPDFALL: рамки вставляються в Model space. Перейдіть на вкладку Model.") (exit)))
  (setq sysvars (list (cons "CMDECHO" (getvar "CMDECHO")) (cons "CLAYER" (getvar "CLAYER"))))
  (setvar "CMDECHO" 0)
  ;; the name cell is on layer 0, so a pasted рамка must not pick up a hidden or шар заливки layer
  (setvar "CLAYER" "0")
  ;; a рамка is found only when it is square to the world axes
  (if (= 0 (getvar "WORLDUCS"))
    (progn (princ "\nPDFALL: рамки вставляються у світовій системі координат. Введіть UCS, потім W, і спробуйте ще раз.") (exit))))

(defun pa:acad-doc ()
  (vla-get-activedocument (vlax-get-acad-object)))

(defun pa:paste-cleanup ()
  ;; Also runs from *error*, where (command) may be refused; then the undo group is left to AutoCAD.
  (if undo-open
    (progn (vl-catch-all-apply '(lambda () (command "_.UNDO" "_E"))) (setq undo-open nil)))
  (pa:restore))

(defun pa:paste-one (file marka / path last0 r e d)
  ;; Pastes the template file where the user picks its lower-left corner and writes marka into
  ;; its name cell. Returns nil when the user pressed Esc instead.
  (setq path (strcat *pdfall-home* "\\" file))
  (if (not (findfile path))
    (progn (princ (strcat "\n! " path " не знайдено. Запустіть install.bat ще раз.")) (exit)))
  (setq last0 (entlast))
  (command "_.UNDO" "_BE")
  (setq undo-open T)
  ;; Esc at the insertion point is how a run ends, so it is caught here instead of reaching *error*
  (setq r (vl-catch-all-apply '(lambda () (command "_.-INSERT" path "_S" 1.0 "_R" 0.0 pause))))
  (if (vl-catch-all-error-p r) (command))
  (cond
    ((or (vl-catch-all-error-p r) (equal (entlast) last0))
     (if (and (vl-catch-all-error-p r) (not (wcmatch (strcase (vl-catch-all-error-message r)) "*CANCEL*")))
       (princ (strcat "\n! Не вдалося вставити " file ": " (vl-catch-all-error-message r))))
     (command "_.UNDO" "_E")
     (setq undo-open nil)
     nil)
    (T
     (command "_.EXPLODE" (entlast))
     ;; The block definition is not needed once it is exploded, and a stale one would be reused next time.
     ;; ActiveX is not there in the console version of AutoCAD; the definition is then left alone.
     (vl-catch-all-apply
       '(lambda ()
          (vla-delete (vla-item (vla-get-blocks (pa:acad-doc)) (vl-filename-base file)))))
     (setq e (if last0 (entnext last0) (entnext)))
     (while e
       (setq d (entget e))
       (if (and (= (cdr (assoc 0 d)) "MTEXT") (vl-string-search "МАРКА" (cdr (assoc 1 d))))
         (entmod (subst (cons 1 (pa:subst-marka (cdr (assoc 1 d)) marka)) (assoc 1 d) d)))
       (setq e (entnext e)))
     (command "_.UNDO" "_E")
     (setq undo-open nil)
     T)))

(defun pa:paste-run (cmd marka pick / what)
  ;; Pastes рамки one after another; the user ends it with Esc (Enter is not accepted at the
  ;; insertion point prompt). (apply pick (list i)) gives the template file and a description
  ;; for the i-th рамка of this run, counting from 0. The caller's placed counts them.
  (setq placed 0)
  (while (progn
           (setq what (apply pick (list placed)))
           (princ (strcat "\n" cmd ": " (cdr what) ". Вкажіть лівий нижній кут рамки або натисніть Esc, щоб закінчити."))
           (pa:paste-one (car what) marka))
    (setq placed (1+ placed))
    (princ (strcat "\n  + додано: " (cdr what)))))

(defun pa:paste-report (cmd marka)
  (princ (if (and placed (> placed 0))
           (strcat "\n\n" cmd ": додано рамок: " (itoa placed) " (марка " marka
                   "). Номери Аркуш/Аркушів заповнить PDFNUM.")
           (strcat "\n\n" cmd ": нічого не додано."))))

(defun pa:paste-failed (cmd msg)
  ;; What the *error* of PDFLIST and PDFSPEC does.
  (pa:paste-cleanup)
  (if (not (wcmatch (strcase msg) "*CANCEL*,*QUIT*,*EXIT*"))
    (princ (strcat "\nПомилка " cmd ": " msg)))
  (princ))

(defun c:PDFLIST (/ *error* sysvars fill-state undo-open marka placed)
  (defun *error* (msg) (pa:paste-failed "PDFLIST" msg))
  (pa:paste-start)
  (setq marka (pa:ask-marka))
  (pa:paste-run "PDFLIST" marka '(lambda (i) (cons "PDFALL_list.dwg" "лист (A3)")))
  (pa:paste-cleanup)
  (pa:paste-report "PDFLIST" marka)
  (princ))

(defun c:PDFSPEC (/ *error* sysvars fill-state undo-open marka placed form dflt)
  (defun *error* (msg)
    (if (and placed (> placed 0)) (setq *pdfall-spec-marka* marka))
    (pa:paste-failed "PDFSPEC" msg))
  (pa:paste-start)
  (setq marka (pa:ask-marka)
        ;; the next специфікація after one of the same марка is usually a later аркуш of it
        dflt (if (= marka *pdfall-spec-marka*) "Наступний" "Перший"))
  (initget "Перший Наступний")
  (setq form (getkword (strcat "\nАркуш специфікації [Перший/Наступний] <" dflt ">: ")))
  (if (null form) (setq form dflt))
  (pa:paste-run "PDFSPEC" marka
    '(lambda (i)
       (if (and (= i 0) (= form "Перший"))
         (cons "PDFALL_spec1.dwg" "специфікація, перший аркуш")
         (cons "PDFALL_spec2.dwg" "специфікація, наступний аркуш"))))
  (if (> placed 0) (setq *pdfall-spec-marka* marka))
  (pa:paste-cleanup)
  (pa:paste-report "PDFSPEC" marka)
  (princ))

(princ (strcat "\nPDFALL " *pdfall-version* " завантажено. PDFALL друкує всі листи й специфікації в PDF,"))
(princ " PDFNUM заповнює порожні клітинки Аркуш/Аркушів, PDFLIST і PDFSPEC вставляють порожню рамку листа й специфікації.")
(princ)
