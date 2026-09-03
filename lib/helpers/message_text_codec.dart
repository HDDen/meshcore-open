import 'mcmp_app_codec.dart';
import 'mcotxt_app_codec.dart';
import 'mesh_compressor.dart';
import 'smaz.dart';

class DecodedMessageText {
  final String text;
  final DecodedMcmpAppMessage? mcmpMessage;
  final DecodedMcotxtAppMessage? mcotxtMessage;

  const DecodedMessageText({
    required this.text,
    this.mcmpMessage,
    this.mcotxtMessage,
  });
}

class MessageTextCodec {
  static String? tryDecodeKnownCompression(String text) {
    return tryDecodeKnownCompressionDetails(text)?.text;
  }

  static DecodedMessageText? tryDecodeKnownCompressionDetails(String text) {
    final mcmpMessage = McmpAppCodec.tryDecodeTextPayloadMessage(text);
    if (mcmpMessage != null) {
      return DecodedMessageText(
        text: mcmpMessage.text,
        mcmpMessage: mcmpMessage,
      );
    }
    final mcotxtMessage = McotxtAppCodec.tryDecodeTextPayloadMessage(text);
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
