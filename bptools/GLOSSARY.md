# Blueprint development

Tools for drawing the листи of a джгут: labels in one look, and роз'єми pasted from a library instead of redrawn. Марка, лист, рамка, специфікація, текстовий документ, шар заливки and джгут mean what [PDFALL's glossary](../pdfall/GLOSSARY.md) says.

## Language

**Стиль оформлення**:
The one right look of each kind of label on a лист: ISOCPEUR italic (ГОСТ 2.304 type B) at a fixed height in mm on the sheet, one text style per kind of label, named after it. A label's kind is the style it is drawn in; its height is the style's, never typed by hand.
_Avoid_: house style, format, template

**Роз'єм**:
A connector at an end of a джгут or on a device, such as D-Sub DB-15F, Futaba M or JST GH 1.25 4 pin. Drawn in one or more вигляди, each with its контакти numbered.
_Avoid_: з'єднувач, конектор, connector

**Вигляд**:
How a part is seen on a лист, named by the side it is seen from: з лицьового боку (the mating face), з монтажного боку (where the wires go in) or з боку контактів. A роз'єм drawn on a лист shows the вигляди the reader needs, each with its «Вигляд з …» note.
_Avoid_: view, проєкція

**Деталь бібліотеки**:
One вигляд of one роз'єм or other part, drawn once, correctly, with its номери контактів, and pasted onto листи as it is instead of being redrawn. Named «<part> — <вигляд>», such as «D-Sub DB-15F — з лицьового боку». The set grows when a new part is needed, and every user has the same set.
_Avoid_: block, symbol, component

**Позиційний номер**:
The number on the shelf of a leader that ends in a dot on a part, naming the part's line in the специфікація (ГОСТ 2.109), one or two sizes larger than the dimension numbers. Numbered across the whole марка, not per лист: the same part has the same number on every лист.
_Avoid_: position, callout, номер позиції

**Номер контакту**:
The number of a pin of a роз'єм, written at that pin in a вигляд.
_Avoid_: pin number, номер піна

**Колір проводу**:
The label naming the colour of a wire next to it, such as «Чорний» or «Жовтий», spelled as in one shared list of colours so the same colour is never named two ways.
_Avoid_: wire label, маркування

**Назва роз'єму**:
The label naming a роз'єм by its type, such as «Futaba - M» or «JST GH 1.25 4 pin», placed by its вигляди.
_Avoid_: part name, title

**Термозбіжна трубка**:
A heat-shrink sleeve over wires or over the back of a роз'єм, drawn at its length on the джгут.
_Avoid_: термоусадка, heat-shrink
