import 'dart:math' as math;

/// An immutable sRGB colour with OKLCh and WCAG accessors.
///
/// Deliberately free of Flutter and `dart:ui`, so the colour maths runs in a
/// command-line tool, a server, or a test without a Flutter binding.
///
/// OKLCh is used in preference to HSL because HSL lightness is not perceptually
/// uniform: two colours sharing an HSL `L` can sit several contrast steps apart,
/// which makes a contrast solver over HSL non-monotonic and therefore unsolvable
/// by search.
class KdmColor {
  /// Red channel, 0..1, **not** premultiplied.
  final double r;

  /// Green channel, 0..1, **not** premultiplied.
  final double g;

  /// Blue channel, 0..1, **not** premultiplied.
  final double b;

  /// 0 = fully transparent, 1 = fully opaque.
  final double a;

  /// Creates a colour from sRGB channels in 0..1.
  const KdmColor(this.r, this.g, this.b, [this.a = 1.0]);

  /// Creates a colour from a packed `0xRRGGBB` integer.
  const KdmColor.fromRgb(int rgb, [this.a = 1.0])
      : r = ((rgb >> 16) & 0xFF) / 255,
        g = ((rgb >> 8) & 0xFF) / 255,
        b = (rgb & 0xFF) / 255;

  /// Opaque white.
  static const KdmColor white = KdmColor(1, 1, 1);

  /// Opaque black.
  static const KdmColor black = KdmColor(0, 0, 0);

  /// Whether the colour is (effectively) fully opaque.
  bool get isOpaque => a >= 0.999;

  // ---------------------------------------------------------------- factories

  /// Parses `#rgb`, `#rgba`, `#rrggbb` or `#rrggbbaa`, with or without the `#`.
  ///
  /// Returns null rather than throwing — callers treat unparseable values as
  /// opaque tokens to be passed through untouched.
  static KdmColor? tryHex(String input) {
    var hex = input.trim();
    if (hex.startsWith('#')) hex = hex.substring(1);
    if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex)) return null;

    switch (hex.length) {
      case 3:
      case 4:
        final ch = hex.split('').map((c) => int.parse('$c$c', radix: 16) / 255).toList();
        return KdmColor(ch[0], ch[1], ch[2], ch.length == 4 ? ch[3] : 1.0);
      case 6:
      case 8:
        int at(int i) => int.parse(hex.substring(i, i + 2), radix: 16);
        return KdmColor(
          at(0) / 255,
          at(2) / 255,
          at(4) / 255,
          hex.length == 8 ? at(6) / 255 : 1.0,
        );
      default:
        return null;
    }
  }

  /// Builds from OKLCh, reducing chroma until the result lands inside the sRGB
  /// gamut. Falls back to the achromatic axis if reduction cannot converge, so
  /// this never returns an out-of-gamut colour.
  ///
  /// The result is **quantised to 8 bits per channel**, because that is what the
  /// emitted `#RRGGBB` will be. Measuring contrast on an unrounded float and
  /// then rounding for output can drop a boundary value below its target — a
  /// solved 4.50:1 became 4.48:1 in practice. Quantising here makes every
  /// contrast measurement true of the value actually written to the page.
  factory KdmColor.fromOkLch(double l, double c, double h, [double alpha = 1.0]) {
    var chroma = c;
    for (var i = 0; i < 48; i++) {
      final candidate = _okLabToRgb(l, chroma * math.cos(_rad(h)), chroma * math.sin(_rad(h)), alpha);
      if (candidate._inGamut) return candidate._clamped()._quantised();
      chroma *= 0.94;
    }
    return _okLabToRgb(l, 0, 0, alpha)._clamped()._quantised();
  }

  // ------------------------------------------------------------------- OKLCh

  /// Perceptual lightness, 0..1.
  double get okL => _okLab[0];

  /// Perceptual chroma. 0 is achromatic; sRGB tops out near 0.37.
  double get okC => math.sqrt(_okLab[1] * _okLab[1] + _okLab[2] * _okLab[2]);

  /// Hue angle in degrees, 0..360.
  double get okH {
    final deg = _deg(math.atan2(_okLab[2], _okLab[1]));
    return deg < 0 ? deg + 360 : deg;
  }

  List<double> get _okLab {
    double lin(double v) => v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    final rl = lin(r), gl = lin(g), bl = lin(b);

    final l = 0.4122214708 * rl + 0.5363325363 * gl + 0.0514459929 * bl;
    final m = 0.2119034982 * rl + 0.6806995451 * gl + 0.1073969566 * bl;
    final s = 0.0883024619 * rl + 0.2817188376 * gl + 0.6299787005 * bl;

    final l_ = _cbrt(l), m_ = _cbrt(m), s_ = _cbrt(s);
    return [
      0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
      1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
      0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_,
    ];
  }

  static KdmColor _okLabToRgb(double l, double aa, double bb, double alpha) {
    final l_ = l + 0.3963377774 * aa + 0.2158037573 * bb;
    final m_ = l - 0.1055613458 * aa - 0.0638541728 * bb;
    final s_ = l - 0.0894841775 * aa - 1.2914855480 * bb;

    final lc = l_ * l_ * l_, mc = m_ * m_ * m_, sc = s_ * s_ * s_;

    double gam(double v) {
      if (v <= 0) return 0;
      return v <= 0.0031308 ? 12.92 * v : 1.055 * math.pow(v, 1 / 2.4) - 0.055;
    }

    return KdmColor(
      gam(4.0767416621 * lc - 3.3077115913 * mc + 0.2309699292 * sc),
      gam(-1.2684380046 * lc + 2.6097574011 * mc - 0.3413193965 * sc),
      gam(-0.0041960863 * lc - 0.7034186147 * mc + 1.7076147010 * sc),
      alpha,
    );
  }

  bool get _inGamut => r >= -0.001 && r <= 1.001 && g >= -0.001 && g <= 1.001 && b >= -0.001 && b <= 1.001;

  KdmColor _clamped() => KdmColor(r.clamp(0.0, 1.0), g.clamp(0.0, 1.0), b.clamp(0.0, 1.0), a);

  /// Snaps channels to the 8-bit grid the CSS output uses.
  KdmColor _quantised() => KdmColor(
        (r * 255).round() / 255,
        (g * 255).round() / 255,
        (b * 255).round() / 255,
        a,
      );

  // -------------------------------------------------------------------- WCAG

  /// WCAG 2.1 relative luminance.
  double get luminance {
    double lin(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b);
  }

  /// WCAG 2.1 contrast ratio, 1.0..21.0. Symmetric in its arguments.
  static double contrast(KdmColor x, KdmColor y) {
    final a = x.luminance, b = y.luminance;
    final hi = a > b ? a : b;
    final lo = a > b ? b : a;
    return (hi + 0.05) / (lo + 0.05);
  }

  // ------------------------------------------------------------- composition

  /// Composites this colour over [backdrop] using its own alpha, returning an
  /// opaque colour. Used to resolve what a translucent overlay actually looks
  /// like before deciding whether it needs remapping.
  KdmColor over(KdmColor backdrop) {
    if (isOpaque) return this;
    return KdmColor(
      r * a + backdrop.r * (1 - a),
      g * a + backdrop.g * (1 - a),
      b * a + backdrop.b * (1 - a),
    )._quantised();
  }

  /// This colour with its alpha replaced by [alpha].
  KdmColor withAlpha(double alpha) => KdmColor(r, g, b, alpha);

  // ----------------------------------------------------------------- output

  /// Uppercase `#RRGGBB`, or `rgba(r, g, b, a)` when translucent.
  String toCss() {
    if (isOpaque) return toHex();
    int n(double v) => (v * 255).round().clamp(0, 255);
    return 'rgba(${n(r)}, ${n(g)}, ${n(b)}, ${_trimAlpha(a)})';
  }

  /// Uppercase `#RRGGBB`, alpha dropped.
  String toHex() {
    String c(double v) => (v * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0').toUpperCase();
    return '#${c(r)}${c(g)}${c(b)}';
  }

  /// Packed `0xAARRGGBB`, the form Flutter's `Color(int)` takes.
  int toArgb() {
    int n(double v) => (v * 255).round().clamp(0, 255);
    return (n(a) << 24) | (n(r) << 16) | (n(g) << 8) | n(b);
  }

  static String _trimAlpha(double v) {
    final s = v.toStringAsFixed(3);
    return s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }

  @override
  String toString() => toCss();

  @override
  bool operator ==(Object other) =>
      other is KdmColor &&
      (r * 255).round() == (other.r * 255).round() &&
      (g * 255).round() == (other.g * 255).round() &&
      (b * 255).round() == (other.b * 255).round() &&
      (a * 255).round() == (other.a * 255).round();

  @override
  int get hashCode => Object.hash((r * 255).round(), (g * 255).round(), (b * 255).round(), (a * 255).round());

  // ---------------------------------------------------------------- helpers

  static double _cbrt(double v) => v <= 0 ? 0 : math.pow(v, 1 / 3).toDouble();
  static double _rad(double deg) => deg * math.pi / 180;
  static double _deg(double rad) => rad * 180 / math.pi;
}
