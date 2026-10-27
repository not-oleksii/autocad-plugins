;;; ---- BPPART -----------------------------------------------------------------
;;; «Вставити деталь»: pastes one вигляд of a part of the library (docs/adr/0002). A window lists
;;; the parts, the вигляди of the one picked and a preview, with the rotation (in 90° steps) and the
;;; scale; it opens on the part, вигляд, rotation and scale used last. The вигляд is pasted as a block
;;; from its drawing in the bundle's parts folder, on the current layer, never mirrored, and its pin
;;; numbers are stood upright at their style's height whatever the rotation and scale. The part's
;;; name becomes the one BPNAME offers next. Defines c:BPPART. tests/run.ps1 also calls:
;;;   bp:part-names                     the parts of the catalog, sorted
;;;   bp:part-views (part)              its entries of the catalog, in the order of *bptools-views*
;;;   bp:paste-part (entry pt rot scale)  inserts an entry at pt (or pause); returns the insert
;;; Settings: Part, View (its key), Rotation and Scale, the ones used last.

(defun bp:part-names (/ out)
  (foreach p *bptools-parts* (if (not (member (car p) out)) (setq out (cons (car p) out))))
  (acad_strlsort out))

(defun bp:part-views (part)
  (vl-remove nil (mapcar '(lambda (v) (vl-some '(lambda (p) (if (and (= (car p) part) (= (cadr p) (car v))) p)) *bptools-parts*))
                         *bptools-views*)))

(defun bp:view-name (entry) (cadr (assoc (cadr entry) *bptools-views*)))
(defun bp:part-block (entry) (strcat (car entry) *bptools-part-dash* (bp:view-name entry)))
(defun bp:part-file (entry) (strcat *bptools-home* "\\parts\\" (caddr entry) ".dwg"))

(defun bp:style-height (style)
  (vl-some '(lambda (s) (if (= (strcase (cadr s)) (strcase style)) (caddr s))) *bptools-styles*))

(defun bp:upright (ins / e d h)
  ;; The insert's attributes (its pin numbers) turned back to horizontal about their centres, at
  ;; their style's height, so a rotated or enlarged part keeps numbers the size and way up of the rest.
  (setq e (entnext ins))
  (while (and e (= (cdr (assoc 0 (setq d (entget e)))) "ATTRIB"))
    (setq h (cond ((bp:style-height (cdr (assoc 7 d)))) ((cdr (assoc 40 d)))))
    (entmod (bp:put (list '(50 . 0.0) (cons 40 h) '(41 . 1.0)) d))
    (setq e (entnext e)))
  (entupd ins))

(defun bp:paste-part (entry pt rot scale / name)
  (setq name (bp:part-block entry))
  (bp:set-var "ATTREQ" 0)
  (bp:set-var "ATTDIA" 0)
  (command "_.-INSERT" (if (tblobjname "BLOCK" name) name (strcat name "=" (bp:part-file entry)))
           "_S" scale "_R" rot pt)
  (bp:upright (entlast))
  (bp:set-setting "Name" (car entry))
  (entlast))

;;; ---- The window -------------------------------------------------------------

(setq *bp-part-dcl* '(
  "bptools_part : dialog {"
  "  label = @title@;"
  "  : row {"
  "    : column {"
  "      : text { key = \"h_parts\"; width = 34; }"
  "      : list_box { key = \"parts\"; width = 34; height = 22; }"
  "    }"
  "    : column {"
  "      : text { key = \"h_views\"; width = 44; }"
  "      : list_box { key = \"views\"; width = 44; height = 4; }"
  "      : image { key = \"preview\"; width = 44; height = 16; color = 255; }"
  "      : row {"
  "        : popup_list { key = \"rotation\"; label = @rotation@; width = 22; }"
  "        : popup_list { key = \"scale\"; label = @scale@; width = 20; }"
  "      }"
  "    }"
  "  }"
  "  ok_cancel;"
  "}"))

(setq *bp-rotations* '(0 90 180 270) *bp-scales* '(1 2 3 4 5))

(defun bp:preview (entry rot / w h k dx dy b segs a c s x1 y1 x2 y2)
  ;; The вигляд's outline turned by rot, as big as fits the image tile and centred, y downwards:
  ;; dark grey (250) on white (255), since colour 7 shows white on the dialog's grey.
  (setq w (dimx_tile "preview") h (dimy_tile "preview") b (nth 3 entry) segs (nth 4 entry)
        a (* pi (/ rot 180.0)) c (cos a) s (sin a))
  (defun bp:turn (x y) (list (- (* x c) (* y s)) (+ (* x s) (* y c))))
  (setq b (mapcar '(lambda (p) (bp:turn (car p) (cadr p)))
                  (list (list (car b) (cadr b)) (list (caddr b) (cadr b)) (list (car b) (cadddr b)) (list (caddr b) (cadddr b)))))
  (setq x1 (apply 'min (mapcar 'car b)) x2 (apply 'max (mapcar 'car b))
        y1 (apply 'min (mapcar 'cadr b)) y2 (apply 'max (mapcar 'cadr b))
        k (* 0.9 (min (/ w (max 1.0 (- x2 x1))) (/ h (max 1.0 (- y2 y1)))))
        dx (- (/ w 2.0) (* k (/ (+ x1 x2) 2.0)))
        dy (+ (/ h 2.0) (* k (/ (+ y1 y2) 2.0))))
  (start_image "preview")
  (fill_image 0 0 w h 255)
  (while segs
    (setq a (bp:turn (car segs) (cadr segs)) b (bp:turn (caddr segs) (cadddr segs)) segs (cddr (cddr segs)))
    (vector_image (fix (+ dx (* k (car a)))) (fix (- dy (* k (cadr a)))) (fix (+ dx (* k (car b)))) (fix (- dy (* k (cadr b)))) 250))
  (end_image))

(defun bp:part-dialog (/ d names part views view rot scale done)
  ;; (entry rotation scale), 'cancel, or nil without a dialog (the console AutoCAD).
  (if (setq d (bp:dlg-open (bp:dcl-lines *bp-part-dcl* (list (list "title" (bp:msg "part.title" nil) "Insert part")
                                                             (list "rotation" (bp:msg "part.rotation" nil) "Rotation")
                                                             (list "scale" (bp:msg "part.scale" nil) "Scale")))
                           "bptools_part"))
    (progn
      (setq names (bp:part-names)
            part (cond ((member (bp:setting "Part") names) (bp:setting "Part")) ((car names)))
            rot (cond ((member (atoi (bp:setting "Rotation")) *bp-rotations*) (atoi (bp:setting "Rotation"))) (0))
            scale (cond ((member (atoi (bp:setting "Scale")) *bp-scales*) (atoi (bp:setting "Scale"))) (1)))
      (defun bp:part-show (/ keys)
        ;; The вигляди of part, the one of the same side as before kept, and its preview.
        (setq views (bp:part-views part)
              keys (mapcar 'cadr views)
              view (nth (cond ((vl-position (if view (cadr view) (bp:setting "View")) keys)) (0)) views))
        (bp:dlg-list "views" (mapcar 'bp:view-name views) (vl-position view views))
        (bp:preview view rot))
      (set_tile "h_parts" (bp:msg "part.parts" nil))
      (set_tile "h_views" (bp:msg "part.views" nil))
      (bp:dlg-list "parts" names (vl-position part names))
      (bp:dlg-list "rotation" (mapcar '(lambda (r) (strcat (itoa r) "°")) *bp-rotations*) (vl-position rot *bp-rotations*))
      (bp:dlg-list "scale" (mapcar '(lambda (s) (strcat (itoa s) ":1")) *bp-scales*) (vl-position scale *bp-scales*))
      (bp:part-show)
      (action_tile "parts" "(setq part (nth (atoi $value) names)) (bp:part-show) (if (= $reason 4) (done_dialog 1))")
      (action_tile "views" "(setq view (nth (atoi $value) views)) (bp:preview view rot) (if (= $reason 4) (done_dialog 1))")
      (action_tile "rotation" "(setq rot (nth (atoi $value) *bp-rotations*)) (bp:preview view rot)")
      (action_tile "scale" "(setq scale (nth (atoi $value) *bp-scales*))")
      (setq done (start_dialog))
      (bp:dlg-close d)
      (if (= done 1) (list view rot scale) 'cancel))))

(defun bp:pick-number (items default / i s)
  ;; One of items, listed with numbers at the command line; Enter takes the one at default.
  (setq i 0)
  (foreach x items (princ (strcat "\n  " (itoa (setq i (1+ i))) " " x)))
  (setq s (vl-string-trim " " (getstring (strcat "\n" (bp:msg "part.ask-number" (list "n" (1+ default)))))))
  (cond ((= s "") default)
        ((and (bp:digits-p s) (<= 1 (atoi s) (length items))) (1- (atoi s)))))

(defun bp:part-ask (/ names i views j rot scale)
  ;; The same choices at the command line. nil when one of them is wrong.
  (setq names (bp:part-names))
  (princ (strcat "\n" (bp:msg "part.parts" nil)))
  (if (setq i (bp:pick-number names (cond ((vl-position (bp:setting "Part") names)) (0))))
    (progn
      (setq views (bp:part-views (nth i names)))
      (princ (strcat "\n" (bp:msg "part.views" nil)))
      (if (setq j (bp:pick-number (mapcar 'bp:view-name views) (cond ((vl-position (bp:setting "View") (mapcar 'cadr views))) (0))))
        (progn
          (initget 4)
          (setq rot (cond ((getint (strcat "\n" (bp:msg "part.ask-rotation" nil)))) (0)))
          (initget 6)
          (setq scale (cond ((getint (strcat "\n" (bp:msg "part.ask-scale" nil)))) (1)))
          (if (member rot *bp-rotations*)
            (list (nth j views) rot scale)
            (progn (princ (strcat "\n" (bp:msg "part.bad-rotation" nil))) nil)))))))

(defun bp:part-command (/ choice)
  (cond ((null *bptools-parts*) (princ (strcat "\n" (bp:msg "part.none" nil))))
        ((and (setq choice (cond ((bp:part-dialog)) ((bp:part-ask)))) (/= choice 'cancel))
         (bp:set-setting "Part" (car (car choice)))
         (bp:set-setting "View" (cadr (car choice)))
         (bp:set-setting "Rotation" (itoa (cadr choice)))
         (bp:set-setting "Scale" (itoa (caddr choice)))
         (princ (strcat "\n" (bp:msg "part.where" (list "part" (bp:part-block (car choice))))))
         (bp:paste-part (car choice) pause (cadr choice) (caddr choice)))))

(defun c:BPPART () (bp:run "BPPART" 'bp:part-command))
