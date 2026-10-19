# Cuts the three empty рамка templates that PDFLIST and PDFSPEC paste out of the sample drawing:
#   PDFALL_list.dwg    a лист (A3 landscape) with its title block
#   PDFALL_spec1.dwg   the first аркуш of a специфікація (A4 portrait, 40 mm title block + table)
#   PDFALL_spec2.dwg   a later аркуш of a специфікація (15 mm title block + table)
# Each holds the рамка, the title block form and the name cell (with МАРКА where the марка goes,
# made as wide and high as its cell and centred in it), but none of the drawing, dates or table
# contents that happen to be in the sample.
# The result is committed in src\templates, so this only has to run when the sample's title blocks
# change. It needs AutoCAD 2024 and examples\*.dxf (kept out of git).
# Usage: powershell -ExecutionPolicy Bypass -File src\make_templates.ps1
param(
    [string]$Dxf = (Get-ChildItem (Join-Path $PSScriptRoot '..\examples') -Filter '*.dxf' | Select-Object -First 1).FullName,
    [string]$Out = (Join-Path $PSScriptRoot 'templates'),
    [string]$Acad = 'C:\Program Files\Autodesk\AutoCAD 2024\accoreconsole.exe',
    [int]$Seconds = 180
)
$ErrorActionPreference = 'Stop'
New-Item $Out -ItemType Directory -Force | Out-Null
$Out = (Resolve-Path $Out).Path
$work = Join-Path $env:TEMP 'pdfall-templates'
if (Test-Path $work) { Remove-Item $work -Recurse -Force }
New-Item $work -ItemType Directory | Out-Null
Copy-Item $Dxf (Join-Path $work 'sample.dxf')
foreach ($n in 'list', 'spec1', 'spec2') { Remove-Item (Join-Path $Out "PDFALL_$n.dwg") -ErrorAction SilentlyContinue }

# AutoCAD script lines can't hold a blank line, so the work is done by a loaded .lsp file.
# Both are UTF-8 with BOM so the Cyrillic survives.
$o = $Out -replace '\\', '/'
$lisp = @"
;; Model space is searched whole (a window pick would depend on the sample's current view and layout).
;; The layers and the window pick the form; texts that are content (not the form's own labels) are dropped.
(defun in-window (d llx lly w / ok)
  (setq ok T)
  (foreach k (if (= (cdr (assoc 0 d)) "LINE") '(10 11) '(10))
    (if (and ok (assoc k d))
      (setq ok (and (<= (- llx 0.5) (cadr (assoc k d)) (+ llx w 0.5))
                    (<= (- lly 0.5) (caddr (assoc k d)) (+ lly 297.5))))))
  ok)

;; The form's own labels are in the style основная надпись (the dates written in it are smaller) and
;; the table's column heads in стиль1 at 3.5 mm; everything else in стиль1 is what a specification says.
(defun form-text-p (d / style h)
  (setq style (cdr (assoc 7 d)) h (cdr (assoc 40 d)))
  (or (and (= style "основная надпись") (>= h 3.0))
      (and (= style "стиль1") (>= h 3.5))))

;; (x1 y1 x2 y2) of every LINE and LWPOLYLINE segment in ss.
(defun segs (ss / i d out pts)
  (setq i (sslength ss))
  (while (> i 0)
    (setq i (1- i) d (entget (ssname ss i)))
    (cond
      ((= (cdr (assoc 0 d)) "LINE")
       (setq out (cons (list (cadr (assoc 10 d)) (caddr (assoc 10 d)) (cadr (assoc 11 d)) (caddr (assoc 11 d))) out)))
      ((= (cdr (assoc 0 d)) "LWPOLYLINE")
       (setq pts nil)
       (foreach g d (if (= (car g) 10) (setq pts (cons (cdr g) pts))))
       (setq pts (reverse pts))
       (if (= 1 (logand 1 (cdr (assoc 70 d)))) (setq pts (append pts (list (car pts)))))
       (while (cadr pts)
         (setq out (cons (list (caar pts) (cadar pts) (caadr pts) (cadadr pts)) out) pts (cdr pts))))))
  out)

;; The cell around the point (px py): (left bottom right top) from the nearest lines on each side.
(defun cell (segs px py / left right bottom top)
  (foreach s segs
    (cond
      ((and (< (abs (- (car s) (caddr s))) 0.01) (<= (min (cadr s) (cadddr s)) py (max (cadr s) (cadddr s))))
       (if (< (car s) px)
         (if (or (null left) (> (car s) left)) (setq left (car s)))
         (if (or (null right) (< (car s) right)) (setq right (car s)))))
      ((and (< (abs (- (cadr s) (cadddr s))) 0.01) (<= (min (car s) (caddr s)) px (max (car s) (caddr s))))
       (if (< (cadr s) py)
         (if (or (null bottom) (> (cadr s) bottom)) (setq bottom (cadr s)))
         (if (or (null top) (< (cadr s) top)) (setq top (cadr s)))))))
  (if (and left right bottom top) (list left bottom right top)))

;; The name MTEXT made to fill its cell: anchored at the cell's centre (attachment 5), as wide and as
;; high as the cell, so it stays on one line and wraps only when the марка is too long for the cell.
(defun fit (d segs name / w h at col row c)
  (setq w (cond ((/= 0.0 (cdr (assoc 41 d))) (cdr (assoc 41 d))) ((cdr (assoc 42 d))))
        h (cond ((cdr (assoc 43 d))) (0.0))
        at (cdr (assoc 71 d)) col (rem (1- at) 3) row (/ (1- at) 3)
        c (cell segs (+ (cadr (assoc 10 d)) (* w (- 0.5 (* 0.5 col)))) (+ (caddr (assoc 10 d)) (* h (- (* 0.5 row) 0.5)))))
  (if (null c) (progn (princ (strcat "\nTEMPLATE-FAIL " name ": no cell around the name")) (exit)))
  (princ (strcat "\nTEMPLATE " name ": name cell " (rtos (- (caddr c) (car c)) 2 2) " x " (rtos (- (cadddr c) (cadr c)) 2 2)))
  (setq d (subst (cons 71 5) (assoc 71 d) d)
        d (subst (list 10 (/ (+ (car c) (caddr c)) 2.0) (/ (+ (cadr c) (cadddr c)) 2.0) 0.0) (assoc 10 d) d)
        d (subst (cons 41 (- (caddr c) (car c))) (assoc 41 d) d))
  ;; An MTEXT with columns (the лист's name cell in the sample has them, though entget doesn't show
  ;; them) takes its width from the column width, so the columns are turned off (75 = 0).
  (setq d (if (assoc 75 d) (subst (cons 75 0) (assoc 75 d) d) (append d (list (cons 75 0)))))
  (if (assoc 46 d)
    (subst (cons 46 (- (cadddr c) (cadr c))) (assoc 46 d) d)
    (append d (list (cons 46 (- (cadddr c) (cadr c)))))))

(defun mk (name llx lly w / all ss i d keep s a b)
  (setq all (ssget "_X" (list '(410 . "Model") (cons 8 "Формат чертежа,Defpoints"))) ss (ssadd) i (sslength all))
  (while (> i 0)
    (setq i (1- i) d (entget (ssname all i)))
    (if (and (in-window d llx lly w)
             (not (and (= (cdr (assoc 0 d)) "TEXT") (not (form-text-p d)))))
      (ssadd (ssname all i) ss)))
  (if (= 0 (sslength ss)) (progn (princ (strcat "\nTEMPLATE-FAIL " name ": nothing in the window")) (exit)))
  ;; the name cell: the MTEXT "Джгут <марка>" in the title block's corner
  (setq all (ssget "_X" '((410 . "Model") (0 . "MTEXT") (8 . "0"))) i (sslength all) keep nil)
  (while (> i 0)
    (setq i (1- i) d (entget (ssname all i)) s (cdr (assoc 1 d)))
    (if (and (vl-string-search "Джгут " s)
             (<= (- (+ llx w) 195.0) (cadr (assoc 10 d)) (+ llx w))
             (<= lly (caddr (assoc 10 d)) (+ lly 60.0)))
      (setq keep (cons (cons (ssname all i) d) keep))))
  (if (/= (length keep) 1) (progn (princ (strcat "\nTEMPLATE-FAIL " name ": name cells " (itoa (length keep)))) (exit)))
  (setq d (cdar keep) s (cdr (assoc 1 d))
        a (+ (vl-string-search "Джгут " s) 6)
        b (vl-string-search "\\P" s a))
  (entmod (fit (subst (cons 1 (strcat (substr s 1 a) "МАРКА" (if b (substr s (1+ b)) ""))) (assoc 1 d) d)
               (segs ss) name))
  (ssadd (caar keep) ss)
  (princ (strcat "\nTEMPLATE " name ": " (itoa (sslength ss)) " objects"))
  (command "_.-WBLOCK" (strcat "$o/" name ".dwg") "" (list llx lly 0.0) ss ""))
"@
$lispPath = Join-Path $work 'make.lsp'
[IO.File]::WriteAllText($lispPath, $lisp, (New-Object Text.UTF8Encoding($true)))

# The lower-left corners of the sample's рамки that make the cleanest templates.
$lp = $lispPath -replace '\\', '/'
$scr = @"
(setvar "FILEDIA" 0)
(setvar "CMDECHO" 0)
(setvar "INSUNITS" 0)
(load "$lp")
(mk "PDFALL_list" 1823.210660030745 2110.720724986636 420.0)
(mk "PDFALL_spec1" 2267.449286520352 2110.720724986636 210.0)
(mk "PDFALL_spec2" 2934.880218674831 1476.600519115046 210.0)
(princ "\nEND-OF-TEMPLATES")
QUIT
Y
"@
$scrPath = Join-Path $work 'make.scr'
[IO.File]::WriteAllText($scrPath, $scr, (New-Object Text.UTF8Encoding($true)))

$outTxt = Join-Path $work 'acad.txt'
$acadArgs = "/i `"$(Join-Path $work 'sample.dxf')`" /s `"$scrPath`" /l en-US /isolate pdfalltemplates `"$(Join-Path $work 'user')`""
$p = Start-Process $Acad -ArgumentList $acadArgs -WorkingDirectory $work -RedirectStandardOutput $outTxt -PassThru -NoNewWindow
$deadline = (Get-Date).AddSeconds($Seconds)
while (-not $p.WaitForExit(2000)) {
    $sofar = try {
        $fs = [IO.File]::Open($outTxt, 'Open', 'Read', 'ReadWrite')
        try { (New-Object IO.StreamReader($fs, [Text.Encoding]::Unicode)).ReadToEnd() } finally { $fs.Close() }
    } catch { '' }
    if ($sofar -match 'Command: QUIT') { Start-Sleep 5; if (-not $p.HasExited) { $p.Kill() }; break }
    if ((Get-Date) -gt $deadline) { $p.Kill(); throw 'accoreconsole timed out' }
}
Start-Sleep -Milliseconds 300
$log = [IO.File]::ReadAllText($outTxt, [Text.Encoding]::Unicode)
$log -split "`r?`n" | Where-Object { $_ -match 'TEMPLATE|error' } | ForEach-Object { Write-Host $_ }
foreach ($n in 'list', 'spec1', 'spec2') {
    $f = Join-Path $Out "PDFALL_$n.dwg"
    if (-not (Test-Path $f)) { throw "PDFALL_$n.dwg was not written; see $outTxt" }
}
Write-Host "Templates written to $Out"
