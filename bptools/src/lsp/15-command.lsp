;;; ---- Commands ---------------------------------------------------------------
;;; What every BPTOOLS command shares. Other files may call:
;;;   bp:run          runs a command: brings in the стиль оформлення, makes the whole command one
;;;                   undo step, puts back the system variables it changed, and says nothing on Esc
;;;   bp:set-var      sets a system variable until the command ends
;;;   bp:kind-style bp:kind-height  the text style and height of a kind of label (*bptools-styles*)
;;;   bp:wcs          a point the user picked, in world coordinates
;;; Settings (common\lsp\14-settings.lsp): Debug; Name, the назва роз'єму typed or pasted last; Part,
;;; View, Rotation and Scale, what BPPART pasted last.

(setq *bp-setting-defaults* '(("Debug" . "0") ("Name" . "") ("Part" . "") ("View" . "front") ("Rotation" . "0") ("Scale" . "1")))
(setq *bp-log-on* (= (bp:setting "Debug") "1"))

(defun bp:cancelled-p (msg)
  ;; Whether an error message means the user pressed Esc, in any AutoCAD language.
  (or (wcmatch (strcase msg) "*CANCEL*,*QUIT*,*EXIT*") (wcmatch msg *bptools-cancel-words*)))

(defun bp:set-var (name value)
  (if (not (assoc name sysvars)) (setq sysvars (cons (cons name (getvar name)) sysvars)))
  (setvar name value))

(defun bp:restore-vars ()
  (foreach s sysvars (setvar (car s) (cdr s)))
  (setq sysvars nil))

(defun bp:run (cmd body / *error* sysvars)
  ;; body is the function that does the command's work.
  (defun *error* (msg)
    (command-s "_.UNDO" "_E")
    (bp:restore-vars)
    (bp:log (list cmd "stopped:" msg))
    (if (not (bp:cancelled-p msg))
      (princ (strcat "\n" (bp:msg "command-error" (list "cmd" cmd "msg" msg)))))
    (princ))
  (bp:log-start cmd)
  (bp:set-var "CMDECHO" 0)
  (command "_.UNDO" "_BE")
  (bp:ensure-styles)
  (apply body nil)
  (command "_.UNDO" "_E")
  (bp:restore-vars)
  (princ))

(defun bp:kind-style (kind) (cadr (assoc kind *bptools-styles*)))
(defun bp:kind-height (kind) (caddr (assoc kind *bptools-styles*)))

(defun bp:wcs (p) (trans p 1 0))
