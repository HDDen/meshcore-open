import 'package:flutter/material.dart';

import '../theme/mcoa_theme_style.dart';
import 'chat_bubble_box.dart';
import 'mcoa_bubble_surface.dart';
import 'message_bookmark.dart';

/// The upstream box remains the default. Separation changes painting only.
class McoaChatBubbleBox extends StatelessWidget {
  const McoaChatBubbleBox({
    super.key,
    required this.outgoing,
    this.metadataVisible = true,
    this.bookmarked = false,
    required this.duration,
    this.curve = Curves.linear,
    this.padding,
    this.constraints,
    required this.decoration,
    required this.child,
  });

  final bool outgoing;
  final bool metadataVisible;
  final bool bookmarked;
  final Duration duration;
  final Curve curve;
  final EdgeInsetsGeometry? padding;
  final BoxConstraints? constraints;
  final BoxDecoration decoration;
  final Widget child;

  @override
  Widget build(BuildContext context) => MessageBookmarkBadge(
    marked: bookmarked,
    cornerRadius: decoration.borderRadius?.resolve(Directionality.of(context)).topLeft.y ?? 0,
    child: _buildSurface(context),
  );

  Widget _buildSurface(BuildContext context) {
    if (!metadataVisible || !McoaThemeStyle.of(context).separateMetadataFor(outgoing)) {
      return ChatBubbleBox(
        duration: duration, curve: curve, padding: padding,
        constraints: constraints, decoration: decoration, child: child,
      );
    }
    final inset = decoration.padding.add(padding ?? EdgeInsets.zero);
    final box = TweenAnimationBuilder<Decoration>(
      duration: duration,
      curve: curve,
      tween: DecorationTween(begin: decoration, end: decoration),
      child: Padding(padding: inset, child: child),
      builder: (context, value, child) => McoaBubbleSurface(
        decoration: value as BoxDecoration,
        metadataColor: McoaThemeStyle.color(
          context, 'metadata_background', Theme.of(context).colorScheme.surface,
          outgoing: outgoing,
        ),
        textDirection: Directionality.of(context),
        child: child!,
      ),
    );
    return constraints == null ? box : ConstrainedBox(constraints: constraints!, child: box);
  }
}
