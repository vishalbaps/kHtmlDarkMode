// Renders the browser-suite inputs: every fixture, through the real
// KHtmlDarkMode.convert, in every variant the suite checks.
//
//     dart run tool/render_fixtures.dart
//
// Writes build/browser/*.html plus build/browser/manifest.json. Run by the
// Playwright global setup, so the browser suite always tests current output.
import 'dart:convert';
import 'dart:io';

import 'package:k_html_dark_mode/k_html_dark_mode.dart';

const _fixtures = 'test/fixtures/templates';
const _out = 'build/browser';

/// A host script that records what the package reports, so the suite can
/// check the events a real host would listen for.
const _hostListener = '''
<script id="host-listener">
  window.__host = { reports: [], layouts: [] };
  window.addEventListener('kdm:report', function (e) { window.__host.reports.push(e.detail); });
  window.addEventListener('kdm:layout', function (e) { window.__host.layouts.push(e.detail); });
</script>''';

/// Host CSS that declares color-scheme itself — it must not be mistaken for
/// the author shipping their own dark mode.
const _hostStyle = '''
<meta name="color-scheme" content="dark light">
<style id="host-style">html { color-scheme: dark; } @media (prefers-color-scheme: dark) { .host-only { color: red; } }</style>''';

void main() {
  final dir = Directory(_out);
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  dir.createSync(recursive: true);

  final manifest = <Map<String, Object?>>[];

  void emit(String id, String fixture, String html, {required bool isDark, Map<String, Object?> options = const {}}) {
    File('$_out/$id.html').writeAsStringSync(html);
    manifest.add({'id': id, 'fixture': fixture, 'isDark': isDark, 'options': options});
  }

  String read(String name) => File('$_fixtures/$name').readAsStringSync();

  final names = Directory(_fixtures)
      .listSync()
      .whereType<File>()
      .map((f) => f.uri.pathSegments.last)
      .where((n) => n.endsWith('.html'))
      .toList()
    ..sort();

  for (final name in names) {
    final base = name.replaceAll('.html', '');
    final source = read(name);

    // The untouched original, as a browser would show it, for the
    // light-mode identity check. A fragment gets the bare minimum around it.
    final original =
        source.trimLeft().startsWith('<') && RegExp(r'^\s*<(!doctype|html)', caseSensitive: false).hasMatch(source)
            ? source
            : '<!DOCTYPE html><html><head><meta charset="utf-8"></head><body>$source</body></html>';
    File('$_out/$base.original.html').writeAsStringSync(original);

    for (final isDark in [true, false]) {
      final mode = isDark ? 'dark' : 'light';
      emit('$base.$mode', name, KHtmlDarkMode.convert(source, isDark: isDark, extraBodyEnd: _hostListener).html,
          isDark: isDark);
    }
  }

  // ---- variants -------------------------------------------------------------
  final probe = read('probe-1-colours.html');
  final message = read('fragment-message.html');

  emit('probe-1-colours.dark.scaled', 'probe-1-colours.html',
      KHtmlDarkMode.convert(probe, isDark: true, fontScale: 1.3, extraBodyEnd: _hostListener).html,
      isDark: true, options: {'fontScale': 1.3});

  emit(
      'probe-1-colours.dark.twice',
      'probe-1-colours.html',
      KHtmlDarkMode.convert(KHtmlDarkMode.convert(probe, isDark: true).html, isDark: true, extraBodyEnd: _hostListener)
          .html,
      isDark: true,
      options: {'twice': true});

  emit('fragment-message.dark.fit', 'fragment-message.html',
      KHtmlDarkMode.convert(message, isDark: true, fitToWidth: true, extraBodyEnd: _hostListener).html,
      isDark: true, options: {'fitToWidth': true});

  emit('fragment-message.dark.black', 'fragment-message.html',
      KHtmlDarkMode.convert(message, isDark: true, pageBackground: '#000000', extraBodyEnd: _hostListener).html,
      isDark: true, options: {'pageBackground': '#000000'});

  emit('fragment-message.dark.hostcss', 'fragment-message.html',
      KHtmlDarkMode.convert(message, isDark: true, extraHead: _hostStyle, extraBodyEnd: _hostListener).html,
      isDark: true, options: {'extraHead': 'host color-scheme'});

  emit('fragment-message.dark.trace', 'fragment-message.html',
      KHtmlDarkMode.convert(message, isDark: true, debugTrace: true, extraBodyEnd: _hostListener).html,
      isDark: true, options: {'debugTrace': true});

  File('$_out/manifest.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
    'version': KHtmlDarkMode.version,
    'documents': manifest,
  }));
  stdout.writeln('wrote ${manifest.length} documents to $_out');
}
