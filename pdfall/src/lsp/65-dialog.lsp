;;; ---- PDFSETTINGS ------------------------------------------------------------
;;; The settings dialog: what the «Лист» button (PDFLIST) pastes (a лист or a текстовий документ),
;;; the марка and what goes in the name cell, with a preview of the chosen template and the name
;;; cell's text (docs/adr/0009), and the шари заливки PDFALL turns off (docs/adr/0011). Its
;;; «Вставити» button saves them and pastes at once.
;;; Also the window of «Друк у PDF» that asks which марки to plot (docs/adr/0012).
;;; Defines c:PDFSETTINGS, and for PDFALL pa:settings-dialog (opened when the drawing has none of
;;; the шари заливки chosen) and pa:pick-dialog; tests/run.ps1 also calls pa:preview-lines, since
;;; the console AutoCAD the tests run in has no dialogs.
;;;
;;; The DCL is written to a temporary file when the dialog opens (pa:dlg-open). Every text is put
;;; in with set_tile and add_list, except the buttons' labels and the title, which pa:dcl-lines
;;; writes into the file (common\lsp\16-dialog.lsp).

(setq *pa-dcl* '(
  "pdfall_settings : dialog {"
  "  key = \"dialog\";"
  "  label = @title@;"
  "  : text { key = \"note\"; width = 130; }"
  "  spacer;"
  "  : row {"
  "    : column {"
  "      : text { key = \"h_doc\"; width = 42; }"
  "      : popup_list { key = \"doc\"; width = 42; }"
  "      : row {"
  "        : popup_list { key = \"size\"; width = 12; }"
  "        : popup_list { key = \"orient\"; width = 28; }"
  "      }"
  "      spacer;"
  "      : text { key = \"h_marka\"; width = 42; }"
  "      : edit_box { key = \"marka\"; edit_width = 40; }"
  "      spacer;"
  "      : text { key = \"h_prefix\"; width = 42; }"
  "      : popup_list { key = \"prefix\"; width = 42; }"
  "      : edit_box { key = \"prefix_text\"; edit_width = 40; }"
  "      spacer;"
  "      : text { key = \"h_line2\"; width = 42; }"
  "      : popup_list { key = \"line2\"; width = 42; }"
  "      : edit_box { key = \"line2_text\"; edit_width = 40; }"
  "    }"
  "    : column {"
  "      : text { key = \"h_preview\"; width = 46; }"
  "      : image { key = \"preview\"; width = 46; height = 22; color = -15; }"
  "      : text { key = \"h_name\"; width = 46; }"
  "      : text { key = \"name\"; width = 46; }"
  "    }"
  "    : column {"
  "      : text { key = \"h_fills\"; width = 38; }"
  "      : list_box { key = \"fills\"; width = 38; height = 24; multiple_select = true; }"
  "    }"
  "  }"
  "  : text { key = \"error\"; width = 130; }"
  "  : row {"
  "    fixed_width = true;"
  "    alignment = centered;"
  "    : button { key = \"paste\"; label = @paste@; width = 16; }"
  "    : spacer { width = 2; }"
  "    ok_button;"
  "    : spacer { width = 2; }"
  "    cancel_button;"
  "  }"
  "}"))

(defun pa:preview-lines (file wpx hpx / tp w h k dx dy c lines out px py)
  ;; The template file drawn into an image tile wpx by hpx pixels: (x1 y1 x2 y2 colour) per line,
  ;; y downwards as image tiles count it, the рамка as big as fits and centred, the name cell in red.
  (setq tp (pa:template (vl-filename-base file))
        w (nth 5 tp) h (nth 6 tp)
        k (* 0.94 (min (/ wpx (float w)) (/ hpx (float h))))
        dx (/ (- wpx (* k w)) 2.0)
        dy (/ (- hpx (* k h)) 2.0)
        c (nth 7 tp)
        lines (nth 8 tp))
  (defun px (x) (fix (+ dx (* k x) 0.5)))
  (defun py (y) (fix (+ dy (* k (- h y)) 0.5)))
  (while lines
    (setq out (cons (list (px (car lines)) (py (cadr lines)) (px (caddr lines)) (py (cadddr lines)) -16) out)
          lines (cddddr lines)))
  (foreach s (list (list (car c) (cadr c) (caddr c) (cadr c)) (list (caddr c) (cadr c) (caddr c) (cadddr c))
                   (list (caddr c) (cadddr c) (car c) (cadddr c)) (list (car c) (cadddr c) (car c) (cadr c)))
    (setq out (cons (list (px (car s)) (py (cadr s)) (px (caddr s)) (py (cadddr s)) 1) out)))
  (reverse out))

;; Shows the dialog; mode 'fills when PDFALL opens it because the drawing has none of the шари
;; заливки chosen, which also turns «Вставити» off. Returns 0 when it was cancelled, 1 when the
;; settings were saved, 2 when they were saved to paste at once, and nil when there is no dialog.
(defun pa:settings-dialog (mode / docs doc sizes size want-size orients orient want-orient
                             choices marka prefix prefix-text line2 line2-text result chosen tp
                             line2-empty fill-names fill-items fill-texts fill-on refresh-sizes refresh
                             draw check d)
  (setq docs (pa:docs)
        choices '("std" "custom" "none")
        chosen (pa:chosen)
        tp (pa:template (pa:doc-file chosen))
        doc (if (wcmatch chosen "text_*") chosen (strcat "list_" (caddr tp)))
        want-size (if (wcmatch chosen "text_*") "A3" (cadddr tp))
        want-orient (if (wcmatch chosen "text_*") "l" (substr chosen (strlen chosen)))
        marka (cond ((pa:last-marka)) (""))
        prefix (pa:setting "Prefix") prefix-text (vl-string-trim " " (pa:setting "PrefixText"))
        line2 (pa:setting "Line2") line2-text (vl-string-trim " " (pa:setting "Line2Text"))
        line2-empty (pa:msg "settings.line2-empty" nil)
        fill-names (pa:fill-names)
        fill-items (pa:fill-choices)
        fill-texts (mapcar 'cadr fill-items)
        fill-on (mapcar '(lambda (o) (if (pa:name-in (car o) fill-names) T)) fill-items))
  (defun refresh-sizes ()
    ;; The sizes and orientations the chosen document has, keeping the ones last picked where it
    ;; has them: a текстовий документ is A4 only, and going back to a лист brings its size back.
    (setq sizes (pa:doc-sizes doc)
          size (if (member want-size sizes) want-size (car sizes))
          orients (pa:doc-orients doc size)
          orient (if (member want-orient orients) want-orient (car orients)))
    (pa:dlg-list "size" sizes (pa:dlg-index size sizes))
    (pa:dlg-list "orient" (mapcar 'pa:orient-name orients) (pa:dlg-index orient orients)))
  (defun draw (/ file w h)
    ;; The preview: the template that will be pasted and the name cell's text, all in one line.
    (setq file (pa:doc-file (pa:doc-id doc size orient))
          w (dimx_tile "preview") h (dimy_tile "preview"))
    (start_image "preview")
    (fill_image 0 0 w h -15)
    (foreach s (pa:preview-lines file w h) (apply 'vector_image s))
    (end_image)
    (set_tile "h_preview" (if (= (pa:doc-kind doc) "text")
                            (pa:msg "settings.preview-text" (list "std" (pa:std-name (pa:doc-std doc))))
                            (pa:msg "settings.preview-list" (list "form" (pa:form-name file)))))
    (set_tile "name" (pa:name-line (pa:prefix-of prefix prefix-text)
                                   (if (= marka "") (pa:label "placeholder") marka)
                                   (if (= (pa:doc-kind doc) "list") (pa:line2-of line2 line2-text) ""))))
  (defun refresh ()
    (mode_tile "prefix_text" (if (= prefix "custom") 0 1))
    ;; only a лист has a second line
    (mode_tile "line2" (if (= (pa:doc-kind doc) "list") 0 1))
    (mode_tile "line2_text" (if (and (= line2 "custom") (= (pa:doc-kind doc) "list")) 0 1))
    (set_tile "error" "")
    (draw))
  (defun check (code / err)
    ;; Closes the dialog with code unless a field is wrong; pasting needs a марка.
    (setq marka (vl-string-trim " " (get_tile "marka"))
          prefix-text (vl-string-trim " " (get_tile "prefix_text"))
          line2-text (vl-string-trim " " (get_tile "line2_text")))
    (cond
      ((and (or (= code 2) (/= marka "")) (setq err (pa:marka-error marka)))
       (set_tile "error" err) (mode_tile "marka" 2))
      ((and (= prefix "custom") (setq err (pa:prefix-error prefix-text)))
       (set_tile "error" err) (mode_tile "prefix_text" 2))
      ((and (= line2 "custom") (= line2-text "") (= (pa:doc-kind doc) "list"))
       (set_tile "error" line2-empty) (mode_tile "line2_text" 2))
      (T (done_dialog code))))

  (pa:log (list "dialog: settings, mode" mode "| fill layers" fill-names))
  (if (setq d (pa:dlg-open (pa:dcl-lines *pa-dcl* (list (list "title" (pa:msg "settings.title" nil) "PDFALL")
                                                         (list "paste" (pa:msg "settings.paste" nil) "Paste")))
                           "pdfall_settings"))
    (progn
      (set_tile "dialog" (pa:msg "settings.title" nil))
      (set_tile "note" (if (or (= mode 'fills) (null (pa:fill-layers fill-names)))
                         (pa:msg "settings.fills-ask" nil)
                         (pa:msg "settings.note" nil)))
      (set_tile "h_doc" (pa:msg "settings.doc" nil))
      (set_tile "h_marka" (pa:msg "settings.marka" nil))
      (set_tile "h_prefix" (pa:msg "settings.prefix" nil))
      (set_tile "h_line2" (pa:msg "settings.line2" nil))
      (set_tile "h_name" (pa:msg "settings.name" nil))
      (set_tile "h_fills" (pa:msg "settings.fills" nil))
      (pa:dlg-list "doc" (mapcar 'pa:doc-name docs) (pa:dlg-index doc docs))
      (pa:dlg-list "prefix" (list (pa:label "prefix") (pa:msg "settings.custom" nil) (pa:msg "settings.no-prefix" nil))
                   (pa:dlg-index prefix choices))
      (pa:dlg-list "line2" (list (pa:label "list-line2") (pa:msg "settings.custom" nil) (pa:msg "settings.no-line2" nil))
                   (pa:dlg-index line2 choices))
      (pa:check-fill "fills" fill-texts fill-on)
      (set_tile "marka" marka)
      (set_tile "prefix_text" prefix-text)
      (set_tile "line2_text" line2-text)
      (refresh-sizes)
      (refresh)
      (if (= mode 'fills) (progn (mode_tile "paste" 1) (mode_tile "fills" 2)))
      (action_tile "doc" "(setq doc (nth (atoi $value) docs)) (refresh-sizes) (refresh)")
      (action_tile "size" "(setq size (nth (atoi $value) sizes) want-size size) (refresh-sizes) (refresh)")
      (action_tile "orient" "(setq orient (nth (atoi $value) orients) want-orient orient) (refresh)")
      (action_tile "marka" "(setq marka (vl-string-trim \" \" $value)) (draw)")
      (action_tile "prefix" "(setq prefix (nth (atoi $value) choices)) (refresh)")
      (action_tile "line2" "(setq line2 (nth (atoi $value) choices)) (refresh)")
      (action_tile "prefix_text" "(setq prefix-text (vl-string-trim \" \" $value)) (draw)")
      (action_tile "line2_text" "(setq line2-text (vl-string-trim \" \" $value)) (draw)")
      (action_tile "fills" "(setq fill-on (pa:check-flip \"fills\" $value fill-texts fill-on))")
      (action_tile "accept" "(check 1)")
      (action_tile "paste" "(check 2)")
      (setq result (start_dialog)
            fill-names (pa:fill-saved (vl-remove nil (mapcar '(lambda (o on) (if on (car o))) fill-items fill-on))
                                      fill-names))
      (pa:log (list "dialog: closed with" result "| document" (pa:doc-id doc size orient) "| marka" marka
                    "| prefix" prefix prefix-text "| line2" line2 line2-text "| fill layers" fill-names))
      (pa:dlg-close d)
      (if (member result '(1 2))
        (progn
          (pa:set-setting "Paste" (pa:doc-id doc size orient))
          (if (/= marka "") (pa:remember-marka marka))
          (pa:set-setting "Prefix" prefix)
          (pa:set-setting "PrefixText" prefix-text)
          (pa:set-setting "Line2" line2)
          (pa:set-setting "Line2Text" line2-text)
          (pa:set-fill-names fill-names)
          result)
        0))))

;;; ---- Which марки to plot ----------------------------------------------------

(setq *pa-pick-dcl* '(
  "pdfall_pick : dialog {"
  "  key = \"dialog\";"
  "  label = @title@;"
  "  : text { key = \"note\"; width = 70; }"
  "  : list_box { key = \"markas\"; width = 70; height = 16; multiple_select = true; }"
  "  : row {"
  "    fixed_width = true;"
  "    : button { key = \"all\"; label = @all@; width = 14; }"
  "    : button { key = \"none\"; label = @none@; width = 14; }"
  "  }"
  "  : text { key = \"error\"; width = 70; }"
  "  : row {"
  "    fixed_width = true;"
  "    alignment = centered;"
  "    : button { key = \"accept\"; label = @plot@; width = 16; is_default = true; }"
  "    : spacer { width = 2; }"
  "    cancel_button;"
  "  }"
  "}"))

(defun pa:marka-line (marka records / parts n)
  ;; A марка as the window lists it: "1ЧП — листів: 3, специфікацій: 1".
  (foreach k (reverse *pa-kinds*)
    (if (> (setq n (length (pa:of marka k records))) 0)
      (setq parts (cons (cond ((= k "list") (pa:msg "pick.lists" (list "n" n)))
                              ((= k "spec") (pa:msg "pick.specs" (list "n" n)))
                              ((pa:msg "pick.texts" (list "n" n))))
                        parts))))
  (pa:msg "pick.line" (list "marka" marka "kinds" (pa:names-shown parts))))

(defun pa:pick-dialog (markas records / d texts ons result check)
  ;; Asks which of markas to plot, all of them ticked at first. Returns the ones ticked, in the order
  ;; of markas; 'cancel when the user cancelled; nil when there is no dialog.
  (setq texts (mapcar '(lambda (m) (pa:marka-line m records)) markas)
        ons (mapcar '(lambda (m) T) markas))
  (defun check ()
    (if (vl-some '(lambda (on) on) ons) (done_dialog 1) (set_tile "error" (pa:msg "pick.none-ticked" nil))))
  (if (setq d (pa:dlg-open (pa:dcl-lines *pa-pick-dcl* (list (list "title" (pa:msg "pick.title" nil) "PDFALL")
                                                             (list "all" (pa:msg "pick.all" nil) "All")
                                                             (list "none" (pa:msg "pick.none" nil) "None")
                                                             (list "plot" (pa:msg "pick.plot" nil) "Plot")))
                           "pdfall_pick"))
    (progn
      (set_tile "dialog" (pa:msg "pick.title" nil))
      (set_tile "note" (pa:msg "pick.note" nil))
      (pa:check-fill "markas" texts ons)
      (action_tile "markas" "(setq ons (pa:check-flip \"markas\" $value texts ons)) (set_tile \"error\" \"\")")
      (action_tile "all" "(setq ons (mapcar '(lambda (m) T) markas)) (pa:check-fill \"markas\" texts ons) (set_tile \"error\" \"\")")
      (action_tile "none" "(setq ons (mapcar '(lambda (m) nil) markas)) (pa:check-fill \"markas\" texts ons)")
      (action_tile "accept" "(check)")
      (setq result (start_dialog))
      (pa:dlg-close d)
      (pa:log (list "dialog: pick closed with" result "| ticked" (vl-remove nil (mapcar '(lambda (m on) (if on m)) markas ons))))
      (if (= result 1) (vl-remove nil (mapcar '(lambda (m on) (if on m)) markas ons)) 'cancel))))

(defun c:PDFSETTINGS (/ *error* sysvars fill-state undo-open marka placed result)
  (defun *error* (msg) (pa:list-failed "PDFSETTINGS" msg))
  (pa:log-start "PDFSETTINGS")
  (setq result (pa:settings-dialog nil))
  (cond
    ((null result) (princ (strcat "\n" (pa:msg "settings.no-dialog" nil))))
    ((= result 2)
     (pa:paste-start)
     (setq marka (pa:last-marka))
     (pa:list-run "PDFLIST" marka)
     (pa:paste-cleanup)
     (pa:paste-report "PDFLIST" marka))
    ((= result 1)
     (princ (strcat "\n" (pa:msg "settings.saved"
                                 (list "form" (pa:chosen-shown)
                                       "name" (pa:name-shown (pa:chosen-kind) (cond ((pa:last-marka)) ((pa:label "placeholder"))))
                                       "fills" (pa:names-shown (pa:fills-here (pa:fill-names))))))))
    (T (princ (strcat "\n" (pa:msg "settings.unchanged" nil)))))
  (princ))
