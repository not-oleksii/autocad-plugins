r"""Turns the drawings of the components library into parts BPPART can paste (docs/adr/0002). The 10
views of each drawing become the blocks «<part> — <вигляд>» of one drawing,
src\parts\components\<id>.dwg, with their preview in <id>.txt; src\lsp\46-components.lsp lists them.

    make_components.py <components library> [--only=<regex>] [--acad=<accoreconsole.exe>]

<components library> holds a folder per kind of part (connectors, ...) with its drawings in
"dwg blueprints". A drawing is read again only when it changed since the last run, which
src\parts\components\index.tsv remembers; --only reads again the ones whose path matches anyway.
"""
import concurrent.futures as cf
import hashlib
import math
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import ezdxf
from ezdxf import bbox, path as ezpath
from ezdxf.enums import TextEntityAlignment
from ezdxf.math import Vec2

SRC = Path(__file__).resolve().parents[2] / "src"
OUT = SRC / "parts" / "components"
CATALOG = SRC / "lsp" / "46-components.lsp"
CORE = r"C:\Program Files\Autodesk\AutoCAD 2024\accoreconsole.exe"
WORK = Path(tempfile.gettempdir()) / "bptools-components"
DASH = " — "
PREVIEW = 400  # steps across a view's longer side in its preview

# The views of a library drawing, by where they sit (see tools\step-views): key and вигляд, as
# *bptools-views* in src\lsp\00-settings.lsp has them.
VIEWS = {
    "from-front": "спереду", "from-back": "ззаду", "top": "зверху", "bottom": "знизу",
    "left": "зліва", "right": "справа",
    "iso-left-top": "спереду зліва зверху", "iso-right-top": "спереду справа зверху",
    "iso-left-bottom": "спереду зліва знизу", "iso-right-bottom": "спереду справа знизу",
}


def block_safe(name):
    """The name as a block name: AutoCAD takes none of < > / \\ " : ; ? * | , = ` in one (as bp:block-safe)."""
    return re.sub(r'[<>/\\":;?*|=`]', "-", name.replace(",", "."))


def part_id(rel):
    slug = re.sub(r"[^A-Za-z0-9]+", "_", Path(rel).stem).strip("_")[:40]
    return f"{slug}_{hashlib.sha1(rel.lower().encode()).hexdigest()[:6]}"


def console(drawing, script, work):
    """Runs the console AutoCAD on drawing with the script's lines."""
    scr = work / "run.scr"
    scr.write_text("\n".join(['(setvar "FILEDIA" 0)', *script, "_.QUIT", "_Y", ""]), encoding="utf-8-sig")
    try:
        subprocess.run([CORE, "/i", str(drawing), "/s", str(scr), "/l", "en-US"], cwd=work, capture_output=True, timeout=300)
    except subprocess.TimeoutExpired:
        pass


# ---- Pin numbers -----------------------------------------------------------------------------
# The model's axes as each view shows them, its x and its y, Z pointing at the viewer of the front
# view (as tools\step-views lays the views out); the axis each view looks along, and from which end.
AXES = {"from-front": ("+X", "+Y"), "from-back": ("-X", "+Y"), "top": ("+X", "-Z"), "bottom": ("+X", "+Z"),
        "left": ("+Z", "+Y"), "right": ("-Z", "+Y")}
FACING = {"from-front": "Z", "from-back": "Z", "top": "Y", "bottom": "Y", "left": "X", "right": "X"}
VIEWER = {"from-front": "+Z", "from-back": "-Z", "top": "+Y", "bottom": "-Y", "left": "-X", "right": "+X"}
PIN_STYLE, PIN_HEIGHT = "Номер контакту малий", 1.8  # as make_parts.lsp numbers its parts
DIGIT, CLEAR = 1.26, 0.3  # a digit's width in that style, and the room kept between two numbers
# The parts that get pin numbers: (pattern of the part's name, with its pins per row as n and its
# rows, 1 or 2, as rows; pitch; the axis its contacts point along; the end of the rows pin 1 is at;
# the end of the contacts its wires leave from, for a header the end its mating housing's wires
# do; for two rows the side of the row with the odd pins, 1, 3, ..., beside 2, 4, ...), as model
# axes. Their rows are centred in the views, which number them across the contacts (on the side
# of the views away from the wires) and along them; a view looking along the rows shows one pin
# and has none. Pin 1 is after the maker's drawing in datasheets\ (git keeps them out) where there
# is one, matched to a feature the model shows; else at the left of the front view (спереду), or
# for two rows at its top left.
PIN_PARTS = [
    # ePH.pdf: No. 1 circuit at the right of the housing seen from the side with the contact
    # windows, this drawing's front; wires out of the top
    (r"^PHR-(?P<n>\d+)$", 2.0, "Y", "+X", "+Y", None),
    # ePH.pdf: No. 1 circuit at the right seen from the wall with the windows, posts down; that wall
    # is this drawing's top, posts to the left
    (r"^B(?P<n>\d+)B-PH-K-S$", 2.0, "X", "+Z", "+X", None),
    # ePH.pdf: PC board layout from above, leads away from the viewer: No. 1 circuit at the right;
    # here the mating face is the right view, leads down
    (r"^B(?P<n>\d+)B-PH-SM4-TB$", 2.0, "X", "+Z", "+X", None),
    # eEH.pdf shows no feature this model has: as B..B-PH-K-S, mating face at the right
    (r"^B(?P<n>\d+)B-EH-A$", 2.5, "X", "+Z", "+X", None),
    # eSH.pdf: PC board layout from above, leads towards the viewer: No. 1 circuit at the left; here
    # the front looks down on the mating face, leads up
    (r"^SH1\.0 90 Socket - BM(?P<n>\d+)B-SRSS", 1.0, "Z", "+X", "+Z", None),
    # eSH.pdf: the mating face with the board down, No. 1 circuit at the left: this drawing's bottom
    (r"^SH1\.0 Straight Socket - SM(?P<n>\d+)B-SRSS", 1.0, "Y", "-X", "-Y", None),
    # eSH.pdf: the mark of No. 1 circuit, a triangle on this drawing's bottom, at the left; the
    # contacts' barrels face the front, the mating face the back
    (r"^SH1\.0 (Tabbed )?Plug - SHR-(?P<n>\d+)V-S", 1.0, "Z", "-X", "+Z", None),
    # eGH.pdf: pin 1 at the right of the mating face with the lock up
    (r"^JST_GHR-(?P<n>\d+)V-S", 1.25, "Z", "+X", "+Z", None),
    # Molex PicoBlade, no drawing: the part number's 6th and 7th digits are the circuits. 53048,
    # mating face at the front; 53047, mating face at the bottom, leads up; 51021, the housing on
    # the wires, mating face at the top, wires down; 51047, the plug on the wires, mating face at
    # the bottom, wires up
    (r"^Molex 1\.25 Angle Socket - 53048(?P<n>\d\d)\d\d$", 1.25, "Z", "-X", "+Z", None),
    (r"^Molex PicoBlade 1\.25 PCB Straight Socket - 53047(?P<n>\d\d)\d\d$", 1.25, "Y", "-X", "-Y", None),
    (r"^Molex 1\.25 Plug - 51021(?P<n>\d\d)\d\d$", 1.25, "Y", "-X", "-Y", None),
    (r"^Molex 1\.25 Socket - 51047(?P<n>\d\d)\d\d$", 1.25, "Y", "-X", "+Y", None),
    # Pin headers, no drawing: straight, its long side to the back; angled, its straight pins up
    # and the front row bent least
    (r"^Pin Header (?P<rows>[12])x(?P<n>\d+) TH Pitch 2\.54mm$", 2.54, "Z", "-X", "-Z", "+Y"),
    (r"^(?P<rows>[12])x(?P<n>\d+) Male Pin Header Angle$", 2.54, "Y", "-X", "+Y", "+Z"),
    # BLD housings: their triangle marks pin 1, on the bottom at the back; the mating face, with
    # the funnels, at the left, the wires out of the right
    (r"^Leergehäuse, Kabel-Platine RM 2,54 mm - (?P<rows>[12]) x (?P<n>\d+)$", 2.54, "X", "-Z", "+X", "-Y"),
]


def pins(name, key, box):
    """A part's pin numbers in one view, [(x, y, "n")] from its base point (the centre of box,
    (x1, y1, x2, y2) from it), beside the view: across the contacts on its side away from the
    wires, numbering the row nearer the viewer; along them beside the row, for two rows each beside
    its own. Numbers too close for the pitch go out in a zig-zag of as many steps as they need."""
    rule = next((r for r in PIN_PARTS if re.search(r[0], name)), None)
    if not rule or key not in AXES:
        return []
    pattern, pitch, contact, end, wires, odd = rule
    m = re.search(pattern, name)
    n, rows = int(m["n"]), int(m.groupdict().get("rows") or 1)
    if FACING[key] == end[1]:  # looking along the rows
        return []
    ax, ay = AXES[key]
    along_x = ax[1] == end[1]
    run, across = (ax, ay) if along_x else (ay, ax)
    sign = 1 if run[0] == end[0] else -1
    lo, hi = (box[1], box[3]) if along_x else (box[0], box[2])

    def row(first):  # the numbers of a row, its column at pin 1's end first
        return [str(first + rows * i) for i in range(n)]

    if FACING[key] == contact:
        if rows == 1:
            sets = [(-1, row(1))]
        else:
            s = 1 if across[0] == odd[0] else -1
            sets = [(s, row(1)), (-s, row(2))]
    else:
        sets = [(-1 if across[0] == wires[0] else 1, row(1 if rows == 1 or VIEWER[key] == odd else 2))]
    if sum(len(t) for _, t in sets) < 2:
        return []
    out = []
    for s, texts in sets:
        w = max(len(t) for t in texts) * DIGIT
        size, first, step = (w, PIN_HEIGHT / 2 + 0.7, PIN_HEIGHT + 0.5) if along_x else (PIN_HEIGHT, w / 2 + 0.5, w + 0.5)
        k = math.ceil((size + CLEAR) / pitch)
        for i, t in enumerate(texts):
            u = round(sign * ((n - 1) / 2 - i) * pitch, 3)
            v = round((hi if s > 0 else lo) + s * (first + i % k * step), 3)
            out.append((u, v, t) if along_x else (v, u, t))
    return out


# ---- Arcs the wrong way round ----------------------------------------------------------------

def fix_arcs(ents, tol=0.005):
    """Turns round the arcs the library's drawings have the wrong way round, mostly in the views
    their maker mirrored: such an arc, more than half a circle where a fillet was meant, sets off
    from an end along a line that meets it there, over that line, where the arc meant (its start
    and end swapped) sets off away from it. How many."""
    ends = []  # (point, the way the line leaves it)
    for e in ents:
        if e.dxftype() == "LINE":
            ps = [(Vec2(e.dxf.start), Vec2(e.dxf.end))]
        elif e.dxftype() == "LWPOLYLINE":
            pts = [(Vec2(p[0], p[1]), p[2]) for p in e.get_points("xyb")]
            ps = [(a, b) for (a, bulge), (b, _) in zip(pts, pts[1:] + (pts[:1] if e.closed else [])) if not bulge]
        else:
            continue
        for a, b in ps:
            if a.distance(b) > tol:
                ends += [(a, (b - a).normalize()), (b, (a - b).normalize())]
    turned = 0
    for e in ents:
        if e.dxftype() != "ARC" or tuple(e.dxf.extrusion) != (0, 0, 1) or (e.dxf.end_angle - e.dxf.start_angle) % 360 <= 180:
            continue
        c, r = Vec2(e.dxf.center), e.dxf.radius
        s, t = math.radians(e.dxf.start_angle), math.radians(e.dxf.end_angle)
        # each end, and the way the arc leaves it
        arc_ends = [(c + Vec2(math.cos(s), math.sin(s)) * r, Vec2(-math.sin(s), math.cos(s))),
                    (c + Vec2(math.cos(t), math.sin(t)) * r, Vec2(math.sin(t), -math.cos(t)))]
        over = away = 0
        for p, d in arc_ends:
            for q, dq in ends:
                if p.distance(q) < tol:
                    dot = d.dot(dq)
                    over += dot > 0.98
                    away += dot < -0.98
        if over > away:
            e.dxf.start_angle, e.dxf.end_angle = e.dxf.end_angle, e.dxf.start_angle
            turned += 1
    return turned


# ---- Splitting a drawing into its views ------------------------------------------------------

def entities(doc):
    """The drawing's model space with every block reference exploded into what it shows."""
    out = []
    for e in doc.modelspace():
        if e.dxftype() == "INSERT":
            out += [v for v in e.virtual_entities() if v.dxftype() != "ATTRIB"]
        elif e.dxftype() not in ("TEXT", "MTEXT", "DIMENSION", "VIEWPORT"):
            out.append(e)
    return out


def groups(ents):
    """Entities whose boxes touch, as [[x1, y1, x2, y2], [entities]], each group one view."""
    items = []
    for e in ents:
        b = bbox.extents([e], fast=True)
        if b.has_data:
            items.append((e, [b.extmin.x, b.extmin.y, b.extmax.x, b.extmax.y]))
    if not items:
        return []
    size = max(max(b[2] for _, b in items) - min(b[0] for _, b in items), max(b[3] for _, b in items) - min(b[1] for _, b in items))
    tol = 0.002 * size

    def touch(a, b):
        return a[0] - tol <= b[2] and b[0] - tol <= a[2] and a[1] - tol <= b[3] and b[1] - tol <= a[3]

    out = []
    for e, b in sorted(items, key=lambda it: it[1][0]):
        box, members = list(b), [e]
        for g in [g for g in out if touch(g[0], box)]:
            box = [min(box[0], g[0][0]), min(box[1], g[0][1]), max(box[2], g[0][2]), max(box[3], g[0][3])]
            members += g[1]
            out.remove(g)
        out.append([box, members])
    merged = True
    while merged:  # a grown box may now touch one it did not
        merged = False
        for a in out:
            for g in out:
                if g is not a and touch(a[0], g[0]):
                    a[0] = [min(a[0][0], g[0][0]), min(a[0][1], g[0][1]), max(a[0][2], g[0][2]), max(a[0][3], g[0][3])]
                    a[1] += g[1]
                    out.remove(g)
                    merged = True
                    break
            if merged:
                break
    for g in out:  # the exact box, now that the groups are known
        b = bbox.extents(g[1])
        g[0] = [b.extmin.x, b.extmin.y, b.extmax.x, b.extmax.y]
    return out


def segments(ents, cx, cy, step):
    """The entities as segments in steps of `step` from (cx, cy), each once."""
    seen = set()
    for e in ents:
        try:
            pts = [(e.dxf.start, e.dxf.end)] if e.dxftype() == "LINE" else None
            if pts is None:
                vs = list(ezpath.make_path(e).flattening(step / 2))
                pts = list(zip(vs, vs[1:]))
        except Exception:
            continue
        for a, b in pts:
            s = (round((a.x - cx) / step), round((a.y - cy) / step), round((b.x - cx) / step), round((b.y - cy) / step))
            if s[:2] == s[2:]:
                continue
            if s[2:] < s[:2]:
                s = s[2:] + s[:2]
            seen.add(s)
    return sorted(seen)


def raster(segs, box, mirror, n=40):
    """Which of n×n cells over box the segments cross, the view turned over left to right if mirror."""
    cells = set()
    w, h = max(box[2] - box[0], 1e-9), max(box[3] - box[1], 1e-9)
    for x1, y1, x2, y2 in segs:
        k = max(2, int(math.hypot(x2 - x1, y2 - y1) * n / max(w, h)) + 2)
        for i in range(k + 1):
            x, y = x1 + (x2 - x1) * i / k, y1 + (y2 - y1) * i / k
            u = (x - box[0]) / w
            cells.add((min(n - 1, int((1 - u if mirror else u) * n)), min(n - 1, int((y - box[1]) / h * n))))
    return cells


def likeness(a, b):
    """How much view a, turned over, looks like view b, from 0 to 1."""
    ra = raster(a["raw"], a["box"], True)
    rb = raster(b["raw"], b["box"], False)
    return len(ra & rb) / max(1, len(ra | rb))


def classify(found):
    """({key: view}, how many groups were left over) for a drawing laid out as tools\\step-views draws
    it: three rows, the front in the middle one under the top view and over the bottom view, the left
    view left of it, the right and back views right of it, an isometric view in each corner. A view
    the drawing lacks is left out; raises when there is no such layout."""
    vs = [{"box": b, "ents": e} for b, e in found]
    for v in vs:
        b = v["box"]
        v["w"], v["h"], v["cx"], v["cy"] = b[2] - b[0], b[3] - b[1], (b[0] + b[2]) / 2, (b[1] + b[3]) / 2
        step = max(v["w"], v["h"], 1e-6) / 200
        v["raw"] = [tuple(c * step for c in s) for s in segments(v["ents"], 0, 0, step)]
    big = max(max(v["w"], v["h"]) for v in vs)
    stray = [v for v in vs if max(v["w"], v["h"]) < 0.02 * big]  # a speck beside the views
    vs = [v for v in vs if v not in stray]
    if len(vs) < 5:
        raise ValueError(f"{len(vs)} views")
    ys = sorted(vs, key=lambda v: -v["cy"])  # the rows: split at the two widest gaps between centres
    gaps = sorted(range(1, len(ys)), key=lambda i: ys[i - 1]["cy"] - ys[i]["cy"])[-2:]
    a, b = sorted(gaps)
    rows = [sorted(r, key=lambda v: v["cx"]) for r in (ys[:a], ys[a:b], ys[b:])]
    above, row, below = rows
    if len(row) < 2:
        raise ValueError("no row of views across the middle")
    def aligned(v, m):  # v projected from m: the same width at the same place
        tol = 0.02 * max(v["w"], m["w"])
        return abs(v["box"][0] - m["box"][0]) < tol and abs(v["box"][2] - m["box"][2]) < tol

    def under(v):  # the view of the middle row under or over v
        return min(row, key=lambda m: (not aligned(v, m), abs(m["cx"] - v["cx"])))

    def near(r, f):  # the view of row r over or under f
        return min(r, key=lambda v: (not aligned(v, f), abs(v["cx"] - f["cx"])), default=None)

    # the front: under the middle one of three views at the top (or at the bottom); a drawing may
    # have more, such as a second bottom view under the back
    if len(above) % 2:
        top = above[len(above) // 2]
        f = under(top)
        bottom = near(below, f)
    elif len(below) % 2:
        bottom = below[len(below) // 2]
        f = under(bottom)
        top = near(above, f)
    else:
        raise ValueError(f"{len(above)} views above and {len(below)} below the middle row")
    out = {"from-front": f}
    if top:
        out["top"] = top
    if bottom:
        out["bottom"] = bottom
    lefts = [v for v in row if v["cx"] < f["cx"]]
    left = max(lefts, key=lambda v: v["cx"]) if lefts else None
    if left:
        out["left"] = left
    others = sorted([v for v in row if v is not f and v is not left], key=lambda v: abs(v["cx"] - f["cx"]))[:2]

    def mirrors(x, y):
        return likeness(x, y) if x else 0.0

    # which is the back: it mirrors the front, the right mirrors the left
    if len(others) == 2:
        p, q = others
        back, right = (p, q) if mirrors(f, p) + mirrors(left, q) >= mirrors(f, q) + mirrors(left, p) else (q, p)
        out["from-back"], out["right"] = back, right
    elif others:
        out["from-back" if mirrors(f, others[0]) >= mirrors(left, others[0]) else "right"] = others[0]
    rest = [v for v in vs if all(v is not u for u in out.values())]
    for key, r, sx in (("iso-left-top", above, -1), ("iso-right-top", above, 1), ("iso-left-bottom", below, -1), ("iso-right-bottom", below, 1)):
        near = [v for v in rest if v in r and (v["cx"] - f["cx"]) * sx > 0]
        if near:  # not a view projected from one of the middle row
            v = min(near, key=lambda v: (any(aligned(v, m) for m in row), abs(v["cx"] - f["cx"])))
            out[key] = v
            rest.remove(v)
    return out, len(rest) + len(stray)


# ---- One part --------------------------------------------------------------------------------

def make(src, rel, name, pid):
    work = Path(tempfile.mkdtemp(prefix="part-", dir=WORK))
    try:
        shutil.copy(src, work / "in.dwg")
        console(work / "in.dwg", [f'_.DXFOUT "{(work / "in.dxf").as_posix()}" 16'], work)
        if not (work / "in.dxf").exists():
            return rel, None, "AutoCAD did not open it"
        doc = ezdxf.readfile(work / "in.dxf")
        ents = entities(doc)
        turned = fix_arcs(ents)
        views, stray = classify(groups(ents))
        part = ezdxf.new("R2013", setup=["linetypes"])
        part.header["$INSUNITS"] = 4
        part.styles.new(PIN_STYLE, dxfattribs={"font": "isocpeui.ttf"})
        lines = []
        for key, view in sorted(views.items(), key=lambda kv: list(VIEWS).index(kv[0])):
            b = view["box"]
            cx, cy = (b[0] + b[2]) / 2, (b[1] + b[3]) / 2
            blk = part.blocks.new(block_safe(name) + DASH + VIEWS[key], base_point=(0, 0))
            blk.block_record.dxf.units = 4
            for e in view["ents"]:
                c = e.copy()
                c.dxf.layer, c.dxf.color = "0", 0
                # a linetype the part's drawing has (hidden lines), by its name there, else the layer's
                lt = c.dxf.get("linetype", "BYLAYER").upper()
                c.dxf.linetype = next((l.dxf.name for l in part.linetypes if l.dxf.name.upper() == lt and lt != "CONTINUOUS"), "BYLAYER")
                c.dxf.discard("lineweight")
                c.dxf.discard("true_color")
                c.translate(-cx, -cy, 0)
                blk.add_entity(c)
            for x, y, text in pins(name, key, (b[0] - cx, b[1] - cy, b[2] - cx, b[3] - cy)):
                # a preset attribute, as make_parts.lsp makes them, which BPPART stands upright
                a = blk.add_attdef(f"PIN{text}", (x, y), text, dxfattribs={
                    "layer": "0", "color": 0, "height": PIN_HEIGHT, "style": PIN_STYLE, "flags": 8})
                a.set_placement((x, y), align=TextEntityAlignment.MIDDLE_CENTER)
            step = max(b[2] - b[0], b[3] - b[1], 1e-6) / PREVIEW
            segs = segments(view["ents"], cx, cy, step)
            lines.append(f"V \"{key}\" {step:.6g} {b[0] - cx:.2f} {b[1] - cy:.2f} {b[2] - cx:.2f} {b[3] - cy:.2f}")
            for i in range(0, len(segs), 200):
                lines.append("S " + " ".join(" ".join(map(str, s)) for s in segs[i:i + 200]))
        part.saveas(work / "part.dxf")
        console(work / "part.dxf", [f'_.SAVEAS 2018 "{(work / "part.dwg").as_posix()}"'], work)
        if not (work / "part.dwg").exists():
            return rel, None, "AutoCAD did not save the part"
        shutil.move(str(work / "part.dwg"), OUT / f"{pid}.dwg")
        (OUT / f"{pid}.txt").write_text("\n".join(lines) + "\n", encoding="ascii")
        note = f"{len(views)} views" + (f", {stray} left over" if stray else "") + (f", {turned} arcs turned round" if turned else "")
        return rel, sorted(views, key=list(VIEWS).index), note
    except Exception as e:
        return rel, None, f"{type(e).__name__}: {e}"
    finally:
        shutil.rmtree(work, ignore_errors=True)


# ---- The catalog -----------------------------------------------------------------------------

def lisp_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def write_catalog(index):
    rows = []
    for rel, (sha, pid, name) in sorted(index.items(), key=lambda kv: kv[1][2].lower()):
        txt = OUT / f"{pid}.txt"
        if not txt.exists():
            continue
        for line in txt.read_text(encoding="ascii").splitlines():
            if line.startswith("V "):
                _, key, _, *box = line.split()
                ps = pins(name, key.strip('"'), [float(v) for v in box])
                ps = "(" + " ".join(f"({x:g} {y:g} {lisp_str(t)})" for x, y, t in ps) + ")" if ps else "nil"
                rows.append(f"  ({lisp_str(name)} {key} {lisp_str('components\\' + pid)} ({' '.join(box)}) {lisp_str('components\\' + pid)} {ps})")
    CATALOG.write_text(
        ";;; ---- Components library -----------------------------------------------------\n"
        ";;; Made by tools\\components\\make_components.py from the drawings of the components library; run it\n"
        ";;; again instead of editing this. Every view of every part, in the form of 45-parts.lsp, with\n"
        ";;; the file of its outlines in place of them: src\\parts\\components\\<id>.txt, which BPPART reads\n"
        ";;; when it shows the part. The drawing src\\parts\\components\\<id>.dwg holds all of a part's views.\n\n"
        "(setq *bptools-parts* (append *bptools-parts* '(\n" + "\n".join(rows) + "\n  )))\n",
        encoding="utf-8", newline="\n")
    return len(rows)


def main():
    global CORE
    root = Path(sys.argv[1])
    opts = dict(a[2:].split("=", 1) if "=" in a else (a[2:], "1") for a in sys.argv[2:] if a.startswith("--"))
    CORE = opts.get("acad", CORE)
    OUT.mkdir(parents=True, exist_ok=True)
    WORK.mkdir(exist_ok=True)
    index = {}
    if (OUT / "index.tsv").exists():
        for line in (OUT / "index.tsv").read_text(encoding="utf-8").splitlines()[1:]:
            rel, sha, pid, name = line.split("\t")
            index[rel] = (sha, pid, name)
    sources = sorted(p for p in root.glob("*/dwg blueprints/**/*") if p.suffix.lower() == ".dwg")
    names, todo, keep = {}, [], {}
    for p in sources:
        rel = str(p.relative_to(root))
        sha = hashlib.sha1(p.read_bytes()).hexdigest()
        name = re.sub(r"\s+", " ", p.stem).strip()
        if name.lower() in names:  # the same name in two folders
            name = f"{name} ({p.parent.name})"
        names[name.lower()] = rel
        pid = part_id(rel)
        keep[rel] = (sha, pid, name)
        if index.get(rel, ("",))[0] != sha or not (OUT / f"{pid}.dwg").exists() or ("only" in opts and re.search(opts["only"], rel, re.I)):
            todo.append((p, rel, name, pid))
    print(f"{len(sources)} drawings, {len(todo)} to read", flush=True)
    failed = []
    with cf.ThreadPoolExecutor(int(opts.get("jobs", 6))) as pool:
        for rel, views, note in pool.map(lambda a: make(*a), todo):
            print(f"  {rel}: {note}", flush=True)
            if views is None:
                failed.append(rel)
    for rel in failed:  # a drawing that fails keeps the part made from it before, if any
        old = index.get(rel)
        if old and (OUT / f"{old[1]}.dwg").exists():
            keep[rel] = old
        else:
            keep.pop(rel)
    ids = {pid for _, pid, _ in keep.values()}
    for f in OUT.iterdir():  # a part whose drawing was removed or failed
        if f.suffix.lower() in (".dwg", ".txt") and f.stem not in ids:
            f.unlink()
    with open(OUT / "index.tsv", "w", encoding="utf-8", newline="\n") as f:
        f.write("drawing\tsha1\tid\tname\n")
        for rel, (sha, pid, name) in sorted(keep.items()):
            f.write(f"{rel}\t{sha}\t{pid}\t{name}\n")
    n = write_catalog(keep)
    print(f"\n{len(keep)} parts, {n} views in {CATALOG.name}; {len(failed)} drawings failed" + (": " + ", ".join(failed) if failed else ""))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
