import 'dart:convert';

import 'color.dart';
import 'engine.dart';
import 'generated/script_source.g.dart';
import 'tokens.dart';
import 'version.dart';

/// Everything [composeDocument] needs to know about one conversion. Internal;
/// see `KHtmlDarkMode.convert` for what each option means.
class DocumentSpec {
  /// Render in dark mode.
  final bool isDark;

  /// Page background.
  final KdmColor background;

  /// Default text colour for the page.
  final KdmColor foreground;

  /// The `--kdm-*` tokens for this mode and background.
  final KdmTokens tokens;

  /// Text size multiplier.
  final double fontScale;

  /// Scale over-wide content down to the viewport.
  final bool fitToWidth;

  /// Viewport meta content, or null for none.
  final String? viewport;

  /// Host markup for the end of the head block.
  final String extraHead;

  /// Host markup placed after the script.
  final String extraBodyEnd;

  /// Include the background decision trace in the report.
  final bool trace;

  /// Engine tuning constants.
  final KdmEngineConfig config;

  /// Creates a spec.
  const DocumentSpec({
    required this.isDark,
    required this.background,
    required this.foreground,
    required this.tokens,
    required this.fontScale,
    required this.fitToWidth,
    required this.viewport,
    required this.extraHead,
    required this.extraBodyEnd,
    required this.trace,
    required this.config,
  });

  /// `dark` or `light`, as written into the document.
  String get mode => isDark ? 'dark' : 'light';
}

// Every injected piece sits between a pair of `<!--kdm:NAME-->` /
// `<!--/kdm:NAME-->` comments, which is what lets a second conversion remove
// the first one's output instead of stacking on it, and lets the in-page pass
// tell the package's CSS from the author's.
const _markerPrefix = '<!--kdm:';
final _previousConversion = RegExp(r'<!--kdm:(head|body|wrap|wrap-end)-->[\s\S]*?<!--/kdm:\1-->');

/// Builds the converted document for [html].
///
/// A fragment is placed inside a complete document. A full document keeps its
/// own markup; the package's head block goes first in `<head>` — so the
/// author's styles, coming later, still win the cascade — and its script goes
/// last in `<body>`, after everything it has to walk.
String composeDocument(String html, DocumentSpec spec) {
  final source = stripPreviousConversion(html);
  return isFullDocument(source) ? _injectIntoDocument(source, spec) : _wrapFragment(source, spec);
}

/// Removes everything a previous conversion injected.
///
/// One substring search answers the common case; the expression only runs on
/// a document that really was converted before.
String stripPreviousConversion(String html) =>
    html.contains(_markerPrefix) ? html.replaceAll(_previousConversion, '') : html;

/// Whether [html] is a whole document rather than a fragment: after any byte
/// order mark, whitespace and comments it opens with a doctype or an
/// `<html>`, `<head>` or `<body>` tag.
bool isFullDocument(String html) => _documentStart.matchAsPrefix(html, _leadingEnd(html)) != null;

int _leadingEnd(String html) => _leading.matchAsPrefix(html)?.end ?? 0;

final _leading = RegExp('(?:﻿)?(?:\\s|<!--[\\s\\S]*?-->)*');
final _documentStart = RegExp(r'<(?:!doctype|html|head|body)\b', caseSensitive: false);

// ------------------------------------------------------------------ fragment

String _wrapFragment(String fragment, DocumentSpec spec) {
  final body = spec.fitToWidth ? '${_wrapStart()}$fragment${_wrapEnd()}' : fragment;
  return '<!DOCTYPE html>\n'
      '<html data-kdm-theme="${spec.mode}">\n'
      '<head>\n'
      '${_headBlock(spec, charset: true, viewport: spec.viewport)}\n'
      '</head>\n'
      '<body>\n'
      '$body\n'
      '${_bodyBlock(spec)}\n'
      '</body>\n'
      '</html>\n';
}

// ------------------------------------------------------------- full document

/// Injects into a complete document with one scan that records every landmark
/// and one assembly. Newsletters with inline images run to hundreds of
/// kilobytes, and this runs on the host's UI thread, so neither a scan per tag
/// nor a copy per edit is affordable.
String _injectIntoDocument(String doc, DocumentSpec spec) {
  final at = _Landmarks.scan(doc);
  final edits = _Edits(doc);
  final headOpen = at.headOpen;

  // 1. Mark <html> with the mode, so the token block applies before any script
  //    runs. Create the element if the author left it implicit.
  final htmlOpen = at.htmlOpen;
  final int afterHtml;
  if (htmlOpen != null) {
    edits.replace(htmlOpen.start, htmlOpen.end, _setThemeAttribute(htmlOpen.group(0)!, spec.mode));
    afterHtml = htmlOpen.end;
  } else {
    afterHtml = at.doctype?.end ?? _leadingEnd(doc);
    edits.insert(afterHtml, '<html data-kdm-theme="${spec.mode}">');
  }

  // 2. The script goes last in the body, after everything it has to walk.
  final scriptAt = (at.lastBodyClose ?? at.lastHtmlClose)?.start ?? doc.length;

  // 3. Fit-to-width wraps everything from the start of the body content to the
  //    script: after <body>, else after the head — the author's, or the one
  //    created below when there is none.
  int? wrapAt;
  var wrapAfterCreatedHead = false;
  if (spec.fitToWidth) {
    wrapAt = at.bodyOpen?.end ?? at.lastHeadClose?.end;
    if (wrapAt == null && headOpen == null) wrapAfterCreatedHead = afterHtml <= scriptAt;
    if (wrapAt != null && wrapAt > scriptAt) wrapAt = null;
  }

  // 4. The head block. The author's viewport wins if they declared one.
  final head = _headBlock(spec, charset: false, viewport: at.hasViewport ? null : spec.viewport);
  if (headOpen != null) {
    // After the author's charset declaration if it leads the head, so it stays
    // inside the first 1024 bytes the encoding sniffer reads.
    final charset = at.charset;
    final headClose = at.headClose;
    final leadsHead = charset != null &&
        (headClose == null || charset.start < headClose.start) &&
        doc.substring(headOpen.end, charset.start).trim().isEmpty;
    edits.insert(leadsHead ? charset.end : headOpen.end, '\n$head\n');
  } else {
    edits.insert(afterHtml, '\n<head>\n$head\n</head>${wrapAfterCreatedHead ? _wrapStart() : ''}\n');
  }

  if (wrapAt != null) edits.insert(wrapAt, _wrapStart());
  final wrapped = wrapAt != null || wrapAfterCreatedHead;
  edits.insert(scriptAt, wrapped ? '\n${_wrapEnd()}\n${_bodyBlock(spec)}\n' : '\n${_bodyBlock(spec)}\n');

  return edits.apply();
}

String _setThemeAttribute(String htmlTag, String mode) {
  final cleaned = htmlTag.replaceAll(_themeAttribute, '');
  return cleaned.replaceFirstMapped(_htmlTagName, (m) => '${m.group(0)} data-kdm-theme="$mode"');
}

final _themeAttribute = RegExp('''\\s+data-kdm-theme\\s*=\\s*(?:"[^"]*"|'[^']*'|[^\\s>]+)''', caseSensitive: false);
final _htmlTagName = RegExp('^<html', caseSensitive: false);

/// The tags the injection needs, found in a single scan.
///
/// Comments are matched as whole units by the same expression, so a `<head>`
/// or `</body>` written inside a comment is never mistaken for the real one.
class _Landmarks {
  RegExpMatch? doctype;
  RegExpMatch? htmlOpen;
  RegExpMatch? headOpen;

  /// The first `</head>` after [headOpen].
  RegExpMatch? headClose;
  RegExpMatch? lastHeadClose;
  RegExpMatch? bodyOpen;
  RegExpMatch? lastBodyClose;
  RegExpMatch? lastHtmlClose;

  /// The first charset declaration after [headOpen].
  RegExpMatch? charset;
  bool hasViewport = false;

  static final _tags = RegExp(
    r'<!--[\s\S]*?-->'
    r'|(<!doctype[^>]*>)'
    r'|(<html\b[^>]*>)'
    r'|(</html\s*>)'
    r'|(<head\b[^>]*>)'
    r'|(</head\s*>)'
    r'|(<body\b[^>]*>)'
    r'|(</body\s*>)'
    r'|(<meta\b[^>]*>)',
    caseSensitive: false,
  );
  static final _charsetAttr = RegExp('charset', caseSensitive: false);
  static final _viewportAttr = RegExp(r'''name\s*=\s*["']?viewport\b''', caseSensitive: false);

  static _Landmarks scan(String doc) {
    final l = _Landmarks();
    for (final m in _tags.allMatches(doc)) {
      if (m.group(1) != null) {
        l.doctype ??= m;
      } else if (m.group(2) != null) {
        l.htmlOpen ??= m;
      } else if (m.group(3) != null) {
        l.lastHtmlClose = m;
      } else if (m.group(4) != null) {
        l.headOpen ??= m;
      } else if (m.group(5) != null) {
        if (l.headOpen != null) l.headClose ??= m;
        l.lastHeadClose = m;
      } else if (m.group(6) != null) {
        l.bodyOpen ??= m;
      } else if (m.group(7) != null) {
        l.lastBodyClose = m;
      } else if (m.group(8) != null) {
        final tag = m.group(8)!;
        if (l.headOpen != null && l.charset == null && _charsetAttr.hasMatch(tag)) l.charset = m;
        if (!l.hasViewport && _viewportAttr.hasMatch(tag)) l.hasViewport = true;
      }
    }
    return l;
  }
}

/// Insertions and replacements against one source string, applied in a single
/// pass. Edits at the same position apply in the order they were added.
class _Edits {
  final String source;
  final List<(int, int, int, String)> _list = [];

  _Edits(this.source);

  void insert(int at, String text) => _list.add((at, at, _list.length, text));

  void replace(int start, int end, String text) => _list.add((start, end, _list.length, text));

  String apply() {
    _list.sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$3 - b.$3);
    final out = StringBuffer();
    var cursor = 0;
    for (final (start, end, _, text) in _list) {
      out
        ..write(source.substring(cursor, start))
        ..write(text);
      cursor = end;
    }
    out.write(source.substring(cursor));
    return out.toString();
  }
}

// ------------------------------------------------------------------- blocks

String _headBlock(DocumentSpec spec, {required bool charset, required String? viewport}) {
  final b = StringBuffer('<!--kdm:head-->\n');
  if (charset) b.writeln('<meta charset="utf-8">');
  if (viewport != null) b.writeln('<meta name="viewport" content="${_attr(viewport)}">');
  b
    ..writeln('<meta id="kdm-color-scheme" name="color-scheme" content="${spec.mode}">')
    ..writeln('<style id="kdm-theme-css">')
    ..writeln(_themeCss(spec))
    ..writeln('</style>');
  if (spec.extraHead.isNotEmpty) b.writeln(spec.extraHead);
  b.write('<!--/kdm:head-->');
  return b.toString();
}

String _bodyBlock(DocumentSpec spec) {
  final b = StringBuffer('<!--kdm:body-->\n')
    ..writeln('<script id="kdm-script">')
    ..writeln(buildScript(spec))
    ..writeln('</script>');
  if (spec.extraBodyEnd.isNotEmpty) b.writeln(spec.extraBodyEnd);
  b.write('<!--/kdm:body-->');
  return b.toString();
}

String _wrapStart() => '<!--kdm:wrap--><div id="kdm-root"><div id="kdm-content"><!--/kdm:wrap-->';
String _wrapEnd() => '<!--kdm:wrap-end--></div></div><!--/kdm:wrap-end-->';

/// The pre-paint CSS: tokens, `color-scheme`, and the page colours.
///
/// The root stays at 16px. Text scaling happens in the script by multiplying
/// each element's *resolved* font size, because scaling the root would only
/// affect `rem` and templates almost always size in `px`. `text-size-adjust`
/// pins the browser's own autosizing so it cannot compound with that.
String _themeCss(DocumentSpec spec) {
  final b = StringBuffer()
    ..writeln(spec.tokens.toCssBlock())
    ..writeln('html {')
    ..writeln('  color-scheme: ${spec.mode};')
    ..writeln('  font-size: 16px;')
    ..writeln('  -webkit-text-size-adjust: 100%;')
    ..writeln('  text-size-adjust: 100%;')
    ..writeln('}')
    ..writeln('html, body {')
    ..writeln('  margin: 0;')
    ..writeln('  padding: 0;')
    ..writeln('  background-color: ${spec.background.toHex()};')
    ..writeln('  color: ${spec.foreground.toHex()};')
    ..writeln('}')
    ..write('img, video, canvas, svg, picture { max-width: 100%; height: auto; }');
  if (spec.fitToWidth) {
    b
      ..writeln()
      ..writeln('#kdm-root { overflow: hidden; }')
      ..write('#kdm-content { transform-origin: top left; }');
  }
  return b.toString();
}

/// The in-page pass with this conversion's options bound in.
///
/// Every tuning constant comes from [KdmEngineConfig], so the Dart and
/// JavaScript engines can never run on different numbers.
String buildScript(DocumentSpec spec) {
  final options = jsonEncode({
    'config': spec.config.toJson(),
    'page': [spec.background.r, spec.background.g, spec.background.b],
    'isDark': spec.isDark,
    'fontScale': spec.fontScale,
    'fitToWidth': spec.fitToWidth,
    'trace': spec.trace,
    'version': kdmVersion,
  });
  return '(function () {\n$kdmScriptSource\nkdmDarkMode($options);\n})();';
}

String _attr(String v) => v.replaceAll('&', '&amp;').replaceAll('"', '&quot;');
