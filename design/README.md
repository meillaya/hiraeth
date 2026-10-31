# Softbound design assets

- `index.html` — the formal design-system specification: canonical tokens, type
  scale, responsive matrix, component contracts, and the pixel acceptance
  checklist. Open it directly in a browser; it reads values from
  `../assets/css/tokens.css`, so it cannot drift from the running site.
- `softbound_*.html` — static page prototypes for the Softbound edition. They
  are reference compositions (and some depend on a prototype-only data/JS
  bundle that is not shipped); the production implementation is the Phoenix
  LiveView app in `lib/hiraeth_web/`.
- `spec.css` — document-only styling for the specification page.

Runtime sources of truth:

- `assets/css/tokens.css` — tokens
- `assets/css/softbound.css` — component layer
- `lib/hiraeth_web/components/layouts.ex` — sheet/header/footer shell
- `lib/hiraeth_web/live/` — page implementations

Responsive acceptance:

```sh
node scripts/qa/design_screenshots.mjs http://127.0.0.1:4000 artifacts/qa/design
```

The script captures every public surface at 390, 560, 760, 834, 900, 1040,
1180, 1280, and 1440 px and fails on horizontal overflow, sheet inset drift, or
header-mode drift.
