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
PDFNUM
(princ "SECOND-PDFNUM")
PDFNUM
PDFALL
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
(defun report (/ f)
  (setq texts nil hsegs nil vsegs nil cellsegs nil)
  (pa:walk-model)
  (setq f (pa:find-frames))
  (princ (strcat "\nFRAMES=" (itoa (length f))))
  (foreach tx texts (if (wcmatch (caddr tx) "*Джгут*") (princ (strcat "\nNAME=" (cadddr tx)))))
  (princ (strcat "\nCLAYER=" (getvar "CLAYER"))))
(tpaste "PDFLIST" "1ЧП" 2 "PDFALL_list.dwg")
1000,1000
1500,1000
(tpaste "PDFSPEC" "К1" 1 "PDFALL_spec1.dwg")
3000,1000
(tpaste "PDFSPEC" "К1" 2 "PDFALL_spec2.dwg")
3300,1000
3600,1000
(report)
PDFNUM
(command "_.-LAYER" "_M" "Цвет" "")
(command "_.SAVEAS" "2018" "$($pasteDir -replace '\\', '/')/paste.dwg")
PDFALL
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
Check ($plog -match 'PDFALL: 7 PDF у') 'PDFALL plots the 7 PDFs of the pasted рамки'
Check ($plog -notmatch 'Помилка') 'no error was reported'

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
