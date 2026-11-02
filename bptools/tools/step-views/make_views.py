"""Makes the 10-view DWG of every STEP model under <folder>\\3D model that has none yet in
<folder>\\dwg blueprints, with step_views.py, and saves it as DWG with the console AutoCAD. A DWG
already there, under the model's name or a size's, is never overwritten.

    make_views.py <folder> [--dry] [--only=<regex>] [--jobs=4] [--acad=<accoreconsole.exe>]

--dry lists what would be made; --only takes the models whose path under 3D model matches.
"""
import concurrent.futures as cf
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
PY = sys.executable
CORE = r"C:\Program Files\Autodesk\AutoCAD 2024\accoreconsole.exe"
TIMEOUT = 1800  # s per STEP file, for the exact hidden-line algorithm
WORK = Path(tempfile.gettempdir()) / "step-views"

# relative path of the STEP -> (folder in dwg blueprints, step_views options). Any other model goes
# into a folder named after its first folder, with the front view from +Z as SolidWorks.
FAMILIES = [
    # as the drawings of B2B..B5B already there: front from -X, back next to the front
    (r"^JST PH ALL\\", "jst ph", ["--front=-x", "--row=left,front,back,right"]),
    (r"^JST SH ALL\\", "jst sh", []),
    (r"^molex", "molex picoblade", []),
    (r"^pixhawk", "pixhawk power brick", []),
    (r"^(Гребенка[^\\]*)\\", None, []),
]


def family(rel):
    for pat, folder, opts in FAMILIES:
        m = re.match(pat, rel, re.I)
        if m:
            return folder or m.group(1), opts
    return rel.split("\\")[0].lower(), []


def to_dwg(dxf, dwg, work):
    """Saves dxf as an AutoCAD 2018 DWG through the console AutoCAD."""
    tmp = work / (dxf.stem + ".dwg")
    scr = work / (dxf.stem + ".scr")
    scr.write_text(f'(setvar "FILEDIA" 0)\n_.SAVEAS 2018 "{tmp.as_posix()}"\n_.QUIT\n', encoding="utf-8-sig")
    subprocess.run([CORE, "/i", str(dxf), "/s", str(scr), "/l", "en-US"], cwd=work, capture_output=True, timeout=300)
    if not tmp.exists():
        raise RuntimeError(f"AutoCAD did not save {dxf}")
    dwg.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(tmp), dwg)


def base_name(step):
    """The drawing's name, or the start of its sizes' names: the file's name without « ALL»."""
    return re.sub(r"\s+", " ", re.sub(r"\s+ALL$", "", step.stem, flags=re.I)).strip()


def make(step, rel, out_root, existing):
    folder, opts = family(rel)
    base = base_name(step)
    work = Path(tempfile.mkdtemp(prefix="views-", dir=WORK))
    results = []
    for mode in ([], ["--poly"]):
        try:
            p = subprocess.run([PY, str(HERE / "step_views.py"), str(step), str(work), base, *opts, *mode],
                               capture_output=True, text=True, encoding="utf-8", timeout=TIMEOUT)
            lines = [l[4:].split("|") for l in p.stdout.splitlines() if l.startswith("DXF ")]
            if p.returncode == 0 and lines:
                break
            err = (p.stderr or p.stdout).strip().splitlines()[-1:] or ["no output"]
            results.append((rel, "", "failed" + (" (poly)" if mode else ""), err[0]))
        except subprocess.TimeoutExpired:
            results.append((rel, "", "timed out" + (" (poly)" if mode else ""), f"{TIMEOUT}s"))
        lines = []
    for dxf, name, ents, secs in lines:
        dwg = out_root / folder / f"{name}.DWG"
        if name.lower() in existing or dwg.exists():
            results.append((rel, name, "skipped", "a DWG is already there"))
            continue
        try:
            to_dwg(Path(dxf), dwg, work)
            results.append((rel, name, "made" + (" (poly)" if mode else ""), f"{ents}, {secs}"))
        except Exception as e:
            results.append((rel, name, "failed", str(e)))
    shutil.rmtree(work, ignore_errors=True)
    return results


def main():
    global CORE
    root = Path(sys.argv[1])
    opts = dict(a[2:].split("=", 1) if "=" in a else (a[2:], "1") for a in sys.argv[2:] if a.startswith("--"))
    CORE = opts.get("acad", CORE)
    models, out_root = root / "3D model", root / "dwg blueprints"
    existing = {p.stem.lower() for p in out_root.rglob("*") if p.suffix.lower() == ".dwg"}
    steps = sorted(p for p in models.rglob("*") if p.suffix.lower() in (".stp", ".step"))
    todo = []
    for s in steps:
        rel = str(s.relative_to(models))
        sizes = base_name(s).lower() + " - "
        drawn = s.stem.lower() in existing or any(e.startswith(sizes) for e in existing)
        if drawn or ("only" in opts and not re.search(opts["only"], rel, re.I)):
            continue
        todo.append((s, rel))
    print(f"{len(steps)} STEP models, {len(todo)} without a DWG", flush=True)
    if "dry" in opts:
        for s, rel in todo:
            print(f"  {rel}  ->  {family(rel)[0]}")
        return
    WORK.mkdir(exist_ok=True)
    t = time.time()
    report = []
    with cf.ThreadPoolExecutor(int(opts.get("jobs", 4))) as pool:
        futs = {pool.submit(make, s, rel, out_root, existing): rel for s, rel in todo}
        for f in cf.as_completed(futs):
            try:
                rows = f.result()
            except Exception as e:
                rows = [(futs[f], "", "failed", str(e))]
            for r in rows:
                print(" | ".join(r), flush=True)
            report += rows
    with open(WORK / "report.tsv", "w", encoding="utf-8-sig") as f:
        f.write("model\tdrawing\tresult\tdetail\n")
        for r in sorted(report):
            f.write("\t".join(r) + "\n")
    made = sum(r[2].startswith("made") for r in report)
    print(f"\n{made} drawings made, {sum(not r[2].startswith(('made', 'skipped')) for r in report)} problems, "
          f"{(time.time() - t) / 60:.1f} min. Report: {WORK / 'report.tsv'}")


if __name__ == "__main__":
    main()
