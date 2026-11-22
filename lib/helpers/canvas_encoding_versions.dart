import 'mcoimg_types.dart';

/// Legacy formats remain readable, but the editor creates only v3/v4.
MCOImageEncodingVersion canvasEncodingVersionForImport(
  MCOImageEncodingVersion source,
) => switch (source) {
  MCOImageEncodingVersion.v1Legacy || MCOImageEncodingVersion.v2 =>
    MCOImageEncodingVersion.v3,
  _ => source,
};

List<MCOImageEncodingVersion> canvasEncodingVersions({
  bool editingV4RasterLayer = false,
}) => editingV4RasterLayer
    ? const [MCOImageEncodingVersion.v3]
    : const [MCOImageEncodingVersion.v3, MCOImageEncodingVersion.v4];
