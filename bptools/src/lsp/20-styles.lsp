;;; ---- Стиль оформлення -------------------------------------------------------
;;; Brings the стиль оформлення into the drawing and puts back what someone changed in it
;;; (docs/adr/0001): the text styles of *bptools-styles*, the dimension style and the multileader
;;; style of позиційні номери named in 00-settings.lsp, and the «Написи» layer, which is also
;;; turned on, thawed and unlocked. Only these, found by their names; the drawing's other styles
;;; and texts are left as they are. Other files may call:
;;;   bp:ensure-styles   makes or restores them all; returns the names it made or restored

(defun bp:put (pairs d)
  ;; d with each (code . value) of pairs in place of the pair of its code, or added at the end.
  (foreach p pairs (setq d (if (assoc (car p) d) (subst p (assoc (car p) d) d) (append d (list p)))))
  d)

(defun bp:same (a b)
  (cond ((and (numberp a) (numberp b)) (equal a b 1e-6))
        ((and (= (type a) 'STR) (= (type b) 'STR)) (= (strcase a) (strcase b)))
        ((equal a b))))

(defun bp:differs (pairs d)
  ;; Whether d lacks one of pairs or has another value for its code.
  (vl-some '(lambda (p / q) (setq q (assoc (car p) d)) (not (and q (bp:same (cdr q) (cdr p))))) pairs))

(defun bp:strip (d codes)
  ;; d without the pairs of codes.
  (vl-remove-if '(lambda (p) (member (car p) codes)) d))

(defun bp:ensure-text-style (name height / want e)
  (setq want (list (cons 40 height) (cons 41 1.0) (cons 50 0.0) (cons 71 0) (cons 3 *bptools-font*) (cons 4 "")))
  (cond ((null (setq e (tblobjname "STYLE" name)))
         (entmake (append (list '(0 . "STYLE") '(100 . "AcDbSymbolTableRecord") '(100 . "AcDbTextStyleTableRecord")
                                (cons 2 name) '(70 . 0) (cons 42 height))
                          want))
         name)
        ((bp:differs want (setq e (entget e)))
         (entmod (bp:put want e))
         name)))

(defun bp:ensure-layer (/ e want)
  ;; On, thawed and unlocked: a label made on a layer that is off would vanish at once.
  (setq want '((70 . 0)))
  (cond ((null (setq e (tblobjname "LAYER" *bptools-layer*)))
         (entmake (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord") '(100 . "AcDbLayerTableRecord")
                        (cons 2 *bptools-layer*) '(70 . 0) '(62 . 7) '(6 . "Continuous")))
         *bptools-layer*)
        ((or (bp:differs want (setq e (entget e))) (minusp (cdr (assoc 62 e))))
         (entmod (bp:put (list '(70 . 0) (cons 62 (abs (cdr (assoc 62 e))))) e))
         *bptools-layer*)))

(defun bp:ensure-dim-style (/ want e base)
  ;; ISO-25, or the current dimension style, with the «Розміри» text at its height.
  (setq want (list (cons 140 (bp:kind-height "dim")) (cons 340 (tblobjname "STYLE" (bp:kind-style "dim")))))
  (cond ((null (setq e (tblobjname "DIMSTYLE" *bptools-dim-style*)))
         (setq base (entget (cond ((tblobjname "DIMSTYLE" "ISO-25")) ((tblobjname "DIMSTYLE" (getvar "DIMSTYLE"))))))
         (entmake (bp:put want (append (list '(0 . "DIMSTYLE") '(100 . "AcDbSymbolTableRecord") '(100 . "AcDbDimStyleTableRecord")
                                             (cons 2 *bptools-dim-style*) '(70 . 0))
                                       (bp:strip base '(-1 0 2 5 70 100 105 330)))))
         *bptools-dim-style*)
        ((bp:differs want (setq e (entget e)))
         (entmod (bp:put want e))
         *bptools-dim-style*)))

(defun bp:arrow (name / old)
  ;; The block record of AutoCAD's arrowhead name, such as _DOT, loading it into the drawing first:
  ;; setting DIMBLK is how AutoCAD makes an arrowhead's block.
  (if (not (tblobjname "BLOCK" name))
    (progn
      (setq old (getvar "DIMBLK"))
      (setvar "DIMBLK" name)
      (setvar "DIMBLK" (if (= old "") "." old))))
  (cdr (assoc 330 (entget (tblobjname "BLOCK" name)))))

(defun bp:ensure-pos-style (/ dict want e std new)
  ;; Made from the drawing's Standard multileader style: the number in the «Позиційний номер» text
  ;; style on a horizontal shelf (attached at its underline), a dot at the part, not annotative.
  (if (setq dict (cdr (assoc -1 (dictsearch (namedobjdict) "ACAD_MLEADERSTYLE"))))
    (progn
      (setq want (list '(170 . 2) '(173 . 1) '(290 . 1) '(42 . 0.5) '(291 . 1) '(43 . 1.0)
                       (cons 341 (bp:arrow "_DOT")) '(44 . 1.0)
                       (cons 342 (tblobjname "STYLE" (bp:kind-style "pos")))
                       '(174 . 5) '(178 . 5) '(175 . 1) (cons 45 (bp:kind-height "pos")) '(292 . 0) '(296 . 0) '(271 . 0)))
      (cond ((setq e (dictsearch dict *bptools-pos-style*))
             (if (bp:differs want e) (progn (entmod (bp:put want e)) *bptools-pos-style*)))
            ((setq std (dictsearch dict "Standard"))
             (setq new (entmakex (bp:put (cons '(3 . "") want)
                                         (append '((0 . "MLEADERSTYLE") (100 . "AcDbMLeaderStyle"))
                                                 (bp:strip std '(-1 0 5 100 102 330))))))
             (if new (progn (dictadd dict *bptools-pos-style* new) *bptools-pos-style*)))))))

(defun bp:ensure-styles (/ done)
  (foreach s *bptools-styles*
    (if (bp:ensure-text-style (cadr s) (caddr s)) (setq done (cons (cadr s) done))))
  (foreach x (list (bp:ensure-layer) (bp:ensure-dim-style) (bp:ensure-pos-style))
    (if x (setq done (cons x done))))
  (bp:log (cons "styles: made or restored" (reverse done)))
  (reverse done))
