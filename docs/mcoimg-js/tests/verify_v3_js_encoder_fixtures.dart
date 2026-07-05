import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:meshcore_open/helpers/mcoimg_types.dart';
import 'package:meshcore_open/helpers/mcoimg_v3_codec.dart';

PaletteProfile _paletteProfile(String name) {
  return PaletteProfile.values.firstWhere(
    (value) => value.name == name,
    orElse: () => throw ArgumentError('Unknown palette profile: $name'),
  );
}

Future<void> main(List<String> arguments) async {
  final scriptDirectory = File.fromUri(Platform.script).parent;
  final fixtureFile = File(
    arguments.isNotEmpty
        ? arguments.first
        : '${scriptDirectory.path}/v3-js-encoder-fixtures.json',
  );
  final document = jsonDecode(await fixtureFile.readAsString()) as Map<String, dynamic>;
  final fixtures = document['fixtures'] as List<dynamic>;
  final codec = MCOImageV3Codec();
  final summaries = <Map<String, dynamic>>[];

  for (final raw in fixtures) {
    final fixture = Map<String, dynamic>.from(raw as Map);
    final name = fixture['name'] as String;
    final body = Uint8List.fromList(base64Decode(fixture['bodyBase64'] as String));
    final appPayload = Uint8List.fromList(
      base64Decode(fixture['appPayloadBase64'] as String),
    );
    final profile = _paletteProfile(fixture['paletteProfile'] as String);
    final pixels = List<int>.from(fixture['pixels'] as List);
    final transparentColor = fixture['transparentColor'] as int?;

    final decoded = <String, MCOImage>{
      'body': codec.decodeBody(body),
      'app': codec.decodeAppPayloadWithoutSender(appPayload),
      'text': codec.decodeText(fixture['text'] as String),
    };
    for (final entry in decoded.entries) {
      final image = entry.value;
      if (image.width != fixture['width'] ||
          image.height != fixture['height'] ||
          image.paletteProfile != profile ||
          image.transparentColor != transparentColor ||
          !_sameInts(image.pixels, pixels)) {
        throw StateError('$name: Dart ${entry.key} decode mismatch');
      }
    }
    if (!_sameInts(MCOImageV3Codec.bodyFromText(fixture['text'] as String), body)) {
      throw StateError('$name: Dart text/body conversion mismatch');
    }
    summaries.add(<String, dynamic>{
      'name': name,
      'bytes': body.length,
      'container': fixture['container'],
      'algorithm': fixture['algorithm'],
    });
  }

  stdout.writeln(const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
    'fixtureFile': fixtureFile.path,
    'generator': document['generator'] ?? 'unknown',
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
