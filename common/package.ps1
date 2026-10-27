# The last step of every plugin's build.bat: puts what all plugins share next to the plugin's
# <NAME>.bundle in dist\ and zips it all into dist\<NAME>.zip for colleagues:
#   install.bat, install.ps1, uninstall.bat, messages.json   the installer and every text it says
#   updater\                                                 the shared updater, with version.txt
#   Instruktsiia.html                                        the plugin's guide, if it has one
# The bundle gets plugin.json, which marks it as one of these plugins for the installer, and the guide.
# version.txt is the time of the last commit that changed common\, so the installer can tell an
# older updater from a newer one without anyone keeping a number up to date.
#   powershell -File common\package.ps1 -Plugin pdfall -Built %TEMP%\pdfall-build\lisp -Dist pdfall\dist
param(
    [Parameter(Mandatory = $true)][string]$Plugin,
    [Parameter(Mandatory = $true)][string]$Built,
    [Parameter(Mandatory = $true)][string]$Dist
)
$ErrorActionPreference = 'Stop'
$src = Join-Path (Resolve-Path $Plugin).Path 'src'
$name = (Get-Content (Join-Path $src 'plugin.json') -Raw -Encoding UTF8 | ConvertFrom-Json).name
$bundle = Join-Path $Dist "$name.bundle"
if (-not (Test-Path (Join-Path $bundle 'PackageContents.xml'))) { throw "build $bundle first" }

Copy-Item (Join-Path $src 'plugin.json') $bundle
foreach ($f in 'install.bat', 'install.ps1', 'uninstall.bat') { Copy-Item (Join-Path $PSScriptRoot $f) $Dist }
Copy-Item (Join-Path $Built 'messages.json') $Dist
$guide = Join-Path $src 'Instruktsiia.html'
if (Test-Path $guide) { Copy-Item $guide $Dist; Copy-Item $guide $bundle }

$updater = Join-Path $Dist 'updater'
New-Item $updater -ItemType Directory -Force | Out-Null
foreach ($f in 'update.bat', 'update.ps1') { Copy-Item (Join-Path $PSScriptRoot "updater\$f") $updater }
Copy-Item (Join-Path $PSScriptRoot 'messages.json') $updater
$global:LASTEXITCODE = 0
$stamp = & git.exe -C $PSScriptRoot log -1 --format=%ct -- . 2>$null
if ($LASTEXITCODE -ne 0 -or -not $stamp) { $stamp = '0' }
[IO.File]::WriteAllText((Join-Path $updater 'version.txt'), "$stamp`n")

$zip = Join-Path $Dist "$name.zip"
if (Test-Path $zip) { Remove-Item $zip }
$entries = @(Get-ChildItem $Dist | ForEach-Object { $_.Name })
& tar.exe -a -c -f $zip -C $Dist @entries
if ($LASTEXITCODE -ne 0) { throw "tar could not make $zip" }
Write-Host "Built $zip"
