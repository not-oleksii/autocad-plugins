;;; ---- Command state ----------------------------------------------------------
;;; What the commands share. Other files may call:
;;;   pa:err pa:warn     add to the command's errors and warnings
;;;   pa:where pa:kind-of pa:kind-pl  how a рамка and its kind read in a message
;;;   pa:report-errors pa:report-warnings
;;;   pa:layer pa:layer-set pa:restore  put layers and system variables back
;;; A command that uses them declares errors, warnings, fill-state and sysvars among its locals.

(defun pa:where (r)
  (strcat "рамка " (pa:kind-of (pa:get 'kind r)) " у точці "
          (rtos (car (pa:get 'll r)) 2 0) "," (rtos (cadr (pa:get 'll r)) 2 0)))

;; "лист" and "специфікація" as they read after "рамка" (of one) and "рамок/рамки" (of many).
(defun pa:kind-of (kind) (if (= kind "лист") "листа" "специфікації"))
(defun pa:kind-pl (kind) (if (= kind "лист") "листів" "специфікацій"))

(defun pa:err (msg r) (setq errors (cons (cons msg r) errors)))
(defun pa:warn (msg) (setq warnings (cons msg warnings)))

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
