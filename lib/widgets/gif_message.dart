import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../helpers/gif_playback.dart';
import '../services/app_settings_service.dart';
import '../services/gif_image_provider.dart';
import '../l10n/l10n.dart';

class GifMessage extends StatefulWidget {
  final String url;
  final Color backgroundColor;
  final Color fallbackTextColor;
  final double maxSize;

  const GifMessage({
    super.key,
    required this.url,
    required this.backgroundColor,
    required this.fallbackTextColor,
    this.maxSize = 200,
  });

  @override
  State<GifMessage> createState() => _GifMessageState();
}

class _GifMessageState extends State<GifMessage> {
  final _subscription = GifImageSubscription();
  late final GifPlaybackVisibility _visibility;
  int _streamRevision = 0;
  ui.Image? _image;
  Object? _error;
  bool _isLoading = true;
  bool _isPaused = false;

  @override
  void initState() {
    super.initState();
    _visibility = GifPlaybackVisibility(onChanged: _onVisibilityChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = context.watch<AppSettingsService?>();
    _visibility.updateContext(context,
        enabled: settings?.settings.powerSaving.effective.pauseHiddenGifs ?? false);
    _syncSubscription();
  }

  void _onVisibilityChanged() {
    if (!mounted) return;
    _syncSubscription();
    setState(() {});
  }

  void _syncSubscription() {
    if (!mounted) return;
    final playing = !_isPaused && _visibility.allowed;
    if (playing && !_subscription.hasStream) {
      _resolveImage();
    } else {
      _subscription.setPlaying(playing);
    }
  }

  @override
  void didUpdateWidget(covariant GifMessage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _unsubscribe();
      _image = null;
      _error = null;
      _isLoading = true;
      _isPaused = false;
      _syncSubscription();
    }
  }

  @override
  void dispose() {
    _visibility.dispose();
    _unsubscribe();
    super.dispose();
  }

  void _resolveImage() {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final provider = gifImageProvider(widget.url);
    final stream = provider.resolve(ImageConfiguration.empty);
    final revision = ++_streamRevision;
    final listener = ImageStreamListener(
      (imageInfo, _) {
        if (!mounted || revision != _streamRevision ||
            _isPaused || !_visibility.allowed) {
          imageInfo.dispose();
          return;
        }
        setState(() {
          _image = imageInfo.image;
          _isLoading = false;
        });
      },
      onError: (error, _) {
        if (!mounted || revision != _streamRevision) {
          return;
        }
        setState(() {
          _error = error;
          _isLoading = false;
        });
      },
    );
    _subscription.bind(stream, listener);
    _subscription.setPlaying(!_isPaused && _visibility.allowed);
  }

  void _retryLoad() {
    _unsubscribe();
    _image = null;
    _isPaused = false;
    // A failed load stays in the image cache as a completer that only repeats
    // its error, so it has to go before the retry.
    PaintingBinding.instance.imageCache.evict(gifImageProvider(widget.url));
    _syncSubscription();
  }

  void _unsubscribe() {
    _streamRevision++;
    _subscription.clear();
  }

  void _togglePause() {
    if (_error != null) {
      _retryLoad();
      return;
    }
    if (_image == null) {
      if (!_isLoading) {
        _retryLoad();
      }
      return;
    }
    setState(() {
      _isPaused = !_isPaused;
    });
    _syncSubscription();
  }

  @override
  Widget build(BuildContext context) {
    // Calculate display size based on image aspect ratio
    // Use 4:3 placeholder aspect ratio during loading to minimize layout shifts
    double displayWidth = widget.maxSize;
    double displayHeight = widget.maxSize * 0.75;

    if (_image != null) {
      final imageWidth = _image!.width.toDouble();
      final imageHeight = _image!.height.toDouble();
      final aspectRatio = imageWidth / imageHeight;

      // Fit within maxSize, calculating dimensions from aspect ratio
      if (aspectRatio >= 1) {
        // Wider than tall: constrain by width
        displayWidth = widget.maxSize;
        displayHeight = displayWidth / aspectRatio;
      } else {
        // Taller than wide: constrain by height
        displayHeight = widget.maxSize;
        displayWidth = displayHeight * aspectRatio;
      }
    }

    Widget content;

    if (_error != null) {
      content = Center(
        child: Text(
          context.l10n.gif_loadFailedRetry,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: widget.fallbackTextColor),
        ),
      );
    } else if (_isLoading && _image == null) {
      content = const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    } else if (_image == null) {
      content = Center(
        child: Text(
          context.l10n.gif_tapToLoad,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: widget.fallbackTextColor),
        ),
      );
    } else {
      content = RawImage(
        image: _image,
        fit: BoxFit.contain,
        width: displayWidth,
        height: displayHeight,
      );
    }

    return _visibility.wrap(
      GestureDetector(
        onTap: _togglePause,
        child: Container(
          color: widget.backgroundColor,
          width: displayWidth,
          height: displayHeight,
          child: Stack(
            fit: StackFit.expand,
            children: [
              content,
              if (_isPaused && _image != null)
                Container(
                  color: Colors.black.withValues(alpha: 0.2),
                  child: const Center(
                    child: Icon(Icons.pause, color: Colors.white70, size: 28),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
