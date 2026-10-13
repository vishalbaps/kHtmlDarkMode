import 'color.dart';

/// How the engine classified a background, for diagnostics and linting.
enum KdmSurfaceKind {
  /// Light mode — nothing is transformed.
  lightMode,

  /// Already an appropriate colour for the target mode. Left alone (I3).
  alreadyDark,

  /// A saturated, non-light fill: a deliberate brand colour. Left alone (I5).
  brandFill,

  /// A light-mode surface, remapped into the dark ramp (I1).
  remapped,

  /// Repeats its parent's authored background, so it is not a new surface and
  /// reuses the parent's mapped colour rather than elevating above it (I6).
  inherited,
}

/// Result of mapping a background, carrying why the decision was made.
class KdmSurfaceResult {
  /// The colour to paint.
  final KdmColor color;

  /// Why [color] was chosen.
  final KdmSurfaceKind kind;

  /// Creates a result.
  const KdmSurfaceResult(this.color, this.kind);

  /// True when the authored colour was returned as-is. [KdmSurfaceKind.inherited]
  /// is deliberately excluded: it returns the *parent's* mapped colour, which
  /// is a change even though no new surface was invented.
  bool get unchanged =>
      kind == KdmSurfaceKind.lightMode || kind == KdmSurfaceKind.alreadyDark || kind == KdmSurfaceKind.brandFill;
}

/// Tuning constants for [KdmEngine].
///
/// Changing any value must keep the invariant tests green — they assert
/// behaviour, not these numbers. It also changes the golden vectors, which is
/// a behaviour change and needs a version bump (see `CHANGELOG.md`).
class KdmEngineConfig {
  /// OKL at or below which a background is already suited to dark mode and is
  /// returned unchanged (I3).
  final double darkPassthroughOkL;

  /// A background at or above this chroma is a deliberate brand fill and is
  /// left alone (I5). Chroma is what separates "#1976D2, a chosen blue" from
  /// "#EEEEEE, a light surface".
  ///
  /// **There is deliberately no lightness ceiling.** A lightness ceiling breaks
  /// every warm brand ramp in half: yellows and golds are intrinsically
  /// high-lightness, so with a ceiling of 0.80 `#ff9800` (OKL 0.770) was kept
  /// while `#ffb300` (OKL 0.818) — same ramp, same chroma — was remapped to a
  /// muddy olive. No ceiling value fixes that, because lightness cannot
  /// distinguish "saturated gold" from "pale cream".
  ///
  /// Chroma can, and the two populations do not overlap. Measured across real
  /// email templates:
  ///
  ///     brand colours   OKC 0.090 (#006851 teal) .. 0.197 (#e65100 orange)
  ///     pale tints      OKC 0.006 (#eef0f4)      .. 0.062 (#fff3c4)
  ///
  /// 0.075 sits in that gap. Relative chroma — chroma as a fraction of what the
  /// hue can hold — was measured first and does *not* separate them: at OKL
  /// 0.96 sRGB holds almost no chroma, so pale tints score 0.97 and above.
  final double brandFillMinChroma;

  /// Lift applied to every remapped surface, so even the darkest authored
  /// surface sits clear of the page background.
  final double surfaceLiftOkL;

  /// Span of OKL the remapped surface ramp occupies above [surfaceLiftOkL].
  ///
  /// The mapping is **monotonically increasing** in authored lightness: a
  /// lighter authored surface maps to a lighter dark-mode surface. That is what
  /// preserves the author's ordering — a white card on a grey page stays
  /// raised, a grey inset inside a white card stays recessed. Inverting the
  /// direction (as Dark Reader does) reverses both, which it can afford because
  /// it owns the page background and an embedded fragment does not.
  final double surfaceRangeOkL;

  /// Fraction of authored chroma retained on a remapped surface. Together with
  /// [surfaceChromaCap] it stops a saturated band turning neon.
  final double surfaceChromaFactor;

  /// Ceiling on a remapped surface's chroma.
  final double surfaceChromaCap;

  /// Minimum contrast between a remapped surface and its parent, so nesting
  /// stays visible (I1).
  final double surfaceSeparation;

  /// Upper bound on remapped surface lightness, so deep nesting cannot walk all
  /// the way to light grey.
  final double surfaceCeilingOkL;

  /// Hard ceiling on a remapped surface's WCAG luminance.
  ///
  /// Above roughly 0.183 no light text reaches 4.5:1 — pure white tops out at
  /// 4.41:1 — so the solver is forced into near-black and a panel in a dark
  /// theme renders black-on-grey. Keeping every mapped surface below this makes
  /// that unreachable by construction rather than by luck.
  final double surfaceMaxLuminance;

  /// Bottom of the dark-mode text ramp: an authored colour at OKL 1 maps here,
  /// one at OKL 0 maps to [textFloorOkL] + [textRangeOkL].
  ///
  /// Inverting rather than solving to the nearest passing value is what keeps a
  /// typographic hierarchy intact. Solving collapsed every failing colour onto
  /// a single grey — black, #212121, #333333 and #8c8c8c all arrived at
  /// #AFAFAF — because a minimum is one point, not a range.
  final double textFloorOkL;

  /// Span of the dark-mode text ramp above [textFloorOkL].
  final double textRangeOkL;

  /// WCAG target for normal text.
  final double textContrast;

  /// WCAG target for large text: >= 24px, or >= 18.66px bold.
  final double largeTextContrast;

  /// Creates a configuration. The defaults are [standard].
  const KdmEngineConfig({
    this.darkPassthroughOkL = 0.45,
    this.brandFillMinChroma = 0.075,
    this.surfaceLiftOkL = 0.030,
    this.surfaceRangeOkL = 0.110,
    this.surfaceChromaFactor = 0.70,
    this.surfaceChromaCap = 0.055,
    this.surfaceSeparation = 1.20,
    this.surfaceCeilingOkL = 0.52,
    this.surfaceMaxLuminance = 0.17,
    this.textFloorOkL = 0.62,
    this.textRangeOkL = 0.33,
    this.textContrast = 4.5,
    this.largeTextContrast = 3.0,
  });

  /// The configuration `KHtmlDarkMode.convert` ships with.
  static const KdmEngineConfig standard = KdmEngineConfig();

  /// The constants as JSON — the form the in-page script receives, so the Dart
  /// and JavaScript engines can never run on different numbers.
  Map<String, double> toJson() => {
        'darkPassthroughOkL': darkPassthroughOkL,
        'brandFillMinChroma': brandFillMinChroma,
        'surfaceLiftOkL': surfaceLiftOkL,
        'surfaceRangeOkL': surfaceRangeOkL,
        'surfaceChromaFactor': surfaceChromaFactor,
        'surfaceChromaCap': surfaceChromaCap,
        'surfaceSeparation': surfaceSeparation,
        'surfaceCeilingOkL': surfaceCeilingOkL,
        'surfaceMaxLuminance': surfaceMaxLuminance,
        'textFloorOkL': textFloorOkL,
        'textRangeOkL': textRangeOkL,
        'textContrast': textContrast,
        'largeTextContrast': largeTextContrast,
      };
}

/// Maps authored HTML colours into the active theme.
///
/// This is the Dart reference implementation. The in-page script carries the
/// same maths in JavaScript — it has to run where `getComputedStyle` can
/// resolve the cascade — and the two are held together by the golden vectors
/// in `test/golden/vectors.json`.
///
/// Invariants, each covered by tests:
///
/// * **I1 monotonic** — a remapped surface stays visibly separated from its
///   parent wherever the author drew a visible step, in the author's direction.
/// * **I2 contrast** — corrected text always meets its WCAG target.
/// * **I3 passthrough** — a colour already suited to the mode is untouched.
/// * **I4 idempotent** — mapping twice equals mapping once.
/// * **I5 authored-correct is untouched** — brand fills pass through, and
///   [solveForeground] is a no-op on a pair that already passes.
/// * **I6 no invented elevation** — a nested element repeating its parent's
///   authored background reuses the parent's mapped colour.
/// * **I7 no stranded text** — no remapped surface is light enough that light
///   text cannot reach AA on it.
/// * **I8 hierarchy** — distinct authored text colours stay distinct, in order.
class KdmEngine {
  /// Tuning constants.
  final KdmEngineConfig config;

  /// The page background the content sits on.
  final KdmColor pageBackground;

  /// Whether the target mode is dark. In light mode every method is an
  /// identity transform.
  final bool isDark;

  /// Creates an engine for one page background and mode.
  const KdmEngine({
    required this.pageBackground,
    required this.isDark,
    this.config = KdmEngineConfig.standard,
  });

  /// Classifies [authored] without transforming it. Exposed so a linter or a
  /// diagnostics overlay can explain a decision.
  ///
  /// **Known limitation — ordering across the passthrough boundary.**
  /// Remapped surfaces land in a narrow band *below*
  /// [KdmEngineConfig.darkPassthroughOkL], while a surface at or below that
  /// threshold keeps its authored lightness. The two output ranges overlap, and
  /// inside the overlap the order can reverse:
  ///
  ///     #808080 -> #282828   (remapped)
  ///     #333333 -> #333333   (passthrough)   <- the darker input, lighter out
  ///
  /// This is not a tuning problem. Tying the passthrough edge to the remap
  /// floor removes the overlap — and breaks idempotence (I4), because mapped
  /// values then sit above the threshold and are remapped when fed back in.
  /// Idempotence requires the function to be the identity on its own output
  /// range, which a strictly increasing map that moves light colours down into
  /// that range cannot be. I4 is kept: a document can be converted twice, while
  /// the reversal needs a template that places a mid grey beside a dark grey.
  KdmSurfaceKind classify(KdmColor authored) {
    if (!isDark) return KdmSurfaceKind.lightMode;
    if (authored.okL <= config.darkPassthroughOkL) return KdmSurfaceKind.alreadyDark;
    if (authored.okC >= config.brandFillMinChroma) return KdmSurfaceKind.brandFill;
    return KdmSurfaceKind.remapped;
  }

  /// Maps an authored background into the target mode.
  ///
  /// [authored] must already be composited over its backdrop if it was
  /// translucent — use [KdmColor.over]. [parent] is the mapped background of
  /// the nearest ancestor that paints one, and [parentAuthored] that
  /// ancestor's authored colour; together they drive I1 and I6.
  KdmSurfaceResult mapSurface(KdmColor authored, {KdmColor? parent, KdmColor? parentAuthored}) {
    final kind = classify(authored);
    if (kind != KdmSurfaceKind.remapped) return KdmSurfaceResult(authored, kind);

    // I6: elevate only where the author drew a step. A nested element repeating
    // its parent's background is not a new surface, and treating it as one is
    // what turned a flat all-white email into a seven-rung staircase ending on
    // light grey. Table-based email nests four to eight deep as a matter of
    // course, so this is the common case, not an edge case.
    if (parent != null && parentAuthored != null && authored == parentAuthored) {
      return KdmSurfaceResult(parent, KdmSurfaceKind.inherited);
    }

    final hue = authored.okH;
    final chroma = _min(authored.okC * config.surfaceChromaFactor, config.surfaceChromaCap);

    // Increasing in authored lightness, so the author's own ordering survives.
    final t = ((authored.okL - config.darkPassthroughOkL) / (1.0 - config.darkPassthroughOkL)).clamp(0.0, 1.0);
    var lightness = pageBackground.okL + config.surfaceLiftOkL + t * config.surfaceRangeOkL;

    var result = _cappedSurface(lightness, chroma, hue);
    if (parent == null) return KdmSurfaceResult(result, kind);

    // I1: separate from the parent until the step is visible — but move in the
    // direction the author drew, not always upward, and only where the author
    // drew a visible step in the first place.
    //
    // Requiring every child to be *lighter* than its parent forced a recessed
    // inset and a raised card to the same place, which is how four distinct
    // sibling greys all arrived at one colour. Near black, 1.20:1 also costs a
    // large jump in lightness, so forcing every child to clear it flattens a
    // whole ramp onto one value. Two surfaces the author made barely different
    // should stay barely different.
    final authoredStep = parentAuthored == null ? null : KdmColor.contrast(authored, parentAuthored);
    if (authoredStep != null && authoredStep < config.surfaceSeparation) {
      return KdmSurfaceResult(result, kind);
    }

    final goLighter = parentAuthored == null || authored.okL >= parentAuthored.okL;
    final step = goLighter ? 0.005 : -0.005;
    var guard = 0;
    while (KdmColor.contrast(result, parent) < config.surfaceSeparation &&
        lightness < config.surfaceCeilingOkL &&
        lightness > 0.0 &&
        guard < 300) {
      lightness += step;
      guard++;
      final next = _cappedSurface(lightness, chroma, hue);
      if (next == result) break; // a cap has bitten; stop walking
      result = next;
    }
    return KdmSurfaceResult(result, kind);
  }

  /// Builds a surface, backing off lightness until it sits under
  /// [KdmEngineConfig.surfaceMaxLuminance] — the point past which light text
  /// can no longer reach AA on it (I7).
  KdmColor _cappedSurface(double l, double c, double h) {
    var lightness = l;
    var out = KdmColor.fromOkLch(lightness, c, h);
    var guard = 0;
    while (out.luminance > config.surfaceMaxLuminance && lightness > 0 && guard < 200) {
      lightness -= 0.004;
      guard++;
      out = KdmColor.fromOkLch(lightness, c, h);
    }
    return out;
  }

  /// Returns a foreground for [authored] that meets [minRatio] against
  /// [background].
  ///
  /// **I5: returns [authored] unchanged when it already passes.** The engine
  /// never "improves" a pair the author got right — doing so measurably
  /// degrades good templates (`#FFFFFF` on `#00695C` at 6.61:1 came back as
  /// `#D5D5D5` at 4.51:1 under an earlier design).
  ///
  /// On failure it keeps hue and chroma and inverts lightness onto the text
  /// ramp (I8); only if that misses does it search for a passing value.
  KdmColor solveForeground(KdmColor authored, KdmColor background, {double? minRatio}) {
    if (!isDark) return authored;
    final target = minRatio ?? config.textContrast;
    if (KdmColor.contrast(authored, background) >= target) return authored;

    final hue = authored.okH;
    final chroma = authored.okC;

    // Step 1 — invert. A monotonic map from authored lightness onto the dark
    // ramp, so six authored greys stay six distinct greys and black lands near
    // white, the way every mature mail client renders it.
    final inverted = KdmColor.fromOkLch(
      config.textFloorOkL + (1.0 - authored.okL) * config.textRangeOkL,
      chroma,
      hue,
    );
    if (KdmColor.contrast(inverted, background) >= target) return inverted;

    // Step 2 — repair, only if the inverted value misses. Walk away from the
    // background rather than toward it, so corrected text stays on the side of
    // the ramp the inversion put it on.
    final preferLighter = background.luminance < config.surfaceMaxLuminance;
    var l = inverted.okL;
    for (var i = 0; i < 400; i++) {
      l += preferLighter ? 0.0025 : -0.0025;
      if (l <= 0.0 || l >= 1.0) break;
      final candidate = KdmColor.fromOkLch(l, chroma, hue);
      if (KdmColor.contrast(candidate, background) >= target) return candidate;
    }

    // Step 3 — nothing at this hue and chroma works. Fall back to the extreme
    // on the side the backdrop calls for.
    return preferLighter ? KdmColor.white : KdmColor.black;
  }

  /// Contrast target for text of [fontSizePx], accounting for the WCAG
  /// large-text allowance.
  double targetFor({required double fontSizePx, required bool bold}) {
    final isLarge = fontSizePx >= 24 || (bold && fontSizePx >= 18.66);
    return isLarge ? config.largeTextContrast : config.textContrast;
  }

  /// Borders move *toward* the page background in dark mode — the opposite of
  /// text. A subtle light hairline must stay subtle, not become a bright line.
  KdmColor mapBorder(KdmColor authored, KdmColor background) {
    if (!isDark) return authored;
    if (authored.okL <= config.darkPassthroughOkL) return authored;
    if (classify(authored) == KdmSurfaceKind.brandFill) return authored;
    // Sit a fixed perceptual step above the surface it divides, never below it.
    final target = _min(background.okL + 0.10, 0.55);
    return KdmColor.fromOkLch(target, _min(authored.okC, config.surfaceChromaCap), authored.okH, authored.a);
  }

  /// Shadows darken in dark mode rather than lightening — a light shadow on a
  /// dark page reads as a glow.
  KdmColor mapShadow(KdmColor authored) {
    if (!isDark) return authored;
    return KdmColor.fromOkLch(
      authored.okL * 0.35,
      _min(authored.okC, config.surfaceChromaCap),
      authored.okH,
      authored.a,
    );
  }

  static double _min(double a, double b) => a < b ? a : b;
}
