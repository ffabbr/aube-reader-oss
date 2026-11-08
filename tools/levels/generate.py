"""Writes every version of the app's two built-in documents: six levels of
difficulty at each of a document's lengths, for every paragraph, and checks
each against the measures in `measure.py` and a reader's ranking.

    python3 -I tools/levels/generate.py black-holes swarm --work /some/dir

The middle length is written first, all six levels in one go, from the source
paragraph in `sources.json`; each other length is written from the one beside
it nearer the middle, level by level. Any version that misses its length, its
grade, or its place in the ladder is written again with what was wrong, up to
`ROUNDS` times. Progress is kept in --work, so a run that stops can carry on.
"""
import argparse, concurrent.futures as cf, json, os, random, sys, threading

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import llm, measure as m

HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.path.join(llm.ROOT, "AubeReader", "Resources")
ROUNDS = 6
JUDGE_SHUFFLES = 3
lock = threading.Lock()


def log(*a):
    with lock:
        print(*a, flush=True)


SYSTEM = f"""You write the versions of a paragraph for an adaptive reader. Readers swipe a paragraph easier or harder, \
one level at a time, and pinch it shorter or longer. Every swipe must make a clear, noticeable difference, and the \
levels must climb steadily from the first to the last.

There are {m.LEVELS} levels. Difficulty is measured as the Flesch–Kincaid grade: 0.39 × (words per sentence) + \
11.8 × (syllables per word) − 15.59.
{chr(10).join(f"- Level {c}: grade {m.target_grade(c):.1f}, for {m.READERS[c]}." for c in range(m.LEVELS))}

What changes from level to level is more than sentence length:
- Lower levels use short sentences and everyday words, explain or leave out anything a young reader wouldn't know, \
and use comparisons from daily life. No jargon; no formulas below level 3.
- Middle levels use the field's main terms, each made clear by context.
- Higher levels use long, dense sentences and the field's precise vocabulary, assume the background a student or \
researcher has, and give exact quantities, mechanisms and qualifications.

Rules:
- Stay faithful to the source: same subject, same claims, nothing that contradicts it. Anything added must be \
accurate and well established.
- Each version is one paragraph of plain prose: no title, quotes, lists, markdown or commentary.
- Formulas are TeX between dollar signs. Keep any you use exactly as in the source; never put dollar signs around \
anything else.
- Length is counted in whitespace-separated words, and every version must land in the range it is given.
- When a version is too short to hold everything, keep the paragraph's main point, the one its first sentences \
make, and let the details go. Every level of the same length says the same thing; only how it's said changes."""


def context(spec, p):
    ps = spec["paragraphs"]
    lines = [f'Document: "{spec["title"]}" ({spec["field"]}). Paragraph {p + 1} of {len(ps)}.']
    if p > 0:
        lines.append(f'Previous paragraph, for context only: "{ps[p - 1]}"')
    if p + 1 < len(ps):
        lines.append(f'Next paragraph, for context only: "{ps[p + 1]}"')
    lines.append(f'SOURCE: "{ps[p]}"')
    return lines


def rng(spec, z):
    L, s = spec["lengths"][z], spec["slack"][z]
    return L - s, L + s


ROW = {"type": "object", "properties": {"versions": {"type": "array", "items": {"type": "string"}}},
       "required": ["versions"], "additionalProperties": False}
ONE = {"type": "object", "properties": {"text": {"type": "string"}}, "required": ["text"], "additionalProperties": False}


def targets(spec, z):
    lo, hi = rng(spec, z)
    short = spec["lengths"][z] < m.GRADED_WORDS
    return "\n".join(
        f"- Level {c} ({m.READERS[c]}): {lo}–{hi} words"
        + ("" if short else f", grade {m.target_grade(c) - m.GRADE_TOLERANCE:.1f}–{m.target_grade(c) + m.GRADE_TOLERANCE:.1f}")
        for c in range(m.LEVELS))


def first_row(spec, p, z):
    lines = context(spec, p) + [
        f"Write all {m.LEVELS} levels of this paragraph, from level 0 to level {m.LEVELS - 1}:",
        targets(spec, z),
        "Return them in order as `versions`."]
    out = llm.chat([{"role": "system", "content": SYSTEM}, {"role": "user", "content": "\n\n".join(lines)}], ROW, effort="medium")
    return fit(out["versions"])


def next_row(spec, p, z, beside, zb):
    lo, hi = rng(spec, z)
    how = ("shorter: mainly delete words, phrases and whole sentences, keeping the most important ideas"
           if spec["lengths"][z] < spec["lengths"][zb] else
           "longer: keep every sentence and add clauses and sentences with more detail on the same point")
    lines = context(spec, p) + [
        "These are the paragraph's six levels at another length:",
        "\n".join(f"- Level {c} ({m.count(t)} words, grade {m.grade(t):.1f}): \"{t}\"" for c, t in enumerate(beside)),
        f"Make each one {how}, so that it runs {lo}–{hi} words, and keep each at its own level:",
        targets(spec, z),
        "Return all six in order as `versions`."]
    out = llm.chat([{"role": "system", "content": SYSTEM}, {"role": "user", "content": "\n\n".join(lines)}], ROW, effort="medium")
    return fit(out["versions"])


def fit(vs):
    vs = [v.strip() for v in vs][: m.LEVELS]
    return vs + [vs[-1] if vs else ""] * (m.LEVELS - len(vs))


def repair(spec, p, z, row, c, said, beside):
    lo, hi = rng(spec, z)
    lines = context(spec, p) + [
        "The paragraph's levels at this length, as they stand:",
        "\n".join(f"- Level {k} ({m.count(t)} words, grade {m.grade(t):.1f}): \"{t}\"" for k, t in enumerate(row))]
    if beside:
        lines.append(f'Level {c} at the neighbouring length: "{beside[c]}"')
    want = f"{lo}–{hi} words" + ("" if spec["lengths"][z] < m.GRADED_WORDS else f", grade {m.target_grade(c) - m.GRADE_TOLERANCE:.1f}–{m.target_grade(c) + m.GRADE_TOLERANCE:.1f}")
    lines += [f"Rewrite level {c} ({m.READERS[c]}). What's wrong: " + "; and ".join(said) + ".",
              f"It must read clearly harder than level {c - 1} and clearly easier than level {c + 1}, where those exist. Target: {want}. "
              "Return it as `text`."]
    out = llm.chat([{"role": "system", "content": SYSTEM}, {"role": "user", "content": "\n\n".join(lines)}], ONE, effort="medium")
    return out["text"].strip()


RANK = {"type": "object", "properties": {"order": {"type": "array", "items": {"type": "string"}}}, "required": ["order"], "additionalProperties": False}


def judge(row, seed):
    """Where a reader, ranking the six from easiest to hardest to understand, puts them out of order."""
    labels = list("ABCDEF")[: len(row)]
    order = list(range(len(row)))
    random.Random(seed).shuffle(order)
    shown = "\n\n".join(f"{labels[i]}: \"{row[c]}\"" for i, c in enumerate(order))
    out = llm.chat([
        {"role": "system", "content": "You judge how hard texts are for a general reader to understand: vocabulary, sentence "
                                      "structure, assumed background knowledge and density of ideas, not length."},
        {"role": "user", "content": f"Rank these versions of one paragraph from easiest to hardest to understand. Return every "
                                    f"label once, easiest first, as `order`.\n\n{shown}"}], RANK, effort="low")
    pos = {}
    for rank, lab in enumerate(out["order"]):
        if lab in labels:
            pos[order[labels.index(lab)]] = rank
    bad = []
    for c in range(1, len(row)):
        if c in pos and c - 1 in pos and pos[c] < pos[c - 1]:
            bad.append(c)
    return bad


def check(spec, z, row, p, rnd):
    found = m.problems(row, spec["lengths"][z], spec["slack"][z])
    if not any(found):
        for k in range(JUDGE_SHUFFLES):
            for c in judge(row, hash((p, z, rnd, k))):
                said = f"a reader ranked it easier than level {c - 1}'s version; make it clearly more demanding"
                if said not in found[c]:
                    found[c].append(said)
    return found


def build(spec, doc, p, work):
    path = os.path.join(work, f"{doc}-{p}.json")
    grid = json.load(open(path)) if os.path.exists(path) else {}
    home = spec["home"]
    Z = len(spec["lengths"])
    order = [home] + list(range(home - 1, -1, -1)) + list(range(home + 1, Z))
    for z in order:
        if str(z) in grid and grid[str(z)]["ok"]:
            continue
        zb = None if z == home else (z + 1 if z < home else z - 1)
        beside = None if zb is None else grid[str(zb)]["row"]
        row = first_row(spec, p, z) if beside is None else next_row(spec, p, z, beside, zb)
        found = check(spec, z, row, p, 0)
        for rnd in range(1, ROUNDS + 1):
            if not any(found):
                break
            for c in [c for c in range(m.LEVELS) if found[c]]:
                row[c] = repair(spec, p, z, row, c, found[c], beside)
            found = check(spec, z, row, p, rnd)
        left = [f"L{c}: " + "; ".join(f) for c, f in enumerate(found) if f]
        grid[str(z)] = {"row": row, "ok": not left, "left": left}
        json.dump(grid, open(path, "w"), indent=1, ensure_ascii=False)
        log(f"{doc} ¶{p} length {z}: " + ("ok" if not left else "STILL WRONG: " + " | ".join(left)))
    return grid


def write(doc, spec, grids):
    Z = len(spec["lengths"])
    paragraphs = [[[grids[p][str(z)]["row"][c] for z in range(Z)] for c in range(m.LEVELS)] for p in range(len(spec["paragraphs"]))]
    if doc == "black-holes":
        out = {"paragraphs": paragraphs, "defaultDifficulty": 3, "defaultZoom": spec["home"], "core": spec["core"]}
        name = "content.json"
    else:
        out = {"title": spec["title"], "authors": spec["authors"], "field": spec["field"], "paragraphs": paragraphs,
               "defaultDifficulty": 3, "defaultZoom": spec["home"]}
        name = "swarm.json"
    with open(os.path.join(RES, name), "w") as f:
        json.dump(out, f, indent=2, ensure_ascii=False)
        f.write("\n")
    log(f"wrote {name}")


def main():
    a = argparse.ArgumentParser()
    a.add_argument("docs", nargs="+")
    a.add_argument("--work", required=True)
    a.add_argument("--only", type=int, nargs="*", help="paragraph indices, for a trial run (nothing is written)")
    a.add_argument("--threads", type=int, default=8)
    args = a.parse_args()
    os.makedirs(args.work, exist_ok=True)
    specs = json.load(open(os.path.join(HERE, "sources.json")))
    jobs = [(d, p) for d in args.docs for p in range(len(specs[d]["paragraphs"])) if args.only is None or p in args.only]
    grids = {}
    with cf.ThreadPoolExecutor(args.threads) as ex:
        futs = {ex.submit(build, specs[d], d, p, args.work): (d, p) for d, p in jobs}
        for f in cf.as_completed(futs):
            grids[futs[f]] = f.result()
    if args.only is None:
        for d in args.docs:
            write(d, specs[d], [grids[(d, p)] for p in range(len(specs[d]["paragraphs"]))])
    bad = [(d, p, z) for (d, p), g in grids.items() for z, r in g.items() if not r["ok"]]
    log(f"done; {len(bad)} rows still wrong" + (": " + ", ".join(f"{d} ¶{p} length {z}" for d, p, z in bad) if bad else ""))


if __name__ == "__main__":
    main()
