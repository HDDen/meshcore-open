import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/power_saving_settings.dart';
import 'package:meshcore_open/screens/power_saving_screen.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:meshcore_open/widgets/power_saving_settings_tile.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RecordingSettings extends AppSettingsService {
  int intervalSaves = 0;
  int batterySaves = 0;
  int gpsSaves = 0;
  int imageSaves = 0;
  int gifSaves = 0;
  int uiSaves = 0;
  int descriptionSaves = 0;
  int pluginLogSaves = 0;
  int hiddenAnimationSaves = 0;
  int staticAnimationSaves = 0;
  int channelHashSaves = 0;

  @override
  Future<void> setCacheChannelKeyHashes(bool value) {
    channelHashSaves++;
    return super.setCacheChannelKeyHashes(value);
  }

  @override
  Future<void> setPauseHiddenStatusAnimations(bool value) {
    hiddenAnimationSaves++;
    return super.setPauseHiddenStatusAnimations(value);
  }

  @override
  Future<void> setDisableContinuousStatusAnimations(bool value) {
    staticAnimationSaves++;
    return super.setDisableContinuousStatusAnimations(value);
  }

  @override
  Future<void> setReduceBlePluginLogs(bool value) {
    pluginLogSaves++;
    return super.setReduceBlePluginLogs(value);
  }

  @override
  Future<void> setDeferBleLogDescriptions(bool value) {
    descriptionSaves++;
    return super.setDeferBleLogDescriptions(value);
  }

  @override
  Future<void> setUiNotificationIntervalMilliseconds(int milliseconds) {
    uiSaves++;
    return super.setUiNotificationIntervalMilliseconds(milliseconds);
  }

  @override
  Future<void> setPauseHiddenGifs(bool value) {
    gifSaves++;
    return super.setPauseHiddenGifs(value);
  }

  @override
  Future<void> setPauseIdleImageCleanup(bool value) {
    imageSaves++;
    return super.setPauseIdleImageCleanup(value);
  }

  @override
  Future<void> setHiddenRadioStatsIntervalSeconds(int seconds) {
    intervalSaves++;
    return super.setHiddenRadioStatsIntervalSeconds(seconds);
  }

  @override
  Future<void> setBatteryPollingIntervalSeconds(int seconds) {
    batterySaves++;
    return super.setBatteryPollingIntervalSeconds(seconds);
  }

  @override
  Future<void> setGpsPollingIntervalSeconds(int seconds) {
    gpsSaves++;
    return super.setGpsPollingIntervalSeconds(seconds);
  }
}

Finder _slider(String name) => find.descendant(
  of: find.byKey(ValueKey('power-saving-$name')),
  matching: find.byType(Slider),
);

Finder _toggle(String name) => find.descendant(
  of: find.byKey(ValueKey('power-saving-$name')),
  matching: find.byType(Switch),
);

Future<void> _showToggle(WidgetTester tester, String name) async {
  tester.state<ScrollableState>(find.byType(Scrollable).first)
      .position.jumpTo(0);
  await tester.pump();
  await tester.scrollUntilVisible(_toggle(name), 200,
      scrollable: find.byType(Scrollable).first);
  await tester.pump();
}

Future<void> _showSlider(WidgetTester tester, String name) async {
  tester.state<ScrollableState>(find.byType(Scrollable).first)
      .position.jumpTo(0);
  await tester.pump();
  await tester.scrollUntilVisible(_slider(name), 200,
      scrollable: find.byType(Scrollable).first);
  await tester.pump();
}

Future<void> _dragSlider(
  WidgetTester tester,
  String name,
  VoidCallback beforeRelease,
) async {
  await _showSlider(tester, name);
  final rect = tester.getRect(_slider(name));
  final gesture = await tester.startGesture(
    Offset(rect.left + 24, rect.center.dy),
  );
  await gesture.moveBy(const Offset(200, 0));
  await tester.pump();
  beforeRelease();
  await gesture.up();
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 2),
  );
}

Future<void> _select(WidgetTester tester, String label) async {
  tester.state<ScrollableState>(find.byType(Scrollable).first)
      .position.jumpTo(0);
  await tester.pump();
  await tester.ensureVisible(find.byType(DropdownButton<PowerSavingProfile>));
  await tester.tap(find.byType(DropdownButton<PowerSavingProfile>));
  await _settle(tester);
  await tester.tap(find.text(label).last);
  await _settle(tester);
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });
  tearDown(PrefsManager.reset);

  for (final locale in ['en', 'ru']) {
    testWidgets('profile selector and custom slider preserve separate values ($locale)',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final settings = _RecordingSettings();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        settings.dispose();
      });
      await tester.pumpWidget(
        ChangeNotifierProvider<AppSettingsService>.value(
          value: settings,
          child: MaterialApp(
            locale: Locale(locale),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: PowerSavingSettingsTile()),
          ),
        ),
      );
      final title = locale == 'ru' ? 'Энергосбережение' : 'Power saving';
      await tester.tap(find.text(title));
      await _settle(tester);
      expect(find.byType(PowerSavingScreen), findsOneWidget);
      expect(settings.settings.powerSaving.profile, PowerSavingProfile.disabled);
      var slider = tester.widget<Slider>(_slider('radio-stats'));
      expect(slider.value, 1);
      expect(slider.min, 1);
      expect(slider.max, 60);
      expect(slider.onChanged, isNull);
      var pauseSwitch = tester.widget<Switch>(_toggle('radio-indicator'));
      expect(pauseSwitch.value, isFalse);
      expect(pauseSwitch.onChanged, isNull);
      await _showSlider(tester, 'battery');
      var batterySlider = tester.widget<Slider>(_slider('battery'));
      expect(batterySlider.value, 120);
      expect(batterySlider.min, 120);
      expect(batterySlider.max, 600);
      expect(batterySlider.divisions, 8);
      expect(batterySlider.onChanged, isNull);
      await _showSlider(tester, 'gps');
      var gpsSlider = tester.widget<Slider>(_slider('gps'));
      expect(gpsSlider.value, 60);
      expect(gpsSlider.min, 60);
      expect(gpsSlider.max, 600);
      expect(gpsSlider.divisions, 9);
      expect(gpsSlider.onChanged, isNull);

      final custom = locale == 'ru' ? 'Свои настройки' : 'Custom settings';
      final balanced = locale == 'ru' ? 'Сбалансированный' : 'Balanced';
      await _select(tester, custom);
      slider = tester.widget<Slider>(_slider('radio-stats'));
      expect(slider.onChanged, isNotNull);
      pauseSwitch = tester.widget<Switch>(_toggle('radio-indicator'));
      expect(pauseSwitch.onChanged, isNotNull);

      final rect = tester.getRect(_slider('radio-stats'));
      final gesture = await tester.startGesture(
        Offset(rect.left + 24, rect.center.dy),
      );
      await gesture.moveBy(const Offset(200, 0));
      await tester.pump();
      expect(settings.intervalSaves, 0);
      await gesture.up();
      await _settle(tester);
      expect(settings.intervalSaves, 1);
      final saved = settings.settings.powerSaving.custom
          .hiddenRadioStatsIntervalSeconds;
      expect(saved, greaterThan(1));
      await tester.ensureVisible(_toggle('radio-indicator'));
      await tester.tap(_toggle('radio-indicator'));
      await _settle(tester);
      expect(settings.settings.powerSaving.custom.pauseHiddenRadioIndicator,
          isTrue);
      expect(settings.intervalSaves, 1);

      await _dragSlider(tester, 'battery', () {
        expect(settings.batterySaves, 0);
      });
      final savedBattery = settings.settings.powerSaving.custom
          .batteryIntervalSeconds;
      expect(savedBattery, greaterThan(120));
      expect(settings.batterySaves, 1);
      expect(settings.gpsSaves, 0);
      await _dragSlider(tester, 'gps', () {
        expect(settings.gpsSaves, 0);
      });
      final savedGps = settings.settings.powerSaving.custom.gpsIntervalSeconds;
      expect(savedGps, greaterThan(60));
      expect(settings.gpsSaves, 1);
      expect(settings.batterySaves, 1);

      await _select(tester, balanced);
      slider = tester.widget<Slider>(_slider('radio-stats'));
      expect(slider.value, 15);
      expect(slider.onChanged, isNull);
      pauseSwitch = tester.widget<Switch>(_toggle('radio-indicator'));
      expect(pauseSwitch.value, isTrue);
      expect(pauseSwitch.onChanged, isNull);
      expect(settings.settings.powerSaving.custom
          .hiddenRadioStatsIntervalSeconds, saved);
      await _showSlider(tester, 'battery');
      batterySlider = tester.widget<Slider>(_slider('battery'));
      expect(batterySlider.value, 180);
      expect(batterySlider.onChanged, isNull);
      expect(find.textContaining(locale == 'ru'
          ? 'контроля связи: 7 мин' : 'threshold is 7 minutes'), findsOneWidget);
      await _showSlider(tester, 'gps');
      gpsSlider = tester.widget<Slider>(_slider('gps'));
      expect(gpsSlider.value, 120);
      expect(gpsSlider.onChanged, isNull);
      await _select(tester, custom);
      expect(tester.widget<Slider>(_slider('radio-stats')).value,
          saved.toDouble());
      expect(settings.intervalSaves, 1);
      expect(tester.widget<Switch>(_toggle('radio-indicator')).value, isTrue);
      await tester.ensureVisible(_toggle('radio-indicator'));
      await tester.tap(_toggle('radio-indicator'));
      await _settle(tester);
      expect(settings.settings.powerSaving.custom.pauseHiddenRadioIndicator,
          isFalse);
      await _select(tester, balanced);
      expect(tester.widget<Switch>(_toggle('radio-indicator')).value, isTrue);
      await _select(tester, custom);
      expect(tester.widget<Switch>(_toggle('radio-indicator')).value, isFalse);
      expect(settings.settings.powerSaving.custom
          .hiddenRadioStatsIntervalSeconds, saved);
      await _showSlider(tester, 'battery');
      expect(tester.widget<Slider>(_slider('battery')).value,
          savedBattery.toDouble());
      expect(tester.widget<Slider>(_slider('battery')).onChanged, isNotNull);
      await _showSlider(tester, 'gps');
      expect(tester.widget<Slider>(_slider('gps')).value, savedGps.toDouble());
      expect(tester.widget<Slider>(_slider('gps')).onChanged, isNotNull);
      expect(settings.batterySaves, 1);
      expect(settings.gpsSaves, 1);

      await _showSlider(tester, 'battery');
      final pendingRect = tester.getRect(_slider('battery'));
      final pendingDrag = await tester.startGesture(
        Offset(pendingRect.left + 24, pendingRect.center.dy),
      );
      await pendingDrag.moveBy(const Offset(100, 0));
      await tester.pump();
      await settings.setPowerSavingProfile(PowerSavingProfile.balanced);
      await tester.pump();
      await pendingDrag.up();
      await _settle(tester);
      expect(settings.batterySaves, 1);
      expect(settings.settings.powerSaving.custom.batteryIntervalSeconds,
          savedBattery);

      final off = locale == 'ru' ? 'Выключено' : 'Off';
      await _select(tester, off);
      await _showToggle(tester, 'image-cleanup');
      var imageSwitch = tester.widget<Switch>(_toggle('image-cleanup'));
      expect(imageSwitch.value, isFalse);
      expect(imageSwitch.onChanged, isNull);
      expect(find.text(locale == 'ru'
          ? 'Приостанавливать очистку изображений в простое'
          : 'Pause idle image cleanup'), findsOneWidget);
      await _select(tester, balanced);
      await _showToggle(tester, 'image-cleanup');
      imageSwitch = tester.widget<Switch>(_toggle('image-cleanup'));
      expect(imageSwitch.value, isTrue);
      expect(imageSwitch.onChanged, isNull);
      await _select(tester, custom);
      await _showToggle(tester, 'image-cleanup');
      imageSwitch = tester.widget<Switch>(_toggle('image-cleanup'));
      expect(imageSwitch.value, isFalse);
      expect(imageSwitch.onChanged, isNotNull);
      await tester.tap(_toggle('image-cleanup'));
      await _settle(tester);
      expect(settings.imageSaves, 1);
      expect(settings.settings.powerSaving.custom.pauseIdleImageCleanup, isTrue);
      expect(settings.settings.powerSaving.custom.pauseHiddenRadioIndicator, isFalse);
      expect(settings.settings.powerSaving.custom.batteryIntervalSeconds, savedBattery);
      expect(settings.settings.powerSaving.custom.gpsIntervalSeconds, savedGps);
      expect(settings.settings.powerSaving.custom.hiddenRadioStatsIntervalSeconds, saved);
      await _select(tester, balanced);
      await _select(tester, custom);
      await _showToggle(tester, 'image-cleanup');
      expect(tester.widget<Switch>(_toggle('image-cleanup')).value, isTrue);
      await tester.tap(_toggle('image-cleanup'));
      await _settle(tester);
      expect(settings.imageSaves, 2);
      expect(settings.settings.powerSaving.custom.pauseIdleImageCleanup, isFalse);
      expect(settings.batterySaves, 1);
      expect(settings.gpsSaves, 1);
      expect(settings.intervalSaves, 1);
      await _select(tester, off);
      await _showToggle(tester, 'gifs');
      var gifSwitch = tester.widget<Switch>(_toggle('gifs'));
      expect(gifSwitch.value, isFalse);
      expect(gifSwitch.onChanged, isNull);
      expect(find.text(locale == 'ru' ? 'Приостанавливать скрытые GIF' : 'Pause hidden GIFs'),
          findsOneWidget);
      await _select(tester, balanced);
      await _showToggle(tester, 'gifs');
      gifSwitch = tester.widget<Switch>(_toggle('gifs'));
      expect(gifSwitch.value, isTrue);
      expect(gifSwitch.onChanged, isNull);
      await _select(tester, custom);
      await _showToggle(tester, 'gifs');
      expect(tester.widget<Switch>(_toggle('gifs')).value, isFalse);
      expect(tester.widget<Switch>(_toggle('gifs')).onChanged, isNotNull);
      await tester.tap(_toggle('gifs'));
      await _settle(tester);
      expect(settings.gifSaves, 1);
      expect(settings.settings.powerSaving.custom.pauseHiddenGifs, isTrue);
      expect(settings.settings.powerSaving.custom.pauseIdleImageCleanup, isFalse);
      expect(settings.settings.powerSaving.custom.pauseHiddenRadioIndicator, isFalse);
      expect(settings.settings.powerSaving.custom.batteryIntervalSeconds, savedBattery);
      expect(settings.settings.powerSaving.custom.gpsIntervalSeconds, savedGps);
      await _select(tester, balanced);
      await _select(tester, custom);
      await _showToggle(tester, 'gifs');
      expect(tester.widget<Switch>(_toggle('gifs')).value, isTrue);
      await tester.tap(_toggle('gifs'));
      await _settle(tester);
      expect(settings.gifSaves, 2);
      expect(settings.settings.powerSaving.custom.pauseHiddenGifs, isFalse);
      expect(settings.imageSaves, 2);
      expect(settings.batterySaves, 1);
      expect(settings.gpsSaves, 1);

      await _select(tester, off);
      await _showSlider(tester, 'ui-notifications');
      var uiSlider = tester.widget<Slider>(_slider('ui-notifications'));
      expect(uiSlider.value, 50);
      expect(uiSlider.min, 50);
      expect(uiSlider.max, 1000);
      expect(uiSlider.divisions, 19);
      expect(uiSlider.onChanged, isNull);
      expect(find.text(locale == 'ru' ? '50 мс' : '50 ms'), findsOneWidget);
      for (final entry in [
        (balanced, 100),
        (locale == 'ru' ? 'Экономный' : 'Economical', 250),
        (locale == 'ru' ? 'Максимальная экономия' : 'Maximum saving', 500),
      ]) {
        await _select(tester, entry.$1);
        await _showSlider(tester, 'ui-notifications');
        uiSlider = tester.widget<Slider>(_slider('ui-notifications'));
        expect(uiSlider.value, entry.$2.toDouble());
        expect(uiSlider.onChanged, isNull);
      }
      await _select(tester, custom);
      await _dragSlider(tester, 'ui-notifications', () {
        expect(settings.uiSaves, 0);
      });
      final savedUi = settings.settings.powerSaving.custom
          .uiNotificationIntervalMilliseconds;
      expect(savedUi, greaterThan(50));
      expect(savedUi % 50, 0);
      expect(settings.uiSaves, 1);
      expect(settings.settings.powerSaving.custom.batteryIntervalSeconds, savedBattery);
      expect(settings.settings.powerSaving.custom.gpsIntervalSeconds, savedGps);
      expect(settings.settings.powerSaving.custom.hiddenRadioStatsIntervalSeconds, saved);
      await _select(tester, balanced);
      await _select(tester, custom);
      await _showSlider(tester, 'ui-notifications');
      expect(tester.widget<Slider>(_slider('ui-notifications')).value, savedUi.toDouble());
      final uiRect = tester.getRect(_slider('ui-notifications'));
      final uiDrag = await tester.startGesture(Offset(uiRect.left + 24, uiRect.center.dy));
      await uiDrag.moveBy(const Offset(100, 0));
      await tester.pump();
      await settings.setPowerSavingProfile(PowerSavingProfile.balanced);
      await tester.pump();
      await uiDrag.up();
      await _settle(tester);
      expect(settings.uiSaves, 1);
      expect(settings.settings.powerSaving.custom.uiNotificationIntervalMilliseconds, savedUi);
      await _select(tester, off);
      await _showToggle(tester, 'log-descriptions');
      var descriptionSwitch = tester.widget<Switch>(_toggle('log-descriptions'));
      expect(descriptionSwitch.value, isFalse);
      expect(descriptionSwitch.onChanged, isNull);
      expect(find.text(locale == 'ru'
          ? 'Откладывать описание кадров журнала' : 'Defer frame log descriptions'), findsOneWidget);
      for (final preset in [
        balanced,
        locale == 'ru' ? 'Экономный' : 'Economical',
        locale == 'ru' ? 'Максимальная экономия' : 'Maximum saving',
      ]) {
        await _select(tester, preset);
        await _showToggle(tester, 'log-descriptions');
        descriptionSwitch = tester.widget<Switch>(_toggle('log-descriptions'));
        expect(descriptionSwitch.value, isTrue);
        expect(descriptionSwitch.onChanged, isNull);
      }
      await _select(tester, custom);
      await _showToggle(tester, 'log-descriptions');
      expect(tester.widget<Switch>(_toggle('log-descriptions')).value, isFalse);
      await tester.tap(_toggle('log-descriptions'));
      await _settle(tester);
      expect(settings.descriptionSaves, 1);
      expect(settings.settings.powerSaving.custom.deferBleLogDescriptions, isTrue);
      expect(settings.settings.powerSaving.custom.uiNotificationIntervalMilliseconds, savedUi);
      expect(settings.settings.powerSaving.custom.batteryIntervalSeconds, savedBattery);
      expect(settings.settings.powerSaving.custom.gpsIntervalSeconds, savedGps);
      expect(settings.settings.powerSaving.custom.hiddenRadioStatsIntervalSeconds, saved);
      await _select(tester, off);
      await _select(tester, custom);
      await _showToggle(tester, 'log-descriptions');
      expect(tester.widget<Switch>(_toggle('log-descriptions')).value, isTrue);
      await tester.tap(_toggle('log-descriptions'));
      await _settle(tester);
      expect(settings.descriptionSaves, 2);
      expect(settings.settings.powerSaving.custom.deferBleLogDescriptions, isFalse);
      expect(settings.uiSaves, 1);
      expect(settings.gifSaves, 2);
      expect(settings.imageSaves, 2);

      await _select(tester, off);
      await _showToggle(tester, 'ble-plugin-logs');
      var pluginSwitch = tester.widget<Switch>(_toggle('ble-plugin-logs'));
      expect(pluginSwitch.value, isFalse);
      expect(pluginSwitch.onChanged, isNull);
      expect(find.text(locale == 'ru'
          ? 'Меньше служебных BLE-логов' : 'Reduce Bluetooth diagnostic logs'), findsOneWidget);
      for (final preset in [
        balanced,
        locale == 'ru' ? 'Экономный' : 'Economical',
        locale == 'ru' ? 'Максимальная экономия' : 'Maximum saving',
      ]) {
        await _select(tester, preset);
        await _showToggle(tester, 'ble-plugin-logs');
        pluginSwitch = tester.widget<Switch>(_toggle('ble-plugin-logs'));
        expect(pluginSwitch.value, isTrue);
        expect(pluginSwitch.onChanged, isNull);
      }
      await _select(tester, custom);
      await _showToggle(tester, 'ble-plugin-logs');
      expect(tester.widget<Switch>(_toggle('ble-plugin-logs')).value, isFalse);
      expect(tester.widget<Switch>(_toggle('ble-plugin-logs')).onChanged, isNotNull);
      await tester.tap(_toggle('ble-plugin-logs'));
      await _settle(tester);
      expect(settings.pluginLogSaves, 1);
      expect(settings.settings.powerSaving.custom.reduceBlePluginLogs, isTrue);
      expect(settings.settings.powerSaving.custom.deferBleLogDescriptions, isFalse);
      expect(settings.settings.powerSaving.custom.uiNotificationIntervalMilliseconds, savedUi);
      expect(settings.settings.powerSaving.custom.batteryIntervalSeconds, savedBattery);
      expect(settings.settings.powerSaving.custom.gpsIntervalSeconds, savedGps);
      expect(settings.settings.powerSaving.custom.hiddenRadioStatsIntervalSeconds, saved);
      await _select(tester, off);
      await _select(tester, custom);
      await _showToggle(tester, 'ble-plugin-logs');
      expect(tester.widget<Switch>(_toggle('ble-plugin-logs')).value, isTrue);
      await tester.tap(_toggle('ble-plugin-logs'));
      await _settle(tester);
      expect(settings.pluginLogSaves, 2);
      expect(settings.settings.powerSaving.custom.reduceBlePluginLogs, isFalse);
      expect(settings.descriptionSaves, 2);
      expect(settings.uiSaves, 1);
      expect(settings.gifSaves, 2);
      expect(settings.imageSaves, 2);

      for (final entry in [
        ('hidden-status-animations', 'pause_hidden_status_animations',
            locale == 'ru' ? 'Приостанавливать скрытые статусные анимации'
                : 'Pause hidden status animations'),
        ('static-status-animations', 'disable_continuous_status_animations',
            locale == 'ru' ? 'Статичные индикаторы статуса' : 'Static status indicators'),
        ('channel-key-hashes', 'cache_channel_key_hashes',
            locale == 'ru' ? 'Кэшировать параметры каналов' : 'Cache channel parameters'),
      ]) {
        await _select(tester, off);
        await _showToggle(tester, entry.$1);
        var toggle = tester.widget<Switch>(_toggle(entry.$1));
        expect(toggle.value, isFalse);
        expect(toggle.onChanged, isNull);
        expect(find.text(entry.$3), findsOneWidget);
        for (final preset in [
          balanced,
          locale == 'ru' ? 'Экономный' : 'Economical',
          locale == 'ru' ? 'Максимальная экономия' : 'Maximum saving',
        ]) {
          await _select(tester, preset);
          await _showToggle(tester, entry.$1);
          toggle = tester.widget<Switch>(_toggle(entry.$1));
          expect(toggle.value, preset != balanced || entry.$1 != 'static-status-animations');
          expect(toggle.onChanged, isNull);
        }
        await _select(tester, custom);
        await _showToggle(tester, entry.$1);
        final savedOptions = settings.settings.powerSaving.custom.toJson();
        expect(tester.widget<Switch>(_toggle(entry.$1)).value, isFalse);
        expect(tester.widget<Switch>(_toggle(entry.$1)).onChanged, isNotNull);
        await tester.tap(_toggle(entry.$1));
        await _settle(tester);
        expect(settings.settings.powerSaving.custom.toJson(), {
          ...savedOptions, entry.$2: true,
        });
        await _select(tester, off);
        await _select(tester, custom);
        await _showToggle(tester, entry.$1);
        expect(tester.widget<Switch>(_toggle(entry.$1)).value, isTrue);
        await tester.tap(_toggle(entry.$1));
        await _settle(tester);
        expect(settings.settings.powerSaving.custom.toJson(), savedOptions);
      }
      expect(settings.hiddenAnimationSaves, 2);
      expect(settings.staticAnimationSaves, 2);
      expect(settings.channelHashSaves, 2);
      expect(settings.pluginLogSaves, 2);
      expect(settings.descriptionSaves, 2);
    });
  }
}
