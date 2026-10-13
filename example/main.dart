// Converts a small message for both themes and writes the results next to each
// other, so you can open them in a browser and compare.
//
//     dart run example/main.dart
//     open build/example/index.html
import 'dart:io';

import 'package:k_html_dark_mode/k_html_dark_mode.dart';

const message = '''
<div style="background:#ffffff;padding:16px;font-family:Arial,sans-serif">
  <h2 style="color:#1f2937;margin:0 0 8px">Weekly update</h2>
  <p style="color:#6b7280">Written for a white page, with no dark-mode CSS at all.</p>
  <div style="background:#f3f4f6;border:1px solid #e5e7eb;border-radius:8px;padding:12px;color:#374151">
    A light inset card — remapped to a dark surface, text kept readable.
  </div>
  <p><a href="#" style="background:#006851;color:#ffffff;padding:8px 14px;border-radius:6px;
     text-decoration:none">A brand button — kept exactly as authored</a></p>
</div>
''';

void main() {
  final light = KHtmlDarkMode.convert(message, isDark: false);
  final dark = KHtmlDarkMode.convert(message, fontScale: 1.15); // dark is the default

  stdout
    ..writeln('k_html_dark_mode ${KHtmlDarkMode.version}')
    ..writeln('light: ${light.html.length} chars, background ${light.backgroundHex}')
    ..writeln('dark:  ${dark.html.length} chars, background ${dark.backgroundHex}');

  // Each rendering goes in its own iframe; srcdoc needs & and " escaped.
  String frame(KdmResult r) => '<iframe style="width:360px;height:420px;border:1px solid #888" '
      'srcdoc="${r.html.replaceAll('&', '&amp;').replaceAll('"', '&quot;')}"></iframe>';

  final out = Directory('build/example')..createSync(recursive: true);
  File('${out.path}/index.html')
      .writeAsStringSync('<!DOCTYPE html><meta charset="utf-8"><body style="font-family:sans-serif">'
          '<h3>light / dark</h3>${frame(light)} ${frame(dark)}</body>');
  stdout.writeln('wrote ${out.path}/index.html');
}
