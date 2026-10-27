# Prepares and publishes a plugin's releases on GitHub (see "Releasing" in the plugin's
# DEVELOPING.md). Each plugin's release.ps1 runs it with -Plugin set to the plugin's folder, whose
# src\plugin.json names it (PDFALL, tag pdfall-v<version>).
#
#   release.ps1 -Prepare 1.8.0
#       Sets the version in src\lsp\00-settings.lsp and src\PackageContents.xml and turns the
#       "Невипущене" section of CHANGELOG.md into "1.8.0 - <today>". Commit that in a pull request.
#   release.ps1 [-DryRun]
#       On main, clean and equal to origin/main, after that pull request is merged: checks the
#       changelog, runs build.bat and both tests, then tags <name>-v<version>, pushes the tag and
#       publishes the GitHub release with <NAME>-<version>.zip, its .sha256 and the changelog
#       section as notes. -DryRun stops before the tag; the files are left in dist\release.
#
# The release is published with the GitHub CLI (gh) when it is installed and signed in;
# otherwise this prints a link to a pre-filled release page and the files to attach there.
param(
    [Parameter(Mandatory = $true)][string]$Plugin,
    [string]$Prepare,
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$repo = 'not-oleksii/autocad-plugins'   # the updater reads its releases from the same repository
$root = (Resolve-Path $Plugin).Path
$pluginName = (Get-Content (Join-Path $root 'src\plugin.json') -Raw -Encoding UTF8 | ConvertFrom-Json).name
$lower = $pluginName.ToLower()
$settings = Join-Path $root 'src\lsp\00-settings.lsp'
$manifest = Join-Path $root 'src\PackageContents.xml'
$changelog = Join-Path $root 'CHANGELOG.md'
$unreleased = '## Невипущене'
$utf8 = New-Object Text.UTF8Encoding($false)

$messages = (Get-Content (Join-Path $root 'src\messages.json') -Raw -Encoding UTF8 | ConvertFrom-Json).messages
function Msg($key, $values = @{}) {
    $text = $messages.$key
    foreach ($name in $values.Keys) { $text = $text.Replace("{$name}", [string]$values[$name]) }
    $text
}

function Read-Text($path) { [IO.File]::ReadAllText($path, $utf8) }
function Write-Text($path, $text) {
    # keep a BOM where the file had one
    $bom = [IO.File]::ReadAllBytes($path)[0] -eq 0xEF
    [IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding($bom)))
}
function Get-Version {
    if ((Read-Text $settings) -notmatch "\(setq \*$lower-version\* `"([^`"]+)`"\)") { throw "no *$lower-version* in $settings" }
    $Matches[1]
}
# The lines of a "## " section of CHANGELOG.md, without its heading.
function Get-Section($heading) {
    $lines = (Read-Text $changelog) -split "\r?\n"
    $start = [array]::IndexOf($lines, $heading)
    if ($start -lt 0) { return $null }
    $rest = @($lines | Select-Object -Skip ($start + 1))
    $end = 0
    while ($end -lt $rest.Count -and $rest[$end] -notmatch '^## ') { $end++ }
    ((@($rest | Select-Object -First $end)) -join "`n").Trim()
}
function Invoke-Step($what, [scriptblock]$run) {
    Write-Host "== $what"
    $global:LASTEXITCODE = 0
    & $run
    if ($LASTEXITCODE -ne 0) { throw "$what failed" }
}
# Named apart from git: PowerShell names ignore case, so a function Git would call itself.
function Invoke-Git { $out = & git.exe @args; if ($LASTEXITCODE -ne 0) { throw "git $args failed" }; $out }

if ($Prepare) {
    if ($Prepare -notmatch '^\d+\.\d+\.\d+$') { throw "the version must be <major>.<minor>.<patch>, e.g. 1.8.0" }
    $current = Get-Version
    if ([version]$Prepare -le [version]$current) { throw "$Prepare is not newer than the current $current" }
    $notes = Get-Section $unreleased
    if ($notes -notmatch '(?m)^- ') { throw "the '$unreleased' section of CHANGELOG.md lists no changes" }
    Write-Text $settings ((Read-Text $settings).Replace("(setq *$lower-version* `"$current`")", "(setq *$lower-version* `"$Prepare`")"))
    Write-Text $manifest ((Read-Text $manifest).Replace("AppVersion=`"$current`"", "AppVersion=`"$Prepare`""))
    $today = Get-Date -Format 'yyyy-MM-dd'
    $text = Read-Text $changelog
    $at = $text.IndexOf("$unreleased`n")
    if ($at -lt 0) { $at = $text.IndexOf("$unreleased`r`n") }
    $text = $text.Substring(0, $at) + "$unreleased`n`n## $Prepare - $today" + $text.Substring($at + $unreleased.Length)
    Write-Text $changelog $text
    Write-Host "Version $current -> $Prepare in 00-settings.lsp, PackageContents.xml and CHANGELOG.md."
    Write-Host "Next: commit this on a branch (e.g. release/$lower-$Prepare), merge its pull request,"
    Write-Host "then run release.ps1 on main."
    return
}

$version = Get-Version
$tag = "$lower-v$version"
$name = "$pluginName-$version.zip"
Write-Host "Releasing $pluginName $version as $tag$(if ($DryRun) { ' (dry run)' })"

# 1. Where it is released from: exactly what is on GitHub's main.
Push-Location $root
try {
    if ((Invoke-Git rev-parse --abbrev-ref HEAD) -ne 'main') { throw 'switch to main first' }
    if (Invoke-Git status --porcelain) { throw 'the working tree has uncommitted changes' }
    Invoke-Git fetch --quiet --tags origin | Out-Null
    if ((Invoke-Git rev-parse HEAD) -ne (Invoke-Git rev-parse origin/main)) { throw 'main is not equal to origin/main; pull or push first' }
    & git rev-parse -q --verify "refs/tags/$tag" | Out-Null
    if ($LASTEXITCODE -eq 0) { throw "tag $tag already exists; raise the version with -Prepare" }
}
finally { Pop-Location }

# 2. The changelog says what this version changes.
$heading = ((Read-Text $changelog) -split "\r?\n") | Where-Object { $_ -like "## $version - *" } | Select-Object -First 1
$notes = if ($heading) { Get-Section $heading }
if ($notes -notmatch '(?m)^- ') { throw "CHANGELOG.md has no '## $version - <date>' section with changes; run release.ps1 -Prepare $version" }
if ((Get-Section $unreleased) -match '(?m)^- ') { throw "CHANGELOG.md still lists changes under '$unreleased'; prepare a new version for them" }

# 3. Build and test what will be shipped.
Invoke-Step 'build.bat' { & cmd.exe /c (Join-Path $root 'build.bat') }
Invoke-Step 'tests\run.ps1' { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tests\run.ps1') }
Invoke-Step 'tests\install.ps1' { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tests\install.ps1') }

# 4. The release files: the versioned zip, its checksum in sha256sum's format, and the notes.
$out = Join-Path $root 'dist\release'
New-Item $out -ItemType Directory -Force | Out-Null
$zip = Join-Path $out $name
Copy-Item (Join-Path $root "dist\$pluginName.zip") $zip -Force
$hash = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
[IO.File]::WriteAllText("$zip.sha256", "$hash  $name`n", $utf8)
$notesFile = Join-Path $out 'notes.md'
[IO.File]::WriteAllText($notesFile, "$notes`n`n---`n`n$(Msg 'release.footer' @{ file = $name })`n", $utf8)
Write-Host "== Files in ${out}: $name, $name.sha256 (sha256 $hash), notes.md"
if ($DryRun) { Write-Host 'Dry run: nothing tagged or published.'; return }

# 5. Tag, push the tag, publish.
Push-Location $root
try {
    Invoke-Git tag -a $tag -m "$pluginName $version" | Out-Null
    Invoke-Git push --quiet origin "refs/tags/$tag" | Out-Null
}
finally { Pop-Location }
Write-Host "== Tagged and pushed $tag"

$gh = Get-Command gh -ErrorAction SilentlyContinue
if ($gh) {
    # Windows PowerShell turns a native program's stderr into an error when it is redirected.
    $ErrorActionPreference = 'Continue'
    & gh auth status --hostname github.com *> $null
    $signedIn = $LASTEXITCODE -eq 0
    $ErrorActionPreference = 'Stop'
    if (-not $signedIn) { $gh = $null; Write-Host 'gh is not signed in (run: gh auth login).' }
}
if ($gh) {
    Invoke-Step 'gh release create' {
        & gh release create $tag $zip "$zip.sha256" --repo $repo --verify-tag --latest --title "$pluginName $version" --notes-file $notesFile
    }
    Write-Host "Published https://github.com/$repo/releases/tag/$tag"
}
else {
    $body = [Uri]::EscapeDataString((Read-Text $notesFile))
    $title = [Uri]::EscapeDataString("$pluginName $version")
    Write-Host ''
    Write-Host 'Finish the release in the browser:'
    Write-Host "  1. Open https://github.com/$repo/releases/new?tag=$tag&title=$title&body=$body"
    Write-Host "  2. Attach $zip"
    Write-Host "     and $zip.sha256"
    Write-Host '  3. Keep "Set as the latest release" ticked and press "Publish release".'
}
