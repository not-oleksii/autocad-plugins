# Installs (or with -Uninstall removes) the plugin whose <NAME>.bundle lies next to this file, for the
# current Windows user, together with the updater every plugin shares. Run it through install.bat or
# uninstall.bat, with AutoCAD closed; the updater runs the install.ps1 of the release it downloaded.
# The same file is in every plugin's zip (../docs/adr/0001-one-updater-for-every-plugin.md):
#   - the bundle goes to %APPDATA%\Autodesk\ApplicationPlugins and is trusted in every AutoCAD 2021+
#     profile;
#   - updater\ goes to %LOCALAPPDATA%\AutoCAD plugins, unless a newer one is there (version.txt);
#   - the Start menu gets «Оновити плагіни AutoCAD» and the plugin's guide, and loses the plugin's
#     own «Оновити <NAME>» that versions before the shared updater made.
# Then it offers once each plugin that this one suggests (plugin.json "suggests"), unless it is
# installed already or the user said no before, and the updater installs it.
# Uninstalling removes the bundle, and the updater too once no other plugin is left.
# -AcadKey, -PluginsDir, -StartMenuDir, -UpdaterDir, -IgnoreRunningAutoCAD and -ReleasesUrl (handed
# to the updater) exist for the tests; -SuggestAnswer answers the offer instead of the user (y, n,
# or anything else to skip it). -WaitForPrograms is passed by the updater: wait for the bundle's
# programs to close instead of stopping.
param(
    [switch]$Uninstall,
    [string]$AcadKey = 'HKCU:\Software\Autodesk\AutoCAD',
    [string]$PluginsDir = (Join-Path $env:APPDATA 'Autodesk\ApplicationPlugins'),
    [string]$StartMenuDir = (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'),
    [string]$UpdaterDir = (Join-Path $env:LOCALAPPDATA 'AutoCAD plugins'),
    [switch]$IgnoreRunningAutoCAD,
    [switch]$WaitForPrograms,
    [string]$SuggestAnswer = '',
    [string]$ReleasesUrl = ''
)
$ErrorActionPreference = 'Stop'

# What it says is in messages.json, which the build puts next to it. Without that file there is
# nothing to say it with, so this one message stays here.
$texts = Join-Path $PSScriptRoot 'messages.json'
if (-not (Test-Path $texts)) {
    Write-Host 'Не виконано: поруч з install.bat немає messages.json. Спершу розпакуйте весь zip.'
    exit 1
}
$messages = (Get-Content $texts -Raw -Encoding UTF8 | ConvertFrom-Json).messages
function Msg($key, $values = @{}) {
    $text = $messages.$key
    foreach ($name in $values.Keys) { $text = $text.Replace("{$name}", [string]$values[$name]) }
    $text
}

$src = Get-ChildItem $PSScriptRoot -Directory -Filter '*.bundle' | Select-Object -First 1
$name = if ($src) { $src.Name -replace '\.bundle$', '' } else { '' }
$dest = Join-Path $PluginsDir "$name.bundle"
$contents = Join-Path $dest 'Contents'
$updaterSrc = Join-Path $PSScriptRoot 'updater'
$updaterLink = Join-Path $StartMenuDir "$(Msg 'install.shortcut').lnk"
$guideLink = Join-Path $StartMenuDir "$(Msg 'install.shortcut-guide' @{ name = $name }).lnk"
$oldUpdateLink = Join-Path $StartMenuDir "$(Msg 'install.old-shortcut' @{ name = $name }).lnk"

# The programs of the installed bundle that still run, as the user knows them: merge.exe's window
# stays open until Enter, and Windows won't let a running program be replaced or removed.
function Get-OpenPrograms {
    @(Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -and $_.Path.StartsWith("$dest\", [StringComparison]::OrdinalIgnoreCase) } |
        ForEach-Object { $text = $messages."program.$($_.ProcessName.ToLower())"; if ($text) { $text } else { "$($_.ProcessName).exe" } } |
        Select-Object -Unique)
}

# Every AutoCAD R24 (2021) or later profile of this user, e.g. ...\R24.3\ACAD-7101:409\Profiles\<<Unnamed Profile>>
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

# Remove the plugin's .lsp from the Startup Suite: an older copy loaded there would replace the bundle's.
function Remove-StartupCopies($acadProfile) {
    $key = Join-Path $acadProfile.PSPath 'Dialogs\Appload\Startup'
    if (-not (Test-Path $key)) { return }
    $props = Get-ItemProperty $key
    $count = [int]$props.NumStartup
    $files = @(1..$count | Where-Object { $count -gt 0 } | ForEach-Object { $props."$($_)Startup" } | Where-Object { $_ })
    $keep = @($files | Where-Object { (Split-Path $_ -Leaf) -ne "$($name.ToLower()).lsp" })
    if ($keep.Count -eq $files.Count) { return }
    foreach ($f in $files | Where-Object { $keep -notcontains $_ }) { Write-Host (Msg 'install.removed-startup' @{ file = $f }) }
    1..$count | ForEach-Object { Remove-ItemProperty $key "$($_)Startup" -ErrorAction SilentlyContinue }
    for ($i = 0; $i -lt $keep.Count; $i++) { Set-ItemProperty $key "$($i + 1)Startup" $keep[$i] }
    Set-ItemProperty $key NumStartup "$($keep.Count)"
}

function Get-UpdaterVersion($dir) {
    $file = Join-Path $dir 'version.txt'
    if (Test-Path $file) { [long](Get-Content $file -Raw).Trim() } else { [long]-1 }
}

# The shared updater, unless the one installed is newer: an older plugin zip must not take it back.
# Its files are overwritten, not the folder replaced, since the update that runs this may run from it.
function Install-Updater {
    if ((Get-UpdaterVersion $updaterSrc) -le (Get-UpdaterVersion $UpdaterDir)) { return }
    New-Item $UpdaterDir -ItemType Directory -Force | Out-Null
    Copy-Item (Join-Path $updaterSrc '*') $UpdaterDir -Recurse -Force
}

# A Start menu entry. It starts in %TEMP%, because an update replaces the folders the files are in,
# and Windows can't delete a folder that a program is working in.
function Set-Shortcut($path, $target, $title) {
    try {
        New-Item $StartMenuDir -ItemType Directory -Force | Out-Null
        $link = (New-Object -ComObject WScript.Shell).CreateShortcut($path)
        $link.TargetPath = $target
        $link.WorkingDirectory = $env:TEMP
        $link.Description = $title
        $link.Save()
    }
    catch {
        Write-Host (Msg 'install.no-shortcut' @{ shortcut = $title; msg = $_.Exception.Message; file = $target })
    }
}

function Remove-Link($path) { if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force } }

# The plugins this one suggests, each offered once: not when it is installed already or the user said
# no before, which declined.txt in the updater's folder remembers. A yes runs the updater on it.
function Invoke-Suggestions {
    $suggests = @((Get-Content (Join-Path $src.FullName 'plugin.json') -Raw -Encoding UTF8 | ConvertFrom-Json).suggests | Where-Object { $_ })
    $declinedFile = Join-Path $UpdaterDir 'declined.txt'
    $declined = if (Test-Path $declinedFile) { @(Get-Content $declinedFile) } else { @() }
    foreach ($s in $suggests) {
        if ((Test-Path (Join-Path $PluginsDir "$s.bundle")) -or $declined -contains $s) { continue }
        $answer = $SuggestAnswer
        if (-not $answer) {
            if ([Console]::IsInputRedirected) { continue }
            $about = $messages."suggest.$($s.ToLower())"
            Write-Host ''
            $answer = Read-Host (Msg 'install.suggest' @{ plugin = $(if ($about) { $about } else { $s }) })
        }
        $answer = "$answer".Trim().ToLower()
        if (@('', 'т', 'так', 'y', 'yes') -contains $answer) {
            $updateArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $UpdaterDir 'update.ps1'), '-Install', $s,
                '-AcadKey', $AcadKey, '-PluginsDir', $PluginsDir, '-StartMenuDir', $StartMenuDir)
            if ($ReleasesUrl) { $updateArgs += @('-ReleasesUrl', $ReleasesUrl) }
            if ($IgnoreRunningAutoCAD) { $updateArgs += '-IgnoreRunningAutoCAD' }
            & powershell @updateArgs
        }
        elseif (@('н', 'ні', 'n', 'no') -contains $answer) {
            Add-Content $declinedFile $s
            Write-Host (Msg 'install.suggest-later' @{ plugin = $s; shortcut = (Msg 'install.shortcut') })
        }
    }
}

# Whether another plugin that uses the shared updater is still installed.
function Test-OtherPlugins {
    [bool](Get-ChildItem $PluginsDir -Directory -Filter '*.bundle' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne "$name.bundle" -and (Test-Path (Join-Path $_.FullName 'plugin.json')) })
}

try {
    if (-not $src -or -not (Test-Path (Join-Path $src.FullName 'PackageContents.xml'))) {
        throw (Msg 'install.no-bundle')
    }
    if (-not $IgnoreRunningAutoCAD -and (Get-Process acad, accoreconsole -ErrorAction SilentlyContinue)) {
        throw (Msg 'install.acad-running')
    }
    $open = Get-OpenPrograms
    if ($open -and $WaitForPrograms) {
        Write-Host (Msg 'install.close-program' @{ program = ($open -join ', ') })
        while (Get-OpenPrograms) { Start-Sleep 2 }
    }
    elseif ($open) { throw (Msg 'install.program-running' @{ program = ($open -join ', ') }) }
    $profiles = @(Get-AcadProfiles)

    if ($Uninstall) {
        if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
        Remove-Link $guideLink
        Remove-Link $oldUpdateLink
        if (-not (Test-OtherPlugins)) {
            Remove-Link $updaterLink
            if (Test-Path $UpdaterDir) { Remove-Item $UpdaterDir -Recurse -Force }
        }
        foreach ($p in $profiles) { Set-Trusted $p $false }
        Write-Host (Msg 'install.uninstalled' @{ name = $name })
        return
    }

    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    New-Item $PluginsDir -ItemType Directory -Force | Out-Null
    Copy-Item $src.FullName $dest -Recurse
    foreach ($p in $profiles) {
        Set-Trusted $p $true
        Remove-StartupCopies $p
    }
    if (-not $profiles) {
        Write-Host (Msg 'install.no-profiles' @{ name = $name })
    }
    Install-Updater
    $version = ([xml](Get-Content (Join-Path $dest 'PackageContents.xml') -Encoding UTF8)).ApplicationPackage.AppVersion
    Write-Host (Msg 'install.done' @{ name = $name; version = $version; folder = $dest })
    Write-Host (Msg 'install.next')

    Remove-Link $oldUpdateLink
    Set-Shortcut $updaterLink (Join-Path $UpdaterDir 'update.bat') (Msg 'install.shortcut')
    $guide = Join-Path $dest 'guide.html'
    if (Test-Path $guide) {
        Set-Shortcut $guideLink $guide (Msg 'install.shortcut-guide' @{ name = $name })
        Write-Host (Msg 'install.update-hint' @{ name = $name; shortcut = (Msg 'install.shortcut'); guide = (Msg 'install.shortcut-guide' @{ name = $name }) })
    }
    else { Write-Host (Msg 'install.update-hint-short' @{ name = $name; shortcut = (Msg 'install.shortcut') }) }
    Invoke-Suggestions
}
catch {
    Write-Host (Msg 'install.failed' @{ msg = $_.Exception.Message })
    exit 1
}
