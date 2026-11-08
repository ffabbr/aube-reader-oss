# Levels

Every version of the four documents that come with the app, written ahead and checked.

Each paragraph exists at six levels of difficulty (see `AubeReader/Engine/Scale.swift`), each at every one of its document's lengths:

| Level | Grade | Written for |
|---|---|---|
| 0 | 2.0 | a seven-year-old |
| 1 | 4.5 | a ten-year-old |
| 2 | 7.0 | a twelve-year-old |
| 3 | 9.5 | an educated adult (where a paragraph starts) |
| 4 | 12.0 | a university student in the field |
| 5 | 14.5 | a specialist researcher |

Grade is the Flesch–Kincaid grade level, measured as the app measures it (`measure.py`, which agrees with `Scale.swift` for English).

- `sources.json` holds each paragraph as it was given, which every version is written from, each document's lengths in words, and the file it's written to. A mark like `[^4]` in a paragraph is a footnote (see `Manuscript.notes`), which every version keeps.
- `generate.py` writes `AubeReader/Resources/attention.json` (“Attention Is All You Need”, the paper itself, from its arXiv source) and `gw150914.json` (“Observation of Gravitational Waves from a Binary Black Hole Merger”, LIGO and Virgo’s paper in Phys. Rev. Lett. 116, 061102, published under CC BY 3.0), and `black-holes.json` and `swarm.json`, two reviews made up for the app. It needs an OpenAI key, read from `Local.xcconfig` or `OPENAI_API_KEY`.
- `check.py` checks those files without any model, and with `--judge` has a model rank each set of six versions as well.

A version passes when:

- its word count is within its length's range;
- it keeps each of the source's footnote marks once, and uses no formula the source doesn't;
- if it runs 30 words or more, it measures within one grade of its level's target;
- it measures at least one grade above the level below it (half a grade for versions of 15 to 29 words);
- a model, ranking the six versions of that length from easiest to hardest to understand, puts it above the level below it (in every one of three rankings when generating, and in most of three when checking).

Run `python3 -I tools/levels/check.py` after changing any of them.
