;;; ---- PDFLIST and PDFSPEC ----------------------------------------------------
;;; Paste an empty рамка with its title block: PDFLIST a лист (A3), PDFSPEC a специфікація (A4).
;;; The templates are the DWGs that make_templates.ps1 cuts out of a real drawing. A template is
;;; pasted exploded, so PDFNUM and PDFALL treat it like a рамка drawn by hand.
;;; Defines c:PDFLIST and c:PDFSPEC; tests/run.ps1 also drives pa:paste-start, pa:paste-run and
;;; pa:paste-cleanup, because a run ends with Esc, which would stop the test script too.

(defun pa:subst-marka (s marka / p)
  ;; s with the МАРКА that the template leaves in the name cell replaced by marka.
  (if (setq p (vl-string-search (pa:label "placeholder") s))
    (strcat (substr s 1 p) marka (substr s (+ p 1 (strlen (pa:label "placeholder")))))
    s))

(defun pa:ask-marka (/ s)
  ;; The марка exactly as typed, or the one used last when the user just presses Enter.
  (while (not s)
    (setq s (getstring (strcat "\n" (if *pdfall-marka*
                                      (pa:msg "paste.marka-last" (list "marka" *pdfall-marka*))
                                      (pa:msg "paste.marka" nil)))))
    (if (and (= s "") *pdfall-marka*) (setq s *pdfall-marka*))
    (cond
      ((not (pa:marka-p s))
       (princ (strcat "\n  " (pa:msg "paste.marka-bad" nil))) (setq s nil))
      ((pa:bad-char s)
       (princ (strcat "\n  " (pa:msg "paste.marka-char" (list "char" (pa:bad-char s))))) (setq s nil))))
  (setq *pdfall-marka* s))

(defun pa:paste-start ()
  (if (/= (getvar "CTAB") "Model")
    (progn (princ (strcat "\n" (pa:msg "paste.not-model" nil))) (exit)))
  (setq sysvars (list (cons "CMDECHO" (getvar "CMDECHO")) (cons "CLAYER" (getvar "CLAYER"))))
  (setvar "CMDECHO" 0)
  ;; the name cell is on layer 0, so a pasted рамка must not pick up a hidden or шар заливки layer
  (setvar "CLAYER" "0")
  ;; a рамка is found only when it is square to the world axes
  (if (= 0 (getvar "WORLDUCS"))
    (progn (princ (strcat "\n" (pa:msg "paste.not-world" nil))) (exit))))

(defun pa:acad-doc ()
  (vla-get-activedocument (vlax-get-acad-object)))

(defun pa:paste-cleanup ()
  ;; Also runs from *error*, where (command) may be refused; then the undo group is left to AutoCAD.
  (if undo-open
    (progn (vl-catch-all-apply '(lambda () (command "_.UNDO" "_E"))) (setq undo-open nil)))
  (pa:restore))

(defun pa:paste-one (file marka / path last0 r e d)
  ;; Pastes the template file where the user picks its lower-left corner and writes marka into
  ;; its name cell. Returns nil when the user pressed Esc instead.
  (setq path (strcat *pdfall-home* "\\" file))
  (if (not (findfile path))
    (progn (princ (strcat "\n! " (pa:msg "paste.no-template" (list "path" path)))) (exit)))
  (setq last0 (entlast))
  (command "_.UNDO" "_BE")
  (setq undo-open T)
  ;; Esc at the insertion point is how a run ends, so it is caught here instead of reaching *error*
  (setq r (vl-catch-all-apply '(lambda () (command "_.-INSERT" path "_S" 1.0 "_R" 0.0 pause))))
  (if (vl-catch-all-error-p r) (command))
  (cond
    ((or (vl-catch-all-error-p r) (equal (entlast) last0))
     (if (and (vl-catch-all-error-p r) (not (pa:cancelled-p (vl-catch-all-error-message r))))
       (princ (strcat "\n! " (pa:msg "paste.insert-failed" (list "file" file "msg" (vl-catch-all-error-message r))))))
     (command "_.UNDO" "_E")
     (setq undo-open nil)
     nil)
    (T
     (command "_.EXPLODE" (entlast))
     ;; The block definition is not needed once it is exploded, and a stale one would be reused next time.
     ;; ActiveX is not there in the console version of AutoCAD; the definition is then left alone.
     (vl-catch-all-apply
       '(lambda ()
          (vla-delete (vla-item (vla-get-blocks (pa:acad-doc)) (vl-filename-base file)))))
     (setq e (if last0 (entnext last0) (entnext)))
     (while e
       (setq d (entget e))
       (if (and (= (cdr (assoc 0 d)) "MTEXT") (vl-string-search (pa:label "placeholder") (cdr (assoc 1 d))))
         (entmod (subst (cons 1 (pa:subst-marka (cdr (assoc 1 d)) marka)) (assoc 1 d) d)))
       (setq e (entnext e)))
     (command "_.UNDO" "_E")
     (setq undo-open nil)
     T)))

(defun pa:paste-run (cmd marka pick / what)
  ;; Pastes рамки one after another; the user ends it with Esc (Enter is not accepted at the
  ;; insertion point prompt). (apply pick (list i)) gives the template file and a description
  ;; for the i-th рамка of this run, counting from 0. The caller's placed counts them.
  (setq placed 0)
  (while (progn
           (setq what (apply pick (list placed)))
           (princ (strcat "\n" (pa:msg "paste.pick" (list "cmd" cmd "what" (cdr what)))))
           (pa:paste-one (car what) marka))
    (setq placed (1+ placed))
    (princ (strcat "\n  " (pa:msg "paste.added-one" (list "what" (cdr what)))))))

(defun pa:paste-report (cmd marka)
  (princ (strcat "\n\n" (if (and placed (> placed 0))
                          (pa:msg "paste.added" (list "cmd" cmd "n" placed "marka" marka))
                          (pa:msg "paste.nothing" (list "cmd" cmd))))))

(defun pa:paste-failed (cmd msg)
  ;; What the *error* of PDFLIST and PDFSPEC does.
  (pa:paste-cleanup)
  (pa:report-crash cmd msg)
  (princ))

(defun c:PDFLIST (/ *error* sysvars fill-state undo-open marka placed)
  (defun *error* (msg) (pa:paste-failed "PDFLIST" msg))
  (pa:paste-start)
  (setq marka (pa:ask-marka))
  (pa:paste-run "PDFLIST" marka '(lambda (i) (cons "PDFALL_list.dwg" (pa:msg "paste.list" nil))))
  (pa:paste-cleanup)
  (pa:paste-report "PDFLIST" marka)
  (princ))

(defun c:PDFSPEC (/ *error* sysvars fill-state undo-open marka placed first next form dflt)
  (defun *error* (msg)
    (if (and placed (> placed 0)) (setq *pdfall-spec-marka* marka))
    (pa:paste-failed "PDFSPEC" msg))
  (pa:paste-start)
  (setq marka (pa:ask-marka)
        first (pa:msg "paste.first" nil)
        next (pa:msg "paste.next" nil)
        ;; the next специфікація after one of the same марка is usually a later аркуш of it
        dflt (if (= marka *pdfall-spec-marka*) next first))
  (initget (strcat first " " next))
  (setq form (getkword (strcat "\n" (pa:msg "paste.which-spec" (list "first" first "next" next "default" dflt)))))
  (if (null form) (setq form dflt))
  (pa:paste-run "PDFSPEC" marka
    '(lambda (i)
       (if (and (= i 0) (= form first))
         (cons "PDFALL_spec1.dwg" (pa:msg "paste.spec-first" nil))
         (cons "PDFALL_spec2.dwg" (pa:msg "paste.spec-next" nil)))))
  (if (> placed 0) (setq *pdfall-spec-marka* marka))
  (pa:paste-cleanup)
  (pa:paste-report "PDFSPEC" marka)
  (princ))
