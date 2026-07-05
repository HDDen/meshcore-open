import 'package:flutter/material.dart';

class PopupMenuRow extends StatelessWidget {
  final IconData? icon;
  final Widget? leading;
  final String text;
  final Color? iconColor;
  final TextStyle? textStyle;

  const PopupMenuRow({
    super.key,
    this.icon,
    this.leading,
    required this.text,
    this.iconColor,
    this.textStyle,
  }) : assert(icon != null || leading != null);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        leading ?? Icon(icon, color: iconColor),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            text,
            softWrap: true,
            overflow: TextOverflow.visible,
            style: textStyle,
          ),
        ),
      ],
    );
  }
}
