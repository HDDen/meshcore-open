import 'dart:convert';
import 'dart:io';

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
  final sourceFile = File('${scriptDirectory.path}/v2-fixture-cases.json');
  final outputFile = File(
    arguments.isNotEmpty
        ? arguments.first
        : '${scriptDirectory.path}/v2-dart-fixtures.json',
  );
  final source = jsonDecode(await sourceFile.readAsString()) as Map<String, dynamic>;
  final cases = source['cases'] as List<dynamic>;
  final codec = MCOImageCodec();
  final fixtures = <Map<String, dynamic>>[];

  for (final raw in cases) {
    final fixture = Map<String, dynamic>.from(raw as Map);
    final width = fixture['width'] as int;
    final height = fixture['height'] as int;
    final profile = _paletteProfile(fixture['paletteProfile'] as String);
    final pixels = List<int>.from(fixture['pixels'] as List);
    final transparentColor = fixture['transparentColor'] as int?;
    final image = MCOImage(
      width: width,
      height: height,
      paletteProfile: profile,
      pixels: pixels,
      transparentColor: transparentColor,
      encodingVersion: MCOImageEncodingVersion.v2,
    );
    final result = codec.encode(
      image,
      encodingVersion: MCOImageEncodingVersion.v2,
      outputTarget: MCOImageOutputTarget.binary,
      compressionLevel: _compressionLevel(fixture['compressionLevel'] as String),
      maxRegions: fixture['maxRegions'] as int,
    );
    final decoded = codec.decode(MCOImageCodec.textFromBinaryPayload(result.payload));
    if (decoded.width != width ||
        decoded.height != height ||
        decoded.paletteProfile != profile ||
        decoded.transparentColor != transparentColor ||
        !_sameInts(decoded.pixels, pixels)) {
      throw StateError('${fixture['name']}: Dart self round-trip failed');
    }
    fixtures.add(<String, dynamic>{
      ...fixture,
      'payloadBase64': base64Encode(result.payload),
      'text': MCOImageCodec.textFromBinaryPayload(result.payload),
      'byteLength': result.byteLength,
      'charLength': result.charLength,
      'mode': result.mode.name,
      'scan': result.scan.name,
      'container': result.container,
      'backgroundColor': result.backgroundColor,
      'regionCount': result.regionCount,
      'dynamicReferenceEncoding': result.dynamicReferenceEncoding?.name,
    });
  }

  await outputFile.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
      'schema': 1,
      'generator': 'lib/helpers/mcoimg_codec.dart',
      'fixtures': fixtures,
    })}\n',
  );
  stdout.writeln(outputFile.path);
}

bool _sameInts(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
