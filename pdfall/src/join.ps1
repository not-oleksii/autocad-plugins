# Joins src\lsp\*.lsp in name order into the one pdfall.lsp that AutoCAD loads from the bundle.
# build.bat runs it; the number prefix of each file sets its place.
param([Parameter(Mandatory)] [string] $Out)
$ErrorActionPreference = 'Stop'

$utf8 = New-Object System.Text.UTF8Encoding $false
$parts = foreach ($f in Get-ChildItem (Join-Path $PSScriptRoot 'lsp') -Filter *.lsp | Sort-Object Name) {
    ";;; ==== $($f.Name) " + ('=' * (90 - 10 - $f.Name.Length)) + "`n"
    [IO.File]::ReadAllText($f.FullName, $utf8).TrimEnd() + "`n`n"
}
if (-not $parts) { throw "no .lsp files in $PSScriptRoot\lsp" }
[IO.File]::WriteAllText($Out, ";;; Built by build.bat from src\lsp\*.lsp. Edit those files, not this one.`n`n" + (-join $parts), $utf8)
