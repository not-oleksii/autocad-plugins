;;; ---- Text -------------------------------------------------------------------
;;; String helpers that every plugin file may use:
;;;   @:msg @:label @:file  the texts of messages.json
;;;   @:fill          {name}s of any text filled in, as @:msg does
;;;   @:split @:words @:digit-p @:letter-p @:digits-p @:lower @:pad @:bad-char @:file-safe
;;;
;;; build.bat writes messages.json (common and the plugin's) into *@-messages*, *@-labels* and
;;; *@-files* right after the plugin's 00-settings.lsp, and fails if the code uses a key or {name}
;;; that messages.json doesn't have, or a Ukrainian string outside 00-settings.lsp. So every key is a
;;; literal string, and @:msg gets its values as a literal (list "name" value ...).
;;; Shared by every plugin (common/build_lisp.py gives each its own copy under its own prefix).

(defun @:msg (key args)
  ;; The message key with each {name} replaced by its value from args, (name value name value ...).
  ;; Numbers are written as integers.
  (@:fill (cond ((cdr (assoc key *@-messages*))) ((strcat "{" key "}"))) args))

(defun @:fill (s args / k v p)
  ;; s with each {name} replaced by its value from args, as for @:msg.
  (while args
    (setq k (strcat "{" (car args) "}")
          v (cadr args)
          v (cond ((= (type v) 'INT) (itoa v)) ((numberp v) (rtos v 2 0)) (v))
          args (cddr args)
          p 0)
    ;; search on after each value, so a value that holds the {name} itself can't loop
    (while (setq p (vl-string-search k s p))
      (setq s (strcat (substr s 1 p) v (substr s (+ p 1 (strlen k))))
            p (+ p (strlen v)))))
  s)

(defun @:label (key) (cdr (assoc key *@-labels*)))

(defun @:file (key) (cdr (assoc key *@-files*)))

(defun @:lower (s)
  ;; s in lower case; strcase alone leaves Cyrillic letters as they are.
  (vl-string-translate (@:label "upper") (@:label "lower") (strcase s T)))

(defun @:pad (n)
  ;; A sheet number as it is written in a file name: at least two digits.
  (if (< n 10) (strcat "0" (itoa n)) (itoa n)))

(defun @:bad-char (s)
  ;; The first character of s that Windows doesn't allow in a file name, or nil.
  (vl-some '(lambda (c) (if (vl-string-position c s) (chr c)))
           (vl-string->list "\\/:*?\"<>|")))

(defun @:file-safe (s)
  ;; s with every character Windows doesn't allow in a file name replaced by _.
  (vl-string-translate "\\/:*?\"<>|" "_________" s))

(defun @:split (s sep / out p)
  (while (setq p (vl-string-search sep s))
    (setq out (cons (substr s 1 p) out)
          s (substr s (+ p 1 (strlen sep)))))
  (reverse (cons s out)))

(defun @:words (s)
  (vl-remove "" (@:split (vl-string-translate "\t\n" "  " s) " ")))

(defun @:digit-p (c) (<= 48 c 57))

(defun @:letter-p (c) (and (or (<= 65 c 90) (<= 97 c 122) (>= c 192)) (/= c 8470)))

(defun @:digits-p (s)
  (and s (/= s "") (vl-every '@:digit-p (vl-string->list s))))
