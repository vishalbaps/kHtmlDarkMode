/// Standalone dark mode for HTML shown in a web view.
///
/// Start with [KHtmlDarkMode.convert]. The colour engine, palette and tokens are
/// exported for linting, previews and matching native UI to the content.
library;

export 'src/color.dart' show KdmColor;
export 'src/engine.dart' show KdmEngine, KdmEngineConfig, KdmSurfaceKind, KdmSurfaceResult;
export 'src/k_html_dark_mode.dart' show KHtmlDarkMode, KdmResult;
export 'src/palette.dart' show KdmPalette;
export 'src/tokens.dart' show KdmTokens, KdmTokenViolation;
