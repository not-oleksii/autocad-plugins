# Context map

Each plugin has its own glossary. A term is defined once, by the plugin that owns it; the other links to it.

| Context | Glossary | Owns |
| --- | --- | --- |
| PDFALL: plotting and combining blueprint sets | [pdfall/GLOSSARY.md](pdfall/GLOSSARY.md) | марка, лист, рамка, специфікація, текстовий документ, шар заливки, без заливки, title block, джгут, загальний, загальний друк |
| BPTOOLS: drawing the листи | [bptools/GLOSSARY.md](bptools/GLOSSARY.md) | стиль оформлення, роз'єм, вигляд, деталь бібліотеки, позиційний номер, номер контакту, колір проводу, назва роз'єму, термозбіжна трубка |

BPTOOLS reads which марка a рамка belongs to from PDFALL, through one public function; it never reads title blocks itself.

Decisions about the whole repository (the shared installer and updater, the code shared between plugins) are in [docs/adr](docs/adr); each plugin's own are in its `docs/adr`.
