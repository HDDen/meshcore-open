import '../helpers/mcoimg_types.dart';
import '../helpers/mcoimg_v3_codec.dart';
import '../helpers/mcoimg_v4_model.dart';

class CanvasEditorResult {
  final String text;
  final EncodedMCOImage? encodedImage;
  final EncodedMCOImageV4? encodedImageV4;
  final MCOImage? rasterImage;

  CanvasEditorResult._({
    required this.text,
    this.encodedImage,
    this.encodedImageV4,
    this.rasterImage,
  });

  factory CanvasEditorResult.fromEncoded(EncodedMCOImage encoded) {
    return CanvasEditorResult._(
      text: encoded.actualEncodingVersion == MCOImageEncodingVersion.v3
          ? MCOImageV3Codec.textFromBody(encoded.payload)
          : encoded.text,
      encodedImage: encoded,
    );
  }

  factory CanvasEditorResult.fromV4({
    required String text,
    required EncodedMCOImageV4 encoded,
  }) {
    return CanvasEditorResult._(text: text, encodedImageV4: encoded);
  }

  factory CanvasEditorResult.fromRasterImage(MCOImage image) {
    return CanvasEditorResult._(text: '', rasterImage: image);
  }

  bool get isMcoImageV3 =>
      encodedImage?.actualEncodingVersion == MCOImageEncodingVersion.v3;

  EncodedMCOImageV3? get mcoImageV3 {
    if (!isMcoImageV3) return null;
    return EncodedMCOImageV3(
      body: encodedImage!.payload,
      byteLength: encodedImage!.payload.length,
      encodedCandidate: encodedImage!,
    );
  }
}
