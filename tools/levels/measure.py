"""The app's measures, as `Scale.swift` has them: words, and Flesch–Kincaid grade."""
import re

LEVELS = 6
GRADE_LOW = 2.0
GRADE_STEP = 2.5
# How far from its grade a version may measure, and the least it must climb from the level below.
GRADE_TOLERANCE = 1.0
GRADE_CLIMB = 1.0
# Below this many words grade isn't measured against a target; below SHORT, not at all.
GRADED_WORDS = 30
SHORT = 15

READERS = [
    "a seven-year-old",
    "a ten-year-old",
    "a twelve-year-old",
    "an educated adult reading the science pages of a newspaper",
    "a university student in the field",
    "a specialist researcher in the field",
]


def target_grade(level):
    return GRADE_LOW + GRADE_STEP * level


_note = re.compile(r"\[\^\d+\]")


def words(text):
    text = _note.sub("", text)
    return [w for w in re.split(r"[ \n\t]+", text) if re.search(r"[A-Za-z0-9]", w)]


def count(text):
    return len(words(text))


def _syllables(word):
    w = "".join(c for c in word.lower() if "a" <= c <= "z")
    if not w:
        return 0
    if len(w) <= 3:
        return 1
    w = re.sub(r"(?:[^laeiouy]es|ed|[^laeiouy]e)$", "", w)
    w = re.sub(r"^y", "", w)
    return max(1, len(re.findall(r"[aeiouy]{1,2}", w)))


def grade(text):
    text = _note.sub("", text)
    ws = words(text)
    if not ws:
        return 0.0
    sentences = max(1, len(re.findall(r"[.!?]+(\s|$)", text)))
    return 0.39 * len(ws) / sentences + 11.8 * sum(_syllables(w) for w in ws) / len(ws) - 15.59


def problems(row, lengths_z, slack_z):
    """What's wrong with one length's six versions, by level: a list of complaints for each."""
    out = [[] for _ in row]
    lo, hi = lengths_z - slack_z, lengths_z + slack_z
    for c, t in enumerate(row):
        n = count(t)
        if not lo <= n <= hi:
            out[c].append(f"it has {n} words; it needs between {lo} and {hi}")
        if n >= GRADED_WORDS:
            g, want = grade(t), target_grade(c)
            if abs(g - want) > GRADE_TOLERANCE:
                fix = "shorter sentences and simpler, shorter words" if g > want else "longer sentences and more precise, longer terms"
                out[c].append(f"it measures grade {g:.1f}; it needs grade {want - GRADE_TOLERANCE:.1f} to {want + GRADE_TOLERANCE:.1f} ({fix})")
        if c > 0 and t.strip() == row[c - 1].strip():
            out[c].append(f"it is word for word the same as level {c - 1}")
    for c in range(1, len(row)):
        a, b = row[c - 1], row[c]
        if min(count(a), count(b)) < SHORT:
            continue
        need = GRADE_CLIMB if min(count(a), count(b)) >= GRADED_WORDS else GRADE_CLIMB / 2
        ga, gb = grade(a), grade(b)
        if gb - ga < need:
            out[c].append(f"it measures grade {gb:.1f}, too close to level {c - 1} (grade {ga:.1f}); it must read clearly harder")
    return out
