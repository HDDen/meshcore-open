import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/canvas_encoding_versions.dart';
import 'package:meshcore_open/helpers/mcoimg_codec.dart';

void main() {
  test('every imported format maps to exactly one supported editor choice', () {
    for (final source in MCOImageEncodingVersion.values) {
      final current = canvasEncodingVersionForImport(source);
      final choices = canvasEncodingVersions();
      expect(choices.where((item) => item == current), hasLength(1));
      expect(choices, [MCOImageEncodingVersion.v3, MCOImageEncodingVersion.v4]);
    }
  });

  test('reported v2 image decodes unchanged but is edited as v3', () {
    final bytes = Uint8List.fromList([0x82, 0x28, 0xff, 0xff]);
    final image = MCOImageCodec().decode(MCOImageCodec.textFromBinaryPayload(bytes));
    expect(image.encodingVersion, MCOImageEncodingVersion.v2);
    expect(canvasEncodingVersionForImport(image.encodingVersion), MCOImageEncodingVersion.v3);
    expect((image.width, image.height), (256, 256));
    expect(image.pixels.every((pixel) => pixel == 0), isTrue);
    // A legacy candidate cannot be reused as a result in the editor format.
    expect(image.encodingVersion == canvasEncodingVersionForImport(image.encodingVersion), isFalse);
  });

  test('legacy imports upgrade; modern formats and raster-layer policy stay unchanged', () {
    expect(canvasEncodingVersionForImport(MCOImageEncodingVersion.v1Legacy), MCOImageEncodingVersion.v3);
    for (final version in [MCOImageEncodingVersion.v3, MCOImageEncodingVersion.v4]) {
      expect(canvasEncodingVersionForImport(version), version);
    }
    expect(canvasEncodingVersions(editingV4RasterLayer: true), [MCOImageEncodingVersion.v3]);
  });
}
