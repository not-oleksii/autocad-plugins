# End-to-end test of the built PDFALL.bundle without opening AutoCAD:
#   1. on examples\Креслення приклад.dxf: PDFNUM (to fill the empty counters) and PDFALL in accoreconsole
#      with a throwaway AutoCAD profile, then merge.exe on the PDFs;
#   2. in an empty drawing: PDFLIST and PDFSPEC paste рамки, PDFNUM numbers them and PDFALL plots them;
#   3. the ribbon tab.
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

Write-Host "PDFNUM and PDFALL in accoreconsole ($Work)..."
$log = Invoke-Acad 'sample' $scr (Join-Path $Work 'sample.dxf')
$out = Join-Path $Work 'sample\acad.txt'

$exported = Join-Path $Work 'exported files'
$pdfs = @(Get-ChildItem $exported -Recurse -Filter '*.pdf' -ErrorAction SilentlyContinue)
$first, $second = $log -split 'SECOND-PDFNUM', 2
Check ($log -match 'END-OF-TEST') 'the script ran to the end'
Check ($first -match 'PDFNUM заповнив:') 'PDFNUM filled in the empty counters'
Check ($first -match 'К1 специфікація 2: Аркуш 2') 'К1 специфікація 2 got Аркуш 2'
Check ($first -match '1П лист 1: Аркуш 1, Аркушів 1') '1П лист 1 got Аркуш 1, Аркушів 1'
Check ($first -notmatch 'К1 лист') 'К1 листи, already numbered, were left alone'
Check ($second -match 'PDFNUM: порожніх клітинок') 'a second PDFNUM finds nothing left to fill'
Check ($log -notmatch 'клітинк[аи] Аркуш\S* порожн') 'PDFALL finds no empty counters'
Check ($log -match 'PDFALL: 34 PDF у') 'PDFALL reports 34 PDFs'
Check ($pdfs.Count -eq 34) "34 PDFs on disk (found $($pdfs.Count))"
Check (Test-Path (Join-Path $plotters 'PDFALL.pc3')) 'PDFALL.pc3 was copied into the Plotters folder'
Check ($log -notmatch 'відкриється в переглядачі') 'PDFALL.pc3 was used in the same run'
Check (Test-Path (Join-Path $exported 'К1\К1 лист 1 без заливки.pdf')) 'К1 лист 1 без заливки.pdf exists'
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
$merged = @(Get-ChildItem $exported -Recurse -Filter '*Загальний*.pdf')
$markas = @(Get-ChildItem $exported -Directory)
Check ($m.ExitCode -eq 0) "merge.exe exit code 0 (got $($m.ExitCode))"
$mergeLog = Get-Content $mergeOut -Raw -Encoding UTF8
Check ($mergeLog -notmatch 'Не вдалося звірити') 'merge.exe reads every Аркуш back from the PDFs'
Check ($merged.Count -eq 2 * $markas.Count) "Загальний and Загальний друк for each of $($markas.Count) марки (found $($merged.Count))"

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
(setq *pdfall-merge* nil)
(defun tpaste (cmd marka n file)
  (setq placed 0 undo-open nil)
  (pa:paste-start)
  (vl-catch-all-apply '(lambda () (pa:paste-run cmd marka '(lambda (i) (if (< i n) (cons file "t") (exit))))))
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
(tpaste "PDFLIST" "1ЧП" 2 "PDFALL_list.dwg")
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
(command "_.-LAYER" "_M" "Цвет" "")
(command "_.SAVEAS" "2018" "$($pasteDir -replace '\\', '/')/paste.dwg")
PDFALL
(princ (strcat "\nDATED-PLOTS=" (itoa dated-plots) " TODAY-LEFT=" (itoa (date-count (pa:today)))))
(princ (strcat "\nLEAKED=" (vl-princ-to-string (vl-remove-if-not 'boundp '(texts hsegs vsegs cellsegs rowsegs pa-owner dated)))))
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
Check ($plog -match 'DATES=5/5 DATE-WARNINGS=0 LEFT=0') 'the date goes in the Дата cell of all 5 pasted рамки at 2 mm, centred, and comes out again'
Check ($plog -match 'DATED-PLOTS=7 TODAY-LEFT=0') 'all 7 PDFs of the pasted рамки were plotted with the date, and the drawing has none left'

# The real command, ended by Esc (0x1B), which also ends the script.
$esc = [string][char]27
$escScr = @"
(setvar "SECURELOAD" 0)
(setq *pdfall-home* "$($pasteHome -replace '\\', '\\')")
(load "$ph/pdfall.lsp")
PDFLIST
1ЧП
1000,1000
$esc
"@
$elog = Invoke-Acad 'esc' $escScr $null
Check ($elog -match 'PDFLIST: додано рамок: 1 \(марка 1ЧП\)') 'PDFLIST reports what it added when Esc ends it'

Write-Host 'Ribbon tab...'
[Reflection.Assembly]::LoadFrom((Join-Path (Split-Path $Acad) 'AcCui.dll')) | Out-Null
$cs = New-Object Autodesk.AutoCAD.Customization.CustomizationSection((Join-Path $Contents 'PDFALL.cuix'))
$tab = @($cs.MenuGroup.RibbonRoot.RibbonTabSources)[0]
$macros = @($cs.MenuGroup.MacroGroups | ForEach-Object { $_.MenuMacros })
Check ($tab.Text -eq 'PDFALL' -and "$($tab.DefaultDisplay)" -eq 'AddToWorkspace') 'PDFALL.cuix has a PDFALL tab that AutoCAD adds by itself'
Check (($macros | ForEach-Object { $_.macro.Command }) -join ',' -eq '^C^CPDFALL ,^C^CPDFNUM ,^C^CPDFLIST ,^C^CPDFSPEC ') 'its buttons run PDFALL, PDFNUM, PDFLIST and PDFSPEC'
Check (@($macros | Where-Object { -not (Test-Path (Join-Path $Contents $_.macro.LargeImage)) }).Count -eq 0) 'every button image is in Contents'
Check (@('PDFALL_list.dwg', 'PDFALL_spec1.dwg', 'PDFALL_spec2.dwg' | Where-Object { -not (Test-Path (Join-Path $Contents $_)) }).Count -eq 0) 'the three рамка templates are in Contents'

Write-Host "Logs: $out, $mergeOut"
if ($failures) { Write-Host "FAILED: $($failures -join '; ')"; exit 1 } else { Write-Host 'All passed.' }
