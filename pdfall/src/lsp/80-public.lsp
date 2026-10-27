;;; ---- For other plugins ------------------------------------------------------
;;; The one function another plugin may call: BPTOOLS asks it which марка a label is drawn in, to
;;; number позиційні номери across the марка (../docs/adr/0003-plugins-talk-through-one-function.md).
;;; Its name, arguments and result stay the same from version to version, and tests/run.ps1 checks them.
;;;   (pdfall:marka-at pt)   the марка of the рамка that point pt is in, exactly as typed in its
;;;                          title block, or nil when pt is in no рамка or its рамка has no марка
;;;   (pdfall:marka-at pts)  the same for each point of a list, reading the drawing once
;;; A point is (x y) or (x y z) in Model space. A plugin that runs without PDFALL tests for it first:
;;;   (if pdfall:marka-at (pdfall:marka-at pt))

(defun pdfall:marka-at (p / records)
  (setq records (car (pa:read-drawing)))
  (if (numberp (car p))
    (pa:marka-of-point p records)
    (mapcar '(lambda (pt) (pa:marka-of-point pt records)) p)))

(defun pa:marka-of-point (pt records)
  (vl-some '(lambda (r / ll ur)
              (setq ll (pa:get 'll r) ur (pa:get 'ur r))
              (if (and (<= (car ll) (car pt) (car ur)) (<= (cadr ll) (cadr pt) (cadr ur)))
                (pa:get 'marka r)))
           records))
