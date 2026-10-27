;;; ---- Labels -----------------------------------------------------------------
;;; The commands that place labels, each in the style of its kind, on the «Написи» layer, centred
;;; on the point clicked (so a label lines up with its pin, wire or part), and BPSTYLE, which gives
;;; texts already drawn the style of a kind. Defines c:BPPOS, c:BPPIN, c:BPWIRE, c:BPNAME,
;;; c:BPVIEW, c:BPFIG and c:BPSTYLE. tests/run.ps1 also calls:
;;;   bp:add-text (kind s pt)        a text of a kind, centred at pt (world coordinates)
;;;   bp:add-pos (n arrow shelf)     a позиційний номер from the part at arrow to its shelf (UCS points)
;;;   bp:restyle (ents kind)         gives texts the style of a kind; returns how many

(defun bp:add-text (kind s pt)
  (entmakex (list '(0 . "TEXT") '(100 . "AcDbEntity") (cons 8 *bptools-layer*) '(100 . "AcDbText")
                  (cons 10 pt) (cons 40 (bp:kind-height kind)) (cons 1 s) '(50 . 0.0) '(41 . 1.0)
                  (cons 7 (bp:kind-style kind)) '(72 . 1) (cons 11 pt) '(100 . "AcDbText") '(73 . 2))))

(defun bp:acad (/ a)
  ;; AutoCAD's ActiveX object, or nil in the console AutoCAD, which has none.
  (setq a (vl-catch-all-apply 'vlax-get-acad-object nil))
  (if (not (vl-catch-all-error-p a)) a))

(defun bp:add-pos (n arrow shelf / acad pts ml)
  ;; A multileader of the «Позиційний номер» style. With ActiveX it is made directly, since MLEADER
  ;; asks for its points in the order the user last chose (arrowhead, landing or content first);
  ;; the console AutoCAD has no ActiveX but asks arrowhead first, and its MLEADER takes one line of
  ;; text and ends (one more Enter would repeat the command).
  (bp:set-var "CMLEADERSTYLE" *bptools-pos-style*)
  (bp:set-var "CLAYER" *bptools-layer*)
  (if (setq acad (bp:acad))
    (progn
      (setq pts (vlax-make-safearray vlax-vbdouble '(0 . 5)))
      (vlax-safearray-fill pts (append (bp:wcs arrow) (bp:wcs shelf)))
      (setq ml (vla-addmleader (vla-get-modelspace (vla-get-activedocument acad)) (vlax-make-variant pts) 0))
      (vla-put-textstring ml n)
      (vla-put-layer ml *bptools-layer*)
      (vlax-vla-object->ename ml))
    (progn
      (command "_.MLEADER" "_non" arrow "_non" shelf n)
      (entlast))))

(defun bp:restyle (ents kind / n)
  ;; TEXT and MTEXT get the kind's style and height and go on the «Написи» layer; a TEXT's width
  ;; factor goes back to 1. Other entities are left alone.
  (setq n 0)
  (foreach e ents
    (setq e (entget e))
    (if (member (cdr (assoc 0 e)) '("TEXT" "MTEXT"))
      (progn
        (entmod (bp:put (append (list (cons 7 (bp:kind-style kind)) (cons 40 (bp:kind-height kind)) (cons 8 *bptools-layer*))
                                (if (= (cdr (assoc 0 e)) "TEXT") '((41 . 1.0))))
                        e))
        (setq n (1+ n)))))
  n)

(defun bp:place (kind s / p)
  ;; Asks where s goes and puts it there. Returns the entity, or nil on Enter.
  (if (setq p (getpoint (strcat "\n" (bp:msg "label.where" (list "text" s)))))
    (bp:add-text kind s (bp:wcs p))))

;;; ---- BPPOS ------------------------------------------------------------------

(defun bp:pos-command (/ a n s b)
  (while (setq a (getpoint (strcat "\n" (bp:msg "pos.arrow" nil))))
    (setq n (itoa (bp:next-pos (bp:wcs a)))
          s (getstring (strcat "\n" (bp:msg "pos.number" (list "n" n)))))
    (if (= s "") (setq s n))
    (if (setq b (getpoint a (strcat "\n" (bp:msg "pos.shelf" (list "n" s)))))
      (bp:add-pos s a b))))

(defun c:BPPOS () (bp:run "BPPOS" 'bp:pos-command))

;;; ---- BPPIN ------------------------------------------------------------------

(defun bp:pin-command (/ n kind p kw-number kw-size)
  ;; One number per click, counting on; Номер sets the next number, Малий and Звичайний switch
  ;; between the 2.5 and the 1.8 style (for the faces of small роз'єми).
  (setq n 1 kind "pin" kw-number (bp:msg "pin.kw-number" nil))
  (while (progn
           (setq kw-size (if (= kind "pin") (bp:msg "pin.kw-small" nil) (bp:msg "pin.kw-normal" nil)))
           (initget (strcat kw-number " " kw-size))
           (setq p (getpoint (strcat "\n" (bp:msg "pin.where" (list "n" n "number" kw-number "size" kw-size))))))
    (cond ((= p kw-number)
           (initget 6)
           (setq n (cond ((getint (strcat "\n" (bp:msg "pin.ask-number" (list "n" n))))) (n))))
          ((= p kw-size) (setq kind (if (= kind "pin") "pin-small" "pin")))
          (T (bp:add-text kind (itoa n) (bp:wcs p)) (setq n (1+ n))))))

(defun c:BPPIN () (bp:run "BPPIN" 'bp:pin-command))

;;; ---- BPWIRE -----------------------------------------------------------------

(setq *bp-colour-dcl* '(
  "bptools_colour : dialog {"
  "  label = @title@;"
  "  : list_box { key = \"colours\"; width = 36; height = 18; }"
  "  : edit_box { key = \"other\"; edit_width = 34; }"
  "  : text { key = \"error\"; width = 36; }"
  "  ok_cancel;"
  "}"))

(defun bp:colour-dialog (colours / d pick other done)
  ;; The colour picked in a list of colours, or typed under «Інший»; "" on Cancel; nil without a
  ;; dialog (the console AutoCAD).
  (if (setq d (bp:dlg-open (bp:dcl-lines *bp-colour-dcl* (list (list "title" (bp:msg "wire.title" nil) "Wire colour")))
                           "bptools_colour"))
    (progn
      (start_list "colours") (mapcar 'add_list colours) (end_list)
      (set_tile "colours" "0")
      (setq pick 0)
      (set_tile "other" "")
      (action_tile "colours" "(setq pick (atoi $value)) (if (= $reason 4) (done_dialog 1))")
      (action_tile "other" "(setq other $value)")
      (action_tile "accept" "(setq other (get_tile \"other\")) (done_dialog 1)")
      (setq done (start_dialog))
      (bp:dlg-close d)
      (cond ((/= done 1) "")
            ((and other (/= (vl-string-trim " " other) "")) (vl-string-trim " " other))
            ((nth pick colours))))))

(defun bp:pick-colour (/ colours c s)
  ;; From the dialog, or at the command line as a number of the list or a name.
  (setq colours (bp:label "colours"))
  (cond ((setq c (bp:colour-dialog colours)) c)
        (T
         (setq c 0)
         (princ (strcat "\n" (bp:msg "wire.list" nil)))
         (foreach x colours (princ (strcat "\n  " (itoa (setq c (1+ c))) " " x)))
         (setq s (vl-string-trim " " (getstring T (strcat "\n" (bp:msg "wire.ask" nil)))))
         (cond ((= s "") "")
               ((and (bp:digits-p s) (<= 1 (atoi s) (length colours))) (nth (1- (atoi s)) colours))
               (s)))))

(defun bp:wire-command (/ c)
  (if (/= (setq c (bp:pick-colour)) "")
    (while (bp:place "wire" c))))

(defun c:BPWIRE () (bp:run "BPWIRE" 'bp:wire-command))

;;; ---- BPNAME -----------------------------------------------------------------

(defun bp:name-command (/ last s)
  (setq last (bp:setting "Name")
        s (vl-string-trim " " (getstring T (strcat "\n" (if (= last "") (bp:msg "name.ask" nil) (bp:msg "name.ask-last" (list "name" last)))))))
  (if (= s "") (setq s last))
  (if (/= s "")
    (progn (bp:set-setting "Name" s) (bp:place "name" s))))

(defun c:BPNAME () (bp:run "BPNAME" 'bp:name-command))

;;; ---- BPVIEW -----------------------------------------------------------------

(defun bp:view-command (/ kws k)
  ;; The side's keyword, then the note «Вигляд з …» of the same place in the labels' list.
  (setq kws (bp:label "view-keywords"))
  (initget (apply 'strcat (mapcar '(lambda (k) (strcat k " ")) kws)))
  (if (setq k (getkword (strcat "\n" (bp:msg "view.ask" (list "sides" (bp:join kws "/"))))))
    (bp:place "view" (nth (vl-position k kws) (bp:label "views")))))

(defun bp:join (xs sep)
  (if xs (apply 'strcat (cons (car xs) (mapcar '(lambda (x) (strcat sep x)) (cdr xs)))) ""))

(defun c:BPVIEW () (bp:run "BPVIEW" 'bp:view-command))

;;; ---- BPFIG ------------------------------------------------------------------

(defun bp:figure-command (/ p n s c)
  (if (setq p (getpoint (strcat "\n" (bp:msg "figure.where" nil))))
    (progn
      (setq n (bp:next-figure (bp:wcs p))
            s (vl-string-trim " " (getstring (strcat "\n" (bp:msg "figure.number" (list "n" n))))))
      (if (bp:digits-p s) (setq n (atoi s)))
      (setq c (vl-string-trim " " (getstring T (strcat "\n" (bp:msg "figure.caption" nil)))))
      (bp:add-text "figure" (bp:figure-text n c) (bp:wcs p)))))

(defun c:BPFIG () (bp:run "BPFIG" 'bp:figure-command))

;;; ---- BPSTYLE ----------------------------------------------------------------

(defun bp:style-command (/ ss kws k kind ents i n)
  (princ (strcat "\n" (bp:msg "style.select" nil)))
  (if (setq ss (ssget '((0 . "TEXT,MTEXT"))))
    (progn
      (setq kws (mapcar 'cadddr *bptools-styles*))
      (initget (apply 'strcat (mapcar '(lambda (k) (strcat k " ")) kws)))
      (if (setq k (getkword (strcat "\n" (bp:msg "style.ask" (list "kinds" (bp:join kws "/"))))))
        (progn
          (setq kind (car (nth (vl-position k kws) *bptools-styles*)))
          (repeat (setq i (sslength ss)) (setq ents (cons (ssname ss (setq i (1- i))) ents)))
          (setq n (bp:restyle ents kind))
          (princ (strcat "\n" (bp:msg "style.done" (list "n" n "style" (bp:kind-style kind))))))))))

(defun c:BPSTYLE () (bp:run "BPSTYLE" 'bp:style-command))
