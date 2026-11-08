# Graphics

Small animated line drawings, one per concept, used for topics and book covers.

- `src/` – source SVGs
- `svg/` – built files, bundled with the app
- `index.json` – manifest the app chooses drawings from
- `index.html` – open in a browser to see them all

## Adding a drawing

Name it `<discipline>--<concept>.svg` (e.g. `physics--pendulum.svg`) and put it in
`src/`. Use a 400×240 canvas, the classes `s q f` for lines, `p pq w` for fills and
`t` for labels, and shapes in the order they should draw. See existing files for
examples. Then build and check:

```sh
python3 tools/build.py src/physics--pendulum.svg   # validate and build
python3 tools/check.py --prefix physics--pend       # render previews to .check/
```

`check.py` uses headless Chrome; set `CHROME` if it isn't in `/Applications`.
