# Contributing

Issues and pull requests are welcome.

- No third-party dependencies.
- Match the surrounding style (two-space indentation). One main type to a
  file, named after it; a helper used in more than one folder goes in
  `Support/`.
- Run `xcodegen generate` after adding or moving files, and commit the project.
- Build without warnings and check light and dark, portrait and landscape.
- Never commit `Local.xcconfig`.

## Driving the app from a script

Debug builds can run a script of commands against the real app, for checking
an import or a change to the reader without tapping through it by hand. Write
one command to a line (`#` starts a comment) and launch with its path:

```sh
xcrun simctl launch booted <bundle id> -drive /path/to/script.txt
```

The app writes what happens to `script.txt.log`. For example:

```
open 0
look 1
contents
shot /tmp/contents.png
selftest
quit
```

The commands are in `Desk/DeskViewController+Drive.swift`: among them `import`
a file and wait until it's `ready` or `done`, `open` a document, `look` (0
plain, 1 paper, 2 journal), `scroll`, `shorter`/`longer`/`easier`/`harder`,
`topic x y`, `tapnote`, `contents`, `settings`, `style dark`, `orient
landscape`, `shot` a screenshot to a path, `selftest` to check how footnote
marks are handled, and `quit`. None of this is in a release build.

## The bundled documents

`tools/levels` writes and checks every version of the four documents that come
with the app. It needs Python 3 and, to write them, an OpenAI API key (see
`tools/levels/README.md`).
