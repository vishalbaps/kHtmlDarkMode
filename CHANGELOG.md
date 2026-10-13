## 1.0.0

First release.

- `KHtmlDarkMode.convert(html)` — pass any HTML, fragment or complete document,
  and get back a document that themes itself in the web view. Dark by default;
  `isDark: false` for light mode.
- Standalone: no palette input. Built-in light and dark colours, so every host
  app renders the same message the same way. One optional override,
  `pageBackground`, lets a host match the screen the content sits on; it is
  rejected if it would break any contrast guarantee.
- Cascade-aware in-page pass: light surfaces are remapped into a dark ramp that
  preserves the author's ordering; text, inline SVG fills, borders and shadows
  are corrected to WCAG AA; brand colours, images, already-dark colours and
  templates that ship their own `prefers-color-scheme` CSS are left alone.
- Optional text scaling (`fontScale`) that multiplies each element's resolved
  size, and optional fit-to-width (`fitToWidth`) for fixed-width email layouts.
- `--kdm-*` design tokens for authors who want exact control, applied before any
  script runs. `data-kdm-preserve` opts an element and its subtree out.
- Diagnostics: `data-kdm-version`, `data-kdm-source` and `data-kdm-stats` on
  `<html>`, `window.kdmReport` / `window.kdmLayout`, and `kdm:report` /
  `kdm:layout` events.
- Built for the UI thread: `convert()` runs in about 2 ms on a 450 KB newsletter
  and well under 0.1 ms on a typical message, with no first-call cost — the
  default token tables are precomputed. The in-page pass reads each element's
  style once and batches every write that no later read can observe.
- Zero dependencies; Dart SDK 3.0 and later.

The colour algorithm is the one proven in production in the MySatsang app's
inbox (its engine 2.0.0); only names, packaging and the document assembly are
new. Golden vectors pin both the Dart and the JavaScript implementation to it.
