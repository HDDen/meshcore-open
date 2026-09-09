import 'mcmp_app_codec.dart';
import 'mcotxt_app_codec.dart';
import 'mesh_compressor.dart';
import 'smaz.dart';

class DecodedMessageText {
  final String text;
  final DecodedMcmpAppMessage? mcmpMessage;
  final DecodedMCOtxtAppMessage? mcotxtMessage;

  const DecodedMessageText({
    required this.text,
    this.mcmpMessage,
    this.mcotxtMessage,
  });
}

class MessageTextCodec {
  static String? tryDecodeKnownCompression(
    String text, {
    int? inheritedTimestamp,
  }) {
    return tryDecodeKnownCompressionDetails(
      text,
      inheritedTimestamp: inheritedTimestamp,
    )?.text;
  }

  static DecodedMessageText? tryDecodeKnownCompressionDetails(
    String text, {
    int? inheritedTimestamp,
  }) {
    final trimmedLeft = text.trimLeft();
    if (trimmedLeft.startsWith(McmpAppCodec.textPrefix)) {
      final message = McmpAppCodec.tryDecodeTextPayloadMessage(text);
      return message == null
          ? null
          : DecodedMessageText(text: message.text, mcmpMessage: message);
    }

    if (trimmedLeft.startsWith(MCOtxtAppCodec.textPrefix)) {
      final message = MCOtxtAppCodec.tryDecodeTextPayloadMessage(
        text,
        inheritedTimestamp: inheritedTimestamp,
      );
      return message == null
          ? null
          : DecodedMessageText(text: message.text, mcotxtMessage: message);
    }

    String? decodedText;
    if (trimmedLeft.startsWith(MeshCompressor.prefix) ||
        trimmedLeft.startsWith(MeshCompressor.legacyPrefix)) {
      decodedText = MeshCompressor.instance.tryDecodePrefixed(text);
    } else if (trimmedLeft.startsWith('s:')) {
      decodedText = Smaz.tryDecodePrefixed(text);
    }
    if (decodedText == null) return null;
    return DecodedMessageText(text: decodedText);
  }
}
