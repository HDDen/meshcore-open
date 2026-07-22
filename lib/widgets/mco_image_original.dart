import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../helpers/mcoimg_codec.dart';
import '../services/app_settings_service.dart';
import '../services/mco_image_pack_originals.dart';
import 'mco_image_message.dart';

/// Renders a received MCOimg message, preferring the original image
/// (Lottie/png/gif/jpg) from an installed *.mcoimg.pack when the
/// payload identity hash matches a pack item. Falls back to rendering the
/// received LoRa version when the image is unknown or the original file is
/// missing. While the original lookup is pending, the widget reserves the same
/// box that a found original would use. If no original exists, it falls back to
/// the normal full-size MCOimg render instead of keeping the replacement scale.
/// Keeping found originals stable is important for reverse chat lists: if an
/// async original image load changes an old message height below the viewport,
/// Flutter may repeatedly correct the scroll offset while the user scrolls
/// back to newer messages.
class MCOImageOriginalOrFallback extends StatefulWidget {
  final String text;
  final MCOImage image;
  final double maxSize;

  /// When true, always render the received LoRa version even if a pack
  /// original exists (per-message user override).
  final bool forceLora;
  final bool expandOriginalToMaxSize;
  final List<String> originalRelativePaths;

  const MCOImageOriginalOrFallback({
    super.key,
    required this.text,
    required this.image,
    this.maxSize = 200,
    this.forceLora = false,
    this.expandOriginalToMaxSize = false,
    this.originalRelativePaths = const [],
  });

  @override
  State<MCOImageOriginalOrFallback> createState() =>
      _MCOImageOriginalOrFallbackState();
}

class _MCOImageOriginalOrFallbackState
    extends State<MCOImageOriginalOrFallback> {
  late Future<ResolvedMcoImageOriginal?> _originalFuture;
  final Set<String> _rejectedOriginalPaths = {};

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
        oldWidget.forceLora != widget.forceLora ||
        oldWidget.originalRelativePaths != widget.originalRelativePaths) {
      _rejectedOriginalPaths.clear();
      _originalFuture = _resolve();
      _sharpenKey = null;
      _sharpenFuture = null;
    }
  }

  Future<ResolvedMcoImageOriginal?> _resolve() async {
    if (widget.forceLora) return null;
    if (widget.originalRelativePaths.isNotEmpty) {
      return McoImagePackOriginals.instance.resolveOriginalCandidates(
        widget.originalRelativePaths,
        excludedRelativePaths: _rejectedOriginalPaths,
      );
    }
    return McoImagePackOriginals.instance.resolveOriginalForText(
      widget.text,
      excludedRelativePaths: _rejectedOriginalPaths,
    );
  }

  void _rejectOriginal(ResolvedMcoImageOriginal original) {
    if (!_rejectedOriginalPaths.add(original.relativePath)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _originalFuture = _resolve();
        _sharpenKey = null;
        _sharpenFuture = null;
      });
    });
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
    final settings = context.watch<AppSettingsService>().settings;
    final imageScale = settings.mcoImageReplacementsScale
        .clamp(1.0, 5.0)
        .toDouble();
    final longestSide = widget.image.width > widget.image.height
        ? widget.image.width
        : widget.image.height;
    final displayScale = widget.forceLora || widget.expandOriginalToMaxSize
        ? widget.maxSize / longestSide
        : (imageScale > widget.maxSize / longestSide
              ? widget.maxSize / longestSide
              : imageScale);
    final displayWidth = widget.image.width * displayScale;
    final displayHeight = widget.image.height * displayScale;

    Widget fallbackLora() {
      return MCOImageMessage(image: widget.image, maxSize: widget.maxSize);
    }

    Widget replacementSizedFallback() {
      return SizedBox(
        width: displayWidth,
        height: displayHeight,
        child: MCOImageMessage(
          image: widget.image,
          maxSize: longestSide * displayScale,
        ),
      );
    }

    return FutureBuilder<ResolvedMcoImageOriginal?>(
      future: _originalFuture,
      builder: (context, snapshot) {
        final resolved = snapshot.data;
        if (resolved == null) {
          return snapshot.connectionState == ConnectionState.done
              ? fallbackLora()
              : replacementSizedFallback();
        }

        final resolvedDisplayScale = resolved.isLottie
            ? widget.maxSize / longestSide
            : displayScale;
        final resolvedDisplayWidth = widget.image.width * resolvedDisplayScale;
        final resolvedDisplayHeight =
            widget.image.height * resolvedDisplayScale;

        // Nearest-neighbor keeps hard pixel edges when the stable chat box
        // scales a small pack original up to the LoRa message size.
        final filterQuality = settings.mcoImageScaleNearestNeighbor
            ? FilterQuality.none
            : FilterQuality.medium;
        final sharpness = settings.mcoImageReplacementsSharpness.clamp(0, 10);

        Widget fallbackImage() => _ViewportAwareRaster(
          child: Image.file(
            resolved.file,
            fit: BoxFit.contain,
            filterQuality: filterQuality,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) {
              _rejectOriginal(resolved);
              return replacementSizedFallback();
            },
          ),
        );

        Widget imageWidget;
        if (resolved.isLottie) {
          final composition = resolved.lottieComposition;
          if (composition == null) {
            _rejectOriginal(resolved);
            imageWidget = replacementSizedFallback();
          } else {
            imageWidget = _ViewportAwareLottie(
              composition: composition,
            );
          }
        } else if (sharpness > 0) {
          final key = '${resolved.relativePath}|$sharpness';
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
          width: resolvedDisplayWidth,
          height: resolvedDisplayHeight,
          child: imageWidget,
        );
      },
    );
  }
}

class _ViewportAwareRaster extends StatefulWidget {
  final Widget child;

  const _ViewportAwareRaster({required this.child});

  @override
  State<_ViewportAwareRaster> createState() => _ViewportAwareRasterState();
}

class _ViewportAwareRasterState extends State<_ViewportAwareRaster> {
  final Key _visibilityKey = UniqueKey();
  bool _visible = true;

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: _visibilityKey,
      onVisibilityChanged: (info) {
        final visible = info.visibleFraction > 0;
        if (visible == _visible || !mounted) return;
        setState(() => _visible = visible);
      },
      child: TickerMode(
        enabled: _visible,
        child: widget.child,
      ),
    );
  }
}

class _ViewportAwareLottie extends StatefulWidget {
  final LottieComposition composition;

  const _ViewportAwareLottie({required this.composition});

  @override
  State<_ViewportAwareLottie> createState() => _ViewportAwareLottieState();
}

class _ViewportAwareLottieState extends State<_ViewportAwareLottie>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller;
  final Key _visibilityKey = UniqueKey();
  bool _visible = true;
  bool _tickerEnabled = true;
  bool _appResumed = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appResumed = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _controller = AnimationController(
      vsync: this,
      duration: widget.composition.duration,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _syncPlayback();
  }

  @override
  void didUpdateWidget(covariant _ViewportAwareLottie oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.composition != widget.composition) {
      _controller.duration = widget.composition.duration;
    }
    _syncPlayback();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appResumed = state == AppLifecycleState.resumed;
    _syncPlayback();
  }

  void _syncPlayback() {
    if (!mounted) return;
    if ((_controller.duration ?? Duration.zero) <= Duration.zero) {
      if (_controller.isAnimating) _controller.stop(canceled: false);
      return;
    }
    final shouldPlay = _visible && _tickerEnabled && _appResumed;
    if (shouldPlay) {
      if (!_controller.isAnimating) _controller.repeat();
    } else if (_controller.isAnimating) {
      _controller.stop(canceled: false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: _visibilityKey,
      onVisibilityChanged: (info) {
        final visible = info.visibleFraction > 0;
        if (visible == _visible) return;
        _visible = visible;
        _syncPlayback();
      },
      child: Lottie(
        composition: widget.composition,
        controller: _controller,
        fit: BoxFit.contain,
        frameRate: FrameRate.composition,
        addRepaintBoundary: true,
      ),
    );
  }
}
