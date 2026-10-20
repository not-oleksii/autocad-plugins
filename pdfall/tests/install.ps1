# Tests dist\install.ps1 and the bundle's update.ps1 against a fake AutoCAD registry tree, a
# temporary plug-ins folder and Start menu, and a fake list of GitHub releases on disk, so the real
# AutoCAD settings are not touched and nothing is downloaded (AutoCAD may stay open).
# Usage: powershell -ExecutionPolicy Bypass -File tests\install.ps1   (run build.bat first)
$ErrorActionPreference = 'Stop'
$installer = Join-Path $PSScriptRoot '..\dist\install.ps1'
$root = 'HKCU:\Software\PdfallTest'
$acad = "$root\AutoCAD"
$plugins = Join-Path $env:TEMP 'pdfall-test-plugins'
$startMenu = Join-Path $env:TEMP 'pdfall-test-startmenu'
$releases = Join-Path $env:TEMP 'pdfall-test-releases'
$contents = Join-Path $plugins 'PDFALL.bundle\Contents'
$manifest = Join-Path $plugins 'PDFALL.bundle\PackageContents.xml'
$messages = (Get-Content (Join-Path $PSScriptRoot '..\src\messages.json') -Raw -Encoding UTF8 | ConvertFrom-Json).messages
$shortcut = Join-Path $startMenu "$($messages.'install.shortcut').lnk"
$guideShortcut = Join-Path $startMenu "$($messages.'install.shortcut-guide').lnk"
$common = @{ AcadKey = $acad; PluginsDir = $plugins; StartMenuDir = $startMenu; IgnoreRunningAutoCAD = $true }
$failures = @()
function Check($ok, $what) {
    if ($ok) { Write-Host "  ok    $what" } else { Write-Host "  FAIL  $what"; $script:failures += $what }
}
function Profile2024 { "$acad\R24.3\ACAD-7101:409\Profiles\<<Unnamed Profile>>" }
function Trusted($p) { (Get-ItemProperty -LiteralPath "$p\Variables").TRUSTEDPATHS }
function Installed { ([xml](Get-Content $manifest -Encoding UTF8)).ApplicationPackage.AppVersion }
function Set-Installed($v) {
    $x = [xml](Get-Content $manifest -Encoding UTF8)
    $x.ApplicationPackage.AppVersion = $v
    $x.Save($manifest)
}
function Uri($path) { ([Uri]$path).AbsoluteUri }

# A fake GitHub release list: the built zip published as $version and again as 1.7.5 (to go back
# to), one older than 1.7.0 without files, and releases update.ps1 must skip (a pre-release, a
# draft, another plugin's tag). $hash replaces the zip's real checksum of $version.
function Publish($version, $hash) {
    if (Test-Path $releases) { Remove-Item $releases -Recurse -Force }
    New-Item $releases -ItemType Directory | Out-Null
    $name = "PDFALL-$version.zip"
    $zip = Join-Path $releases $name
    Copy-Item (Join-Path $PSScriptRoot '..\dist\PDFALL.zip') $zip
    if (-not $hash) { $hash = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower() }
    [IO.File]::WriteAllText("$zip.sha256", "$hash  $name`n")
    $assets = @(
        @{ name = $name; browser_download_url = (Uri $zip) },
        @{ name = "$name.sha256"; browser_download_url = (Uri "$zip.sha256") })
    $oldZip = Join-Path $releases 'PDFALL-1.7.5.zip'
    Copy-Item $zip $oldZip
    [IO.File]::WriteAllText("$oldZip.sha256", "$((Get-FileHash $oldZip -Algorithm SHA256).Hash.ToLower())  PDFALL-1.7.5.zip`n")
    $oldAssets = @(
        @{ name = 'PDFALL-1.7.5.zip'; browser_download_url = (Uri $oldZip) },
        @{ name = 'PDFALL-1.7.5.zip.sha256'; browser_download_url = (Uri "$oldZip.sha256") })
    $list = @(
        @{ tag_name = 'other-v9.0.0'; body = '- NOTES-OTHER' },
        @{ tag_name = 'pdfall-v9.1.0-rc.1'; prerelease = $true; body = '- NOTES-RC' },
        @{ tag_name = 'pdfall-v9.2.0'; draft = $true; body = '- NOTES-DRAFT' },
        @{ tag_name = "pdfall-v$version"; published_at = '2026-10-19T10:00:00Z'; assets = $assets
           body = "### Додано`r`n`r`n- NOTES-NEW **жирне**`r`n`r`n---`r`n`r`nNOTES-FOOTER" },
        @{ tag_name = 'pdfall-v1.7.5'; published_at = '2026-10-18T10:00:00Z'; assets = $oldAssets; body = '- NOTES-BETWEEN' },
        @{ tag_name = 'pdfall-v1.6.0'; published_at = '2026-10-17T10:00:00Z'; body = '- NOTES-OLD' })
    [IO.File]::WriteAllText((Join-Path $releases 'releases.json'), (ConvertTo-Json $list -Depth 5), (New-Object Text.UTF8Encoding($false)))
}

# Runs the installed bundle's update.ps1 in its own process, started in the bundle folder that the
# update replaces (update.bat moves to %TEMP% first; this checks update.ps1 copes without that).
# $keys, such as 'DownArrow,Enter', are pressed in the version picker; without them it answers yes.
function Invoke-Update($keys) {
    $bundle = Join-Path $plugins 'PDFALL.bundle'
    $out = Join-Path $env:TEMP 'pdfall-test-update.txt'
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$bundle\update.ps1`"",
        '-AcadKey', "`"$acad`"", '-PluginsDir', "`"$plugins`"", '-StartMenuDir', "`"$startMenu`"",
        '-ReleasesUrl', (Uri (Join-Path $releases 'releases.json')), '-IgnoreRunningAutoCAD')
    $argList += if ($keys) { @('-Keys', $keys) } else { @('-Yes') }
    $p = Start-Process powershell -ArgumentList $argList -WorkingDirectory $bundle -RedirectStandardOutput $out -PassThru -NoNewWindow -Wait
    $text = Get-Content $out -Raw -Encoding UTF8
    Remove-Item $out
    @{ Code = $p.ExitCode; Text = "$text" }
}

foreach ($p in $root, $plugins, $startMenu, $releases) { if (Test-Path $p) { Remove-Item $p -Recurse -Force } }
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
Set-ItemProperty -LiteralPath $startup 2Startup 'C:\Old plugins\pdfall.lsp'
Set-ItemProperty -LiteralPath $startup 3Startup 'C:\b.lsp'

try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zipFile = [IO.Compression.ZipFile]::OpenRead((Join-Path $PSScriptRoot '..\dist\PDFALL.zip'))
    $names = @($zipFile.Entries | ForEach-Object { $_.FullName })
    $zipFile.Dispose()
    Check ($names -contains 'Instruktsiia.html' -and $names -contains 'install.bat' -and $names -contains 'PDFALL.bundle/Instruktsiia.html') `
        'the zip has the guide next to install.bat and in the bundle'

    Write-Host 'Install...'
    & $installer @common
    & $installer @common | Out-Null   # a second run must change nothing more
    Check (Test-Path (Join-Path $contents 'pdfall.lsp')) 'the bundle was copied'
    Check ((Trusted $p24) -eq "D:\old;$contents") "the bundle is trusted once, old paths kept ($(Trusted $p24))"
    Check ((Trusted $p24b) -eq $contents) 'a profile without Variables gets them'
    Check ((Trusted $p23) -eq ';') 'AutoCAD 2019 is left alone'
    $s = Get-ItemProperty -LiteralPath $startup
    Check ($s.NumStartup -eq '2' -and $s.'1Startup' -eq 'C:\a.lsp' -and $s.'2Startup' -eq 'C:\b.lsp' -and -not $s.'3Startup') `
        'the old pdfall.lsp is removed from the Startup Suite, the rest kept in order'
    Check (@('update.bat', 'update.ps1', 'messages.json', 'Instruktsiia.html' | Where-Object { -not (Test-Path (Join-Path $plugins "PDFALL.bundle\$_")) }).Count -eq 0) `
        'the updater and the guide are in the bundle'
    $link = if (Test-Path -LiteralPath $shortcut) { (New-Object -ComObject WScript.Shell).CreateShortcut($shortcut) }
    Check ($link -and $link.TargetPath -eq (Join-Path $plugins 'PDFALL.bundle\update.bat') -and $link.WorkingDirectory -eq $env:TEMP) `
        'the Start menu entry runs the bundle''s update.bat from %TEMP%'
    $link = if (Test-Path -LiteralPath $guideShortcut) { (New-Object -ComObject WScript.Shell).CreateShortcut($guideShortcut) }
    Check ($link -and $link.TargetPath -eq (Join-Path $plugins 'PDFALL.bundle\Instruktsiia.html')) 'the Start menu has the guide'
    $built = Installed

    Write-Host 'Update...'
    Set-Installed '1.7.0'
    Publish $built
    $u = Invoke-Update
    Check ($u.Code -eq 0 -and (Installed) -eq $built) "update.ps1 installs $built over 1.7.0 (exit $($u.Code), now $(Installed))"
    Check ($u.Text -match '1\.7\.0' -and $u.Text -match [regex]::Escape($built)) 'it shows the installed and the new version'
    Check ($u.Text -match 'NOTES-NEW' -and $u.Text -match 'NOTES-BETWEEN' -and $u.Text.IndexOf('NOTES-NEW') -lt $u.Text.IndexOf('NOTES-BETWEEN')) `
        'it shows the changes of every newer version, newest first'
    Check ($u.Text -notmatch 'NOTES-(OLD|OTHER|RC|DRAFT|FOOTER)' -and $u.Text -notmatch '###|\*\*') `
        'it skips older versions, pre-releases, drafts, other plugins, the install help and Markdown marks'
    Check ((Trusted $p24) -eq "D:\old;$contents" -and (Test-Path -LiteralPath $shortcut)) 'after the update the bundle is trusted once and the Start menu entry is there'
    if ($u.Code -ne 0) { Write-Host $u.Text }

    Set-Installed '1.7.0'
    Publish $built ('0' * 64)
    $u = Invoke-Update
    Check ($u.Code -eq 1 -and (Installed) -eq '1.7.0') 'a zip that does not match its .sha256 is not installed'

    Set-Installed $built
    Publish $built
    $u = Invoke-Update
    Check ($u.Code -eq 0 -and $u.Text -notmatch 'NOTES-') 'nothing is done when the newest version is installed'

    Write-Host 'Pick a version...'
    $u = Invoke-Update 'DownArrow,Enter'
    Check ($u.Code -eq 0 -and $u.Text -match "встановлено[\s\S]*> PDFALL 1\.7\.5" -and $u.Text -match 'NOTES-BETWEEN' -and
           $u.Text -match 'NOTES-NEW' -and $u.Text -match 'Enter — повернутися до 1\.7\.5' -and $u.Text -match 'Завантажую PDFALL-1\.7\.5\.zip') `
        'with the newest installed, the arrow down picks the older version, shows its notes and installs it'
    if ($u.Code -ne 0) { Write-Host $u.Text }

    Set-Installed '1.7.0'
    $u = Invoke-Update 'DownArrow,DownArrow,DownArrow,UpArrow,Escape'
    Check ($u.Code -eq 0 -and (Installed) -eq '1.7.0' -and $u.Text -match 'Скасовано' -and $u.Text -notmatch 'Завантажую' -and
           $u.Text -match 'У PDFALL 1\.6\.0 ще немає «Оновити PDFALL»' -and $u.Text -match 'NOTES-OLD') `
        'the picker starts at the newest version, shows the notes of 1.6.0 and warns it has no updater, stops at the oldest, and Esc changes nothing'

    $u = Invoke-Update 'Enter'
    Check ($u.Code -eq 0 -and (Installed) -eq $built -and $u.Text -match "Завантажую PDFALL-$([regex]::Escape($built))\.zip" -and
           $u.Text -match 'NOTES-NEW' -and $u.Text -notmatch 'NOTES-BETWEEN') "Enter in the picker shows only the newest version's notes and installs it ($built) over 1.7.0"

    Write-Host 'Uninstall...'
    & $installer -Uninstall @common
    Check (-not (Test-Path (Join-Path $plugins 'PDFALL.bundle'))) 'the bundle was removed'
    Check (-not (Test-Path -LiteralPath $shortcut) -and -not (Test-Path -LiteralPath $guideShortcut)) 'the Start menu entries were removed'
    Check ((Trusted $p24) -eq 'D:\old') 'the trust entry was removed, old paths kept'
}
finally {
    foreach ($p in $root, $plugins, $startMenu, $releases) { if (Test-Path $p) { Remove-Item $p -Recurse -Force } }
}
if ($failures) { Write-Host "FAILED: $($failures -join '; ')"; exit 1 } else { Write-Host 'All passed.' }
