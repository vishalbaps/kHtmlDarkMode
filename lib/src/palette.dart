import 'color.dart';

/// The fixed colours the package themes with.
///
/// The package is standalone on purpose: callers pass HTML, never a palette,
/// so every host app renders the same message identically. These values are
/// the neutral scale and brand accents of the MySatsang app, which is where the
/// engine was proven on device.
///
/// The neutral ramp is mirrored between modes — each step sits the same
/// distance from its own page background — which is what lets one template
/// read correctly in both.
final class KdmPalette {
  /// Whether this is the dark palette.
  final bool isDark;

  /// Page background. Also the web view's own background, so there is no
  /// flash of the wrong colour before the document paints.
  final KdmColor background;

  /// Body text.
  final KdmColor foreground;

  /// Secondary text.
  final KdmColor foregroundMuted;

  /// Card / panel surface.
  final KdmColor surface;

  /// Nested block surface.
  final KdmColor surface2;

  /// Divider and track colour. Not a text surface.
  final KdmColor surface3;

  /// Hairline border.
  final KdmColor border;

  /// Emphasised border.
  final KdmColor borderStrong;

  /// Primary brand accent.
  final KdmColor accent;

  /// Error / destructive accent.
  final KdmColor danger;

  /// Informational accent.
  final KdmColor info;

  /// Warning accent.
  final KdmColor warning;

  const KdmPalette._({
    required this.isDark,
    required this.background,
    required this.foreground,
    required this.foregroundMuted,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.border,
    required this.borderStrong,
    required this.accent,
    required this.danger,
    required this.info,
    required this.warning,
  });

  /// The light palette.
  static const KdmPalette light = KdmPalette._(
    isDark: false,
    background: KdmColor.fromRgb(0xFFFFFF),
    foreground: KdmColor.fromRgb(0x141417),
    foregroundMuted: KdmColor.fromRgb(0x62626C),
    surface: KdmColor.fromRgb(0xF6F6F9),
    surface2: KdmColor.fromRgb(0xECECF2),
    surface3: KdmColor.fromRgb(0xCECEDA),
    border: KdmColor.fromRgb(0xECECF2),
    borderStrong: KdmColor.fromRgb(0xCECEDA),
    accent: _accent,
    danger: _danger,
    info: _info,
    warning: _warning,
  );

  /// The dark palette.
  static const KdmPalette dark = KdmPalette._(
    isDark: true,
    background: KdmColor.fromRgb(0x181A1B),
    foreground: KdmColor.fromRgb(0xF6F6F9),
    foregroundMuted: KdmColor.fromRgb(0xB1B1BD),
    surface: KdmColor.fromRgb(0x232328),
    surface2: KdmColor.fromRgb(0x2E2F35),
    surface3: KdmColor.fromRgb(0x35353B),
    border: KdmColor.fromRgb(0x35353B),
    borderStrong: KdmColor.fromRgb(0x484851),
    accent: _accent,
    danger: _danger,
    info: _info,
    warning: _warning,
  );

  // Brand accents are identical in both modes, so a primary button looks like
  // the same button everywhere.
  static const KdmColor _accent = KdmColor.fromRgb(0x006851);
  static const KdmColor _danger = KdmColor.fromRgb(0xF44336);
  static const KdmColor _info = KdmColor.fromRgb(0x2196F3);
  static const KdmColor _warning = KdmColor.fromRgb(0xFF9800);

  /// The palette for a mode.
  static KdmPalette of({required bool isDark}) => isDark ? dark : light;

  /// This palette with its page background replaced — the one override the
  /// package allows, so a host can match the screen the content sits on.
  KdmPalette withBackground(KdmColor background) => KdmPalette._(
        isDark: isDark,
        background: background,
        foreground: foreground,
        foregroundMuted: foregroundMuted,
        surface: surface,
        surface2: surface2,
        surface3: surface3,
        border: border,
        borderStrong: borderStrong,
        accent: accent,
        danger: danger,
        info: info,
        warning: warning,
      );
}
