"""Merge per-sheet AutoCAD PDF plots into one Загальний and one Загальний друк per марка.

Usage:
    py -3 merge_blueprints.py [FOLDER ...]

Every given folder is processed together with all folders inside it. With no folder
given, the folder this script is in is processed. See GLOSSARY.md for the terms.
"""

import logging
import os
import re
import sys
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path

from pypdf import PdfReader, PdfWriter

GENERAL = "Загальний"
GENERAL_PRINT = "Загальний друк"

# Latin letters that look identical to Cyrillic ones, mapped to the Cyrillic letter.
LOOKALIKES = str.maketrans(
    "ABCEHIKMOPTXYaceiopxy",
    "АВСЕНІКМОРТХУасеіорху",
)

SHEET = "лист"
SPEC = "специфікація"
UNFILLED = "без заливки"

# The title block's name cell reads "<product> <марка>", e.g. "Джгут 1ЧП". These labels
# also start a title-block line but are never a product.
LABELS = {"Аркуш", "Аркушів", "Лист", "Листів", "Масштаб", "Маса", "Літера", "Стадія"}
# The title block sits within this many points of the bottom edge on every sheet format.
TITLE_BLOCK_HEIGHT = 130


@dataclass
class TitleBlock:
    """What the sheet's title block prints; None where the field is empty or unreadable."""

    marka: str | None = None
    sheet: int | None = None
    total: int | None = None


@dataclass
class Part:
    """One recognized input PDF."""

    path: Path
    marka: str
    kind: str  # "filled", "unfilled", "spec", or "output" for an earlier combined document
    number: int
    explicit: bool  # the name contains "лист N"
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
    marka = words[0].upper()
    rest = [w.lower() for w in words[1:]]

    for title in (GENERAL, GENERAL_PRINT):
        if rest == title.lower().split():
            return Part(path, marka, "output", 0, True, f"{marka} {title}.pdf")

    kind = "filled"
    if rest[:1] == [SPEC]:
        kind = "spec"
        rest = rest[1:]
    if kind == "filled" and rest[-2:] == UNFILLED.split():
        kind = "unfilled"
        rest = rest[:-2]

    if rest == []:
        number, explicit = 1, False
    elif len(rest) == 2 and rest[0] == SHEET and rest[1].isdigit():
        number, explicit = int(rest[1]), True
    else:
        return None

    words_out = [marka]
    if kind == "spec":
        words_out.append(SPEC)
    if explicit:
        words_out += [SHEET, str(number)]
    if kind == "unfilled":
        words_out.append(UNFILLED)
    return Part(path, marka, kind, number, explicit, " ".join(words_out) + ".pdf")


def is_marka(text):
    """A марка is letters and digits only, with at least one of each, e.g. 1ЧП, К2, Х1А1Р."""
    return text.isalnum() and any(c.isdigit() for c in text) and any(c.isalpha() for c in text)


def read_marka(items):
    """The марка printed after the product word in the name cell, which may wrap onto the line below."""
    for x0, y0, text in items:
        product = text.split()[0]
        if not product.isalpha() or product in LABELS:
            continue
        line = [(x0, text[len(product):])]
        line += [(x, t) for x, y, t in items if abs(y - y0) < 3 and x0 < x < x0 + 150]
        if not "".join(t for _, t in line).strip():
            line = [(x, t) for x, y, t in items if y0 - 30 < y < y0 - 5 and x0 - 5 < x < x0 + 150]
        marka = "".join(t for _, t in sorted(line)).replace(" ", "").upper()
        if is_marka(marka):
            return marka
    return None


def number_below(items, label_x, label_y, x_max, depth):
    """The number in the table cell under a label, or None if the cell is empty."""
    values = [
        t for x, y, t in items
        if label_y - depth < y < label_y - 3 and label_x - 5 <= x < x_max and t.isdigit()
    ]
    return int(values[0]) if values else None


def read_title_block(items):
    """Read марка, sheet number and sheet count from the text items of a page's title block.

    Handles the drawing form ("Аркуш 1  Аркушів 3" in one line), the first specification
    sheet ("Аркуш" and "Аркушів" labels with values below) and continuation sheets
    (an "Арк." cell in the bottom-right corner with the value below).
    """
    items = [i for i in items if i[1] < TITLE_BLOCK_HEIGHT]
    title = TitleBlock(marka=read_marka(items))
    labels = {}
    for x, y, text in items:
        if m := re.fullmatch(r"Аркуш\s+(\d+)", text):
            title.sheet = int(m.group(1))
        elif m := re.fullmatch(r"Аркушів\s+(\d+)", text):
            title.total = int(m.group(1))
        elif text in ("Аркуш", "Аркушів", "Арк."):
            labels[text] = (x, y)

    if title.sheet is None and "Аркуш" in labels:
        x, y = labels["Аркуш"]
        x_max = labels["Аркушів"][0] if "Аркушів" in labels else x + 40
        title.sheet = number_below(items, x, y, x_max, 20)
    if title.total is None and "Аркушів" in labels:
        x, y = labels["Аркушів"]
        title.total = number_below(items, x, y, x + 50, 20)
    right_edge = max((x for x, _, _ in items), default=0)
    if title.sheet is None and "Арк." in labels and labels["Арк."][0] > right_edge - 60:
        x, y = labels["Арк."]
        title.sheet = number_below(items, x, y, x + 20, 28)
    return title


def load(part):
    """Read the PDF's text and title block, and compare the title block with the file name.

    Raises if the PDF is empty or unreadable.
    """
    pages = PdfReader(part.path).pages
    part.pages = len(pages)
    items = []

    def collect(text, cm, tm, font, size):
        text = text.strip()
        if text:
            x = tm[4] * cm[0] + tm[5] * cm[2] + cm[4]
            y = tm[4] * cm[1] + tm[5] * cm[3] + cm[5]
            items.append((x, y, text.translate(LOOKALIKES)))

    part.text = (pages[0].extract_text(visitor_text=collect) or "") + "".join(
        page.extract_text() or "" for page in pages[1:]
    )
    part.title = title = read_title_block(items)

    if title.marka is None:
        part.unverified.append("марка")
    elif looks(title.marka) != looks(part.marka):
        part.mismatches.append(f"title block says марка '{title.marka}'")
    if title.sheet is None:
        part.unverified.append("аркуш")
    elif title.sheet != part.number:
        part.mismatches.append(f"title block says Аркуш {title.sheet}")


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
            warnings.append(f"'{loser.path.name}' ignored, superseded by '{winner.path.name}'")
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
    try:
        answer = input(f"{question} [y/N] ")
    except EOFError:
        return False
    return answer.strip().lower() in ("y", "yes", "т", "так")


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
            warnings.append(
                f"{marka}: '{part.path.name}' has the same content as '{first.path.name}', wrong sheet plotted?"
            )


def build(folder, marka, sheets, specs, sheet_kind, title, force, dry_run, report, warnings):
    """Merge the given sheet kind plus specs into '<марка> <title>.pdf'.

    Skipped when a sheet is missing, or when a title block contradicts its file name and
    the user did not force the build. With dry_run, only reports what it would write.
    """
    missing = [n for n, by_kind in sorted(sheets.items()) if sheet_kind not in by_kind]
    if missing:
        name = "без заливки" if sheet_kind == "unfilled" else "filled"
        listed = ", ".join(f"лист {n}" for n in missing)
        warnings.append(f"{marka}: '{title}' skipped, no {name} version of {listed}")
        return
    sources = [sheets[n][sheet_kind] for n in sorted(sheets)]
    sources += [specs[n] for n in sorted(specs)]
    if not sources:
        return
    target = folder / f"{marka} {title}.pdf"
    wrong = ", ".join(f"'{p.path.name}'" for p in sources if p.mismatches)
    if wrong and not force:
        warnings.append(f"{marka}: '{target.name}' NOT built, title block mismatch in {wrong}")
        return
    if dry_run:
        report.append(f"{target.name}: {len(sources)} files, {sum(p.pages for p in sources)} pages")
        return
    if wrong:
        warnings.append(f"{marka}: '{target.name}' built anyway despite mismatch in {wrong}")
    try:
        pages = merge([p.path for p in sources], target)
    except PermissionError:
        warnings.append(f"{marka}: could not write '{target.name}', is it open in another program?")
        return
    report.append(f"{target.name}: {len(sources)} files, {pages} pages")


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
                warnings.append(f"'{path.name}' is empty or unreadable, skipped (still plotting or syncing?)")
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
    print("\nThese files have sloppy names:")
    for part, target in renames:
        print(f"  '{part.path.relative_to(root)}'  ->  '{target.name}'")
    if check:
        print("A merge run will offer to rename them.")
    elif ask_yes("Rename these files?"):
        for part, target in renames:
            part.path.rename(target)
            part.path = target
        print("Renamed.")
    else:
        print("Names left as they are.")


def confirm_mismatches(folders, root, check):
    """List every sheet whose title block contradicts its name; return True to build anyway."""
    wrong = [p for folder in folders for p in folder.winners if p.mismatches]
    if not wrong:
        return False
    print("\nTitle block does NOT match the file name:")
    for part in wrong:
        print(f"  X '{part.path.relative_to(root)}': {'; '.join(part.mismatches)}")
    print("The combined files that include these sheets will not be built.")
    return not check and ask_yes("Build them anyway?")


def warn_sheet_count(marka, parts, label, numbers, warnings):
    """Warn when a title block's "Аркушів" promises more sheets than there are files."""
    totals = {p.title.total for p in parts if p.title.total}
    if totals and max(totals) > max(numbers, default=0):
        found = ", ".join(map(str, numbers)) or "none"
        warnings.append(
            f"{marka}: title block says Аркушів {max(totals)}, but only {label} {found} found"
        )


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
                warnings.append(
                    f"'{marka}' and '{other}' look the same but are typed with different "
                    "(Latin/Cyrillic) letters, so they are merged separately"
                )

    report = []
    for marka in sorted(by_marka):
        sheets = defaultdict(dict)
        specs = {}
        for part in by_marka[marka]:
            if part.kind == "spec":
                specs[part.number] = part
            else:
                sheets[part.number][part.kind] = part
        for numbers, label in ((sorted(sheets), SHEET), (sorted(specs), f"{SPEC} {SHEET}")):
            gaps = sorted(set(range(1, max(numbers, default=0) + 1)) - set(numbers))
            if gaps:
                warnings.append(f"{marka}: no {label} {', '.join(map(str, gaps))}, is that right?")
        drawings = [p for p in by_marka[marka] if p.kind != "spec"]
        warn_sheet_count(marka, drawings, SHEET, sorted(sheets), warnings)
        warn_sheet_count(marka, list(specs.values()), f"{SPEC} {SHEET}", sorted(specs), warnings)
        warn_duplicate_plots(marka, by_marka[marka], warnings)
        for kind, title in (("filled", GENERAL), ("unfilled", GENERAL_PRINT)):
            build(folder, marka, sheets, specs, kind, title, force, dry_run, report, warnings)

    print("\nWould build:" if dry_run else "\nBuilt:")
    for line in report or ["(nothing)"]:
        print(f"  {line}")
    if warnings:
        print("\nWarnings:")
        for line in warnings:
            print(f"  ! {line}")
    unverified = [p for p in entry.winners if p.unverified]
    if unverified:
        print("\nCould not check against the title block (field empty or unreadable):")
        for part in sorted(unverified, key=lambda p: p.path.name):
            print(f"  ~ {part.path.name}: {', '.join(part.unverified)}")
    if entry.unrecognized:
        print("\nUnrecognized PDFs (not merged):")
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
    roots = [Path(arg).resolve() for arg in args if arg != "--check"] or [home_folder()]
    if check:
        print("CHECK ONLY: nothing will be built or renamed.")
    for root in roots:
        if not root.is_dir():
            print(f"\n=== {root}\n  ! not a folder, skipped")
            continue
        print(f"Scanning {root} and its subfolders...")
        folders = [f for f in map(scan, walk(root)) if f]
        if not folders:
            print("  no blueprint sheets found")
            continue
        rename_sloppy(folders, root, check)
        force = confirm_mismatches(folders, root, check)
        for entry in folders:
            process(entry, root, force, dry_run=check)
    if getattr(sys, "frozen", False):
        # A double-clicked .exe closes its window on exit; keep the report readable.
        try:
            input("\nPress Enter to close...")
        except EOFError:
            pass


if __name__ == "__main__":
    main()
