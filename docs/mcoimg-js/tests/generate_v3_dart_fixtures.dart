import 'dart:convert';
import 'dart:io';

import 'package:meshcore_open/helpers/mcoimg_types.dart';
import 'package:meshcore_open/helpers/mcoimg_v3_codec.dart';

int _compressionLevel(String name) {
  return switch (name.toLowerCase()) {
    'normal' => mcoImageCompressionLevelNormal,
    'extreme' => mcoImageCompressionLevelExtreme,
    _ => mcoImageCompressionLevelHigh,
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
        : '${scriptDirectory.path}/v3-dart-fixtures.json',
  );
  final source =
      jsonDecode(await sourceFile.readAsString()) as Map<String, dynamic>;
  final cases = source['cases'] as List<dynamic>;
  final codec = MCOImageV3Codec();
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
      encodingVersion: MCOImageEncodingVersion.v3,
    );
    final encoded = codec.encode(
      image,
      compressionLevel: _compressionLevel(
        fixture['compressionLevel'] as String,
      ),
    );
    final decoded = codec.decodeBody(encoded.body);
    if (decoded.width != width ||
        decoded.height != height ||
        decoded.paletteProfile != profile ||
        decoded.transparentColor != transparentColor ||
        !_sameInts(decoded.pixels, pixels)) {
      throw StateError('${fixture['name']}: Dart v3 self round-trip failed');
    }
    final appPayload = encoded.toAppPayloadWithoutSender();
    final text = MCOImageV3Codec.textFromBody(encoded.body);
    final candidate = encoded.encodedCandidate;
    fixtures.add(<String, dynamic>{
      ...fixture,
      'bodyBase64': base64Encode(encoded.body),
      'appPayloadBase64': base64Encode(appPayload),
      'text': text,
      'byteLength': encoded.byteLength,
      'subtypeVersion': encoded.subtypeVersion,
      'mode': candidate.mode.name,
      'scan': candidate.scan.name,
      'container': candidate.container,
      'backgroundColor': candidate.backgroundColor,
      'regionCount': candidate.regionCount,
      'dynamicReferenceEncoding': candidate.dynamicReferenceEncoding?.name,
    });
  }

  await outputFile.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(<String, dynamic>{'schema': 1, 'generator': 'lib/helpers/mcoimg_v3_codec.dart', 'fixtures': fixtures})}\n',
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
