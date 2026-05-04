import 'model_text_compression.dart';
import 'smaz.dart';

class MessageTextCodec {
  static String decode(String text) {
    return ModelTextCompression.tryDecodePrefixed(text) ??
        Smaz.tryDecodePrefixed(text) ??
        text;
  }
}
