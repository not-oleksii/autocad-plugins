# Builds PDFALL.cuix, the partial menu that adds a "PDFALL" ribbon tab with PDFALL, PDFNUM,
# PDFLIST, PDFSPEC and PDFSETTINGS buttons, and the buttons' icons, with common\ribbon.ps1.
# build.bat runs it: powershell -File src\ribbon.ps1 -Out dist\PDFALL.bundle\Contents
param(
    [Parameter(Mandatory = $true)][string]$Out,
    [string]$Acad = 'C:\Program Files\Autodesk\AutoCAD 2024'
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\..\common\ribbon.ps1')
# The button texts are in messages.json.
$messages = (Get-Content (Join-Path $PSScriptRoot 'messages.json') -Raw -Encoding UTF8 | ConvertFrom-Json).messages
function Msg($key) { $messages.$key }
Initialize-Ribbon $Acad

# PDF for PDFALL, 1 2 for PDFNUM, Л and СП for PDFLIST and PDFSPEC, ... for PDFSETTINGS.
New-RibbonIcon $Out 'PDFALL' 'PDF' ([Drawing.Color]::FromArgb(200, 40, 40))
New-RibbonIcon $Out 'PDFNUM' '1 2' ([Drawing.Color]::FromArgb(40, 90, 180))
New-RibbonIcon $Out 'PDFLIST' 'Л' ([Drawing.Color]::FromArgb(40, 140, 70))
New-RibbonIcon $Out 'PDFSPEC' 'СП' ([Drawing.Color]::FromArgb(210, 120, 30))
New-RibbonIcon $Out 'PDFSETTINGS' '...' ([Drawing.Color]::FromArgb(110, 110, 110))

$ribbon = New-Ribbon 'PDFALL' 'PD'
Add-RibbonPanel $ribbon (Msg 'ribbon.print-panel') 'PDFALL' @(
    @{ Name = 'PDFALL'; Text = (Msg 'ribbon.pdfall'); Help = (Msg 'ribbon.pdfall-help') },
    @{ Name = 'PDFNUM'; Text = (Msg 'ribbon.pdfnum'); Help = (Msg 'ribbon.pdfnum-help') }
)
Add-RibbonPanel $ribbon (Msg 'ribbon.frame-panel') 'PDFFRAME' @(
    @{ Name = 'PDFLIST'; Text = (Msg 'ribbon.list'); Help = (Msg 'ribbon.list-help') },
    @{ Name = 'PDFSPEC'; Text = (Msg 'ribbon.spec'); Help = (Msg 'ribbon.spec-help') },
    @{ Name = 'PDFSETTINGS'; Text = (Msg 'ribbon.settings'); Help = (Msg 'ribbon.settings-help') }
)
Save-Ribbon $ribbon (Join-Path $Out 'PDFALL.cuix')
