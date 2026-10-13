import 'dart:convert';
import 'dart:io';

import 'package:k_html_dark_mode/k_html_dark_mode.dart';
import 'package:test/test.dart';

/// Holds the Dart engine to the committed golden vectors.
///
/// The same file holds the shipped JavaScript to the same answers (see
/// tool/node). A failure here means the engine's behaviour changed: if that
/// was intended, regenerate with `dart run tool/generate_vectors.dart`, review
/// the diff, and record it in CHANGELOG.md.
void main() {
  final vectors = jsonDecode(File('test/golden/vectors.json').readAsStringSync()) as Map<String, dynamic>;
  List<Map<String, dynamic>> cases(String key) => (vectors[key] as List).cast<Map<String, dynamic>>();

  final page = KdmColor.tryHex(vectors['page'] as String)!;
  final engine = KdmEngine(pageBackground: page, isDark: true);
  KdmColor hex(String s) => KdmColor.tryHex(s)!;
  KdmColor? maybe(Object? s) => s == null ? null : hex(s as String);

  test('the vectors were generated with the shipped configuration', () {
    expect(vectors['config'], KdmEngineConfig.standard.toJson());
  });

  test('classify', () {
    for (final c in cases('classify')) {
      expect(engine.classify(hex(c['input'] as String)).name, c['expected'], reason: '${c['input']}');
    }
  });

  test('mapSurface', () {
    for (final c in cases('mapSurface')) {
      final got = engine
          .mapSurface(hex(c['input'] as String), parent: maybe(c['parent']), parentAuthored: maybe(c['parentAuthored']))
          .color
          .toHex();
      expect(got, c['expected'], reason: '$c');
    }
  });

  test('solveForeground', () {
    for (final c in cases('solveForeground')) {
      final got = engine
          .solveForeground(hex(c['input'] as String), hex(c['background'] as String),
              minRatio: (c['target'] as num).toDouble())
          .toHex();
      expect(got, c['expected'], reason: '$c');
    }
  });

  test('mapShadow', () {
    for (final c in cases('mapShadow')) {
      expect(engine.mapShadow(hex(c['input'] as String)).toHex(), c['expected'], reason: '$c');
    }
  });

  test('mapBorder', () {
    for (final c in cases('mapBorder')) {
      expect(engine.mapBorder(hex(c['input'] as String), hex(c['background'] as String)).toHex(), c['expected'],
          reason: '$c');
    }
  });

  test('composite', () {
    for (final c in cases('composite')) {
      final got = hex(c['input'] as String)
          .withAlpha((c['alpha'] as num).toDouble())
          .over(hex(c['backdrop'] as String))
          .toHex();
      expect(got, c['expected'], reason: '$c');
    }
  });

  test('targetFor', () {
    for (final c in cases('targetFor')) {
      expect(engine.targetFor(fontSizePx: (c['px'] as num).toDouble(), bold: c['bold'] as bool), c['expected'],
          reason: '$c');
    }
  });
}
