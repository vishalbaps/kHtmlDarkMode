import 'dart:io';

import 'package:k_html_dark_mode/k_html_dark_mode.dart';
import 'package:test/test.dart';

/// Invariants checked against the colours of **real templates**, rather than a
/// hand-picked list.
///
/// Unit tests pick their own inputs, which is how six defects once survived a
/// green suite: the only "real" fixture was a hand-authored best case with no
/// white background at all. The probe files contain the colour shapes that
/// actually break things — nested whites, sibling grey ramps, a saturated warm
/// ramp, a gradient ending pale, mid greys beside dark greys.
///
/// Deliberately property-based rather than golden hexes: goldens over a whole
/// template are rewritten on every tuning change, which makes them noise. The
/// exact values are pinned separately by the golden vectors.
void main() {
  const page = KdmColor.fromRgb(0x181A1B);
  const dark = KdmEngine(pageBackground: page, isDark: true);
  const light = KdmEngine(pageBackground: KdmColor.white, isDark: false);

  final dir = Directory('test/fixtures/templates');
  final templates = dir.listSync().whereType<File>().where((f) => f.uri.pathSegments.last.startsWith('probe-')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  /// Every distinct colour literal in the markup, hex or rgb()/rgba().
  Set<KdmColor> coloursIn(String html) {
    final out = <KdmColor>{};
    for (final m in RegExp(r'#[0-9a-fA-F]{3,8}\b').allMatches(html)) {
      final c = KdmColor.tryHex(m.group(0)!);
      if (c != null) out.add(c);
    }
    for (final m in RegExp(r'rgba?\(\s*(\d+)[\s,]+(\d+)[\s,]+(\d+)').allMatches(html)) {
      out.add(KdmColor(
        int.parse(m.group(1)!) / 255,
        int.parse(m.group(2)!) / 255,
        int.parse(m.group(3)!) / 255,
      ));
    }
    return out;
  }

  test('the fixture corpus is actually present', () {
    expect(templates, hasLength(greaterThanOrEqualTo(2)), reason: 'no probes in ${dir.path}');
    for (final f in templates) {
      expect(coloursIn(f.readAsStringSync()).length, greaterThan(5),
          reason: '${f.path} yielded too few colours to be a useful corpus');
    }
  });

  for (final file in templates) {
    final name = file.uri.pathSegments.last;
    final colours = coloursIn(file.readAsStringSync());

    group(name, () {
      test('light mode changes nothing', () {
        for (final c in colours) {
          expect(light.mapSurface(c).color, c);
          expect(light.solveForeground(c, KdmColor.white), c);
          expect(light.mapBorder(c, KdmColor.white), c);
        }
      });

      test('no *invented* surface strands its own text (I7)', () {
        for (final c in colours) {
          final r = dark.mapSurface(c, parent: page);
          // The wall applies only to surfaces the engine invents. A brand fill
          // passes through by design and may legitimately be bright — black
          // text on orange is the correct answer there, not a defect.
          if (r.unchanged) continue;
          expect(r.color.luminance, lessThanOrEqualTo(dark.config.surfaceMaxLuminance + 0.001),
              reason: '${c.toHex()} mapped to ${r.color.toHex()}, above the wall');
          final text = dark.solveForeground(KdmColor.black, r.color);
          expect(text.luminance, greaterThan(r.color.luminance),
              reason: 'text on ${r.color.toHex()} came back darker than its surface');
        }
      });

      test('mapping is idempotent (I4)', () {
        for (final c in colours) {
          final once = dark.mapSurface(c, parent: page).color;
          expect(dark.mapSurface(once, parent: page).color, once, reason: 'not stable for ${c.toHex()}');
        }
      });

      test('corrected text always meets its target (I2)', () {
        final surfaces = [page, dark.mapSurface(KdmColor.white, parent: page).color];
        for (final bg in surfaces) {
          for (final c in colours) {
            for (final target in [4.5, 3.0]) {
              final solved = dark.solveForeground(c, bg, minRatio: target);
              expect(KdmColor.contrast(solved, bg), greaterThanOrEqualTo(target - 0.01),
                  reason: '${c.toHex()} on ${bg.toHex()} solved to ${solved.toHex()}');
            }
          }
        }
      });

      test('saturated colours are never mistaken for tints (I5)', () {
        for (final c in colours) {
          if (c.okC < dark.config.brandFillMinChroma) continue;
          final r = dark.mapSurface(c, parent: page);
          expect(r.color, c, reason: '${c.toHex()} (okC ${c.okC.toStringAsFixed(3)}) was recoloured');
        }
      });
    });
  }

  test('the warm ramp in probe 1 survives end to end', () {
    // The ramp that used to snap in half at an okL 0.80 ceiling.
    const ramp = ['#e65100', '#f57c00', '#ff9800', '#ffb300', '#ffd25a', '#ffeb3b'];
    final html = File('test/fixtures/templates/probe-1-colours.html').readAsStringSync();
    for (final s in ramp) {
      expect(html.contains(s), isTrue, reason: '$s is missing from the probe');
      expect(dark.mapSurface(KdmColor.tryHex(s)!, parent: page).color, KdmColor.tryHex(s),
          reason: '$s must survive as a brand colour');
    }
  });
}
