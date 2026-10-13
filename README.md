# k_html_dark_mode

Dark mode for HTML you show in a web view — emails, newsletters, CMS messages,
anything authored for a white page.

Pass HTML in, get a document back that themes itself when the web view loads it:

- light surfaces become dark surfaces, **keeping the author's ordering** — a
  raised card stays raised, a recessed inset stays recessed;
- text, inline SVG icons, borders and shadows are corrected to **WCAG AA**;
- **brand colours, images and already-dark colours are left alone**;
- a template that ships its own `prefers-color-scheme` CSS is left to it;
- light mode changes no authored colour.

It is **standalone**: there is no palette to configure. Every app using the
package renders the same message the same way. Pure Dart, zero dependencies.

## Install

```yaml
dependencies:
  k_html_dark_mode: ^1.0.0
```

## Use

```dart
import 'package:k_html_dark_mode/k_html_dark_mode.dart';

final result = KHtmlDarkMode.convert(html);   // dark is the default

result.html;             // the document to load
result.backgroundArgb;   // paint the web view with this — no white flash
```

In light mode pass `isDark: false`: authored colours are then left as they are.

`html` can be a fragment (`<div>…</div>`) or a complete document. The web view
**must run JavaScript**: the colour pass runs inside the page, because only a
browser can tell which CSS rule won and what an element actually sits on.

### webview_flutter

```dart
final result = KHtmlDarkMode.convert(html, isDark: isDarkTheme, fontScale: textScale);

controller
  ..setJavaScriptMode(JavaScriptMode.unrestricted)
  ..setBackgroundColor(Color(result.backgroundArgb))
  ..loadHtmlString(result.html);
```

### flutter_inappwebview

```dart
final result = KHtmlDarkMode.convert(html, isDark: isDarkTheme);

InAppWebView(
  initialData: InAppWebViewInitialData(data: result.html),
  initialSettings: InAppWebViewSettings(javaScriptEnabled: true),
);
```

`convert` is deterministic — the same arguments always return the same string —
so a widget that compares its input can skip reloading.

## Options

| Option | Default | |
|---|---|---|
| `isDark` | `true` | The mode to render in. Pass `false` for light mode — authored colours are then left alone. |
| `fontScale` | `1.0` | Multiplies each element's **resolved** font size, so `px`-sized templates scale and keep their hierarchy. |
| `fitToWidth` | `false` | Scale content wider than the screen down to fit, like a mail client shows a fixed-width email. |
| `pageBackground` | built-in | `#RRGGBB` to blend into the screen behind the content. Must be opaque, suit the mode, and keep every contrast guarantee — otherwise `ArgumentError`. |
| `viewport` | `width=device-width, initial-scale=1.0` | Injected only when the HTML has none; `null` injects nothing. |
| `extraHead` | `''` | Your markup at the end of the injected head block. |
| `extraBodyEnd` | `''` | Your markup after the package's script — the place for your listeners. |
| `debugTrace` | `false` | Include the first 40 background decisions in the report. |

Converting an already-converted document replaces the earlier conversion, so
switching theme is just another `convert` call.

## Talking to the host

The document reports back through the page, so it works with any web view:

```dart
const listener = '''
<script>
  window.addEventListener('kdm:layout', function (e) {
    // e.detail = { height, scale } — size an inline web view to its content
    HeightChannel.postMessage(String(e.detail.height));
  });
  window.addEventListener('kdm:report', function (e) {
    // e.detail = { v, source, stats, dom, trace }
  });
</script>''';

final result = KHtmlDarkMode.convert(html, extraBodyEnd: listener);
```

`kdm:layout` fires after the colour pass and any fit-to-width scaling, then
once for each new size (a resize, a late image). The latest is also left on
`window.kdmLayout`, and the report on `window.kdmReport` and on `<html>`:

| Attribute | Value |
|---|---|
| `data-kdm-theme` | `dark` or `light` |
| `data-kdm-version` | the package version that converted the document |
| `data-kdm-source` | `engine`, `author` (the template handles dark itself), `light`, or `error` |
| `data-kdm-stats` | `{"surfaces","texts","skipped","untouched","scaled"}` counts |
| `data-kdm-error` | only if the pass failed — the content is then left as authored |

## For template authors

Nothing is required: a plain light template is converted automatically. Three
levels of control, from least to most:

1. **Do nothing.** Write for a white page. Colours you got right are kept.
2. **Ship your own dark mode.** Any `@media (prefers-color-scheme: …)` rule or
   `color-scheme: dark` declaration and the engine stands aside entirely.
3. **Use the tokens.** These CSS custom properties are set on
   `html[data-kdm-theme]` before any script runs, so token-based markup is
   exact in both modes. Define your own `:root` fallbacks for browser preview —
   the package's values outrank them.

| Token | Light | Dark |
|---|---|---|
| `--kdm-bg` | `#FFFFFF` | `#181A1B` |
| `--kdm-surface` | `#F6F6F9` | `#232328` |
| `--kdm-surface-2` | `#ECECF2` | `#2E2F35` |
| `--kdm-surface-3` | `#CECEDA` | `#35353B` |
| `--kdm-fg` | `#141417` | `#F6F6F9` |
| `--kdm-fg-muted` | `#62626C` | `#B1B1BD` |
| `--kdm-fg-subtle` | `#6A6A74` | `#9595A0` |
| `--kdm-border` | `#ECECF2` | `#35353B` |
| `--kdm-border-strong` | `#CECEDA` | `#484851` |
| `--kdm-accent` | `#1F7860` | `#52A58B` |
| `--kdm-accent-fill` / `-fill-fg` | `#006851` / `#FFFFFF` | `#006851` / `#FFFFFF` |
| `--kdm-accent-soft` / `-soft-fg` | `#DDE8E8` / `#1A745D` | `#1B3231` / `#52A48A` |
| `--kdm-danger` | `#D31914` | `#FD6354` |
| `--kdm-danger-fill` / `-fill-fg` | `#F44336` / `#000000` | `#F44336` / `#000000` |
| `--kdm-danger-soft` / `-soft-fg` | `#F6E4E5` / `#D01411` | `#512A2B` / `#FB7464` |
| `--kdm-info` | `#006CC6` | `#289BF8` |
| `--kdm-info-fill` / `-fill-fg` | `#2196F3` / `#000000` | `#2196F3` / `#000000` |
| `--kdm-info-soft` / `-soft-fg` | `#E1ECF8` / `#006BC4` | `#233C55` / `#4DA9FB` |
| `--kdm-warning` | `#B04F00` | `#E17C00` |
| `--kdm-warning-fill` / `-fill-fg` | `#FF9800` / `#000000` | `#FF9800` / `#000000` |
| `--kdm-warning-soft` / `-soft-fg` | `#F7EDE0` / `#B15000` | `#533D1F` / `#FB9400` |

Every text token meets 4.5:1 on `bg`, `surface` and `surface-2`; every `-fg`
meets 4.5:1 on its fill or tint. `surface-3` is for dividers, not text.

To keep one element and everything inside it exactly as authored — a chart, a
signature, a colour swatch — add `data-kdm-preserve`:

```html
<div data-kdm-preserve>…</div>
```

## How it works

1. **Before first paint**, CSS in `<head>`: `color-scheme`, the page colours and
   the tokens. No flash, and token-based templates are already done.
2. **Author check**: if the template declares its own dark mode, stop.
3. **The pass**, in the page: walk the DOM with `getComputedStyle`, so the real
   cascade decides what each element looks like and what it sits on. Then:
   - a background that is light and unsaturated is remapped onto a dark ramp
     that rises with authored lightness; a nested element that repeats its
     parent's colour reuses the parent's result instead of stepping again;
   - a saturated background is a brand colour and is kept;
   - text that already passes is kept; text that fails is inverted onto a light
     ramp (so a hierarchy of greys stays a hierarchy), then repaired if needed;
   - borders dim, shadows darken, SVG fills and strokes are treated like text;
   - images, video, canvas and iframes are never touched.

The colour maths is computed in OKLCh (perceptual) and every contrast check is
WCAG 2.1. The same engine is exported in Dart — `KdmEngine`, `KdmColor`,
`KdmTokens` — for linting templates or matching native UI to the content.

## Performance

Measured with `tool/benchmark.dart` and `tool/node/bench.mjs` (not published):

| | 2 KB message | 12 KB email | 214 KB fragment | 449 KB newsletter |
|---|---|---|---|---|
| `convert()` — Dart, AOT | 0.03 ms | 0.09 ms | 1.2 ms | 2.3 ms |
| In-page pass — Chromium | 1.0 ms | 2.3 ms | 18 ms | 33 ms |
| In-page pass — Chromium, CPU 6× slower | 7.7 ms | 15 ms | 176 ms | 265 ms |
| In-page pass — WebKit | 2 ms | 6 ms | 49 ms | 89 ms |

- `convert()` does no colour maths for the built-in palettes — the token
  tables are precomputed — and touches a full document once to find where to
  inject and once to assemble. The first call costs the same as any other.
- The in-page pass runs inside the web view's renderer, off the host's UI
  thread. Its cost is reading the CSS cascade, one element at a time; the colour
  maths is about 2% of it.
- At typical message sizes neither half is noticeable. If a host routinely
  converts very large documents, `convert()` can move to `Isolate.run`.

## Limits

- **JavaScript is required for the pass.** A renderer that cannot run it
  (`flutter_html`, `flutter_widget_from_html`, an email client) still gets the
  pre-paint CSS and tokens, but light surfaces are not remapped.
- Text drawn over an image or a gradient is best effort.
- Remapped surfaces sit in a narrow band just above the page, so a mid grey
  placed directly beside a dark grey can swap which looks lighter. This is the
  price of idempotence (converting twice equals converting once).

## License

MIT
