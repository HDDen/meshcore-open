import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/channel_app_data_helper.dart';
import 'package:meshcore_open/helpers/channel_binary_data_helper.dart';

Uint8List _envelope({required int subtypeId, required int version}) {
  return ChannelAppDataHelper.encodeEnvelope(
    senderName: 'Alice',
    subtypeId: subtypeId,
    version: version,
    body: Uint8List.fromList([1, 2, 3, 4]),
  );
}

UnknownChannelAppData? _describe(Uint8List payload, {int? dataType}) {
  return ChannelBinaryDataHelper.tryDescribeUnknownAppData(
    dataType: dataType ?? ChannelAppDataHelper.appDataType,
    payload: payload,
  );
}

void main() {
  group('ChannelBinaryDataHelper.tryDescribeUnknownAppData', () {
    test('an unknown 0x0120 subtype is described with name and ids', () {
      final payload = _envelope(subtypeId: 0x0A, version: 2);
      expect(
        ChannelBinaryDataHelper.tryDecodeAppData(
          dataType: ChannelAppDataHelper.appDataType,
          payload: payload,
        ),
        isNull,
      );

      final unknown = _describe(payload);

      expect(unknown, isNotNull);
      expect(unknown!.dataType, 0x0120);
      expect(unknown.senderName, 'Alice');
      expect(unknown.subtypeId, 0x0A);
      expect(unknown.version, 2);
      expect(unknown.namespaceLabel, '0x0120 MCO Advanced');
    });

    test('an MCMP wire version this build does not know is described too', () {
      final payload = _envelope(
        subtypeId: ChannelAppDataHelper.mcmpSubtype,
        version: 7,
      );

      final unknown = _describe(payload);

      expect(unknown, isNotNull);
      expect(unknown!.subtypeId, ChannelAppDataHelper.mcmpSubtype);
      expect(unknown.version, 7);
    });

    test('a 0x0120 payload that is not an envelope keeps the namespace', () {
      final unknown = _describe(Uint8List(0));

      expect(unknown, isNotNull);
      expect(unknown!.dataType, 0x0120);
      expect(unknown.senderName, isNull);
      expect(unknown.subtypeId, isNull);
      expect(unknown.version, isNull);
    });

    test('a MeshCore Open packet is described by its namespace alone', () {
      final unknown = _describe(
        Uint8List.fromList([9, 8, 7]),
        dataType: ChannelBinaryDataHelper.meshCoreOpenDataType,
      );

      expect(unknown, isNotNull);
      expect(unknown!.dataType, 0x0100);
      expect(unknown.senderName, isNull);
      expect(unknown.subtypeId, isNull);
      expect(unknown.namespaceLabel, '0x0100 MeshCore Open');
    });

    test('a known subtype that decodes is not left for the describer', () {
      // MCOtxt of a foreign version reports its own placeholder text through
      // tryDecodeAppData, so the describer is never asked.
      final payload = _envelope(
        subtypeId: ChannelAppDataHelper.mcotxtSubtype,
        version: 9,
      );
      expect(
        ChannelBinaryDataHelper.tryDecodeAppData(
          dataType: ChannelAppDataHelper.appDataType,
          payload: payload,
        ),
        isNotNull,
      );
    });

    test('an unregistered data type is not ours to describe', () {
      final payload = _envelope(subtypeId: 0x0A, version: 2);
      expect(_describe(payload, dataType: 0x0121), isNull);
      expect(_describe(payload, dataType: 0xFFF1), isNull);
    });
  });

  group('UnknownChannelAppData sentinel', () {
    test('round-trips namespace, subtype and version, carries no name', () {
      const unknown = UnknownChannelAppData(
        dataType: 0x0120,
        senderName: 'Alice',
        subtypeId: 0x0A,
        version: 2,
      );
      expect(unknown.sentinelText, 'mcoapp-unknown:0x0120:10.2');

      final parsed = UnknownChannelAppData.parseSentinel(unknown.sentinelText);

      expect(parsed, isNotNull);
      expect(parsed!.dataType, 0x0120);
      expect(parsed.subtypeId, 0x0A);
      expect(parsed.version, 2);
      expect(parsed.senderName, isNull);
    });

    test('round-trips a namespace-only sentinel', () {
      const unknown = UnknownChannelAppData(dataType: 0x0100, senderName: null);
      expect(unknown.sentinelText, 'mcoapp-unknown:0x0100');

      final parsed = UnknownChannelAppData.parseSentinel(unknown.sentinelText);

      expect(parsed, isNotNull);
      expect(parsed!.dataType, 0x0100);
      expect(parsed.subtypeId, isNull);
      expect(parsed.version, isNull);
    });

    test('rejects anything that is not the sentinel', () {
      expect(UnknownChannelAppData.parseSentinel('hello'), isNull);
      expect(UnknownChannelAppData.parseSentinel('mcoapp-unknown:'), isNull);
      expect(UnknownChannelAppData.parseSentinel('mcoapp-unknown:10.2'), isNull);
      expect(
        UnknownChannelAppData.parseSentinel('mcoapp-unknown:0x0120:x.1'),
        isNull,
      );
      expect(
        UnknownChannelAppData.parseSentinel('mcoapp-unknown:0x0120:1'),
        isNull,
      );
    });
  });
}
