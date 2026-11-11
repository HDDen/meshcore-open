import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/image_codec_installation.dart';
import 'package:meshcore_open/models/image_codec_support.dart';

void main() {
  final preset = imageCodecPresetModels.single;

  ImageCodecModelRecord record({
    List<String>? files,
    int version = kImageCodecBundleVersion,
    String? path,
    Map<String, ImageCodecAssetRole> roles = const {},
  }) => ImageCodecModelRecord(
    id: preset.id,
    name: preset.fileName,
    sourceUrl: preset.graph.sourceUrl,
    localPath: path ?? '/models/${preset.fileName}',
    downloadedAt: DateTime.utc(2026),
    fileSizeBytes: preset.totalSizeBytes,
    assetFileNames: files ?? preset.assets.map((asset) => asset.fileName).toList(),
    assetRoles: roles,
    bundleVersion: version,
  );

  test('only a full current preset is ready in the download controls', () {
    expect(isImageCodecPresetComplete(preset, record()), isTrue);
    expect(isImageCodecPresetComplete(preset, record(version: 0)), isFalse);
    expect(isImageCodecPresetComplete(preset, record(path: '')), isFalse);
    expect(
      isImageCodecPresetComplete(
        preset,
        record(version: kImageCodecBundleVersion + 1),
      ),
      isTrue,
    );
  });

  test('a recorded role must agree with the catalog', () {
    final decoder = preset.graph;
    expect(isImageCodecPresetComplete(preset, record(roles: {
      decoder.fileName: ImageCodecAssetRole.entropyGraph,
    })), isFalse);
    expect(isImageCodecPresetComplete(preset, record(roles: {
      for (final asset in preset.assets) asset.fileName: asset.role,
    })), isTrue);
  });

  for (final missing in preset.assets) {
    test('missing ${missing.role.name} cannot be labelled ready', () {
      final partial = record(
        files: [
          for (final asset in preset.assets)
            if (asset != missing) asset.fileName,
        ],
      );
      expect(isImageCodecPresetComplete(preset, partial), isFalse);
      expect(
        hasImageCodecDecoderAssets(preset, partial),
        missing.role != ImageCodecAssetRole.decoderGraph &&
            missing.role != ImageCodecAssetRole.decoderWeights,
      );
    });
  }
}
