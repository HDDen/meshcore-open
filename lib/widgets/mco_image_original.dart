import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../helpers/mcoimg_codec.dart';
import '../services/app_settings_service.dart';
import '../services/mco_image_pack_originals.dart';
import 'mco_image_message.dart';

class _ResolvedOriginal {
  final File file;
  final int width;
  final int height;

  const _ResolvedOriginal(this.file, this.width, this.height);
}

/// Renders a received MCOimg message, preferring the original image
/// (png/jpg/gif, possibly animated) from an installed *.mcoimg.pack when the
/// payload identity hash matches a pack item. Falls back to rendering the
/// received LoRa version when the image is unknown or the original file is
/// missing. The original is shown inside the same box as the LoRa render, so
/// only the picture changes — not the bubble layout.
class MCOImageOriginalOrFallback extends StatefulWidget {
  final String text;
  final MCOImage image;
  final double maxSize;

  /// When true, always render the received LoRa version even if a pack
  /// original exists (per-message user override).
  final bool forceLora;

  const MCOImageOriginalOrFallback({
    super.key,
    required this.text,
    required this.image,
    this.maxSize = 200,
    this.forceLora = false,
  });

  @override
  State<MCOImageOriginalOrFallback> createState() =>
      _MCOImageOriginalOrFallbackState();
}

class _MCOImageOriginalOrFallbackState
    extends State<MCOImageOriginalOrFallback> {
  late Future<_ResolvedOriginal?> _originalFuture;

  // Memoized sharpened still, keyed by "<text>|<sharpness>". Sharpening runs a
  // CPU unsharp mask over the decoded pixels, so it uses a single (first)
  // frame — animated GIFs won't animate while sharpness > 0.
  Future<ui.Image?>? _sharpenFuture;
  String? _sharpenKey;

  @override
  void initState() {
    super.initState();
    _originalFuture = _resolve();
  }

  @override
  void didUpdateWidget(covariant MCOImageOriginalOrFallback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.forceLora != widget.forceLora) {
      _originalFuture = _resolve();
      _sharpenKey = null;
      _sharpenFuture = null;
    }
  }

  Future<_ResolvedOriginal?> _resolve() async {
    if (widget.forceLora) return null;
    final file = await McoImagePackOriginals.instance.resolveOriginalForText(
      widget.text,
    );
    if (file == null) return null;
    try {
      final bytes = await file.readAsBytes();
      final descriptor = await ui.ImageDescriptor.encoded(
        await ui.ImmutableBuffer.fromUint8List(bytes),
      );
      final width = descriptor.width;
      final height = descriptor.height;
      descriptor.dispose();
      if (width <= 0 || height <= 0) return null;
      return _ResolvedOriginal(file, width, height);
    } catch (_) {
      return null;
    }
  }

  /// Builds a sharpened still image using an unsharp-mask 3x3 convolution.
  /// [sharpness] is 0–10; higher values enhance edges more strongly.
  Future<ui.Image?> _buildSharpened(File file, int sharpness) async {
    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final w = image.width;
      final h = image.height;
      final byteData = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      image.dispose();
      if (byteData == null || w <= 0 || h <= 0) return null;

      final src = byteData.buffer.asUint8List();
      final out = _applyUnsharpMask(src, w, h, sharpness);

      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        out,
        w,
        h,
        ui.PixelFormat.rgba8888,
        completer.complete,
      );
      return completer.future;
    } catch (_) {
      return null;
    }
  }

  Uint8List _applyUnsharpMask(Uint8List src, int w, int h, int sharpness) {
    final out = Uint8List.fromList(src);
    // Map 1..10 to a per-neighbor kernel weight (0.1..1.0). Center weight is
    // 1 + 4k so the kernel keeps overall brightness roughly constant.
    final k = sharpness * 0.1;
    final center = 1.0 + 4.0 * k;
    for (int y = 0; y < h; y++) {
      final yUp = y > 0 ? y - 1 : y;
      final yDown = y < h - 1 ? y + 1 : y;
      for (int x = 0; x < w; x++) {
        final xLeft = x > 0 ? x - 1 : x;
        final xRight = x < w - 1 ? x + 1 : x;
        final i = (y * w + x) * 4;
        final up = (yUp * w + x) * 4;
        final down = (yDown * w + x) * 4;
        final left = (y * w + xLeft) * 4;
        final right = (y * w + xRight) * 4;
        for (int c = 0; c < 3; c++) {
          final value =
              center * src[i + c] -
              k *
                  (src[up + c] +
                      src[down + c] +
                      src[left + c] +
                      src[right + c]);
          out[i + c] = value < 0
              ? 0
              : value > 255
              ? 255
              : value.round();
        }
        // Alpha untouched.
        out[i + 3] = src[i + 3];
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ResolvedOriginal?>(
      future: _originalFuture,
      builder: (context, snapshot) {
        final resolved = snapshot.data;
        if (resolved == null) {
          return MCOImageMessage(image: widget.image, maxSize: widget.maxSize);
        }

        final settings = context.watch<AppSettingsService>().settings;
        // Upscale factor for originals (user setting, 1x–5x), capped so the
        // longest side never exceeds maxSize.
        final upscaleFactor = settings.mcoImageReplacementsScale;
        // Nearest-neighbor keeps hard pixel edges when upscaling.
        final filterQuality = settings.mcoImageScaleNearestNeighbor
            ? FilterQuality.none
            : FilterQuality.medium;
        final sharpness = settings.mcoImageReplacementsSharpness.clamp(0, 10);
        final longestSide = resolved.width > resolved.height
            ? resolved.width
            : resolved.height;
        final scale = upscaleFactor.clamp(0.0, widget.maxSize / longestSide);
        final displayWidth = resolved.width * scale;
        final displayHeight = resolved.height * scale;

        Widget fallbackImage() => Image.file(
          resolved.file,
          fit: BoxFit.contain,
          filterQuality: filterQuality,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) =>
              MCOImageMessage(image: widget.image, maxSize: widget.maxSize),
        );

        Widget imageWidget;
        if (sharpness > 0) {
          final key = '${widget.text}|$sharpness';
          if (_sharpenKey != key) {
            _sharpenKey = key;
            _sharpenFuture = _buildSharpened(resolved.file, sharpness);
          }
          imageWidget = FutureBuilder<ui.Image?>(
            future: _sharpenFuture,
            builder: (context, sharpSnap) {
              final sharpened = sharpSnap.data;
              if (sharpened == null) return fallbackImage();
              return RawImage(
                image: sharpened,
                fit: BoxFit.contain,
                filterQuality: filterQuality,
              );
            },
          );
        } else {
          _sharpenKey = null;
          _sharpenFuture = null;
          imageWidget = fallbackImage();
        }

        return SizedBox(
          width: displayWidth,
          height: displayHeight,
          child: imageWidget,
        );
      },
    );
  }
}
