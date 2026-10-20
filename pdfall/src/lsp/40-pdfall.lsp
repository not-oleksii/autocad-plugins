;;; ---- PDFALL -----------------------------------------------------------------
;;; Checks every марка, plots every рамка to PDF with the day's date in its Дата cell and runs
;;; merge.exe. Defines c:PDFALL; nothing here is called from the other files.
;;; Paper sizes, A4 листи and old drawings: docs/adr/0008-read-old-drawings.md; every A size and
;;; текстові документи: docs/adr/0009-every-a-size-and-settings-for-pasting.md.

;;; ---- Checks -----------------------------------------------------------------

(defun pa:check (marka kind items / n nums out r k)
  ;; Settles and checks the sheet numbers of one kind of one марка. Returns the items, numbered.
  (setq n (length items))
  (if (= n 1)
    (progn
      (setq r (car items))
      (if (or (null (pa:get 'sheet r)) (null (pa:get 'total r)))
        (pa:warn (pa:msg "check.single-empty" (list "marka" marka "kind" (pa:kind-name kind)))))
      (if (null (pa:get 'sheet r)) (setq items (list (pa:put 'sheet 1 r))))))
  (foreach r items
    (if (null (pa:get 'sheet r))
      (pa:err (pa:msg "check.sheet-empty" (list "marka" marka "kinds" (pa:kind-pl kind) "n" n)) r)))
  (setq nums (vl-remove nil (mapcar '(lambda (r) (pa:get 'sheet r)) items)))
  (foreach r items
    (setq k (pa:get 'sheet r))
    (if (and k (> (length (vl-remove-if-not '(lambda (x) (= x k)) nums)) 1))
      (pa:err (pa:msg "check.sheet-twice" (list "marka" marka "sheet" k "kinds" (pa:kind-pl kind))) r))
    (if (and k (or (< k 1) (> k n)))
      (pa:err (pa:msg "check.sheet-too-big" (list "marka" marka "sheet" k "kinds" (pa:kind-pl kind) "n" n)) r)))
  (setq k 1)
  (while (<= k n)
    (if (and (not (member k nums)) (= (length nums) n))
      (pa:err (pa:msg "check.sheet-missing" (list "marka" marka "kind" (pa:kind-of kind) "sheet" k)) (car items)))
    (setq k (1+ k)))
  ;; Аркушів: on every лист; on a специфікація or текстовий документ only on its first аркуш.
  (foreach r items
    (cond
      ((and (pa:get 'total r) (/= (pa:get 'total r) n))
       (pa:err (pa:msg "check.total-wrong" (list "marka" marka "total" (pa:get 'total r) "kinds" (pa:kind-pl kind) "n" n))
               r))
      ((and (null (pa:get 'total r)) (> n 1)
            (or (= kind "list") (= (pa:get 'sheet r) 1)))
       (pa:err (pa:msg "check.total-empty" (list "marka" marka)) r))))
  (vl-sort items '(lambda (a b) (< (cond ((pa:get 'sheet a)) (0)) (cond ((pa:get 'sheet b)) (0))))))

;;; ---- Files ------------------------------------------------------------------

(defun pa:kind-file (kind)
  ;; The word of a kind in the PDF names.
  (cond ((= kind "list") (pa:file "sheet")) ((= kind "spec") (pa:file "spec")) ((pa:file "text"))))

(defun pa:file-name (marka r unfilled)
  ;; <марка> лист NN.pdf, <марка> лист NN без заливки.pdf, <марка> специфікація NN.pdf or
  ;; <марка> текстовий документ NN.pdf
  (strcat marka " " (pa:kind-file (pa:get 'kind r)) " " (pa:pad (pa:get 'sheet r))
          (if unfilled (strcat " " (pa:file "unfilled")) "")
          ".pdf"))

(defun pa:ours-p (name marka / w)
  ;; True for the PDFs PDFALL and merge.exe write for this марка, also under the names of earlier
  ;; versions (Загальний, лист 1, специфікація лист 1), so a new run clears them away.
  (if (and (wcmatch (strcase name) "*.PDF")
           (> (strlen name) (+ (strlen marka) 5))
           (= (substr name 1 (1+ (strlen marka))) (strcat marka " ")))
    (progn
      (setq w (mapcar 'pa:lower (pa:words (substr name (+ 2 (strlen marka)) (- (strlen name) (strlen marka) 5)))))
      (or (equal w (pa:words (pa:file "general")))
          (equal w (pa:words (pa:file "general-print")))
          (and (= (car w) (pa:file "sheet")) (pa:digits-p (cadr w))
               (or (null (cddr w)) (equal (cddr w) (pa:words (pa:file "unfilled")))))
          (and (= (car w) (pa:file "spec"))
               (setq w (if (= (cadr w) (pa:file "sheet")) (cddr w) (cdr w)))
               (pa:digits-p (car w)) (null (cdr w)))
          (and (equal (reverse (cdr (reverse w))) (pa:words (pa:file "text")))
               (pa:digits-p (last w)))))))

(defun pa:escape (s / out)
  ;; s with wildcard characters escaped for ssget and wcmatch.
  (setq out "")
  (foreach c (vl-string->list s)
    (setq out (strcat out (if (member c (vl-string->list "#@.*?~[]-,`")) "`" "") (chr c))))
  out)

(defun pa:paper-name (size)
  ;; The canonical name of the paper of size (name width height), e.g.
  ;; ISO_full_bleed_A3_(420.00_x_297.00_MM).
  (pa:fill *pdfall-paper* (list "size" (car size) "w" (itoa (cadr size)) "h" (itoa (caddr size)))))

(defun pa:plot (r path / size paper p1 p2)
  ;; Plots one рамка at 1:1 on paper of exactly its size and orientation, which follow from the
  ;; рамка, not from its kind: a лист may be any A size. After the first plot AutoCAD refuses,
  ;; nothing more is plotted (refused, local to c:PDFALL).
  (setq size (pa:paper r)
        paper (pa:paper-name size)
        p1 (trans (pa:get 'll r) 0 1)
        p2 (trans (pa:get 'ur r) 0 1))
  (if (not refused)
    (progn
      (if (findfile path) (vl-file-delete path))
      (princ (strcat "\n  " (vl-filename-base path) "..."))
      (pa:log (list "plot:" path "| device" device "| paper" paper "| window" p1 p2))
      (command "_.-PLOT" "_Y" "Model" device paper)
      ;; -PLOT quits on a paper size the device doesn't know, and every answer after it would run as
      ;; a command ("Неизвестная команда M"). CMDNAMES holds English command names in any language.
      (if (wcmatch (strcase (getvar "CMDNAMES")) "*PLOT*")
        (command "_M" (if (> (cadr size) (caddr size)) "_L" "_P") "_N" "_W" p1 p2
                 "1=1" "_C" "_N" "." "_Y" "_A" path "_N" "_Y")
        (progn
          (pa:log (list "plot: -PLOT quit after the paper size; CMDNAMES" (getvar "CMDNAMES")))
          (setq refused T)
          (pa:err (pa:msg "pdfall.paper-refused" (list "paper" paper "device" device)) r)))
      (cond
        (refused)
        ((findfile path) (setq plotted (1+ plotted)) (pa:log "plot: written"))
        (T (pa:log "plot: no file written") (pa:err (pa:msg "pdfall.cannot-write" (list "path" path)) r))))))

;;; ---- Layers -----------------------------------------------------------------

(defun pa:set-fill (on / d)
  (foreach n fills
    (setq d (pa:layer n))
    (if on
      (pa:layer-set n (abs (cdr (assoc 62 d))) (logand (cdr (assoc 70 d)) (~ 1)))
      (pa:layer-set n (- (abs (cdr (assoc 62 d)))) (cdr (assoc 70 d))))))

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

(defun pa:run (/ hidden yes no ans r drawing records markas groups base dir files locked e)
  (if (= 0 (getvar "DWGTITLED"))
    (progn (princ (strcat "\n" (pa:msg "pdfall.unsaved" nil))) (exit)))

  (princ (strcat "\n" (pa:msg "reading" (list "cmd" "PDFALL"))))
  (pa:log (list "pdfall: fill layers" fills "| device" device "| plotters" (pa:plotters) "| merge" *pdfall-merge*))
  (setq drawing (pa:read-drawing)
        records (car drawing)
        markas (pa:markas records))
  (foreach p (cadr drawing) (setq errors (cons p errors)))

  ;; Check each марка.
  ;; Two марки that look the same but are typed with different letters would split one марка in two.
  (foreach m markas
    (foreach other (cdr (member m markas))
      (if (= (pa:cyr m) (pa:cyr other))
        (pa:err (pa:msg "check.lookalike" (list "marka" m "other" other))
                (vl-some '(lambda (r) (if (= (pa:get 'marka r) m) r)) records)))))
  ;; A марка is a folder and the start of every file name.
  (foreach m markas
    (if (pa:bad-char m)
      (pa:err (pa:msg "check.bad-char" (list "marka" m "char" (pa:bad-char m)))
              (vl-some '(lambda (r) (if (= (pa:get 'marka r) m) r)) records))))
  ;; groups: (марка листи специфікації текстові-документи), each kind numbered and checked.
  (foreach m markas
    (setq groups (cons (cons m (mapcar '(lambda (k) (pa:check m k (pa:of m k records))) *pa-kinds*)) groups)))
  (setq groups (reverse groups))

  ;; Old drawings have no шар заливки: their листи без заливки come out the same as the filled ones.
  (if (null fills)
    (pa:warn (pa:msg "pdfall.no-fill-layer"
                     (list "layers" (vl-string-right-trim ", " (apply 'strcat (mapcar '(lambda (n) (strcat n ", ")) *pdfall-fill-layers*)))))))
  ;; A рамка a few millimetres off its size, as in old drawings, is plotted at 1:1 all the same.
  (foreach r records
    (if (pa:off-size r)
      (pa:warn (pa:msg "pdfall.off-size" (list "marka" (pa:get 'marka r) "size" (pa:off-size r)
                                               "nominal" (strcat (itoa (cadr (pa:paper r))) "x" (itoa (caddr (pa:paper r))))
                                               "where" (pa:where r))))))
  (if errors
    (progn
      (pa:report-errors (pa:msg "pdfall.fix-first" nil))
      (pa:report-warnings)
      (exit)))

  ;; Hidden layers would silently drop objects from every PDF.
  (if (setq hidden (pa:hidden-layers))
    (progn
      (princ (strcat "\n\n" (pa:msg "pdfall.hidden-layers" nil)))
      (foreach n hidden (princ (strcat "\n  " n)))
      (setq yes (pa:msg "pdfall.yes" nil) no (pa:msg "pdfall.no" nil))
      (initget (strcat yes " " no))
      (setq ans (getkword (strcat "\n" (pa:msg "pdfall.plot-anyway" (list "yes" yes "no" no)))))
      (if (/= ans yes) (progn (princ (strcat "\n" (pa:msg "pdfall.nothing-plotted" nil))) (exit)))))

  (if (/= 0 (getvar "DBMOD")) (command "_.QSAVE"))

  ;; Folders, and the old PDFs of every марка plotted now.
  (setq base (strcat (getvar "DWGPREFIX") (pa:file "folder")))
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
      (princ (strcat "\n\n" (pa:msg "pdfall.files-locked" nil)))
      (foreach path (reverse locked) (princ (strcat "\n  X " path)))
      (exit)))
  (foreach path files (vl-file-delete path))
  (foreach name (vl-directory-files base nil -1)
    (if (not (member name (append '("." "..") markas)))
      (pa:warn (pa:msg "pdfall.not-a-marka" (list "folder" (pa:file "folder") "name" name)))))

  ;; Plot: everything with the шар заливки on, then every лист again with it off.
  (setq sysvars (append sysvars (mapcar '(lambda (v) (cons v (getvar v))) '("BACKGROUNDPLOT" "OSMODE"))))
  (setvar "BACKGROUNDPLOT" 0)
  (setvar "OSMODE" 0)
  (setq fill-state
    (mapcar '(lambda (n / d) (setq d (pa:layer n)) (list n (cdr (assoc 62 d)) (cdr (assoc 70 d))))
            fills))
  (princ (strcat "\n\n" (pa:msg "pdfall.plotting" nil)))
  (pa:date-add records)
  (pa:set-fill T)
  (foreach g groups
    (foreach items (cdr g)
      (foreach r items (pa:plot r (strcat base "\\" (car g) "\\" (pa:file-name (car g) r nil))))))
  (pa:set-fill nil)
  (foreach g groups
    (foreach r (cadr g) (pa:plot r (strcat base "\\" (car g) "\\" (pa:file-name (car g) r T)))))
  (pa:date-remove)
  (pa:restore)

  (princ (strcat "\n\n" (pa:msg "pdfall.plotted" (list "n" plotted "folder" base))))
  (if errors (pa:report-errors (pa:msg "pdfall.not-plotted" nil)))
  (pa:report-warnings)
  (cond
    ((null *pdfall-merge*))
    ((findfile *pdfall-merge*)
     (princ (strcat "\n" (pa:msg "pdfall.merging" nil)))
     (pa:log (list "pdfall: merging" base))
     (startapp "cmd.exe" (strcat "/c \"\"" *pdfall-merge* "\" \"" base "\"\"")))
    (T (princ (strcat "\n! " (pa:msg "pdfall.no-merge" (list "path" *pdfall-merge*)))))))

;; AutoCAD's Plotters folder (the first one, if several are set).
(defun pa:plotters ()
  (car (pa:split (getenv "PrinterConfigDir") ";")))

;; Copy PDFALL.pc3 from *pdfall-home* into the Plotters folder if it isn't there yet.
(defun pa:install-pc3 (/ name)
  (setq name (car *pdfall-devices*))
  (if (and (not (findfile (strcat (pa:plotters) "\\" name)))
           (findfile (strcat *pdfall-home* "\\" name)))
    (vl-file-copy (strcat *pdfall-home* "\\" name) (strcat (pa:plotters) "\\" name))))

(defun c:PDFALL (/ *error* errors warnings fills fill-state sysvars dated plotted device refused)
  (defun *error* (msg)
    (pa:date-remove)
    (pa:restore)
    (pa:report-crash "PDFALL" msg)
    (princ))
  (pa:install-pc3)
  (setq plotted 0
        fills (vl-remove-if-not '(lambda (n) (tblsearch "LAYER" n)) *pdfall-fill-layers*)
        device (cond ((vl-some '(lambda (n) (if (findfile (strcat (pa:plotters) "\\" n)) n))
                               *pdfall-devices*))
                     ((last *pdfall-devices*))))
  (if (/= device (car *pdfall-devices*))
    (pa:warn (pa:msg "pdfall.no-pc3" (list "pc3" (car *pdfall-devices*) "plotters" (pa:plotters) "home" *pdfall-home*))))
  (setq sysvars (list (cons "CMDECHO" (getvar "CMDECHO"))))
  (setvar "CMDECHO" 0)
  (pa:log-start "PDFALL")
  (pa:run)
  (pa:restore)
  (princ))
