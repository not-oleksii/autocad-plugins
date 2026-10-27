# Makes BPTOOLS.dwt, the template «Нове креслення» (BPNEW) opens: AutoCAD's metric acadiso.dwt with
# the стиль оформлення of the built bptools.lsp, the «Розміри» dimension style, the «Позиційний
# номер» multileader style and the «Примітка» text style current, on layer 0, in millimetres.
# A .dwt is a drawing under another name, so the console AutoCAD saves a .dwg and this renames it.
# build.bat runs it: powershell -File src\make_template.ps1 -Contents dist\BPTOOLS.bundle\Contents
param(
    [Parameter(Mandatory = $true)][string]$Contents,
    [string]$Acad = 'C:\Program Files\Autodesk\AutoCAD 2024'
)
$ErrorActionPreference = 'Stop'
$Contents = (Resolve-Path $Contents).Path
$base = Join-Path $Acad 'UserDataCache\en-us\Template\acadiso.dwt'
if (-not (Test-Path $base)) { throw "no $base" }
$work = Join-Path $env:TEMP 'bptools-template'
if (Test-Path $work) { Remove-Item $work -Recurse -Force }
New-Item $work -ItemType Directory | Out-Null
$dwg = Join-Path $work 'BPTOOLS.dwg'
$c = $Contents -replace '\\', '/'
$scr = @"
(setvar "SECURELOAD" 0)
(setq *bptools-home* "$($Contents -replace '\\', '\\')")
(load "$c/bptools.lsp")
(bp:ensure-styles)
(setvar "CLAYER" "0")
(setvar "TEXTSTYLE" (bp:kind-style "note"))
(setvar "CMLEADERSTYLE" *bptools-pos-style*)
(command "_.-DIMSTYLE" "_R" *bptools-dim-style*)
(setvar "INSUNITS" 4)
(command "_.SAVEAS" "2018" "$($dwg -replace '\\', '/')")
(princ "\nTEMPLATE-SAVED")
QUIT
Y
"@
$scrPath = Join-Path $work 'make.scr'
[IO.File]::WriteAllText($scrPath, $scr, (New-Object Text.UTF8Encoding($true)))
$out = Join-Path $work 'acad.txt'
$p = Start-Process (Join-Path $Acad 'accoreconsole.exe') -ArgumentList "/i `"$base`" /s `"$scrPath`" /l en-US /isolate bptoolstemplate `"$(Join-Path $work 'user')`"" `
    -WorkingDirectory $work -RedirectStandardOutput $out -PassThru -NoNewWindow
# With /isolate, accoreconsole sometimes never exits after QUIT, so stop it once the script is done.
$deadline = (Get-Date).AddSeconds(180)
while (-not $p.WaitForExit(2000)) {
    $sofar = try {
        $fs = [IO.File]::Open($out, 'Open', 'Read', 'ReadWrite')
        try { (New-Object IO.StreamReader($fs, [Text.Encoding]::Unicode)).ReadToEnd() } finally { $fs.Close() }
    } catch { '' }
    if ($sofar -match 'Command: QUIT') { Start-Sleep 3; if (-not $p.HasExited) { $p.Kill() }; break }
    if ((Get-Date) -gt $deadline) { $p.Kill(); break }
}
if (-not (Test-Path $dwg)) { throw "the console AutoCAD did not save the template; see $out" }
Copy-Item $dwg (Join-Path $Contents 'BPTOOLS.dwt') -Force
Write-Host "Built $(Join-Path $Contents 'BPTOOLS.dwt')"
