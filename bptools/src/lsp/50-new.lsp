;;; ---- BPNEW ------------------------------------------------------------------
;;; Opens a new drawing from BPTOOLS.dwt, which build.bat makes (src\make_template.ps1): the
;;; стиль оформлення with the «Розміри» dimension style, the «Позиційний номер» multileader style
;;; and the «Примітка» text style current, the «Написи» layer, millimetres. A drawing started
;;; otherwise gets the same styles from the first BPTOOLS command anyway. Defines c:BPNEW.

(defun bp:template () (strcat *bptools-home* "\\BPTOOLS.dwt"))

(defun c:BPNEW (/ acad)
  (cond ((not (findfile (bp:template)))
         (princ (strcat "\n" (bp:msg "new.no-template" (list "file" (bp:template))))))
        ((setq acad (bp:acad))
         (vla-activate (vla-add (vla-get-documents acad) (bp:template))))
        (T (princ (strcat "\n" (bp:msg "new.no-documents" nil)))))
  (princ))
