# End-to-end test of the built PDFALL.bundle on examples\Креслення приклад.dxf, without opening AutoCAD.
# Runs PDFNUM (to fill the empty counters) and PDFALL in accoreconsole with a throwaway AutoCAD
# profile, then merge.exe on the PDFs.
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

if (Test-Path $Work) { Remove-Item $Work -Recurse -Force }
$plotters = Join-Path $Work 'Plotters'
New-Item $plotters -ItemType Directory -Force | Out-Null
$dxf = Get-ChildItem (Join-Path $PSScriptRoot '..\examples') -Filter '*.dxf' | Select-Object -First 1
Copy-Item $dxf.FullName (Join-Path $Work 'sample.dxf')

# AutoCAD script: forward slashes in paths, UTF-8 with BOM so Cyrillic survives.
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
$scrPath = Join-Path $Work 'run.scr'
[IO.File]::WriteAllText($scrPath, $scr, (New-Object Text.UTF8Encoding($true)))

Write-Host "PDFNUM and PDFALL in accoreconsole ($Work)..."
$out = Join-Path $Work 'acad.txt'
$acadArgs = "/i `"$(Join-Path $Work 'sample.dxf')`" /s `"$scrPath`" /l en-US /isolate pdfalltest `"$(Join-Path $Work 'user')`""
$p = Start-Process $Acad -ArgumentList $acadArgs -WorkingDirectory $Work -RedirectStandardOutput $out -PassThru -NoNewWindow
# With /isolate, accoreconsole sometimes never exits after QUIT, so stop it once the script is done.
$deadline = (Get-Date).AddSeconds($Seconds)
while (-not $p.WaitForExit(2000)) {
    $sofar = try {
        $fs = [IO.File]::Open($out, 'Open', 'Read', 'ReadWrite')
        try { (New-Object IO.StreamReader($fs, [Text.Encoding]::Unicode)).ReadToEnd() } finally { $fs.Close() }
    } catch { '' }
    if ($sofar -match 'Command: QUIT') { Start-Sleep 5; if (-not $p.HasExited) { $p.Kill() }; break }
    if ((Get-Date) -gt $deadline) { $p.Kill(); $script:failures += 'accoreconsole timed out'; break }
}
Start-Sleep -Milliseconds 300
$log = [IO.File]::ReadAllText($out, [Text.Encoding]::Unicode)
[IO.File]::WriteAllText($out, $log, (New-Object Text.UTF8Encoding($false)))

$exported = Join-Path $Work 'exported files'
$pdfs = @(Get-ChildItem $exported -Recurse -Filter '*.pdf' -ErrorAction SilentlyContinue)
$first, $second = $log -split 'SECOND-PDFNUM', 2
Check ($log -match 'END-OF-TEST') 'the script ran to the end'
Check ($first -match 'PDFNUM filled in:') 'PDFNUM filled in the empty counters'
Check ($first -match 'К1 специфікація 2: Аркуш 2') 'К1 специфікація 2 got Аркуш 2'
Check ($first -match '1П лист 1: Аркуш 1, Аркушів 1') '1П лист 1 got Аркуш 1, Аркушів 1'
Check ($first -notmatch 'К1 лист') 'К1 листи, already numbered, were left alone'
Check ($second -match 'PDFNUM: no empty') 'a second PDFNUM finds nothing left to fill'
Check ($log -notmatch 'cells are empty|cell is empty') 'PDFALL finds no empty counters'
Check ($log -match 'PDFALL: 34 PDFs') 'PDFALL reports 34 PDFs'
Check ($pdfs.Count -eq 34) "34 PDFs on disk (found $($pdfs.Count))"
Check (Test-Path (Join-Path $plotters 'PDFALL.pc3')) 'PDFALL.pc3 was copied into the Plotters folder'
Check ($log -notmatch 'is not in .*every PDF opens in a viewer') 'PDFALL.pc3 was used in the same run'
Check (Test-Path (Join-Path $exported 'К1\К1 лист 1 без заливки.pdf')) 'К1 лист 1 без заливки.pdf exists'

Write-Host 'merge.exe on the exported files...'
$mergeOut = Join-Path $Work 'merge.txt'
$m = Start-Process (Join-Path $Contents 'merge.exe') -ArgumentList "`"$exported`"" -RedirectStandardInput $scrPath `
    -RedirectStandardOutput $mergeOut -PassThru -NoNewWindow
$null = $m.Handle
if (-not $m.WaitForExit(120000)) { $m.Kill(); $script:failures += 'merge.exe timed out' }
$merged = @(Get-ChildItem $exported -Recurse -Filter '*Загальний*.pdf')
$markas = @(Get-ChildItem $exported -Directory)
Check ($m.ExitCode -eq 0) "merge.exe exit code 0 (got $($m.ExitCode))"
$mergeLog = Get-Content $mergeOut -Raw -Encoding UTF8
Check ($mergeLog -notmatch 'Could not check') 'merge.exe reads every Аркуш back from the PDFs'
Check ($merged.Count -eq 2 * $markas.Count) "Загальний and Загальний друк for each of $($markas.Count) марки (found $($merged.Count))"

Write-Host "Logs: $out, $mergeOut"
if ($failures) { Write-Host "FAILED: $($failures -join '; ')"; exit 1 } else { Write-Host 'All passed.' }
