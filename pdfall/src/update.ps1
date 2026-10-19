# Updates PDFALL from the repository's GitHub releases. Run it through update.bat (the
# "Оновити PDFALL" Start menu entry). It shows the installed and the newest version and what changed
# in every version in between, asks, downloads that release's PDFALL-<version>.zip, checks it
# against the release's .sha256, waits for AutoCAD to close and runs the zip's install.ps1.
# Only releases tagged pdfall-v<major>.<minor>.<patch> count; drafts and pre-releases are skipped
# (docs/adr/0007-update-from-github-releases.md).
# -AcadKey, -PluginsDir, -StartMenuDir, -IgnoreRunningAutoCAD, -ReleasesUrl and -Yes exist for tests\install.ps1.
param(
    [string]$AcadKey = 'HKCU:\Software\Autodesk\AutoCAD',
    [string]$PluginsDir = (Join-Path $env:APPDATA 'Autodesk\ApplicationPlugins'),
    [string]$StartMenuDir = (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'),
    [string]$ReleasesUrl = 'https://api.github.com/repos/not-oleksii/autocad-plugins/releases?per_page=100',
    [switch]$IgnoreRunningAutoCAD,
    [switch]$Yes
)
$ErrorActionPreference = 'Stop'
# The progress bar makes Invoke-WebRequest many times slower in Windows PowerShell.
$ProgressPreference = 'SilentlyContinue'
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
function Write-Notes($body) {
    $lines = @("$body" -split "\r?\n")
    $cut = [array]::IndexOf($lines, '---')
    if ($cut -ge 0) { $lines = @($lines | Select-Object -First $cut) }
    $lines = @($lines | ForEach-Object {
        $_ -replace '^#+\s*', '' -replace '\*\*|__|`', '' -replace '\[([^\]]+)\]\([^)]+\)', '$1'
    })
    while ($lines.Count -and -not $lines[0].Trim()) { $lines = @($lines | Select-Object -Skip 1) }
    if (-not ($lines -join '').Trim()) { $lines = @(Msg 'update.no-notes') }
    foreach ($line in $lines) { Write-Host ("    $line".TrimEnd()) }
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
        $date = if ($r.Release.published_at) { ([datetime]$r.Release.published_at).ToString('dd.MM.yyyy') } else { '' }
        Write-Host ('  ' + (Msg 'update.release' @{ version = $r.Version; date = $date }))
        Write-Notes $r.Release.body
    }
    Write-Host ''
    $question = if ($installed) { Msg 'update.ask' @{ from = $installed; to = $latest.Version } } else { Msg 'update.ask-install' @{ to = $latest.Version } }
    if (-not (Confirm-Update $question)) { Write-Host (Msg 'update.cancelled'); return }

    $name = "PDFALL-$($latest.Version).zip"
    $zipAsset = $latest.Release.assets | Where-Object { $_.name -eq $name } | Select-Object -First 1
    $sumAsset = $latest.Release.assets | Where-Object { $_.name -eq "$name.sha256" } | Select-Object -First 1
    foreach ($pair in @(@($zipAsset, $name), @($sumAsset, "$name.sha256"))) {
        if (-not $pair[0]) { throw (Msg 'update.no-asset' @{ version = $latest.Version; file = $pair[1] }) }
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
