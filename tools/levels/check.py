"""Checks the versions the app ships, without asking any model:

    python3 -I tools/levels/check.py [--judge]

For both built-in documents, every paragraph must have all six levels at every
one of its lengths; each version must land in its length's range and, where
it's long enough to measure, within a grade of its level's target; and every
level must measure clearly harder than the one below it. --judge also has a
model rank each length's six versions three times by how hard they are to
understand, and fails any two levels that most of the rankings put out of order. Exits non-zero if anything fails.
"""
import json, os, statistics, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import measure as m

HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.path.join(os.path.dirname(os.path.dirname(HERE)), "AubeReader", "Resources")
FILES = {"black-holes": "content.json", "swarm": "swarm.json"}


def main():
    judging = "--judge" in sys.argv
    if judging:
        from generate import judge
    specs = json.load(open(os.path.join(HERE, "sources.json")))
    failures = 0
    for doc, name in FILES.items():
        spec = specs[doc]
        data = json.load(open(os.path.join(RES, name)))
        P = data["paragraphs"]
        Z = len(spec["lengths"])
        print(f"\n{name}: {len(P)} paragraphs, {m.LEVELS} levels, {Z} lengths")
        if len(P) != len(spec["paragraphs"]):
            print(f"  FAIL: {len(P)} paragraphs, expected {len(spec['paragraphs'])}")
            failures += 1
        for p, levels in enumerate(P):
            if len(levels) != m.LEVELS or any(len(l) != Z for l in levels):
                print(f"  FAIL ¶{p}: shape {len(levels)}×{[len(l) for l in levels]}")
                failures += 1
                continue
            for z in range(Z):
                row = [levels[c][z] for c in range(m.LEVELS)]
                found = m.problems(row, spec["lengths"][z], spec["slack"][z])
                if judging and not any(found):
                    # One ranking can swap two close levels by chance; a pair fails when most rankings swap it.
                    votes = [c for k in range(3) for c in judge(row, hash((p, z, "check", k)))]
                    for c in sorted(set(votes)):
                        if votes.count(c) >= 2:
                            found[c].append(f"most readers ranked it easier than level {c - 1}")
                for c, f in enumerate(found):
                    for said in f:
                        print(f"  FAIL ¶{p} length {z} level {c}: {said}")
                        failures += 1
        # The ladder, on average: each length's grade at each level.
        print("  mean grade (rows: level; columns: length, longest first; '-' where too short to measure)")
        for c in range(m.LEVELS):
            cells = []
            for z in range(Z):
                gs = [m.grade(P[p][c][z]) for p in range(len(P)) if m.count(P[p][c][z]) >= m.GRADED_WORDS]
                cells.append(f"{statistics.mean(gs):5.1f}" if gs else "    -")
            print(f"    level {c} (target {m.target_grade(c):4.1f}): " + " ".join(cells))
    print(f"\n{'OK' if not failures else f'{failures} FAILURES'}")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
