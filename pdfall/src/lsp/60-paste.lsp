;;; ---- PDFLIST and PDFSPEC ----------------------------------------------------
;;; Paste an empty рамка with its title block: PDFLIST a лист (A3), PDFSPEC a специфікація (A4).
;;; The templates are the DWGs that make_templates.ps1 cuts out of a real drawing. A template is
;;; pasted exploded, so PDFNUM and PDFALL treat it like a рамка drawn by hand.
;;; Defines c:PDFLIST and c:PDFSPEC; tests/run.ps1 also drives pa:paste-start, pa:paste-run and
;;; pa:paste-cleanup, because a run ends with Esc, which would stop the test script too.

(defun pa:subst-marka (s marka / p)
  ;; s with the МАРКА that the template leaves in the name cell replaced by marka.
  (if (setq p (vl-string-search "МАРКА" s))
    (strcat (substr s 1 p) marka (substr s (+ p 6)))
    s))

(defun pa:ask-marka (/ s)
  ;; The марка exactly as typed, or the one used last when the user just presses Enter.
  (while (not s)
    (setq s (getstring (strcat "\nМарка" (if *pdfall-marka* (strcat " <" *pdfall-marka* ">") "") ": ")))
    (if (and (= s "") *pdfall-marka*) (setq s *pdfall-marka*))
    (if (not (pa:marka-p s))
      (progn (princ "\n  Марка має містити літеру й цифру, наприклад 1ЧП.") (setq s nil))))
  (setq *pdfall-marka* s))

(defun pa:paste-start ()
  (if (/= (getvar "CTAB") "Model")
    (progn (princ "\nPDFALL: рамки вставляються в Model space. Перейдіть на вкладку Model.") (exit)))
  (setq sysvars (list (cons "CMDECHO" (getvar "CMDECHO")) (cons "CLAYER" (getvar "CLAYER"))))
  (setvar "CMDECHO" 0)
  ;; the name cell is on layer 0, so a pasted рамка must not pick up a hidden or шар заливки layer
  (setvar "CLAYER" "0")
  ;; a рамка is found only when it is square to the world axes
  (if (= 0 (getvar "WORLDUCS"))
    (progn (princ "\nPDFALL: рамки вставляються у світовій системі координат. Введіть UCS, потім W, і спробуйте ще раз.") (exit))))

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
    (progn (princ (strcat "\n! " path " не знайдено. Запустіть install.bat ще раз.")) (exit)))
  (setq last0 (entlast))
  (command "_.UNDO" "_BE")
  (setq undo-open T)
  ;; Esc at the insertion point is how a run ends, so it is caught here instead of reaching *error*
  (setq r (vl-catch-all-apply '(lambda () (command "_.-INSERT" path "_S" 1.0 "_R" 0.0 pause))))
  (if (vl-catch-all-error-p r) (command))
  (cond
    ((or (vl-catch-all-error-p r) (equal (entlast) last0))
     (if (and (vl-catch-all-error-p r) (not (wcmatch (strcase (vl-catch-all-error-message r)) "*CANCEL*")))
       (princ (strcat "\n! Не вдалося вставити " file ": " (vl-catch-all-error-message r))))
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
       (if (and (= (cdr (assoc 0 d)) "MTEXT") (vl-string-search "МАРКА" (cdr (assoc 1 d))))
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
           (princ (strcat "\n" cmd ": " (cdr what) ". Вкажіть лівий нижній кут рамки або натисніть Esc, щоб закінчити."))
           (pa:paste-one (car what) marka))
    (setq placed (1+ placed))
    (princ (strcat "\n  + додано: " (cdr what)))))

(defun pa:paste-report (cmd marka)
  (princ (if (and placed (> placed 0))
           (strcat "\n\n" cmd ": додано рамок: " (itoa placed) " (марка " marka
                   "). Номери Аркуш/Аркушів заповнить PDFNUM.")
           (strcat "\n\n" cmd ": нічого не додано."))))

(defun pa:paste-failed (cmd msg)
  ;; What the *error* of PDFLIST and PDFSPEC does.
  (pa:paste-cleanup)
  (if (not (wcmatch (strcase msg) "*CANCEL*,*QUIT*,*EXIT*"))
    (princ (strcat "\nПомилка " cmd ": " msg)))
  (princ))

(defun c:PDFLIST (/ *error* sysvars fill-state undo-open marka placed)
  (defun *error* (msg) (pa:paste-failed "PDFLIST" msg))
  (pa:paste-start)
  (setq marka (pa:ask-marka))
  (pa:paste-run "PDFLIST" marka '(lambda (i) (cons "PDFALL_list.dwg" "лист (A3)")))
  (pa:paste-cleanup)
  (pa:paste-report "PDFLIST" marka)
  (princ))

(defun c:PDFSPEC (/ *error* sysvars fill-state undo-open marka placed form dflt)
  (defun *error* (msg)
    (if (and placed (> placed 0)) (setq *pdfall-spec-marka* marka))
    (pa:paste-failed "PDFSPEC" msg))
  (pa:paste-start)
  (setq marka (pa:ask-marka)
        ;; the next специфікація after one of the same марка is usually a later аркуш of it
        dflt (if (= marka *pdfall-spec-marka*) "Наступний" "Перший"))
  (initget "Перший Наступний")
  (setq form (getkword (strcat "\nАркуш специфікації [Перший/Наступний] <" dflt ">: ")))
  (if (null form) (setq form dflt))
  (pa:paste-run "PDFSPEC" marka
    '(lambda (i)
       (if (and (= i 0) (= form "Перший"))
         (cons "PDFALL_spec1.dwg" "специфікація, перший аркуш")
         (cons "PDFALL_spec2.dwg" "специфікація, наступний аркуш"))))
  (if (> placed 0) (setq *pdfall-spec-marka* marka))
  (pa:paste-cleanup)
  (pa:paste-report "PDFSPEC" marka)
  (princ))
