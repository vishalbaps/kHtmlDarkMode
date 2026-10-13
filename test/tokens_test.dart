import 'package:k_html_dark_mode/k_html_dark_mode.dart';
import 'package:test/test.dart';

/// The token table's contrast guarantee, re-derived from the fixed palettes.
void main() {
  final light = KdmTokens.from(KdmPalette.light);
  final dark = KdmTokens.from(KdmPalette.dark);

  test('the precomputed tables are exactly what the palette derives, in order', () {
    // Order matters: it is the order the CSS block is emitted in.
    expect(KdmTokens.defaultLight.values.entries.map((e) => '${e.key}: ${e.value}').toList(),
        light.values.entries.map((e) => '${e.key}: ${e.value}').toList());
    expect(KdmTokens.defaultDark.values.entries.map((e) => '${e.key}: ${e.value}').toList(),
        dark.values.entries.map((e) => '${e.key}: ${e.value}').toList());
    expect(KdmTokens.defaultLight.isDark, isFalse);
    expect(KdmTokens.defaultDark.isDark, isTrue);
  });

  test('the built-in palettes use the precomputed tables', () {
    expect(identical(KHtmlDarkMode.tokens(), KdmTokens.defaultDark), isTrue);
    expect(identical(KHtmlDarkMode.tokens(isDark: false), KdmTokens.defaultLight), isTrue);
  });

  test('no token pair violates AA in either mode', () {
    expect(light.validate(), isEmpty, reason: 'light: ${light.validate()}');
    expect(dark.validate(), isEmpty, reason: 'dark: ${dark.validate()}');
  });

  test('surfaces and text match the published table', () {
    // Published in README.md. If a palette change moves these, the README has
    // to move with it — that is the point of asserting them.
    expect(light.values['--kdm-bg'], '#FFFFFF');
    expect(light.values['--kdm-surface'], '#F6F6F9');
    expect(light.values['--kdm-surface-2'], '#ECECF2');
    expect(light.values['--kdm-surface-3'], '#CECEDA');
    expect(light.values['--kdm-fg'], '#141417');
    expect(light.values['--kdm-fg-muted'], '#62626C');
    expect(light.values['--kdm-border'], '#ECECF2');
    expect(light.values['--kdm-border-strong'], '#CECEDA');

    expect(dark.values['--kdm-bg'], '#181A1B');
    expect(dark.values['--kdm-surface'], '#232328');
    expect(dark.values['--kdm-surface-2'], '#2E2F35');
    expect(dark.values['--kdm-surface-3'], '#35353B');
    expect(dark.values['--kdm-fg'], '#F6F6F9');
    expect(dark.values['--kdm-fg-muted'], '#B1B1BD');
    expect(dark.values['--kdm-border'], '#35353B');
    expect(dark.values['--kdm-border-strong'], '#484851');
  });

  test('solid fills keep the brand colour in both modes', () {
    for (final name in KdmTokens.accents) {
      expect(light.values['--kdm-$name-fill'], dark.values['--kdm-$name-fill'],
          reason: '$name fill must not change between modes');
    }
    expect(light.values['--kdm-accent-fill'], '#006851');
    expect(light.values['--kdm-accent-fill-fg'], '#FFFFFF');
  });

  test('soft tints stay distinct from the surface they sit on', () {
    KdmColor at(KdmTokens t, String k) => KdmColor.tryHex(t.values[k]!)!;
    for (final name in KdmTokens.accents) {
      expect(KdmColor.contrast(at(light, '--kdm-$name-soft'), at(light, '--kdm-surface')), greaterThan(1.02),
          reason: 'light $name soft vs surface');
      expect(KdmColor.contrast(at(dark, '--kdm-$name-soft'), at(dark, '--kdm-surface')), greaterThan(1.02),
          reason: 'dark $name soft vs surface');
    }
  });

  test("the emitted CSS block outranks a template's :root fallbacks", () {
    final css = dark.toCssBlock();
    expect(css, startsWith('html[data-kdm-theme="dark"] {'));
    expect(css, contains('--kdm-bg: #181A1B;'));
    // Specificity 0,1,1 beats :root at 0,1,0.
    expect(css, isNot(contains(':root')));
    expect(light.toCssBlock(), startsWith('html[data-kdm-theme="light"] {'));
  });

  test('every documented token is emitted', () {
    const neutrals = [
      '--kdm-bg',
      '--kdm-surface',
      '--kdm-surface-2',
      '--kdm-surface-3',
      '--kdm-fg',
      '--kdm-fg-muted',
      '--kdm-fg-subtle',
      '--kdm-border',
      '--kdm-border-strong',
    ];
    for (final t in neutrals) {
      expect(light.values.containsKey(t), isTrue, reason: 'missing $t');
      expect(dark.values.containsKey(t), isTrue, reason: 'missing $t');
    }
    for (final n in KdmTokens.accents) {
      for (final suffix in ['', '-fill', '-fill-fg', '-soft', '-soft-fg']) {
        expect(light.values.containsKey('--kdm-$n$suffix'), isTrue, reason: 'missing --kdm-$n$suffix');
      }
    }
    expect(light.values.length, 29);
    expect(dark.values.length, 29);
  });

  group('page background override', () {
    test('common dark app backgrounds keep every guarantee', () {
      for (final bg in ['#000000', '#121212', '#1E1E1E', '#101418', '#202124']) {
        final t = KHtmlDarkMode.tokens(isDark: true, pageBackground: bg);
        expect(t.values['--kdm-bg'], bg);
        expect(t.validate(), isEmpty, reason: '$bg: ${t.validate()}');
      }
    });

    test('common light app backgrounds keep every guarantee', () {
      for (final bg in ['#FFFFFF', '#FAFAFA', '#F5F5F5', '#F2F2F7']) {
        final t = KHtmlDarkMode.tokens(isDark: false, pageBackground: bg);
        expect(t.validate(), isEmpty, reason: '$bg: ${t.validate()}');
      }
    });

    test('a background that does not suit the mode is rejected', () {
      expect(() => KHtmlDarkMode.tokens(isDark: true, pageBackground: '#FFFFFF'), throwsArgumentError);
      expect(() => KHtmlDarkMode.tokens(isDark: true, pageBackground: '#808080'), throwsArgumentError);
      expect(() => KHtmlDarkMode.tokens(isDark: false, pageBackground: '#181A1B'), throwsArgumentError);
      expect(() => KHtmlDarkMode.tokens(isDark: true, pageBackground: 'black'), throwsArgumentError);
      expect(() => KHtmlDarkMode.tokens(isDark: true, pageBackground: '#00000080'), throwsArgumentError);
    });
  });

  group('KdmColor extras', () {
    test('fromRgb matches tryHex', () {
      expect(const KdmColor.fromRgb(0x181A1B), KdmColor.tryHex('#181A1B'));
      expect(const KdmColor.fromRgb(0x006851).toHex(), '#006851');
    });

    test('toArgb packs alpha first, ready for Flutter Color(int)', () {
      expect(const KdmColor.fromRgb(0x181A1B).toArgb(), 0xFF181A1B);
      expect(KdmColor.tryHex('#11223380')!.toArgb(), 0x80112233);
    });
  });
}
