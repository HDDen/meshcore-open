import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/MCOtxt/mcotxt.dart';
import 'package:meshcore_open/helpers/channel_app_data_helper.dart';
import 'package:meshcore_open/helpers/mcotxt_app_codec.dart';

import '../../tool/mcotxt_js_reference.dart';

void main() {
  late Map<String, Object?> reference;
  setUpAll(() {
    reference = buildMCOtxtJsReference();
  });
  tearDown(() => MCOtxtCodec.defaultLanguagePair = null);

  test('frozen JS reference matches the unchanged Dart codec byte for byte', () {
    final fixture = File(mcotxtJsFixturePath);
    expect(
      fixture.existsSync(),
      isTrue,
      reason: 'First run: dart --packages=.dart_tool/package_config.json '
          'tool/mcotxt_js_reference.dart --write',
    );
    expect(reference, jsonDecode(fixture.readAsStringSync()));
  });

  for (final sample in mcotxtJsCases) {
    test('reference container and transports match the app: ${sample.id}', () {
      final cases = reference['cases']! as List<Object?>;
      final entry = cases.cast<Map<String, Object?>>().singleWhere(
        (entry) => entry['id'] == sample.id,
      );
      final expected = entry['expected']! as Map<String, Object?>;
      MCOtxtCodec.defaultLanguagePair = sample.pair;
      final body = MCOtxtAppCodec.encodeBody(
        text: sample.text,
        timestamp: sample.timestamp,
        senderName: sample.senderName,
        replyAuthorName: sample.replyAuthorName,
        replyTimestamp: sample.replyTimestamp,
        includeTimestamp: sample.includeTimestamp,
      );
      expect(mcotxtReferenceHex(body), expected['bodyHex']);
      expect(body.length, expected['bodyBytes']);
      final transport = MCOtxtAppCodec.textFromBody(body);
      expect(transport, expected['mct']);
      expect(MCOtxtAppCodec.bodyFromText(transport), body);

      final decoded = MCOtxtAppCodec.decodeBody(body);
      expect(decoded.text, expected['text']);
      expect(decoded.timestamp, expected['timestamp']);
      expect(decoded.senderName, expected['senderName']);
      expect(decoded.replyAuthorName, expected['replyAuthorName']);
      expect(decoded.replyTimestamp, expected['replyTimestamp']);
      if (!sample.includeTimestamp) {
        expect(
          MCOtxtAppCodec.decodeBody(body, inheritedTimestamp: 123).timestamp,
          123,
        );
      }

      final envelopeHex = expected['envelopeHex'];
      if (envelopeHex != null) {
        final envelope = ChannelAppDataHelper.encodeEnvelope(
          senderName: sample.outerSenderName,
          subtypeId: MCOtxtAppCodec.subtypeId,
          version: MCOtxtAppCodec.wireVersion,
          body: body,
        );
        expect(mcotxtReferenceHex(envelope), envelopeHex);
        final decodedEnvelope = ChannelAppDataHelper.tryDecodeEnvelope(envelope);
        expect(decodedEnvelope, isNotNull);
        expect(decodedEnvelope!.body, body);
        expect(decodedEnvelope.subtypeId, 3);
        expect(decodedEnvelope.version, 1);
      }
    });
  }
}
