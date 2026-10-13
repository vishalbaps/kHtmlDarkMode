import 'package:k_html_dark_mode/k_html_dark_mode.dart';
import 'package:test/test.dart';

/// Invariant tests for the colour engine.
///
/// These assert *behaviour*, never the tuning constants — a constant may be
/// retuned, but the invariants must survive it. The U-numbers are stable ids
/// carried over from the engine's original suite, so a failure can be traced
/// back to the defect each one was written for.
void main() {
  // KdmPalette.dark.background
  final darkPage = KdmColor.tryHex('#181A1B')!;
  final lightPage = KdmColor.tryHex('#FFFFFF')!;

  final dark = KdmEngine(pageBackground: darkPage, isDark: true);
  final light = KdmEngine(pageBackground: lightPage, isDark: false);

  KdmColor hex(String s) => KdmColor.tryHex(s)!;
  double ratio(KdmColor a, KdmColor b) => KdmColor.contrast(a, b);

  group('KdmColor', () {
    test('parses every hex form, and rejects the rest', () {
      expect(hex('#abc').toHex(), '#AABBCC');
      expect(hex('abc').toHex(), '#AABBCC');
      expect(hex('#AABBCC').toHex(), '#AABBCC');
      expect(hex('#AABBCCFF').toHex(), '#AABBCC');
      expect(hex('#AABBCC80').a, closeTo(0.502, 0.01));
      expect(hex('#abcd').a, closeTo(0.867, 0.01));

      for (final bad in ['', '#', '#zz', '#12345', 'rgb(1,2,3)', 'white', 'var(--x)']) {
        expect(KdmColor.tryHex(bad), isNull, reason: 'should not parse "$bad"');
      }
    });

    test('contrast matches known WCAG values and is symmetric', () {
      expect(ratio(KdmColor.white, KdmColor.black), closeTo(21.0, 0.01));
      expect(ratio(KdmColor.black, KdmColor.white), closeTo(21.0, 0.01));
      expect(ratio(KdmColor.white, KdmColor.white), closeTo(1.0, 0.001));
      // The accent fill / fill-fg token pair.
      expect(ratio(KdmColor.white, hex('#006851')), closeTo(6.78, 0.05));
    });

    test('OKLCh round-trips within a rounding step', () {
      for (final s in ['#DEE8D5', '#2F5D3A', '#1976D2', '#181A1B', '#FFFFFF', '#000000']) {
        final c = hex(s);
        final back = KdmColor.fromOkLch(c.okL, c.okC, c.okH);
        expect(back.toHex(), s.toUpperCase(), reason: 'round-trip failed for $s');
      }
    });

    test('composites translucent colours over a backdrop', () {
      final overlay = KdmColor.tryHex('#80808080')!.withAlpha(0.12);
      expect(overlay.over(lightPage).toHex(), '#F0F0F0');
      expect(overlay.over(darkPage).toHex(), '#242627');
    });
  });

  group('light mode is an identity transform', () {
    test('every entry point returns its input unchanged', () {
      for (final s in ['#DEE8D5', '#2F5D3A', '#FFFFFF', '#000000', '#1976D2', '#14211F']) {
        final c = hex(s);
        expect(light.mapSurface(c).color, c, reason: 'mapSurface changed $s');
        expect(light.solveForeground(c, lightPage), c, reason: 'solveForeground changed $s');
        expect(light.mapBorder(c, lightPage), c, reason: 'mapBorder changed $s');
        expect(light.classify(c), KdmSurfaceKind.lightMode);
      }
    });
  });

  group('U-1/U-2: the reported bug is fixed', () {
    test('the Commons surface chain is remapped, monotonic and separated', () {
      const authoredChain = ['#F0EDE4', '#FBF9F0', '#DEE8D5'];
      final wrapper = dark.mapSurface(hex('#F0EDE4'), parent: darkPage);
      final card = dark.mapSurface(hex('#FBF9F0'), parent: wrapper.color, parentAuthored: hex('#F0EDE4'));
      final chip = dark.mapSurface(hex('#DEE8D5'), parent: card.color, parentAuthored: hex('#FBF9F0'));

      for (final r in [wrapper, card, chip]) {
        expect(r.kind, KdmSurfaceKind.remapped);
      }

      // I1: each step stays visibly distinct from its parent, and moves in the
      // direction the author drew. Requiring every child to be *lighter* than
      // its parent — as this test used to — is what flattened sibling ramps:
      // a recessed inset and a raised card were forced to the same place.
      final chain = [darkPage, wrapper.color, card.color, chip.color];

      // The first step has no authored parent to compare against, so the
      // guarantee is unconditional there.
      expect(ratio(chain[0], chain[1]), greaterThanOrEqualTo(1.20),
          reason: 'the outermost surface must clear the page');

      for (var i = 1; i < authoredChain.length; i++) {
        final a = hex(authoredChain[i - 1]);
        final b = hex(authoredChain[i]);

        // Separation is owed only where the author drew a visible step. Forcing
        // it everywhere is what flattened ramps: #F0EDE4 and #FBF9F0 are 1.05:1
        // apart as authored, and should stay that subtle.
        if (ratio(a, b) >= dark.config.surfaceSeparation) {
          expect(ratio(chain[i], chain[i + 1]), greaterThanOrEqualTo(1.20),
              reason: '${authoredChain[i - 1]} -> ${authoredChain[i]} was a visible step');
        }

        // Ordering survives either way.
        expect(chain[i + 1].luminance > chain[i].luminance, b.okL > a.okL,
            reason: '${authoredChain[i - 1]} -> ${authoredChain[i]}: ordering must survive');
      }

      // I2: the chip text that measured 1.14:1 before now passes.
      final chipText = dark.solveForeground(hex('#2F5D3A'), chip.color);
      expect(ratio(chipText, chip.color), greaterThanOrEqualTo(4.5));

      // Hue survives: sage stays sage.
      expect(chipText.okH, closeTo(hex('#2F5D3A').okH, 2.0));
      expect(chip.color.okH, closeTo(hex('#DEE8D5').okH, 2.0));
    });

    test('all Commons text passes on its mapped surface', () {
      final card = dark.mapSurface(hex('#FBF9F0'), parent: darkPage).color;
      for (final s in ['#2C5530', '#4A4A45', '#C1502E', '#222222']) {
        final solved = dark.solveForeground(hex(s), card);
        expect(ratio(solved, card), greaterThanOrEqualTo(4.5), reason: 'text $s on card');
        expect(solved.okH, closeTo(hex(s).okH, 2.0), reason: 'hue drift for $s');
      }
    });
  });

  group('U-3: passthrough boundary (I3)', () {
    test('already-dark backgrounds are returned untouched', () {
      for (final s in ['#181A1B', '#232328', '#2E2F35', '#000000', '#1B3231', '#14211F']) {
        final r = dark.mapSurface(hex(s), parent: darkPage);
        expect(r.color, hex(s), reason: '$s must be unchanged');
        expect(r.unchanged, isTrue);
      }
    });

    test('a neutral colour either side of the threshold is classified correctly', () {
      // Achromatic, so the brand-fill rule cannot apply — this isolates okL.
      final below = KdmColor.fromOkLch(dark.config.darkPassthroughOkL - 0.02, 0, 0);
      final above = KdmColor.fromOkLch(dark.config.darkPassthroughOkL + 0.05, 0, 0);
      expect(dark.classify(below), KdmSurfaceKind.alreadyDark);
      expect(dark.classify(above), KdmSurfaceKind.remapped);
    });
  });

  group('U-20: a brand ramp survives intact (I5)', () {
    // The regression this group exists for: an okL ceiling of 0.80 split this
    // ramp down the middle, keeping #ff9800 (okL 0.770) and turning #ffb300
    // (okL 0.818) into a muddy olive — same ramp, same chroma, 0.05 apart.
    test('every step of a warm brand ramp is left alone', () {
      for (final s in ['#e65100', '#f57c00', '#ff9800', '#ffb300', '#ffd25a', '#ffeb3b']) {
        final r = dark.mapSurface(hex(s), parent: darkPage);
        expect(r.kind, KdmSurfaceKind.brandFill, reason: '$s must read as a brand fill');
        expect(r.color, hex(s), reason: '$s must be byte-identical');
      }
    });

    test('pale tints are still remapped, however light', () {
      for (final s in ['#fdf3ff', '#fff2cc', '#eef6ff', '#fff0f3', '#fff3c4', '#eee0f5']) {
        expect(dark.classify(hex(s)), KdmSurfaceKind.remapped, reason: '$s is a tint, not a brand fill');
      }
    });
  });

  group('U-21: repeated backgrounds do not invent elevation (I6)', () {
    test('a chain of identical authored backgrounds stays flat', () {
      var parent = darkPage;
      final seen = <String>{};
      for (var depth = 0; depth < 8; depth++) {
        final r = dark.mapSurface(KdmColor.white,
            parent: parent, parentAuthored: depth == 0 ? hex('#EEF0F4') : KdmColor.white);
        seen.add(r.color.toHex());
        parent = r.color;
      }
      expect(seen.length, 1, reason: 'eight nested identical surfaces produced ${seen.length} colours: $seen');
    });

    test('a genuinely different nested background still separates', () {
      final card = dark.mapSurface(KdmColor.white, parent: darkPage).color;
      final inner = dark.mapSurface(hex('#CCCCCC'), parent: card, parentAuthored: KdmColor.white);
      expect(inner.kind, KdmSurfaceKind.remapped);
      expect(KdmColor.contrast(inner.color, card), greaterThanOrEqualTo(dark.config.surfaceSeparation - 0.01),
          reason: 'an authored step of 1.61:1 must stay visible');
    });
  });

  group('U-22: no mapped surface strands its own text (I7)', () {
    test('every remapped surface stays under the luminance wall', () {
      // Above ~0.183 even white cannot reach 4.5:1, so the solver is forced
      // into near-black and a panel renders black-on-grey in a dark theme.
      var parent = darkPage;
      for (var depth = 0; depth < 10; depth++) {
        final r = dark.mapSurface(KdmColor.white, parent: parent);
        expect(r.color.luminance, lessThanOrEqualTo(dark.config.surfaceMaxLuminance + 0.001),
            reason: 'depth $depth produced ${r.color.toHex()}');
        final solved = dark.solveForeground(hex('#777777'), r.color);
        expect(solved.luminance, greaterThan(r.color.luminance),
            reason: 'text on ${r.color.toHex()} came back darker than its surface');
        parent = r.color;
      }
    });
  });

  group('U-23: a text ramp keeps its hierarchy (I8)', () {
    test('six authored greys remain six distinct colours', () {
      final card = dark.mapSurface(KdmColor.white, parent: darkPage).color;
      final ramp = ['#000000', '#212121', '#333333', '#555555', '#6e6e6e', '#8c8c8c'];
      final out = ramp.map((s) => dark.solveForeground(hex(s), card)).toList();
      expect(out.map((c) => c.toHex()).toSet().length, ramp.length,
          reason: 'collapsed to ${out.map((c) => c.toHex()).toSet()}');
      // ...and in the right order: darker authored means lighter on a dark card.
      for (var i = 1; i < out.length; i++) {
        expect(out[i].luminance, lessThan(out[i - 1].luminance),
            reason: '${ramp[i]} should be dimmer than ${ramp[i - 1]}');
      }
    });

    test('one authored colour maps to one output, whatever the font size', () {
      final card = dark.mapSurface(KdmColor.white, parent: darkPage).color;
      final large = dark.solveForeground(hex('#2b1055'), card, minRatio: 3.0);
      final normal = dark.solveForeground(hex('#2b1055'), card, minRatio: 4.5);
      expect(large, normal, reason: 'the large-text allowance must not make a 20px heading dimmer than an 18px one');
    });
  });

  group('U-4: idempotence (I4)', () {
    test('mapping twice equals mapping once', () {
      for (final s in ['#F0EDE4', '#DEE8D5', '#FBF9F0', '#EEEEEE', '#FFFFFF']) {
        final once = dark.mapSurface(hex(s)).color;
        final twice = dark.mapSurface(once).color;
        expect(twice, once, reason: 'not stable for $s');
      }
    });
  });

  group('U-5: deep nesting cannot run away', () {
    test('nested identical whites do not climb at all', () {
      // This used to assert the opposite — that each level must be lighter —
      // which is precisely the staircase the engine was building. Seven nested
      // #ffffff tables rendered as seven distinct greys ending on #868686, a
      // light panel in a dark theme, from markup that authored one flat white.
      var parent = darkPage;
      var authoredParent = hex('#EEF0F4');
      final produced = <String>[];
      for (var depth = 0; depth < 7; depth++) {
        final next = dark.mapSurface(KdmColor.white, parent: parent, parentAuthored: authoredParent);
        produced.add(next.color.toHex());
        parent = next.color;
        authoredParent = KdmColor.white;
      }
      expect(produced.toSet().length, 1, reason: 'climbed through $produced');
    });

    test('even without authored context, nesting stays bounded', () {
      // The degraded path: no parentAuthored, so I6 cannot apply. It must still
      // never strand text on a mid-grey panel.
      var parent = darkPage;
      for (var depth = 0; depth < 10; depth++) {
        final next = dark.mapSurface(KdmColor.white, parent: parent).color;
        expect(next.okL, lessThanOrEqualTo(dark.config.surfaceCeilingOkL + 0.01),
            reason: 'depth $depth exceeded the ceiling');
        expect(next.luminance, lessThanOrEqualTo(dark.config.surfaceMaxLuminance + 0.001),
            reason: 'depth $depth crossed the luminance wall');
        parent = next;
      }
    });
  });

  group('U-17: a correctly-authored template is untouched (I5)', () {
    // Every fill/text pair from a hand-authored, already dark-safe template.
    const authored = <String, String>{
      '#00695C': '#FFFFFF', // gradient stop
      '#006851': '#FFFFFF', // gradient stop / primary button
      '#0B5FA5': '#FFFFFF', // gradient stop
      '#2E7D32': '#FFFFFF', // badge: on track
      '#B34700': '#FFFFFF', // badge: needs review
      '#C62828': '#FFFFFF', // badge: blocked
      '#1976D2': '#FFFFFF', // badge: info
      '#14211F': '#FFFFFF', // intentionally dark panel
    };

    test('every authored fill and its text is returned byte-identical', () {
      authored.forEach((fill, text) {
        final surface = dark.mapSurface(hex(fill), parent: darkPage);
        expect(surface.color, hex(fill), reason: 'fill $fill was changed');
        expect(surface.unchanged, isTrue, reason: 'fill $fill was reclassified');

        final solved = dark.solveForeground(hex(text), surface.color);
        expect(solved, hex(text), reason: 'text $text on $fill was changed');
        expect(ratio(solved, surface.color), greaterThanOrEqualTo(4.5), reason: '$text on $fill should already pass');
      });
    });

    test('translucent neutral surfaces pass through once composited', () {
      for (final alpha in [0.12, 0.14, 0.18]) {
        final composited = hex('#808080').withAlpha(alpha).over(darkPage);
        final surface = dark.mapSurface(composited, parent: darkPage);
        expect(surface.unchanged, isTrue, reason: 'rgba grey at $alpha should pass through');

        final bodyText = dark.solveForeground(hex('#F6F6F9'), surface.color);
        expect(bodyText, hex('#F6F6F9'), reason: 'body text should not be touched');
        expect(ratio(bodyText, surface.color), greaterThan(7.0));
      }
      // The amber highlight composites to a dark olive and must also survive.
      final highlight = hex('#FFC107').withAlpha(0.30).over(darkPage);
      expect(dark.mapSurface(highlight, parent: darkPage).unchanged, isTrue);
    });

    test('accent text on the dark page IS corrected — it fails as authored', () {
      // The author's "dual-safe" set is only safe because a transform lightens
      // it. Verify both halves of that claim.
      for (final s in ['#006851', '#00695C', '#1976D2', '#2E7D32']) {
        expect(ratio(hex(s), darkPage), lessThan(4.5),
            reason: '$s should fail as authored, else the test proves nothing');
        final solved = dark.solveForeground(hex(s), darkPage);
        expect(ratio(solved, darkPage), greaterThanOrEqualTo(4.5), reason: '$s solved');
        expect(solved.okH, closeTo(hex(s).okH, 2.0), reason: '$s hue drift');
      }
    });

    test('a white background-color becomes a visible surface, not the page', () {
      // Old engine collapsed #FFFFFF onto the page background exactly, so white
      // cards vanished. That workaround is what the authored template's rule #1
      // exists for.
      final mapped = dark.mapSurface(KdmColor.white, parent: darkPage).color;
      expect(mapped, isNot(darkPage));
      expect(ratio(mapped, darkPage), greaterThanOrEqualTo(1.20));
    });
  });

  group('U-18: solveForeground no-op boundary', () {
    test('at or above the target is unchanged; below is solved', () {
      final bg = hex('#232328');
      // Search a hue ramp for colours straddling the 4.5 boundary.
      KdmColor? justAbove, justBelow;
      for (var i = 0; i <= 400; i++) {
        final c = KdmColor.fromOkLch(i / 400, 0.05, 150);
        final r = ratio(c, bg);
        if (r >= 4.5 && r < 4.7) justAbove ??= c;
        if (r < 4.5 && r > 4.3) justBelow = c;
      }
      expect(justAbove, isNotNull);
      expect(justBelow, isNotNull);

      expect(dark.solveForeground(justAbove!, bg), justAbove, reason: 'a passing colour must not be touched');
      final fixed = dark.solveForeground(justBelow!, bg);
      expect(fixed, isNot(justBelow));
      expect(ratio(fixed, bg), greaterThanOrEqualTo(4.5));
    });

    test('large text uses the 3:1 allowance', () {
      expect(dark.targetFor(fontSizePx: 16, bold: false), 4.5);
      expect(dark.targetFor(fontSizePx: 24, bold: false), 3.0);
      expect(dark.targetFor(fontSizePx: 19, bold: true), 3.0);
      expect(dark.targetFor(fontSizePx: 19, bold: false), 4.5);
    });
  });

  group('U-19: brand-fill classification', () {
    test('chromatic mid-tones are brand fills; achromatic light ones are surfaces', () {
      for (final s in ['#00695C', '#006851', '#0B5FA5', '#2E7D32', '#B34700', '#C62828', '#1976D2']) {
        expect(dark.classify(hex(s)), KdmSurfaceKind.brandFill, reason: '$s should be a brand fill');
      }
      for (final s in ['#EEEEEE', '#F6F6F9', '#FFFFFF', '#DEE8D5', '#FBF9F0']) {
        expect(dark.classify(hex(s)), KdmSurfaceKind.remapped, reason: '$s should be remapped');
      }
    });

    test('#808080 — documented boundary case', () {
      // Achromatic and OKL just above the brand-fill ceiling, so it is treated
      // as a surface. Asserted explicitly so a constant change is visible.
      final grey = hex('#808080');
      expect(grey.okC, lessThan(dark.config.brandFillMinChroma));
      expect(dark.classify(grey), KdmSurfaceKind.remapped);
    });
  });

  group('U-11: borders and shadows move opposite to text', () {
    test('a light hairline dims instead of brightening', () {
      final surface = hex('#232328');
      final border = dark.mapBorder(hex('#CCCCCC'), surface);
      // Old engine produced #E6E6E6 — brighter than authored. Must not happen.
      expect(border.luminance, lessThan(hex('#CCCCCC').luminance));
      // Still visible against the surface it divides.
      expect(border.luminance, greaterThan(surface.luminance));
    });

    test('shadows darken', () {
      final shadow = dark.mapShadow(hex('#888888'));
      expect(shadow.okL, lessThan(hex('#888888').okL));
    });
  });
}
