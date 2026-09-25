import 'package:flutter/widgets.dart';

/// The box of a chat bubble: its width limit and padding apply at once, and
/// only its decoration, the highlight and status colours, fades.
///
/// It takes the parameters the bubbles used to hand to [AnimatedContainer],
/// which animates every property that changes. A bubble's maximum width is a
/// share of the window, so each step of a window resize restarted a
/// one-second width animation in every visible bubble, and their text was
/// laid out again on every frame of it.
///
/// The layout is the one [AnimatedContainer] builds: the constraints outside
/// the decoration, the padding inside it.
class ChatBubbleBox extends StatelessWidget {
  const ChatBubbleBox({
    super.key,
    required this.duration,
    this.curve = Curves.linear,
    this.padding,
    this.constraints,
    this.decoration,
    required this.child,
  });

  final Duration duration;
  final Curve curve;
  final EdgeInsetsGeometry? padding;
  final BoxConstraints? constraints;
  final Decoration? decoration;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final padding = this.padding;
    final constraints = this.constraints;
    final Widget box = AnimatedContainer(
      duration: duration,
      curve: curve,
      decoration: decoration,
      child: padding == null ? child : Padding(padding: padding, child: child),
    );
    if (constraints == null) return box;
    return ConstrainedBox(constraints: constraints, child: box);
  }
}
