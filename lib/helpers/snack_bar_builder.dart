import 'package:flutter/material.dart';

// showDismissibleSnackBar shows  a [SnackBar] with tap to dismiss
// all other properties are default and optional
void showDismissibleSnackBar(
  BuildContext context, {
  Key? key,
  required Widget content,
  Color? backgroundColor,
  double? elevation,
  EdgeInsetsGeometry? margin,
  EdgeInsetsGeometry? padding,
  double? width,
  ShapeBorder? shape,
  HitTestBehavior? hitTestBehavior,
  SnackBarBehavior? behavior,
  SnackBarAction? action,
  double? actionOverflowThreshold,
  bool? showCloseIcon,
  Color? closeIconColor,
  Duration? duration,
  bool? persist,
  Animation<double>? animation,
  void Function()? onVisible,
  DismissDirection? dismissDirection,
  Clip? clipBehavior,
}) {
  final messenger = ScaffoldMessenger.of(context);
  final contentPadding =
      padding ?? const EdgeInsets.symmetric(horizontal: 24, vertical: 14);
  messenger.showSnackBar(
    SnackBar(
      key: key,
      content: GestureDetector(
        // Keep padding inside the tap target so the colored snackbar surface
        // dismisses even when the click lands outside the text glyphs.
        behavior: HitTestBehavior.opaque,
        onTap: () =>
            messenger.hideCurrentSnackBar(reason: SnackBarClosedReason.dismiss),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 48),
          alignment: AlignmentDirectional.centerStart,
          padding: contentPadding,
          child: content,
        ),
      ),
      backgroundColor: backgroundColor,
      elevation: elevation,
      margin: margin,
      padding: EdgeInsets.zero,
      width: width,
      shape: shape,
      hitTestBehavior: hitTestBehavior,
      behavior: behavior,
      action: action,
      actionOverflowThreshold: actionOverflowThreshold,
      showCloseIcon: showCloseIcon,
      closeIconColor: closeIconColor,
      duration: duration ?? const Duration(seconds: 4),
      persist: persist,
      animation: animation,
      onVisible: onVisible,
      dismissDirection: dismissDirection ?? DismissDirection.down,
      clipBehavior: clipBehavior ?? Clip.hardEdge,
    ),
  );
}
