# End-to-end test of the built PDFALL.bundle without opening AutoCAD:
#   1. on examples\Креслення приклад.dxf: PDFNUM (to fill the empty counters) and PDFALL in accoreconsole
#      with a throwaway AutoCAD profile, then merge.exe on the PDFs;
#   2. on the old project drawings in examples\old, if there are any: PDFNUM, PDFALL and merge.exe,
#      and a paper size AutoCAD refuses;
#   3. in an empty drawing: PDFLIST and PDFSPEC paste рамки, PDFNUM numbers them and PDFALL plots them;
#   4. in another: every one of the 28 templates pasted, with each choice of name-cell text, then
#      PDFNUM, PDFALL (each PDF on paper of its рамка's size) and merge.exe;
#   5. the шари заливки chosen in the settings, an xref's among them;
#   6. the ribbon tab.
# Usage: powershell -ExecutionPolicy Bypass -File tests\run.ps1   (run build.bat first)
param(
    [string]$Contents = (Join-Path $PSScriptRoot '..\dist\PDFALL.bundle\Contents'),
    [string]$Work = (Join-Path $env:TEMP 'pdfall-test'),
    [string]$Acad = 'C:\Program Files\Autodesk\AutoCAD 2024\accoreconsole.exe',
    [int]$Seconds = 300
)
$ErrorActionPreference = 'Stop'
$Contents = (Resolve-Path $Contents).Path
$failures = @()
function Check($ok, $what) {
    if ($ok) { Write-Host "  ok    $what" } else { Write-Host "  FAIL  $what"; $script:failures += $what }
}

# Runs an AutoCAD script in accoreconsole (on $Dxf, or on an empty drawing) with a throwaway profile
# and returns its log. The script is UTF-8 with BOM so Cyrillic survives.
function Invoke-Acad($Name, $ScriptText, $Dxf) {
    $dir = Join-Path $Work $Name
    New-Item $dir -ItemType Directory -Force | Out-Null
    $scrPath = Join-Path $dir 'run.scr'
    [IO.File]::WriteAllText($scrPath, $ScriptText, (New-Object Text.UTF8Encoding($true)))
    $out = Join-Path $dir 'acad.txt'
    $open = if ($Dxf) { "/i `"$Dxf`" " } else { '' }
    $acadArgs = "$($open)/s `"$scrPath`" /l en-US /isolate pdfall$Name `"$(Join-Path $dir 'user')`""
    $p = Start-Process $Acad -ArgumentList $acadArgs -WorkingDirectory $dir -RedirectStandardOutput $out -PassThru -NoNewWindow
    # With /isolate, accoreconsole sometimes never exits after QUIT, so stop it once the script is done.
    $deadline = (Get-Date).AddSeconds($Seconds)
    while (-not $p.WaitForExit(2000)) {
        $sofar = try {
            $fs = [IO.File]::Open($out, 'Open', 'Read', 'ReadWrite')
            try { (New-Object IO.StreamReader($fs, [Text.Encoding]::Unicode)).ReadToEnd() } finally { $fs.Close() }
        } catch { '' }
        if ($sofar -match 'Command: QUIT') { Start-Sleep 5; if (-not $p.HasExited) { $p.Kill() }; break }
        if ((Get-Date) -gt $deadline) { $p.Kill(); $script:failures += "accoreconsole timed out ($Name)"; break }
    }
    Start-Sleep -Milliseconds 300
    $log = [IO.File]::ReadAllText($out, [Text.Encoding]::Unicode)
    [IO.File]::WriteAllText($out, $log, (New-Object Text.UTF8Encoding($false)))
    $log
}

if (Test-Path $Work) { Remove-Item $Work -Recurse -Force }
$plotters = Join-Path $Work 'Plotters'
New-Item $plotters -ItemType Directory -Force | Out-Null
$dxf = Get-ChildItem (Join-Path $PSScriptRoot '..\examples') -Filter '*.dxf' | Select-Object -First 1
Copy-Item $dxf.FullName (Join-Path $Work 'sample.dxf')

# LISP shared by both drawings: the texts reading some date in Model space, and whether a рамка has
# the day's date.
$dateLisp = @"
(defun date-ents (s / ss i out)
  (if (setq ss (ssget "_X" (list '(0 . "TEXT") (cons 1 s) '(410 . "Model"))))
    (repeat (setq i (sslength ss)) (setq out (cons (ssname ss (setq i (1- i))) out))))
  out)
(defun date-count (s) (length (date-ents s)))
(defun dated-p (r / ll ur)
  (setq ll (pa:get 'll r) ur (pa:get 'ur r))
  (vl-some '(lambda (e / p) (setq p (cdr (assoc 10 (entget e))))
              (and (< (car ll) (car p) (car ur)) (< (cadr ll) (cadr p) (cadr ur))))
           (date-ents (pa:today))))
"@

# AutoCAD script: forward slashes in paths.
$w = $Work -replace '\\', '/'
$c = $Contents -replace '\\', '/'
$scr = @"
(setvar "SECURELOAD" 0)
(setenv "PrinterConfigDir" "$($plotters -replace '\\', '\\')")
(command "_.SAVEAS" "2018" "$w/sample.dwg")
(setq *pdfall-home* "$($Contents -replace '\\', '\\')")
(load "$c/pdfall.lsp")
(foreach s *pa-setting-defaults* (pa:set-setting (car s) (cdr s)))
(setq *pdfall-merge* nil)
$dateLisp
;; Counts the рамки that have the day's date while they are plotted.
(setq pa:plot0 pa:plot dated-plots 0)
(defun pa:plot (r path) (if (dated-p r) (setq dated-plots (1+ dated-plots))) (pa:plot0 r path))
PDFNUM
(princ "SECOND-PDFNUM")
PDFNUM
(princ (strcat "\nOLD-BEFORE=" (itoa (date-count "11.09.2026"))))
PDFALL
(princ (strcat "\nDATED-PLOTS=" (itoa dated-plots) " TODAY-LEFT=" (itoa (date-count (pa:today))) " OLD-AFTER=" (itoa (date-count "11.09.2026"))))
(princ "\nEND-OF-TEST")
QUIT
Y
"@

# PDFs under the names of earlier versions, which PDFALL must clear away before it plots.
$oldNames = 'К1 лист 1.pdf', 'К1 лист 1 без заливки.pdf', 'К1 лист 2.pdf', 'К1 специфікація лист 1.pdf', 'К1 Загальний.pdf', 'К1 Загальний друк.pdf'
New-Item (Join-Path $Work 'exported files\К1') -ItemType Directory -Force | Out-Null
foreach ($n in $oldNames) { Set-Content (Join-Path $Work "exported files\К1\$n") 'old' }

Write-Host "PDFNUM and PDFALL in accoreconsole ($Work)..."
$log = Invoke-Acad 'sample' $scr (Join-Path $Work 'sample.dxf')
$out = Join-Path $Work 'sample\acad.txt'

$exported = Join-Path $Work 'exported files'
$pdfs = @(Get-ChildItem $exported -Recurse -Filter '*.pdf' -ErrorAction SilentlyContinue)
$first, $second = $log -split 'SECOND-PDFNUM', 2
Check ($log -match 'END-OF-TEST') 'the script ran to the end'
Check ($first -match 'PDFNUM записав номери:') 'PDFNUM filled in the empty counters'
Check ($first -match 'К1 специфікація 2: Аркуш 2') 'К1 специфікація 2 got Аркуш 2'
Check ($first -match '1П лист 1: Аркуш 1, Аркушів 1') '1П лист 1 got Аркуш 1, Аркушів 1'
Check ($first -notmatch 'К1 лист') 'К1 листи, already numbered, were left alone'
Check ($second -match 'PDFNUM: усі номери') 'a second PDFNUM finds nothing left to fill or fix'
Check ($log -notmatch 'клітинк[аи] Аркуш\S* порожн') 'PDFALL finds no empty counters'
Check ($log -match 'PDFALL: 34 PDF у') 'PDFALL reports 34 PDFs'
Check ($pdfs.Count -eq 34) "34 PDFs on disk (found $($pdfs.Count))"
Check (Test-Path (Join-Path $plotters 'PDFALL.pc3')) 'PDFALL.pc3 was copied into the Plotters folder'
Check ($log -notmatch 'відкриється в переглядачі') 'PDFALL.pc3 was used in the same run'
Check (Test-Path (Join-Path $exported 'К1\К1 лист 01 без заливки.pdf')) 'К1 лист 01 без заливки.pdf exists'
Check (Test-Path (Join-Path $exported 'К1\К1 специфікація 02.pdf')) 'К1 специфікація 02.pdf exists'
$left = @(Get-ChildItem (Join-Path $exported 'К1') -Filter '*.pdf' | Where-Object { $_.Length -lt 100 })
Check ($left.Count -eq 0) "the $($oldNames.Count) PDFs under earlier names were cleared away (left: $($left.Name -join ', '))"
Check (@(Get-ChildItem $exported -Recurse -Filter '*.pdf' | Where-Object { $_.Name -cmatch '[A-ZА-ЯІЇЄҐ][а-яіїєґ]+\.pdf$|лист \d[ .]|специфікація (лист )?\d[ .]' }).Count -eq 0) 'every exported name is lower case with two-digit sheet numbers'
$oldBefore = if ($log -match 'OLD-BEFORE=(\d+)') { [int]$Matches[1] } else { -1 }
Check ($log -match 'DATED-PLOTS=34 ' ) 'every one of the 34 PDFs was plotted with the day''s date'
Check ($oldBefore -gt 0 -and $log -match "TODAY-LEFT=0 OLD-AFTER=$oldBefore\b") "the $oldBefore dates already in the drawing are back as they were, and no new date is left"

Write-Host 'merge.exe on the exported files...'
$mergeOut = Join-Path $Work 'merge.txt'
$scrPath = Join-Path $Work 'sample\run.scr'
$m = Start-Process (Join-Path $Contents 'merge.exe') -ArgumentList "`"$exported`"" -RedirectStandardInput $scrPath `
    -RedirectStandardOutput $mergeOut -PassThru -NoNewWindow
$null = $m.Handle
if (-not $m.WaitForExit(120000)) { $m.Kill(); $script:failures += 'merge.exe timed out' }
$merged = @(Get-ChildItem $exported -Recurse -Filter '*загальний*.pdf')
$markas = @(Get-ChildItem $exported -Directory)
Check ($m.ExitCode -eq 0) "merge.exe exit code 0 (got $($m.ExitCode))"
$mergeLog = Get-Content $mergeOut -Raw -Encoding UTF8
Check ($mergeLog -notmatch 'Не вдалося звірити') 'merge.exe reads every Аркуш back from the PDFs'
Check ($merged.Count -eq 2 * $markas.Count) "загальний and загальний друк for each of $($markas.Count) марки (found $($merged.Count))"
Check (@($merged | Where-Object { $_.Name -cmatch ' загальний( друк)?\.pdf$' }).Count -eq $merged.Count) 'every merged file is named in lower case'

# A folder of PDFs under the names of earlier versions: merge.exe offers to rename them (answer y).
$oldDir = Join-Path $Work 'oldnames\К1'
New-Item $oldDir -ItemType Directory -Force | Out-Null
Get-ChildItem (Join-Path $exported 'К1') -Filter '*.pdf' | Where-Object { $_.Name -notmatch 'загальний' } | ForEach-Object {
    $n = $_.Name -replace ' лист 0(\d)', ' лист $1' -replace 'специфікація 0(\d)', 'специфікація лист $1'
    Copy-Item $_.FullName (Join-Path $oldDir $n)
}
$oldCount = @(Get-ChildItem $oldDir).Count
$answers = Join-Path $Work 'answers.txt'
[IO.File]::WriteAllText($answers, "y`ny`n", (New-Object Text.UTF8Encoding($false)))
$m2 = Start-Process (Join-Path $Contents 'merge.exe') -ArgumentList "`"$(Join-Path $Work 'oldnames')`"" -RedirectStandardInput $answers `
    -RedirectStandardOutput (Join-Path $Work 'merge-old.txt') -PassThru -NoNewWindow
$null = $m2.Handle
if (-not $m2.WaitForExit(120000)) { $m2.Kill(); $script:failures += 'merge.exe (old names) timed out' }
$oldNow = @(Get-ChildItem $oldDir | Where-Object { $_.Name -cmatch 'лист \d[ .]|специфікація лист' })
Check ($oldNow.Count -eq 0 -and (Test-Path (Join-Path $oldDir 'К1 лист 01.pdf')) -and (Test-Path (Join-Path $oldDir 'К1 специфікація 01.pdf'))) "merge.exe renamed the $oldCount PDFs under earlier names to the new ones"
Check ((Test-Path (Join-Path $oldDir 'К1 загальний.pdf')) -and (Test-Path (Join-Path $oldDir 'К1 загальний друк.pdf'))) 'and built загальний and загальний друк from them'

# Old project drawings (examples\old\*.dwg, real drawings kept out of git): the марка alone in the
# name cell, Аркушів spelled with a Latin i and its number after it in the same row, no шар заливки,
# and in М5 an A4 лист (a Складальний кресленик) whose рамка is 210x295.
$oldDwgs = @(Get-ChildItem (Join-Path $PSScriptRoot '..\examples\old') -Filter '*.dwg' -ErrorAction SilentlyContinue)
if ($oldDwgs.Count -eq 0) { Write-Host '  skip  old drawings: examples\old has no .dwg' }
foreach ($dwg in $oldDwgs) {
    $n = $dwg.BaseName -replace '[МM]', 'M'
    Write-Host "Old drawing $($dwg.Name)..."
    $dir = Join-Path $Work "old\$n"
    New-Item $dir -ItemType Directory -Force | Out-Null
    $copy = Join-Path $dir $dwg.Name
    Copy-Item -LiteralPath $dwg.FullName $copy
    $oldScr = @"
(setvar "SECURELOAD" 0)
(setenv "PrinterConfigDir" "$($plotters -replace '\\', '\\')")
(setq *pdfall-home* "$($Contents -replace '\\', '\\')")
(load "$c/pdfall.lsp")
(foreach s *pa-setting-defaults* (pa:set-setting (car s) (cdr s)))
(setq *pdfall-merge* nil)
(defun show (tag / d)
  (setq d (pa:read-drawing))
  (foreach r (car d) (princ (strcat "\n" tag " " (pa:get 'kind r) " " (pa:get 'marka r) " " (car (pa:paper r)) " sheet=" (vl-princ-to-string (pa:get 'sheet r)) " total=" (vl-princ-to-string (pa:get 'total r)))))
  (foreach p (cadr d) (princ (strcat "\n" tag " problem: " (car p)))))
(show "BEFORE")
PDFNUM
(show "AFTER")
PDFALL
(princ "\nEND-OF-TEST")
QUIT
Y
"@
    $olog = Invoke-Acad "old$n" $oldScr $copy
    $a4 = $n -eq 'M5'
    $paper = if ($a4) { 'A4' } else { 'A3' }
    $oldPdfs = @(Get-ChildItem (Join-Path $dir 'exported files') -Recurse -Filter '*.pdf' -ErrorAction SilentlyContinue)
    Check ($olog -match 'END-OF-TEST') "$($dwg.Name): the script ran to the end"
    Check ($olog -match "BEFORE list $n $paper sheet=nil total=1" -and $olog -notmatch 'BEFORE.*problem') `
        "$($dwg.Name): one $paper лист of марка $n, Аркуш empty and Аркушів 1 read after its label"
    Check ($olog -match "AFTER list $n $paper sheet=1 total=1") "$($dwg.Name): PDFNUM writes Аркуш 1 after the label, and PDFALL reads it back"
    Check ($olog -match 'не вибрано шару заливки' -and $olog -match "PDFALL: 2 PDF у" -and $oldPdfs.Count -eq 2) `
        "$($dwg.Name): with no шар заливки, the лист and its без заливки copy are plotted (found $($oldPdfs.Count) PDFs)"
    Check ($olog -notmatch 'Unknown command|Помилка') "$($dwg.Name): no unknown command and no error"
    Check ($olog -notmatch 'клітинку під заголовком Дата|у клітинці Дата написано') "$($dwg.Name): the date goes in the Дата cell"
    if ($a4) {
        Check ($olog -match '210x295 замість 210x297') 'M5: the 210x295 рамка is plotted with a warning'
        $pdf = Get-ChildItem (Join-Path $dir 'exported files') -Recurse -Filter '*лист 01.pdf' | Select-Object -First 1
        $box = if ($pdf -and ([Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($pdf.FullName)) -match '/MediaBox\s*\[\s*0\s+0\s+([\d.]+)\s+([\d.]+)')) { [double]$Matches[1], [double]$Matches[2] }
        Check ($box -and [math]::Abs($box[0] - 595.3) -lt 2 -and [math]::Abs($box[1] - 841.9) -lt 2) "M5: the A4 лист is plotted on A4 portrait (MediaBox $box)"
    } else {
        Check ($olog -notmatch 'замість') "$($dwg.Name): its 420x297 рамка gets no size warning"
    }
}
if ($oldDwgs.Count) {
    Write-Host 'merge.exe on the old drawings...'
    $answers = Join-Path $Work 'answers-old.txt'
    [IO.File]::WriteAllText($answers, "n`nn`nn`nn`n`n", (New-Object Text.UTF8Encoding($false)))
    $mergeOld = Join-Path $Work 'merge-oldplots.txt'
    $m3 = Start-Process (Join-Path $Contents 'merge.exe') -ArgumentList "`"$(Join-Path $Work 'old')`"" -RedirectStandardInput $answers `
        -RedirectStandardOutput $mergeOld -PassThru -NoNewWindow
    $null = $m3.Handle
    if (-not $m3.WaitForExit(120000)) { $m3.Kill(); $script:failures += 'merge.exe (old drawings) timed out' }
    $mlog = Get-Content $mergeOld -Raw -Encoding UTF8
    $oldMerged = @(Get-ChildItem (Join-Path $Work 'old') -Recurse -Filter '*загальний*.pdf')
    Check ($oldMerged.Count -eq 2 * $oldDwgs.Count) "merge.exe builds загальний and загальний друк for each old drawing (found $($oldMerged.Count))"
    Check ($mlog -notmatch 'Не вдалося звірити|НЕ збігається') 'merge.exe reads the марка and Аркуш of the old title blocks back from the PDFs'

    # A paper size AutoCAD doesn't know, as a Russian AutoCAD didn't know the English names: PDFALL
    # stops with a message instead of feeding the rest of -PLOT to the command line.
    $dwg = $oldDwgs[0]
    $dir = Join-Path $Work 'refused'
    New-Item $dir -ItemType Directory -Force | Out-Null
    $copy = Join-Path $dir $dwg.Name
    Copy-Item -LiteralPath $dwg.FullName $copy
    $refusedScr = @"
(setvar "SECURELOAD" 0)
(setenv "PrinterConfigDir" "$($plotters -replace '\\', '\\')")
(setq *pdfall-home* "$($Contents -replace '\\', '\\')")
(load "$c/pdfall.lsp")
(foreach s *pa-setting-defaults* (pa:set-setting (car s) (cdr s)))
(setq *pdfall-merge* nil *pdfall-paper* "No such paper")
PDFNUM
PDFALL
(princ "\nEND-OF-TEST")
QUIT
Y
"@
    $rlog = Invoke-Acad 'refused' $refusedScr $copy
    $refusedPdfs = @(Get-ChildItem (Join-Path $dir 'exported files') -Recurse -Filter '*.pdf' -ErrorAction SilentlyContinue)
    Check ($rlog -match 'END-OF-TEST' -and $rlog -match 'не прийняв розмір паперу No such paper' -and $refusedPdfs.Count -eq 0) `
        'a paper size AutoCAD refuses stops PDFALL with a message'
    Check ($rlog -notmatch 'Unknown command') 'and no answer meant for -PLOT runs as a command'
}

Write-Host 'PDFLIST and PDFSPEC in an empty drawing...'
$pasteDir = Join-Path $Work 'paste'
$pasteHome = Join-Path $pasteDir 'home'
New-Item (Join-Path $pasteDir 'Plotters') -ItemType Directory -Force | Out-Null
Copy-Item $Contents $pasteHome -Recurse
$ph = $pasteHome -replace '\\', '/'
# The commands end a run on Esc, which also stops an AutoCAD script, so the checks drive the same
# functions with a pick that stops after n рамки. The points are the lines that follow.
$pasteScr = @"
(setvar "SECURELOAD" 0)
(setenv "PrinterConfigDir" "$((Join-Path $pasteDir 'Plotters') -replace '\\', '\\')")
(setq *pdfall-home* "$($pasteHome -replace '\\', '\\')")
(load "$ph/pdfall.lsp")
(foreach s *pa-setting-defaults* (pa:set-setting (car s) (cdr s)))
(setq *pdfall-merge* nil)
(defun tpaste (cmd marka n file / kind)
  (setq placed 0 undo-open nil kind (cond ((wcmatch file "*list*") "list") ((wcmatch file "*spec*") "spec") ("text")))
  (pa:paste-start)
  (vl-catch-all-apply '(lambda () (pa:paste-run cmd marka kind '(lambda (i) (if (< i n) (cons file "t") (exit))))))
  (pa:paste-cleanup)
  (princ (strcat "\nPLACED=" (itoa placed))))
(defun report (/ d rs)
  (setq d (pa:read-drawing)
        rs (append (car d) (vl-remove nil (mapcar 'cdr (cadr d)))))
  (princ (strcat "\nFRAMES=" (itoa (length rs))))
  (foreach r rs
    (foreach z (pa:get 'zone r) (if (wcmatch (caddr z) "*Джгут*") (princ (strcat "\nNAME=" (cadddr z))))))
  (princ (strcat "\nCLAYER=" (getvar "CLAYER"))))
(defun decoy (/ r z f p)
  (foreach x (car (pa:read-drawing))
    (if (= (pa:get 'kind x) "spec")
      (foreach y (pa:get 'zone x)
        (if (and (null z) (equal (pa:words (caddr y)) '("Арк.")) (< (car y) -25.0)) (setq z y r x)))))
  (if z
    (progn
      (setq f (pa:get 'frame r) p (list (+ (car z) (caddr f)) (+ (cadr z) (cadr f) -5.0) 0.0))
      (entmake (list '(0 . "TEXT") '(8 . "0") (cons 10 p) (cons 11 p) '(72 . 1) '(73 . 2) '(40 . 9.0) '(51 . 0.2618) '(1 . "7")))))
  (princ (strcat "\nDECOY=" (if z "1" "0"))))
(defun slant (/ ss i d n up tall)
  (setq ss (ssget "_X" '((0 . "TEXT") (410 . "Model"))) i 0 n 0 up 0 tall 0)
  (while (< i (sslength ss))
    (setq d (entget (ssname ss i)) i (1+ i))
    (if (wcmatch (cdr (assoc 1 d)) "#,##")
      (setq n (1+ n) up (if (< (abs (cdr (assoc 51 d))) 0.01) (1+ up) up)
            tall (if (< (abs (- (cdr (assoc 40 d)) 9.0)) 0.1) (1+ tall) tall))))
  (princ (strcat "\nNUMBERS=" (itoa n) " UPRIGHT=" (itoa up) " TALL=" (itoa tall))))
(defun edge (lines v w / lo hi)
  (foreach s lines
    (if (<= (cadr s) w (caddr s))
      (if (< (car s) v) (if (or (null lo) (> (car s) lo)) (setq lo (car s))) (if (or (null hi) (< (car s) hi)) (setq hi (car s))))))
  (if (and lo hi) (list lo hi)))
(defun mid-p (v e) (and e (< (abs (- v (/ (+ (car e) (cadr e)) 2.0))) 0.05)))
(defun in-cell-p (r d p / x y hx vy)
  (setq x (- (car p) (caddr (pa:get 'frame r))) y (- (cadr p) (cadr (pa:get 'frame r)))
        hx (edge (pa:get 'cells r) x y) vy (edge (pa:get 'rows r) y x))
  (cond
    ((and (mid-p x hx) (mid-p y vy)
          (or (= (cdr (assoc 0 d)) "TEXT") (and (= (cdr (assoc 71 d)) 5) (< (abs (- (cdr (assoc 41 d)) (- (cadr hx) (car hx)))) 0.05)))))
    (T (princ (strcat "\nOFF-CENTRE " (pa:get 'kind r) " " (cdr (assoc 0 d)) " at " (rtos x 2 2) "," (rtos y 2 2) " cell x " (vl-princ-to-string hx) " y " (vl-princ-to-string vy) " 71=" (vl-princ-to-string (cdr (assoc 71 d))) " 41=" (vl-princ-to-string (cdr (assoc 41 d))))) nil)))
(defun centred (/ names nok nums mok d)
  (setq names 0 nok 0 nums 0 mok 0)
  (foreach r (car (pa:read-drawing))
    (foreach z (pa:get 'zone r)
      (if (and (wcmatch (caddr z) "*Джгут*") (nth 4 z))
        (setq d (entget (nth 4 z)) names (1+ names) nok (if (in-cell-p r d (cdr (assoc 10 d))) (1+ nok) nok))))
    (foreach c (pa:get 'counters r)
      (if (and (cadddr c) (nth 4 (cadddr c)))
        (setq d (entget (nth 4 (cadddr c))) nums (1+ nums) mok (if (in-cell-p r d (cdr (assoc 11 d))) (1+ mok) mok)))))
  (princ (strcat "\nNAMES=" (itoa nok) "/" (itoa names) " NUMS=" (itoa mok) "/" (itoa nums))))
$dateLisp
(defun dates (/ dated warnings n ok head d)
  (setq n 0 ok 0)
  (pa:date-add (car (pa:read-drawing)))
  (foreach r (car (pa:read-drawing))
    (setq head (pa:date-head r))
    (foreach z (pa:get 'zone r)
      (if (and (= (cadddr z) (pa:today)) (nth 4 z))
        (progn
          (setq d (entget (nth 4 z)) n (1+ n))
          (princ (strcat "\nDATE-AT " (pa:get 'kind r) " " (rtos (car z) 2 1) "," (rtos (cadr z) 2 1) " head " (rtos (car head) 2 1) "," (rtos (cadr head) 2 1)))
          (if (and (in-cell-p r d (cdr (assoc 11 d)))
                   (equal (cdr (assoc 40 d)) 2.0 0.001)
                   (< (abs (- (car z) (car head))) 5.0)
                   (if (< (cadr head) 15.0) (< (+ (cadr head) 7.5) (cadr z) (+ (cadr head) 12.5)) (< (- (cadr head) 7.5) (cadr z) (- (cadr head) 2.5))))
            (setq ok (1+ ok)))))))
  (pa:date-remove)
  (princ (strcat "\nDATES=" (itoa ok) "/" (itoa n) " DATE-WARNINGS=" (itoa (length warnings)) " LEFT=" (itoa (date-count (pa:today))))))
(setq pa:plot0 pa:plot dated-plots 0)
(defun pa:plot (r path) (if (dated-p r) (setq dated-plots (1+ dated-plots))) (pa:plot0 r path))
(tpaste "PDFLIST" "1ЧП" 2 "PDFALL_list_spdbv_A3l.dwg")
1000,1000
1500,1000
(tpaste "PDFSPEC" "К1" 1 "PDFALL_spec1.dwg")
3000,1000
(tpaste "PDFSPEC" "К1" 2 "PDFALL_spec2.dwg")
3300,1000
3600,1000
(report)
(decoy)
PDFNUM
(slant)
(centred)
(dates)
(princ (strcat "\nTODAY=" (pa:today) "|"))
(command "_.-LAYER" "_M" "Цвет" "")
(command "_.SAVEAS" "2018" "$($pasteDir -replace '\\', '/')/paste.dwg")
PDFALL
(princ (strcat "\nDATED-PLOTS=" (itoa dated-plots) " TODAY-LEFT=" (itoa (date-count (pa:today)))))
(princ (strcat "\nLEAKED=" (vl-princ-to-string (vl-remove-if-not 'boundp '(texts hsegs vsegs cellsegs rowsegs pa-owner dated)))))
(princ (strcat "\nHELPERS=" (vl-princ-to-string (list (pa:bad-char "1/2П") (pa:bad-char "К1") (pa:bad-char "Х1:А") (pa:pad 3) (pa:pad 12) (pa:lower "Загальний ДРУК") (pa:file-safe "1/2П:") (pa:title-name '("ДВНЗ" "\"ПДАБА\"")) (pa:title-name '("\""))))))
(princ (strcat "\nSHOWN=" (if (pa:console-p) "console" "full") " " (pa:shown-folder "C:\\x" '("1ЧП")) " " (pa:shown-folder "C:\\x" '("1ЧП" "К1"))))
(princ (strcat "\nCANCELS=" (vl-princ-to-string (mapcar 'pa:cancelled-p (list "Function cancelled" "Функция прервана" (vl-catch-all-error-message (vl-catch-all-apply 'exit nil)) "bad argument type: numberp: nil")))))
;; a марка that Windows can't use in a file name stops PDFALL before it plots anything
(tpaste "PDFLIST" "1/2П" 1 "PDFALL_list_spdbv_A3l.dwg")
5000,1000
PDFALL
Ні
(princ "\nREFUSED-FORCE")
;; with 4 листи whose name text was deleted and a лист copied together with its numbers as well, plot
;; anyway: 1/2П becomes 1_2П, the copy is named by its position, the first two листи after their
;; organisation cells, and the other two, both Аркуш 1, Без_марки_01 and Без_марки_02
(tpaste "PDFLIST" "Х9" 4 "PDFALL_list_spdbv_A3l.dwg")
7000,1000
7500,1000
8000,1000
8500,1000
(defun org-text (r s / p)
  (setq p (list (- (car (pa:get 'ur r)) 30.0) (+ (cadr (pa:get 'll r)) 15.0) 0.0))
  (entmake (list '(0 . "TEXT") (cons 10 p) (cons 11 p) '(72 . 1) '(40 . 3.5) (cons 1 s))))
(foreach r (car (pa:read-drawing))
  (if (= (pa:get 'marka r) "Х9")
    (progn
      (foreach z (pa:get 'zone r) (if (and (nth 4 z) (pa:name-cell-p z "list")) (entdel (nth 4 z))))
      (cond
        ((equal (car (pa:get 'll r)) 7000.0 1.0) (org-text r "1ДВНЗ \"ПДАБА\""))
        ((equal (car (pa:get 'll r)) 7500.0 1.0) (org-text r "ДВНЗ \"ПДАБА\"")))
      (if (> (car (pa:get 'll r)) 7900.0)
        (foreach c (pa:get 'counters r)
          (if (eq (car c) 'sheet)
            ((lambda (d) (entmod (subst (cons 1 (strcat (cdr (assoc 1 d)) " 1")) (assoc 1 d) d))) (entget (nth 4 (cadr c))))))))))
(princ (strcat "\nORG-TITLES=" (vl-princ-to-string (mapcar '(lambda (r) (pa:title-name (pa:org-title r))) (vl-sort (vl-remove nil (mapcar 'cdr (cadr (pa:read-drawing)))) '(lambda (a b) (< (car (pa:get 'll a)) (car (pa:get 'll b)))))))))
(foreach r (car (pa:read-drawing))
  (if (and (= (pa:get 'marka r) "1ЧП") (= (pa:get 'sheet r) 2))
    (foreach c (pa:get 'counters r) (if (eq (car c) 'sheet) (pa:set-number c 1)))))
PDFALL
Так
(princ "\nEND-OF-TEST")
QUIT
Y
"@
$plog = Invoke-Acad 'paste' $pasteScr $null
Check ($plog -match 'END-OF-TEST') 'the paste script ran to the end'
Check ($plog -match 'PLACED=2[\s\S]*PLACED=1[\s\S]*PLACED=2') 'PDFLIST and PDFSPEC pasted 2, 1 and 2 рамки'
Check ($plog -match 'FRAMES=5') 'PDFALL finds all 5 pasted рамки'
Check ($plog -match 'NAME=Джгут 1ЧП' -and $plog -match 'NAME=Джгут К1') 'the марка was written into the name cells as typed'
Check ($plog -notmatch 'NAME=Джгут МАРКА') 'no name cell still says МАРКА'
Check ($plog -match 'CLAYER=0') 'the current layer was put back'
Check ($plog -match 'К1 специфікація 3: Аркуш 3') 'PDFNUM numbers the pasted специфікації'
Check ($plog -match 'NUMBERS=[1-9]\d* UPRIGHT=0') 'the numbers PDFNUM wrote lean 15 degrees like the title block'
# A 9 mm "7" under the "Арк." column of a changes table is not a sheet number, so PDFNUM must not copy its look.
Check ($plog -match 'DECOY=1' -and $plog -match 'TALL=1\b') 'PDFNUM ignores a number in the changes table''s Арк. column'
Check ($plog -match 'NAMES=5/5\b') 'the name text fills its cell and is centred in it, in all 5 pasted рамки'
Check ($plog -match 'NUMS=4/4\b') 'PDFNUM centres the 4 numbers it wrote in their cells'
Check ($plog -match 'PDFALL: 7 PDF у') 'PDFALL plots the 7 PDFs of the pasted рамки'
Check ($plog -notmatch 'Помилка') 'no error was reported'
Check ($plog -match 'LEAKED=nil') 'the reader and PDFALL keep their texts, lines and dates to themselves'
Check ($plog -match 'HELPERS=\(/ nil : 03 12 загальний друк 1_2П_ ДВНЗ_ПДАБА nil\)') 'the name helpers find a forbidden character, pad a number, lower-case Cyrillic and make a марка fit a file name'
Check ($plog -match 'SHOWN=console C:\\x\\1ЧП C:\\x(\s|"|$)') 'after plotting PDFALL shows the марка''s folder, or all of them when there are several; not in the console AutoCAD'
Check ($plog -match 'CANCELS=\(T T T nil\)') 'Esc in English or Russian and (exit) are not reported as errors, a real error is'
$beforeForce, $afterForce = $plog -split 'REFUSED-FORCE', 2
Check ($beforeForce -match "1/2П: у марці є символ '/'" -and ([regex]::Matches($beforeForce, 'PDFALL: \d+ PDF у')).Count -eq 1) 'a марка with a character Windows forbids in file names stops PDFALL before it plots, when the user says no'
$pasted1 = Join-Path $pasteDir 'exported files\1ЧП'
$pastedOut = Join-Path $pasteDir 'exported files'
Check ($afterForce -match 'Аркуш 1 стоїть на кількох' -and $afterForce -match 'PDFALL друкує попри проблеми' -and $afterForce -match 'PDFALL: 17 PDF у' -and
       (Test-Path (Join-Path $pasted1 '1ЧП лист 01.pdf')) -and (Test-Path (Join-Path $pasted1 '1ЧП лист 02.pdf'))) 'plotting anyway names a copied лист by its position and plots every рамка found (17 PDFs)'
Check ($afterForce -match 'ORG-TITLES=\(1ДВНЗ_ПДАБА ДВНЗ_ПДАБА nil nil\)') 'the organisation cell''s top line names a рамка without a марка; none is read from an empty one'
$orgNames = '1ДВНЗ_ПДАБА', 'ДВНЗ_ПДАБА', 'Без_марки_01', 'Без_марки_02'
Check ($afterForce -match 'рамку без марки надруковано як «1ДВНЗ_ПДАБА»' -and $afterForce -match 'рамку без марки надруковано як «Без_марки_02»' -and
       @($orgNames | Where-Object { -not (Test-Path (Join-Path $pastedOut "$_\$_ лист 01.pdf")) -or -not (Test-Path (Join-Path $pastedOut "$_\$_ лист 01 без заливки.pdf")) }).Count -eq 0 -and
       -not (Test-Path (Join-Path $pastedOut 'Без_марки'))) 'plotting anyway plots рамки without a марка in a folder each: by organisation cell, else Без_марки_01, _02 when both are Аркуш 1'
Check ($afterForce -match '1/2П: надруковано як «1_2П»' -and (Test-Path (Join-Path $pastedOut '1_2П\1_2П лист 01.pdf'))) 'plotting anyway plots a марка with a forbidden character with _ in its place'
Check ($plog -match 'DATES=5/5 DATE-WARNINGS=0 LEFT=0') 'the date goes in the Дата cell of all 5 pasted рамки at 2 mm, centred, and comes out again'
$today = Get-Date -Format 'dd.MM.yy'
Check ($plog -match "TODAY=$([regex]::Escape($today))\|") "the date reads dd.mm.yy ($today)"
Check ($plog -match 'DATED-PLOTS=7 TODAY-LEFT=0') 'all 7 PDFs of the pasted рамки were plotted with the date, and the drawing has none left'

# Every template, pasted in one row in the order of $forms, so that PDFNUM numbers each марка's
# рамки of a kind in that order. Each марка has its own choice of name-cell text.
Write-Host 'Every template in an empty drawing...'
$formsDir = Join-Path $Work 'forms'
New-Item (Join-Path $formsDir 'Plotters') -ItemType Directory -Force | Out-Null
$sizes = @{ A1 = 594, 841; A2 = 420, 594; A3 = 297, 420; A4 = 210, 297; A5 = 148, 210 }
$groups = @(
    # марка, kind, template-name pattern, prefix, custom prefix, second line, custom second line, name it gets
    @('1ЧП', 'list', 'PDFALL_list_skd_*', 'std', '', 'std', '', 'Джгут 1ЧП|Складальне креслення'),
    # a марка may be any word, without a digit too
    @('Іпсум', 'list', 'PDFALL_list_spdb_*', 'none', '', 'none', '', 'Іпсум'),
    @('Лорем', 'list', 'PDFALL_list_spdbv_*', 'custom', 'Кабель живлення', 'custom', 'Монтажна схема', 'Кабель живлення Лорем|Монтажна схема'),
    @('Іпсум', 'spec', 'PDFALL_spec?', 'none', '', 'none', '', 'Іпсум'),
    @('1ЧП', 'text', 'PDFALL_text_skd_?', 'std', '', 'std', '', 'Джгут 1ЧП'),
    @('Лорем', 'text', 'PDFALL_text_spdb_?', 'custom', 'Кабель живлення', 'custom', 'Монтажна схема', 'Кабель живлення Лорем')
)
$x = 0
$pasteLines = @()
$expected = @()
foreach ($g in $groups) {
    $files = @(Get-ChildItem $Contents -Filter "$($g[2]).dwg" | Sort-Object Name)
    $pasteLines += "(pa:set-setting `"Prefix`" `"$($g[3])`") (pa:set-setting `"PrefixText`" `"$($g[4])`") (pa:set-setting `"Line2`" `"$($g[5])`") (pa:set-setting `"Line2Text`" `"$($g[6])`")"
    $n = 0
    foreach ($f in $files) {
        $n++
        $size, $o = if ($f.BaseName -match '_(A\d)([lp])$') { $Matches[1], $Matches[2] } else { 'A4', 'p' }
        $wh = $sizes[$size]
        $w, $h = if ($o -eq 'l') { $wh[1], $wh[0] } else { $wh[0], $wh[1] }
        $pasteLines += "(tone `"$($g[0])`" `"$($f.Name)`")"
        $pasteLines += "$x,0"
        $expected += [pscustomobject]@{ Marka = $g[0]; Kind = $g[1]; Size = $size; W = $w; H = $h; Sheet = $n; Count = $files.Count; Name = $g[7] }
        $x += $w + 50
    }
}
$fh = $Contents -replace '\\', '/'
$formsScr = @"
(setvar "SECURELOAD" 0)
(setenv "PrinterConfigDir" "$((Join-Path $formsDir 'Plotters') -replace '\\', '\\')")
(setq *pdfall-home* "$($Contents -replace '\\', '\\')")
(load "$fh/pdfall.lsp")
(foreach s *pa-setting-defaults* (pa:set-setting (car s) (cdr s)))
(setq *pdfall-merge* nil)
(defun tone (marka file / kind)
  (setq placed 0 undo-open nil kind (cond ((wcmatch file "*list*") "list") ((wcmatch file "*spec*") "spec") ("text")))
  (pa:paste-start)
  (vl-catch-all-apply '(lambda () (pa:paste-run "T" marka kind '(lambda (i) (if (< i 1) (cons file "t") (exit))))))
  (pa:paste-cleanup))
(defun show (tag / d n)
  (setq d (pa:read-drawing))
  (foreach r (vl-sort (car d) '(lambda (a b) (< (car (pa:get 'll a)) (car (pa:get 'll b)))))
    (setq n nil)
    (foreach z (pa:get 'zone r) (if (and (pa:name-cell-p z (pa:get 'kind r)) (vl-string-search (pa:get 'marka r) (cadddr z))) (setq n (cadddr z))))
    (princ (strcat "\n" tag " " (pa:get 'marka r) " " (pa:get 'kind r) " " (car (pa:paper r)) " "
                   (itoa (cadr (pa:paper r))) "x" (itoa (caddr (pa:paper r)))
                   " sheet=" (vl-princ-to-string (pa:get 'sheet r)) " total=" (vl-princ-to-string (pa:get 'total r))
                   " name=" (vl-string-translate "\n" "|" (cond (n) ("?"))))))
  (foreach p (cadr d) (princ (strcat "\n" tag " problem: " (car p))))
  (princ))
$($pasteLines -join "`r`n")
(show "BEFORE")
PDFNUM
(show "AFTER")
(princ (strcat "\nPREFIX-ERRORS=" (vl-princ-to-string (list (if (pa:prefix-error "Кабель 2") 1 0) (if (pa:prefix-error "  ") 1 0) (if (pa:prefix-error "Кабель живлення") 1 0)))))
(setq pl (pa:preview-lines "PDFALL_list_skd_A1p.dwg" 200 120))
(princ (strcat "\nPREVIEW=" (itoa (length pl)) " " (if (vl-every '(lambda (s) (and (<= 0 (car s) 200) (<= 0 (cadr s) 120) (<= 0 (caddr s) 200) (<= 0 (cadddr s) 120))) pl) "inside" "outside")))
(pa:set-setting "Paste" "list_skd_A5l")
(princ (strcat "\nCHOSEN=" (pa:chosen-kind) " " (pa:list-file) " " (pa:chosen-shown) "|" (apply 'strcat (pa:doc-sizes "list_spdb")) "|" (apply 'strcat (pa:doc-orients "list_skd" "A4")) "|" (apply 'strcat (pa:doc-sizes "text_spdb")) (apply 'strcat (pa:doc-orients "text_spdb" "A4"))))
(pa:set-setting "Paste" "text_spdb")
(princ (strcat "\nTEXT=" (pa:chosen-kind) " " (pa:text-file "2") " " (pa:list-file) " " (pa:chosen-shown)))
(pa:set-setting "Paste" "list_skd_A5p")
(princ (strcat "\nFALLBACK=" (pa:list-file)))
(princ (strcat "\nMARKA-ERRORS=" (vl-princ-to-string (mapcar '(lambda (m) (if (pa:marka-error m) 1 0)) (list "Лорем" "1ЧП" "Лорем Іпсум" "" "1/2")))))
(princ (strcat "\nNAME-LINE=" (pa:name-line "Джгут" "Лорем" "Складальне креслення") "|" (pa:name-line "" "Лорем" "") "|"))
(pa:remember-marka "Лорем") (setq *pdfall-marka* nil)
(princ (strcat "\nREMEMBERED=" (pa:last-marka)))
(pa:set-setting "Prefix" "custom") (pa:set-setting "PrefixText" "Джгут {1}\\") (pa:set-setting "Line2" "none")
(princ (strcat "\nESCAPED=" (pa:name-text "list" "Х2")))
(command "_.-LAYER" "_M" "Цвет" "")
(command "_.SAVEAS" "2018" "$($formsDir -replace '\\', '/')/forms.dwg")
PDFALL
(princ "\nEND-OF-TEST")
QUIT
Y
"@
$flog = Invoke-Acad 'forms' $formsScr $null
Check ($flog -match 'END-OF-TEST') 'the every-template script ran to the end'
$before = @([regex]::Matches($flog, '(?m)^BEFORE (\S+) (\S+) (A\d) (\d+)x(\d+) sheet=\S+ total=\S+ name=(.*)$'))
$after = @([regex]::Matches($flog, '(?m)^AFTER (\S+) (\S+) (A\d) (\d+)x(\d+) sheet=(\S+) total=(\S+) name=(.*)$'))
Check ($before.Count -eq $expected.Count -and $flog -notmatch 'BEFORE problem') "PDFALL finds all $($expected.Count) pasted рамки and reads a марка in each (found $($before.Count))"
$bad = @()
for ($i = 0; $i -lt [math]::Min($after.Count, $expected.Count); $i++) {
    $e = $expected[$i]; $a = $after[$i].Groups
    $total = if ($e.Kind -eq 'list' -or $e.Sheet -eq 1) { "$($e.Count)" } else { 'nil' }
    if ($a[1].Value -ne $e.Marka -or $a[2].Value -ne $e.Kind -or $a[3].Value -ne $e.Size -or $a[4].Value -ne "$($e.W)" -or $a[5].Value -ne "$($e.H)" -or
        $a[6].Value -ne "$($e.Sheet)" -or $a[7].Value -ne $total -or $a[8].Value.Trim() -ne $e.Name) {
        $bad += "$($after[$i].Value.Trim()) (expected $($e.Marka) $($e.Kind) $($e.Size) $($e.W)x$($e.H) sheet=$($e.Sheet) total=$total name=$($e.Name))"
    }
}
Check ($after.Count -eq $expected.Count -and $bad.Count -eq 0) "every рамка is read with its kind, size, марка and name cell, and PDFNUM numbers it ($($bad -join '; '))"
Check ($flog -match 'PREFIX-ERRORS=\(1 1 0\)') 'a custom prefix with a digit, or an empty one, is refused'
Check ($flog -match 'PREVIEW=(\d+) inside' -and [int]$Matches[1] -gt 50) 'the preview draws a template''s lines inside the picture'
Check ($flog -match 'CHOSEN=list PDFALL_list_skd_A5l\.dwg лист СКД A5 горизонтальний\|A1A2A3A4\|p\|A4p') 'the settings pick a лист template, and list a document''s sizes and orientations'
Check ($flog -match 'TEXT=text PDFALL_text_spdb_2\.dwg PDFALL_text_spdb_1\.dwg текстовий документ СПДБ') 'the «Лист» button''s settings may pick a текстовий документ instead'
Check ($flog -match 'MARKA-ERRORS=\(0 0 1 1 1\)') 'a марка may be any one word, without a space or a character Windows forbids'
Check ($flog -match 'NAME-LINE=Джгут Лорем Складальне креслення\|Лорем\|') 'the dialog shows the whole name in one line'
Check ($flog -match 'REMEMBERED=Лорем') 'the марка set last is remembered across sessions'
Check ($flog -match 'FALLBACK=PDFALL_list_spdbv_A3l\.dwg') 'a лист format with no template falls back to the default'
Check ($flog -match [regex]::Escape('ESCAPED=Джгут \{1\}\\ Х2')) 'a custom prefix is written literally, not as MTEXT codes'
$formPdfs = @(Get-ChildItem (Join-Path $formsDir 'exported files') -Recurse -Filter '*.pdf' -ErrorAction SilentlyContinue)
$lists = @($expected | Where-Object { $_.Kind -eq 'list' }).Count
$wantPdfs = 2 * $lists + ($expected.Count - $lists)
Check ($flog -match "PDFALL: $wantPdfs PDF у" -and $formPdfs.Count -eq $wantPdfs) "PDFALL plots $wantPdfs PDFs: every лист twice, every специфікація and текстовий документ once (found $($formPdfs.Count))"
Check ($flog -notmatch 'Unknown command|Помилка|замість|клітинку під заголовком Дата') 'with no error, no size warning, and a date in every Дата cell'
$words = @{ list = 'лист'; spec = 'специфікація'; text = 'текстовий документ' }
$wrong = @()
foreach ($e in $expected) {
    $name = "$($e.Marka) $($words[$e.Kind]) $('{0:D2}' -f $e.Sheet).pdf"
    $pdf = Join-Path $formsDir "exported files\$($e.Marka)\$name"
    $box = if ((Test-Path $pdf) -and ([Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($pdf)) -match '/MediaBox\s*\[\s*0\s+0\s+([\d.]+)\s+([\d.]+)')) { [double]$Matches[1], [double]$Matches[2] }
    if (-not $box -or [math]::Abs($box[0] - $e.W * 72 / 25.4) -gt 2 -or [math]::Abs($box[1] - $e.H * 72 / 25.4) -gt 2) { $wrong += "$name ($box)" }
}
Check ($wrong.Count -eq 0) "every PDF is on paper of its рамка's size and orientation ($($wrong -join '; '))"
$mergeForms = Join-Path $Work 'merge-forms.txt'
$m4 = Start-Process (Join-Path $Contents 'merge.exe') -ArgumentList "`"$(Join-Path $formsDir 'exported files')`" --force" -RedirectStandardInput $answers `
    -RedirectStandardOutput $mergeForms -PassThru -NoNewWindow
$null = $m4.Handle
if (-not $m4.WaitForExit(120000)) { $m4.Kill(); $script:failures += 'merge.exe (every template) timed out' }
$fmlog = Get-Content $mergeForms -Raw -Encoding UTF8
$formMerged = @(Get-ChildItem (Join-Path $formsDir 'exported files') -Recurse -Filter '*загальний*.pdf')
Check ($formMerged.Count -eq 6 -and $fmlog -notmatch 'Не вдалося звірити|НЕ збігається|Нерозпізнані|--force') "merge.exe reads every марка, Аркуш and текстовий документ back and builds 6 combined files (found $($formMerged.Count))"
$n1 = @($expected | Where-Object { $_.Marka -eq '1ЧП' }).Count
Check ($fmlog -match "1ЧП загальний\.pdf: файлів $n1, сторінок $n1") "1ЧП загальний holds its $n1 листи and текстові документи"

# The шари заливки chosen in the settings: in any case, an xref's layer by its own name (forms.dwg,
# saved above with a layer Цвет, attached as an xref), and switched off for the листи без заливки.
Write-Host 'Fill layers chosen in the settings...'
$formsDwg = (Join-Path $formsDir 'forms.dwg') -replace '\\', '/'
$fillScr = @"
(setvar "SECURELOAD" 0)
(setq *pdfall-home* "$($pasteHome -replace '\\', '\\')")
(load "$ph/pdfall.lsp")
(foreach s *pa-setting-defaults* (pa:set-setting (car s) (cdr s)))
(princ (strcat "\nDEFAULT-FILLS=" (pa:join-names (pa:fill-names))))
(command "_.-LAYER" "_M" "Заливка" "_M" "Штрих" "_S" "0" "")
(command "_.-XREF" "_A" "$formsDwg" "0,0" "1" "1" "0")
(pa:set-fill-names '("заливка" " Цвет " "Немає"))
(princ (strcat "\nFILL-NAMES=" (pa:join-names (pa:fill-names))))
(setq fills (pa:fill-layers (pa:fill-names)))
(princ (strcat "\nFILL-LAYERS=" (pa:join-names fills)))
(princ (strcat "\nFILL-CHOICES=" (pa:join-names (mapcar 'cadr (pa:fill-choices)))))
(princ (strcat "\nFILLS-HERE=" (pa:join-names (pa:fills-here (pa:fill-names)))))
(princ (strcat "\nFILL-SAVED=" (pa:join-names (pa:fill-saved '("Штрих") (pa:fill-names)))))
(pa:set-fill nil)
(princ (strcat "\nFILLS-OFF=" (pa:join-names (mapcar '(lambda (n) (if (minusp (cdr (assoc 62 (pa:layer n)))) "off" "on")) (append fills '("Штрих"))))))
(princ (strcat "\nNO-DIALOG=" (vl-princ-to-string (pa:settings-dialog 'fills))))
(pa:set-fill-names nil)
(princ (strcat "\nNO-FILLS=" (pa:names-shown (pa:fill-names)) "|" (vl-princ-to-string (pa:fill-names))))
(princ "\nEND-OF-TEST")
QUIT
Y
"@
$xlog = Invoke-Acad 'fills' $fillScr $null
Check ($xlog -match 'END-OF-TEST' -and $xlog -notmatch '; error|Помилка') 'the fill-layer script ran to the end without an error'
Check ($xlog -match 'DEFAULT-FILLS=Цвет;Колір') 'the шари заливки are Цвет and Колір until the user chooses'
Check ($xlog -match 'FILL-NAMES=заливка;Цвет;Немає') 'the chosen names are kept, trimmed'
Check ($xlog -match '(?m)^FILL-LAYERS=Заливка;forms\|Цвет"') 'a chosen name finds the layer in any case, and the same layer in an xref'
$choices = if ($xlog -match '(?m)^FILL-CHOICES=([^"]*)') { $Matches[1] } else { '' }
Check ($choices -match '(^|;)Заливка;' -and $choices -match 'Цвет \(у зовнішньому посиланні\)' -and $choices -match '(^|;)Штрих(;|$)' -and
       $choices -notmatch '(^|;)0(;|$)' -and $choices -notmatch 'Немає' -and $choices -cnotmatch 'заливка') "the dialog lists the drawing's layers but 0 and an xref's by its own name, not a chosen layer the drawing lacks ($choices)"
Check ($xlog -match '(?m)^FILLS-HERE=заливка;Цвет"') 'the settings report only the chosen layers the drawing has'
Check ($xlog -match '(?m)^FILL-SAVED=Штрих;Немає"') 'closing the dialog keeps the layers ticked, and the names chosen for other drawings'
Check ($xlog -match 'FILLS-OFF=off;off;on') 'the листи без заливки have the chosen layers off, and only those'
Check ($xlog -match 'NO-DIALOG=nil') 'without a dialog, PDFALL''s question about the шари заливки is skipped'
Check ($xlog -match 'NO-FILLS=жодного\|nil') 'the user may choose no шар заливки at all'

# The real command, ended by Esc (0x1B), which also ends the script.
$esc = [string][char]27
$escScr = @"
(setvar "SECURELOAD" 0)
(setq *pdfall-home* "$($pasteHome -replace '\\', '\\')")
(load "$ph/pdfall.lsp")
(foreach s *pa-setting-defaults* (pa:set-setting (car s) (cdr s)))
PDFLIST
1ЧП
1000,1000
$esc
"@
$elog = Invoke-Acad 'esc' $escScr $null
Check ($elog -match 'PDFLIST: додано рамок: 1 \(марка 1ЧП\)') 'PDFLIST reports what it added when Esc ends it'

# The real PDFLIST and PDFSPEC, down to the run of pages, with pasting itself replaced by a stand-in
# that "pastes" 3 рамки and then ends the run as Esc would. The debug log is on.
Write-Host 'Runs of pages and the debug log...'
$pagesDwg = Join-Path $Work 'pages.dwg'
Copy-Item (Join-Path $pasteDir 'paste.dwg') $pagesDwg -Force
$debugLog = Join-Path $env:TEMP 'PDFALL-debug.log'
$pagesScr = @"
(setvar "SECURELOAD" 0)
(setq *pdfall-home* "$($pasteHome -replace '\\', '\\')")
(load "$ph/pdfall.lsp")
(foreach s *pa-setting-defaults* (pa:set-setting (car s) (cdr s)))
PDFDEBUG
Увімкнути
(defun pa:paste-one (file name) (if (< (length pasted) 3) (progn (setq pasted (cons file pasted)) T)))
(setq pasted nil)
(pa:set-setting "Paste" "text_skd")
PDFLIST
Лорем
Перший
(princ (strcat "\nTEXT-PAGES=" (vl-princ-to-string (reverse pasted))))
(setq pasted nil)
PDFSPEC
Лорем
Наступний
(princ (strcat "\nSPEC-PAGES=" (vl-princ-to-string (reverse pasted))))
(setq pasted nil)
(pa:set-setting "Paste" "list_skd_A3l")
PDFLIST
Лорем
(princ (strcat "\nLIST-PAGES=" (vl-princ-to-string (reverse pasted))))
(foreach r (car (pa:read-drawing))
  (if (and (= (pa:get 'marka r) "1ЧП") (equal (car (pa:get 'll r)) 1500.0 1.0))
    (foreach c (pa:get 'counters r) (pa:set-number c (if (eq (car c) 'total) 5 1)))))
PDFNUM
;; deleting "Аркуш 2" and "Аркушів 2" deletes the labels with the numbers
(foreach r (car (pa:read-drawing))
  (if (and (= (pa:get 'marka r) "1ЧП") (equal (car (pa:get 'll r)) 1500.0 1.0))
    (foreach c (pa:get 'counters r) (entdel (nth 4 (cadr c))))))
(princ "\nLABELS-DELETED")
PDFNUM
PDFALL
Ні
PDFDEBUG
Вимкнути
(princ "\nEND-OF-TEST")
QUIT
Y
"@
$glog = Invoke-Acad 'pages' $pagesScr $pagesDwg
Check ($glog -match 'END-OF-TEST' -and $glog -notmatch 'Hard error|Помилка') 'PDFLIST and PDFSPEC run through their pages without an error'
Check ($glog -match 'TEXT-PAGES=\(PDFALL_text_skd_1\.dwg PDFALL_text_skd_2\.dwg PDFALL_text_skd_2\.dwg\)') 'PDFLIST pastes a текстовий документ''s first page, then later ones'
Check ($glog -match 'SPEC-PAGES=\(PDFALL_spec2\.dwg PDFALL_spec2\.dwg PDFALL_spec2\.dwg\)') 'PDFSPEC pastes only later pages when asked to start on one'
Check ($glog -match 'LIST-PAGES=\(PDFALL_list_skd_A3l\.dwg PDFALL_list_skd_A3l\.dwg PDFALL_list_skd_A3l\.dwg\)') 'PDFLIST pastes the лист chosen in the settings'
Check ($glog -match 'журнал увімкнено' -and $glog -match 'журнал вимкнено') 'PDFDEBUG turns the debug log on and off'
Check ($glog -match '1ЧП лист 2: Аркуш 1 → 2, Аркушів 5 → 2' -and $glog -notmatch '1ЧП лист 1:') 'PDFNUM fixes a лист copied with the number of another, and leaves the right ones alone'
$dlog = if (Test-Path $debugLog) { Get-Content $debugLog -Raw -Encoding UTF8 } else { '' }
Check ($dlog -match '==== PDFLIST \| PDFALL' -and $dlog -match 'paste: pages of text starting on' -and $dlog -match 'paste: template "?PDFALL_spec2') 'the debug log follows PDFLIST and PDFSPEC step by step'
Check ($dlog -match '==== PDFNUM' -and $dlog -match 'reader: frame at' -and $dlog -match 'kind (list|spec)' -and $dlog -match '\[name cell\]' -and $dlog -match 'pdfnum: filled') 'the debug log shows each рамка''s kind and title-block texts, with the name cell marked'
Check ($dlog -match 'log turned off') 'turning the log off is the last thing logged'
$afterDelete = ($glog -split 'LABELS-DELETED', 2)[1]
Check ($afterDelete -match 'немає напису «Аркуш», тож номер нікуди записати' -and $afterDelete -match 'немає напису «Аркушів»' -and
       $afterDelete -match 'немає напису «Аркуш» \(його видалили') 'PDFNUM and PDFALL say when the Аркуш and Аркушів labels were deleted, instead of offering to fill them'

Write-Host 'Ribbon tab...'
[Reflection.Assembly]::LoadFrom((Join-Path (Split-Path $Acad) 'AcCui.dll')) | Out-Null
$cs = New-Object Autodesk.AutoCAD.Customization.CustomizationSection((Join-Path $Contents 'PDFALL.cuix'))
$tab = @($cs.MenuGroup.RibbonRoot.RibbonTabSources)[0]
$macros = @($cs.MenuGroup.MacroGroups | ForEach-Object { $_.MenuMacros })
Check ($tab.Text -eq 'PDFALL' -and "$($tab.DefaultDisplay)" -eq 'AddToWorkspace') 'PDFALL.cuix has a PDFALL tab that AutoCAD adds by itself'
Check (($macros | ForEach-Object { $_.macro.Command }) -join ',' -eq '^C^CPDFALL ,^C^CPDFNUM ,^C^CPDFLIST ,^C^CPDFSPEC ,^C^CPDFSETTINGS ') 'its buttons run PDFALL, PDFNUM, PDFLIST, PDFSPEC and PDFSETTINGS'
$labels = @($cs.MenuGroup.RibbonRoot.RibbonPanelSources | ForEach-Object { $_.Items } | ForEach-Object { $_.Items } | ForEach-Object { $_.Text })
Check (($labels -join '|') -eq 'Друк у PDF|Номери аркушів|Лист|Специфікація|Налаштування') "the buttons read in Ukrainian, not as command names (got $($labels -join ', '))"
Check (@($macros | Where-Object { -not (Test-Path (Join-Path $Contents $_.macro.LargeImage)) }).Count -eq 0) 'every button image is in Contents'
Check (@(Get-ChildItem $Contents -Filter 'PDFALL_*.dwg').Count -eq 28) 'the 28 рамка templates are in Contents'

Write-Host "Logs: $out, $mergeOut"
if ($failures) { Write-Host "FAILED: $($failures -join '; ')"; exit 1 } else { Write-Host 'All passed.' }
