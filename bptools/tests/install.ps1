# Tests dist\install.ps1 of BPTOOLS against a fake AutoCAD registry tree, a temporary plug-ins
# folder, updater folder and Start menu, so the real AutoCAD settings are not touched (AutoCAD may
# stay open). The installer and the shared updater are common code, tested in full by
# ..\pdfall\tests\install.ps1; this checks what BPTOOLS's zip brings.
# Usage: powershell -ExecutionPolicy Bypass -File tests\install.ps1   (run build.bat first)
$ErrorActionPreference = 'Stop'
$dist = Join-Path $PSScriptRoot '..\dist'
$installer = Join-Path $dist 'install.ps1'
$root = 'HKCU:\Software\BptoolsTest'
$acad = "$root\AutoCAD"
$plugins = Join-Path $env:TEMP 'bptools-test-plugins'
$startMenu = Join-Path $env:TEMP 'bptools-test-startmenu'
$updater = Join-Path $env:TEMP 'bptools-test-updater'
$contents = Join-Path $plugins 'BPTOOLS.bundle\Contents'
$messages = (Get-Content (Join-Path $dist 'messages.json') -Raw -Encoding UTF8 | ConvertFrom-Json).messages
$shortcut = Join-Path $startMenu "$($messages.'install.shortcut').lnk"
$guideShortcut = Join-Path $startMenu "$($messages.'install.shortcut-guide'.Replace('{name}', 'BPTOOLS')).lnk"
$common = @{ AcadKey = $acad; PluginsDir = $plugins; StartMenuDir = $startMenu; UpdaterDir = $updater; IgnoreRunningAutoCAD = $true; SuggestAnswer = 'skip' }
$failures = @()
function Check($ok, $what) {
    if ($ok) { Write-Host "  ok    $what" } else { Write-Host "  FAIL  $what"; $script:failures += $what }
}
$cleanup = $root, $plugins, $startMenu, $updater
foreach ($p in $cleanup) { if (Test-Path $p) { Remove-Item $p -Recurse -Force } }
$p24 = "$acad\R24.3\ACAD-7101:409\Profiles\<<Unnamed Profile>>"
New-Item -Path "$p24\Variables" -Force | Out-Null

try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zipFile = [IO.Compression.ZipFile]::OpenRead((Join-Path $dist 'BPTOOLS.zip'))
    $names = @($zipFile.Entries | ForEach-Object { $_.FullName })
    $zipFile.Dispose()
    Check (@('install.bat', 'uninstall.bat', 'guide.html', 'updater/update.ps1', 'BPTOOLS.bundle/plugin.json', 'BPTOOLS.bundle/guide.html',
             'BPTOOLS.bundle/Contents/bptools.lsp', 'BPTOOLS.bundle/Contents/BPTOOLS.dwt', 'BPTOOLS.bundle/Contents/BPTOOLS.cuix' |
        Where-Object { $names -notcontains $_ }).Count -eq 0) 'the zip has the bundle with bptools.lsp, the template, the ribbon and the guide, and the shared installer and updater'

    Write-Host 'Install...'
    $o = & $installer @common *>&1 | Out-String
    Check (Test-Path (Join-Path $contents 'bptools.lsp')) 'the bundle was copied'
    Check ((Get-ItemProperty -LiteralPath "$p24\Variables").TRUSTEDPATHS -eq $contents) 'and trusted'
    Check ((Test-Path (Join-Path $updater 'update.ps1')) -and (Test-Path -LiteralPath $shortcut) -and (Test-Path -LiteralPath $guideShortcut)) `
        'the shared updater and the Start menu entries «Оновити плагіни AutoCAD» and «Інструкція BPTOOLS» are there'
    Check ($o -match 'BPTOOLS \d+\.\d+\.\d+ встановлено' -and $o -match 'вкладку «Креслення»') 'it says what was installed and where to start'

    Write-Host 'Uninstall...'
    & $installer -Uninstall @common | Out-Null
    Check (-not (Test-Path (Join-Path $plugins 'BPTOOLS.bundle')) -and -not (Test-Path -LiteralPath $guideShortcut)) 'the bundle and the guide entry were removed'
    Check (-not (Test-Path $updater) -and -not (Test-Path -LiteralPath $shortcut)) 'with no other plugin, the updater goes too'
}
finally {
    foreach ($p in $cleanup) { if (Test-Path $p) { Remove-Item $p -Recurse -Force } }
}
if ($failures) { Write-Host "FAILED: $($failures -join '; ')"; exit 1 } else { Write-Host 'All passed.' }
