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
      await _shareBytes(bytes, fileName, mimeType: 'image/png');
      return true;
    }
  }

  static Future<bool> saveOriginalBytes(
    Uint8List bytes,
    String originalFileName,
  ) async {
    final lower = originalFileName.toLowerCase();
    final (suffix, extension, mimeType, uti, label) =
        lower.endsWith('.lottie.json')
        ? (
            '.mcoimg.lottie.json',
            'json',
            'application/json',
            'public.json',
            'Lottie JSON animation',
          )
        : lower.endsWith('.lottie')
        ? (
            '.mcoimg.lottie',
            'lottie',
            'application/zip',
            'public.zip-archive',
            'dotLottie animation',
          )
        : lower.endsWith('.gif')
        ? ('.mcoimg.gif', 'gif', 'image/gif', 'com.compuserve.gif', 'GIF image')
        : lower.endsWith('.jpg') || lower.endsWith('.jpeg')
        ? ('.mcoimg.jpg', 'jpg', 'image/jpeg', 'public.jpeg', 'JPEG image')
        : ('.mcoimg.png', 'png', 'image/png', 'public.png', 'PNG image');
    final fileName = '${_timestampFileStem()}$suffix';
    try {
      final location = await file_selector.getSaveLocation(
        suggestedName: fileName,
        acceptedTypeGroups: [
          file_selector.XTypeGroup(
            label: label,
            extensions: [extension],
            mimeTypes: [mimeType],
            uniformTypeIdentifiers: [uti],
          ),
        ],
      );
      if (location == null) return false;
      await XFile.fromData(
        bytes,
        mimeType: mimeType,
        name: fileName,
      ).saveTo(location.path);
      return true;
    } catch (_) {
      await _shareBytes(bytes, fileName, mimeType: mimeType);
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
      await _shareBytes(
        payload,
        fileName,
        mimeType: 'application/octet-stream',
      );
      return true;
    }
  }

  static Future<void> _shareBytes(
    Uint8List bytes,
    String fileName, {
    required String mimeType,
  }) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, mimeType: mimeType, name: fileName)],
        fileNameOverrides: [fileName],
      ),
    );
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
    return pngFileName();
  }

  static String _binaryFileName() {
    return binaryFileName();
  }

  static String pngFileName() {
    return '${_timestampFileStem()}.mcoimg.png';
  }

  static String binaryFileName() {
    return '${_timestampFileStem()}.mcoimg.bin';
  }

  static String _timestampFileStem() {
    final now = DateTime.now();
    final year = now.year.toString().padLeft(4, '0');
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    final second = now.second.toString().padLeft(2, '0');
    return '$year-$month-$day'
        '_$hour-$minute-$second';
  }
}
