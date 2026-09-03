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
    String? inheritedSenderName,
  }) {
    return tryDecodeKnownCompressionDetails(
      text,
      inheritedTimestamp: inheritedTimestamp,
      inheritedSenderName: inheritedSenderName,
    )?.text;
  }

  static DecodedMessageText? tryDecodeKnownCompressionDetails(
    String text, {
    int? inheritedTimestamp,
    String? inheritedSenderName,
  }) {
    final mcmpMessage = McmpAppCodec.tryDecodeTextPayloadMessage(text);
    if (mcmpMessage != null) {
      return DecodedMessageText(
        text: mcmpMessage.text,
        mcmpMessage: mcmpMessage,
      );
    }
    final mcotxtMessage = MCOtxtAppCodec.tryDecodeTextPayloadMessage(
      text,
      inheritedTimestamp: inheritedTimestamp,
      inheritedSenderName: inheritedSenderName,
    );
    if (mcotxtMessage != null) {
      return DecodedMessageText(
        text: mcotxtMessage.text,
        mcotxtMessage: mcotxtMessage,
      );
    }
    final decodedText =
        MeshCompressor.instance.tryDecodePrefixed(text) ??
        Smaz.tryDecodePrefixed(text);
    if (decodedText == null) return null;
    return DecodedMessageText(text: decodedText);
  }
}
