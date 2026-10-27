# End-to-end test of the built BPTOOLS.bundle without opening AutoCAD:
#   1. in an empty metric drawing: the стиль оформлення is made, left alone when it is right, and
#      put back when changed; then every label command, driven as a user would type at the command
#      line (the console AutoCAD has no dialogs, so BPWIRE and BPPART ask at the command line),
#      the library's parts, and BPCENTER;
#   2. on the PDFALL sample drawing (..\pdfall\examples\*.dxf), if it is there: позиційні номери and
#      Рис. numbers are counted across the марка with PDFALL loaded, across the drawing without;
#   3. the template BPTOOLS.dwt;
#   4. the ribbon tab.
# Usage: powershell -ExecutionPolicy Bypass -File tests\run.ps1   (run build.bat first, and
# ..\pdfall\build.bat for part 2)
param(
    [string]$Contents = (Join-Path $PSScriptRoot '..\dist\BPTOOLS.bundle\Contents'),
    [string]$Pdfall = (Join-Path $PSScriptRoot '..\..\pdfall\dist\PDFALL.bundle\Contents'),
    [string]$Work = (Join-Path $env:TEMP 'bptools-test'),
    [string]$Acad = 'C:\Program Files\Autodesk\AutoCAD 2024\accoreconsole.exe',
    [int]$Seconds = 300
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\..\common\tests\acad.ps1')
$Contents = (Resolve-Path $Contents).Path
$failures = @()
if (Test-Path $Work) { Remove-Item $Work -Recurse -Force }
New-Item $Work -ItemType Directory | Out-Null
$iso = 'C:\Program Files\Autodesk\AutoCAD 2024\UserDataCache\en-us\Template\acadiso.dwt'
$c = $Contents -replace '\\', '/'

# LISP the scripts share: the BPTOOLS just built, its settings reset (the console's profile is
# seeded with the real user's), and lines that print what a test looks at.
$load = @"
(setvar "SECURELOAD" 0)
(setq *bptools-home* "$($Contents -replace '\\', '\\')")
(load "$c/bptools.lsp")
(foreach s *bp-setting-defaults* (bp:set-setting (car s) (cdr s)))
(defun show (tag x) (princ (strcat "\n" tag "=")) (prin1 x) (princ "|") (princ))
(defun style-of (name / e) (setq e (entget (tblobjname "STYLE" name))) (list (cdr (assoc 40 e)) (strcase (cdr (assoc 3 e)))))
;; TEXT as (text style layer 72 73), MTEXT as (text style layer "M" attachment rows), rows from its height
(defun texts (/ out) (foreach e (bp:model '((0 . "TEXT,MTEXT")))
  (setq out (cons (if (= (cdr (assoc 0 e)) "TEXT")
                    (list (cdr (assoc 1 e)) (cdr (assoc 7 e)) (cdr (assoc 8 e)) (cdr (assoc 72 e)) (cdr (assoc 73 e)))
                    (list (cdr (assoc 1 e)) (cdr (assoc 7 e)) (cdr (assoc 8 e)) "M" (cdr (assoc 71 e)) (fix (+ 0.5 (/ (cdr (assoc 43 e)) (* 1.6 (cdr (assoc 40 e))))))))
                  out))) (reverse out))
(defun attribs (ins / e out) (setq e (entnext ins))
  (while (and e (= (cdr (assoc 0 (entget e))) "ATTRIB")) (setq out (cons (entget e) out) e (entnext e))) (reverse out))
(defun pin-x (ins tag) (vl-some '(lambda (a) (if (= (cdr (assoc 2 a)) tag) (car (cdr (assoc 11 a))))) (attribs ins)))
(defun mid-of (e / b) (setq b (bp:box e)) (list (/ (+ (caar b) (caadr b)) 2.0) (/ (+ (cadar b) (cadadr b)) 2.0)))
(defun mleaders (/ out) (foreach e (bp:model '((0 . "MULTILEADER"))) (setq out (cons (list (cdr (assoc 304 e)) (cdr (assoc 8 e))) out))) (reverse out))
"@

Write-Host 'The стиль оформлення and the label commands in an empty drawing...'
$scr = @"
$load
(show "MADE" (bp:ensure-styles))
(show "AGAIN" (bp:ensure-styles))
(show "STYLES" (mapcar '(lambda (s) (cons (cadr s) (style-of (cadr s)))) *bptools-styles*))
(setq ds (entget (tblobjname "DIMSTYLE" *bptools-dim-style*)))
(show "DIM" (list (cdr (assoc 140 ds)) (cdr (assoc 2 (entget (cdr (assoc 340 ds)))))))
(setq ms (dictsearch (cdr (assoc -1 (dictsearch (namedobjdict) "ACAD_MLEADERSTYLE"))) *bptools-pos-style*))
(show "MLSTYLE" (list (cdr (assoc 45 ms)) (cdr (assoc 2 (entget (cdr (assoc 342 ms))))) (cdr (assoc 2 (entget (cdr (assoc 341 ms))))) (cdr (assoc 174 ms))))
(setq e (entget (tblobjname "STYLE" (bp:kind-style "pin"))))
(entmod (subst '(40 . 3.11) (assoc 40 e) (subst '(3 . "arial.ttf") (assoc 3 e) e)))
(setq e (entget (tblobjname "LAYER" *bptools-layer*)))
(entmod (subst '(62 . -7) (assoc 62 e) (subst '(70 . 4) (assoc 70 e) e)))
(show "RESTORED" (bp:ensure-styles))
(show "PIN-STYLE" (style-of (bp:kind-style "pin")))
(setq e (entget (tblobjname "LAYER" *bptools-layer*)))
(show "LAYER" (list (cdr (assoc 62 e)) (cdr (assoc 70 e))))
(bp:add-pos "7" '(0.0 0.0) '(20.0 10.0))
(show "ADD-POS" (mleaders))
BPPOS
0,40

20,50
30,40
3
50,50

(show "BPPOS" (mleaders))
BPPIN
100,100
110,100
Номер
5
120,100
Малий
130,100

BPWIRE
3
50,0
60,0

BPNAME
JST GH 1.25 4 pin
70,0
BPNAME

80,0
BPVIEW
Монтажний
90,0
BPFIG
0,-50

Схема з'єднань
BPFIG
0,-60
5

(entmake '((0 . "TEXT") (10 0.0 -80.0 0.0) (40 . 3.11) (1 . "Ручний напис") (7 . "Standard") (8 . "0")))
BPSTYLE
_L

Колір
(show "TEXTS" (texts))
(show "PARTS" (bp:part-names))
(show "VIEWS" (mapcar 'cadr (bp:part-views "D-Sub DB-09F")))
(setvar "CLAYER" "0")
BPPART
3
1
90
2
200,200
(setq ins (entlast) d (entget ins))
(show "PASTED" (list (cdr (assoc 2 d)) (cdr (assoc 8 d)) (fix (+ 0.5 (* 180 (/ (cdr (assoc 50 d)) pi)))) (cdr (assoc 41 d)) (length (attribs ins))))
(setq seen nil)
(foreach a (attribs ins) (if (not (member (setq x (list (cdr (assoc 50 a)) (cdr (assoc 40 a)) (cdr (assoc 7 a)))) seen)) (setq seen (cons x seen))))
(show "UPRIGHT" seen)
(show "NAME-NEXT" (bp:setting "Name"))
(setq f (bp:paste-part (car (bp:part-views "D-Sub DB-09F")) '(300.0 300.0 0.0) 0 1)
      b (bp:paste-part (cadr (bp:part-views "D-Sub DB-09F")) '(400.0 300.0 0.0) 0 1)
      m (bp:paste-part (car (bp:part-views "D-Sub DB-09M")) '(500.0 300.0 0.0) 0 1))
(show "PIN1" (list (> (pin-x f "PIN1") (pin-x f "PIN5")) (< (pin-x b "PIN1") (pin-x b "PIN5")) (< (pin-x m "PIN1") (pin-x m "PIN5"))))
(entmake '((0 . "LINE") (10 0.0 -200.0 0.0) (11 100.0 -200.0 0.0)))
(entmake '((0 . "LINE") (10 0.0 -240.0 0.0) (11 100.0 -240.0 0.0)))
(entmake '((0 . "TEXT") (10 10.0 -230.0 0.0) (40 . 2.5) (1 . "ABC") (7 . "Standard") (8 . "0")))
BPCENTER
_L

_W
-1,-250
101,-195


(show "CENTER-H" (list (equal (car (mid-of (entlast))) 50.0 0.01) (mid-of (entlast))))
(bp:add-text "name" "Futaba - M" '(20.0 -236.0 0.0))
BPCENTER
_L

_W
-1,-250
101,-195

Вертикально
(show "CENTER-V" (list (equal (cadr (mid-of (entlast))) -220.0 0.01) (mid-of (entlast))))
(princ "\nEND-OF-TEST")
QUIT
Y
"@
$log = Invoke-Acad $Work 'labels' $scr $iso
function Value($tag) { if ($log -match "(?m)^$tag=(.*?)\|") { $Matches[1] } else { '<none>' } }
# Whether the printed list holds every one of these items, in any order.
function Holds($list, $items) { @($items | Where-Object { -not $list.Contains($_) }).Count -eq 0 }
Check ($log -match 'END-OF-TEST') 'the script ran to the end'
Check ((Value 'MADE') -match 'Позиційний номер' -and (Value 'MADE') -match 'Написи' -and (Value 'MADE') -match '"Розміри"') "the first run makes every style and the layer ($(Value 'MADE'))"
Check ((Value 'AGAIN') -eq 'nil') 'a second run finds nothing to make or put back'
$styles = Value 'STYLES'
Check ($styles -match [regex]::Escape('("Позиційний номер" 5.0 "ISOCPEUI.TTF")') -and $styles -match [regex]::Escape('("Номер контакту" 2.5 "ISOCPEUI.TTF")') -and
       $styles -match [regex]::Escape('("Номер контакту малий" 1.8 "ISOCPEUI.TTF")') -and $styles -match [regex]::Escape('("Підпис рисунка" 5.0 "ISOCPEUI.TTF")')) `
    "each kind of label has its text style in ISOCPEUR italic at its height ($styles)"
Check ((Value 'DIM') -eq '(3.5 "Розміри")') "the «Розміри» dimension style writes its numbers 3.5 high in the «Розміри» style ($(Value 'DIM'))"
Check ((Value 'MLSTYLE') -eq '(5.0 "Позиційний номер" "_Dot" 5)') "позиційні номери: 5 high in their style, a dot at the part, the number on the shelf ($(Value 'MLSTYLE'))"
Check ((Value 'RESTORED') -eq '("Номер контакту" "Написи")' -and (Value 'PIN-STYLE') -eq '(2.5 "ISOCPEUI.TTF")' -and (Value 'LAYER') -eq '(7 0)') `
    "a style changed by hand is put back, and the layer turned on and unlocked ($(Value 'RESTORED'), $(Value 'PIN-STYLE'), $(Value 'LAYER'))"
Check ((Value 'ADD-POS') -eq '(("7" "Написи"))') "a позиційний номер is a multileader with the number, on «Написи» ($(Value 'ADD-POS'))"
$pos = Value 'BPPOS'
Check ((Holds $pos '("7" "Написи")', '("8" "Написи")', '("3" "Написи")') -and ([regex]::Matches($pos, '"Написи"').Count -eq 3)) "BPPOS offers the next number (8) and takes another typed (3) ($pos)"
$texts = Value 'TEXTS'
Check (Holds $texts '("1" "Номер контакту" "Написи" 1 2)', '("2" "Номер контакту" "Написи" 1 2)', '("5" "Номер контакту" "Написи" 1 2)', '("6" "Номер контакту малий" "Написи" 1 2)') `
    'BPPIN numbers the pins one per click, centred, goes on from the number given, and switches to the small style'
Check ([regex]::Matches($texts, [regex]::Escape('("Жовтий" "Колір проводу" "Написи" 1 2)')).Count -eq 2) 'BPWIRE puts colour 3 of the list wherever it is clicked'
Check ([regex]::Matches($texts, [regex]::Escape('("JST GH 1.25 4 pin" "Назва роз''єму" "Написи" "M" 5 1)')).Count -eq 2) 'BPNAME writes the name typed as one row of multiline text, centred, and offers it again the next time'
Check (Holds $texts '("Вигляд з монтажного боку" "Вигляд" "Написи" "M" 5 1)') 'BPVIEW writes the note of the side picked'
Check (Holds $texts '("Рис. 1. Схема з''єднань" "Підпис рисунка" "Написи" "M" 5 1)', '("Рис. 5." "Підпис рисунка" "Написи" "M" 5 1)') 'BPFIG numbers the captions and takes a number typed'
Check (Holds $texts '("Ручний напис" "Колір проводу" "Написи" 0 0)') "BPSTYLE gives a text typed by hand the style picked ($texts)"
Check ($log -match 'Стиль «Колір проводу» отримали написів: 1') 'and says how many'
Check ($log -notmatch 'Помилка BP') 'no command stopped with an error'
Check ((Value 'PARTS') -eq '("D-Sub DB-09F" "D-Sub DB-09M" "D-Sub DB-15F" "D-Sub DB-15M")' -and (Value 'VIEWS') -eq '("front" "back")') `
    "the library has the generated D-Sub parts, each from the front and the back ($(Value 'PARTS'))"
Check ((Value 'PASTED') -eq '("D-Sub DB-15F — з лицьового боку" "0" 90 2.0 15)') "BPPART pastes the вигляд picked, turned and scaled as asked, on the current layer, with its 15 pin numbers ($(Value 'PASTED'))"
Check ((Value 'UPRIGHT') -eq '((0.0 1.8 "Номер контакту малий"))') "the pin numbers stay upright and 1.8 high whatever the rotation and scale ($(Value 'UPRIGHT'))"
Check ((Value 'NAME-NEXT') -eq '"D-Sub DB-15F"') 'BPNAME then offers the name of the part pasted'
Check ((Value 'PIN1') -eq '(T T T)') 'pin 1 is at the right of a female роз''єм seen from the front, at the left seen from the back, and at the left of a male one from the front'
Check ((Value 'CENTER-H') -match '^\(T ') "BPCENTER moves a text across to midway between the objects' outermost points ($(Value 'CENTER-H'))"
Check ((Value 'CENTER-V') -match '^\(T ') "and, Вертикально, up or down ($(Value 'CENTER-V'))"

$dxf = Get-ChildItem (Join-Path $PSScriptRoot '..\..\pdfall\examples') -Filter '*.dxf' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($dxf -and (Test-Path (Join-Path $Pdfall 'pdfall.lsp'))) {
    Write-Host 'Numbers across the марка, on the PDFALL sample drawing...'
    $p = $Pdfall -replace '\\', '/'
    $scr = @"
(setq *pdfall-home* "$($Pdfall -replace '\\', '\\')")
(load "$p/pdfall.lsp")
$load
(defun mid (m / r) (setq r (vl-some '(lambda (r) (if (= (pa:get 'marka r) m) r)) (car (pa:read-drawing))))
  (mapcar '(lambda (a b) (/ (+ a b) 2.0)) (pa:get 'll r) (pa:get 'ur r)))
(setq k1 (mid "К1") p1 (mid "1П"))
(bp:ensure-styles)
(bp:add-pos "50" k1 (mapcar '+ k1 '(10.0 10.0 0.0)))
(bp:add-pos "90" p1 (mapcar '+ p1 '(10.0 10.0 0.0)))
(bp:add-text "figure" (bp:figure-text 2 "") k1)
(show "WITH-PDFALL" (list (bp:next-pos k1) (bp:next-pos p1) (bp:next-figure k1) (bp:next-figure p1)))
(setq pdfall:marka-at nil)
(show "WITHOUT-PDFALL" (list (bp:next-pos k1) (bp:next-figure p1)))
(princ "\nEND-OF-TEST")
QUIT
Y
"@
    $nlog = Invoke-Acad $Work 'numbers' $scr $dxf.FullName
    $log = $nlog
    Check ((Value 'WITH-PDFALL') -eq '(51 91 3 1)') "with PDFALL, the next number counts only the марка's own (К1: 51, 1П: 91, Рис. in К1: 3, in 1П: 1) ($(Value 'WITH-PDFALL'))"
    Check ((Value 'WITHOUT-PDFALL') -eq '(91 3)' -and $nlog -match 'PDFALL не завантажено') "without PDFALL, across the whole drawing, and it says so ($(Value 'WITHOUT-PDFALL'))"
}
else { Write-Host '  (skipped: no ..\pdfall\examples\*.dxf or no built PDFALL)' }

Write-Host 'The template...'
$scr = @"
(princ (strcat "\nCURRENT=" (getvar "CLAYER") "," (getvar "TEXTSTYLE") "," (getvar "CMLEADERSTYLE") "," (getvar "DIMSTYLE") "," (itoa (getvar "INSUNITS")) "|"))
(princ (strcat "\nHAS=" (if (and (tblobjname "LAYER" "Написи") (tblobjname "STYLE" "Номер контакту")) "yes" "no") "|"))
QUIT
Y
"@
$log = Invoke-Acad $Work 'template' $scr (Join-Path $Contents 'BPTOOLS.dwt')
Check ((Value 'CURRENT') -eq '0,Примітка,Позиційний номер,Розміри,4' -and (Value 'HAS') -eq 'yes') "BPTOOLS.dwt has the styles, with «Примітка», «Позиційний номер» and «Розміри» current, in mm ($(Value 'CURRENT'))"

Write-Host 'The ribbon tab...'
[Reflection.Assembly]::LoadFrom('C:\Program Files\Autodesk\AutoCAD 2024\AcCui.dll') | Out-Null
$cs = New-Object Autodesk.AutoCAD.Customization.CustomizationSection((Join-Path $Contents 'BPTOOLS.cuix'))
$tab = $cs.MenuGroup.RibbonRoot.RibbonTabSources | Select-Object -First 1
$macros = @($cs.MenuGroup.MacroGroups | ForEach-Object { $_.MenuMacros } | ForEach-Object { $_.macro.CLICommand })
Check ($tab.Text -eq 'Креслення') "BPTOOLS.cuix has a «Креслення» tab ($($tab.Text))"
Check ((@('BPPOS', 'BPPIN', 'BPWIRE', 'BPNAME', 'BPVIEW', 'BPFIG', 'BPSTYLE', 'TEXTALIGN', 'MLEADERALIGN', 'BPNEW') | Where-Object { $macros -notcontains $_ }).Count -eq 0) `
    "with a button for each command ($($macros -join ', '))"
Check (@(Get-ChildItem $Contents -Filter '*_32.png').Count -eq 12) 'and an icon for each'

if ($failures) { Write-Host "FAILED: $($failures -join '; ')"; exit 1 } else { Write-Host 'All passed.' }
