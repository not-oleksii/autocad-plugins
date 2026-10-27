;;; ---- Debug log --------------------------------------------------------------
;;; A detailed log of what the commands read and do, to find out why a drawing doesn't work on a
;;; colleague's PC. @@DEBUG@@ turns it on and off and opens it; while it is on, every command
;;; appends to %TEMP%\@@NAME@@-debug.log. Other files may call:
;;;   @:log           append one line made of the items of a list (or of one string); does
;;;                    nothing while the log is off
;;;   @:log-on-p      whether the log is on, to skip building costly lines
;;;   @:log-start     a command's first line: @@NAME@@, AutoCAD, the drawing and the settings
;;;   @:log-path
;;; Each line is written and the file closed at once, so a hard error that stops LISP still leaves
;;; every line before it. The log is in English, for developers; texts from the drawing are
;;; written as they are.
;;; Defines c:@@DEBUG@@. The plugin's *@-setting-defaults* holds ("Debug" . "0") (14-settings.lsp).

(defun @:log-path () (strcat (getenv "TEMP") "\\@@NAME@@-debug.log"))

;; Read from the Debug setting when @@NAME@@ loads and when @@DEBUG@@ changes it, so that @:log costs
;; nothing while the log is off.
(setq *@-log-on* nil)

(defun @:log-on-p () *@-log-on*)

(defun @:log-open (/ f)
  ;; UTF-8 where AutoCAD can write it (2021 and later), else the system code page.
  (setq f (vl-catch-all-apply 'open (list (@:log-path) "a" "utf8")))
  (if (or (vl-catch-all-error-p f) (null f)) (open (@:log-path) "a") f))

(defun @:log-time (/ c n)
  ;; The time of day as hh:mm:ss, from CDATE (YYYYMMDD.HHMMSSmsec).
  (setq c (getvar "CDATE")
        n (fix (+ 0.5 (* 1000000.0 (- c (fix c))))))
  (strcat (@:pad (/ n 10000)) ":" (@:pad (rem (/ n 100) 100)) ":" (@:pad (rem n 100))))

(defun @:log-item (x)
  (cond ((= (type x) 'STR) x) ((= (type x) 'REAL) (rtos x 2 2)) ((vl-prin1-to-string x))))

(defun @:log (items / f s)
  (if *@-log-on*
    (progn
      (setq s (if (= (type items) 'STR) items (apply 'strcat (mapcar '(lambda (x) (strcat (@:log-item x) " ")) items))))
      (if (setq f (@:log-open))
        (progn (write-line (strcat (@:log-time) " " (vl-string-right-trim " " s)) f) (close f)))))
  nil)

(defun @:log-start (cmd)
  ;; A command's first lines, and a reminder in the command line that the log is on.
  (if *@-log-on*
    (progn
      (@:log "")
      (@:log (list "====" cmd "| @@NAME@@" *@@-version* "| AutoCAD" (getvar "ACADVER") (getvar "LOCALE")
                    "| syscodepage" (getvar "SYSCODEPAGE") "dwgcodepage" (getvar "DWGCODEPAGE")))
      (@:log (list "drawing" (strcat (getvar "DWGPREFIX") (getvar "DWGNAME")) "CTAB" (getvar "CTAB")
                    "WORLDUCS" (getvar "WORLDUCS") "INSUNITS" (getvar "INSUNITS")))
      (@:log (list "home" *@@-home*))
      (@:log (cons "settings" (mapcar '(lambda (s) (cons (car s) (@:setting (car s)))) *@-setting-defaults*)))
      (princ (strcat "\n" (@:msg "log.on" (list "path" (@:log-path) "command" "@@DEBUG@@")))))))

(defun c:@@DEBUG@@ (/ on off show dflt k)
  (setq on (@:msg "log.turn-on" nil) off (@:msg "log.turn-off" nil) show (@:msg "log.show" nil)
        dflt (if *@-log-on* show on))
  (initget (strcat on " " off " " show))
  (setq k (getkword (strcat "\n" (@:msg "log.ask" (list "name" "@@NAME@@" "on" on "off" off "show" show "default" dflt)))))
  (if (null k) (setq k dflt))
  (cond
    ((= k on)
     (vl-file-delete (@:log-path))
     (@:set-setting "Debug" "1")
     (setq *@-log-on* T)
     (@:log-start "@@DEBUG@@")
     (princ (strcat "\n" (@:msg "log.started" (list "path" (@:log-path) "command" "@@DEBUG@@")))))
    ((= k off)
     (@:log "log turned off")
     (@:set-setting "Debug" "0")
     (setq *@-log-on* nil)
     (princ (strcat "\n" (@:msg "log.stopped" (list "path" (@:log-path) "command" "@@DEBUG@@")))))
    ((findfile (@:log-path)) (startapp "notepad.exe" (strcat "\"" (@:log-path) "\"")))
    (T (princ (strcat "\n" (@:msg "log.none" (list "command" "@@DEBUG@@"))))))
  (princ))
