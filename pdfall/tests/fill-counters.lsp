;;; The example drawing leaves the Аркуш/Аркушів cells of the К1, К2 and 1ЖП специфікації empty,
;;; so PDFALL refuses it. This types them in, the way the user would.
(defun tt (x y s) (entmake (list '(0 . "TEXT") (list 10 x y 0.0) '(40 . 2.5) (cons 1 s) '(8 . "Формат чертежа"))))
(tt 2877.3 1497.7 "1") (tt 2894.7 1497.7 "2") (tt 3134.0 1484.2 "2")
(tt 2442.3 1161.7 "1") (tt 2459.7 1161.7 "2") (tt 2700.0 1148.2 "2")
(tt 2901.3 825.7 "1") (tt 2918.7 825.7 "2") (tt 3158.0 812.2 "2")
(princ)
