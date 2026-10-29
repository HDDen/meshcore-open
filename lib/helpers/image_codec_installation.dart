import '../models/image_codec_support.dart';

/// Installation metadata comes from the downloader or the disk reconciliation.
/// A small ONNX graph alone is not the preset: external weights and both
/// entropy graphs must be present too. No disk I/O or inference runs here.
bool isImageCodecPresetComplete(
  ImageCodecModelSpec spec,
  ImageCodecModelRecord model,
) {
  return spec.isComplete &&
      model.id == spec.id &&
      model.localPath.isNotEmpty &&
      model.bundleVersion >= kImageCodecBundleVersion &&
      spec.assets.every((asset) => model.assetFileNames.contains(asset.fileName));
}

/// Preserve old/custom single-file models, but never treat a registered
/// decoder as usable when its declared graph or external weights are absent.
bool hasImageCodecDecoderAssets(
  ImageCodecModelSpec spec,
  ImageCodecModelRecord model,
) {
  return spec.assets
      .where(
        (asset) =>
            asset.role == ImageCodecAssetRole.decoderGraph ||
            asset.role == ImageCodecAssetRole.decoderWeights,
      )
      .every((asset) => model.assetFileNames.contains(asset.fileName));
}
