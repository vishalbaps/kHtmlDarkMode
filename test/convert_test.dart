import 'dart:io';

import 'package:k_html_dark_mode/k_html_dark_mode.dart';
import 'package:test/test.dart';

/// Document assembly: what [KHtmlDarkMode.convert] puts where.
///
/// The colour behaviour itself runs in the page and is covered by the browser
/// suite in tool/node; these tests pin the structure that suite depends on.
void main() {
  int count(String haystack, String needle) => needle.allMatches(haystack).length;

  const fragment = '<div style="background:#fff;color:#222">Hello <b>world</b></div>';

  group('fragment', () {
    final dark = KHtmlDarkMode.convert(fragment, isDark: true).html;

    test('is wrapped in a complete document', () {
      expect(dark, startsWith('<!DOCTYPE html>'));
      expect(dark, contains('<html data-kdm-theme="dark">'));
      expect(dark, contains('<meta charset="utf-8">'));
      expect(dark, contains('<meta name="viewport" content="${KHtmlDarkMode.defaultViewport}">'));
      expect(dark, contains('</body>\n</html>'));
    });

    test("keeps the author's markup byte-for-byte", () {
      expect(dark, contains(fragment));
    });

    test('injects exactly one of each piece', () {
      expect(count(dark, 'id="kdm-theme-css"'), 1);
      expect(count(dark, 'id="kdm-color-scheme"'), 1);
      expect(count(dark, 'id="kdm-script"'), 1);
    });

    test('puts the content before the script, so the pass can see it', () {
      expect(dark.indexOf(fragment), lessThan(dark.indexOf('id="kdm-script"')));
    });

    test('declares the mode before any script runs', () {
      expect(dark, contains('content="dark"'));
      expect(dark, contains('color-scheme: dark;'));
      expect(dark, contains('html[data-kdm-theme="dark"] {'));
    });

    test('light mode is marked light', () {
      final light = KHtmlDarkMode.convert(fragment, isDark: false).html;
      expect(light, contains('<html data-kdm-theme="light">'));
      expect(light, contains('color-scheme: light;'));
      expect(light, contains('background-color: #FFFFFF;'));
    });
  });

  group('full document', () {
    final probe = File('test/fixtures/templates/probe-1-colours.html').readAsStringSync();
    final out = KHtmlDarkMode.convert(probe, isDark: true).html;

    test('keeps the author html attributes and adds the mode', () {
      expect(out, contains('<html data-kdm-theme="dark" xmlns="http://www.w3.org/1999/xhtml"'));
      expect(count(out, '<html'), 1);
      expect(count(out, '<head>'), 1);
      expect(count(out, '<body'), 1);
    });

    test("injects the theme CSS before the author's styles, so theirs win", () {
      expect(out.indexOf('id="kdm-theme-css"'), lessThan(out.indexOf('<style type="text/css">')));
      expect(out.indexOf('<head>'), lessThan(out.indexOf('id="kdm-theme-css"')));
    });

    test('keeps the author viewport and does not add a second one', () {
      expect(count(out, 'name="viewport"'), 1);
      expect(out, isNot(contains('<meta charset="utf-8">')));
    });

    test('puts the script last in the body', () {
      final script = out.indexOf('id="kdm-script"');
      expect(script, greaterThan(out.indexOf('Rendering probe &mdash;')));
      expect(script, lessThan(out.lastIndexOf('</body>')));
    });

    test('injects a viewport when the document has none', () {
      const doc = '<!DOCTYPE html><html><head><title>t</title></head><body><p>x</p></body></html>';
      final o = KHtmlDarkMode.convert(doc, isDark: true).html;
      expect(count(o, 'name="viewport"'), 1);
      expect(KHtmlDarkMode.convert(doc, isDark: true, viewport: null).html, isNot(contains('name="viewport"')));
    });

    test('creates a head when the document has none', () {
      const doc = '<html><body><p>x</p></body></html>';
      final o = KHtmlDarkMode.convert(doc, isDark: true).html;
      expect(o, contains('<html data-kdm-theme="dark">\n<head>\n<!--kdm:head-->'));
      expect(o.indexOf('</head>'), lessThan(o.indexOf('<body>')));
    });

    test('creates the html element when the document leaves it implicit', () {
      const doc = '<!DOCTYPE html><head><title>t</title></head><body><p>x</p></body>';
      final o = KHtmlDarkMode.convert(doc, isDark: true).html;
      expect(o, startsWith('<!DOCTYPE html><html data-kdm-theme="dark"><head>'));
    });

    test('ignores tags written inside comments', () {
      const doc = '<!-- an old <head> and <body> in a comment -->\n'
          '<html><head><title>t</title></head><body><p>x</p><!-- </body> --></body></html>';
      final o = KHtmlDarkMode.convert(doc, isDark: true).html;
      expect(o, contains('<!-- an old <head> and <body> in a comment -->'));
      expect(o.indexOf('id="kdm-theme-css"'), greaterThan(o.indexOf('<html data-kdm-theme')));
      expect(o.indexOf('id="kdm-script"'), greaterThan(o.indexOf('<!-- </body> -->')));
    });

    test('a partial document — no closing body — gets the script at the end', () {
      // An inbox renderer can split one message around a <video> tag, so the
      // first chunk opens the document and never closes it.
      const chunk = '<!DOCTYPE html><html><head><style>p{color:#333}</style></head><body><p>first half';
      final o = KHtmlDarkMode.convert(chunk, isDark: true).html;
      expect(o, contains('<p>first half'));
      expect(o.trimRight(), endsWith('<!--/kdm:body-->'));
    });

    test('the charset declaration stays first in the head', () {
      const doc = '<html><head><meta charset="utf-8"><title>t</title></head><body>x</body></html>';
      final o = KHtmlDarkMode.convert(doc, isDark: true).html;
      expect(o, contains('<head><meta charset="utf-8">\n<!--kdm:head-->'));
    });
  });

  group('re-conversion', () {
    test('converting twice leaves one conversion, not two', () {
      final once = KHtmlDarkMode.convert(fragment, isDark: true, fitToWidth: true).html;
      final twice = KHtmlDarkMode.convert(once, isDark: true, fitToWidth: true).html;
      expect(count(twice, 'id="kdm-theme-css"'), 1);
      expect(count(twice, 'id="kdm-script"'), 1);
      expect(count(twice, 'id="kdm-root"'), 1);
      expect(count(twice, '<html data-kdm-theme="dark"'), 1);
      expect(RegExp(r'<html[^>]*data-kdm-theme[^>]*data-kdm-theme').hasMatch(twice), isFalse,
          reason: 'the attribute must be replaced, not repeated');
      expect(twice, contains(fragment));
    });

    test('re-converting into the other mode switches it cleanly', () {
      final dark = KHtmlDarkMode.convert(fragment, isDark: true).html;
      final light = KHtmlDarkMode.convert(dark, isDark: false).html;
      expect(light, contains('data-kdm-theme="light"'));
      expect(light, isNot(contains('data-kdm-theme="dark"')));
      expect(light, isNot(contains('color-scheme: dark')));
    });
  });

  group('options', () {
    test('fitToWidth wraps the content, and only then', () {
      final fit = KHtmlDarkMode.convert(fragment, isDark: true, fitToWidth: true).html;
      expect(fit, contains('<div id="kdm-root"><div id="kdm-content">'));
      expect(fit.indexOf('id="kdm-content"'), lessThan(fit.indexOf(fragment)));
      expect(fit.indexOf(fragment), lessThan(fit.indexOf('<!--kdm:wrap-end-->')));
      expect(fit, contains('#kdm-content { transform-origin: top left; }'));
      expect(KHtmlDarkMode.convert(fragment, isDark: true).html, isNot(contains('id="kdm-root"')));
    });

    test('fitToWidth wraps a full document body', () {
      const doc = '<html><head></head><body class="b"><p>x</p></body></html>';
      final o = KHtmlDarkMode.convert(doc, isDark: true, fitToWidth: true).html;
      expect(o, contains('<body class="b"><!--kdm:wrap--><div id="kdm-root">'));
      expect(o.indexOf('<!--kdm:wrap-end-->'), lessThan(o.indexOf('id="kdm-script"')));
    });

    test('extraHead follows the theme CSS; extraBodyEnd follows the script', () {
      final o = KHtmlDarkMode.convert(fragment,
              isDark: true, extraHead: '<style id="host">x{}</style>', extraBodyEnd: '<script id="host-js"></script>')
          .html;
      expect(o.indexOf('id="host"'), greaterThan(o.indexOf('id="kdm-theme-css"')));
      expect(o.indexOf('id="host"'), lessThan(o.indexOf('<!--/kdm:head-->')));
      expect(o.indexOf('id="host-js"'), greaterThan(o.indexOf('id="kdm-script"')));
      expect(o.indexOf('id="host-js"'), lessThan(o.indexOf('<!--/kdm:body-->')));
    });

    test('options reach the script', () {
      final o = KHtmlDarkMode.convert(fragment, isDark: true, fontScale: 1.3, fitToWidth: true, debugTrace: true).html;
      expect(o, contains('"fontScale":1.3'));
      expect(o, contains('"isDark":true'));
      expect(o, contains('"fitToWidth":true'));
      expect(o, contains('"trace":true'));
      expect(o, contains('"version":"${KHtmlDarkMode.version}"'));
    });

    test('pageBackground replaces the page colour everywhere', () {
      final r = KHtmlDarkMode.convert(fragment, isDark: true, pageBackground: '#121212');
      expect(r.backgroundHex, '#121212');
      expect(r.backgroundArgb, 0xFF121212);
      expect(r.html, contains('background-color: #121212;'));
      expect(r.html, contains('--kdm-bg: #121212;'));
    });

    test('the default backgrounds are the palette backgrounds', () {
      expect(KHtmlDarkMode.convert(fragment, isDark: true).backgroundHex, '#181A1B');
      expect(KHtmlDarkMode.convert(fragment, isDark: false).backgroundHex, '#FFFFFF');
    });

    test('bad arguments are rejected', () {
      expect(() => KHtmlDarkMode.convert(fragment, isDark: true, fontScale: 0), throwsArgumentError);
      expect(() => KHtmlDarkMode.convert(fragment, isDark: true, fontScale: double.nan), throwsArgumentError);
      expect(() => KHtmlDarkMode.convert(fragment, isDark: true, pageBackground: '#FFFFFF'), throwsArgumentError);
    });
  });

  test('dark mode is the default', () {
    final r = KHtmlDarkMode.convert(fragment);
    expect(r.isDark, isTrue);
    expect(r.backgroundHex, '#181A1B');
    expect(r.html, KHtmlDarkMode.convert(fragment, isDark: true).html);
  });

  test('the same input always produces the same string', () {
    final a = KHtmlDarkMode.convert(fragment, isDark: true, fontScale: 1.15);
    final b = KHtmlDarkMode.convert(fragment, isDark: true, fontScale: 1.15);
    expect(a.html, b.html);
  });

  test('an empty input still produces a valid, themed document', () {
    final o = KHtmlDarkMode.convert('', isDark: true).html;
    expect(o, contains('<body>'));
    expect(o, contains('id="kdm-script"'));
  });
}
