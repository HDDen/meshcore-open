import 'mcmp_app_codec.dart';
import 'mesh_compressor.dart';
import 'smaz.dart';

class DecodedMessageText {
  final String text;
  final DecodedMcmpAppMessage? mcmpMessage;

  const DecodedMessageText({required this.text, this.mcmpMessage});
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
    final decodedText =
        MeshCompressor.instance.tryDecodePrefixed(text) ??
        Smaz.tryDecodePrefixed(text);
    if (decodedText == null) return null;
    return DecodedMessageText(text: decodedText);
  }
}
