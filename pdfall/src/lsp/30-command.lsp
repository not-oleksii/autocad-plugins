;;; ---- Command state ----------------------------------------------------------
;;; What the commands share. Other files may call:
;;;   pa:err pa:warn     add to the command's errors and warnings
;;;   pa:where pa:problem  how a рамка, and a problem found on one, read in a message
;;;   pa:kind-name pa:kind-of pa:kind-pl  a record's kind as it reads in a message
;;;   pa:report-errors pa:report-warnings pa:report-crash
;;;   pa:cancelled-p     whether an error message means Esc, in any AutoCAD language
;;;   pa:layer pa:layer-set pa:restore  put layers and system variables back
;;; A command that uses them declares errors, warnings, fill-state and sysvars among its locals.

(defun pa:where (r)
  (pa:msg "where" (list "kind" (pa:kind-of (pa:get 'kind r))
                        "x" (rtos (car (pa:get 'll r)) 2 0) "y" (rtos (cadr (pa:get 'll r)) 2 0))))

(defun pa:problem (e)
  ;; An error (message . record) as it is listed: the message, then where the рамка is.
  (strcat (car e) (if (cdr e) (strcat "  (" (pa:where (cdr e)) ")") "")))

;; A kind as it reads on its own ("лист"), after "рамка" (of one: "листа") and after "рамок" (of
;; many: "листів").
(defun pa:kind-name (kind) (if (= kind "list") (pa:msg "kind.list" nil) (pa:msg "kind.spec" nil)))
(defun pa:kind-of (kind) (if (= kind "list") (pa:msg "kind.list.of" nil) (pa:msg "kind.spec.of" nil)))
(defun pa:kind-pl (kind) (if (= kind "list") (pa:msg "kind.list.pl" nil) (pa:msg "kind.spec.pl" nil)))

(defun pa:err (msg r) (setq errors (cons (cons msg r) errors)))
(defun pa:warn (msg) (setq warnings (cons msg warnings)))

(defun pa:report-errors (header / e)
  (princ (strcat "\n\nPDFALL: " header))
  (foreach e (reverse errors)
    (princ (strcat "\n  X " (pa:problem e))))
  (if (setq e (vl-some 'cdr (reverse errors)))
    (progn
      (command "_.ZOOM" "_W" (trans (pa:get 'll e) 0 1) (trans (pa:get 'ur e) 0 1))
      (princ (strcat "\n  " (pa:msg "shown-first" nil))))))

(defun pa:report-warnings ()
  (if warnings
    (progn
      (princ (strcat "\n\n" (pa:msg "warnings" nil)))
      (foreach w (reverse warnings) (princ (strcat "\n  ! " w))))))

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
  (if (not (pa:cancelled-p msg))
    (princ (strcat "\n" (pa:msg "command-error" (list "cmd" cmd "msg" msg))))))

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
