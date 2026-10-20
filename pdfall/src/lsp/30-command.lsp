;;; ---- Command state ----------------------------------------------------------
;;; What the commands share. Other files may call:
;;;   pa:err pa:warn     add to the command's errors and warnings
;;;   pa:where pa:problem  how a рамка, and a problem found on one, read in a message
;;;   pa:kind-name pa:kind-of pa:kind-pl  a record's kind as it reads in a message
;;;   pa:report-errors pa:report-warnings pa:report-crash
;;;   pa:cancelled-p     whether an error message means Esc, in any AutoCAD language
;;;   pa:layer pa:layer-set pa:restore  put layers and system variables back
;;;   pa:in-order pa:sheet-numbers  the order рамки of one kind of one марка are numbered in, and
;;;                    the Аркуш each gets (docs/adr/0010); PDFNUM writes them, PDFALL plots by them
;;;                    when told to plot despite wrong numbers
;;;   pa:sheet-cell-p pa:total-cell-p  whether a рамка's title block has the Аркуш / Аркушів label
;;; A command that uses them declares errors, warnings, fill-state and sysvars among its locals.

(defun pa:where (r)
  (pa:msg "where" (list "kind" (pa:kind-of (pa:get 'kind r))
                        "x" (rtos (car (pa:get 'll r)) 2 0) "y" (rtos (cadr (pa:get 'll r)) 2 0))))

(defun pa:problem (e)
  ;; An error (message . record) as it is listed: the message, then where the рамка is.
  (strcat (car e) (if (cdr e) (strcat "  (" (pa:where (cdr e)) ")") "")))

;; A kind as it reads on its own ("лист"), after "рамка" (of one: "листа") and after "рамок" (of
;; many: "листів").
(defun pa:kind-name (kind)
  (cond ((= kind "list") (pa:msg "kind.list" nil)) ((= kind "spec") (pa:msg "kind.spec" nil)) ((pa:msg "kind.text" nil))))
(defun pa:kind-of (kind)
  (cond ((= kind "list") (pa:msg "kind.list.of" nil)) ((= kind "spec") (pa:msg "kind.spec.of" nil)) ((pa:msg "kind.text.of" nil))))
(defun pa:kind-pl (kind)
  (cond ((= kind "list") (pa:msg "kind.list.pl" nil)) ((= kind "spec") (pa:msg "kind.spec.pl" nil)) ((pa:msg "kind.text.pl" nil))))

;; The kinds of рамка in the order they are plotted, numbered and merged.
(setq *pa-kinds* '("list" "spec" "text"))

(defun pa:err (msg r) (setq errors (cons (cons msg r) errors)))
(defun pa:warn (msg) (setq warnings (cons msg warnings)))

(defun pa:report-errors (header / e)
  (princ (strcat "\n\nPDFALL: " header))
  (foreach e (reverse errors)
    (pa:log (list "error:" (pa:problem e)))
    (princ (strcat "\n  X " (pa:problem e))))
  (if (setq e (vl-some 'cdr (reverse errors)))
    (progn
      (command "_.ZOOM" "_W" (trans (pa:get 'll e) 0 1) (trans (pa:get 'ur e) 0 1))
      (princ (strcat "\n  " (pa:msg "shown-first" nil))))))

(defun pa:report-warnings ()
  (if warnings
    (progn
      (princ (strcat "\n\n" (pa:msg "warnings" nil)))
      (foreach w (reverse warnings) (pa:log (list "warning:" w)) (princ (strcat "\n  ! " w))))))

;; What (exit) says in this AutoCAD's language ("quit / exit abort" in English), read once here.
(setq *pa-exit-msg* (vl-catch-all-error-message (vl-catch-all-apply 'exit nil)))

(defun pa:cancelled-p (msg)
  ;; T when an error message means the user pressed Esc, or a command stopped itself with (exit)
  ;; after saying why. AutoCAD words both in its own language (Russian: "Функция прервана").
  (or (= msg *pa-exit-msg*)
      (wcmatch (strcase msg) "*CANCEL*,*QUIT*,*EXIT*")
      (wcmatch msg *pdfall-cancel-words*)))

(defun pa:report-crash (cmd msg)
  ;; What a command's *error* says, unless the user cancelled.
  (pa:log (list cmd "stopped:" msg (if (pa:cancelled-p msg) "(cancelled)" "(error)")))
  (if (not (pa:cancelled-p msg))
    (princ (strcat "\n" (pa:msg "command-error" (list "cmd" cmd "msg" msg))))))

;;; ---- Numbering --------------------------------------------------------------

(defun pa:position< (a b / ya yb)
  ;; Upper row first, then left to right.
  (setq ya (cadr (pa:get 'll a)) yb (cadr (pa:get 'll b)))
  (if (> (abs (- ya yb)) 100.0) (> ya yb) (< (car (pa:get 'll a)) (car (pa:get 'll b)))))

(defun pa:first-page-p (r)
  ;; Whether r is the first page of a специфікація or текстовий документ: the one with Аркушів.
  (and (vl-some '(lambda (c) (= (car c) 'total)) (pa:get 'counters r)) T))

(defun pa:first-page< (a b)
  ;; A first page before later ones, then by position.
  (if (eq (pa:first-page-p a) (pa:first-page-p b)) (pa:position< a b) (pa:first-page-p a)))

(defun pa:in-order (kind items)
  ;; The рамки of one kind of one марка in the order they are numbered in.
  (vl-sort items (if (= kind "list") 'pa:position< 'pa:first-page<)))

(defun pa:sheet-numbers (items n / keep out)
  ;; The Аркуш number each of items gets, in their order: its own when it is 1..n and no earlier
  ;; item has it, otherwise the smallest number nobody keeps.
  (foreach r items
    (if (and (pa:get 'sheet r) (<= 1 (pa:get 'sheet r) n) (not (member (pa:get 'sheet r) keep)))
      (setq keep (cons (pa:get 'sheet r) keep) out (cons (pa:get 'sheet r) out))
      (setq out (cons nil out))))
  (setq out (reverse out))
  (mapcar '(lambda (x / k) (if x x (progn (setq k 1) (while (member k keep) (setq k (1+ k))) (setq keep (cons k keep)) k)))
          out))

(defun pa:sheet-cell-p (r)
  (and (vl-some '(lambda (c) (member (car c) '(sheet corner))) (pa:get 'counters r)) T))

(defun pa:total-cell-p (r)
  (and (assoc 'total (pa:get 'counters r)) T))

;;; ---- Layers -----------------------------------------------------------------
;;; A layer is off when its colour (62) is negative and frozen when bit 1 of its flags (70) is set.

(defun pa:layer (name) (entget (tblobjname "LAYER" name)))

(defun pa:layer-set (name color flags / d)
  (setq d (pa:layer name))
  (entmod (subst (cons 70 flags) (assoc 70 d) (subst (cons 62 color) (assoc 62 d) d))))

(defun pa:restore ()
  (foreach s fill-state (pa:layer-set (car s) (cadr s) (caddr s)))
  (setq fill-state nil)
  (foreach s sysvars (setvar (car s) (cdr s)))
  (setq sysvars nil))
