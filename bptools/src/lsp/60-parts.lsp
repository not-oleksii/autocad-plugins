;;; ---- BPPART -----------------------------------------------------------------
;;; «Вставити деталь»: pastes one вигляд of a part of the library (docs/adr/0002). A window lists
;;; the parts (narrowed by what is typed in its search box), the вигляди of the one picked and a
;;; preview with the pin numbers, with the rotation (in 90° steps) and the scale; it opens on the
;;; part, вигляд, rotation and scale used last. The вигляд is pasted as a block from its drawing in
;;; the bundle's parts folder, on the current layer, never mirrored, and its pin numbers are stood
;;; upright at their style's height whatever the rotation and scale. Under it go the part's name and
;;; its «Вигляд з …» note, as labels the user can move; the name becomes the one BPNAME offers next.
;;; The name is the library's unless the user gave the part another in the window, which this PC
;;; then keeps; the block keeps the library's, so a drawing reads the same on every PC. Without
;;; «З номерами контактів» ticked the part goes in without its pin numbers.
;;; Defines c:BPPART. tests/run.ps1 also calls:
;;;   bp:part-names                     the parts of the catalog, sorted
;;;   bp:part-views (part)              its entries of the catalog, in the order of *bptools-views*
;;;   bp:paste-part (entry pt rot scale)  inserts an entry at pt (or pause) with its labels; returns the insert
;;;   bp:part-search (text names)       the names that contain text, or whose name on this PC does, ignoring case
;;;   bp:part-label, bp:set-part-label  the part's name on this PC
;;;   bp:outline (entry)                the вигляд's lines for the preview
;;;   bp:pins (entry)                   its pin numbers, none when the user wants none
;;; Settings: Part, View (its key), Rotation, Scale and Pins (1 with pin numbers, 0 without), the
;;; ones used last; Name:<part> for each part the user renamed.

(defun bp:part-names (/ out)
  (foreach p *bptools-parts* (if (not (member (car p) out)) (setq out (cons (car p) out))))
  (acad_strlsort out))

(defun bp:part-views (part)
  (vl-remove nil (mapcar '(lambda (v) (vl-some '(lambda (p) (if (and (= (car p) part) (= (cadr p) (car v))) p)) *bptools-parts*))
                         *bptools-views*)))

(defun bp:view-name (entry) (cadr (assoc (cadr entry) *bptools-views*)))

(defun bp:block-safe (name)
  ;; name as a block name: AutoCAD takes none of < > / \ " : ; ? * | , = ` in one. The commas become
  ;; points («2,54» is «2.54»), the rest dashes, as make_components.py names the blocks it makes.
  (vl-list->string (mapcar '(lambda (c) (cond ((= c 44) 46) ((member c '(60 62 47 92 34 58 59 63 42 124 61 96)) 45) (c)))
                           (vl-string->list name))))

(defun bp:part-block (entry) (strcat (bp:block-safe (car entry)) *bptools-part-dash* (bp:view-name entry)))
(defun bp:part-file (entry) (strcat *bptools-home* "\\parts\\" (caddr entry) ".dwg"))

(defun bp:label-key (part)
  ;; The setting holding part's name on this PC: Name: and the codes of its letters, since a
  ;; setting's name takes no Cyrillic.
  (apply 'strcat (cons "Name:" (mapcar '(lambda (c) (strcat (itoa c) ".")) (vl-string->list part)))))

(defun bp:part-label (part / s)
  ;; part's name on this PC: the one the user gave it, else the library's.
  (setq s (vl-string-trim " " (cond ((bp:setting (bp:label-key part))) (""))))
  (if (= s "") part s))

(defun bp:set-part-label (part label)
  ;; Gives part the name label on this PC; an empty label, or the library's name, takes it back.
  (setq label (vl-string-trim " " label))
  (bp:set-setting (bp:label-key part) (if (= label part) "" label)))

;; The outlines read so far of the parts whose outlines are in a file, (file (view-key x1 y1 ...) ...).
(setq *bp-outlines* nil)

(defun bp:read-outlines (file / f line view step out chunks)
  ;; The outlines of parts\<file>.txt, as make_components.py writes them: per вигляд a line
  ;; V "key" step x1 y1 x2 y2 (its extents in mm), then lines S of segments in steps from the base point.
  (cond ((assoc file *bp-outlines*))
        ((setq f (open (strcat *bptools-home* "\\parts\\" file ".txt") "r"))
         (defun bp:close-view ()
           (if view (setq out (cons (cons view (apply 'append (reverse chunks))) out))))
         (while (setq line (read-line f))
           (cond ((= (substr line 1 2) "V ")
                  (bp:close-view)
                  (setq line (read (strcat "(" (substr line 3) ")")) view (car line) step (cadr line) chunks nil))
                 ((= (substr line 1 2) "S ")
                  (setq chunks (cons (mapcar '(lambda (i) (* i step)) (read (strcat "(" (substr line 3) ")"))) chunks)))))
         (bp:close-view)
         (close f)
         (car (setq *bp-outlines* (cons (cons file out) *bp-outlines*))))))

(defun bp:outline (entry)
  ;; The вигляд's lines for the preview, (x1 y1 x2 y2 ...) in mm from its base point: in the
  ;; catalog, or, for a part of the components library, the name of the file they are in.
  (if (listp (nth 4 entry))
    (nth 4 entry)
    (cdr (assoc (cadr entry) (cdr (bp:read-outlines (nth 4 entry)))))))

(defun bp:pins (entry)
  ;; entry's pin numbers, ((x y "n") ...), unless the user wants parts without them.
  (if (/= (bp:setting "Pins") "0") (nth 5 entry)))

(defun bp:drop-pins (ins)
  ;; ins made again without its attributes (its pin numbers), the new insert returned: an
  ;; attribute can't be deleted on its own, and ActiveX is missing in the console AutoCAD.
  (entmake (vl-remove-if '(lambda (p) (member (car p) '(-1 5 66 330))) (entget ins)))
  (entdel ins)
  (entlast))

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

(defun bp:turned-box (entry rot scale / b a c s pts)
  ;; The вигляд's extents once turned by rot and scaled, as ((x1 y1) (x2 y2)) from its base point:
  ;; its outline, and its pin numbers, which stay upright and their size (1.2 around each centre).
  (setq b (nth 3 entry) a (* pi (/ rot 180.0)) c (cos a) s (sin a))
  (setq pts (mapcar '(lambda (p) (list (* scale (- (* (car p) c) (* (cadr p) s))) (* scale (+ (* (car p) s) (* (cadr p) c)))))
                    (list (list (car b) (cadr b)) (list (caddr b) (cadr b)) (list (car b) (cadddr b)) (list (caddr b) (cadddr b)))))
  (foreach n (bp:pins entry)
    (setq b (list (* scale (- (* (car n) c) (* (cadr n) s))) (* scale (+ (* (car n) s) (* (cadr n) c))))
          pts (append pts (list (mapcar '- b '(1.2 1.2)) (mapcar '+ b '(1.2 1.2))))))
  (bp:corners pts))

(defun bp:part-labels (entry ins rot scale / p b x y hn hv)
  ;; The part's name and, under it, «Вигляд з …», centred under the pasted вигляд.
  (setq p (cdr (assoc 10 (entget ins))) b (bp:turned-box entry rot scale)
        hn (bp:kind-height "name") hv (bp:kind-height "view")
        x (+ (car p) (/ (+ (caar b) (caadr b)) 2.0))
        y (- (+ (cadr p) (cadar b)) 2.0 (/ hn 2.0)))
  (bp:add-text "name" (bp:part-label (car entry)) (list x y 0.0))
  (bp:add-text "view" (strcat (bp:label "view") " " (bp:view-name entry)) (list x (- y (/ hn 2.0) 1.5 (/ hv 2.0)) 0.0)))

(setq *bp-part-file-block* "BPTOOLS-part-file")

(defun bp:define-views (entry / mates new)
  ;; Brings the blocks of a drawing that holds several вигляди of entry's part (a part of the
  ;; components library) into this one: the drawing becomes an empty block, inserted and deleted
  ;; again (cancelling the insert would stop a script too), and the вигляди that were not here
  ;; before and are not entry's are purged again, so only the one pasted stays.
  (setq mates (vl-remove-if-not '(lambda (e) (= (caddr e) (caddr entry))) (bp:part-views (car entry)))
        new (vl-remove-if '(lambda (e) (tblobjname "BLOCK" (bp:part-block e))) mates))
  (if (tblobjname "BLOCK" *bp-part-file-block*) (command "_.-PURGE" "_B" *bp-part-file-block* "_N"))
  (command "_.-INSERT" (strcat *bp-part-file-block* "=" (bp:part-file entry)) "_S" 1 "_R" 0 '(0.0 0.0 0.0))
  (entdel (entlast))
  (command "_.-PURGE" "_B"
           (apply 'strcat (cons *bp-part-file-block* (mapcar '(lambda (e) (strcat "," (bp:part-block e))) (vl-remove entry new))))
           "_N"))

(defun bp:paste-part (entry pt rot scale / name shared ins)
  (setq name (bp:part-block entry)
        shared (cdr (vl-remove-if-not '(lambda (e) (= (caddr e) (caddr entry))) (bp:part-views (car entry)))))
  (bp:set-var "ATTREQ" 0)
  (bp:set-var "ATTDIA" 0)
  (if (and shared (not (tblobjname "BLOCK" name))) (bp:define-views entry))
  (command "_.-INSERT" (if (tblobjname "BLOCK" name) name (strcat name "=" (bp:part-file entry)))
           "_S" scale "_R" rot pt)
  (setq ins (entlast))
  (if (bp:pins entry) (bp:upright ins) (setq ins (bp:drop-pins ins)))
  (bp:part-labels entry ins rot scale)
  (bp:set-setting "Name" (bp:part-label (car entry)))
  ins)

(defun bp:part-search (text names / key)
  (setq key (bp:lower (strcase (vl-string-trim " " text) T)))
  (if (= key "")
    names
    (vl-remove-if-not '(lambda (n) (or (vl-string-search key (bp:lower (strcase n T)))
                                       (vl-string-search key (bp:lower (strcase (bp:part-label n) T)))))
                      names)))

(defun bp:by-label (names)
  ;; names in the order of their names on this PC.
  (vl-sort names '(lambda (a b) (< (bp:lower (strcase (bp:part-label a) T)) (bp:lower (strcase (bp:part-label b) T))))))

;;; ---- The window -------------------------------------------------------------

(setq *bp-part-dcl* '(
  "bptools_part : dialog {"
  "  label = @title@;"
  "  : row {"
  "    : column {"
  "      : text { key = \"h_parts\"; width = 46; }"
  "      : edit_box { key = \"search\"; edit_width = 44; }"
  "      : list_box { key = \"parts\"; width = 46; height = 26; }"
  "    }"
  "    : column {"
  "      : text { key = \"h_views\"; width = 44; }"
  "      : list_box { key = \"views\"; width = 44; height = 7; }"
  "      : image { key = \"preview\"; width = 44; height = 16; color = 255; }"
  "      : row {"
  "        : popup_list { key = \"rotation\"; label = @rotation@; width = 22; }"
  "        : popup_list { key = \"scale\"; label = @scale@; width = 20; }"
  "      }"
  "      : toggle { key = \"pins\"; label = @pins@; }"
  "      : text { key = \"h_label\"; width = 44; }"
  "      : edit_box { key = \"label\"; edit_width = 42; }"
  "    }"
  "  }"
  "  ok_cancel;"
  "}"))

(setq *bp-rotations* '(0 90 180 270) *bp-scales* '(1 2 3 4 5))

;; The strokes of the digits 0-9 for the preview, image tiles having no text: segments of a cell
;; 0.6 wide and 1 high as (x1 y1 x2 y2), y upwards from the middle.
(setq *bp-digits*
  (mapcar '(lambda (on) (vl-remove nil (mapcar '(lambda (seg flag) (if (= flag 1) seg))
                                               '((0 0.5 0.6 0.5) (0.6 0.5 0.6 0) (0.6 0 0.6 -0.5) (0 -0.5 0.6 -0.5)
                                                 (0 -0.5 0 0) (0 0 0 0.5) (0 0 0.6 0))
                                               on)))
          '((1 1 1 1 1 1 0) (0 1 1 0 0 0 0) (1 1 0 1 1 0 1) (1 1 1 1 0 0 1) (0 1 1 0 0 1 1)
            (1 0 1 1 0 1 1) (1 0 1 1 1 1 1) (1 1 1 0 0 0 0) (1 1 1 1 1 1 1) (1 1 1 1 0 1 1))))

(defun bp:preview-number (s px py hp / w x)
  ;; s drawn in strokes hp pixels high, centred at the pixel px py.
  (setq w (* 0.85 hp) x (- px (/ (* w (strlen s)) 2.0)))
  (foreach ch (vl-string->list s)
    (if (<= 48 ch 57)
      (foreach g (nth (- ch 48) *bp-digits*)
        (vector_image (fix (+ x (* 0.1 hp) (* hp (car g)))) (fix (- py (* hp (cadr g))))
                      (fix (+ x (* 0.1 hp) (* hp (caddr g)))) (fix (- py (* hp (cadddr g)))) 1)))
    (setq x (+ x w))))

(defun bp:preview (entry rot / w h k dx dy b segs a c s x1 y1 x2 y2 hp)
  ;; The вигляд's outline turned by rot, as big as fits the image tile and centred, y downwards:
  ;; dark grey (250) on white (255), since colour 7 shows white on the dialog's grey; its pin numbers
  ;; in red, upright as they are pasted.
  (setq w (dimx_tile "preview") h (dimy_tile "preview") b (nth 3 entry) segs (bp:outline entry)
        a (* pi (/ rot 180.0)) c (cos a) s (sin a))
  (defun bp:turn (x y) (list (- (* x c) (* y s)) (+ (* x s) (* y c))))
  ;; the same extents as the pasted part, numbers included, so none falls outside the tile
  (setq b (bp:turned-box entry rot 1.0))
  (setq x1 (caar b) x2 (caadr b) y1 (cadar b) y2 (cadadr b)
        k (* 0.9 (min (/ w (max 1.0 (- x2 x1))) (/ h (max 1.0 (- y2 y1)))))
        hp (* k 1.8)
        dx (- (/ w 2.0) (* k (/ (+ x1 x2) 2.0)))
        dy (+ (/ h 2.0) (* k (/ (+ y1 y2) 2.0))))
  (start_image "preview")
  (fill_image 0 0 w h 255)
  (while segs
    (setq a (bp:turn (car segs) (cadr segs)) b (bp:turn (caddr segs) (cadddr segs)) segs (cddr (cddr segs)))
    (vector_image (fix (+ dx (* k (car a)))) (fix (- dy (* k (cadr a)))) (fix (+ dx (* k (car b)))) (fix (- dy (* k (cadr b)))) 250))
  (foreach n (bp:pins entry)
    (setq a (bp:turn (car n) (cadr n)))
    (bp:preview-number (caddr n) (+ dx (* k (car a))) (- dy (* k (cadr a))) hp))
  (end_image))

(defun bp:part-dialog (/ d names shown part views view rot scale pins done)
  ;; (entry rotation scale), 'cancel, or nil without a dialog (the console AutoCAD). The Pins
  ;; setting follows the check box at once, for the preview, and is put back on Cancel.
  (if (setq d (bp:dlg-open (bp:dcl-lines *bp-part-dcl* (list (list "title" (bp:msg "part.title" nil) "Insert part")
                                                             (list "rotation" (bp:msg "part.rotation" nil) "Rotation")
                                                             (list "scale" (bp:msg "part.scale" nil) "Scale")
                                                             (list "pins" (bp:msg "part.pins" nil) "With pin numbers")))
                           "bptools_part"))
    (progn
      (setq names (bp:by-label (bp:part-names))
            shown names
            part (cond ((member (bp:setting "Part") names) (bp:setting "Part")) ((car names)))
            rot (cond ((member (atoi (bp:setting "Rotation")) *bp-rotations*) (atoi (bp:setting "Rotation"))) (0))
            scale (cond ((member (atoi (bp:setting "Scale")) *bp-scales*) (atoi (bp:setting "Scale"))) (1))
            pins (bp:setting "Pins"))
      (defun bp:part-show (/ keys)
        ;; The вигляди of part, the one of the same side as before kept, its preview and its name.
        (setq views (bp:part-views part)
              keys (mapcar 'cadr views)
              view (nth (cond ((vl-position (if view (cadr view) (bp:setting "View")) keys)) (0)) views))
        (bp:dlg-list "views" (mapcar 'bp:view-name views) (vl-position view views))
        (set_tile "label" (bp:part-label part))
        (mode_tile "pins" (if (nth 5 view) 0 1))
        (bp:preview view rot))
      (defun bp:part-rename (s)
        ;; part takes the name s on this PC, in the list too.
        (bp:set-part-label part s)
        (set_tile "label" (bp:part-label part))
        (bp:dlg-list "parts" (mapcar 'bp:part-label shown) (cond ((vl-position part shown)) (0))))
      (set_tile "h_parts" (bp:msg "part.search" nil))
      (set_tile "h_views" (bp:msg "part.views" nil))
      (set_tile "h_label" (bp:msg "part.label" nil))
      (bp:dlg-list "parts" (mapcar 'bp:part-label names) (vl-position part names))
      (bp:dlg-list "rotation" (mapcar '(lambda (r) (strcat (itoa r) "°")) *bp-rotations*) (vl-position rot *bp-rotations*))
      (bp:dlg-list "scale" (mapcar '(lambda (s) (strcat (itoa s) ":1")) *bp-scales*) (vl-position scale *bp-scales*))
      (set_tile "pins" (if (= pins "0") "0" "1"))
      (bp:part-show)
      (action_tile "search" "(setq shown (bp:part-search $value names)) (bp:dlg-list \"parts\" (mapcar 'bp:part-label shown) (cond ((vl-position part shown)) (0))) (if (and shown (not (member part shown))) (progn (setq part (car shown)) (bp:part-show)))")
      (action_tile "parts" "(setq part (nth (atoi $value) shown)) (bp:part-show) (if (= $reason 4) (done_dialog 1))")
      (action_tile "label" "(bp:part-rename $value)")
      (action_tile "accept" "(bp:part-rename (get_tile \"label\")) (done_dialog 1)")
      (action_tile "views" "(setq view (nth (atoi $value) views)) (bp:preview view rot) (if (= $reason 4) (done_dialog 1))")
      (action_tile "rotation" "(setq rot (nth (atoi $value) *bp-rotations*)) (bp:preview view rot)")
      (action_tile "scale" "(setq scale (nth (atoi $value) *bp-scales*))")
      (action_tile "pins" "(bp:set-setting \"Pins\" $value) (bp:preview view rot)")
      (setq done (start_dialog))
      (bp:dlg-close d)
      (if (/= done 1) (bp:set-setting "Pins" pins))
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
  (setq names (bp:by-label (bp:part-names)))
  (princ (strcat "\n" (bp:msg "part.parts" nil)))
  (if (setq i (bp:pick-number (mapcar 'bp:part-label names) (cond ((vl-position (bp:setting "Part") names)) (0))))
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
         (princ (strcat "\n" (bp:msg "part.where" (list "part" (strcat (bp:part-label (car (car choice))) *bptools-part-dash* (bp:view-name (car choice)))))))
         (bp:paste-part (car choice) pause (cadr choice) (caddr choice)))))

(defun c:BPPART () (bp:run "BPPART" 'bp:part-command))
