import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../../lib/helpers/mcoimg_codec.dart';

int _compressionLevel(String name) {
  return switch (name.toLowerCase()) {
    'normal' => MCOImageCodec.compressionLevelNormal,
    'extreme' => MCOImageCodec.compressionLevelExtreme,
    _ => MCOImageCodec.compressionLevelHigh,
  };
}

PaletteProfile _paletteProfile(String name) {
  return PaletteProfile.values.firstWhere(
    (value) => value.name == name,
    orElse: () => throw ArgumentError('Unknown palette profile: $name'),
  );
}

Future<void> main(List<String> arguments) async {
  final scriptDirectory = File.fromUri(Platform.script).parent;
  final positional = arguments.where((argument) => !argument.startsWith('--')).toList();
  final fixtureFile = File(
    positional.isNotEmpty
        ? positional.first
        : '${scriptDirectory.path}/v2-js-fixtures.json',
  );
  final decodeOnly = arguments.contains('--decode-only');
  final document = jsonDecode(await fixtureFile.readAsString()) as Map<String, dynamic>;
  final fixtures = document['fixtures'] as List<dynamic>;
  final codec = MCOImageCodec();
  final summaries = <Map<String, dynamic>>[];

  for (final raw in fixtures) {
    final fixture = Map<String, dynamic>.from(raw as Map);
    final name = fixture['name'] as String;
    final payload = Uint8List.fromList(base64Decode(fixture['payloadBase64'] as String));
    final decoded = codec.decode(MCOImageCodec.textFromBinaryPayload(payload));
    final profile = _paletteProfile(fixture['paletteProfile'] as String);
    final pixels = List<int>.from(fixture['pixels'] as List);
    final transparentColor = fixture['transparentColor'] as int?;
    if (decoded.width != fixture['width'] ||
        decoded.height != fixture['height'] ||
        decoded.paletteProfile != profile ||
        decoded.transparentColor != transparentColor ||
        !_sameInts(decoded.pixels, pixels)) {
      throw StateError('$name: Dart fixture decode mismatch');
    }
    final expectedText = MCOImageCodec.textFromBinaryPayload(payload);
    if (fixture['text'] != null && fixture['text'] != expectedText) {
      throw StateError('$name: Base91 text does not match the binary payload');
    }

    bool? exact;
    if (!decodeOnly) {
      final encoded = codec.encode(
        MCOImage(
          width: fixture['width'] as int,
          height: fixture['height'] as int,
          paletteProfile: profile,
          pixels: pixels,
          transparentColor: transparentColor,
          encodingVersion: MCOImageEncodingVersion.v2,
        ),
        encodingVersion: MCOImageEncodingVersion.v2,
        outputTarget: MCOImageOutputTarget.binary,
        compressionLevel: _compressionLevel(fixture['compressionLevel'] as String),
        maxRegions: fixture['maxRegions'] as int,
      );
      exact = _sameInts(encoded.payload, payload);
      if (!exact) {
        throw StateError(
          '$name: exact Dart encoder mismatch '
          '(${encoded.payload.length} vs ${payload.length} bytes)',
        );
      }
    }
    summaries.add(<String, dynamic>{
      'name': name,
      'bytes': payload.length,
      'exact': exact,
    });
  }

  stdout.writeln(const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
    'fixtureFile': fixtureFile.path,
    'generator': document['generator'] ?? 'unknown',
    'decodeOnly': decodeOnly,
    'fixtures': summaries,
  }));
}

bool _sameInts(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
