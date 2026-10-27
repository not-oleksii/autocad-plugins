# Updates the AutoCAD plugins of this repository from its GitHub releases. Run it through update.bat
# (the «Оновити плагіни AutoCAD» Start menu entry); every plugin's install.ps1 puts both in
# %LOCALAPPDATA%\AutoCAD plugins (../../docs/adr/0001-one-updater-for-every-plugin.md).
#
# It lists every plugin that has a release, with the version installed and the newest one, and
# «Оновити все» under them. Enter on a plugin opens its versions: the user picks one with the arrow
# keys, newer or older, and sees what it changes; Esc goes back to the list. «Оновити все» installs
# the newest version of every installed plugin that has a newer one; a plugin that isn't installed
# is installed only when picked. Then it downloads each release's <NAME>-<version>.zip, checks it
# against the release's .sha256, waits once for AutoCAD to close and runs each zip's install.ps1.
# Without a keyboard (input redirected) it only offers «Оновити все».
# A release counts when it is tagged <name>-v<major>.<minor>.<patch> and is neither a draft nor a
# pre-release (../../pdfall/docs/adr/0007-update-from-github-releases.md).
# -AcadKey, -PluginsDir, -StartMenuDir, -UpdaterDir, -IgnoreRunningAutoCAD, -ReleasesUrl, -Yes and
# -Keys exist for the tests. -Keys stands in for the keyboard: key names such as DownArrow,Enter.
param(
    [string]$AcadKey = 'HKCU:\Software\Autodesk\AutoCAD',
    [string]$PluginsDir = (Join-Path $env:APPDATA 'Autodesk\ApplicationPlugins'),
    [string]$StartMenuDir = (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'),
    [string]$UpdaterDir = $PSScriptRoot,
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
# Output sent to a file (as the tests do) is UTF-8, so the Ukrainian text survives.
if ([Console]::IsOutputRedirected) { [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false) }
# Windows PowerShell may not offer TLS 1.2 by itself, and GitHub accepts nothing older.
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
# An install overwrites this script's folder, and Windows can't delete a folder that is a program's
# current folder. PowerShell sets the process's folder to its own location now and then, so both move.
Set-Location $env:TEMP
[Environment]::CurrentDirectory = $env:TEMP

$texts = Join-Path $PSScriptRoot 'messages.json'
if (-not (Test-Path $texts)) {
    Write-Host 'Не виконано: поруч з update.bat немає messages.json. Встановіть будь-який плагін заново з його zip.'
    exit 1
}
$messages = (Get-Content $texts -Raw -Encoding UTF8 | ConvertFrom-Json).messages
function Msg($key, $values = @{}) {
    $text = $messages.$key
    foreach ($name in $values.Keys) { $text = $text.Replace("{$name}", [string]$values[$name]) }
    $text
}

# The first version of each plugin that installs this updater. An older one, picked to go back to,
# brings back its own «Оновити <NAME>» Start menu entry next to it.
$sharedSince = @{ PDFALL = [version]'1.12.0' }

$queue = New-Object Collections.Queue
foreach ($k in $Keys) { $queue.Enqueue($k) }
$screen = -not [Console]::IsOutputRedirected

# The next key as (name, character), from -Keys or the keyboard; Escape once -Keys runs out.
function Read-Key {
    if ($Keys) {
        if ($queue.Count -eq 0) { return @('Escape', '') }
        return @($queue.Dequeue(), '')
    }
    $info = [Console]::ReadKey($true)
    $key = [string]$info.Key
    if (@('н', 'n') -contains ([string]$info.KeyChar).ToLower()) { $key = 'Escape' }
    @($key, [string]$info.KeyChar)
}

function Get-File($url, $path) {
    Invoke-WebRequest $url -OutFile $path -UseBasicParsing
}

# Every plugin with a published release, by name: { Name, Releases (newest first, each { Version,
# Release }), Installed (the version in the plug-ins folder, or $null) }. The JSON is saved and read
# as UTF-8, because Invoke-RestMethod may decode the Ukrainian notes with the wrong encoding.
function Get-Plugins {
    $file = Join-Path $work 'releases.json'
    try { Get-File $ReleasesUrl $file }
    catch { throw (Msg 'update.offline' @{ msg = $_.Exception.Message }) }
    $all = Get-Content $file -Raw -Encoding UTF8 | ConvertFrom-Json
    $found = foreach ($r in $all) {
        if ($r.draft -or $r.prerelease -or $r.tag_name -cnotmatch '^([a-z][a-z0-9]*)-v(\d+\.\d+\.\d+)$') { continue }
        [pscustomobject]@{ Name = $Matches[1].ToUpper(); Version = [version]$Matches[2]; Release = $r }
    }
    @($found | Group-Object Name | Sort-Object Name | ForEach-Object {
        $manifest = Join-Path $PluginsDir "$($_.Name).bundle\PackageContents.xml"
        [pscustomobject]@{
            Name = $_.Name
            Releases = @($_.Group | Sort-Object Version -Descending)
            Installed = if (Test-Path $manifest) { [version]([xml](Get-Content $manifest -Encoding UTF8)).ApplicationPackage.AppVersion }
        }
    })
}

# The installed plugins that have a newer version, each as { Plugin, Release } of the newest one.
function Get-Outdated {
    @($plugins | Where-Object { $_.Installed -and $_.Releases[0].Version -gt $_.Installed } |
        ForEach-Object { [pscustomobject]@{ Plugin = $_; Release = $_.Releases[0] } })
}

# Those plugins as "PDFALL 1.11.0 → 1.12.0, ...".
function Get-OutdatedList($outdated) {
    ($outdated | ForEach-Object { Msg 'update.all-item' @{ name = $_.Plugin.Name; from = $_.Plugin.Installed; to = $_.Release.Version } }) -join ', '
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

function Get-Title($plugin, $r) {
    $date = if ($r.Release.published_at) { ([datetime]$r.Release.published_at).ToString('dd.MM.yyyy') } else { '' }
    Msg 'update.release' @{ name = $plugin.Name; version = $r.Version; date = $date }
}

# What installing $pick of $plugin does, as text for the console.
function Get-Action($plugin, $pick) {
    if (-not $plugin.Installed) { Msg 'update.action-install' @{ version = $pick.Version } }
    elseif ($pick.Version -gt $plugin.Installed) { Msg 'update.action-update' @{ version = $pick.Version } }
    elseif ($pick.Version -lt $plugin.Installed) { Msg 'update.action-back' @{ version = $pick.Version } }
    else { Msg 'update.action-reinstall' @{ version = $pick.Version } }
}

# The notes of $pick alone, under its name.
function Get-ChoiceLines($plugin, $pick) {
    $lines = @()
    $since = $sharedSince[$plugin.Name]
    if ($since -and $pick.Version -lt $since) { $lines += Msg 'update.old-version' @{ name = $plugin.Name; version = $pick.Version }; $lines += '' }
    $lines += Get-Title $plugin $pick
    $lines + @(Get-NoteLines $pick.Release.body)
}

function Write-Line($line, $chosen) {
    if ($chosen) { Write-Host "  > $line " -ForegroundColor Black -BackgroundColor Gray } else { Write-Host "    $line" }
}

# The list of plugins and «Оновити все» under them. Returns the plugin picked, 'all', or $null for Esc.
function Select-Plugin {
    $outdated = @(Get-Outdated)
    $i = if ($outdated) { $plugins.Count } else { 0 }
    while ($true) {
        if ($screen) { Clear-Host }
        Write-Host (Msg 'update.plugins')
        for ($j = 0; $j -lt $plugins.Count; $j++) {
            $p = $plugins[$j]
            $latest = $p.Releases[0].Version
            $line = if (-not $p.Installed) { Msg 'update.plugin-new' @{ name = $p.Name; latest = $latest } }
                    elseif ($latest -gt $p.Installed) { Msg 'update.plugin-update' @{ name = $p.Name; installed = $p.Installed; latest = $latest } }
                    else { Msg 'update.plugin-current' @{ name = $p.Name; installed = $p.Installed } }
            Write-Line $line ($j -eq $i)
        }
        Write-Host '    ─────'
        $all = if ($outdated) { Msg 'update.all' @{ list = (Get-OutdatedList $outdated) } } else { Msg 'update.all-none' }
        Write-Line $all ($i -eq $plugins.Count)
        Write-Host ''
        $action = if ($i -eq $plugins.Count) { Msg 'update.action-all' } else { Msg 'update.open' @{ name = $plugins[$i].Name } }
        Write-Host (Msg 'update.plugins-keys' @{ action = $action })
        $key = (Read-Key)[0]
        switch ($key) {
            { 'UpArrow', 'LeftArrow' -contains $_ } { if ($i -gt 0) { $i-- } }
            { 'DownArrow', 'RightArrow' -contains $_ } { if ($i -lt $plugins.Count) { $i++ } }
            'Home' { $i = 0 }
            'End' { $i = $plugins.Count }
            'Enter' { Write-Host ''; if ($i -eq $plugins.Count) { return 'all' } else { return $plugins[$i] } }
            'Escape' { Write-Host ''; return $null }
        }
    }
}

# Lets the user pick a release of $plugin with the arrow keys: up or right for a newer one, down or
# left for an older one, Enter to install it, Esc to go back. It starts at the newest version when
# that is an update, else at the installed one. Returns the release, or $null.
function Select-Release($plugin) {
    $releases = $plugin.Releases
    $installed = $plugin.Installed
    $i = 0
    if ($installed -and $installed -ge $releases[0].Version) {
        for ($j = 0; $j -lt $releases.Count; $j++) { if ($releases[$j].Version -le $installed) { $i = $j; break } }
    }
    try {
        if ($screen) { [Console]::CursorVisible = $false }
        while ($true) {
            $pick = $releases[$i]
            if ($screen) { Clear-Host }
            $installedLine = if ($installed) { Msg 'update.installed' @{ name = $plugin.Name; version = $installed } } else { Msg 'update.not-installed' }
            Write-Host $installedLine
            Write-Host ''
            Write-Host (Msg 'update.pick')
            for ($j = 0; $j -lt $releases.Count; $j++) {
                $r = $releases[$j]
                $tags = @()
                if ($j -eq 0) { $tags += Msg 'update.tag-latest' }
                if ($installed -and $r.Version -eq $installed) { $tags += Msg 'update.tag-installed' }
                Write-Line ((Get-Title $plugin $r) + $(if ($tags) { '  — ' + ($tags -join ', ') } else { '' })) ($j -eq $i)
            }
            Write-Host ''
            $body = @(Get-ChoiceLines $plugin $pick)
            if ($screen) {
                # Keep the list on screen: long notes are cut to the window.
                $room = $Host.UI.RawUI.WindowSize.Height - $releases.Count - 8
                if ($room -lt 3) { $room = 3 }
                if ($body.Count -gt $room) { $body = @($body | Select-Object -First ($room - 1)) + @(Msg 'update.more' @{ n = $body.Count - $room + 1 }) }
            }
            foreach ($line in $body) { Write-Host $line }
            Write-Host ''
            Write-Host (Msg 'update.keys' @{ action = (Get-Action $plugin $pick) })
            switch ((Read-Key)[0]) {
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

# Downloads release $r of $plugin, checks it against its .sha256 and unpacks it. Returns the folder.
function Get-Release($plugin, $r) {
    $name = "$($plugin.Name)-$($r.Version).zip"
    $zipAsset = $r.Release.assets | Where-Object { $_.name -eq $name } | Select-Object -First 1
    $sumAsset = $r.Release.assets | Where-Object { $_.name -eq "$name.sha256" } | Select-Object -First 1
    foreach ($pair in @(@($zipAsset, $name), @($sumAsset, "$name.sha256"))) {
        if (-not $pair[0]) { throw (Msg 'update.no-asset' @{ version = "$($plugin.Name) $($r.Version)"; file = $pair[1] }) }
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
    $unpacked = Join-Path $work $plugin.Name
    Expand-Archive $zip $unpacked
    $unpacked
}

# Runs the install.ps1 of an unpacked release with the arguments it knows: an older release's
# install.ps1 has neither -UpdaterDir nor -WaitForPrograms.
function Invoke-Install($unpacked) {
    $script = Join-Path $unpacked 'install.ps1'
    $known = (Get-Command $script).Parameters.Keys
    $installArgs = @{ AcadKey = $AcadKey; PluginsDir = $PluginsDir; StartMenuDir = $StartMenuDir; IgnoreRunningAutoCAD = [bool]$IgnoreRunningAutoCAD }
    if ($known -contains 'UpdaterDir') { $installArgs.UpdaterDir = $UpdaterDir }
    if ($known -contains 'WaitForPrograms') { $installArgs.WaitForPrograms = $true }
    $global:LASTEXITCODE = 0
    & $script @installArgs
    if ($LASTEXITCODE -ne 0) { exit 1 }
}

$work = Join-Path $env:TEMP "autocad-plugins-update-$PID"
try {
    New-Item $work -ItemType Directory -Force | Out-Null
    Write-Host (Msg 'update.checking')
    $plugins = @(Get-Plugins)
    if (-not $plugins) { Write-Host (Msg 'update.none-published'); return }

    if ($Keys -or (-not $Yes -and -not [Console]::IsInputRedirected)) {
        $targets = $null
        while (-not $targets) {
            $choice = Select-Plugin
            if (-not $choice) { Write-Host (Msg 'update.cancelled'); return }
            if ($choice -eq 'all') {
                $targets = @(Get-Outdated)
                if (-not $targets) { Write-Host (Msg 'update.up-to-date'); return }
            }
            else {
                $pick = Select-Release $choice
                if ($pick) { $targets = @([pscustomobject]@{ Plugin = $choice; Release = $pick }) }
            }
        }
    }
    else {
        Write-Host ''
        foreach ($p in $plugins | Where-Object { $_.Installed }) {
            Write-Host (Msg 'update.installed' @{ name = $p.Name; version = $p.Installed })
            Write-Host (Msg 'update.latest' @{ name = $p.Name; version = $p.Releases[0].Version })
        }
        $targets = @(Get-Outdated)
        if (-not $targets) { Write-Host ''; Write-Host (Msg 'update.up-to-date'); return }
        Write-Host ''
        Write-Host (Msg 'update.changes')
        foreach ($t in $targets) {
            foreach ($r in $t.Plugin.Releases | Where-Object { $_.Version -gt $t.Plugin.Installed }) {
                Write-Host ''
                Write-Host ('  ' + (Get-Title $t.Plugin $r))
                foreach ($line in Get-NoteLines $r.Release.body) { Write-Host $line }
            }
        }
        Write-Host ''
        if (-not (Confirm-Update (Msg 'update.ask' @{ list = (Get-OutdatedList $targets) }))) { Write-Host (Msg 'update.cancelled'); return }
    }

    $unpacked = @(foreach ($t in $targets) { Get-Release $t.Plugin $t.Release })
    if (-not $IgnoreRunningAutoCAD -and (Get-Process acad, accoreconsole -ErrorAction SilentlyContinue)) {
        Write-Host (Msg 'update.close-acad')
        while (Get-Process acad, accoreconsole -ErrorAction SilentlyContinue) { Start-Sleep 2 }
        # AutoCAD writes its settings to the registry as it closes; let it finish first.
        Start-Sleep 3
    }
    foreach ($u in $unpacked) {
        Write-Host ''
        Invoke-Install $u
    }
}
catch {
    Write-Host (Msg 'update.failed' @{ msg = $_.Exception.Message })
    exit 1
}
finally {
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}
