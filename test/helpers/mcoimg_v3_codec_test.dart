import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/channel_binary_data_helper.dart';
import 'package:meshcore_open/helpers/channel_app_data_helper.dart';
import 'package:meshcore_open/helpers/mcoimg_types.dart';
import 'package:meshcore_open/helpers/mcoimg_v3_codec.dart';

void main() {
  final codec = MCOImageV3Codec();

  group('MCOImageV3Codec roundtrip', () {
    test('mono checkerboard body roundtrips', () {
      final image = _image(
        8,
        8,
        (x, y) => (x + y) & 1,
        profile: PaletteProfile.mono,
      );
      final encoded = codec.encode(image);
      final decoded = codec.decodeBody(encoded.body);

      expect(
        encoded.subtypeVersion,
        ChannelAppDataHelper.mcoImageV3SubtypeVersion,
      );
      expect(encoded.byteLength, encoded.body.length);
      expect(encoded.encodedCandidate.text, isEmpty);
      expect(encoded.encodedCandidate.container, MCOImageV3Container.block.name);
      expect(decoded.width, image.width);
      expect(decoded.height, image.height);
      expect(decoded.paletteProfile, image.paletteProfile);
      expect(decoded.encodingVersion, MCOImageEncodingVersion.v3);
      expect(decoded.pixels, image.pixels);
    });

    test('dynamic palette body roundtrips', () {
      final image = _image(
        9,
        7,
        (x, y) => switch ((x + y) % 4) {
          0 => 0,
          1 => 1,
          2 => 2,
          _ => 7,
        },
        profile: PaletteProfile.dynamicGlobal8,
      );
      final encoded = codec.encode(image);
      final decoded = codec.decodeBody(encoded.body);

      expect(decoded.paletteProfile, PaletteProfile.dynamicGlobal8);
      expect(decoded.pixels, image.pixels);
    });

    test('transparency metadata roundtrips', () {
      final image = _image(
        5,
        5,
        (x, y) => x == y ? 1 : 0,
        profile: PaletteProfile.master4,
        transparentColor: 0,
      );
      final encoded = codec.encode(image);
      final decoded = codec.decodeBody(encoded.body);

      expect(decoded.transparentColor, 0);
      expect(decoded.pixels, image.pixels);
    });

    test('solid image uses solid background container', () {
      final image = _image(
        11,
        11,
        (_, _) => 3,
        profile: PaletteProfile.master8,
      );
      final encoded = codec.encode(image);
      final decoded = codec.decodeBody(encoded.body);

      expect(
        encoded.encodedCandidate.container,
        MCOImageV3Container.solidBackground.name,
      );
      expect(decoded.pixels, image.pixels);
    });
  });

  group('MCOImageV3Codec app payload', () {
    test('payload without sender is subtypeVersion followed by body', () {
      final image = _image(4, 4, (x, y) => (x + y) & 1);
      final encoded = codec.encode(image);
      final payload = encoded.toAppPayloadWithoutSender();

      expect(payload.first, ChannelAppDataHelper.mcoImageV3SubtypeVersion);
      expect(
        Uint8List.sublistView(payload, 1),
        encoded.body,
      );

      final decoded = codec.decodeAppPayloadWithoutSender(payload);
      expect(decoded.pixels, image.pixels);
    });

    test('full app envelope carries sender and MCOimg v3 subtype', () {
      final image = _image(4, 4, (x, y) => (x + y) & 1);
      final encoded = codec.encode(image);
      final envelope = ChannelAppDataHelper.encodeEnvelope(
        senderName: 'botQRC',
        subtypeVersion: encoded.subtypeVersion,
        body: encoded.body,
      );

      expect(
        envelope.length,
        ChannelAppDataHelper.envelopeLength(
          bodyLength: encoded.body.length,
          senderName: 'botQRC',
        ),
      );

      final decodedEnvelope = ChannelAppDataHelper.tryDecodeEnvelope(envelope);
      expect(decodedEnvelope, isNotNull);
      expect(decodedEnvelope!.senderName, 'botQRC');
      expect(decodedEnvelope.subtype, ChannelAppDataSubtype.mcoImageV3);
      expect(decodedEnvelope.subtypeVersion, encoded.subtypeVersion);
      expect(codec.decodeBody(decodedEnvelope.body).pixels, image.pixels);
    });

    test('channel binary helper decodes app data separately from legacy text', () {
      final image = _image(4, 4, (x, y) => (x + y) & 1);
      final encoded = codec.encode(image);
      final payload = ChannelAppDataHelper.encodeEnvelope(
        senderName: 'botQRC',
        subtypeVersion: encoded.subtypeVersion,
        body: encoded.body,
      );

      final legacyDecoded = ChannelBinaryDataHelper.tryDecodeInbound(
        dataType: ChannelBinaryDataHelper.appDataType,
        payload: payload,
      );
      expect(legacyDecoded, isNull);

      final appDecoded = ChannelBinaryDataHelper.tryDecodeAppData(
        dataType: ChannelBinaryDataHelper.appDataType,
        payload: payload,
      );
      expect(appDecoded, isNotNull);
      expect(appDecoded!.senderName, 'botQRC');
      expect(appDecoded.subtype, ChannelAppDataSubtype.mcoImageV3);
      expect(appDecoded.mcoImage!.pixels, image.pixels);
    });
  });
}

MCOImage _image(
  int width,
  int height,
  int Function(int x, int y) colorAt, {
  PaletteProfile profile = PaletteProfile.master8,
  int? transparentColor,
}) {
  return MCOImage(
    width: width,
    height: height,
    paletteProfile: profile,
    pixels: [
      for (var y = 0; y < height; y++)
        for (var x = 0; x < width; x++) colorAt(x, y),
    ],
    transparentColor: transparentColor,
    encodingVersion: MCOImageEncodingVersion.v3,
  );
}
