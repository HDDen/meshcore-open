import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/services/app_update_service.dart';
import 'package:meshcore_open/services/github_release_check.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:meshcore_open/theme/mesh_theme.dart';
import 'package:meshcore_open/widgets/app_update_controls.dart';

class _Api extends GitHubReleaseCheck {
  int calls = 0;
  bool available = false;
  UpdateCheckException? error;
  @override
  Future<bool> hasNewerRelease(String installedCommit) async {
    calls++;
    if (error != null) throw error!;
    return available;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Api api;
  late AppSettingsService settings;
  late AppUpdateService service;
  const browserChannel = MethodChannel('plugins.flutter.io/url_launcher');
  final copied = <String>[];
  final opened = <String>[];
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
    settings = AppSettingsService();
    api = _Api();
    copied.clear();
    opened.clear();
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
    messenger.setMockMethodCallHandler(browserChannel, (call) async {
      if (call.method == 'launch') {
        opened.add((call.arguments as Map)['url'] as String);
        return true;
      }
      return false;
    });
  });
  tearDown(() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    messenger.setMockMethodCallHandler(browserChannel, null);
    service.dispose();
    settings.dispose();
    PrefsManager.reset();
  });

  Future<void> show(WidgetTester tester) async {
    service = AppUpdateService(preferences: PrefsManager.instance, api: api,
      installedCommit: 'a' * 40, clock: () => tester.binding.clock.now());
    final key = GlobalKey<ScaffoldMessengerState>();
    await tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider.value(value: settings),
      ChangeNotifierProvider.value(value: service),
    ], child: MaterialApp(
      scaffoldMessengerKey: key,
      theme: MeshTheme.dark(),
      locale: const Locale('ru'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => AppUpdateBinding(messengerKey: key, child: child!),
      home: const Scaffold(body: AppUpdateSettingsTile()),
    )));
    await tester.pumpAndSettle();
  }

  testWidgets('automatic negative is silent; manual negative shows information', (tester) async {
    await show(tester);
    expect(api.calls, 1);
    expect(find.byType(SnackBar), findsNothing);
    await tester.tap(find.text('Проверить обновления'));
    await tester.pumpAndSettle();
    expect(api.calls, 2);
    expect(find.text('Обновления не найдены'), findsOneWidget);
    final bar = find.byType(SnackBar);
    final theme = Theme.of(tester.element(find.byType(AppUpdateSettingsTile)));
    final surface = find.descendant(of: bar, matching: find.byWidgetPredicate(
      (widget) => widget is Material && widget.color == theme.snackBarTheme.backgroundColor,
    ));
    expect(surface, findsOneWidget);
    // Use the painted surface, excluding the floating snackbar's outer margin.
    // A tap in its right padding, outside the text, must dismiss the notice.
    final bounds = tester.getRect(surface);
    await tester.tapAt(Offset(bounds.right - 12, bounds.center.dy));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    expect(copied, isEmpty);
    expect(opened, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('positive result changes the tile and offers a clickable snackbar', (tester) async {
    api.available = true;
    await show(tester);
    expect(find.text('Доступно обновление! Перейти к нему...'), findsOneWidget);
    final notice = find.text('Обнаружена свежая версия! Нажмите, чтобы перейти к странице релизов.');
    expect(notice, findsOneWidget);
    expect(service.updateAvailable, isTrue);
    await tester.tap(notice);
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    expect(opened, [githubReleasesPage.toString()]);
    expect(copied, isEmpty);
    await tester.tap(find.text('Доступно обновление! Перейти к нему...'));
    await tester.pumpAndSettle();
    expect(opened, [githubReleasesPage.toString(), githubReleasesPage.toString()]);
    expect(api.calls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('errors are red and include a separate cause', (tester) async {
    api.error = const UpdateCheckException(UpdateCheckError.network);
    await show(tester);
    expect(find.text('Не удалось проверить обновления'), findsOneWidget);
    expect(find.text('Нет доступа к GitHub. Проверьте подключение к интернету.'), findsOneWidget);
    final snackbar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snackbar.backgroundColor, Theme.of(tester.element(find.byType(AppUpdateSettingsTile))).colorScheme.error);
    await tester.tap(find.text('Не удалось проверить обновления'));
    await tester.pumpAndSettle();
    expect(copied, ['Не удалось проверить обновления\nНет доступа к GitHub. Проверьте подключение к интернету.']);
    expect(find.byType(SnackBar), findsNothing);
    expect(opened, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('disabled automatic checks keep the manual button operational', (tester) async {
    await settings.setCheckGitHubUpdates(false);
    await show(tester);
    expect(api.calls, 0);
    await tester.tap(find.text('Проверить обновления'));
    await tester.pumpAndSettle();
    expect(api.calls, 1);
    expect(find.text('Обновления не найдены'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('background time does not run checks; an overdue check runs on resume', (tester) async {
    final original = tester.binding.lifecycleState;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await show(tester);
    expect(api.calls, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(days: 2));
    expect(api.calls, 1);
    expect(service.timeUntilCheck, Duration.zero);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    // Resume first schedules a frame; its post-frame callback creates the
    // zero-delay timer. pumpAndSettle only follows frames, not pending timers.
    await tester.pump();
    await tester.pump(Duration.zero);
    await tester.pumpAndSettle();
    expect(api.calls, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    if (original != null) {
      tester.binding.handleAppLifecycleStateChanged(original);
    }
  });
}
