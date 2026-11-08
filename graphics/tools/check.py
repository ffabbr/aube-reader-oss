#!/usr/bin/env python3
"""Render built graphics to PNG contact sheets with headless Chrome, to look at.

    python3 tools/check.py physics--pendulum physics--lever ...     # ids
    python3 tools/check.py --prefix physics-mech                    # all ids starting with this
Options:  --at 1.2 4 6.5     seconds into the 10 s cycle to capture (default 1.5 5 7)
          --dark             capture in dark mode too (extra sheet at the last time)
Writes .check/<name>-t<sec>[-dark].png and prints the paths. Read them with the Read tool.
"""
import argparse, os, subprocess, sys, html, re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CHROME = os.environ.get("CHROME", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ids", nargs="*")
    ap.add_argument("--prefix")
    ap.add_argument("--at", nargs="+", type=float, default=[1.5, 5, 7])
    ap.add_argument("--dark", action="store_true")
    ap.add_argument("--cols", type=int, default=3)
    ap.add_argument("--name")
    a = ap.parse_args()
    ids = [i.removesuffix(".svg") for i in a.ids]
    if a.prefix:
        ids += sorted(p.stem for p in (ROOT / "svg").glob(a.prefix + "*.svg"))
    ids = [i for i in dict.fromkeys(ids) if (ROOT / "svg" / f"{i}.svg").exists()]
    if not ids:
        sys.exit("nothing to render (build first: python3 tools/build.py)")
    name = a.name or (a.prefix or ids[0]).replace("--", "-")
    out = ROOT / ".check"
    out.mkdir(exist_ok=True)
    rows = -(-len(ids) // a.cols)
    def inline(n, i):
        svg = (ROOT / "svg" / f"{i}.svg").read_text()
        return re.sub(r"a-[a-z0-9-]+", lambda m: f"{m.group(0)}_{n}", svg)
    cells = "".join(
        f'<figure>{inline(n, i)}<figcaption>{html.escape(i)}</figcaption></figure>' for n, i in enumerate(ids))
    w = a.cols * 414 + 24
    h = rows * 275 + 30
    runs = [(t, False) for t in a.at] + ([(a.at[-1], True)] if a.dark else [])
    for t, dark in runs:
        bg, fg = ("#161513", "#999") if dark else ("#fffdfa", "#555")
        page = out / f"{name}-t{t:g}{'-dark' if dark else ''}.html"
        # Animations are paused and seeked to exactly t seconds, so every frame is deterministic.
        page.write_text(f"""<!doctype html><meta charset=utf-8><style>
body{{margin:0;padding:12px;display:grid;grid-template-columns:repeat({a.cols},400px);gap:14px;background:{bg};font:11px ui-monospace,monospace;color:{fg}}}
figure{{margin:0}} svg{{width:400px;height:240px;display:block;outline:1px solid #8883}} figcaption{{padding:3px 0}}
</style>{cells}<script>
addEventListener("load",()=>requestAnimationFrame(()=>{{document.getAnimations().forEach(x=>{{x.pause();x.currentTime={t * 1000}}})}}))
</script>""")
        png = page.with_suffix(".png")
        cmd = [CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", f"--window-size={w},{h}",
               "--virtual-time-budget=2500", f"--screenshot={png}", f"--blink-settings=preferredColorScheme={0 if dark else 1}",
               f"file://{page}"]
        subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=120)
        print(png)

if __name__ == "__main__":
    main()
