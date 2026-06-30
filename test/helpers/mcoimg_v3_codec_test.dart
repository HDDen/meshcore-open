import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/channel_binary_data_helper.dart';
import 'package:meshcore_open/helpers/channel_app_data_helper.dart';
import 'package:meshcore_open/helpers/mcoimg_palette.dart';
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
      expect(
        encoded.encodedCandidate.container,
        MCOImageV3Container.compactBlock.name,
      );
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
      expect(encoded.body.length, 5);
      expect(decoded.pixels, image.pixels);
    });

    test('small drawing inside large background uses bounds block', () {
      final image = _image(
        32,
        32,
        (x, y) {
          if (x >= 12 && x < 20 && y >= 10 && y < 18) {
            return ((x + y) & 1) == 0 ? 3 : 5;
          }
          return 0;
        },
        profile: PaletteProfile.master8,
      );
      final encoded = codec.encode(image, backgroundColor: 0);
      final decoded = codec.decodeBody(encoded.body);

      expect(
        encoded.encodedCandidate.container,
        MCOImageV3Container.compactBoundsBlock.name,
      );
      expect(encoded.encodedCandidate.boundsPresent, isTrue);
      expect(encoded.encodedCandidate.boundsX, 12);
      expect(encoded.encodedCandidate.boundsY, 10);
      expect(encoded.encodedCandidate.boundsWidth, 8);
      expect(encoded.encodedCandidate.boundsHeight, 8);
      expect(decoded.pixels, image.pixels);
    });

    test('separate drawings can use compact regions stream', () {
      final image = _image(
        32,
        32,
        (x, y) {
          final inFirst = x >= 3 && x < 11 && y >= 4 && y < 12;
          final inSecond = x >= 21 && x < 29 && y >= 19 && y < 27;
          if (inFirst || inSecond) return ((x + y) & 1) == 0 ? 2 : 6;
          return 0;
        },
        profile: PaletteProfile.master8,
      );
      final encoded = codec.encode(image, backgroundColor: 0);
      final decoded = codec.decodeBody(encoded.body);

      expect(
        encoded.encodedCandidate.container,
        startsWith(MCOImageV3Container.compactRegionsStream.name),
      );
      expect(encoded.encodedCandidate.regionCount, 2);
      expect(decoded.pixels, image.pixels);
    });

    test('compact regions stream can share one region block header', () {
      final image = _image(
        40,
        12,
        (x, y) {
          final inFirst = x >= 2 && x < 6 && y >= 2 && y < 6;
          final inSecond = x >= 13 && x < 17 && y >= 2 && y < 6;
          final inThird = x >= 24 && x < 28 && y >= 2 && y < 6;
          if (inFirst || inSecond || inThird) return x.isEven ? 2 : 6;
          return 0;
        },
        profile: PaletteProfile.master8,
      );
      final encoded = codec.encode(image, backgroundColor: 0);
      final decoded = codec.decodeBody(encoded.body);

      expect(
        encoded.encodedCandidate.container,
        startsWith('${MCOImageV3Container.compactRegionsStream.name}-common'),
      );
      expect(encoded.encodedCandidate.regionCount, 3);
      expect(decoded.pixels, image.pixels);
    });

    test('compact regions stream can delta-code region geometry', () {
      final image = _image(
        48,
        12,
        (x, y) {
          final inFirst = x >= 2 && x < 5 && y >= 2 && y < 5;
          final inSecond = x >= 10 && x < 13 && y >= 2 && y < 5;
          final inThird = x >= 18 && x < 21 && y >= 2 && y < 5;
          final inFourth = x >= 26 && x < 29 && y >= 2 && y < 5;
          if (inFirst || inSecond || inThird || inFourth) {
            return x.isEven ? 2 : 6;
          }
          return 0;
        },
        profile: PaletteProfile.master8,
      );
      final encoded = codec.encode(image, backgroundColor: 0);
      final decoded = codec.decodeBody(encoded.body);

      expect(
        encoded.encodedCandidate.container,
        contains('delta'),
      );
      expect(encoded.encodedCandidate.regionCount, 4);
      expect(decoded.pixels, image.pixels);
    });

    test('compact regions stream can share one local palette', () {
      final image = _image(
        56,
        12,
        (x, y) {
          final offsets = [2, 12, 22, 32, 42];
          final inRegion = offsets.any(
            (offset) => x >= offset && x < offset + 4 && y >= 2 && y < 6,
          );
          if (!inRegion) return 0;
          return switch ((x + y) % 4) {
            0 => 2,
            1 => 3,
            2 => 5,
            _ => 6,
          };
        },
        profile: PaletteProfile.master8,
      );
      final encoded = codec.encode(image, backgroundColor: 0);
      final decoded = codec.decodeBody(encoded.body);

      expect(
        encoded.encodedCandidate.container,
        contains('shared'),
      );
      expect(encoded.encodedCandidate.regionCount, 5);
      expect(decoded.pixels, image.pixels);
    });

    test('long runs can use compact RLE algorithm', () {
      final image = _image(
        24,
        1,
        (x, _) {
          if (x < 8) return 0;
          if (x < 16) return 4;
          return 1;
        },
        profile: PaletteProfile.master8,
      );
      final encoded = codec.encode(image);
      final decoded = codec.decodeBody(encoded.body);

      expect(encoded.encodedCandidate.mode, ImageMode.extended);
      expect(decoded.pixels, image.pixels);
    });

    test('sparse multicolor image roundtrips through compact sparse candidates', () {
      final image = _image(
        24,
        24,
        (x, y) {
          if (x == 1 && y == 1) return 2;
          if (x >= 10 && x < 13 && y == 8) return 4;
          if (x == 22 && y >= 19 && y < 23) return 6;
          return 0;
        },
        profile: PaletteProfile.master8,
      );
      final encoded = codec.encode(image, backgroundColor: 0);
      final decoded = codec.decodeBody(encoded.body);

      expect(
        encoded.encodedCandidate.mode,
        anyOf(ImageMode.extended, ImageMode.sparseBg, ImageMode.regionsBg),
      );
      expect(decoded.pixels, image.pixels);
    });

    test('repeated pixel patterns can use LZ pixels candidates', () {
      final pattern = [0, 1, 2, 3, 2, 1];
      final image = _image(
        36,
        1,
        (x, _) => pattern[x % pattern.length],
        profile: PaletteProfile.master8,
      );
      final encoded = codec.encode(image);
      final decoded = codec.decodeBody(encoded.body);

      expect(encoded.encodedCandidate.mode, ImageMode.extended);
      expect(decoded.pixels, image.pixels);
    });

    test('large solid quadrants can use quadtree algorithm', () {
      final image = _image(
        16,
        16,
        (x, y) {
          if (x < 8 && y < 8) return 0;
          if (x >= 8 && y < 8) return 2;
          if (x < 8 && y >= 8) return 4;
          return 6;
        },
        profile: PaletteProfile.master8,
      );
      final encoded = codec.encode(image);
      final decoded = codec.decodeBody(encoded.body);
      final algorithmId = encoded.body[3] & 0x1f;

      expect(algorithmId, MCOImageV3BlockAlgorithm.quadtree.index);
      expect(decoded.pixels, image.pixels);
    });

    test('structured color planes can use bitplanes algorithm', () {
      final image = _image(
        16,
        16,
        (x, y) {
          final lowBit = x < 8 ? 0 : 1;
          final highBit = y < 8 ? 0 : 2;
          return lowBit | highBit;
        },
        profile: PaletteProfile.master8,
      );
      final encoded = codec.encode(image);
      final decoded = codec.decodeBody(encoded.body);
      final algorithmId = encoded.body[3] & 0x1f;

      expect(algorithmId, MCOImageV3BlockAlgorithm.bitplanes.index);
      expect(decoded.pixels, image.pixels);
    });

    test('sparse color planes can use adaptive bitplanes algorithm', () {
      final image = _image(
        24,
        24,
        (x, y) {
          if (x == 5 && y == 5) return 3;
          if (x == 18 && y == 12) return 7;
          return 0;
        },
        profile: PaletteProfile.master8,
      );
      final encoded = codec.encode(image, backgroundColor: 0);
      final decoded = codec.decodeBody(encoded.body);
      final algorithmId = encoded.body[3] & 0x1f;

      expect(algorithmId, MCOImageV3BlockAlgorithm.adaptiveBitplanes.index);
      expect(decoded.pixels, image.pixels);
    });

    test('rows with small changes can use compact row delta algorithm', () {
      final image = _image(
        16,
        12,
        (x, y) {
          if (y == 0) return x.isEven ? 1 : 2;
          if (x == y % 16) return 3;
          if (x == (y * 3) % 16) return 4;
          return x.isEven ? 1 : 2;
        },
        profile: PaletteProfile.master8,
      );
      final encoded = codec.encode(image);
      final decoded = codec.decodeBody(encoded.body);
      final algorithmId = encoded.body[3] & 0x1f;

      expect(algorithmId, MCOImageV3BlockAlgorithm.compactRowDelta.index);
      expect(decoded.pixels, image.pixels);
    });

    test('shifted rows roundtrip through compact row delta predictors', () {
      final base = [1, 2, 3, 4, 1, 2, 3, 4];
      final image = _image(
        8,
        8,
        (x, y) => base[(x - y) % base.length],
        profile: PaletteProfile.master8,
      );
      final encoded = codec.encode(image);
      final decoded = codec.decodeBody(encoded.body);
      final algorithmId = encoded.body[3] & 0x1f;

      expect(algorithmId, MCOImageV3BlockAlgorithm.compactRowDelta.index);
      expect(decoded.pixels, image.pixels);
    });

    test('grayscale levels can use direct grayscale bitplanes', () {
      final image = _image(
        16,
        16,
        (x, y) => (x + y) % 16,
        profile: PaletteProfile.grayscale16,
      );
      final encoded = codec.encode(image);
      final decoded = codec.decodeBody(encoded.body);
      final algorithmId = encoded.body[3] & 0x1f;

      expect(
        algorithmId,
        MCOImageV3BlockAlgorithm.directGrayscaleBitplanes.index,
      );
      expect(decoded.pixels, image.pixels);
    });

    test('grayscale rows can use direct grayscale row delta', () {
      final image = _image(
        16,
        14,
        (x, y) {
          if (y == 0) return x;
          if (x == (y * 3) % 16) return (x + 1) % 16;
          if (x == (y * 5) % 16) return (x + 2) % 16;
          return x;
        },
        profile: PaletteProfile.grayscale16,
      );
      final encoded = codec.encode(image);
      final decoded = codec.decodeBody(encoded.body);
      final algorithmId = encoded.body[3] & 0x1f;

      expect(
        algorithmId,
        MCOImageV3BlockAlgorithm.directGrayscaleRowDelta.index,
      );
      expect(decoded.pixels, image.pixels);
    });

    test('dynamic profile colors can use direct dynamic bitplanes', () {
      final palette = MCOImageDynamicPalette.indicesFor(
        PaletteProfile.dynamicGlobal16,
      );
      final image = _image(
        16,
        16,
        (x, y) => palette[(x + y) % palette.length],
        profile: PaletteProfile.dynamicGlobal16,
      );
      final encoded = codec.encode(image);
      final decoded = codec.decodeBody(encoded.body);
      final algorithmId = encoded.body[3] & 0x1f;

      expect(
        algorithmId,
        MCOImageV3BlockAlgorithm.directDynamicBitplanes.index,
      );
      expect(decoded.pixels, image.pixels);
    });

    test('dynamic profile rows can use direct dynamic row delta', () {
      final palette = MCOImageDynamicPalette.indicesFor(
        PaletteProfile.dynamicGlobal16,
      );
      final image = _image(
        16,
        14,
        (x, y) {
          if (y == 0) return palette[x];
          if (x == (y * 3) % palette.length) {
            return palette[(x + 1) % palette.length];
          }
          if (x == (y * 5) % palette.length) {
            return palette[(x + 2) % palette.length];
          }
          return palette[x];
        },
        profile: PaletteProfile.dynamicGlobal16,
      );
      final encoded = codec.encode(image);
      final decoded = codec.decodeBody(encoded.body);
      final algorithmId = encoded.body[3] & 0x1f;

      expect(
        algorithmId,
        MCOImageV3BlockAlgorithm.directDynamicRowDelta.index,
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
