import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// The checked-in tree is one build profile, lite-aeic, and
// tool/use_translation_profile.dart rebuilds it from pubspec.<profile>.yaml
// and the two service templates. Three things keep every profile usable:
// the live files equal the templates the default profile copies (a change
// made to a live file alone is reverted by the next switch, which is how
// upstream's releaseDecoderSession fix fell out of the onnx template on
// 2026-10-12); the three pubspec profiles agree on everything but their own
// packages; and the two templates of each service declare the same API, or
// the app stops compiling after a switch.

const _profiles = ['lite', 'lite-aeic', 'full'];
const _defaultProfile = 'lite-aeic';
const _onnxTemplate =
    'tool/image_codec_profiles/image_codec_backend_onnx.dart.txt';
const _disabledCodecTemplate =
    'tool/image_codec_profiles/image_codec_backend_disabled.dart.txt';
const _llmTemplate =
    'tool/translation_profiles/translation_service_llm.dart.txt';
const _disabledTranslationTemplate =
    'tool/translation_profiles/translation_service_disabled.dart.txt';

String _read(String path) {
  final file = File(path);
  if (!file.existsSync()) fail('$path is missing (run from the package root)');
  return file.readAsStringSync().replaceAll('\r\n', '\n');
}

String _yamlLine(String raw) =>
    raw.replaceFirst(RegExp(r'(^|\s)#.*$'), '').trimRight();

/// The entries of the top-level mapping [name]: key to its value text with
/// every nested line, comments dropped.
Map<String, String> _section(String yaml, String name) {
  final entries = <String, String>{};
  var inside = false;
  String? current;
  for (final raw in yaml.split('\n')) {
    final line = _yamlLine(raw);
    if (line.trim().isEmpty) continue;
    if (!line.startsWith(' ')) {
      inside = line == '$name:';
      current = null;
      continue;
    }
    if (!inside) continue;
    final entry = RegExp(r'^  (\S+):\s*(.*)$').firstMatch(line);
    if (entry != null) {
      current = entry.group(1)!;
      entries[current] = entry.group(2)!.trim();
    } else if (current != null) {
      entries[current] = '${entries[current]}\n${line.trim()}';
    }
  }
  return entries;
}

/// The file without the top-level [sections], comments and blank lines
/// dropped.
String _outside(String yaml, Set<String> sections) {
  final kept = <String>[];
  var skipping = false;
  for (final raw in yaml.split('\n')) {
    final line = _yamlLine(raw);
    if (line.trim().isEmpty) continue;
    if (!line.startsWith(' ')) {
      skipping = sections.contains(line.split(':').first);
    }
    if (!skipping) kept.add(line);
  }
  return kept.join('\n');
}

String _dartLine(String raw) =>
    raw.replaceFirst(RegExp(r'\s*//.*$'), '').trimRight();

int _parenDepth(String text) =>
    '('.allMatches(text).length - ')'.allMatches(text).length;

/// The public members of [className] in [source]: name to the declaration
/// up to its body, parameters included, whitespace collapsed and `async`
/// dropped, so a stub's one-liner and an implementation's block compare
/// equal when they declare the same thing.
Map<String, String> _publicMembers(String source, String className) {
  final lines = source.split('\n');
  final start = lines.indexWhere(
    (line) => RegExp('^(abstract )?class $className\\b').hasMatch(line),
  );
  if (start == -1) fail('class $className not found');
  final head = RegExp(
    r'^  (?!_|@|static const|static final|final |const |late )(?:static )?'
    r'[A-Za-z][\w<>?, ]*?\s+(?:get\s+|set\s+)?([a-zA-Z]\w*)\s*(?:\(|=>|\{|;|=)',
  );
  final members = <String, String>{};
  for (var i = start + 1; i < lines.length; i++) {
    final line = _dartLine(lines[i]);
    if (line == '}') break;
    final match = head.firstMatch(line);
    if (match == null) continue;
    final buffer = StringBuffer(line.trim());
    var depth = _parenDepth(line);
    while (depth > 0 && i + 1 < lines.length) {
      final next = _dartLine(lines[++i]).trim();
      buffer.write(' $next');
      depth += _parenDepth(next);
    }
    var text = buffer.toString();
    final open = text.indexOf('(');
    final bodyAt = text.indexOf(RegExp(r'\{|=>|;'));
    var close = 0;
    if (open != -1 && (bodyAt == -1 || open < bodyAt)) {
      var nested = 0;
      for (var k = open; k < text.length; k++) {
        if (text[k] == '(') nested++;
        if (text[k] == ')' && --nested == 0) {
          close = k + 1;
          break;
        }
      }
    }
    final end = text.indexOf(RegExp(r'\{|=>|;'), close);
    if (end != -1) text = text.substring(0, end);
    members[match.group(1)!] = text
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'\s*,\s*\)'), ')')
        .replaceAll(RegExp(r'\s*(async\*?|sync\*)\s*$'), '')
        .trim();
  }
  return members;
}

void main() {
  test('the checked-in tree is the $_defaultProfile profile', () {
    expect(
      _read('pubspec.yaml'),
      _read('pubspec.$_defaultProfile.yaml'),
      reason: 'pubspec.yaml is a copy of pubspec.$_defaultProfile.yaml',
    );
    expect(
      _read('lib/services/translation_service.dart'),
      _read(_disabledTranslationTemplate),
      reason: 'the live translation service is a copy of its template',
    );
    expect(
      _read('lib/services/image_codec_backend.dart'),
      _read(_onnxTemplate),
      reason: 'the live image codec backend is a copy of its template',
    );
  });

  test('the pubspec profiles differ only in their own packages', () {
    final deps = {
      for (final profile in _profiles)
        profile: _section(_read('pubspec.$profile.yaml'), 'dependencies'),
    };
    Set<String> only(String a, String b) =>
        deps[a]!.keys.toSet().difference(deps[b]!.keys.toSet());
    expect(only('lite-aeic', 'lite'), {'flutter_onnxruntime'});
    expect(only('lite', 'lite-aeic'), isEmpty);
    expect(only('full', 'lite-aeic'), {'llamadart', 'flutter_langdetect'});
    expect(only('lite-aeic', 'full'), isEmpty);
    for (final package in deps['lite']!.keys) {
      for (final profile in _profiles) {
        expect(
          deps[profile]![package],
          deps['lite']![package],
          reason: '$package in pubspec.$profile.yaml',
        );
      }
    }
    for (final profile in _profiles) {
      expect(
        _section(_read('pubspec.$profile.yaml'), 'hooks').isNotEmpty,
        profile == 'full',
        reason: 'the llamadart hooks belong to the full profile alone',
      );
    }
    final rest = {
      for (final profile in _profiles)
        profile: _outside(_read('pubspec.$profile.yaml'), {
          'dependencies',
          'hooks',
        }),
    };
    expect(rest['lite'], rest['lite-aeic']);
    expect(rest['full'], rest['lite-aeic']);
  });

  test('both image codec templates declare the same backend API', () {
    final onnx = _read(_onnxTemplate);
    final disabled = _read(_disabledCodecTemplate);
    expect(
      _publicMembers(disabled, 'ImageCodecBackend'),
      _publicMembers(onnx, 'ImageCodecBackend'),
    );
    for (final declaration in const [
      'const bool kImageCodecBitstreamPathAvailable',
      'ImageCodecBackend? createImageCodecBackend()',
      'class ImageCodecCancelled implements Exception',
      'class AeicRansCoders implements AeicRansCoderFactory',
    ]) {
      expect(onnx, contains(declaration));
      expect(disabled, contains(declaration));
    }
    expect(onnx, contains('const bool kImageCodecFeatureAvailable = true;'));
    expect(
      disabled,
      contains('const bool kImageCodecFeatureAvailable = false;'),
    );
  });

  test('the LLM translation template keeps the API the app compiles against', () {
    final stub = _publicMembers(
      _read(_disabledTranslationTemplate),
      'TranslationService',
    );
    final llm = _publicMembers(_read(_llmTemplate), 'TranslationService');
    expect(stub, isNotEmpty);
    for (final member in stub.entries) {
      expect(
        llm[member.key],
        member.value,
        reason: '${member.key} in the llm template',
      );
    }
  });
}
