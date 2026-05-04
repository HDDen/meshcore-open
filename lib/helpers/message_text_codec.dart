import 'mesh_compressor.dart';
import 'smaz.dart';

class MessageTextCodec {
  static String? tryDecodeKnownCompression(String text) {
    return MeshCompressor.instance.tryDecodePrefixed(text) ??
        Smaz.tryDecodePrefixed(text);
  }
}
