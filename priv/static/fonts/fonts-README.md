# Self-hosted fonts

All font files in this directory are licensed under the **SIL Open Font License 1.1**
(OFL-1.1). The full license text is in [`OFL.txt`](./OFL.txt) in this directory.
Fonts are served same-origin from `/fonts/...` by `Plug.Static`
(`HiraethWeb.static_paths/0` already declares `fonts`); no remote font hosts are
referenced anywhere in the codebase.

Consumed by `assets/css/app.css` via `@font-face` rules and the
`--sb-serif` / `--sb-sans` CSS tokens.

All files below were downloaded on 2026-08-05 from npm registry tarballs
(registry.npmjs.org) published by the Fontsource project; each package's
`package.json` declares `"license": "OFL-1.1"` and each tarball ships the full
OFL 1.1 text with the family's copyright header.

## Newsreader (serif — `--sb-serif`)

- Font version: 1.003 (variable font, `wght` axis 200–800, normal + italic)
- Copyright: Copyright 2020 The Newsreader Project Authors
  (http://github.com/productiontype/Newsreader)
- License: SIL Open Font License 1.1
- Source: npm package `fontsource-variable/newsreader` v5.3.0 (Fontsource scope,
  registry.npmjs.org, license field OFL-1.1)
- Upstream: https://fonts.google.com/specimen/Newsreader
- Files:
  - `newsreader-variable-normal.woff2` (`newsreader-latin-wght-normal.woff2`, latin subset)
  - `newsreader-variable-italic.woff2` (`newsreader-latin-wght-italic.woff2`, latin subset)

## Archivo (UI sans — `--sb-sans`)

- Font version: variable, `wght` axis 400–700, normal
- Copyright: Copyright 2020 The Archivo Project Authors
  (https://github.com/Omnibus-Type/Archivo)
- License: SIL Open Font License 1.1
- Source: embedded Fontsource `Archivo` (latin subset) in the Hiraeth design
  prototype (`design/home.html`); extracted byte-for-byte into
  `archivo-variable-normal.woff2` and verified `wOF2` on placement.
- Upstream: https://fonts.google.com/specimen/Archivo
- Files:
  - `archivo-variable-normal.woff2` (latin subset)

## Provenance notes

- Every `.woff2` was verified to start with the `wOF2` magic bytes and its
  name-table version string was read with fontTools before placement here.
- Only latin subsets are shipped (4 files: Newsreader normal/italic and Archivo normal); no other families are permitted.
