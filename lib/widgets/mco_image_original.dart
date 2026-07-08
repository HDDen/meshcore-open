import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../helpers/mcoimg_codec.dart';
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

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ResolvedOriginal?>(
      future: _originalFuture,
      builder: (context, snapshot) {
        final resolved = snapshot.data;
        if (resolved == null) {
          return MCOImageMessage(image: widget.image, maxSize: widget.maxSize);
        }

        // Scale factor for originals, capped so the longest side never
        // exceeds maxSize. Multiplier is 1x for now (mechanic kept for easy
        // tuning).
        const upscaleFactor = 1.0;
        final longestSide = resolved.width > resolved.height
            ? resolved.width
            : resolved.height;
        final scale = upscaleFactor.clamp(0.0, widget.maxSize / longestSide);
        final displayWidth = resolved.width * scale;
        final displayHeight = resolved.height * scale;

        return SizedBox(
          width: displayWidth,
          height: displayHeight,
          child: Image.file(
            resolved.file,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) => MCOImageMessage(
              image: widget.image,
              maxSize: widget.maxSize,
            ),
          ),
        );
      },
    );
  }
}
