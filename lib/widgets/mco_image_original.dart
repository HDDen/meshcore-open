import 'dart:io';

import 'package:flutter/material.dart';

import '../helpers/mcoimg_codec.dart';
import '../services/mco_image_pack_originals.dart';
import 'mco_image_message.dart';

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

  const MCOImageOriginalOrFallback({
    super.key,
    required this.text,
    required this.image,
    this.maxSize = 200,
  });

  @override
  State<MCOImageOriginalOrFallback> createState() =>
      _MCOImageOriginalOrFallbackState();
}

class _MCOImageOriginalOrFallbackState
    extends State<MCOImageOriginalOrFallback> {
  late Future<File?> _originalFuture;

  @override
  void initState() {
    super.initState();
    _originalFuture = McoImagePackOriginals.instance.resolveOriginalForText(
      widget.text,
    );
  }

  @override
  void didUpdateWidget(covariant MCOImageOriginalOrFallback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _originalFuture = McoImagePackOriginals.instance.resolveOriginalForText(
        widget.text,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File?>(
      future: _originalFuture,
      builder: (context, snapshot) {
        final file = snapshot.data;
        if (file == null) {
          return MCOImageMessage(image: widget.image, maxSize: widget.maxSize);
        }
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: widget.maxSize,
            maxHeight: widget.maxSize,
          ),
          child: Image.file(
            file,
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
