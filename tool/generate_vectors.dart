// Regenerates test/golden/vectors.json from the Dart engine.
//
//     dart run tool/generate_vectors.dart
//
// The vectors are the contract between the two implementations of the colour
// maths: test/golden_vectors_test.dart holds the Dart engine to them, and
// tool/node/test/conformance.test.mjs holds the shipped JavaScript to them.
//
// Regenerate ONLY for an intended behaviour change. The diff of this file is
// the behaviour change: review it, note it in CHANGELOG.md, bump the minor.
import 'dart:convert';
import 'dart:io';

import 'package:k_html_dark_mode/k_html_dark_mode.dart';

const _target = 'test/golden/vectors.json';

void main() {
  const page = KdmColor.fromRgb(0x181A1B);
  const engine = KdmEngine(pageBackground: page, isDark: true);
  KdmColor hex(String s) => KdmColor.tryHex(s)!;

  // ---- classification -------------------------------------------------------
  const classifyInputs = [
    // brand fills from a hand-authored, already dark-safe template
    '#00695C', '#006851', '#0B5FA5', '#2E7D32', '#B34700', '#C62828', '#1976D2',
    // a warm brand ramp that a lightness ceiling used to split in half
    '#E65100', '#F57C00', '#FF9800', '#FFB300', '#FFD25A', '#FFEB3B',
    // already dark
    '#181A1B', '#232328', '#14211F', '#000000', '#333333',
    // light surfaces and pale tints
    '#FFFFFF', '#F0EDE4', '#FBF9F0', '#DEE8D5', '#EEEEEE', '#808080',
    '#FDF3FF', '#FFF2CC', '#EEF6FF', '#FFF3C4', '#EEF0F4',
  ];
  final classify = [
    for (final s in classifyInputs) {'input': s, 'expected': engine.classify(hex(s)).name},
  ];

  // ---- surface mapping, including the separation loop -----------------------
  final surfaces = <Map<String, Object?>>[];
  void surface(String input, KdmColor? parent, [String? parentAuthored]) {
    surfaces.add({
      'input': input,
      'parent': parent?.toHex(),
      'parentAuthored': parentAuthored,
      'expected': engine
          .mapSurface(hex(input), parent: parent, parentAuthored: parentAuthored == null ? null : hex(parentAuthored))
          .color
          .toHex(),
    });
  }

  for (final s in classifyInputs) {
    surface(s, null);
    surface(s, page);
  }
  // A chain where each step depends on the previous mapped value.
  var parent = page;
  for (final s in ['#F0EDE4', '#FBF9F0', '#DEE8D5']) {
    surface(s, parent);
    parent = engine.mapSurface(hex(s), parent: parent).color;
  }
  // Deep nesting without authored context drives the guard loop to its ceiling.
  parent = page;
  for (var i = 0; i < 5; i++) {
    surface('#FFFFFF', parent);
    parent = engine.mapSurface(KdmColor.white, parent: parent).color;
  }
  // I6: a repeated authored background reuses its parent.
  parent = page;
  var authoredParent = '#EEF0F4';
  for (var i = 0; i < 7; i++) {
    surface('#FFFFFF', parent, authoredParent);
    parent = engine.mapSurface(KdmColor.white, parent: parent, parentAuthored: hex(authoredParent)).color;
    authoredParent = '#FFFFFF';
  }
  // Conditional, direction-aware separation.
  for (final pair in [
    ['#FBF9F0', '#F0EDE4'], // 1.05:1 authored — no separation owed
    ['#DEE8D5', '#FBF9F0'], // darker child
    ['#C9C9C9', '#FFFFFF'], // 1.61:1 authored — separation owed
    ['#F5F5F5', '#FFFFFF'],
    ['#FFFFFF', '#C9C9C9'], // lighter child
    ['#E8E8E8', '#FFFFFF'],
    ['#DADADA', '#F5F5F5'],
  ]) {
    surface(pair[0], engine.mapSurface(hex(pair[1]), parent: page).color, pair[1]);
  }

  // ---- foreground solving, including the I5 no-op ---------------------------
  final foregrounds = <Map<String, Object?>>[];
  void fg(String input, String background, double target) {
    foregrounds.add({
      'input': input,
      'background': background,
      'target': target,
      'expected': engine.solveForeground(hex(input), hex(background), minRatio: target).toHex(),
    });
  }

  // Already passing — must come back untouched on both sides.
  for (final b in ['#00695C', '#006851', '#0B5FA5', '#2E7D32', '#B34700', '#C62828', '#1976D2', '#14211F']) {
    fg('#FFFFFF', b, 4.5);
  }
  // Failing — must be solved identically, on the page, on cards and on a
  // surface the text ramp misses (the repair walk).
  for (final f in [
    '#2F5D3A',
    '#2C5530',
    '#4A4A45',
    '#C1502E',
    '#222222',
    '#006851',
    '#1976D2',
    '#000000',
    '#212121',
    '#333333',
    '#555555',
    '#6E6E6E',
    '#8C8C8C',
    '#2B1055',
  ]) {
    fg(f, '#181A1B', 4.5);
    fg(f, '#232328', 4.5);
    fg(f, '#383732', 4.5);
    fg(f, '#181A1B', 3.0); // large-text allowance
  }
  // A light backdrop: a brand fill the solver must read from the other side.
  for (final f in ['#FFFFFF', '#F6F6F9', '#CCCCCC']) {
    fg(f, '#FFB300', 4.5);
    fg(f, '#FFEB3B', 3.0);
  }

  // ---- shadows and borders --------------------------------------------------
  final shadows = [
    for (final s in ['#000000', '#888888', '#CCCCCC', '#1976D2', '#333333', '#FFFFFF'])
      {'input': s, 'expected': engine.mapShadow(hex(s)).toHex()},
  ];
  final borders = <Map<String, Object?>>[];
  for (final s in ['#CCCCCC', '#E3E6EA', '#DDDDDD', '#FFFFFF', '#333333', '#006851', '#FF9800', '#B0B0B0']) {
    for (final bg in ['#181A1B', '#232328', '#2E2F35']) {
      borders.add({'input': s, 'background': bg, 'expected': engine.mapBorder(hex(s), hex(bg)).toHex()});
    }
  }

  // ---- alpha compositing ----------------------------------------------------
  final composites = <Map<String, Object?>>[];
  for (final a in [0.12, 0.14, 0.18, 0.30, 0.45]) {
    for (final pair in [
      ['#808080', '#181A1B'],
      ['#808080', '#FFFFFF'],
      ['#FFC107', '#181A1B'],
      ['#FFFFFF', '#181A1B'],
      ['#006851', '#232328'],
    ]) {
      composites.add({
        'input': pair[0],
        'alpha': a,
        'backdrop': pair[1],
        'expected': hex(pair[0]).withAlpha(a).over(hex(pair[1])).toHex(),
      });
    }
  }

  // ---- WCAG large-text rule -------------------------------------------------
  final targets = [
    for (final c in [(12.0, false), (16.0, false), (18.66, true), (18.0, true), (19.0, false), (24.0, false)])
      {'px': c.$1, 'bold': c.$2, 'expected': engine.targetFor(fontSizePx: c.$1, bold: c.$2)},
  ];

  final json = const JsonEncoder.withIndent('  ').convert({
    'generatedBy': 'tool/generate_vectors.dart',
    'config': engine.config.toJson(),
    'page': page.toHex(),
    'classify': classify,
    'mapSurface': surfaces,
    'solveForeground': foregrounds,
    'mapShadow': shadows,
    'mapBorder': borders,
    'composite': composites,
    'targetFor': targets,
  });
  File(_target)
    ..createSync(recursive: true)
    ..writeAsStringSync('$json\n');

  final total = classify.length +
      surfaces.length +
      foregrounds.length +
      shadows.length +
      borders.length +
      composites.length +
      targets.length;
  stdout.writeln('wrote $_target ($total cases)');
}
