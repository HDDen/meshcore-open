import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../helpers/mcoa_theme_options.dart';
import '../helpers/mcoa_sender_name_brightness.dart';

class McoaThemeStyle extends ThemeExtension<McoaThemeStyle> {
  const McoaThemeStyle(this.options);
  final McoaThemeOptions options;

  static McoaThemeOptions of(BuildContext context) =>
      Theme.of(context).extension<McoaThemeStyle>()?.options ?? const McoaThemeOptions();

  static Color color(
    BuildContext context, String part, Color fallback, {bool? outgoing}
  ) {
    final direction = outgoing ?? McoaMessageScope.outgoingOf(context);
    return of(context).colors['${direction ? 'outgoing' : 'incoming'}_$part'] ?? fallback;
  }

  static Color senderNameColor(BuildContext context, Color fallback, {required bool colored}) {
    final options = of(context);
    final explicit = options.colors['incoming_sender_name'];
    if (explicit != null) {
      return explicit;
    }
    return colored
        ? adjustSenderNameBrightness(fallback, options.incomingSenderNameBrightness)
        : fallback;
  }

  static ThemeData apply(ThemeData base, McoaThemeOptions options) {
    final header = options.colors['header'];
    final ink = options.colors['header_text'];
    final status = options.colors['status_bar'];
    final backgroundBrightness = ThemeData.estimateBrightnessForColor(
      status ?? header ?? base.colorScheme.surface,
    );
    return base.copyWith(
      extensions: [...base.extensions.values, McoaThemeStyle(options)],
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: header,
        foregroundColor: ink,
        titleTextStyle: base.appBarTheme.titleTextStyle?.copyWith(color: ink),
        iconTheme: base.appBarTheme.iconTheme?.copyWith(color: ink),
        actionsIconTheme: base.appBarTheme.iconTheme?.copyWith(color: ink),
        systemOverlayStyle: status == null ? base.appBarTheme.systemOverlayStyle
            : SystemUiOverlayStyle(
                statusBarColor: status,
                statusBarBrightness: backgroundBrightness,
                statusBarIconBrightness: backgroundBrightness == Brightness.dark
                    ? Brightness.light : Brightness.dark,
              ),
      ),
    );
  }

  @override
  McoaThemeStyle copyWith({McoaThemeOptions? options}) =>
      McoaThemeStyle(options ?? this.options);

  @override
  McoaThemeStyle lerp(McoaThemeStyle? other, double t) {
    if (other == null) {
      return this;
    }
    return McoaThemeStyle((t < 0.5 ? options : other.options).copyWith(
      colors: {
        for (final key in McoaThemeOptions.colorKeys)
          if (options.colors[key] != null || other.options.colors[key] != null)
            key: Color.lerp(options.colors[key], other.options.colors[key], t)!,
      },
    ));
  }
}

/// Direction follows a bubble into its quote and inline mention widgets.
class McoaMessageScope extends InheritedWidget {
  const McoaMessageScope({super.key, required this.outgoing, required super.child});
  final bool outgoing;

  static bool outgoingOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<McoaMessageScope>()?.outgoing ?? false;

  @override
  bool updateShouldNotify(McoaMessageScope oldWidget) => outgoing != oldWidget.outgoing;
}
