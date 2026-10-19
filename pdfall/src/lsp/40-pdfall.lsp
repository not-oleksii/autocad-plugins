;;; ---- PDFALL -----------------------------------------------------------------
;;; Checks every марка, plots every рамка to PDF and runs merge.exe. Defines c:PDFALL; nothing here
;;; is called from the other files.

;;; ---- Checks -----------------------------------------------------------------

(defun pa:check (marka kind items / n nums out r k)
  ;; Settles and checks the sheet numbers of one kind of one марка. Returns the items, numbered.
  (setq n (length items))
  (if (= n 1)
    (progn
      (setq r (car items))
      (if (or (null (pa:get 'sheet r)) (null (pa:get 'total r)))
        (pa:warn (strcat marka " " kind ": клітинки Аркуш/Аркушів порожні, тому це лист 1."
                         " Заповніть їх командою PDFNUM.")))
      (if (null (pa:get 'sheet r)) (setq items (list (pa:put 'sheet 1 r))))))
  (foreach r items
    (if (null (pa:get 'sheet r))
      (pa:err (strcat marka ": клітинка Аркуш порожня, хоча рамок " (pa:kind-pl kind) ": " (itoa n)
                      " (PDFNUM її заповнить)")
              r)))
  (setq nums (vl-remove nil (mapcar '(lambda (r) (pa:get 'sheet r)) items)))
  (foreach r items
    (setq k (pa:get 'sheet r))
    (if (and k (> (length (vl-remove-if-not '(lambda (x) (= x k)) nums)) 1))
      (pa:err (strcat marka ": Аркуш " (itoa k) " стоїть на кількох рамках " (pa:kind-pl kind)) r))
    (if (and k (or (< k 1) (> k n)))
      (pa:err (strcat marka ": Аркуш " (itoa k) ", але рамок " (pa:kind-pl kind) " лише " (itoa n)) r)))
  (setq k 1)
  (while (<= k n)
    (if (and (not (member k nums)) (= (length nums) n))
      (pa:err (strcat marka ": жодна рамка " (pa:kind-of kind) " не має Аркуш " (itoa k)) (car items)))
    (setq k (1+ k)))
  ;; Аркушів: on every лист; on a специфікація only on its first аркуш.
  (foreach r items
    (cond
      ((and (pa:get 'total r) (/= (pa:get 'total r) n))
       (pa:err (strcat marka ": Аркушів " (itoa (pa:get 'total r)) ", але знайдено рамок "
                       (pa:kind-pl kind) ": " (itoa n))
               r))
      ((and (null (pa:get 'total r)) (> n 1)
            (or (= kind "лист") (= (pa:get 'sheet r) 1)))
       (pa:err (strcat marka ": клітинка Аркушів порожня (PDFNUM її заповнить)") r))))
  (vl-sort items '(lambda (a b) (< (cond ((pa:get 'sheet a)) (0)) (cond ((pa:get 'sheet b)) (0))))))

;;; ---- Files ------------------------------------------------------------------

(defun pa:file-name (marka r unfilled)
  (strcat marka
          (if (= (pa:get 'kind r) "лист") " лист " " специфікація лист ")
          (itoa (pa:get 'sheet r))
          (if unfilled " без заливки" "")
          ".pdf"))

(defun pa:ours-p (name marka / w)
  ;; True for the PDFs PDFALL and merge.exe write for this марка.
  (if (and (wcmatch (strcase name) "*.PDF")
           (> (strlen name) (+ (strlen marka) 5))
           (= (substr name 1 (1+ (strlen marka))) (strcat marka " ")))
    (progn
      (setq w (pa:words (substr name (+ 2 (strlen marka)) (- (strlen name) (strlen marka) 5))))
      (or (equal w '("Загальний"))
          (equal w '("Загальний" "друк"))
          (and (= (car w) "лист") (pa:digits-p (cadr w))
               (or (null (cddr w)) (equal (cddr w) '("без" "заливки"))))
          (and (= (car w) "специфікація") (= (cadr w) "лист") (pa:digits-p (caddr w))
               (null (cdddr w)))))))

(defun pa:escape (s / out)
  ;; s with wildcard characters escaped for ssget and wcmatch.
  (setq out "")
  (foreach c (vl-string->list s)
    (setq out (strcat out (if (member c (vl-string->list "#@.*?~[]-,`")) "`" "") (chr c))))
  out)

(defun pa:plot (r path / sheetp p1 p2)
  (setq sheetp (= (pa:get 'kind r) "лист")
        p1 (trans (pa:get 'll r) 0 1)
        p2 (trans (pa:get 'ur r) 0 1))
  (if (findfile path) (vl-file-delete path))
  (princ (strcat "\n  " (vl-filename-base path) "..."))
  (command "_.-PLOT" "_Y" "Model" device
           (if sheetp *pdfall-paper-sheet* *pdfall-paper-spec*)
           "_M" (if sheetp "_L" "_P") "_N" "_W" p1 p2
           "_F" "_C" "_N" "." "_Y" "_A" path "_N" "_Y")
  (if (findfile path)
    (setq plotted (1+ plotted))
    (pa:err (strcat "не вдалося записати " path) r)))

;;; ---- Layers -----------------------------------------------------------------

(defun pa:set-fill (on / d)
  (foreach n fills
    (setq d (pa:layer n))
    (if on
      (pa:layer-set n (abs (cdr (assoc 62 d))) (logand (cdr (assoc 70 d)) (~ 1)))
      (pa:layer-set n (- (abs (cdr (assoc 62 d)))) (cdr (assoc 70 d))))))

(defun pa:hidden-layers (/ out d nm)
  ;; Layers that are off or frozen but hold objects in Model space; their objects would not print.
  (setq d (tblnext "LAYER" T))
  (while d
    (setq nm (cdr (assoc 2 d)))
    (if (and (or (minusp (cdr (assoc 62 d))) (= 1 (logand 1 (cdr (assoc 70 d)))))
             (/= (strcase nm) "DEFPOINTS")
             (not (member nm fills))
             (not (vl-string-search "|" nm))
             (ssget "_X" (list (cons 8 (pa:escape nm)) '(410 . "Model"))))
      (setq out (cons nm out)))
    (setq d (tblnext "LAYER")))
  (reverse out))

;;; ---- The command ------------------------------------------------------------

(defun pa:run (/ hidden ans r drawing records markas groups base dir files locked e)
  (if (= 0 (getvar "DWGTITLED"))
    (progn (princ "\nPDFALL: спершу збережіть креслення, щоб PDF було куди покласти.") (exit)))

  (princ "\nPDFALL: читаю креслення...")
  (setq drawing (pa:read-drawing)
        records (car drawing)
        markas (pa:markas records))
  (foreach p (cadr drawing) (setq errors (cons p errors)))

  ;; Check each марка.
  ;; Two марки that look the same but are typed with different letters would split one марка in two.
  (foreach m markas
    (foreach other (cdr (member m markas))
      (if (= (pa:cyr m) (pa:cyr other))
        (pa:err (strcat "'" m "' і '" other "' виглядають однаково, але набрані різними"
                        " (латинськими/кириличними) літерами; наберіть марку однаково в усіх основних написах")
                (vl-some '(lambda (r) (if (= (pa:get 'marka r) m) r)) records)))))
  (foreach m markas
    (setq groups
      (cons (list m
                  (pa:check m "лист" (pa:of m "лист" records))
                  (pa:check m "специфікація" (pa:of m "специфікація" records)))
            groups)))
  (setq groups (reverse groups))

  (if (null fills)
    (pa:err (strcat "не знайдено шар заливки (шукав: "
                    (vl-string-right-trim ", " (apply 'strcat (mapcar '(lambda (n) (strcat n ", ")) *pdfall-fill-layers*)))
                    "). Якщо його перейменували, додайте нову назву до *pdfall-fill-layers* у pdfall.lsp")
            nil))
  (if errors
    (progn
      (pa:report-errors "нічого не надруковано. Виправте це в кресленні й запустіть PDFALL ще раз:")
      (pa:report-warnings)
      (exit)))

  ;; Hidden layers would silently drop objects from every PDF.
  (if (setq hidden (pa:hidden-layers))
    (progn
      (princ "\n\nЦі шари вимкнені або заморожені, тож їхніх об'єктів НЕ буде в PDF:")
      (foreach n hidden (princ (strcat "\n  " n)))
      (initget "Так Ні")
      (setq ans (getkword "\nВсе одно друкувати? [Так/Ні] <Ні>: "))
      (if (/= ans "Так") (progn (princ "\nPDFALL: нічого не надруковано.") (exit)))))

  (if (/= 0 (getvar "DBMOD")) (command "_.QSAVE"))

  ;; Folders, and the old PDFs of every марка plotted now.
  (setq base (strcat (getvar "DWGPREFIX") *pdfall-folder*))
  (vl-mkdir base)
  (foreach m markas
    (setq dir (strcat base "\\" m))
    (vl-mkdir dir)
    (foreach name (vl-directory-files dir "*.pdf" 1)
      (if (pa:ours-p name m)
        (setq files (cons (strcat dir "\\" name) files)))))
  (foreach path files
    (if (setq e (open path "a")) (close e) (setq locked (cons path locked))))
  (if locked
    (progn
      (princ "\n\nPDFALL: нічого не надруковано. Закрийте ці файли (відкриті в переглядачі PDF?) і запустіть PDFALL ще раз:")
      (foreach path (reverse locked) (princ (strcat "\n  X " path)))
      (exit)))
  (foreach path files (vl-file-delete path))
  (foreach name (vl-directory-files base nil -1)
    (if (not (member name (append '("." "..") markas)))
      (pa:warn (strcat "'" *pdfall-folder* "\\" name "' — не марка цього креслення, залишаю як є"))))

  ;; Plot: everything with the шар заливки on, then every лист again with it off.
  (setq sysvars (append sysvars (mapcar '(lambda (v) (cons v (getvar v))) '("BACKGROUNDPLOT" "OSMODE"))))
  (setvar "BACKGROUNDPLOT" 0)
  (setvar "OSMODE" 0)
  (setq fill-state
    (mapcar '(lambda (n / d) (setq d (pa:layer n)) (list n (cdr (assoc 62 d)) (cdr (assoc 70 d))))
            fills))
  (princ "\n\nДрукую:")
  (pa:set-fill T)
  (foreach g groups
    (foreach r (cadr g) (pa:plot r (strcat base "\\" (car g) "\\" (pa:file-name (car g) r nil))))
    (foreach r (caddr g) (pa:plot r (strcat base "\\" (car g) "\\" (pa:file-name (car g) r nil)))))
  (pa:set-fill nil)
  (foreach g groups
    (foreach r (cadr g) (pa:plot r (strcat base "\\" (car g) "\\" (pa:file-name (car g) r T)))))
  (pa:restore)

  (princ (strcat "\n\nPDFALL: " (itoa plotted) " PDF у " base))
  (if errors (pa:report-errors "ці PDF не вдалося створити:"))
  (pa:report-warnings)
  (cond
    ((null *pdfall-merge*))
    ((findfile *pdfall-merge*)
     (princ "\nЗбираю Загальний і Загальний друк в окремому вікні...")
     (startapp "cmd.exe" (strcat "/c \"\"" *pdfall-merge* "\" \"" base "\"\"")))
    (T (princ (strcat "\n! " *pdfall-merge* " не знайдено, тому нічого не зібрано. Запустіть install.bat ще раз.")))))

;; AutoCAD's Plotters folder (the first one, if several are set).
(defun pa:plotters ()
  (car (pa:split (getenv "PrinterConfigDir") ";")))

;; Copy PDFALL.pc3 from *pdfall-home* into the Plotters folder if it isn't there yet.
(defun pa:install-pc3 (/ name)
  (setq name (car *pdfall-devices*))
  (if (and (not (findfile (strcat (pa:plotters) "\\" name)))
           (findfile (strcat *pdfall-home* "\\" name)))
    (vl-file-copy (strcat *pdfall-home* "\\" name) (strcat (pa:plotters) "\\" name))))

(defun c:PDFALL (/ *error* errors warnings fills fill-state sysvars plotted device)
  (defun *error* (msg)
    (pa:restore)
    (if (not (wcmatch (strcase msg) "*CANCEL*,*QUIT*,*EXIT*"))
      (princ (strcat "\nПомилка PDFALL: " msg)))
    (princ))
  (pa:install-pc3)
  (setq plotted 0
        fills (vl-remove-if-not '(lambda (n) (tblsearch "LAYER" n)) *pdfall-fill-layers*)
        device (cond ((vl-some '(lambda (n) (if (findfile (strcat (pa:plotters) "\\" n)) n))
                               *pdfall-devices*))
                     ((last *pdfall-devices*))))
  (if (/= device (car *pdfall-devices*))
    (pa:warn (strcat (car *pdfall-devices*) " немає в " (pa:plotters) ", тож кожен PDF відкриється в переглядачі."
                     " Скопіюйте його туди з " *pdfall-home* ".")))
  (setq sysvars (list (cons "CMDECHO" (getvar "CMDECHO"))))
  (setvar "CMDECHO" 0)
  (pa:run)
  (pa:restore)
  (princ))
