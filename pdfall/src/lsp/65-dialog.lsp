;;; ---- PDFSETTINGS ------------------------------------------------------------
;;; The settings dialog: what PDFLIST and PDFTEXT paste and what goes in the name cell, with a
;;; preview of the chosen template and of the name cell's text (docs/adr/0009).
;;; Defines c:PDFSETTINGS; tests/run.ps1 also calls pa:preview-lines, since the console AutoCAD the
;;; tests run in has no dialogs.
;;;
;;; The DCL is written to a temporary file when the dialog opens. It holds no Ukrainian: every text
;;; is put in with set_tile and add_list, so the file's encoding never matters.

(setq *pa-dcl* '(
  "pdfall_settings : dialog {"
  "  key = \"dialog\";"
  "  : row {"
  "    : column {"
  "      : text { key = \"h_list\"; width = 42; }"
  "      : popup_list { key = \"list_std\"; width = 42; }"
  "      : row {"
  "        : popup_list { key = \"list_size\"; width = 12; }"
  "        : popup_list { key = \"list_orient\"; width = 28; }"
  "      }"
  "      spacer;"
  "      : text { key = \"h_text\"; width = 42; }"
  "      : popup_list { key = \"text_std\"; width = 42; }"
  "      spacer;"
  "      : text { key = \"h_prefix\"; width = 42; }"
  "      : popup_list { key = \"prefix\"; width = 42; }"
  "      : edit_box { key = \"prefix_text\"; edit_width = 40; }"
  "      spacer;"
  "      : text { key = \"h_line2\"; width = 42; }"
  "      : popup_list { key = \"line2\"; width = 42; }"
  "      : edit_box { key = \"line2_text\"; edit_width = 40; }"
  "      spacer;"
  "      : text { key = \"error\"; width = 42; }"
  "    }"
  "    : column {"
  "      : text { key = \"h_preview\"; width = 46; }"
  "      : image { key = \"preview\"; width = 46; height = 22; color = -15; }"
  "      : text { key = \"name1\"; width = 46; }"
  "      : text { key = \"name2\"; width = 46; }"
  "    }"
  "  }"
  "  ok_cancel;"
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

(defun pa:dlg-list (key items index)
  ;; Fills the popup list key with items and selects the one at index.
  (start_list key)
  (mapcar 'add_list items)
  (end_list)
  (set_tile key (itoa index)))

(defun pa:dlg-index (x xs) (cond ((vl-position x xs)) (0)))

(defun pa:settings-dialog (/ dcl f id stds std sizes size orients orient text-stds text-std
                             choices prefix prefix-text line2 line2-text focus ok
                             line2-empty refresh-sizes refresh draw)
  (setq stds '("skd" "spdb" "spdbv")
        text-stds '("skd" "spdb")
        choices '("std" "custom" "none")
        std (substr (pa:setting "List") 1 (vl-string-search "_" (pa:setting "List")))
        size (substr (pa:setting "List") (+ 2 (strlen std)) 2)
        orient (substr (pa:setting "List") (+ 4 (strlen std)) 1)
        text-std (pa:setting "Text")
        prefix (pa:setting "Prefix") prefix-text (vl-string-trim " " (pa:setting "PrefixText"))
        line2 (pa:setting "Line2") line2-text (vl-string-trim " " (pa:setting "Line2Text"))
        focus "list"
        line2-empty (pa:msg "settings.line2-empty" nil))
  (if (not (member std stds)) (setq std "spdbv" size "A3" orient "l"))
  (defun refresh-sizes ()
    ;; The sizes and orientations the chosen standard has, keeping the chosen ones where they exist.
    (setq sizes (pa:list-sizes std)
          size (if (member size sizes) size (car sizes))
          orients (pa:list-orients std size)
          orient (if (member orient orients) orient (car orients)))
    (pa:dlg-list "list_size" sizes (pa:dlg-index size sizes))
    (pa:dlg-list "list_orient" (mapcar 'pa:orient-name orients) (pa:dlg-index orient orients)))
  (defun draw (/ file w h)
    ;; The preview: the template being set and the name cell's text as it will be pasted.
    (setq file (if (= focus "list") (strcat "PDFALL_list_" std "_" size orient) (strcat "PDFALL_text_" text-std "_1"))
          w (dimx_tile "preview") h (dimy_tile "preview"))
    (start_image "preview")
    (fill_image 0 0 w h -15)
    (foreach s (pa:preview-lines file w h) (apply 'vector_image s))
    (end_image)
    (set_tile "h_preview" (if (= focus "list")
                            (pa:msg "settings.preview-list" (list "form" (pa:form-name file)))
                            (pa:msg "settings.preview-text" (list "std" (pa:std-name text-std)))))
    (set_tile "name1" (strcat (cond ((= prefix "none") "") ((= prefix "custom") (if (= prefix-text "") "" (strcat prefix-text " ")))
                                    ((strcat (pa:label "prefix") " ")))
                              (cond (*pdfall-marka*) ((pa:label "placeholder")))))
    (set_tile "name2" (if (= focus "list")
                        (cond ((= line2 "none") "") ((= line2 "custom") line2-text) ((pa:label "list-line2")))
                        "")))
  (defun refresh ()
    (mode_tile "prefix_text" (if (= prefix "custom") 0 1))
    (mode_tile "line2_text" (if (= line2 "custom") 0 1))
    (set_tile "error" "")
    (draw))

  (setq dcl (vl-filename-mktemp "pdfall.dcl")
        f (open dcl "w"))
  (foreach l *pa-dcl* (write-line l f))
  (close f)
  (setq id (load_dialog dcl))
  (if (not (new_dialog "pdfall_settings" id))
    (progn (unload_dialog id) (vl-file-delete dcl) (princ (strcat "\n" (pa:msg "settings.no-dialog" nil))) (exit)))
  (set_tile "dialog" (pa:msg "settings.title" nil))
  (set_tile "h_list" (pa:msg "settings.list" nil))
  (set_tile "h_text" (pa:msg "settings.text" nil))
  (set_tile "h_prefix" (pa:msg "settings.prefix" nil))
  (set_tile "h_line2" (pa:msg "settings.line2" nil))
  (pa:dlg-list "list_std" (mapcar 'pa:std-name stds) (pa:dlg-index std stds))
  (pa:dlg-list "text_std" (mapcar 'pa:std-name text-stds) (pa:dlg-index text-std text-stds))
  (pa:dlg-list "prefix" (list (pa:label "prefix") (pa:msg "settings.custom" nil) (pa:msg "settings.no-prefix" nil))
               (pa:dlg-index prefix choices))
  (pa:dlg-list "line2" (list (pa:label "list-line2") (pa:msg "settings.custom" nil) (pa:msg "settings.no-line2" nil))
               (pa:dlg-index line2 choices))
  (set_tile "prefix_text" prefix-text)
  (set_tile "line2_text" line2-text)
  (refresh-sizes)
  (refresh)
  (action_tile "list_std" "(setq std (nth (atoi $value) stds) focus \"list\") (refresh-sizes) (refresh)")
  (action_tile "list_size" "(setq size (nth (atoi $value) sizes) focus \"list\") (refresh-sizes) (refresh)")
  (action_tile "list_orient" "(setq orient (nth (atoi $value) orients) focus \"list\") (refresh)")
  (action_tile "text_std" "(setq text-std (nth (atoi $value) text-stds) focus \"text\") (refresh)")
  (action_tile "prefix" "(setq prefix (nth (atoi $value) choices)) (refresh)")
  (action_tile "line2" "(setq line2 (nth (atoi $value) choices)) (refresh)")
  (action_tile "prefix_text" "(setq prefix-text (vl-string-trim \" \" $value)) (draw)")
  (action_tile "line2_text" "(setq line2-text (vl-string-trim \" \" $value)) (draw)")
  (action_tile "accept"
    (strcat "(setq prefix-text (vl-string-trim \" \" (get_tile \"prefix_text\"))"
            "      line2-text (vl-string-trim \" \" (get_tile \"line2_text\")))"
            "(cond ((and (= prefix \"custom\") (pa:prefix-error prefix-text))"
            "       (set_tile \"error\" (pa:prefix-error prefix-text)) (mode_tile \"prefix_text\" 2))"
            "      ((and (= line2 \"custom\") (= line2-text \"\"))"
            "       (set_tile \"error\" line2-empty) (mode_tile \"line2_text\" 2))"
            "      (T (done_dialog 1)))"))
  (setq ok (= 1 (start_dialog)))
  (unload_dialog id)
  (vl-file-delete dcl)
  (if ok
    (progn
      (pa:set-setting "List" (strcat std "_" size orient))
      (pa:set-setting "Text" text-std)
      (pa:set-setting "Prefix" prefix)
      (pa:set-setting "PrefixText" prefix-text)
      (pa:set-setting "Line2" line2)
      (pa:set-setting "Line2Text" line2-text)))
  ok)

(defun c:PDFSETTINGS (/ *error*)
  (defun *error* (msg) (pa:report-crash "PDFSETTINGS" msg) (princ))
  (if (pa:settings-dialog)
    (princ (strcat "\n" (pa:msg "settings.saved" (list "form" (pa:form-name (pa:list-file))
                                                       "name" (pa:name-shown (cond (*pdfall-marka*) ((pa:label "placeholder"))))))))
    (princ (strcat "\n" (pa:msg "settings.unchanged" nil))))
  (princ))
