import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/app_system_ui_style.dart';
import 'package:meshcore_open/theme/mesh_theme.dart';

const _frameKey = ValueKey('system-ui-frame');

Widget _app({ThemeMode mode = ThemeMode.system, Widget? home}) => MaterialApp(
  theme: MeshTheme.light(),
  darkTheme: MeshTheme.dark(),
  themeMode: mode,
  themeAnimationStyle: AnimationStyle.noAnimation,
  builder: (context, child) => AppSystemUi(
    key: _frameKey,
    child: child ?? const SizedBox.shrink(),
  ),
  home: home ?? const SizedBox.shrink(),
);

void main() {
  for (final brightness in Brightness.values) {
    final theme = brightness == Brightness.dark
        ? MeshTheme.dark()
        : MeshTheme.light();

    test('$brightness supplies the themed color and contrast policy', () {
      final style = appSystemUiStyle(theme);
      expect(style.systemNavigationBarColor, theme.colorScheme.surface);
      expect(style.systemNavigationBarDividerColor, theme.colorScheme.surface);
      expect(style.systemNavigationBarColor!.a, 1.0);
      expect(
        style.systemNavigationBarContrastEnforced,
        brightness == Brightness.light,
      );
    });

    testWidgets(
      '$brightness paints the entire window and retains navigation insets',
      (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        tester.view.devicePixelRatio = 1;
        // TestFlutterView does not derive padding from viewPadding.
        tester.view.padding = const FakeViewPadding(bottom: 24);
        tester.view.viewPadding = const FakeViewPadding(bottom: 24);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.view.resetViewPadding);
        double? bottomPadding;
        double? bottomViewPadding;

        final inputMetrics = MediaQueryData.fromView(tester.view);
        expect(inputMetrics.padding.bottom, 24);
        expect(inputMetrics.viewPadding.bottom, 24);

        await tester.pumpWidget(
          _app(
            home: Builder(
              builder: (context) {
                bottomPadding = MediaQuery.paddingOf(context).bottom;
                bottomViewPadding = MediaQuery.viewPaddingOf(context).bottom;
                return const SizedBox.shrink();
              },
            ),
          ),
        );

        expect(bottomPadding, 24);
        expect(bottomViewPadding, 24);
        expect(
          tester.getSize(find.byKey(_frameKey)),
          tester.view.physicalSize / tester.view.devicePixelRatio,
        );
        expect(
          tester.renderObject(find.byKey(_frameKey)),
          paints..rect(color: theme.colorScheme.surface),
        );
      },
    );
  }

  testWidgets('system theme changes update the painted background', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(_app());
    expect(
      tester.renderObject(find.byKey(_frameKey)),
      paints..rect(color: MeshTheme.light().colorScheme.surface),
    );

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pump();
    expect(
      tester.renderObject(find.byKey(_frameKey)),
      paints..rect(color: MeshTheme.dark().colorScheme.surface),
    );
  });

  testWidgets(
    'a dark fullscreen route overrides bars and popping restores the app style',
    (tester) async {
      await tester.pumpWidget(_app(mode: ThemeMode.light));
      await tester.pump();
      expect(
        SystemChrome.latestStyle!.systemNavigationBarColor,
        MeshTheme.light().colorScheme.surface,
      );

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      final route = navigator.push<void>(
        MaterialPageRoute<void>(
          builder: (context) => const AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle.light,
            child: ColoredBox(
              color: Colors.black,
              child: SizedBox.expand(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        SystemChrome.latestStyle!.systemNavigationBarIconBrightness,
        Brightness.light,
      );
      expect(SystemChrome.latestStyle!.systemNavigationBarColor, Colors.black);

      navigator.pop();
      await tester.pumpAndSettle();
      await route;
      expect(
        SystemChrome.latestStyle!.systemNavigationBarIconBrightness,
        Brightness.dark,
      );
      expect(
        SystemChrome.latestStyle!.systemNavigationBarColor,
        MeshTheme.light().colorScheme.surface,
      );
      expect(
        SystemChrome.latestStyle!.systemNavigationBarContrastEnforced,
        isTrue,
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
