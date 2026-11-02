"""Draws the 10 standard views of a STEP model, hidden lines removed, laid out as the library's DWGs:

    iso        top      iso
    left       front    right     back      (row 2's order can be changed, see --row)
    iso        bottom   iso

Scale 1:1, millimetres, everything on layer 0. A STEP that holds every size of a connector stacked
at one origin (JST SH «ALL», Molex PicoBlade) gives one drawing per size, named after it.

    step_views.py <model.step> <out folder> <name> [--front=-x] [--up=y] [--row=left,front,back,right] [--poly]

--front: the model axis that points at the viewer of the front view (default z, as SolidWorks);
--up: the axis that points up in it (default y); --poly: the faster polygonal hidden-line algorithm.
Writes <out folder>/NNN.dxf per drawing and prints a line "DXF <file>|<drawing name>" for each.
"""
import math
import re
import sys
import time
from pathlib import Path

import ezdxf
from ezdxf.math import ConstructionArc, Vec2
from OCP.BRep import BRep_Tool
from OCP.BRepAdaptor import BRepAdaptor_Curve
from OCP.BRepMesh import BRepMesh_IncrementalMesh
from OCP.GCPnts import GCPnts_QuasiUniformDeflection
from OCP.GeomAbs import GeomAbs_Circle, GeomAbs_Line
from OCP.gp import gp_Ax2, gp_Dir, gp_Pnt
from OCP.HLRAlgo import HLRAlgo_Projector
from OCP.HLRBRep import HLRBRep_Algo, HLRBRep_HLRToShape, HLRBRep_PolyAlgo, HLRBRep_PolyHLRToShape
from OCP.STEPCAFControl import STEPCAFControl_Reader
from OCP.TCollection import TCollection_ExtendedString
from OCP.TDataStd import TDataStd_Name
from OCP.TDF import TDF_ChildIterator, TDF_Label
from OCP.TDocStd import TDocStd_Document
from OCP.TopAbs import TopAbs_EDGE
from OCP.TopExp import TopExp_Explorer
from OCP.TopoDS import TopoDS, TopoDS_Compound
from OCP.BRep import BRep_Builder
from OCP.XCAFDoc import XCAFDoc_DocumentTool, XCAFDoc_ShapeTool

DEFLECTION = 0.005  # mm, for curves that are neither lines nor arcs
AXES = {"x": (1, 0, 0), "y": (0, 1, 0), "z": (0, 0, 1)}


def axis(s):
    v = AXES[s[-1].lower()]
    return tuple(-c for c in v) if s.startswith("-") else v


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def neg(a):
    return tuple(-c for c in a)


def views(front, up):
    """name: (direction to the viewer, drawing x axis), for a front view seen from `front` with `up` up."""
    right = cross(up, front)
    v = {
        "front": (front, right), "back": (neg(front), neg(right)),
        "top": (up, right), "bottom": (neg(up), right),
        "right": (right, neg(front)), "left": (neg(right), front),
    }
    for sx, sy, key in ((-1, 1, "iso-tl"), (1, 1, "iso-tr"), (-1, -1, "iso-bl"), (1, -1, "iso-br")):
        n = tuple(sx * r + sy * u + f for r, u, f in zip(right, up, front))
        v[key] = (n, cross(up, n))
    return v


def label_name(label):
    n = TDataStd_Name()
    return n.Get().ToExtString() if label.FindAttribute(TDataStd_Name.GetID_s(), n) else ""


def read_step(path):
    """[(variant name or None, shape)]: one per size for a stack of sizes, else the whole model."""
    doc = TDocStd_Document(TCollection_ExtendedString("doc"))
    reader = STEPCAFControl_Reader()
    reader.SetNameMode(True)
    if not reader.ReadFile(str(path)) or not reader.Transfer(doc):
        raise SystemExit(f"cannot read {path}")
    st = XCAFDoc_DocumentTool.ShapeTool_s(doc.Main())
    free = []
    it = TDF_ChildIterator(st.Label(), False)
    while it.More():
        if XCAFDoc_ShapeTool.IsFree_s(it.Value()):
            free.append(it.Value())
        it.Next()
    if len(free) == 1 and XCAFDoc_ShapeTool.IsAssembly_s(free[0]):
        comps = []
        c = TDF_ChildIterator(free[0], False)
        while c.More():
            ref = TDF_Label()
            XCAFDoc_ShapeTool.GetReferredShape_s(c.Value(), ref)
            comps.append((label_name(ref), XCAFDoc_ShapeTool.GetShape_s(c.Value())))
            c.Next()
        names = [n for n, _ in comps]
        # sizes of one connector: distinct names that differ only in their digits (SHR-02V-S, SHR-03V-S)
        if len(comps) >= 3 and len(set(names)) == len(names) and len({re.sub(r"\d", "", n) for n in names}) == 1:
            return [(re.sub(r"\s+v\d+$", "", n).strip(), s) for n, s in comps]
    builder, whole = BRep_Builder(), TopoDS_Compound()
    builder.MakeCompound(whole)
    for lab in free:
        builder.Add(whole, XCAFDoc_ShapeTool.GetShape_s(lab))
    return [(None, whole)]


def project(shape, n, x, poly):
    """The visible edges of shape seen from direction n, as edges in the drawing plane."""
    projector = HLRAlgo_Projector(gp_Ax2(gp_Pnt(0, 0, 0), gp_Dir(*n), gp_Dir(*x)))
    if poly:
        algo = HLRBRep_PolyAlgo(shape)
        algo.Projector(projector)
        algo.Update()
        out = HLRBRep_PolyHLRToShape()
        out.Update(algo)
    else:
        algo = HLRBRep_Algo()
        algo.Add(shape)
        algo.Projector(projector)
        algo.Update()
        algo.Hide()
        out = HLRBRep_HLRToShape(algo)
    # sharp edges and the outlines of curved faces; smooth (tangent) edges and seams are left out
    return [c for c in (out.VCompound(), out.OutLineVCompound()) if c is not None and not c.IsNull()]


def entities(compounds):
    """('line', p, q) / ('circle', c, r) / ('arc', c, r, a0, a1) / ('poly', pts) for every edge."""
    out = []
    for comp in compounds:
        exp = TopExp_Explorer(comp, TopAbs_EDGE)
        while exp.More():
            edge = TopoDS.Edge(exp.Current())
            exp.Next()
            if BRep_Tool.Degenerated_s(edge):
                continue
            c = BRepAdaptor_Curve(edge)
            u0, u1 = c.FirstParameter(), c.LastParameter()
            p0, p1 = c.Value(u0), c.Value(u1)
            a, b = Vec2(p0.X(), p0.Y()), Vec2(p1.X(), p1.Y())
            kind = c.GetType()
            if kind == GeomAbs_Line:
                if a.distance(b) > 1e-6:
                    out.append(("line", a, b))
            elif kind == GeomAbs_Circle and abs(c.Circle().Axis().Direction().Z()) > 0.999999:
                circ = c.Circle()
                ctr = Vec2(circ.Location().X(), circ.Location().Y())
                if abs(u1 - u0 - 2 * math.pi) < 1e-6:
                    out.append(("circle", ctr, circ.Radius()))
                elif a.distance(b) > 1e-6:
                    pm = c.Value((u0 + u1) / 2)
                    arc = ConstructionArc.from_3p(a, b, Vec2(pm.X(), pm.Y()))
                    out.append(("arc", Vec2(arc.center), arc.radius, arc.start_angle, arc.end_angle))
            else:
                d = GCPnts_QuasiUniformDeflection(c, DEFLECTION)
                pts = [Vec2(d.Value(i).X(), d.Value(i).Y()) for i in range(1, d.NbPoints() + 1)] if d.IsDone() else [a, b]
                if len(pts) >= 2:
                    out.append(("poly", pts))
    return out


def bbox(ents):
    xs, ys = [], []
    for e in ents:
        if e[0] == "line":
            xs += [e[1].x, e[2].x]; ys += [e[1].y, e[2].y]
        elif e[0] in ("circle", "arc"):
            xs += [e[1].x - e[2], e[1].x + e[2]]; ys += [e[1].y - e[2], e[1].y + e[2]]
        else:
            xs += [p.x for p in e[1]]; ys += [p.y for p in e[1]]
    return (min(xs), min(ys), max(xs), max(ys)) if xs else (0, 0, 0, 0)


def layout(drawn, grid):
    """Offsets for every view. The views of row 2 share the front view's centre line, top and
    bottom its x, so the orthographic views stay in projection with each other."""
    box = {k: bbox(v) for k, v in drawn.items()}
    w = {k: b[2] - b[0] for k, b in box.items()}
    h = {k: b[3] - b[1] for k, b in box.items()}
    gap = max(10.0, 0.6 * max(max(w.values()), max(h.values())))
    col_w = [max((w[r[i]] for r in grid if r[i]), default=0) for i in range(4)]
    row_h = [max(h[k] for k in r if k) for r in grid]
    col_x = [sum(col_w[:i]) + gap * i for i in range(4)]  # left edge of each column
    row_y = [-(sum(row_h[:i]) + gap * i) for i in range(3)]  # top edge of each row
    cy = row_y[1] - row_h[1] / 2  # centre line of row 2
    off = {}
    for r, row in enumerate(grid):
        for i, k in enumerate(row):
            if not k:
                continue
            dx = col_x[i] + (col_w[i] - w[k]) / 2 - box[k][0]
            dy = row_y[r] - (row_h[r] - h[k]) / 2 - box[k][3]
            if r == 1 and not k.startswith("iso"):
                dy = cy - (box[k][1] + box[k][3]) / 2
            off[k] = (dx, dy)
    # top and bottom straight above and below the front view
    for k in ("top", "bottom"):
        off[k] = (off["front"][0], off[k][1])
    return off


def write_dxf(drawn, grid, path):
    doc = ezdxf.new("R2013", setup=False)
    doc.header["$INSUNITS"] = 4  # mm
    msp = doc.modelspace()
    for k, (dx, dy) in layout(drawn, grid).items():
        o = Vec2(dx, dy)
        for e in drawn[k]:
            if e[0] == "line":
                msp.add_line(e[1] + o, e[2] + o)
            elif e[0] == "circle":
                msp.add_circle(e[1] + o, e[2])
            elif e[0] == "arc":
                msp.add_arc(e[1] + o, e[2], e[3], e[4])
            else:
                msp.add_lwpolyline([p + o for p in e[1]])
    doc.saveas(path)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    opts = dict(a[2:].split("=", 1) if "=" in a else (a[2:], "1") for a in sys.argv[1:] if a.startswith("--"))
    step, out, base = Path(args[0]), Path(args[1]), args[2]
    poly = "poly" in opts
    row = opts.get("row", "left,front,right,back").split(",")
    grid = [["iso-tl", "top", "iso-tr", None], row, ["iso-bl", "bottom", "iso-br", None]]
    vs = views(axis(opts.get("front", "z")), axis(opts.get("up", "y")))
    out.mkdir(parents=True, exist_ok=True)
    t = time.time()
    for i, (variant, shape) in enumerate(read_step(step)):
        if poly:
            BRepMesh_IncrementalMesh(shape, 0.01, False, 0.2, True)
        drawn = {k: entities(project(shape, n, x, poly)) for k, (n, x) in vs.items()}
        name = f"{base} - {variant}" if variant else base
        dxf = out / f"{i:03d}.dxf"
        write_dxf(drawn, grid, dxf)
        print(f"DXF {dxf}|{name}|{sum(map(len, drawn.values()))} entities|{time.time() - t:.1f}s", flush=True)


if __name__ == "__main__":
    main()
