// Times KHtmlDarkMode.convert — the Dart half, which runs on the host's UI
// isolate once per message — and writes the documents the in-page benchmark
// (tool/node/bench.mjs) loads.
//
//     dart run tool/benchmark.dart
//
// Inputs span a short message to a ~0.5 MB newsletter, as a fragment and as a
// full document. Run with `dart compile exe` for AOT numbers closer to a
// release app; `dart run` (JIT) is within a small factor.
import 'dart:io';

import 'package:k_html_dark_mode/k_html_dark_mode.dart';

void main() {
  final fragment = File('test/fixtures/templates/fragment-message.html').readAsStringSync();
  final probe = File('test/fixtures/templates/probe-1-colours.html').readAsStringSync();

  // A newsletter-sized document: the probe's body content repeated.
  final bodyStart = probe.indexOf('<table id="ebTable"');
  final bodyEnd = probe.lastIndexOf('</body>');
  final content = probe.substring(bodyStart, bodyEnd);
  final bigDocument = probe.replaceRange(bodyStart, bodyEnd, List.filled(40, content).join('\n'));
  final bigFragment = List.filled(100, fragment).join('\n');

  final inputs = {
    'fragment 2 KB': fragment,
    'document 12 KB': probe,
    'fragment ${bigFragment.length ~/ 1024} KB': bigFragment,
    'document ${bigDocument.length ~/ 1024} KB': bigDocument,
  };

  // Cold: the first call in a fresh process pays for token derivation.
  final cold = Stopwatch()..start();
  KHtmlDarkMode.convert(fragment);
  cold.stop();
  stdout.writeln('first call (cold, dark): ${_ms(cold.elapsedMicroseconds)}');
  final coldLight = Stopwatch()..start();
  KHtmlDarkMode.convert(fragment, isDark: false);
  coldLight.stop();
  stdout.writeln('first call (cold, light): ${_ms(coldLight.elapsedMicroseconds)}');

  stdout.writeln('\nwarm, mean of N calls:');
  inputs.forEach((name, html) {
    final n = html.length > 100000 ? 50 : 500;
    for (var i = 0; i < 20; i++) {
      KHtmlDarkMode.convert(html, fitToWidth: true);
    }
    final sw = Stopwatch()..start();
    for (var i = 0; i < n; i++) {
      KHtmlDarkMode.convert(html, fontScale: 1.15, fitToWidth: true);
    }
    sw.stop();
    stdout.writeln('  ${name.padRight(20)} ${_ms(sw.elapsedMicroseconds ~/ n)}');
  });

  // Documents for the in-page benchmark.
  final out = Directory('build/bench')..createSync(recursive: true);
  inputs.forEach((name, html) {
    final file = name.split(' ').first + name.split(' ')[1];
    for (final scale in [1.0, 1.3]) {
      final doc = KHtmlDarkMode.convert(html, fontScale: scale, fitToWidth: true).html;
      // Bracket the package script with timestamps, so the in-page benchmark
      // measures exactly its parse + run.
      final timed = doc
          .replaceFirst(
              '<script id="kdm-script">', '<script>window.__t0=performance.now()</script><script id="kdm-script">')
          .replaceFirst('</script>\n<!--/kdm:body-->',
              '</script><script>window.__t1=performance.now()</script>\n<!--/kdm:body-->');
      File('${out.path}/$file-x$scale.html').writeAsStringSync(timed);
    }
  });
  stdout.writeln('\nwrote in-page benchmark documents to ${out.path}');
}

String _ms(int micros) => '${(micros / 1000).toStringAsFixed(2)} ms';
