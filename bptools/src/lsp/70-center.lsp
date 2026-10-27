;;; ---- BPCENTER ---------------------------------------------------------------
;;; «Центрувати текст»: moves texts so that their centres are midway between the outermost points
;;; of other objects, across (Горизонтально, the default: only x changes) or up and down
;;; (Вертикально: only y). Each text is moved on its own, so a column of texts ends up centred on
;;; the same line. Defines c:BPCENTER. tests/run.ps1 also calls:
;;;   bp:box (e)                       an entity's extents as ((x1 y1) (x2 y2)) in world coordinates
;;;   bp:center (texts refs vertical)  moves texts; returns how many

(defun bp:corners (pts)
  (list (list (apply 'min (mapcar 'car pts)) (apply 'min (mapcar 'cadr pts)))
        (list (apply 'max (mapcar 'car pts)) (apply 'max (mapcar 'cadr pts)))))

(defun bp:box-by-hand (e / d p w h col row tb)
  ;; Extents without ActiveX (the console AutoCAD), for the entities that are easy to measure.
  (setq d (entget e))
  (cond ((= (cdr (assoc 0 d)) "LINE") (bp:corners (list (cdr (assoc 10 d)) (cdr (assoc 11 d)))))
        ((= (cdr (assoc 0 d)) "LWPOLYLINE") (bp:corners (mapcar 'cdr (vl-remove-if-not '(lambda (x) (= (car x) 10)) d))))
        ((member (cdr (assoc 0 d)) '("CIRCLE" "ARC"))
         (setq p (cdr (assoc 10 d)) w (cdr (assoc 40 d)))
         (list (list (- (car p) w) (- (cadr p) w)) (list (+ (car p) w) (+ (cadr p) w))))
        ((= (cdr (assoc 0 d)) "TEXT")
         (setq p (cdr (assoc 10 d)) tb (textbox d))
         (list (mapcar '+ p (car tb)) (mapcar '+ p (cadr tb))))
        ((= (cdr (assoc 0 d)) "MTEXT")
         ;; attachment 1..9: top, middle, bottom row; left, centre, right column
         (setq p (cdr (assoc 10 d)) w (cdr (assoc 42 d)) h (cdr (assoc 43 d))
               col (rem (1- (cdr (assoc 71 d))) 3) row (/ (1- (cdr (assoc 71 d))) 3)
               p (list (- (car p) (* col (/ w 2.0))) (+ (cadr p) (* row (/ h 2.0)))))
         (list (list (car p) (- (cadr p) h)) (list (+ (car p) w) (cadr p))))))

(defun bp:box (e / o mn mx r)
  (if (bp:acad)
    (progn
      (setq o (vlax-ename->vla-object e)
            r (vl-catch-all-apply 'vla-getboundingbox (list o 'mn 'mx)))
      (if (not (vl-catch-all-error-p r))
        (list (vlax-safearray->list mn) (vlax-safearray->list mx))
        (bp:box-by-hand e)))
    (bp:box-by-hand e)))

(defun bp:center (texts refs vertical / boxes ref axis mid n b c)
  (setq boxes (vl-remove nil (mapcar 'bp:box refs)))
  (setq n 0)
  (if boxes
    (progn
      (setq ref (bp:corners (append (mapcar 'car boxes) (mapcar 'cadr boxes)))
            axis (if vertical 'cadr 'car)
            mid (/ (+ ((eval axis) (car ref)) ((eval axis) (cadr ref))) 2.0))
      (foreach e texts
        (if (setq b (bp:box e))
          (progn
            (setq c (- mid (/ (+ ((eval axis) (car b)) ((eval axis) (cadr b))) 2.0)))
            (command "_.MOVE" e "" "_non" '(0.0 0.0 0.0) "_non" (trans (if vertical (list 0.0 c 0.0) (list c 0.0 0.0)) 0 1 T))
            (setq n (1+ n)))))))
  n)

(defun bp:selected (ss / i out)
  (if ss (repeat (setq i (sslength ss)) (setq out (cons (ssname ss (setq i (1- i))) out))))
  out)

(defun bp:center-command (/ texts refs h v k)
  (princ (strcat "\n" (bp:msg "center.texts" nil)))
  (if (setq texts (bp:selected (ssget '((0 . "TEXT,MTEXT")))))
    (progn
      (princ (strcat "\n" (bp:msg "center.refs" nil)))
      (if (setq refs (bp:selected (ssget)))
        (progn
          (setq h (bp:msg "center.kw-horizontal" nil) v (bp:msg "center.kw-vertical" nil))
          (initget (strcat h " " v))
          (setq k (cond ((getkword (strcat "\n" (bp:msg "center.ask" (list "h" h "v" v))))) (h)))
          (princ (strcat "\n" (bp:msg "center.done" (list "n" (bp:center texts refs (= k v)))))))))))

(defun c:BPCENTER () (bp:run "BPCENTER" 'bp:center-command))
