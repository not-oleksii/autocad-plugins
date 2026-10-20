# Makes the рамка templates that PDFLIST, PDFSPEC and PDFTEXT paste from the company's forms in
# examples\formats (kept out of git), one per form:
#   PDFALL_list_<standard>_<size><orientation>.dwg   a лист: skd, spdb or spdbv (СПДБ «Вироби»);
#                                                    A1..A5; p (portrait) or l (landscape)
#   PDFALL_spec1.dwg, PDFALL_spec2.dwg                the first and a later page of a специфікація
#   PDFALL_text_<standard>_1.dwg, ..._2.dwg           the same of a текстовий документ
# Each keeps the form as it is, without its placeholders, and gets МАРКА in its name cell, as wide and
# high as the cell and centred in it (make_templates.lsp). It also writes src\lsp\62-previews.lsp, the
# outline of every template for the settings dialog (docs/adr/0009).
# The result is committed, so this only has to run when the forms change. It needs AutoCAD 2024 and a
# built dist\PDFALL.bundle (build.bat), whose reader finds each form's рамка.
# Usage: powershell -ExecutionPolicy Bypass -File src\make_templates.ps1
param(
    [string]$Formats = (Join-Path $PSScriptRoot '..\examples\formats'),
    [string]$Out = (Join-Path $PSScriptRoot 'templates'),
    [string]$Acad = 'C:\Program Files\Autodesk\AutoCAD 2024\accoreconsole.exe',
    [int]$Seconds = 60
)
$ErrorActionPreference = 'Stop'
$lsp = Join-Path $PSScriptRoot '..\dist\PDFALL.bundle\Contents\pdfall.lsp'
if (-not (Test-Path $lsp)) { throw "run build.bat first: $lsp is missing" }
$lsp = (Resolve-Path $lsp).Path -replace '\\', '/'
$make = (Join-Path $PSScriptRoot 'make_templates.lsp') -replace '\\', '/'
New-Item $Out -ItemType Directory -Force | Out-Null
$Out = (Resolve-Path $Out).Path
$work = Join-Path $env:TEMP 'pdfall-templates'
if (Test-Path $work) { Remove-Item $work -Recurse -Force }
New-Item $work -ItemType Directory | Out-Null
Get-ChildItem $Out -Filter 'PDFALL_*.dwg' | Remove-Item

# The template a form becomes, from its file name ("СПДБ._А3._Горизонтал_ний._Вироби..dwg"):
# @(id, form), form being where its name cell is (see make_templates.lsp).
function Get-Template($name) {
    $std = if ($name -match '^СПДБ') { 'spdb' } elseif ($name -match '^СКД') { 'skd' } else { return $null }
    $page = if ($name -match 'Перш') { '1' } elseif ($name -match 'Наступн') { '2' } else { $null }
    $form = if ($page -eq '1') { 'first' } elseif ($page -eq '2') { 'next' } else { 'list' }
    if ($name -match 'Специф') { return @("PDFALL_spec$page", $form) }
    if ($name -match 'Текстов') { return @("PDFALL_text_$($std)_$page", $form) }
    # -notmatch would leave $Matches unset
    if (-not ($name -match '[АA](\d)')) { return $null }
    $size = "A$($Matches[1])"
    if ($name -match 'Вироби') { $std = 'spdbv' }
    # The orientation comes from the рамка itself (the A5 form is named portrait but drawn landscape),
    # so it is filled in after the run: ? for now.
    return @("PDFALL_list_$($std)_$($size)?", $form)
}

$made = @()
foreach ($f in Get-ChildItem $Formats -Filter '*.dwg' | Sort-Object Name) {
    $t = Get-Template $f.Name
    if (-not $t) { Write-Host "skipped: $($f.Name)"; continue }
    $id = $t[0] -replace '\?', ''
    $dwg = Join-Path $work "$id.dwg"
    Copy-Item -LiteralPath $f.FullName $dwg
    $w = $work -replace '\\', '/'
    $scr = "(setvar `"SECURELOAD`" 0)`r`n(setvar `"FILEDIA`" 0)`r`n(setvar `"CMDECHO`" 0)`r`n(load `"$lsp`")`r`n(load `"$make`")`r`n" +
           "(pdfall-template `"$id`" `"$($t[1])`" `"$w/out`")`r`nQUIT`r`nY`r`n"
    New-Item (Join-Path $work 'out') -ItemType Directory -Force | Out-Null
    $scrPath = Join-Path $work "$id.scr"
    [IO.File]::WriteAllText($scrPath, $scr, (New-Object Text.UTF8Encoding($true)))
    $log = Join-Path $work "$id.log"
    $p = Start-Process $Acad -ArgumentList "/i `"$dwg`" /s `"$scrPath`" /l en-US" -RedirectStandardOutput $log -NoNewWindow -PassThru
    # accoreconsole may hang after QUIT, so it is stopped once the log says the template is done.
    $deadline = (Get-Date).AddSeconds($Seconds)
    $text = ''
    while (-not $p.HasExited) {
        Start-Sleep -Milliseconds 500
        $text = try {
            $fs = [IO.File]::Open($log, 'Open', 'Read', 'ReadWrite')
            try { (New-Object IO.StreamReader($fs, [Text.Encoding]::Unicode)).ReadToEnd() } finally { $fs.Close() }
        } catch { '' }
        if ($text -match 'TEMPLATE-DONE|TEMPLATE-FAIL|; error') { Start-Sleep 2; break }
        if ((Get-Date) -gt $deadline) { break }
    }
    if (-not $p.HasExited) { $p.Kill() }
    Start-Sleep -Milliseconds 300
    $text = [IO.File]::ReadAllText($log, [Text.Encoding]::Unicode)
    $text -split "`r?`n" | Where-Object { $_ -match '^TEMPLATE [^"]*$|TEMPLATE-FAIL|; error' } | ForEach-Object { Write-Host $_.Trim() }
    $outline = Join-Path $work "out\$id.txt"
    if (-not (Test-Path (Join-Path $work "out\$id.dwg")) -or -not (Test-Path $outline)) { throw "$id was not made; see $log" }
    # The orientation, from the рамка's width and height (the outline's first line).
    $wh = (Get-Content $outline -TotalCount 1).Split(' ') | ForEach-Object { [double]$_ }
    $final = if ($t[0] -match '\?$') { $id + $(if ($wh[0] -gt $wh[1]) { 'l' } else { 'p' }) } else { $id }
    Move-Item (Join-Path $work "out\$id.dwg") (Join-Path $Out "$final.dwg") -Force
    $made += [pscustomobject]@{ Id = $final; Outline = Get-Content $outline }
}

# 62-previews.lsp: (id kind standard size page w h (name cell) (x1 y1 x2 y2 ...)) per template.
$rows = foreach ($m in $made | Sort-Object Id) {
    $parts = $m.Id -split '_'
    $kind, $std, $size, $page = switch -Regex ($m.Id) {
        '^PDFALL_list_' { 'list', $parts[2], ($parts[3] -replace '[pl]$', ''), 'nil' }
        '^PDFALL_spec(\d)$' { 'spec', 'skd', 'A4', "`"$($Matches[1])`"" }
        '^PDFALL_text_' { 'text', $parts[2], 'A4', "`"$($parts[3])`"" }
    }
    $wh = $m.Outline[0]
    $cell = $m.Outline[1]
    $lines = ($m.Outline | Select-Object -Skip 2) -join ' '
    "  (`"$($m.Id)`" `"$kind`" `"$std`" `"$size`" $page $wh ($cell)`r`n   ($lines))"
}
$previews = @"
;;; ---- Templates --------------------------------------------------------------
;;; Made by src\make_templates.ps1 from examples\formats; run it again instead of editing this.
;;; Every template PDFLIST, PDFSPEC and PDFTEXT can paste, as
;;;   (file kind standard size page width height (name cell: x1 y1 x2 y2) (lines: x1 y1 x2 y2 ...))
;;; in mm from the рамка's lower-left corner. page is "1" or "2" for the first and a later page of a
;;; специфікація or текстовий документ, nil for a лист. The settings dialog draws the lines as its preview.

(setq *pa-templates* '(
$($rows -join "`r`n")))
"@
$previewPath = Join-Path $PSScriptRoot 'lsp\62-previews.lsp'
[IO.File]::WriteAllText($previewPath, $previews, (New-Object Text.UTF8Encoding($false)))
Write-Host "$($made.Count) templates written to $Out, their outlines to $previewPath"
