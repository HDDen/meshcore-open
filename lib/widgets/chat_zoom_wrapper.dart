import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/chat_text_scale_service.dart';

/// Scale recognizer that only wants genuine two-finger pinches.
///
/// A plain ScaleGestureRecognizer also claims one-finger drags (it treats them
/// as a pan), which would swallow the app-level back-swipe over chat lists even
/// though the handlers here ignore anything but two pointers. Bowing out of the
/// arena as soon as a single-pointer drag starts leaves that gesture to whoever
/// else wants it.
class _PinchOnlyScaleGestureRecognizer extends ScaleGestureRecognizer {
  _PinchOnlyScaleGestureRecognizer({super.debugOwner});

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent && pointerCount < 2) {
      resolve(GestureDisposition.rejected);
      return;
    }
    super.handleEvent(event);
  }
}

/// Gesture wrapper that exposes two-finger pinch-to-zoom for chat scrollables.
/// Double-tap resets the scale. Only the wrapper itself listens to gestures;
/// child scrollables keep their normal touch handling.
class ChatZoomWrapper extends StatefulWidget {
  const ChatZoomWrapper({super.key, required this.child, this.onDoubleTap});

  final Widget child;
  final VoidCallback? onDoubleTap;

  @override
  State<ChatZoomWrapper> createState() => _ChatZoomWrapperState();
}

class _ChatZoomWrapperState extends State<ChatZoomWrapper> {
  double? _startScale;

  @override
  Widget build(BuildContext context) {
    final service = context.read<ChatTextScaleService>();

    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: <Type, GestureRecognizerFactory>{
        DoubleTapGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<DoubleTapGestureRecognizer>(
              () => DoubleTapGestureRecognizer(debugOwner: this),
              (recognizer) {
                recognizer.onDoubleTap = () {
                  service.reset();
                  service.persist();
                  widget.onDoubleTap?.call();
                };
              },
            ),
        _PinchOnlyScaleGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<
              _PinchOnlyScaleGestureRecognizer
            >(
              () => _PinchOnlyScaleGestureRecognizer(debugOwner: this),
              (recognizer) {
                recognizer
                  ..onStart = (details) {
                    if (details.pointerCount != 2) return;
                    _startScale = service.scale;
                  }
                  ..onUpdate = (details) {
                    if (details.pointerCount != 2) return;
                    final baseScale = _startScale ?? service.scale;
                    service.setScale(baseScale * details.scale);
                  }
                  ..onEnd = (_) {
                    _startScale = null;
                    service.persist();
                  };
              },
            ),
      },
      child: widget.child,
    );
  }
}
