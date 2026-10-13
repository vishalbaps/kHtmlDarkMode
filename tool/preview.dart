// Side-by-side preview of any HTML file, in every mode and text size, using the
// exact documents the package produces.
//
//     dart run tool/preview.dart path/to/message.html [--fit]
//     open build/preview/index.html
//
// Each cell is an iframe whose srcdoc is the converted document, at phone
// width, so what you see is what a web view shows.
import 'dart:io';

import 'package:k_html_dark_mode/k_html_dark_mode.dart';

void main(List<String> args) {
  final files = args.where((a) => !a.startsWith('--')).toList();
  if (files.length != 1) {
    stderr.writeln('usage: dart run tool/preview.dart <file.html> [--fit]');
    exit(64);
  }
  final fit = args.contains('--fit');
  final source = File(files.single).readAsStringSync();

  String escape(String s) => s.replaceAll('&', '&amp;').replaceAll('"', '&quot;');
  final cells = StringBuffer();
  for (final isDark in [false, true]) {
    cells.write('<div class="row">');
    for (final scale in [0.85, 1.0, 1.15, 1.3]) {
      final r = KHtmlDarkMode.convert(source, isDark: isDark, fontScale: scale, fitToWidth: fit, debugTrace: true);
      cells.write('<figure><figcaption>${isDark ? 'dark' : 'light'} × $scale</figcaption>'
          '<iframe srcdoc="${escape(r.html)}"></iframe></figure>');
    }
    cells.write('</div>');
  }

  final out = Directory('build/preview')..createSync(recursive: true);
  File('${out.path}/index.html').writeAsStringSync('''
<!DOCTYPE html>
<meta charset="utf-8">
<title>k_html_dark_mode preview — ${files.single}</title>
<style>
  body { font: 13px system-ui, sans-serif; margin: 16px; background: #777; }
  .row { display: flex; gap: 12px; margin-bottom: 16px; }
  figure { margin: 0; }
  figcaption { color: #fff; margin-bottom: 4px; }
  iframe { width: 360px; height: 720px; border: 0; background: #fff; }
</style>
<p style="color:#fff">${files.single} · v${KHtmlDarkMode.version}${fit ? ' · fitToWidth' : ''}</p>
$cells
''');
  stdout.writeln('wrote ${out.path}/index.html');
}
