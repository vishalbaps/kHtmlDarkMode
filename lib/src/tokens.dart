import 'color.dart';
import 'palette.dart';

/// A token pair whose contrast guarantee failed validation.
class KdmTokenViolation {
  /// The text token.
  final String foreground;

  /// The surface token it was measured against.
  final String background;

  /// Measured WCAG contrast.
  final double ratio;

  /// The ratio the pair is documented to meet.
  final double required;

  /// Creates a violation record.
  const KdmTokenViolation(this.foreground, this.background, this.ratio, this.required);

  @override
  String toString() => '$foreground on $background = ${ratio.toStringAsFixed(2)}:1 '
      '(needs ${required.toStringAsFixed(1)}:1)';
}

/// The `--kdm-*` CSS custom properties offered to template authors.
///
/// Optional for authors: a template that ignores them is still themed by the
/// in-page pass. A template that uses them is themed by CSS alone, before any
/// script runs.
///
/// Accents, soft tints and the subtle text token are *solved* against their
/// surfaces rather than written down, which is what makes the contrast
/// guarantee true by construction — see [validate].
class KdmTokens {
  /// Every token, name to `#RRGGBB`.
  final Map<String, String> values;

  /// Whether these are the dark-mode values.
  final bool isDark;

  const KdmTokens._(this.values, this.isDark);

  /// The tokens of [KdmPalette.light], precomputed.
  ///
  /// Deriving tokens costs several hundred OKLCh solves — about one 60 fps
  /// frame — which would otherwise land on the host's UI thread on the first
  /// conversion. `test/tokens_test.dart` re-derives both tables from the
  /// palette and fails if either drifts.
  static const KdmTokens defaultLight = KdmTokens._(_lightValues, false);

  /// The tokens of [KdmPalette.dark], precomputed. See [defaultLight].
  static const KdmTokens defaultDark = KdmTokens._(_darkValues, true);

  /// Text tokens, each guaranteed 4.5:1 on every surface in [textSurfaces].
  static const List<String> textTokens = [
    '--kdm-fg',
    '--kdm-fg-muted',
    '--kdm-fg-subtle',
    '--kdm-accent',
    '--kdm-danger',
    '--kdm-info',
    '--kdm-warning',
  ];

  /// Surfaces text tokens are guaranteed on. `--kdm-surface-3` is a divider and
  /// track colour only, so it is deliberately excluded.
  static const List<String> textSurfaces = ['--kdm-bg', '--kdm-surface', '--kdm-surface-2'];

  /// The accent families, each emitting text, fill and soft-tint tokens.
  static const List<String> accents = ['accent', 'danger', 'info', 'warning'];

  /// Derives the tokens from [palette].
  factory KdmTokens.from(KdmPalette palette) {
    final isDark = palette.isDark;
    final bg = palette.background;
    final surface = palette.surface;
    final surface2 = palette.surface2;
    final fgMuted = palette.foregroundMuted;

    final textSurfaceColours = [bg, surface, surface2];
    final fgSubtle = _solveAgainstAll(fgMuted, textSurfaceColours, 4.5);

    final seeds = {
      'accent': palette.accent,
      'danger': palette.danger,
      'info': palette.info,
      'warning': palette.warning,
    };

    final out = <String, String>{
      '--kdm-bg': bg.toHex(),
      '--kdm-surface': surface.toHex(),
      '--kdm-surface-2': surface2.toHex(),
      '--kdm-surface-3': palette.surface3.toHex(),
      '--kdm-fg': palette.foreground.toHex(),
      '--kdm-fg-muted': fgMuted.toHex(),
      '--kdm-fg-subtle': fgSubtle.toHex(),
      '--kdm-border': palette.border.toHex(),
      '--kdm-border-strong': palette.borderStrong.toHex(),
    };

    seeds.forEach((name, seed) {
      // Accent text: solved so it passes on every text surface.
      out['--kdm-$name'] = _solveAgainstAll(seed, textSurfaceColours, 4.5).toHex();

      // Solid fill: keeps the brand colour in both modes. Its text is whichever
      // of black/white contrasts better.
      out['--kdm-$name-fill'] = seed.toHex();
      out['--kdm-$name-fill-fg'] = KdmColor.contrast(KdmColor.white, seed) >= KdmColor.contrast(KdmColor.black, seed)
          ? KdmColor.white.toHex()
          : KdmColor.black.toHex();

      // Soft tint: the chip/pill pattern. The tint is the seed mixed into the
      // card surface; its text is solved against that exact tint, which is why
      // the pair cannot fail.
      final alpha = isDark ? 0.22 : 0.10;
      final soft = seed.withAlpha(alpha).over(surface);
      out['--kdm-$name-soft'] = soft.toHex();
      out['--kdm-$name-soft-fg'] = _solveAgainstAll(seed, [soft], 4.5).toHex();
    });

    return KdmTokens._(Map.unmodifiable(out), isDark);
  }

  /// The custom-property block injected into the page.
  ///
  /// Scoped to `html[data-kdm-theme="…"]` (specificity 0,1,1) so it outranks the
  /// `:root` fallbacks (0,1,0) an author defines for browser preview — the
  /// package's values always win, while the template still previews standalone.
  String toCssBlock() {
    final body = values.entries.map((e) => '  ${e.key}: ${e.value};').join('\n');
    return 'html[data-kdm-theme="${isDark ? 'dark' : 'light'}"] {\n$body\n}';
  }

  /// Re-checks every documented guarantee. Empty means every pair meets AA.
  List<KdmTokenViolation> validate() {
    final v = <KdmTokenViolation>[];
    KdmColor at(String k) => KdmColor.tryHex(values[k]!)!;

    for (final text in textTokens) {
      for (final surface in textSurfaces) {
        final r = KdmColor.contrast(at(text), at(surface));
        if (r < 4.5) v.add(KdmTokenViolation(text, surface, r, 4.5));
      }
    }
    for (final name in accents) {
      for (final pair in [
        ['--kdm-$name-fill-fg', '--kdm-$name-fill'],
        ['--kdm-$name-soft-fg', '--kdm-$name-soft'],
      ]) {
        final r = KdmColor.contrast(at(pair[0]), at(pair[1]));
        if (r < 4.5) v.add(KdmTokenViolation(pair[0], pair[1], r, 4.5));
      }
    }
    return v;
  }

  /// The **least extreme** colour keeping [seed]'s hue and chroma that still
  /// passes [target] against *every* colour in [backgrounds].
  ///
  /// "Least extreme" means closest in luminance to the backgrounds: on a light
  /// page the lightest value that passes, on a dark page the darkest. That keeps
  /// muted and subtle tokens genuinely muted instead of driving every solved
  /// token to black or white.
  ///
  /// Exactly [KdmColor.contrast], with each luminance computed once rather than
  /// per comparison — the result is identical, at a fraction of the cost.
  static KdmColor _solveAgainstAll(KdmColor seed, List<KdmColor> backgrounds, double target) {
    final hue = seed.okH;
    final chroma = seed.okC;
    final backgroundLuminances = [for (final b in backgrounds) b.luminance];
    final onDark = backgroundLuminances.first < 0.18;
    KdmColor? best;
    var bestLuminance = 0.0;
    for (var i = 0; i <= 400; i++) {
      final c = KdmColor.fromOkLch(i / 400, chroma, hue);
      final l = c.luminance;
      var passes = true;
      for (final b in backgroundLuminances) {
        final hi = l > b ? l : b;
        final lo = l > b ? b : l;
        if ((hi + 0.05) / (lo + 0.05) < target) {
          passes = false;
          break;
        }
      }
      if (!passes) continue;
      if (best == null || (onDark ? l < bestLuminance : l > bestLuminance)) {
        best = c;
        bestLuminance = l;
      }
    }
    return best ?? (onDark ? KdmColor.white : KdmColor.black);
  }
}

// Generated from KdmTokens.from(KdmPalette.light / .dark) and held to it by
// test/tokens_test.dart. Order matters: it is the order the CSS is emitted in.

const Map<String, String> _lightValues = {
  '--kdm-bg': '#FFFFFF',
  '--kdm-surface': '#F6F6F9',
  '--kdm-surface-2': '#ECECF2',
  '--kdm-surface-3': '#CECEDA',
  '--kdm-fg': '#141417',
  '--kdm-fg-muted': '#62626C',
  '--kdm-fg-subtle': '#6A6A74',
  '--kdm-border': '#ECECF2',
  '--kdm-border-strong': '#CECEDA',
  '--kdm-accent': '#1F7860',
  '--kdm-accent-fill': '#006851',
  '--kdm-accent-fill-fg': '#FFFFFF',
  '--kdm-accent-soft': '#DDE8E8',
  '--kdm-accent-soft-fg': '#1A745D',
  '--kdm-danger': '#D31914',
  '--kdm-danger-fill': '#F44336',
  '--kdm-danger-fill-fg': '#000000',
  '--kdm-danger-soft': '#F6E4E5',
  '--kdm-danger-soft-fg': '#D01411',
  '--kdm-info': '#006CC6',
  '--kdm-info-fill': '#2196F3',
  '--kdm-info-fill-fg': '#000000',
  '--kdm-info-soft': '#E1ECF8',
  '--kdm-info-soft-fg': '#006BC4',
  '--kdm-warning': '#B04F00',
  '--kdm-warning-fill': '#FF9800',
  '--kdm-warning-fill-fg': '#000000',
  '--kdm-warning-soft': '#F7EDE0',
  '--kdm-warning-soft-fg': '#B15000',
};

const Map<String, String> _darkValues = {
  '--kdm-bg': '#181A1B',
  '--kdm-surface': '#232328',
  '--kdm-surface-2': '#2E2F35',
  '--kdm-surface-3': '#35353B',
  '--kdm-fg': '#F6F6F9',
  '--kdm-fg-muted': '#B1B1BD',
  '--kdm-fg-subtle': '#9595A0',
  '--kdm-border': '#35353B',
  '--kdm-border-strong': '#484851',
  '--kdm-accent': '#52A58B',
  '--kdm-accent-fill': '#006851',
  '--kdm-accent-fill-fg': '#FFFFFF',
  '--kdm-accent-soft': '#1B3231',
  '--kdm-accent-soft-fg': '#52A48A',
  '--kdm-danger': '#FD6354',
  '--kdm-danger-fill': '#F44336',
  '--kdm-danger-fill-fg': '#000000',
  '--kdm-danger-soft': '#512A2B',
  '--kdm-danger-soft-fg': '#FB7464',
  '--kdm-info': '#289BF8',
  '--kdm-info-fill': '#2196F3',
  '--kdm-info-fill-fg': '#000000',
  '--kdm-info-soft': '#233C55',
  '--kdm-info-soft-fg': '#4DA9FB',
  '--kdm-warning': '#E17C00',
  '--kdm-warning-fill': '#FF9800',
  '--kdm-warning-fill-fg': '#000000',
  '--kdm-warning-soft': '#533D1F',
  '--kdm-warning-soft-fg': '#FB9400',
};
