#!/usr/bin/env python3
"""Build the graphics library.

    python3 tools/build.py                 # build + validate everything in src/
    python3 tools/build.py src/a.svg ...   # validate/build just these (no index rewrite)

src/<id>.svg  is what an author writes: the marks, plus an optional <style>
              for ambient motion. svg/<id>.svg is the finished, standalone file:
              the house style and the draw-on animation are baked in.
Also writes index.json and index.js (the manifest the grid page reads).
"""
import json, re, sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
NS = "http://www.w3.org/2000/svg"
ET.register_namespace("", NS)
Q = lambda t: f"{{{NS}}}{t}"

VIEWBOX = "0 0 400 240"
DISCIPLINES = {
    "physics", "astronomy", "chemistry", "biology", "neuroscience", "medicine", "earth",
    "climate", "math", "computing", "engineering", "energy", "materials", "optics", "acoustics",
    "statistics", "economics", "psychology", "linguistics", "history", "method", "ecology",
    "genetics", "evolution", "geometry", "networks", "society", "technology",
}
STROKE = {"s", "q", "f"}            # pen lines: drawn on
FILL = {"p", "w", "pq", "t", "k"}   # fills, text, dashed lines: faded in
MODS = {"hair", "bold", "i"}        # width modifiers
ALLOWED = STROKE | FILL | MODS
TAGS = {"path", "line", "circle", "ellipse", "rect", "polyline", "polygon", "text", "g"}
ID_RE = re.compile(r"^[a-z]+--[a-z0-9]+(-[a-z0-9]+)*$")
CYCLE = 10          # seconds; ambient animations must divide it
BUCKETS = 16

def base_css() -> str:
    c = []
    c.append(""":root{--ink:#110f0c;--quiet:#555350;--faint:#b8b6b2;--wash:#f5f3ef}
@media (prefers-color-scheme:dark){:root{--ink:#e7e5e2;--quiet:#a3a19e;--faint:#524f4c;--wash:#252321}}
svg{overflow:visible}
.s,.q,.f{fill:none;stroke-linecap:round;stroke-linejoin:round;stroke-dasharray:1;stroke-dashoffset:0}
.s{stroke:var(--ink);stroke-width:1.5}
.q{stroke:var(--quiet);stroke-width:1.3}
.f{stroke:var(--faint);stroke-width:1.1}
.hair{stroke-width:1!important}
.bold{stroke-width:2.2!important}
.k{fill:none;stroke-dasharray:5 5!important;stroke-linecap:round}
.p{fill:var(--ink);stroke:none}
.pq{fill:var(--quiet);stroke:none}
.w{fill:var(--wash);stroke:none}
.t{fill:var(--quiet);stroke:none;font:italic 13px ui-serif,"New York",Georgia,serif}
.all{animation:out %ds linear infinite}
@keyframes out{0%%,90%%{opacity:1}97%%,99.9%%{opacity:0}100%%{opacity:1}}""" % CYCLE)
    step, dur = 2.2, 9
    for b in range(BUCKETS):
        s = round(b * step, 2)
        c.append(f"@keyframes dr{b}{{0%,{s}%{{stroke-dashoffset:1;opacity:0}}{s+.1:g}%{{stroke-dashoffset:1;opacity:1}}"
                 f"{s+dur:g}%,100%{{stroke-dashoffset:0;opacity:1}}}}")
        c.append(f"@keyframes fd{b}{{0%,{s}%{{opacity:0}}{s+7:g}%,100%{{opacity:1}}}}")
    for b in range(BUCKETS):
        c.append(f".s.i{b},.q.i{b},.f.i{b}{{animation:dr{b} {CYCLE}s cubic-bezier(.55,.05,.25,1) infinite}}")
    for b in range(BUCKETS):
        c.append(f".p.i{b},.w.i{b},.pq.i{b},.t.i{b},.k.i{b}{{animation:fd{b} {CYCLE}s cubic-bezier(.2,.7,.3,1) infinite}}")
    c.append("@media (prefers-reduced-motion:reduce){*{animation:none!important}}")
    return "\n".join(c)

def local(tag):  # strip namespace
    return tag.split("}")[-1]

def classes(el):
    return (el.get("class") or "").split()

def problems(tree, path: Path) -> list[str]:
    errs, root = [], tree.getroot()
    pid = path.stem
    if not ID_RE.match(pid):
        errs.append(f"file name '{pid}' must look like discipline--concept-name (lowercase, kebab)")
    if root.get("viewBox") != VIEWBOX:
        errs.append(f"viewBox must be '{VIEWBOX}'")
    if root.get("data-id") != pid:
        errs.append(f"data-id must equal the file name '{pid}'")
    disc = root.get("data-discipline", "")
    if disc not in DISCIPLINES or not pid.startswith(disc + "--"):
        errs.append(f"data-discipline '{disc}' must be one of the known disciplines and prefix the id")
    tags = [t for t in (root.get("data-tags") or "").split(",") if t.strip()]
    if not 3 <= len(tags) <= 8:
        errs.append("data-tags needs 3-8 comma-separated keywords")
    title, desc = root.find(Q("title")), root.find(Q("desc"))
    if title is None or not (title.text or "").strip():
        errs.append("missing <title>")
    if desc is None or not 40 <= len((desc.text or "").strip()) <= 220:
        errs.append("<desc> must be 40-220 chars: what the graphic shows and which idea it stands for")
    n_draw = n_text = 0
    for el in root.iter():
        t = local(el.tag)
        if el is root or t in {"title", "desc", "style"}:
            continue
        if t not in TAGS:
            errs.append(f"<{t}> is not allowed (use {sorted(TAGS)})")
            continue
        for a in el.attrib:
            if a in {"fill", "stroke", "style", "pathLength", "opacity", "fill-opacity", "stroke-opacity", "stroke-width", "stroke-dasharray"} or a.endswith("href"):
                errs.append(f"<{t}> has attribute '{a}': colour, weight and dashes come from classes, not attributes")
        cl = classes(el)
        for c in cl:
            if c not in ALLOWED and not re.fullmatch(r"a-[a-z0-9-]+", c):
                errs.append(f"unknown class '{c}' on <{t}> (ambient motion classes must start with 'a-')")
        kinds = [c for c in cl if c in STROKE | FILL]
        if t == "g":
            if kinds:
                errs.append("classes s/q/f/p/w/pq/t/k go on shapes, not <g>; put a-… motion classes on <g>")
            continue
        n_draw += 1
        if t == "text":
            n_text += 1
            if "t" not in kinds:
                errs.append("<text> needs class 't'")
        if not kinds:
            errs.append(f"<{t}> has no drawing class (s q f p w pq t k)")
        if set(kinds) & STROKE and set(kinds) & {"p", "w", "pq"}:
            errs.append(f"<{t}> mixes a stroke class and a fill class; draw the outline and the fill as two shapes")
        if "k" in kinds and not (set(kinds) & STROKE):
            errs.append("class 'k' (dashed) needs a colour class too: 'k s', 'k q' or 'k f'")
        if "k" in kinds and set(kinds) & STROKE:
            pass
    if n_draw > 90:
        errs.append(f"{n_draw} shapes: too busy (max 90)")
    if n_draw < 4:
        errs.append("too sparse (min 4 shapes)")
    if n_text > 3:
        errs.append("at most 3 text labels")
    st = root.find(Q("style"))
    if st is not None:
        css = st.text or ""
        for m in re.finditer(r"animation(?:-duration)?\s*:[^;}]*", css):
            for d in re.findall(r"(?<![\d.])(\d*\.?\d+)s\b", m.group(0)):
                if float(d) not in {1.0, 2.0, 2.5, 5.0, 10.0}:
                    errs.append(f"ambient animation duration {d}s: use 1, 2, 2.5, 5 or 10 s so the loop closes with the {CYCLE}s cycle")
        for k in re.findall(r"@keyframes\s+([\w-]+)", css):
            if not k.startswith("a-"):
                errs.append(f"@keyframes '{k}' must start with 'a-'")
        if "@import" in css or "url(" in css:
            errs.append("no @import / url() in style")
        if re.search(r"#[0-9a-fA-F]{3,8}\b|rgb\(|hsl\(", css):
            errs.append("no literal colours in <style>; use var(--ink), var(--quiet), var(--faint), var(--wash)")
    return errs

def build_one(src: Path):
    tree = ET.parse(src)
    errs = problems(tree, src)
    if errs:
        return None, errs
    root = tree.getroot()
    meta = {"id": src.stem, "discipline": root.get("data-discipline"),
            "title": root.find(Q("title")).text.strip(), "description": root.find(Q("desc")).text.strip(),
            "tags": [t.strip() for t in root.get("data-tags").split(",") if t.strip()]}
    # number the drawn shapes in document order, spreading them over 16 buckets
    shapes = [e for e in root.iter() if local(e.tag) not in {"svg", "g", "title", "desc", "style"}]
    n = len(shapes)
    for k, el in enumerate(shapes):
        cl = classes(el)
        if not any(re.fullmatch(r"i\d+", c) for c in cl):
            cl.append(f"i{min(k, k * BUCKETS // n, BUCKETS - 1)}")
        el.set("class", " ".join(cl))
        if set(cl) & STROKE and "k" not in cl:
            el.set("pathLength", "1")
    # wrap the drawing so the whole figure can fade out and begin again
    keep = [c for c in root if local(c.tag) in {"title", "desc", "style"}]
    body = [c for c in root if c not in keep]
    for c in body:
        root.remove(c)
    g = ET.Element(Q("g"), {"class": "all"})
    g.extend(body)
    base = ET.Element(Q("style"))
    base.text = "\n" + base_css() + "\n"
    for c in list(root):
        root.remove(c)
    order = [c for c in keep if local(c.tag) in {"title", "desc"}] + [base] + [c for c in keep if local(c.tag) == "style"] + [g]
    root.extend(order)
    for a in ("width", "height"):
        root.attrib.pop(a, None)
    root.set("role", "img")
    out = ROOT / "svg" / f"{src.stem}.svg"
    ET.indent(tree, space=" ")
    tree.write(out, encoding="utf-8", xml_declaration=False)
    return meta, []

def main(argv):
    files = [Path(a) for a in argv] or sorted((ROOT / "src").glob("*.svg"))
    ok, bad = [], 0
    for f in files:
        meta, errs = build_one(f)
        if errs:
            bad += 1
            print(f"✗ {f.name}")
            for e in errs:
                print(f"    - {e}")
        else:
            ok.append(meta)
    if not argv:
        ok.sort(key=lambda m: (m["discipline"], m["id"]))
        (ROOT / "index.json").write_text(json.dumps(ok, indent=1, ensure_ascii=False))
        (ROOT / "index.js").write_text("window.GRAPHICS = " + json.dumps(ok, ensure_ascii=False) + ";\n")
        print(f"{len(ok)} graphics built, {bad} failed → index.json, index.js")
    else:
        print(f"{len(ok)} ok, {bad} failed")
    return 1 if bad else 0

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
