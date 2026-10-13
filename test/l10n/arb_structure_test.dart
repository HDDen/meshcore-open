import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// gen-l10n reads only the root of an ARB file. A merge once put upstream's
// new keys inside a trailing metadata object of app_ru.arb (the
// `placeholders` of `@map_wardriveBackgroundNeeds`) and of app_bg.arb: the
// JSON stayed valid, the keys were silently untranslated, and the generated
// classes fell back to English for a dozen settings strings. Every entry
// written at the root's indentation has to be a root entry.

void main() {
  final files = Directory('lib/l10n')
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('.arb'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  test('lib/l10n holds the ARB files', () {
    expect(files, isNotEmpty, reason: 'run from the package root');
  });

  for (final file in files) {
    test('${file.uri.pathSegments.last}: every indent-2 entry is a root key', () {
      final text = file.readAsStringSync();
      final root = jsonDecode(text) as Map<String, dynamic>;
      final nested = <String>[];
      for (final match in RegExp(
        r'^  "([^"]+)"\s*:',
        multiLine: true,
      ).allMatches(text)) {
        final key = match.group(1)!;
        if (!root.containsKey(key)) nested.add(key);
      }
      expect(
        nested,
        isEmpty,
        reason: 'these entries sit inside another object and are invisible '
            'to gen-l10n',
      );
    });
  }
}
