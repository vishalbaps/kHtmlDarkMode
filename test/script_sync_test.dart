import 'dart:io';

import 'package:k_html_dark_mode/k_html_dark_mode.dart';
import 'package:k_html_dark_mode/src/generated/script_source.g.dart';
import 'package:test/test.dart';

/// Guards the two generated or duplicated facts in the package.
void main() {
  test('the embedded script matches js/k_html_dark_mode.js', () {
    final source = File('js/k_html_dark_mode.js').readAsStringSync().replaceAll('\r\n', '\n');
    expect(kdmScriptSource == source, isTrue,
        reason: 'lib/src/generated/script_source.g.dart is stale — run `dart run tool/generate_script.dart`');
  });

  test('the stamped version matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec)!.group(1);
    expect(KHtmlDarkMode.version, version, reason: 'update lib/src/version.dart');
  });

  test('the changelog has an entry for this version', () {
    final changelog = File('CHANGELOG.md').readAsStringSync();
    expect(changelog, contains('## ${KHtmlDarkMode.version}'));
  });
}
