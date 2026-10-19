# Cuts the three empty рамка templates that PDFLIST and PDFSPEC paste out of the sample drawing:
#   PDFALL_list.dwg    a лист (A3 landscape) with its title block
#   PDFALL_spec1.dwg   the first аркуш of a специфікація (A4 portrait, 40 mm title block + table)
#   PDFALL_spec2.dwg   a later аркуш of a специфікація (15 mm title block + table)
# Each holds the рамка, the title block form and the name cell (with МАРКА where the марка goes),
# but none of the drawing, dates or table contents that happen to be in the sample.
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
  (entmod (subst (cons 1 (strcat (substr s 1 a) "МАРКА" (if b (substr s (1+ b)) ""))) (assoc 1 d) d))
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
