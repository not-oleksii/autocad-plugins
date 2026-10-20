"""Merge per-sheet AutoCAD PDF plots into one загальний and one загальний друк per марка.

Usage:
    py -3 merge_blueprints.py [FOLDER ...]

Every given folder is processed together with all folders inside it. With no folder
given, the folder this script is in is processed. See GLOSSARY.md for the terms.
"""

import json
import logging
import os
import re
import sys
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path

from pypdf import PdfReader, PdfWriter


def load_texts():
    """messages.json: next to this script, or packed into merge.exe by PyInstaller."""
    base = Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parent))
    return json.loads((base / "messages.json").read_text(encoding="utf-8"))


TEXTS = load_texts()


def msg(key, **values):
    """The message key from messages.json with each {name} filled in."""
    return TEXTS["messages"][key].format(**values)


def label(key):
    """A word read from title blocks."""
    return TEXTS["labels"][key]


def file_word(key):
    """A word of the PDF names."""
    return TEXTS["files"][key]


GENERAL = file_word("general")
GENERAL_PRINT = file_word("general-print")

# Latin letters that look identical to Cyrillic ones, mapped to the Cyrillic letter.
LOOKALIKES = str.maketrans(label("lookalike-latin"), label("lookalike-cyrillic"))

SHEET = file_word("sheet")
SPEC = file_word("spec")
TEXT = file_word("text")
UNFILLED = file_word("unfilled")

SHEET_LABEL = label("sheet")
TOTAL_LABEL = label("total")
CORNER_LABEL = label("corner")
# The title block's name cell reads "[prefix] <марка>", e.g. "Джгут 1ЧП" or "1ЧП". These labels
# also start a title-block line but never a name cell.
LABELS = set(label("not-names"))
# The title block sits within this many points of the bottom edge on every sheet format, and
# within this many of the right edge (185 mm plus the 5 mm margin, and a little more).
TITLE_BLOCK_HEIGHT = 130
TITLE_BLOCK_WIDTH = 570
# The name cell lies between these distances from the right edge and below this height on every
# form, in points (as the LISP reader's pa:name-cell-p, in mm: 55 to 125, under 45). On a later
# page of a специфікація or текстовий документ it is wider, reaching 15 mm from the edge.
MM = 72 / 25.4
NAME_CELL_LEFT = 125 * MM
NAME_CELL_RIGHT = 55 * MM
NAME_CELL_RIGHT_LATER = 15 * MM
NAME_CELL_TOP = 45 * MM


@dataclass
class TitleBlock:
    """What the sheet's title block prints; None where the field is empty or unreadable."""

    marka: str | None = None
    sheet: int | None = None
    total: int | None = None
    alone: list = field(default_factory=list)  # texts that are only a марка, as old name cells print it
    name: list = field(default_factory=list)  # the name cell's lines, as lists of words


@dataclass
class Part:
    """One recognized input PDF."""

    path: Path
    marka: str
    kind: str  # "filled", "unfilled", "spec", "text", or "output" for an earlier combined document
    number: int
    explicit: bool  # the name contains the sheet number
    canonical: str  # the file name this part should have
    text: str = ""
    pages: int = 0
    title: TitleBlock = field(default_factory=TitleBlock)
    mismatches: list = field(default_factory=list)  # where the title block contradicts the name
    unverified: list = field(default_factory=list)  # title-block fields that could not be read

    @property
    def mtime(self):
        return self.path.stat().st_mtime


def looks(text):
    """The text with Latin lookalike letters made Cyrillic, for comparing how text looks."""
    return text.translate(LOOKALIKES).upper()


def normalize_words(stem):
    """The words of a file name. The марка is kept as typed: it may mix Latin and Cyrillic, like X1A1Р."""
    words = stem.split(maxsplit=1)
    if len(words) < 2:
        return words
    rest = re.sub(rf"({SHEET})(?=\d)", r"\1 ", words[1].translate(LOOKALIKES), flags=re.IGNORECASE)
    return [words[0]] + rest.split()


def parse(path):
    """Return a Part, or None if the name is unrecognized."""
    if path.suffix.lower() != ".pdf":
        return None
    words = normalize_words(path.stem)
    if not words:
        return None
    marka = words[0]
    rest = [w.lower() for w in words[1:]]

    for title in (GENERAL, GENERAL_PRINT):
        if rest == title.lower().split():
            return Part(path, marka, "output", 0, True, f"{marka} {title}.pdf")

    kind = "filled"
    if rest[:len(TEXT.split())] == TEXT.split():
        kind = "text"
        rest = rest[len(TEXT.split()):]
        if len(rest) == 1 and rest[0].isdigit():
            number, explicit = int(rest[0]), True
        elif rest == []:
            number, explicit = 1, False
        else:
            return None
    elif rest[:1] == [SPEC]:
        kind = "spec"
        rest = rest[1:]
        # earlier versions wrote "специфікація лист N"
        old_word = rest[:1] == [SHEET]
        if old_word:
            rest = rest[1:]
        if len(rest) == 1 and rest[0].isdigit():
            number, explicit = int(rest[0]), True
        elif rest == [] and not old_word:
            number, explicit = 1, False
        else:
            return None
    else:
        if rest[-2:] == UNFILLED.split():
            kind = "unfilled"
            rest = rest[:-2]
        if rest == []:
            number, explicit = 1, False
        elif len(rest) == 2 and rest[0] == SHEET and rest[1].isdigit():
            number, explicit = int(rest[1]), True
        else:
            return None

    # <марка> <вид> <NN>[ <варіант>].pdf, always numbered, with two digits at least
    words_out = [marka, {"spec": SPEC, "text": TEXT}.get(kind, SHEET), f"{number:02d}"]
    if kind == "unfilled":
        words_out.append(UNFILLED)
    return Part(path, marka, kind, number, explicit, " ".join(words_out) + ".pdf")


def is_marka(text):
    """The usual марка: letters and digits only, with at least one of each, e.g. 1ЧП, К2, Х1А1Р.
    A марка may also be any other word ("Лорем"), see read_title_block."""
    return text.isalnum() and any(c.isdigit() for c in text) and any(c.isalpha() for c in text)


def name_marka(words):
    """The usual марка among the words of a name cell: the first word with a letter and a digit, after a
    prefix of words without digits ("Джгут", "Джгут живлення" or none), as the LISP reader's
    pa:name-marka. None for a title-block label ("Формат А3") or when a word before it has a digit."""
    if not words or words[0] in LABELS:
        return None
    for word in words:
        if is_marka(word):
            return word
        if any(c.isdigit() for c in word):
            return None
    return None


def read_name(items, page_width=None, raw=False, right=NAME_CELL_RIGHT):
    """The lines of the name cell from the top, as lists of words: a long prefix or марка may wrap
    onto the line below. Only texts in the name cell count, so the organisation cell or a caption
    near the title block is never taken for the марка.

    A line arrives in pieces wherever the font changes, even inside a word ("Джгут ", "1", "ЧП"),
    and a piece keeps the space after it. With raw, items are such pieces, joined as they are;
    otherwise they are whole texts, joined with spaces. right is where the name cell ends."""
    if page_width is not None:
        items = [i for i in items
                 if page_width - NAME_CELL_LEFT < i[0] < page_width - right and i[1] < NAME_CELL_TOP]
    lines = []
    for x, y, text in sorted(items, key=lambda i: -i[1]):
        if lines and abs(lines[-1][0] - y) < 3:
            lines[-1][1].append((x, text))
        else:
            lines.append((y, [(x, text)]))
    glue = "" if raw else " "
    return [glue.join(t for _, t in sorted(line)).split() for _, line in lines]


def number_below(items, label_x, label_y, x_max, depth):
    """The number in the table cell under a label, or None if the cell is empty."""
    values = [
        t for x, y, t in items
        if label_y - depth < y < label_y - 3 and label_x - 5 <= x < x_max and t.isdigit()
    ]
    return int(values[0]) if values else None


def number_after(items, label_x, label_y, x_max):
    """The number written as a text of its own after a label in the same row (old title blocks)."""
    values = [t for x, y, t in items if abs(y - label_y) < 4 and label_x < x < x_max and t.isdigit()]
    return int(values[0]) if values else None


def read_title_block(items, page_width=None, pieces=None):
    """Read марка, sheet number and sheet count from the text items of a page's title block.

    With page_width, texts left of the title block are left out: on an A3 page, a caption in the
    drawing near the bottom edge ("контактів X6") would read as a name cell. pieces are the same
    texts as they came, with their spaces, for the name cell (see read_name).

    Handles the drawing form ("Аркуш 1  Аркушів 3" in one line, or in an old title block
    "Аркуш", "1", "Аркушів", "3" as separate texts), the first specification sheet ("Аркуш"
    and "Аркушів" labels with values below) and continuation sheets (an "Арк." cell in the
    bottom-right corner with the value below).
    """
    items = [i for i in items if i[1] < TITLE_BLOCK_HEIGHT
             and (page_width is None or i[0] > page_width - TITLE_BLOCK_WIDTH)]
    title = TitleBlock()
    title.alone = [t.replace(" ", "") for _, _, t in items if is_marka(t.replace(" ", ""))]
    labels = {}
    for x, y, text in items:
        if m := re.fullmatch(rf"{re.escape(SHEET_LABEL)}\s+(\d+)", text):
            title.sheet = int(m.group(1))
        elif m := re.fullmatch(rf"{re.escape(TOTAL_LABEL)}\s+(\d+)", text):
            title.total = int(m.group(1))
        elif text in (SHEET_LABEL, TOTAL_LABEL, CORNER_LABEL):
            # the changes table has an "Арк." column too: the corner cell is the rightmost
            if text != CORNER_LABEL or text not in labels or x > labels[text][0]:
                labels[text] = (x, y)

    if title.sheet is None and SHEET_LABEL in labels:
        x, y = labels[SHEET_LABEL]
        x_max = labels[TOTAL_LABEL][0] if TOTAL_LABEL in labels else x + 40
        title.sheet = number_below(items, x, y, x_max, 20)
        if title.sheet is None:
            title.sheet = number_after(items, x, y, x_max)
    if title.total is None and TOTAL_LABEL in labels:
        x, y = labels[TOTAL_LABEL]
        title.total = number_below(items, x, y, x + 50, 20)
        if title.total is None:
            title.total = number_after(items, x, y, x + 60)
    right_edge = max((x for x, _, _ in items), default=0)
    later = CORNER_LABEL in labels and labels[CORNER_LABEL][0] > right_edge - 60
    if title.sheet is None and later:
        x, y = labels[CORNER_LABEL]
        title.sheet = number_below(items, x, y, x + 20, 28)
    right = NAME_CELL_RIGHT_LATER if later else NAME_CELL_RIGHT
    title.name = (read_name(pieces, page_width, raw=True, right=right) if pieces is not None
                  else read_name(items, page_width, right=right))
    title.marka = name_marka([w for line in title.name for w in line])
    return title


def load(part):
    """Read the PDF's text and title block, and compare the title block with the file name.

    Raises if the PDF is empty or unreadable.
    """
    pages = PdfReader(part.path).pages
    part.pages = len(pages)
    items, pieces = [], []

    def collect(text, cm, tm, font, size):
        if text.strip():
            x = tm[4] * cm[0] + tm[5] * cm[2] + cm[4]
            y = tm[4] * cm[1] + tm[5] * cm[3] + cm[5]
            items.append((x, y, text.strip().translate(LOOKALIKES)))
            pieces.append((x, y, text.translate(LOOKALIKES)))

    part.text = (pages[0].extract_text(visitor_text=collect) or "") + "".join(
        page.extract_text() or "" for page in pages[1:]
    )
    part.title = title = read_title_block(items, float(pages[0].mediabox.width), pieces)
    # An old name cell prints only the марка ("M1"). Any title-block text could be only a марка, so
    # such a text confirms the file's марка but never contradicts it.
    if title.marka is None and any(looks(t) == looks(part.marka) for t in title.alone):
        title.marka = part.marka
    # A марка without a digit ("Лорем") is a word of the name cell: the last of its first line, unless
    # a long prefix wrapped it onto the next one.
    words = [w for line in title.name for w in line]
    if title.marka is None and any(looks(w) == looks(part.marka) for w in words):
        title.marka = part.marka
    if title.marka is None and words and words[0] not in LABELS:
        title.marka = title.name[0][-1]

    if title.marka is None:
        part.unverified.append(msg("merge.field-marka"))
    elif looks(title.marka) != looks(part.marka):
        part.mismatches.append(msg("merge.title-marka", marka=title.marka))
    if title.sheet is None:
        part.unverified.append(msg("merge.field-sheet"))
    elif title.sheet != part.number:
        part.mismatches.append(msg("merge.title-sheet", sheet=title.sheet))


def pick_winners(parts, warnings):
    """Keep one Part per (марка, kind, number): explicit "лист N" first, then the newest file."""
    groups = defaultdict(list)
    for part in parts:
        groups[(part.marka, part.kind, part.number)].append(part)
    winners = []
    for candidates in groups.values():
        candidates.sort(key=lambda p: (p.explicit, p.mtime), reverse=True)
        winner = candidates[0]
        winners.append(winner)
        for loser in candidates[1:]:
            warnings.append(msg("merge.replaced", loser=loser.path.name, winner=winner.path.name))
    return winners


def same_file(a, b):
    try:
        return os.path.samefile(a, b)
    except OSError:
        return False


def propose_renames(parts):
    """Renames for parts whose name differs from the canonical one and whose target is free."""
    renames = []
    for part in parts:
        target = part.path.with_name(part.canonical)
        if part.path.name == part.canonical:
            continue
        if target.exists() and not same_file(target, part.path):
            continue
        renames.append((part, target))
    return renames


def ask_yes(question):
    yes = msg("merge.yes")
    try:
        answer = input(msg("merge.ask", question=question, yes=yes, no=msg("merge.no")))
    except EOFError:
        return False
    return answer.strip().lower() in ("y", "yes", yes.lower()[:1], yes.lower())


def merge(sources, target):
    writer = PdfWriter()
    for source in sources:
        writer.append(PdfReader(source))
    tmp = target.with_name(target.name + ".tmp")
    with open(tmp, "wb") as f:
        writer.write(f)
    os.replace(tmp, target)
    return len(writer.pages)


def warn_duplicate_plots(marka, parts, warnings):
    """Warn when two different sheets of one kind carry identical text, i.e. one was plotted twice."""
    seen = {}
    for part in sorted(parts, key=lambda p: (p.kind, p.number)):
        text = part.text.strip()
        if not text:
            continue
        first = seen.setdefault((part.kind, text), part)
        if first is not part:
            warnings.append(msg("merge.same-content", marka=marka, name=part.path.name, first=first.path.name))


def build(folder, marka, sheets, specs, texts, sheet_kind, title, force, dry_run, report, warnings):
    """Merge the given sheet kind, then the specs and the text documents, into '<марка> <title>.pdf'.

    Skipped when a sheet is missing, or when a title block contradicts its file name and
    the user did not force the build. With dry_run, only reports what it would write.
    """
    missing = [n for n, by_kind in sorted(sheets.items()) if sheet_kind not in by_kind]
    if missing:
        variant = msg("merge.variant-unfilled") if sheet_kind == "unfilled" else msg("merge.variant-filled")
        listed = ", ".join(msg("merge.sheet-n", n=n) for n in missing)
        warnings.append(msg("merge.missing-variant", marka=marka, title=title, variant=variant, sheets=listed))
        return
    sources = [sheets[n][sheet_kind] for n in sorted(sheets)]
    sources += [specs[n] for n in sorted(specs)]
    sources += [texts[n] for n in sorted(texts)]
    if not sources:
        return
    target = folder / f"{marka} {title}.pdf"
    wrong = ", ".join(f"'{p.path.name}'" for p in sources if p.mismatches)
    if wrong and not force:
        warnings.append(msg("merge.mismatch-skipped", marka=marka, name=target.name, files=wrong))
        return
    if dry_run:
        report.append(msg("merge.summary", name=target.name, files=len(sources), pages=sum(p.pages for p in sources)))
        return
    if wrong:
        warnings.append(msg("merge.mismatch-forced", marka=marka, name=target.name, files=wrong))
    try:
        pages = merge([p.path for p in sources], target)
    except PermissionError:
        warnings.append(msg("merge.cannot-write", marka=marka, name=target.name))
        return
    report.append(msg("merge.summary", name=target.name, files=len(sources), pages=pages))


@dataclass
class Folder:
    """One folder holding blueprint sheets, scanned but not merged yet."""

    path: Path
    winners: list
    outputs: list
    warnings: list
    unrecognized: list


def scan(folder):
    """Return a Folder, or None when the folder holds no blueprint sheets."""
    parts, outputs, unrecognized, warnings = [], [], [], []
    for path in sorted(folder.iterdir()):
        if not path.is_file() or path.suffix.lower() != ".pdf":
            continue
        part = parse(path)
        if part is None:
            unrecognized.append(path.name)
        elif part.kind == "output":
            outputs.append(part)
        else:
            try:
                load(part)
            except Exception:
                warnings.append(msg("merge.unreadable", name=path.name))
                continue
            parts.append(part)
    if not parts:
        return None
    winners = pick_winners(parts, warnings)
    return Folder(folder, winners, outputs, warnings, unrecognized)


def walk(root):
    """The root folder and every folder below it, parents before children, in name order."""
    for dirpath, dirnames, _ in os.walk(root):
        dirnames.sort()
        yield Path(dirpath)


def rename_sloppy(folders, root, check):
    """Offer every cosmetic rename in all folders behind a single prompt; only list them in check mode."""
    renames = [r for folder in folders for r in propose_renames(folder.winners + folder.outputs)]
    if not renames:
        return
    print("\n" + msg("merge.sloppy-names"))
    for part, target in renames:
        print(f"  '{part.path.relative_to(root)}'  ->  '{target.name}'")
    if check:
        print(msg("merge.rename-later"))
    elif ask_yes(msg("merge.rename-ask")):
        for part, target in renames:
            part.path.rename(target)
            part.path = target
        print(msg("merge.renamed"))
    else:
        print(msg("merge.not-renamed"))


def confirm_mismatches(folders, root, check, forced=False):
    """List every sheet whose title block contradicts its name; return True to build anyway.

    forced: PDFALL plotted despite wrong numbers, the user agreed there, so merge.exe doesn't ask."""
    wrong = [p for folder in folders for p in folder.winners if p.mismatches]
    if not wrong:
        return forced
    print("\n" + msg("merge.mismatches"))
    for part in wrong:
        print(f"  X '{part.path.relative_to(root)}': {'; '.join(part.mismatches)}")
    if forced and not check:
        print(msg("merge.forced"))
        return True
    print(msg("merge.mismatches-skipped"))
    return not check and ask_yes(msg("merge.build-anyway"))


def warn_sheet_count(marka, parts, label, numbers, warnings):
    """Warn when a title block's "Аркушів" promises more sheets than there are files."""
    totals = {p.title.total for p in parts if p.title.total}
    if totals and max(totals) > max(numbers, default=0):
        found = ", ".join(map(str, numbers)) or msg("merge.none")
        warnings.append(msg("merge.total-more", marka=marka, total=max(totals), label=label, found=found))


def process(entry, root, force, dry_run):
    folder, warnings = entry.path, entry.warnings
    print(f"\n=== {folder.relative_to(root.parent)}")

    by_marka = defaultdict(list)
    for part in entry.winners:
        by_marka[part.marka].append(part)
    markas = sorted(by_marka)
    for i, marka in enumerate(markas):
        for other in markas[i + 1:]:
            if looks(marka) == looks(other):
                warnings.append(msg("merge.lookalike", marka=marka, other=other))

    report = []
    for marka in sorted(by_marka):
        sheets = defaultdict(dict)
        specs, texts = {}, {}
        for part in by_marka[marka]:
            if part.kind == "spec":
                specs[part.number] = part
            elif part.kind == "text":
                texts[part.number] = part
            else:
                sheets[part.number][part.kind] = part
        for numbers, label in ((sorted(sheets), SHEET), (sorted(specs), SPEC), (sorted(texts), TEXT)):
            gaps = sorted(set(range(1, max(numbers, default=0) + 1)) - set(numbers))
            if gaps:
                warnings.append(msg("merge.gaps", marka=marka, label=label, gaps=", ".join(map(str, gaps))))
        drawings = [p for p in by_marka[marka] if p.kind in ("filled", "unfilled")]
        warn_sheet_count(marka, drawings, SHEET, sorted(sheets), warnings)
        warn_sheet_count(marka, list(specs.values()), SPEC, sorted(specs), warnings)
        warn_sheet_count(marka, list(texts.values()), TEXT, sorted(texts), warnings)
        warn_duplicate_plots(marka, by_marka[marka], warnings)
        for kind, title in (("filled", GENERAL), ("unfilled", GENERAL_PRINT)):
            build(folder, marka, sheets, specs, texts, kind, title, force, dry_run, report, warnings)

    print("\n" + (msg("merge.will-build") if dry_run else msg("merge.built")))
    for line in report or [msg("merge.nothing")]:
        print(f"  {line}")
    if warnings:
        print("\n" + msg("warnings"))
        for line in warnings:
            print(f"  ! {line}")
    unverified = [p for p in entry.winners if p.unverified]
    if unverified:
        print("\n" + msg("merge.unverified"))
        for part in sorted(unverified, key=lambda p: p.path.name):
            print(f"  ~ {part.path.name}: {', '.join(part.unverified)}")
    if entry.unrecognized:
        print("\n" + msg("merge.unrecognized"))
        for name in entry.unrecognized:
            print(f"  ? {name}")


def home_folder():
    """The folder holding this script, or the .exe when packaged with PyInstaller."""
    frozen = getattr(sys, "frozen", False)
    return Path(sys.executable if frozen else __file__).resolve().parent


def main(check=False):
    """Merge every марка under the given folders; with check, only report and change nothing."""
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    # AutoCAD's PDFs trip harmless pypdf parser warnings on every file.
    logging.getLogger("pypdf").setLevel(logging.ERROR)
    args = sys.argv[1:]
    check = check or "--check" in args
    forced = "--force" in args
    roots = [Path(arg).resolve() for arg in args if arg not in ("--check", "--force")] or [home_folder()]
    if check:
        print(msg("merge.check-only"))
    for root in roots:
        if not root.is_dir():
            print(f"\n=== {root}\n  ! " + msg("merge.not-a-folder"))
            continue
        print(msg("merge.scanning", folder=root))
        folders = [f for f in map(scan, walk(root)) if f]
        if not folders:
            print("  " + msg("merge.no-sheets"))
            continue
        rename_sloppy(folders, root, check)
        force = confirm_mismatches(folders, root, check, forced)
        for entry in folders:
            process(entry, root, force, dry_run=check)
    if getattr(sys, "frozen", False):
        # A double-clicked .exe closes its window on exit; keep the report readable.
        try:
            input("\n" + msg("merge.press-enter"))
        except EOFError:
            pass


if __name__ == "__main__":
    main()
