import 'dart:typed_data';

import 'channel_app_data_helper.dart';
import 'mcoimg_codec.dart';

class EncodedMCOImageV3 {
  final Uint8List body;
  final int byteLength;
  final int subtypeVersion;

  const EncodedMCOImageV3({
    required this.body,
    required this.byteLength,
    this.subtypeVersion = ChannelAppDataHelper.mcoImageV3SubtypeVersion,
  });

  Uint8List toAppPayloadWithoutSender() {
    return ChannelAppDataHelper.appPayloadWithoutSender(
      subtypeVersion: subtypeVersion,
      body: body,
    );
  }
}

class MCOImageV3Codec {
  MCOImageV3Codec();

  static const int subtypeVersion =
      ChannelAppDataHelper.mcoImageV3SubtypeVersion;

  /// MCOimg v3 is the binary-only image payload for the official 0x0120
  /// application data_type.
  ///
  /// This scaffold intentionally fails closed until the v2 image-body logic is
  /// physically moved into this file and its header is rewritten for v3. Keeping
  /// this separate from [MCOImageCodec] lets the old v1/v2 text/dev-binary codec
  /// remain stable while v3 evolves.
  EncodedMCOImageV3 encode(
    MCOImage image, {
    int? backgroundColor,
    MCOImageOutputTarget outputTarget = MCOImageOutputTarget.binary,
    int compressionLevel = MCOImageCodec.defaultCompressionLevel,
  }) {
    throw const MCOImageInvalidInputException(
      'MCOimg v3 encoder is not implemented yet',
    );
  }

  MCOImage decodeBody(Uint8List body) {
    throw const MCOImageInvalidPayloadException(
      'MCOimg v3 decoder is not implemented yet',
    );
  }
}
