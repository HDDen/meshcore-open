import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/repeater_extra_settings.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/widgets/repeater_extra_setting_control.dart';

void main() {
  for (final locale in ['en', 'ru']) {
    for (final size in [const Size(320, 568), const Size(568, 360)]) {
      testWidgets('U13c: complete setting descriptions wrap '
          '($locale, $size, scale=2)', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final controllers = {
          for (final setting in RepeaterExtraSetting.values)
            if (!setting.isToggle) setting: TextEditingController(),
        };
        try {
          await tester.pumpWidget(MaterialApp(
            locale: Locale(locale),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(2),
              ),
              child: child!,
            ),
            home: Scaffold(body: Builder(builder: (context) {
              final l10n = AppLocalizations.of(context);
              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  for (final setting in RepeaterExtraSetting.values)
                    RepeaterExtraSettingControl(
                      setting: setting,
                      l10n: l10n,
                      controller: controllers[setting],
                      loaded: true,
                      refreshing: false,
                      canRefresh: true,
                      inherited:
                          setting == RepeaterExtraSetting.floodMaxUnscoped,
                      onRefresh: () {},
                      onChanged: (_) {},
                      onToggle: (_) {},
                    ),
                ]),
              );
            })),
          ));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          for (final element in find.byType(Text).evaluate()) {
            final widget = element.widget as Text;
            if (widget.data?.isEmpty ?? true) continue;
            expect(widget.maxLines, isNull, reason: widget.data);
            expect(widget.overflow, isNot(TextOverflow.ellipsis),
                reason: widget.data);
            expect((element.renderObject! as RenderParagraph).didExceedMaxLines,
                isFalse, reason: widget.data);
          }
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          for (final controller in controllers.values) {
            controller.dispose();
          }
        }
      });
    }
  }
}
