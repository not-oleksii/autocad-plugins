# Builds a plugin's ribbon tab as a partial menu (.cuix), with AutoCAD's own customization library
# (AcCui.dll), so the file is written exactly as AutoCAD's CUI editor would write it. Every plugin's
# src\ribbon.ps1 dot-sources this file and says which panels and buttons its tab has:
#
#   . (Join-Path $PSScriptRoot '..\..\common\ribbon.ps1')
#   Initialize-Ribbon $Acad
#   New-RibbonIcon $Out 'PDFALL' 'PDF' ([Drawing.Color]::FromArgb(200, 40, 40))
#   $ribbon = New-Ribbon 'PDFALL' 'PD'
#   Add-RibbonPanel $ribbon 'Друк' 'PDFALL' @(@{ Name = 'PDFALL'; Text = 'Друк у PDF'; Help = '...' })
#   Save-Ribbon $ribbon (Join-Path $Out 'PDFALL.cuix')
#
# A button's Name is its command, and its icons are <Name>_16.png and <Name>_32.png next to the
# .cuix, which AutoCAD finds through the support path that PackageContents.xml points at Contents.

function Initialize-Ribbon($Acad) {
    # LoadFrom also finds AcCui's own dependencies in AutoCAD's folder.
    [Reflection.Assembly]::LoadFrom((Join-Path $Acad 'AcCui.dll')) | Out-Null
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName WindowsBase
}

# A command's two icons: a page with a coloured band and a short label, 16 and 32 pixels.
function New-RibbonIcon($Out, $command, $label, $color) {
    New-Item $Out -ItemType Directory -Force | Out-Null
    foreach ($size in 16, 32) {
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
        $bmp.Save((Join-Path $Out "$($command)_$size.png"), [Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
    }
}

# An empty tab named $name (also its menu group), with a key tip.
function New-Ribbon($name, $keyTip) {
    $C = 'Autodesk.AutoCAD.Customization'
    $cs = New-Object "$C.CustomizationSection"
    $cs.MenuGroupName = $name
    $mg = $cs.MenuGroup
    $macros = New-Object "$C.MacroGroup" "$($name)Macros", $mg
    if (-not $mg.MacroGroups.Contains($macros)) { $mg.MacroGroups.Add($macros) | Out-Null }
    $tab = New-Object "$C.RibbonTabSource" $mg.RibbonRoot
    $tab.Text = $name
    $tab.Name = $name
    $tab.ElementID = "RBN_$($name)_TAB"
    $tab.KeyTip = $keyTip
    @{ Section = $cs; Group = $mg; Macros = $macros; Tab = $tab }
}

# One panel of large buttons on the tab. Fixed IDs, so a rebuilt file is the same tab to AutoCAD
# and not a new one. A button's Name is its command, Text what it says.
function Add-RibbonPanel($ribbon, $text, $idPrefix, $buttons) {
    $C = 'Autodesk.AutoCAD.Customization'
    $mg = $ribbon.Group
    $panel = New-Object "$C.RibbonPanelSource" $mg.RibbonRoot
    $panel.Text = $text
    $panel.Name = $idPrefix
    $panel.ElementID = "RBN_$($idPrefix)_PANEL"
    $row = New-Object "$C.RibbonRow" $panel
    $row.ElementID = "RBN_$($idPrefix)_ROW"
    $panel.Items.Add($row)
    foreach ($b in $buttons) {
        $macro = $ribbon.Macros.CreateMenuMacro($b.Name, "^C^C$($b.Name) ", "ID_$($b.Name)")
        $macro.macro.HelpString = $b.Help
        $macro.macro.CLICommand = $b.Name
        $button = New-Object "$C.RibbonCommandButton" $row
        $button.Text = if ($b.Text) { $b.Text } else { $b.Name }
        $button.ElementID = "RBN_$($b.Name)_BUTTON"
        $button.ButtonStyle = 'LargeWithText'
        $button.MacroID = $macro.ElementID
        $button.TooltipTitle = $button.Text
        $row.Items.Add($button)
    }
    $mg.RibbonRoot.RibbonPanelSources.Add($panel)
    $ref = New-Object "$C.RibbonPanelSourceReference" $ribbon.Tab
    $ref.ElementID = "RBN_$($idPrefix)_PANEL_REF"
    $ref.PanelId = $panel.ElementID
    $ribbon.Tab.Items.Add($ref)
}

function Save-Ribbon($ribbon, $path) {
    $ribbon.Group.RibbonRoot.RibbonTabSources.Add($ribbon.Tab)
    if (Test-Path $path) { Remove-Item $path }
    if (-not $ribbon.Section.SaveAs($path)) { throw "AcCui could not save $path" }

    # AcCui can't set button images outside AutoCAD, so they go straight into the saved MenuGroup.cui.
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
}
