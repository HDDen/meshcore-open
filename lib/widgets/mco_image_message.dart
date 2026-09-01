import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../helpers/channel_binary_data_helper.dart';
import '../helpers/mcoimg_codec.dart';
import '../helpers/mcoimg_palette.dart';
import '../helpers/mcoimg_v3_codec.dart';
import '../helpers/mcoimg_v4_codec.dart';
import '../helpers/mcoimg_v4_model.dart';
import '../l10n/l10n.dart';
import 'mco_image_v4_view.dart';

class MCOImageDecodeMetadata {
  final MCOImage? image;
  final int? unsupportedVersion;
  final int currentMaxSupportedVersion;
  final MCOImagePayloadInfo? payloadInfo;

  const MCOImageDecodeMetadata({
    required this.image,
    required this.unsupportedVersion,
    required this.currentMaxSupportedVersion,
    required this.payloadInfo,
  });

  bool get isImage => image != null;
  bool get isUnsupportedVersion => unsupportedVersion != null;
}

class MCOImageMessage extends StatelessWidget {
  final MCOImage image;
  final double maxSize;

  const MCOImageMessage({super.key, required this.image, this.maxSize = 200});

  static MCOImageDecodeMetadata decodeMetadata(String text) {
    const current = 4;
    final trimmed = text.trimLeft();
    if (trimmed.startsWith(ChannelBinaryDataHelper.unsupportedMcoImagePrefix)) {
      final version = int.tryParse(
        trimmed.substring(
          ChannelBinaryDataHelper.unsupportedMcoImagePrefix.length,
        ),
      );
      if (version != null) {
        return MCOImageDecodeMetadata(
          image: null,
          unsupportedVersion: version,
          currentMaxSupportedVersion: current,
          payloadInfo: null,
        );
      }
    }
    final textPayloadVersion = _versionedTextPayloadVersion(trimmed);
    if (textPayloadVersion != null && textPayloadVersion > current) {
      return MCOImageDecodeMetadata(
        image: null,
        unsupportedVersion: textPayloadVersion,
        currentMaxSupportedVersion: current,
        payloadInfo: null,
      );
    }
    if (MCOImageV4Codec.isTextPayload(text)) {
      try {
        final body = const MCOImageV4Codec().bodyFromText(text);
        final decoded = const MCOImageV4Codec().decodeBody(body);
        final document = decoded.document;
        final background = document.backgroundColor == null
            ? -1
            : document.palette[document.backgroundColor!];
        return MCOImageDecodeMetadata(
          image: MCOImageV4Preview(
            document: document,
            paletteProfile: document.paletteProfile,
            pixels: List<int>.filled(
              document.width * document.height,
              background,
            ),
            transparentColor: background < 0 ? background : null,
          ),
          unsupportedVersion: null,
          currentMaxSupportedVersion: current,
          payloadInfo: MCOImagePayloadInfo(
            version: 4,
            algorithm: 'vector',
            binaryLength: body.length,
          ),
        );
      } on MCOImageUnsupportedFormatException catch (error) {
        return MCOImageDecodeMetadata(
          image: null,
          unsupportedVersion: error.receivedVersion,
          currentMaxSupportedVersion: error.currentMaxSupportedVersion,
          payloadInfo: null,
        );
      } on MCOImageCodecException {
        return const MCOImageDecodeMetadata(
          image: null,
          unsupportedVersion: null,
          currentMaxSupportedVersion: current,
          payloadInfo: null,
        );
      }
    }
    if (MCOImageV3Codec.isTextPayload(text)) {
      final payloadInfo = MCOImageV3Codec.inspectText(text);
      try {
        return MCOImageDecodeMetadata(
          image: MCOImageV3Codec().decodeText(text),
          unsupportedVersion: null,
          currentMaxSupportedVersion: current,
          payloadInfo: payloadInfo,
        );
      } on MCOImageCodecException {
        return MCOImageDecodeMetadata(
          image: null,
          unsupportedVersion: null,
          currentMaxSupportedVersion: current,
          payloadInfo: payloadInfo,
        );
      }
    }
    final payloadInfo = MCOImageCodec.inspectPayload(text);
    if (!text.startsWith(MCOImageCodec.prefix)) {
      return MCOImageDecodeMetadata(
        image: null,
        unsupportedVersion: null,
        currentMaxSupportedVersion: current,
        payloadInfo: null,
      );
    }

    final received = MCOImageCodec.decodeHeaderVersion(text);
    if (received != null && received > current) {
      return MCOImageDecodeMetadata(
        image: null,
        unsupportedVersion: received,
        currentMaxSupportedVersion: current,
        payloadInfo: payloadInfo,
      );
    }

    try {
      return MCOImageDecodeMetadata(
        image: MCOImageCodec().decode(text),
        unsupportedVersion: null,
        currentMaxSupportedVersion: current,
        payloadInfo: payloadInfo,
      );
    } on MCOImageCodecException {
      return MCOImageDecodeMetadata(
        image: null,
        unsupportedVersion: null,
        currentMaxSupportedVersion: current,
        payloadInfo: payloadInfo,
      );
    }
  }

  static String? buildBadgeLabel({
    required MCOImageDecodeMetadata metadata,
    required String sourceText,
    required bool isBinary,
    required bool showResolution,
    required bool showFormat,
    required bool showAlgorithm,
    required bool showBytes,
    String? senderName,
    int? binaryPacketBytes,
  }) {
    if (metadata.image == null) return null;
    final parts = <String>['MCOimg${isBinary ? ' bin' : ''}'];
    final image = metadata.image!;
    if (showResolution) parts.add('${image.width}x${image.height}');
    final payloadInfo = metadata.payloadInfo;
    if (showFormat && payloadInfo != null) {
      parts.add('v${payloadInfo.version}');
    } else if (showFormat &&
        image.encodingVersion == MCOImageEncodingVersion.v3) {
      parts.add('v3');
    } else if (showFormat &&
        image.encodingVersion == MCOImageEncodingVersion.v4) {
      parts.add('v4');
    }
    if (showAlgorithm && payloadInfo != null) {
      parts.add(payloadInfo.algorithm);
    }
    if (showBytes) {
      final byteLength = isBinary
          ? payloadInfo != null && senderName != null
                ? payloadInfo.version == 3 || payloadInfo.version == 4
                      ? ChannelBinaryDataHelper.appBinaryEnvelopeLength(
                          bodyLength: payloadInfo.binaryLength,
                          senderName: senderName,
                        )
                      : ChannelBinaryDataHelper.binaryEnvelopeLength(
                          bodyLength: payloadInfo.binaryLength,
                          senderName: senderName,
                        )
                : binaryPacketBytes
          : utf8.encode(sourceText).length;
      if (byteLength != null) parts.add('${byteLength}bytes');
    }
    return parts.join(' ');
  }

  static MCOImage? tryDecode(String text) {
    return decodeMetadata(text).image;
  }

  static int? _versionedTextPayloadVersion(String text) {
    if (!text.startsWith('im')) return null;
    final colon = text.indexOf(':');
    if (colon <= 2) return null;
    final version = int.tryParse(text.substring(2, colon));
    return version;
  }

  static String unsupportedFormatText(
    BuildContext context, {
    required int receivedVersion,
    required int currentMaxSupportedVersion,
  }) {
    if (receivedVersion > currentMaxSupportedVersion) {
      return context.l10n.chat_canvasFormatNotSupported(
        receivedVersion,
        currentMaxSupportedVersion,
      );
    }
    if (Localizations.localeOf(context).languageCode == 'ru') {
      return 'MCOimg v$receivedVersion: этот режим изображения не '
          'поддерживается текущей версией приложения. Обновите приложение, '
          'чтобы открыть его.';
    }
    return 'MCOimg v$receivedVersion: this image mode is not supported by '
        'the current app. Update the app to view it.';
  }

  static Future<Uint8List> renderPngBytes(
    MCOImage image, {
    int cellSize = 16,
  }) async {
    if (image is MCOImageV4Preview) {
      return renderMCOImageV4Png(image.document, scale: cellSize);
    }
    final palette = MCOImagePalette.colorsFor(image.paletteProfile);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = ui.Paint()..isAntiAlias = false;

    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final pixel = image.pixels[y * image.width + x];
        if (image.transparentColor != null && pixel == image.transparentColor) {
          continue;
        }
        paint.color = _colorForPixelValue(image.paletteProfile, pixel, palette);
        canvas.drawRect(
          ui.Rect.fromLTWH(
            (x * cellSize).toDouble(),
            (y * cellSize).toDouble(),
            cellSize.toDouble(),
            cellSize.toDouble(),
          ),
          paint,
        );
      }
    }

    final picture = recorder.endRecording();
    final rendered = await picture.toImage(
      image.width * cellSize,
      image.height * cellSize,
    );
    final png = await rendered.toByteData(format: ui.ImageByteFormat.png);
    rendered.dispose();
    picture.dispose();
    if (png == null) {
      throw const MCOImageInvalidInputException('Cannot render PNG');
    }
    return png.buffer.asUint8List();
  }

  static Color _colorForPixelValue(
    PaletteProfile profile,
    int colorValue,
    List<Color> palette,
  ) {
    if (profile.isDynamic) {
      if (colorValue < 0 ||
          colorValue >= MCOImageDynamicPalette.global512.length ||
          MCOImageDynamicPalette.profileColorIdForGlobalIndex(
                profile,
                colorValue,
              ) ==
              null) {
        final whiteIndex = MCOImagePalette.whiteIndexFor(profile);
        return MCOImageDynamicPalette.global512[whiteIndex];
      }
      return MCOImageDynamicPalette.global512[colorValue];
    }

    final colorIndex = colorValue.clamp(0, palette.length - 1).toInt();
    return palette[colorIndex];
  }

  @override
  Widget build(BuildContext context) {
    if (image is MCOImageV4Preview) {
      return MCOImageV4View(
        document: (image as MCOImageV4Preview).document,
        maxSize: maxSize,
      );
    }
    final aspectRatio = image.width / image.height;
    final displayWidth = aspectRatio >= 1 ? maxSize : maxSize * aspectRatio;
    final displayHeight = aspectRatio >= 1 ? maxSize / aspectRatio : maxSize;
    final palette = MCOImagePalette.colorsFor(image.paletteProfile);

    return CustomPaint(
      size: Size(displayWidth, displayHeight),
      painter: _MCOImagePainter(image: image, palette: palette),
    );
  }
}

class _MCOImagePainter extends CustomPainter {
  final MCOImage image;
  final List<Color> palette;

  const _MCOImagePainter({required this.image, required this.palette});

  @override
  void paint(Canvas canvas, Size size) {
    final cellWidth = size.width / image.width;
    final cellHeight = size.height / image.height;
    final paint = Paint()..isAntiAlias = false;
    final transparentColor = image.transparentColor;

    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final pixel = image.pixels[y * image.width + x];
        if (transparentColor != null && pixel == transparentColor) {
          continue;
        }
        paint.color = MCOImageMessage._colorForPixelValue(
          image.paletteProfile,
          pixel,
          palette,
        );
        canvas.drawRect(
          Rect.fromLTWH(x * cellWidth, y * cellHeight, cellWidth, cellHeight),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MCOImagePainter oldDelegate) {
    return oldDelegate.image != image || oldDelegate.palette != palette;
  }
}
