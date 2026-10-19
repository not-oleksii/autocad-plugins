# Builds PDFALL.cuix, the partial menu that adds a "PDFALL" ribbon tab with PDFALL, PDFNUM,
# PDFLIST and PDFSPEC buttons, and the buttons' icons. It uses AutoCAD's own customization library (AcCui.dll), so
# the file is written exactly as AutoCAD's CUI editor would write it.
# build.bat runs it: powershell -File src\ribbon.ps1 -Out dist\PDFALL.bundle\Contents
param(
    [Parameter(Mandatory = $true)][string]$Out,
    [string]$Acad = 'C:\Program Files\Autodesk\AutoCAD 2024'
)
$ErrorActionPreference = 'Stop'
# The button texts are in messages.json.
$messages = (Get-Content (Join-Path $PSScriptRoot 'messages.json') -Raw -Encoding UTF8 | ConvertFrom-Json).messages
function Msg($key) { $messages.$key }
# LoadFrom also finds AcCui's own dependencies in AutoCAD's folder.
[Reflection.Assembly]::LoadFrom((Join-Path $Acad 'AcCui.dll')) | Out-Null
Add-Type -AssemblyName System.Drawing
New-Item $Out -ItemType Directory -Force | Out-Null

# A page with a coloured band and a short label: PDF for PDFALL, 1 2 for PDFNUM, A3 and A4 for
# PDFLIST and PDFSPEC.
function New-Icon($name, $size, $label, $color) {
    $bmp = New-Object Drawing.Bitmap $size, $size
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.TextRenderingHint = 'AntiAliasGridFit'
    $s = $size / 32.0
    $page = New-Object Drawing.Drawing2D.GraphicsPath
    $page.AddPolygon([Drawing.PointF[]]@(
        (New-Object Drawing.PointF (5 * $s), (2 * $s)), (New-Object Drawing.PointF (21 * $s), (2 * $s)),
        (New-Object Drawing.PointF (27 * $s), (8 * $s)), (New-Object Drawing.PointF (27 * $s), (30 * $s)),
        (New-Object Drawing.PointF (5 * $s), (30 * $s))))
    $g.FillPath([Drawing.Brushes]::White, $page)
    $g.DrawPath((New-Object Drawing.Pen ([Drawing.Color]::FromArgb(90, 90, 90)), ([Math]::Max(1, $s))), $page)
    $band = New-Object Drawing.RectangleF 0, (15 * $s), (32 * $s), (12 * $s)
    $g.FillRectangle((New-Object Drawing.SolidBrush $color), $band)
    if ($size -ge 32) {
        $font = New-Object Drawing.Font 'Arial', 9, ([Drawing.FontStyle]::Bold), ([Drawing.GraphicsUnit]::Pixel)
        $fmt = New-Object Drawing.StringFormat
        $fmt.Alignment = 'Center'; $fmt.LineAlignment = 'Center'
        $g.DrawString($label, $font, [Drawing.Brushes]::White, $band, $fmt)
    }
    $g.Dispose()
    $bmp.Save((Join-Path $Out $name), [Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}
New-Icon 'PDFALL_16.png' 16 'PDF' ([Drawing.Color]::FromArgb(200, 40, 40))
New-Icon 'PDFALL_32.png' 32 'PDF' ([Drawing.Color]::FromArgb(200, 40, 40))
New-Icon 'PDFNUM_16.png' 16 '1 2' ([Drawing.Color]::FromArgb(40, 90, 180))
New-Icon 'PDFNUM_32.png' 32 '1 2' ([Drawing.Color]::FromArgb(40, 90, 180))
New-Icon 'PDFLIST_16.png' 16 'A3' ([Drawing.Color]::FromArgb(40, 140, 70))
New-Icon 'PDFLIST_32.png' 32 'A3' ([Drawing.Color]::FromArgb(40, 140, 70))
New-Icon 'PDFSPEC_16.png' 16 'A4' ([Drawing.Color]::FromArgb(210, 120, 30))
New-Icon 'PDFSPEC_32.png' 32 'A4' ([Drawing.Color]::FromArgb(210, 120, 30))

$C = 'Autodesk.AutoCAD.Customization'
$cs = New-Object "$C.CustomizationSection"
$cs.MenuGroupName = 'PDFALL'
$mg = $cs.MenuGroup
$macros = New-Object "$C.MacroGroup" 'PDFALLMacros', $mg
if (-not $mg.MacroGroups.Contains($macros)) { $mg.MacroGroups.Add($macros) | Out-Null }

$tab = New-Object "$C.RibbonTabSource" $mg.RibbonRoot
$tab.Text = 'PDFALL'
$tab.Name = 'PDFALL'
$tab.ElementID = 'RBN_PDFALL_TAB'
$tab.KeyTip = 'PD'

# One panel of large buttons on the tab. Fixed IDs, so a rebuilt file is the same tab to AutoCAD
# and not a new one. A button's Name is its command, Text what it says.
function Add-Panel($text, $idPrefix, $buttons) {
    $panel = New-Object "$C.RibbonPanelSource" $mg.RibbonRoot
    $panel.Text = $text
    $panel.Name = $idPrefix
    $panel.ElementID = "RBN_$($idPrefix)_PANEL"
    $row = New-Object "$C.RibbonRow" $panel
    $row.ElementID = "RBN_$($idPrefix)_ROW"
    $panel.Items.Add($row)
    foreach ($b in $buttons) {
        $macro = $macros.CreateMenuMacro($b.Name, "^C^C$($b.Name) ", "ID_$($b.Name)")
        $macro.macro.HelpString = $b.Help
        $macro.macro.CLICommand = $b.Name
        $button = New-Object "$C.RibbonCommandButton" $row
        $button.Text = if ($b.Text) { $b.Text } else { $b.Name }
        $button.ElementID = "RBN_$($b.Name)_BUTTON"
        $button.ButtonStyle = 'LargeWithText'
        $button.MacroID = $macro.ElementID
        $button.TooltipTitle = $b.Name
        $row.Items.Add($button)
    }
    $mg.RibbonRoot.RibbonPanelSources.Add($panel)
    $ref = New-Object "$C.RibbonPanelSourceReference" $tab
    $ref.ElementID = "RBN_$($idPrefix)_PANEL_REF"
    $ref.PanelId = $panel.ElementID
    $tab.Items.Add($ref)
}

Add-Panel 'PDF' 'PDFALL' @(
    @{ Name = 'PDFALL'; Help = (Msg 'ribbon.pdfall') },
    @{ Name = 'PDFNUM'; Help = (Msg 'ribbon.pdfnum') }
)
Add-Panel (Msg 'ribbon.frame-panel') 'PDFFRAME' @(
    @{ Name = 'PDFLIST'; Text = (Msg 'ribbon.list'); Help = (Msg 'ribbon.list-help') },
    @{ Name = 'PDFSPEC'; Text = (Msg 'ribbon.spec'); Help = (Msg 'ribbon.spec-help') }
)
$mg.RibbonRoot.RibbonTabSources.Add($tab)

$path = Join-Path $Out 'PDFALL.cuix'
if (Test-Path $path) { Remove-Item $path }
if (-not $cs.SaveAs($path)) { throw "AcCui could not save $path" }

# AcCui can't set button images outside AutoCAD, so they go straight into the saved MenuGroup.cui.
# AutoCAD finds the PNGs through the support path, which PackageContents.xml points at Contents.
Add-Type -AssemblyName WindowsBase
$package = [IO.Packaging.Package]::Open($path, 'Open', 'ReadWrite')
try {
    $part = $package.GetPart([Uri]'/MenuGroup.cui')
    $reader = New-Object IO.StreamReader($part.GetStream())
    [xml]$xml = $reader.ReadToEnd()
    $reader.Close()
    foreach ($macro in $xml.SelectNodes('//MenuMacro/Macro')) {
        $name = $macro.SelectSingleNode('CLICommand').InnerText
        $macro.SelectSingleNode('SmallImage').SetAttribute('Name', "$($name)_16.png")
        $macro.SelectSingleNode('LargeImage').SetAttribute('Name', "$($name)_32.png")
    }
    $stream = $part.GetStream('Create', 'Write')
    $xml.Save($stream)
    $stream.Close()
}
finally { $package.Close() }
Write-Host "Built $path"
