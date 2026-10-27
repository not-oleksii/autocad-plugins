;;; ---- Settings ---------------------------------------------------------------
;;; A plugin's settings, kept per Windows user with setenv (as @@NAME@@_<key>), so an update keeps
;;; them. Other files may call:
;;;   @:setting @:set-setting  read and write one setting
;;; The plugin defines *@-setting-defaults*, ((key . default) ...), which must hold ("Debug" . "0")
;;; for the debug log (12-log.lsp), and then sets *@-log-on* from it:
;;;   (setq *@-log-on* (= (@:setting "Debug") "1"))

(defun @:setting (key / v)
  (setq v (getenv (strcat "@@NAME@@_" key)))
  (if (and v (/= v "")) v (cdr (assoc key *@-setting-defaults*))))

(defun @:set-setting (key value)
  ;; An empty value would read back as the default, so it is stored as a single space.
  (setenv (strcat "@@NAME@@_" key) (if (= value "") " " value)))
