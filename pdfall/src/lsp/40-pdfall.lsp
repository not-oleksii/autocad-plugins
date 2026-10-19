;;; ---- PDFALL -----------------------------------------------------------------
;;; Checks every марка, plots every рамка to PDF and runs merge.exe. Defines c:PDFALL; nothing here
;;; is called from the other files.

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
  ;; Аркушів: on every лист; on a специфікація only on its first аркуш.
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

(defun pa:file-name (marka r unfilled)
  ;; <марка> лист N.pdf, <марка> лист N без заливки.pdf or <марка> специфікація лист N.pdf
  (strcat marka
          (if (= (pa:get 'kind r) "list") "" (strcat " " (pa:file "spec")))
          " " (pa:file "sheet") " " (itoa (pa:get 'sheet r))
          (if unfilled (strcat " " (pa:file "unfilled")) "")
          ".pdf"))

(defun pa:ours-p (name marka / w)
  ;; True for the PDFs PDFALL and merge.exe write for this марка.
  (if (and (wcmatch (strcase name) "*.PDF")
           (> (strlen name) (+ (strlen marka) 5))
           (= (substr name 1 (1+ (strlen marka))) (strcat marka " ")))
    (progn
      (setq w (pa:words (substr name (+ 2 (strlen marka)) (- (strlen name) (strlen marka) 5))))
      (or (equal w (pa:words (pa:file "general")))
          (equal w (pa:words (pa:file "general-print")))
          (and (= (car w) (pa:file "sheet")) (pa:digits-p (cadr w))
               (or (null (cddr w)) (equal (cddr w) (pa:words (pa:file "unfilled")))))
          (and (= (car w) (pa:file "spec")) (= (cadr w) (pa:file "sheet")) (pa:digits-p (caddr w))
               (null (cdddr w)))))))

(defun pa:escape (s / out)
  ;; s with wildcard characters escaped for ssget and wcmatch.
  (setq out "")
  (foreach c (vl-string->list s)
    (setq out (strcat out (if (member c (vl-string->list "#@.*?~[]-,`")) "`" "") (chr c))))
  out)

(defun pa:plot (r path / sheetp p1 p2)
  (setq sheetp (= (pa:get 'kind r) "list")
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
    (pa:err (pa:msg "pdfall.cannot-write" (list "path" path)) r)))

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
  (foreach m markas
    (setq groups
      (cons (list m
                  (pa:check m "list" (pa:of m "list" records))
                  (pa:check m "spec" (pa:of m "spec" records)))
            groups)))
  (setq groups (reverse groups))

  (if (null fills)
    (pa:err (pa:msg "check.no-fill-layer"
                    (list "layers" (vl-string-right-trim ", " (apply 'strcat (mapcar '(lambda (n) (strcat n ", ")) *pdfall-fill-layers*)))))
            nil))
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
  (pa:set-fill T)
  (foreach g groups
    (foreach r (cadr g) (pa:plot r (strcat base "\\" (car g) "\\" (pa:file-name (car g) r nil))))
    (foreach r (caddr g) (pa:plot r (strcat base "\\" (car g) "\\" (pa:file-name (car g) r nil)))))
  (pa:set-fill nil)
  (foreach g groups
    (foreach r (cadr g) (pa:plot r (strcat base "\\" (car g) "\\" (pa:file-name (car g) r T)))))
  (pa:restore)

  (princ (strcat "\n\n" (pa:msg "pdfall.plotted" (list "n" plotted "folder" base))))
  (if errors (pa:report-errors (pa:msg "pdfall.not-plotted" nil)))
  (pa:report-warnings)
  (cond
    ((null *pdfall-merge*))
    ((findfile *pdfall-merge*)
     (princ (strcat "\n" (pa:msg "pdfall.merging" nil)))
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

(defun c:PDFALL (/ *error* errors warnings fills fill-state sysvars plotted device)
  (defun *error* (msg)
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
  (pa:run)
  (pa:restore)
  (princ))
