# Tests dist\install.ps1 against a fake AutoCAD registry tree and a temporary plug-ins folder,
# so the real AutoCAD settings are not touched (AutoCAD may stay open).
# Usage: powershell -ExecutionPolicy Bypass -File tests\install.ps1   (run build.bat first)
$ErrorActionPreference = 'Stop'
$installer = Join-Path $PSScriptRoot '..\dist\install.ps1'
$root = 'HKCU:\Software\PdfallTest'
$acad = "$root\AutoCAD"
$plugins = Join-Path $env:TEMP 'pdfall-test-plugins'
$contents = Join-Path $plugins 'PDFALL.bundle\Contents'
$failures = @()
function Check($ok, $what) {
    if ($ok) { Write-Host "  ok    $what" } else { Write-Host "  FAIL  $what"; $script:failures += $what }
}
function Profile2024 { "$acad\R24.3\ACAD-7101:409\Profiles\<<Unnamed Profile>>" }
function Trusted($p) { (Get-ItemProperty -LiteralPath "$p\Variables").TRUSTEDPATHS }

foreach ($p in $root, $plugins) { if (Test-Path $p) { Remove-Item $p -Recurse -Force } }
$p24 = Profile2024
$p23 = "$acad\R23.1\ACAD-3001:419\Profiles\<<Old Profile>>"
$p24b = "$acad\R24.3\ACAD-7101:409\Profiles\Second"
foreach ($k in "$p24\Variables", "$p24\Dialogs\Appload\Startup", "$p23\Variables", $p24b) {
    New-Item -Path $k -Force | Out-Null
}
Set-ItemProperty -LiteralPath "$p24\Variables" TRUSTEDPATHS 'D:\old'
Set-ItemProperty -LiteralPath "$p23\Variables" TRUSTEDPATHS ';'
$startup = "$p24\Dialogs\Appload\Startup"
Set-ItemProperty -LiteralPath $startup NumStartup '3'
Set-ItemProperty -LiteralPath $startup 1Startup 'C:\a.lsp'
Set-ItemProperty -LiteralPath $startup 2Startup 'D:\main\repos\autocad-blueprints\pdfall.lsp'
Set-ItemProperty -LiteralPath $startup 3Startup 'C:\b.lsp'

try {
    Write-Host 'Install...'
    & $installer -AcadKey $acad -PluginsDir $plugins -IgnoreRunningAutoCAD
    & $installer -AcadKey $acad -PluginsDir $plugins -IgnoreRunningAutoCAD | Out-Null   # a second run must change nothing more
    Check (Test-Path (Join-Path $contents 'pdfall.lsp')) 'the bundle was copied'
    Check ((Trusted $p24) -eq "D:\old;$contents") "the bundle is trusted once, old paths kept ($(Trusted $p24))"
    Check ((Trusted $p24b) -eq $contents) 'a profile without Variables gets them'
    Check ((Trusted $p23) -eq ';') 'AutoCAD 2019 is left alone'
    $s = Get-ItemProperty -LiteralPath $startup
    Check ($s.NumStartup -eq '2' -and $s.'1Startup' -eq 'C:\a.lsp' -and $s.'2Startup' -eq 'C:\b.lsp' -and -not $s.'3Startup') `
        'the old pdfall.lsp is removed from the Startup Suite, the rest kept in order'

    Write-Host 'Uninstall...'
    & $installer -Uninstall -AcadKey $acad -PluginsDir $plugins -IgnoreRunningAutoCAD
    Check (-not (Test-Path (Join-Path $plugins 'PDFALL.bundle'))) 'the bundle was removed'
    Check ((Trusted $p24) -eq 'D:\old') 'the trust entry was removed, old paths kept'
}
finally {
    foreach ($p in $root, $plugins) { if (Test-Path $p) { Remove-Item $p -Recurse -Force } }
}
if ($failures) { Write-Host "FAILED: $($failures -join '; ')"; exit 1 } else { Write-Host 'All passed.' }
