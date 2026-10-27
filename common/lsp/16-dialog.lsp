;;; ---- Dialogs ----------------------------------------------------------------
;;; Helpers for the plugin's DCL dialogs. Other files may call:
;;;   @:dcl-lines     a dialog's DCL lines with its @name@ labels put in
;;;   @:dlg-open @:dlg-close  write the DCL to a temporary file and open its dialog, and close it
;;;   @:dlg-list @:dlg-index  fill a popup list and find what to select in it
;;;   @:check-fill @:check-flip @:check-line  a list_box of ■ ticked and □ unticked lines
;;;
;;; set_tile can't change a button's label or the dialog's title, so those are written into the
;;; DCL file in the PC's code page, which AutoCAD reads it in, when that code page can hold them
;;; (@:code-page-p), and in English otherwise.

(defun @:code-page-p (s / path f back)
  ;; Whether a text file written here keeps s as it is: the PC's code page has its letters.
  (setq path (vl-filename-mktemp "@@NAME@@.txt") f (open path "w"))
  (write-line s f)
  (close f)
  (setq f (open path "r") back (read-line f))
  (close f)
  (vl-file-delete path)
  (= back s))

(defun @:dcl-string (s / out)
  ;; s as a DCL string, in quotes.
  (setq out "")
  (foreach c (vl-string->list s)
    (setq out (strcat out (if (member c '(34 92)) "\\" "") (chr c))))
  (strcat "\"" out "\""))

(defun @:dcl-lines (lines labels / ok)
  ;; lines with each @name@ of labels, ((name text english) ...), put in as a DCL string: the texts
  ;; when the PC's code page holds them all, else the English ones.
  (setq ok (@:code-page-p (apply 'strcat (mapcar 'cadr labels))))
  (@:log (list "dialog: labels in" (if ok "Ukrainian" "English") "| SYSCODEPAGE" (getvar "SYSCODEPAGE")))
  (mapcar '(lambda (l)
             (foreach lb labels
               (setq l (vl-string-subst (@:dcl-string (if ok (cadr lb) (caddr lb))) (strcat "@" (car lb) "@") l)))
             l)
          lines))

(defun @:dlg-open (lines name / dcl f id)
  ;; Writes lines to a temporary DCL file and opens its dialog name. Returns (id . file) for
  ;; @:dlg-close, or nil when there is no dialog: the console AutoCAD has no load_dialog at all.
  (setq dcl (vl-filename-mktemp "@@NAME@@.dcl") f (open dcl "w"))
  (foreach l lines (write-line l f))
  (close f)
  (setq id (if load_dialog (load_dialog dcl) -1))
  (@:log (list "dialog:" name dcl "load_dialog" id))
  (if (and (> id 0) (new_dialog name id))
    (cons id dcl)
    (progn (@:log "dialog: new_dialog failed") (if (> id 0) (unload_dialog id)) (vl-file-delete dcl) nil)))

(defun @:dlg-close (d) (unload_dialog (car d)) (vl-file-delete (cdr d)))

;;; A list_box of ■ ticked and □ unticked lines, since DCL has no list of check boxes and selecting
;;; several in a list_box needs Ctrl. A click flips a line, then the selection is cleared so that the
;;; next click on it counts too; the list_box is multiple_select only because that selection can be
;;; cleared.

(defun @:check-line (on text)
  (if on (@:msg "dialog.on" (list "item" text)) (@:msg "dialog.off" (list "item" text))))

(defun @:check-fill (key texts ons)
  ;; Fills the list_box key with texts, each ticked as ons says.
  (start_list key)
  (mapcar '(lambda (tx on) (add_list (@:check-line on tx))) texts ons)
  (end_list))

(defun @:check-flip (key value texts ons / picked j)
  ;; A click in the list_box key, value its $value: flips those lines. Returns the new ons.
  (setq picked (read (strcat "(" value ")")) j -1
        ons (mapcar '(lambda (on) (setq j (1+ j)) (if (member j picked) (not on) on)) ons))
  (foreach i picked (start_list key 1 i) (add_list (@:check-line (nth i ons) (nth i texts))) (end_list))
  (set_tile key "")
  ons)

(defun @:dlg-list (key items index)
  ;; Fills the popup list key with items and selects the one at index.
  (start_list key)
  (mapcar 'add_list items)
  (end_list)
  (set_tile key (itoa index)))

(defun @:dlg-index (x xs) (cond ((vl-position x xs)) (0)))
