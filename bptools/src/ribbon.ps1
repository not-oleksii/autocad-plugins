# Builds BPTOOLS.cuix, the partial menu that adds the «Креслення» ribbon tab, and the buttons'
# icons, with common\ribbon.ps1. «Вирівняти тексти» and «Вирівняти виноски» run AutoCAD's own
# TEXTALIGN and MLEADERALIGN.
# build.bat runs it: powershell -File src\ribbon.ps1 -Out dist\BPTOOLS.bundle\Contents
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

$blue = [Drawing.Color]::FromArgb(40, 90, 180)
$green = [Drawing.Color]::FromArgb(40, 140, 70)
$grey = [Drawing.Color]::FromArgb(110, 110, 110)
New-RibbonIcon $Out 'BPPOS' '1' $blue
New-RibbonIcon $Out 'BPPIN' '1 2 3' $blue
New-RibbonIcon $Out 'BPWIRE' 'Кол.' $blue
New-RibbonIcon $Out 'BPNAME' 'JST' $blue
New-RibbonIcon $Out 'BPVIEW' 'Вид' $blue
New-RibbonIcon $Out 'BPFIG' 'Рис.' $blue
New-RibbonIcon $Out 'BPSTYLE' 'Aa' $grey
New-RibbonIcon $Out 'BPPART' 'D-Sub' ([Drawing.Color]::FromArgb(210, 120, 30))
New-RibbonIcon $Out 'BPCENTER' '|A|' $green
New-RibbonIcon $Out 'TEXTALIGN' '≡' $green
New-RibbonIcon $Out 'MLEADERALIGN' '1 2' $green
New-RibbonIcon $Out 'BPNEW' 'DWT' $grey

$ribbon = New-Ribbon 'BPTOOLS' 'BP' (Msg 'ribbon.tab')
Add-RibbonPanel $ribbon (Msg 'ribbon.labels-panel') 'BPLABELS' @(
    @{ Name = 'BPPOS'; Text = (Msg 'ribbon.pos'); Help = (Msg 'ribbon.pos-help') },
    @{ Name = 'BPPIN'; Text = (Msg 'ribbon.pin'); Help = (Msg 'ribbon.pin-help') },
    @{ Name = 'BPWIRE'; Text = (Msg 'ribbon.wire'); Help = (Msg 'ribbon.wire-help') },
    @{ Name = 'BPNAME'; Text = (Msg 'ribbon.name'); Help = (Msg 'ribbon.name-help') },
    @{ Name = 'BPVIEW'; Text = (Msg 'ribbon.view'); Help = (Msg 'ribbon.view-help') },
    @{ Name = 'BPFIG'; Text = (Msg 'ribbon.figure'); Help = (Msg 'ribbon.figure-help') },
    @{ Name = 'BPSTYLE'; Text = (Msg 'ribbon.style'); Help = (Msg 'ribbon.style-help') }
)
Add-RibbonPanel $ribbon (Msg 'ribbon.parts-panel') 'BPPARTS' @(
    @{ Name = 'BPPART'; Text = (Msg 'ribbon.part'); Help = (Msg 'ribbon.part-help') }
)
Add-RibbonPanel $ribbon (Msg 'ribbon.align-panel') 'BPALIGN' @(
    @{ Name = 'BPCENTER'; Text = (Msg 'ribbon.center'); Help = (Msg 'ribbon.center-help') },
    @{ Name = 'TEXTALIGN'; Text = (Msg 'ribbon.textalign'); Help = (Msg 'ribbon.textalign-help') },
    @{ Name = 'MLEADERALIGN'; Text = (Msg 'ribbon.mleaderalign'); Help = (Msg 'ribbon.mleaderalign-help') }
)
Add-RibbonPanel $ribbon (Msg 'ribbon.file-panel') 'BPFILE' @(
    @{ Name = 'BPNEW'; Text = (Msg 'ribbon.new'); Help = (Msg 'ribbon.new-help') }
)
Save-Ribbon $ribbon (Join-Path $Out 'BPTOOLS.cuix')
