import 'color.dart';
import 'document.dart';
import 'engine.dart';
import 'palette.dart';
import 'tokens.dart';
import 'version.dart';

/// The output of [KHtmlDarkMode.convert].
class KdmResult {
  /// The complete document to load into the web view.
  final String html;

  /// Whether this is the dark-mode rendering.
  final bool isDark;

  /// The page background. Give the web view this as its own background colour
  /// so there is no flash of the wrong colour before the document paints.
  final KdmColor background;

  /// Creates a result.
  const KdmResult({required this.html, required this.isDark, required this.background});

  /// [background] as `#RRGGBB`.
  String get backgroundHex => background.toHex();

  /// [background] as `0xAARRGGBB`, ready for Flutter's `Color(int)`.
  int get backgroundArgb => background.toArgb();
}

/// Converts HTML for display in a light- or dark-themed web view.
///
/// Standalone by design: callers pass HTML, never a palette, so the same
/// message renders identically in every app. Dark mode is the default.
///
/// ```dart
/// final result = KHtmlDarkMode.convert(html);
/// controller.setBackgroundColor(Color(result.backgroundArgb));
/// controller.loadHtmlString(result.html);
/// ```
///
/// The returned document **themes itself when it loads**: the colour pass runs
/// inside the page, because only a browser can resolve the CSS cascade. The web
/// view must therefore have JavaScript enabled. Renderers that cannot run
/// JavaScript still receive the pre-paint CSS — page colours, `color-scheme`
/// and the `--kdm-*` tokens — but not the pass.
abstract final class KHtmlDarkMode {
  /// The package version, also stamped on every document as `data-kdm-version`.
  static const String version = kdmVersion;

  /// The viewport meta injected when the HTML does not declare its own.
  static const String defaultViewport = 'width=device-width, initial-scale=1.0';

  static final Map<String, KdmTokens> _tokenCache = {};

  /// Converts [html] — a fragment or a complete document — for display.
  ///
  /// * [isDark] — the mode to render in; dark unless the host says otherwise.
  ///   Pass `false` in light mode: the document is then left as authored,
  ///   apart from text scaling and the page colours.
  /// * [fontScale] — the user's text size multiplier (1.0 = as authored).
  ///   Applied to each element's resolved size, so `px`-sized templates scale
  ///   and the typographic hierarchy is preserved.
  /// * [fitToWidth] — scale content wider than the viewport down to fit, the
  ///   way a mail client shows a fixed-width email.
  /// * [pageBackground] — `#RRGGBB` to use instead of the built-in page
  ///   background, so the content blends into the screen it sits on. Must be
  ///   opaque and suit the mode; every token must still meet WCAG AA on it.
  /// * [viewport] — content of the viewport meta injected when the HTML has
  ///   none, or null to inject nothing.
  /// * [extraHead] — host markup placed at the end of the injected head block.
  /// * [extraBodyEnd] — host markup placed after the package's script, so it
  ///   runs after the colour pass. The place for a host's own listeners, e.g.
  ///   for the `kdm:layout` event.
  /// * [debugTrace] — include a trace of up to 40 background decisions in the
  ///   `kdm:report` event.
  ///
  /// The same arguments always produce the same string, so a web view widget
  /// comparing its input can skip a reload. Converting an already-converted
  /// document replaces the earlier conversion rather than stacking on it.
  ///
  /// Throws [ArgumentError] for a non-positive [fontScale] or an unusable
  /// [pageBackground].
  static KdmResult convert(
    String html, {
    bool isDark = true,
    double fontScale = 1.0,
    bool fitToWidth = false,
    String? pageBackground,
    String? viewport = defaultViewport,
    String extraHead = '',
    String extraBodyEnd = '',
    bool debugTrace = false,
  }) {
    if (!fontScale.isFinite || fontScale <= 0) {
      throw ArgumentError.value(fontScale, 'fontScale', 'must be a positive number');
    }

    var palette = KdmPalette.of(isDark: isDark);
    if (pageBackground != null) {
      palette = palette.withBackground(_parseBackground(pageBackground, isDark));
    }
    final tokens = _tokensFor(palette);

    final spec = DocumentSpec(
      isDark: isDark,
      background: palette.background,
      foreground: palette.foreground,
      tokens: tokens,
      fontScale: fontScale,
      fitToWidth: fitToWidth,
      viewport: viewport,
      extraHead: extraHead,
      extraBodyEnd: extraBodyEnd,
      trace: debugTrace,
      config: KdmEngineConfig.standard,
    );

    return KdmResult(
      html: composeDocument(html, spec),
      isDark: isDark,
      background: palette.background,
    );
  }

  /// The `--kdm-*` design tokens for a mode, e.g. to publish to template
  /// authors or to style native UI around the web view to match.
  static KdmTokens tokens({bool isDark = true, String? pageBackground}) {
    var palette = KdmPalette.of(isDark: isDark);
    if (pageBackground != null) {
      palette = palette.withBackground(_parseBackground(pageBackground, isDark));
    }
    return _tokensFor(palette);
  }

  // Token derivation is the only costly step — several hundred OKLCh solves —
  // and depends only on mode and page background. The built-in palettes are
  // precomputed, so only a pageBackground override ever derives, once.
  static KdmTokens _tokensFor(KdmPalette palette) {
    if (identical(palette, KdmPalette.dark)) return KdmTokens.defaultDark;
    if (identical(palette, KdmPalette.light)) return KdmTokens.defaultLight;

    final key = '${palette.isDark}|${palette.background.toHex()}';
    final hit = _tokenCache[key];
    if (hit != null) return hit;
    if (_tokenCache.length >= 16) _tokenCache.clear();
    final tokens = KdmTokens.from(palette);
    final violations = tokens.validate();
    if (violations.isNotEmpty) {
      throw ArgumentError.value(
          palette.background.toHex(), 'pageBackground', 'breaks the contrast guarantee: ${violations.join('; ')}');
    }
    return _tokenCache[key] = tokens;
  }

  static KdmColor _parseBackground(String value, bool isDark) {
    final colour = KdmColor.tryHex(value);
    if (colour == null) {
      throw ArgumentError.value(value, 'pageBackground', 'is not a hex colour');
    }
    if (!colour.isOpaque) {
      throw ArgumentError.value(value, 'pageBackground', 'must be opaque');
    }
    // A dark page above the passthrough threshold would be remapped like any
    // other light surface; a light page below 0.5 is not a light page.
    if (isDark && colour.okL > KdmEngineConfig.standard.darkPassthroughOkL) {
      throw ArgumentError.value(value, 'pageBackground', 'is too light for dark mode');
    }
    if (!isDark && colour.okL < 0.5) {
      throw ArgumentError.value(value, 'pageBackground', 'is too dark for light mode');
    }
    return colour;
  }
}
