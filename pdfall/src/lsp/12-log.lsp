;;; ---- Debug log --------------------------------------------------------------
;;; A detailed log of what the commands read and do, to find out why a drawing doesn't work on a
;;; colleague's PC. PDFDEBUG turns it on and off and opens it; while it is on, every command
;;; appends to %TEMP%\PDFALL-debug.log. Other files may call:
;;;   pa:log           append one line made of the items of a list (or of one string); does
;;;                    nothing while the log is off
;;;   pa:log-on-p      whether the log is on, to skip building costly lines
;;;   pa:log-start     a command's first line: PDFALL, AutoCAD, the drawing and the settings
;;;   pa:log-path
;;; Each line is written and the file closed at once, so a hard error that stops LISP still leaves
;;; every line before it. The log is in English, for developers; texts from the drawing are
;;; written as they are.
;;; Defines c:PDFDEBUG.

(defun pa:log-path () (strcat (getenv "TEMP") "\\PDFALL-debug.log"))

;; Read from the Debug setting when PDFALL loads and when PDFDEBUG changes it, so that pa:log costs
;; nothing while the log is off.
(setq *pa-log-on* nil)

(defun pa:log-on-p () *pa-log-on*)

(defun pa:log-open (/ f)
  ;; UTF-8 where AutoCAD can write it (2021 and later), else the system code page.
  (setq f (vl-catch-all-apply 'open (list (pa:log-path) "a" "utf8")))
  (if (or (vl-catch-all-error-p f) (null f)) (open (pa:log-path) "a") f))

(defun pa:log-time (/ c n)
  ;; The time of day as hh:mm:ss, from CDATE (YYYYMMDD.HHMMSSmsec).
  (setq c (getvar "CDATE")
        n (fix (+ 0.5 (* 1000000.0 (- c (fix c))))))
  (strcat (pa:pad (/ n 10000)) ":" (pa:pad (rem (/ n 100) 100)) ":" (pa:pad (rem n 100))))

(defun pa:log-item (x)
  (cond ((= (type x) 'STR) x) ((= (type x) 'REAL) (rtos x 2 2)) ((vl-prin1-to-string x))))

(defun pa:log (items / f s)
  (if *pa-log-on*
    (progn
      (setq s (if (= (type items) 'STR) items (apply 'strcat (mapcar '(lambda (x) (strcat (pa:log-item x) " ")) items))))
      (if (setq f (pa:log-open))
        (progn (write-line (strcat (pa:log-time) " " (vl-string-right-trim " " s)) f) (close f)))))
  nil)

(defun pa:log-start (cmd)
  ;; A command's first lines, and a reminder in the command line that the log is on.
  (if *pa-log-on*
    (progn
      (pa:log "")
      (pa:log (list "====" cmd "| PDFALL" *pdfall-version* "| AutoCAD" (getvar "ACADVER") (getvar "LOCALE")
                    "| syscodepage" (getvar "SYSCODEPAGE") "dwgcodepage" (getvar "DWGCODEPAGE")))
      (pa:log (list "drawing" (strcat (getvar "DWGPREFIX") (getvar "DWGNAME")) "CTAB" (getvar "CTAB")
                    "WORLDUCS" (getvar "WORLDUCS") "INSUNITS" (getvar "INSUNITS")))
      (pa:log (list "home" *pdfall-home*))
      (pa:log (cons "settings" (mapcar '(lambda (s) (cons (car s) (pa:setting (car s)))) *pa-setting-defaults*)))
      (princ (strcat "\n" (pa:msg "log.on" (list "path" (pa:log-path))))))))

(defun c:PDFDEBUG (/ on off show dflt k)
  (setq on (pa:msg "log.turn-on" nil) off (pa:msg "log.turn-off" nil) show (pa:msg "log.show" nil)
        dflt (if *pa-log-on* show on))
  (initget (strcat on " " off " " show))
  (setq k (getkword (strcat "\n" (pa:msg "log.ask" (list "on" on "off" off "show" show "default" dflt)))))
  (if (null k) (setq k dflt))
  (cond
    ((= k on)
     (vl-file-delete (pa:log-path))
     (pa:set-setting "Debug" "1")
     (setq *pa-log-on* T)
     (pa:log-start "PDFDEBUG")
     (princ (strcat "\n" (pa:msg "log.started" (list "path" (pa:log-path))))))
    ((= k off)
     (pa:log "log turned off")
     (pa:set-setting "Debug" "0")
     (setq *pa-log-on* nil)
     (princ (strcat "\n" (pa:msg "log.stopped" (list "path" (pa:log-path))))))
    ((findfile (pa:log-path)) (startapp "notepad.exe" (strcat "\"" (pa:log-path) "\"")))
    (T (princ (strcat "\n" (pa:msg "log.none" nil)))))
  (princ))
