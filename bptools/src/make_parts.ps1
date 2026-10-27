# Makes the parts library from src\parts\library.dwg (the parts drawn by hand, if there is one) and
# the D-Sub parts that src\make_parts.lsp generates: one drawing per вигляд in src\parts\<file>.dwg,
# which build.bat ships in the bundle, and the catalog src\lsp\45-parts.lsp, which BPPART lists and
# previews (docs/adr/0002). Run it after build.bat whenever a part is added or changed, then
# build.bat again, and commit what it wrote. How to draw a part: DEVELOPING.md, "Adding a part".
#   powershell -ExecutionPolicy Bypass -File src\make_parts.ps1
param(
    [string]$Contents = (Join-Path $PSScriptRoot '..\dist\BPTOOLS.bundle\Contents'),
    [string]$Acad = 'C:\Program Files\Autodesk\AutoCAD 2024'
)
$ErrorActionPreference = 'Stop'
$Contents = (Resolve-Path $Contents).Path
$parts = Join-Path $PSScriptRoot 'parts'
New-Item $parts -ItemType Directory -Force | Out-Null
$library = Join-Path $parts 'library.dwg'
$base = if (Test-Path $library) { $library } else { Join-Path $Acad 'UserDataCache\en-us\Template\acadiso.dwt' }
# A part taken out of library.dwg must not linger as a file.
Get-ChildItem $parts -Filter '*.dwg' | Where-Object { $_.Name -ne 'library.dwg' } | Remove-Item

$work = Join-Path $env:TEMP 'bptools-parts'
if (Test-Path $work) { Remove-Item $work -Recurse -Force }
New-Item $work -ItemType Directory | Out-Null
$c = $Contents -replace '\\', '/'
$s = $PSScriptRoot -replace '\\', '/'
$scr = @"
(setvar "SECURELOAD" 0)
(setvar "FILEDIA" 0)
(setq *bptools-home* "$($Contents -replace '\\', '\\')")
(load "$c/bptools.lsp")
(load "$s/make_parts.lsp")
(bp:ensure-styles)
(mk:dsubs)
(mk:write-library "$($PSScriptRoot -replace '\\', '\\')")
QUIT
Y
"@
$scrPath = Join-Path $work 'make.scr'
[IO.File]::WriteAllText($scrPath, $scr, (New-Object Text.UTF8Encoding($true)))
$out = Join-Path $work 'acad.txt'
$p = Start-Process (Join-Path $Acad 'accoreconsole.exe') -ArgumentList "/i `"$base`" /s `"$scrPath`" /l en-US /isolate bptoolsparts `"$(Join-Path $work 'user')`"" `
    -WorkingDirectory $work -RedirectStandardOutput $out -PassThru -NoNewWindow
# With /isolate, accoreconsole sometimes never exits after QUIT, so stop it once the script is done.
$deadline = (Get-Date).AddSeconds(300)
while (-not $p.WaitForExit(2000)) {
    $sofar = try {
        $fs = [IO.File]::Open($out, 'Open', 'Read', 'ReadWrite')
        try { (New-Object IO.StreamReader($fs, [Text.Encoding]::Unicode)).ReadToEnd() } finally { $fs.Close() }
    } catch { '' }
    if ($sofar -match 'Command: QUIT') { Start-Sleep 3; if (-not $p.HasExited) { $p.Kill() }; break }
    if ((Get-Date) -gt $deadline) { $p.Kill(); break }
}
Start-Sleep -Milliseconds 500
$fs = [IO.File]::Open($out, 'Open', 'Read', 'ReadWrite')
try { $log = (New-Object IO.StreamReader($fs, [Text.Encoding]::Unicode)).ReadToEnd() } finally { $fs.Close() }
if ($log -notmatch 'LIBRARY-WRITTEN=(\d+)\|') { throw "the console AutoCAD did not write the library; see $out" }
$n = [int]$Matches[1]
$files = @(Get-ChildItem $parts -Filter '*.dwg' | Where-Object { $_.Name -ne 'library.dwg' })
if ($files.Count -ne $n) { throw "$n parts listed but $($files.Count) drawings written; see $out" }
Write-Host "Wrote $n parts to $parts and src\lsp\45-parts.lsp"
