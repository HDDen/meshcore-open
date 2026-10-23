import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/app_system_ui_style.dart';
import 'package:meshcore_open/theme/mesh_theme.dart';

const _regionKey = ValueKey('app-system-ui-baseline');

Widget _app({ThemeMode mode = ThemeMode.system}) => MaterialApp(
  theme: MeshTheme.light(),
  darkTheme: MeshTheme.dark(),
  themeMode: mode,
  themeAnimationStyle: AnimationStyle.noAnimation,
  builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
    key: _regionKey,
    value: appSystemUiStyle(Theme.of(context)),
    child: child ?? const SizedBox.shrink(),
  ),
  home: Scaffold(appBar: AppBar(title: const Text('System bars'))),
);

SystemUiOverlayStyle _style(WidgetTester tester) => tester
    .widget<AnnotatedRegion<SystemUiOverlayStyle>>(find.byKey(_regionKey))
    .value;

void _expectBrightness(WidgetTester tester, Brightness themeBrightness) {
  final expectedIcons = themeBrightness == Brightness.dark
      ? Brightness.light
      : Brightness.dark;
  final style = _style(tester);
  expect(style.systemNavigationBarIconBrightness, expectedIcons);
  expect(style.statusBarIconBrightness, expectedIcons);
  expect(style.statusBarBrightness, themeBrightness);
  expect(style.statusBarColor, Colors.transparent);
}

void main() {
  for (final systemBrightness in Brightness.values) {
    testWidgets('system theme follows $systemBrightness for both bars', (
      tester,
    ) async {
      tester.platformDispatcher.platformBrightnessTestValue = systemBrightness;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      await tester.pumpWidget(_app());
      _expectBrightness(tester, systemBrightness);
    });

    testWidgets('explicit theme overrides system $systemBrightness', (
      tester,
    ) async {
      tester.platformDispatcher.platformBrightnessTestValue = systemBrightness;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      await tester.pumpWidget(_app(mode: ThemeMode.dark));
      _expectBrightness(tester, Brightness.dark);

      await tester.pumpWidget(_app(mode: ThemeMode.light));
      _expectBrightness(tester, Brightness.light);
    });
  }

  testWidgets('system brightness changes update the existing app', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(_app());
    _expectBrightness(tester, Brightness.light);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pump();
    _expectBrightness(tester, Brightness.dark);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pump();
    _expectBrightness(tester, Brightness.light);
  });

  testWidgets('returning from an explicit theme uses current system brightness', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(_app(mode: ThemeMode.light));
    _expectBrightness(tester, Brightness.light);

    await tester.pumpWidget(_app());
    _expectBrightness(tester, Brightness.dark);
  });
}
