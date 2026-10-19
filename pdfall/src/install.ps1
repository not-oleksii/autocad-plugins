# Installs (or with -Uninstall removes) PDFALL for the current Windows user.
# Run it through install.bat or uninstall.bat, with AutoCAD closed.
# -AcadKey, -PluginsDir and -IgnoreRunningAutoCAD exist for tests\install.ps1.
param(
    [switch]$Uninstall,
    [string]$AcadKey = 'HKCU:\Software\Autodesk\AutoCAD',
    [string]$PluginsDir = (Join-Path $env:APPDATA 'Autodesk\ApplicationPlugins'),
    [switch]$IgnoreRunningAutoCAD
)
$ErrorActionPreference = 'Stop'

$src = Join-Path $PSScriptRoot 'PDFALL.bundle'
$dest = Join-Path $PluginsDir 'PDFALL.bundle'
$contents = Join-Path $dest 'Contents'

# What it says is in messages.json, which build.bat puts next to it. Without that file there is
# nothing to say it with, so this one message stays here.
$texts = Join-Path $PSScriptRoot 'messages.json'
if (-not (Test-Path $texts)) {
    Write-Host 'Не виконано: поруч з install.bat немає messages.json. Спершу розпакуйте весь PDFALL.zip.'
    exit 1
}
$messages = (Get-Content $texts -Raw -Encoding UTF8 | ConvertFrom-Json).messages
function Msg($key, $values = @{}) {
    $text = $messages.$key
    foreach ($name in $values.Keys) { $text = $text.Replace("{$name}", [string]$values[$name]) }
    $text
}

# Every AutoCAD 2024-or-later profile of this user, e.g. ...\R24.3\ACAD-7101:409\Profiles\<<Unnamed Profile>>
function Get-AcadProfiles {
    Get-ChildItem $AcadKey -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -match '^R(\d+)\.' -and [int]$Matches[1] -ge 24 } |
        ForEach-Object { Get-ChildItem $_.PSPath } |
        ForEach-Object { Get-ChildItem (Join-Path $_.PSPath 'Profiles') -ErrorAction SilentlyContinue }
}

# Trust the bundle so AutoCAD loads it without asking (only Program Files is trusted by default).
function Set-Trusted($acadProfile, [bool]$trusted) {
    $vars = Join-Path $acadProfile.PSPath 'Variables'
    if (-not (Test-Path $vars)) { New-Item $vars | Out-Null }
    $current = (Get-ItemProperty $vars).TRUSTEDPATHS
    $paths = @("$current" -split ';' | Where-Object { $_ -and $_ -ne $contents })
    if ($trusted) { $paths += $contents }
    Set-ItemProperty $vars TRUSTEDPATHS ($paths -join ';')
}

# Remove pdfall.lsp from the Startup Suite: an older copy loaded there would replace the bundle's PDFALL.
function Remove-StartupCopies($acadProfile) {
    $key = Join-Path $acadProfile.PSPath 'Dialogs\Appload\Startup'
    if (-not (Test-Path $key)) { return }
    $props = Get-ItemProperty $key
    $count = [int]$props.NumStartup
    $files = @(1..$count | Where-Object { $count -gt 0 } | ForEach-Object { $props."$($_)Startup" } | Where-Object { $_ })
    $keep = @($files | Where-Object { (Split-Path $_ -Leaf) -ne 'pdfall.lsp' })
    if ($keep.Count -eq $files.Count) { return }
    foreach ($f in $files | Where-Object { $keep -notcontains $_ }) { Write-Host (Msg 'install.removed-startup' @{ file = $f }) }
    1..$count | ForEach-Object { Remove-ItemProperty $key "$($_)Startup" -ErrorAction SilentlyContinue }
    for ($i = 0; $i -lt $keep.Count; $i++) { Set-ItemProperty $key "$($i + 1)Startup" $keep[$i] }
    Set-ItemProperty $key NumStartup "$($keep.Count)"
}

try {
    if (-not $IgnoreRunningAutoCAD -and (Get-Process acad, accoreconsole -ErrorAction SilentlyContinue)) {
        throw (Msg 'install.acad-running')
    }
    $profiles = @(Get-AcadProfiles)

    if ($Uninstall) {
        if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
        foreach ($p in $profiles) { Set-Trusted $p $false }
        Write-Host (Msg 'install.uninstalled')
        return
    }

    if (-not (Test-Path (Join-Path $src 'PackageContents.xml'))) {
        throw (Msg 'install.no-bundle')
    }
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    New-Item (Split-Path $dest) -ItemType Directory -Force | Out-Null
    Copy-Item $src $dest -Recurse
    foreach ($p in $profiles) {
        Set-Trusted $p $true
        Remove-StartupCopies $p
    }
    if (-not $profiles) {
        Write-Host (Msg 'install.no-profiles')
    }
    $version = ([xml](Get-Content (Join-Path $dest 'PackageContents.xml') -Encoding UTF8)).ApplicationPackage.AppVersion
    Write-Host (Msg 'install.done' @{ version = $version; folder = $dest })
    Write-Host (Msg 'install.next')
}
catch {
    Write-Host (Msg 'install.failed' @{ msg = $_.Exception.Message })
    exit 1
}
