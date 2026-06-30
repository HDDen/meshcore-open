import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:share_plus/share_plus.dart';

import 'mcoimg_codec.dart';
import 'mcoimg_v3_codec.dart';
import 'mcoimg_palette.dart';

class MCOImageFileSaver {
  static Future<bool> savePng(MCOImage image) async {
    final bytes = await _renderOriginalPngBytes(image);
    return savePngBytes(bytes);
  }

  static Future<bool> savePngBytes(Uint8List bytes) async {
    final fileName = _fileName();
    try {
      final location = await file_selector.getSaveLocation(
        suggestedName: fileName,
        acceptedTypeGroups: const [
          file_selector.XTypeGroup(
            label: 'PNG image',
            extensions: ['png'],
            mimeTypes: ['image/png'],
            uniformTypeIdentifiers: ['public.png'],
          ),
        ],
      );
      if (location == null) return false;
      await XFile.fromData(
        bytes,
        mimeType: 'image/png',
        name: fileName,
      ).saveTo(location.path);
      return true;
    } catch (_) {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(bytes, mimeType: 'image/png', name: fileName)],
        ),
      );
      return true;
    }
  }

  static Future<bool> saveBinaryPayloadFromText(String text) async {
    final trimmed = text.trimLeft();
    final payload = MCOImageV3Codec.isTextPayload(trimmed)
        ? MCOImageV3Codec.appPayloadWithoutSenderFromText(trimmed)
        : MCOImageCodec.binaryPayloadFromText(trimmed);
    return saveBinaryPayload(payload);
  }

  static Future<bool> saveV3AppPayload(EncodedMCOImageV3 image) async {
    return saveBinaryPayload(image.toAppPayloadWithoutSender());
  }

  static Future<bool> saveBinaryPayload(Uint8List payload) async {
    final fileName = _binaryFileName();
    try {
      final location = await file_selector.getSaveLocation(
        suggestedName: fileName,
        acceptedTypeGroups: const [
          file_selector.XTypeGroup(
            label: 'MCO image binary',
            extensions: ['bin'],
            mimeTypes: ['application/octet-stream'],
            uniformTypeIdentifiers: ['public.data'],
          ),
        ],
      );
      if (location == null) return false;
      await XFile.fromData(
        payload,
        mimeType: 'application/octet-stream',
        name: fileName,
      ).saveTo(location.path);
      return true;
    } catch (_) {
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              payload,
              mimeType: 'application/octet-stream',
              name: fileName,
            ),
          ],
        ),
      );
      return true;
    }
  }

  static Future<Uint8List> _renderOriginalPngBytes(MCOImage image) async {
    final rgba = Uint8List(image.width * image.height * 4);
    final palette = image.paletteProfile.isDynamic
        ? MCOImageDynamicPalette.global512
        : MCOImagePalette.colorsFor(image.paletteProfile);

    for (var i = 0; i < image.pixels.length; i++) {
      final colorIndex = image.paletteProfile.isDynamic
          ? image.pixels[i].clamp(
              0,
              MCOImageDynamicPalette.global512.length - 1,
            )
          : image.pixels[i].clamp(0, palette.length - 1);
      final color = palette[colorIndex.toInt()];
      final offset = i * 4;
      rgba[offset] = _colorChannelToByte(color.r);
      rgba[offset + 1] = _colorChannelToByte(color.g);
      rgba[offset + 2] = _colorChannelToByte(color.b);
      rgba[offset + 3] =
          image.transparentColor != null &&
              image.pixels[i] == image.transparentColor
          ? 0
          : _colorChannelToByte(color.a);
    }

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      image.width,
      image.height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );

    final renderedImage = await completer.future;
    try {
      final byteData = await renderedImage.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (byteData == null) {
        throw StateError('Failed to encode MCO image as PNG');
      }
      return byteData.buffer.asUint8List();
    } finally {
      renderedImage.dispose();
    }
  }

  static int _colorChannelToByte(double value) {
    return (value * 255.0).round().clamp(0, 255).toInt();
  }

  static String _fileName() {
    final timestamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    return 'meshcore_canvas_$timestamp.png';
  }

  static String _binaryFileName() {
    final timestamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    return 'meshcore_canvas_$timestamp.mcoimg.bin';
  }
}
