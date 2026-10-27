# Tests dist\install.ps1 and the shared updater (updater\update.ps1) against a fake AutoCAD registry
# tree, a temporary plug-ins folder, updater folder and Start menu, and a fake list of GitHub
# releases on disk, so the real AutoCAD settings are not touched and nothing is downloaded (AutoCAD
# may stay open).
# Usage: powershell -ExecutionPolicy Bypass -File tests\install.ps1   (run build.bat first)
$ErrorActionPreference = 'Stop'
$dist = Join-Path $PSScriptRoot '..\dist'
$installer = Join-Path $dist 'install.ps1'
$root = 'HKCU:\Software\PdfallTest'
$acad = "$root\AutoCAD"
$plugins = Join-Path $env:TEMP 'pdfall-test-plugins'
$startMenu = Join-Path $env:TEMP 'pdfall-test-startmenu'
$updater = Join-Path $env:TEMP 'pdfall-test-updater'
$releases = Join-Path $env:TEMP 'pdfall-test-releases'
$contents = Join-Path $plugins 'PDFALL.bundle\Contents'
$manifest = Join-Path $plugins 'PDFALL.bundle\PackageContents.xml'
$messages = (Get-Content (Join-Path $dist 'messages.json') -Raw -Encoding UTF8 | ConvertFrom-Json).messages
$shortcut = Join-Path $startMenu "$($messages.'install.shortcut').lnk"
$guideShortcut = Join-Path $startMenu "$($messages.'install.shortcut-guide'.Replace('{name}', 'PDFALL')).lnk"
$oldShortcut = Join-Path $startMenu "$($messages.'install.old-shortcut'.Replace('{name}', 'PDFALL')).lnk"
$common = @{ AcadKey = $acad; PluginsDir = $plugins; StartMenuDir = $startMenu; UpdaterDir = $updater; IgnoreRunningAutoCAD = $true }
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
function Link($path) { if (Test-Path -LiteralPath $path) { (New-Object -ComObject WScript.Shell).CreateShortcut($path) } }

# A fake GitHub release list: the built zip published as $version and again as 1.7.5 (to go back
# to), one older than 1.7.0 without files, another plugin that isn't installed, and releases the
# updater must skip (a pre-release, a draft, a tag of no plugin). $hash replaces the zip's real
# checksum of $version.
function Publish($version, $hash) {
    if (Test-Path $releases) { Remove-Item $releases -Recurse -Force }
    New-Item $releases -ItemType Directory | Out-Null
    $name = "PDFALL-$version.zip"
    $zip = Join-Path $releases $name
    Copy-Item (Join-Path $dist 'PDFALL.zip') $zip
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
        @{ tag_name = 'zzother-v9.0.0'; body = '- NOTES-OTHER' },
        @{ tag_name = 'v2.0.0'; body = '- NOTES-NOPLUGIN' },
        @{ tag_name = 'pdfall-v9.1.0-rc.1'; prerelease = $true; body = '- NOTES-RC' },
        @{ tag_name = 'pdfall-v9.2.0'; draft = $true; body = '- NOTES-DRAFT' },
        @{ tag_name = "pdfall-v$version"; published_at = '2026-10-19T10:00:00Z'; assets = $assets
           body = "### Додано`r`n`r`n- NOTES-NEW **жирне**`r`n`r`n---`r`n`r`nNOTES-FOOTER" },
        @{ tag_name = 'pdfall-v1.7.5'; published_at = '2026-10-18T10:00:00Z'; assets = $oldAssets; body = '- NOTES-BETWEEN' },
        @{ tag_name = 'pdfall-v1.6.0'; published_at = '2026-10-17T10:00:00Z'; body = '- NOTES-OLD' })
    [IO.File]::WriteAllText((Join-Path $releases 'releases.json'), (ConvertTo-Json $list -Depth 5), (New-Object Text.UTF8Encoding($false)))
}

function Get-UpdateArgs {
    @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$updater\update.ps1`"",
      '-AcadKey', "`"$acad`"", '-PluginsDir', "`"$plugins`"", '-StartMenuDir', "`"$startMenu`"",
      '-ReleasesUrl', (Uri (Join-Path $releases 'releases.json')), '-IgnoreRunningAutoCAD')
}

# Runs the installed updater in its own process, started in its own folder, which an install
# overwrites (update.bat moves to %TEMP% first; this checks update.ps1 copes without that).
# $keys, such as 'Enter,DownArrow,Enter', are pressed in its lists; without them it answers yes.
function Invoke-Update($keys) {
    $out = Join-Path $env:TEMP 'pdfall-test-update.txt'
    $argList = Get-UpdateArgs
    $argList += if ($keys) { @('-Keys', $keys) } else { @('-Yes') }
    $p = Start-Process powershell -ArgumentList $argList -WorkingDirectory $updater -RedirectStandardOutput $out -PassThru -NoNewWindow -Wait
    $text = Get-Content $out -Raw -Encoding UTF8
    Remove-Item $out
    @{ Code = $p.ExitCode; Text = "$text" }
}

# The installed merge.exe with nothing to merge, left waiting for Enter as its window is after PDFALL.
function Start-OpenMerge {
    $empty = Join-Path $env:TEMP 'pdfall-test-empty'
    New-Item $empty -ItemType Directory -Force | Out-Null
    $psi = New-Object Diagnostics.ProcessStartInfo (Join-Path $contents 'merge.exe'), "`"$empty`""
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.CreateNoWindow = $true
    $m = [Diagnostics.Process]::Start($psi)
    Start-Sleep 3
    $m
}
function Stop-OpenMerge($m) {
    $m.StandardInput.WriteLine()
    $m.StandardInput.Close()
    if (-not $m.WaitForExit(30000)) { $m.Kill() }
}

$cleanup = $root, $plugins, $startMenu, $updater, $releases
foreach ($p in $cleanup) { if (Test-Path $p) { Remove-Item $p -Recurse -Force } }
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
# The «Оновити PDFALL» entry that PDFALL 1.8.0 to 1.11.0 made.
New-Item $startMenu -ItemType Directory -Force | Out-Null
$old = (New-Object -ComObject WScript.Shell).CreateShortcut($oldShortcut)
$old.TargetPath = Join-Path $plugins 'PDFALL.bundle\update.bat'
$old.Save()

try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zipFile = [IO.Compression.ZipFile]::OpenRead((Join-Path $dist 'PDFALL.zip'))
    $names = @($zipFile.Entries | ForEach-Object { $_.FullName })
    $zipFile.Dispose()
    Check ($names -contains 'Instruktsiia.html' -and $names -contains 'install.bat' -and $names -contains 'PDFALL.bundle/Instruktsiia.html') `
        'the zip has the guide next to install.bat and in the bundle'
    Check (@('updater/update.bat', 'updater/update.ps1', 'updater/messages.json', 'updater/version.txt', 'PDFALL.bundle/plugin.json' |
        Where-Object { $names -notcontains $_ }).Count -eq 0) 'the zip has the shared updater, and the bundle says it is one of the plugins'

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
    Check (@('update.bat', 'update.ps1', 'messages.json', 'version.txt' | Where-Object { -not (Test-Path (Join-Path $updater $_)) }).Count -eq 0 -and
           -not (Test-Path (Join-Path $plugins 'PDFALL.bundle\update.bat'))) 'the shared updater is in its own folder, not in the bundle'
    $link = Link $shortcut
    Check ($link -and $link.TargetPath -eq (Join-Path $updater 'update.bat') -and $link.WorkingDirectory -eq $env:TEMP) `
        'the Start menu entry «Оновити плагіни AutoCAD» runs the shared update.bat from %TEMP%'
    Check (-not (Test-Path -LiteralPath $oldShortcut)) 'the old «Оновити PDFALL» entry is gone'
    $link = Link $guideShortcut
    Check ($link -and $link.TargetPath -eq (Join-Path $plugins 'PDFALL.bundle\Instruktsiia.html')) 'the Start menu has the guide'
    $built = Installed

    $stamp = (Get-Content (Join-Path $updater 'version.txt') -Raw).Trim()
    [IO.File]::WriteAllText((Join-Path $updater 'version.txt'), "99999999999`n")
    Set-Content (Join-Path $updater 'newer.txt') 'x'
    & $installer @common | Out-Null
    Check ((Test-Path (Join-Path $updater 'newer.txt')) -and (Get-Content (Join-Path $updater 'version.txt') -Raw).Trim() -eq '99999999999') `
        'an older updater in a zip does not replace a newer one'
    [IO.File]::WriteAllText((Join-Path $updater 'version.txt'), "0`n")
    & $installer @common | Out-Null
    Check ((Get-Content (Join-Path $updater 'version.txt') -Raw).Trim() -eq $stamp) "a newer one does ($stamp)"
    Remove-Item (Join-Path $updater 'newer.txt')

    Write-Host 'Update...'
    Set-Installed '1.7.0'
    Publish $built
    $u = Invoke-Update
    Check ($u.Code -eq 0 -and (Installed) -eq $built) "the updater installs $built over 1.7.0 (exit $($u.Code), now $(Installed))"
    Check ($u.Text -match '1\.7\.0' -and $u.Text -match [regex]::Escape($built)) 'it shows the installed and the new version'
    Check ($u.Text -match 'NOTES-NEW' -and $u.Text -match 'NOTES-BETWEEN' -and $u.Text.IndexOf('NOTES-NEW') -lt $u.Text.IndexOf('NOTES-BETWEEN')) `
        'it shows the changes of every newer version, newest first'
    Check ($u.Text -notmatch 'NOTES-(OLD|OTHER|NOPLUGIN|RC|DRAFT|FOOTER)' -and $u.Text -notmatch '###|\*\*') `
        'it skips older versions, pre-releases, drafts, plugins not installed, the install help and Markdown marks'
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

    Write-Host 'Pick a plugin and a version...'
    $u = Invoke-Update 'Enter,DownArrow,Enter'
    Check ($u.Text -match "> PDFALL  —  встановлено $([regex]::Escape($built)), найновіша" -and $u.Text -match 'ZZOTHER  —  не встановлено, є 9\.0\.0' -and
           $u.Text -match 'усі встановлені плагіни найновіші' -and $u.Text -notmatch 'NOPLUGIN|V2') `
        'the list shows each plugin with a release, installed or not, and starts at the first one when nothing is to update'
    Check ($u.Code -eq 0 -and $u.Text -match "встановлено[\s\S]*> PDFALL 1\.7\.5" -and $u.Text -match 'NOTES-BETWEEN' -and
           $u.Text -match 'NOTES-NEW' -and $u.Text -match 'Enter — повернутися до 1\.7\.5' -and $u.Text -match 'Завантажую PDFALL-1\.7\.5\.zip') `
        'Enter opens the versions of PDFALL, where the arrow down picks the older one, shows its notes and installs it'
    if ($u.Code -ne 0) { Write-Host $u.Text }

    Set-Installed '1.7.0'
    $u = Invoke-Update 'Home,Enter,DownArrow,DownArrow,DownArrow,UpArrow,Escape'
    Check ($u.Code -eq 0 -and (Installed) -eq '1.7.0' -and $u.Text -match 'Скасовано' -and $u.Text -notmatch 'Завантажую' -and
           $u.Text -match '! PDFALL 1\.6\.0 вийшов до «Оновити плагіни AutoCAD»' -and $u.Text -match 'NOTES-OLD') `
        'the versions start at the newest, warn that one before the shared updater brings back its own, stop at the oldest; Esc goes back and Esc again changes nothing'

    $u = Invoke-Update 'Home,Enter,Enter'
    Check ($u.Code -eq 0 -and (Installed) -eq $built -and $u.Text -match "Завантажую PDFALL-$([regex]::Escape($built))\.zip" -and
           $u.Text -match 'NOTES-NEW' -and $u.Text -notmatch 'NOTES-BETWEEN') "Enter on the newest version shows only its notes and installs it ($built) over 1.7.0"

    Set-Installed '1.7.0'
    $u = Invoke-Update 'Enter'
    Check ($u.Code -eq 0 -and (Installed) -eq $built -and $u.Text -match "> Оновити все: PDFALL 1\.7\.0 → $([regex]::Escape($built))" -and
           $u.Text -notmatch 'Завантажую ZZOTHER') "the list starts at «Оновити все» when there is an update, and Enter installs it ($built), leaving out the plugin that isn't installed"

    Write-Host 'An open merge.exe window...'
    $merge = Start-OpenMerge
    try {
        $o = & $installer @common *>&1 | Out-String
        Check ($LASTEXITCODE -eq 1 -and $o -match 'Відкрите вікно збирання PDF' -and (Test-Path (Join-Path $contents 'merge.exe'))) `
            'install stops while a merge.exe window of the bundle is open, and says to close it'
        Set-Installed '1.7.0'
        $out = Join-Path $env:TEMP 'pdfall-test-update-merge.txt'
        $up = Start-Process powershell -ArgumentList ((Get-UpdateArgs) + '-Yes') -WorkingDirectory $env:TEMP -RedirectStandardOutput $out -PassThru -NoNewWindow
        $null = $up.Handle   # without it, ExitCode stays empty
        $deadline = (Get-Date).AddSeconds(60)
        $text = ''
        while ((Get-Date) -lt $deadline -and $text -notmatch 'Закрийте вікно збирання PDF') {
            Start-Sleep 1
            $text = try {
                $fs = [IO.File]::Open($out, 'Open', 'Read', 'ReadWrite')
                try { (New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8)).ReadToEnd() } finally { $fs.Close() }
            } catch { '' }
        }
        Check (-not $up.HasExited -and $text -match 'Закрийте вікно збирання PDF') 'the update waits for the merge.exe window to close'
    }
    finally { Stop-OpenMerge $merge }
    if (-not $up.WaitForExit(120000)) { $up.Kill() }
    Check ($up.ExitCode -eq 0 -and (Installed) -eq $built) "and installs once it is closed (exit $($up.ExitCode), now $(Installed))"
    Remove-Item $out -ErrorAction SilentlyContinue

    Write-Host 'Uninstall...'
    $other = Join-Path $plugins 'OTHER.bundle'
    New-Item $other -ItemType Directory | Out-Null
    Set-Content (Join-Path $other 'plugin.json') '{"name": "OTHER"}'
    & $installer -Uninstall @common
    Check (-not (Test-Path (Join-Path $plugins 'PDFALL.bundle'))) 'the bundle was removed'
    Check (-not (Test-Path -LiteralPath $guideShortcut)) 'the guide entry was removed'
    Check ((Test-Path (Join-Path $updater 'update.ps1')) -and (Test-Path -LiteralPath $shortcut)) 'the shared updater stays while another plugin uses it'
    Check ((Trusted $p24) -eq 'D:\old') 'the trust entry was removed, old paths kept'
    Remove-Item $other -Recurse -Force
    & $installer @common | Out-Null
    & $installer -Uninstall @common
    Check (-not (Test-Path $updater) -and -not (Test-Path -LiteralPath $shortcut)) 'with the last plugin gone, the updater and its entry go too'
}
finally {
    foreach ($p in $cleanup) { if (Test-Path $p) { Remove-Item $p -Recurse -Force } }
}
if ($failures) { Write-Host "FAILED: $($failures -join '; ')"; exit 1 } else { Write-Host 'All passed.' }
