# Updates PDFALL from the repository's GitHub releases. Run it through update.bat (the
# "Оновити PDFALL" Start menu entry). It lists every published version; the user picks one with the
# arrow keys, newer or older, and sees what it adds or takes away. Then it downloads that release's
# PDFALL-<version>.zip, checks it against the release's .sha256, waits for AutoCAD to close and runs
# the zip's install.ps1. Without a keyboard (input redirected) it only offers the newest version.
# Only releases tagged pdfall-v<major>.<minor>.<patch> count; drafts and pre-releases are skipped
# (docs/adr/0007-update-from-github-releases.md).
# -AcadKey, -PluginsDir, -StartMenuDir, -IgnoreRunningAutoCAD, -ReleasesUrl, -Yes and -Keys exist for
# tests\install.ps1. -Keys stands in for the keyboard: key names such as DownArrow,Enter.
param(
    [string]$AcadKey = 'HKCU:\Software\Autodesk\AutoCAD',
    [string]$PluginsDir = (Join-Path $env:APPDATA 'Autodesk\ApplicationPlugins'),
    [string]$StartMenuDir = (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'),
    [string]$ReleasesUrl = 'https://api.github.com/repos/not-oleksii/autocad-plugins/releases?per_page=100',
    [switch]$IgnoreRunningAutoCAD,
    [switch]$Yes,
    [string[]]$Keys
)
# -File passes "DownArrow,Enter" as one string.
$Keys = @($Keys | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
$ErrorActionPreference = 'Stop'
# The progress bar makes Invoke-WebRequest many times slower in Windows PowerShell.
$ProgressPreference = 'SilentlyContinue'
# Output sent to a file (as tests\install.ps1 does) is UTF-8, so the Ukrainian text survives.
if ([Console]::IsOutputRedirected) { [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false) }
# Windows PowerShell may not offer TLS 1.2 by itself, and GitHub accepts nothing older.
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
# This script may be in the bundle that the update replaces, and Windows can't delete a folder that
# is a program's current folder. PowerShell sets the process's folder to its own location now and
# then, so both move.
Set-Location $env:TEMP
[Environment]::CurrentDirectory = $env:TEMP

$texts = Join-Path $PSScriptRoot 'messages.json'
if (-not (Test-Path $texts)) {
    Write-Host 'Не виконано: поруч з update.bat немає messages.json. Встановіть PDFALL заново з PDFALL.zip.'
    exit 1
}
$messages = (Get-Content $texts -Raw -Encoding UTF8 | ConvertFrom-Json).messages
function Msg($key, $values = @{}) {
    $text = $messages.$key
    foreach ($name in $values.Keys) { $text = $text.Replace("{$name}", [string]$values[$name]) }
    $text
}

function Get-File($url, $path) {
    Invoke-WebRequest $url -OutFile $path -UseBasicParsing
}

# Every published PDFALL release as { Version, Release }, newest first. The JSON is saved and read
# as UTF-8, because Invoke-RestMethod may decode the Ukrainian notes with the wrong encoding.
function Get-Releases {
    $file = Join-Path $work 'releases.json'
    try { Get-File $ReleasesUrl $file }
    catch { throw (Msg 'update.offline' @{ msg = $_.Exception.Message }) }
    $all = Get-Content $file -Raw -Encoding UTF8 | ConvertFrom-Json
    $found = foreach ($r in $all) {
        if ($r.draft -or $r.prerelease -or $r.tag_name -notmatch '^pdfall-v(\d+\.\d+\.\d+)$') { continue }
        [pscustomobject]@{ Version = [version]$Matches[1]; Release = $r }
    }
    @($found | Sort-Object Version -Descending)
}

# A release's notes as plain lines for the console: the Markdown marks dropped, and nothing from the
# first "---" line on (the install help that release.ps1 adds for the GitHub page).
function Get-NoteLines($body) {
    $lines = @("$body" -split "\r?\n")
    $cut = [array]::IndexOf($lines, '---')
    if ($cut -ge 0) { $lines = @($lines | Select-Object -First $cut) }
    $lines = @($lines | ForEach-Object {
        $_ -replace '^#+\s*', '' -replace '\*\*|__|`', '' -replace '\[([^\]]+)\]\([^)]+\)', '$1'
    })
    while ($lines.Count -and -not $lines[0].Trim()) { $lines = @($lines | Select-Object -Skip 1) }
    if (-not ($lines -join '').Trim()) { $lines = @(Msg 'update.no-notes') }
    $lines | ForEach-Object { "    $_".TrimEnd() }
}

function Write-Notes($body) { foreach ($line in Get-NoteLines $body) { Write-Host $line } }

function Get-Title($r) {
    $date = if ($r.Release.published_at) { ([datetime]$r.Release.published_at).ToString('dd.MM.yyyy') } else { '' }
    Msg 'update.release' @{ version = $r.Version; date = $date }
}

# What installing $pick does, as text for the console.
function Get-Action($pick) {
    if (-not $installed) { Msg 'update.action-install' @{ version = $pick.Version } }
    elseif ($pick.Version -gt $installed) { Msg 'update.action-update' @{ version = $pick.Version } }
    elseif ($pick.Version -lt $installed) { Msg 'update.action-back' @{ version = $pick.Version } }
    else { Msg 'update.action-reinstall' @{ version = $pick.Version } }
}

# The notes of every version that installing $pick adds (it is newer than the installed one) or takes
# away (it is older), newest first.
function Get-ChoiceLines($pick) {
    $lines = @()
    # Versions before 1.8.0 have no updater, so there is no way back from them but by hand.
    if ($pick.Version -lt [version]'1.8.0') { $lines += Msg 'update.no-updater' @{ version = $pick.Version }; $lines += '' }
    if ($installed -and $pick.Version -eq $installed) { return $lines + @(Msg 'update.same' @{ version = $pick.Version }) }
    if (-not $installed -or $pick.Version -gt $installed) {
        $lines += Msg 'update.gains' @{ version = $pick.Version }
        $span = $releases | Where-Object { $_.Version -le $pick.Version -and (-not $installed -or $_.Version -gt $installed) }
    }
    else {
        $lines += Msg 'update.loses' @{ version = $pick.Version }
        $span = $releases | Where-Object { $_.Version -gt $pick.Version -and $_.Version -le $installed }
    }
    foreach ($r in $span) { $lines += ''; $lines += '  ' + (Get-Title $r); $lines += @(Get-NoteLines $r.Release.body) }
    $lines
}

# Lets the user pick a release with the arrow keys, starting at $releases[$i]: up or right for a newer
# one, down or left for an older one, Enter to install it, Esc to stop. Returns it, or $null.
function Select-Release($i) {
    $screen = -not [Console]::IsOutputRedirected
    $queue = New-Object Collections.Queue
    foreach ($k in $Keys) { $queue.Enqueue($k) }
    try {
        if ($screen) { [Console]::CursorVisible = $false }
        while ($true) {
            $pick = $releases[$i]
            if ($screen) { Clear-Host }
            $installedLine = if ($installed) { Msg 'update.installed' @{ version = $installed } } else { Msg 'update.not-installed' }
            Write-Host $installedLine
            Write-Host ''
            Write-Host (Msg 'update.pick')
            for ($j = 0; $j -lt $releases.Count; $j++) {
                $r = $releases[$j]
                $tags = @()
                if ($j -eq 0) { $tags += Msg 'update.tag-latest' }
                if ($installed -and $r.Version -eq $installed) { $tags += Msg 'update.tag-installed' }
                $line = (Get-Title $r) + $(if ($tags) { '  — ' + ($tags -join ', ') } else { '' })
                if ($j -eq $i) { Write-Host "  > $line " -ForegroundColor Black -BackgroundColor Gray } else { Write-Host "    $line" }
            }
            Write-Host ''
            $body = @(Get-ChoiceLines $pick)
            if ($screen) {
                # Keep the list on screen: long notes are cut to the window.
                $room = $Host.UI.RawUI.WindowSize.Height - $releases.Count - 8
                if ($room -lt 3) { $room = 3 }
                if ($body.Count -gt $room) { $body = @($body | Select-Object -First ($room - 1)) + @(Msg 'update.more' @{ n = $body.Count - $room + 1 }) }
            }
            foreach ($line in $body) { Write-Host $line }
            Write-Host ''
            Write-Host (Msg 'update.keys' @{ action = (Get-Action $pick) })
            if ($Keys) {
                if ($queue.Count -eq 0) { return $null }
                $key = $queue.Dequeue(); $char = ''
            }
            else {
                $info = [Console]::ReadKey($true)
                $key = [string]$info.Key; $char = [string]$info.KeyChar
            }
            if (@('н', 'n') -contains $char.ToLower()) { $key = 'Escape' }
            switch ($key) {
                { 'UpArrow', 'RightArrow' -contains $_ } { if ($i -gt 0) { $i-- } }
                { 'DownArrow', 'LeftArrow' -contains $_ } { if ($i -lt $releases.Count - 1) { $i++ } }
                'Home' { $i = 0 }
                'End' { $i = $releases.Count - 1 }
                'Enter' { Write-Host ''; return $pick }
                'Escape' { Write-Host ''; return $null }
            }
        }
    }
    finally { if ($screen) { [Console]::CursorVisible = $true } }
}

function Confirm-Update($question) {
    if ($Yes) { return $true }
    while ($true) {
        $answer = (Read-Host $question).Trim().ToLower()
        if (@('', 'т', 'так', 'y', 'yes') -contains $answer) { return $true }
        if (@('н', 'ні', 'n', 'no') -contains $answer) { return $false }
    }
}

$work = Join-Path $env:TEMP "pdfall-update-$PID"
try {
    New-Item $work -ItemType Directory -Force | Out-Null
    Write-Host (Msg 'update.checking')
    $manifest = Join-Path $PluginsDir 'PDFALL.bundle\PackageContents.xml'
    $installed = if (Test-Path $manifest) {
        [version]([xml](Get-Content $manifest -Encoding UTF8)).ApplicationPackage.AppVersion
    }
    $releases = Get-Releases
    if (-not $releases) { Write-Host (Msg 'update.none-published'); return }
    $latest = $releases[0]

    if ($Keys -or (-not $Yes -and -not [Console]::IsInputRedirected)) {
        # Start at the newest version when it is an update, else at the installed one.
        $start = 0
        if ($installed -and $installed -ge $latest.Version) {
            for ($j = 0; $j -lt $releases.Count; $j++) { if ($releases[$j].Version -le $installed) { $start = $j; break } }
        }
        $chosen = Select-Release $start
        if (-not $chosen) { Write-Host (Msg 'update.cancelled'); return }
    }
    else {
        Write-Host ''
        if ($installed) { Write-Host (Msg 'update.installed' @{ version = $installed }) } else { Write-Host (Msg 'update.not-installed') }
        Write-Host (Msg 'update.latest' @{ version = $latest.Version })
        if ($installed -and $installed -ge $latest.Version) {
            Write-Host ''
            if ($installed -eq $latest.Version) { Write-Host (Msg 'update.up-to-date') } else { Write-Host (Msg 'update.newer-installed') }
            return
        }

        Write-Host ''
        Write-Host (Msg 'update.changes')
        foreach ($r in $releases | Where-Object { -not $installed -or $_.Version -gt $installed }) {
            Write-Host ''
            Write-Host ('  ' + (Get-Title $r))
            Write-Notes $r.Release.body
        }
        Write-Host ''
        $question = if ($installed) { Msg 'update.ask' @{ from = $installed; to = $latest.Version } } else { Msg 'update.ask-install' @{ to = $latest.Version } }
        if (-not (Confirm-Update $question)) { Write-Host (Msg 'update.cancelled'); return }
        $chosen = $latest
    }

    $name = "PDFALL-$($chosen.Version).zip"
    $zipAsset = $chosen.Release.assets | Where-Object { $_.name -eq $name } | Select-Object -First 1
    $sumAsset = $chosen.Release.assets | Where-Object { $_.name -eq "$name.sha256" } | Select-Object -First 1
    foreach ($pair in @(@($zipAsset, $name), @($sumAsset, "$name.sha256"))) {
        if (-not $pair[0]) { throw (Msg 'update.no-asset' @{ version = $chosen.Version; file = $pair[1] }) }
    }
    $zip = Join-Path $work $name
    $sum = Join-Path $work "$name.sha256"
    Write-Host (Msg 'update.downloading' @{ file = $name })
    try {
        Get-File $zipAsset.browser_download_url $zip
        Get-File $sumAsset.browser_download_url $sum
    }
    catch { throw (Msg 'update.offline' @{ msg = $_.Exception.Message }) }
    # The .sha256 is "<hash>  <file name>", as sha256sum writes it.
    $expected = ((Get-Content $sum -Raw).Trim() -split '\s+')[0].ToLower()
    if ((Get-FileHash $zip -Algorithm SHA256).Hash.ToLower() -ne $expected) {
        throw (Msg 'update.bad-hash' @{ file = $name; sum = "$name.sha256" })
    }
    $unpacked = Join-Path $work 'PDFALL'
    Expand-Archive $zip $unpacked

    if (-not $IgnoreRunningAutoCAD -and (Get-Process acad, accoreconsole -ErrorAction SilentlyContinue)) {
        Write-Host (Msg 'update.close-acad')
        while (Get-Process acad, accoreconsole -ErrorAction SilentlyContinue) { Start-Sleep 2 }
        # AutoCAD writes its settings to the registry as it closes; let it finish first.
        Start-Sleep 3
    }
    Write-Host ''
    $installArgs = @{ AcadKey = $AcadKey; PluginsDir = $PluginsDir; StartMenuDir = $StartMenuDir; IgnoreRunningAutoCAD = [bool]$IgnoreRunningAutoCAD }
    $global:LASTEXITCODE = 0
    & (Join-Path $unpacked 'install.ps1') @installArgs
    if ($LASTEXITCODE -ne 0) { exit 1 }
}
catch {
    Write-Host (Msg 'update.failed' @{ msg = $_.Exception.Message })
    exit 1
}
finally {
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}
