# Levels

Every version of the two documents that come with the app, written ahead and checked.

Each paragraph exists at six levels of difficulty (see `AubeReader/Engine/Scale.swift`), each at every one of its document's lengths:

| Level | Grade | Written for |
|---|---|---|
| 0 | 2.0 | a seven-year-old |
| 1 | 4.5 | a ten-year-old |
| 2 | 7.0 | a twelve-year-old |
| 3 | 9.5 | an educated adult (where a paragraph starts) |
| 4 | 12.0 | a university student in the field |
| 5 | 14.5 | a specialist researcher |

Grade is the Flesch–Kincaid grade level, measured exactly as the app measures it (`measure.py`).

- `sources.json` holds each paragraph as it was given, which every version is written from, and each document's lengths in words.
- `generate.py` writes `AubeReader/Resources/content.json` (black holes) and `swarm.json` (honeybees). It needs an OpenAI key, read from `Local.xcconfig` or `OPENAI_API_KEY`.
- `check.py` checks those two files without any model, and with `--judge` has a model rank each set of six versions as well.

A version passes when:

- its word count is within its length's range;
- if it runs 30 words or more, it measures within one grade of its level's target;
- it measures at least one grade above the level below it (half a grade for versions of 15 to 29 words);
- a model, ranking the six versions of that length from easiest to hardest to understand, puts it above the level below it (in every one of three rankings when generating, and in most of three when checking).

Run `python3 -I tools/levels/check.py` after changing either file.
