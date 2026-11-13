import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mco_service/mco_service.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/models/quick_actions_settings.dart';
import 'package:meshcore_open/screens/quick_actions_settings_screen.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:meshcore_open/widgets/app_bar.dart';
import 'package:meshcore_open/widgets/battery_indicator.dart';
import 'package:meshcore_open/widgets/quick_actions_button.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Radio extends ChangeNotifier implements MeshCoreConnector {
  @override
  bool get isConnected => true;

  @override
  bool get isOfflineMode => false;

  @override
  bool get isSessionReady => true;

  @override
  String? get selfName => 'Test radio';

  @override
  int? get batteryPercent => 80;

  @override
  int? get batteryMillivolts => 3950;

  @override
  bool get supportsCompanionRadioStats => false;

  @override
  final repeaterActivity = ValueNotifier<int>(0);

  @override
  List<DirectRepeater> get directRepeaters => const [];

  @override
  int? get currentSf => 7;

  @override
  void dispose() {
    repeaterActivity.dispose();
    super.dispose();
  }

  final adverts = <(bool, bool)>[];
  final advertDone = Completer<void>();

  @override
  Future<void> sendSelfAdvert({bool flood = true, bool waitForAck = false}) {
    adverts.add((flood, waitForAck));
    return advertDone.future;
  }

  @override
  final channels = <Channel>[];
  @override
  final unconfirmedChannelSlots = <int>{};
  final sent = <(int, String, bool)>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #sendChannelMessage) {
      sent.add((
        (invocation.positionalArguments[0] as Channel).index,
        invocation.positionalArguments[1] as String,
        invocation.namedArguments[#reportFailure] == true,
      ));
      return Future<void>.value();
    }
    return super.noSuchMethod(invocation);
  }
}

class _ProxySections extends SettingsSectionsService {
  bool licensed = false;
  bool bleLicensed = false;
  final writes = <(String, bool)>[];
  final enabled = Completer<void>();
  bool? waitForBleOnEnable;
  bool _master = false;
  bool _tcp = false;
  bool _ble = false;

  @override
  bool get companionProxySupported => true;

  @override
  bool get allowsCompanionProxy => licensed;

  @override
  bool get allowsCompanionProxyTcp => licensed;

  @override
  bool get allowsCompanionProxyBle => licensed && bleLicensed;

  @override
  bool get companionProxyEnabled => licensed && _master;

  @override
  bool get companionProxyTcpEnabled => licensed && _tcp;

  @override
  bool get companionProxyBleEnabled => allowsCompanionProxyBle && _ble;

  @override
  String? get companionProxyError => null;

  @override
  Future<void> setCompanionProxyEnabled(
    bool value, {
    bool waitForBle = false,
  }) async {
    waitForBleOnEnable = waitForBle;
    writes.add(('companion', value));
    await enabled.future;
    _master = value;
    notifyListeners();
  }

  @override
  Future<void> setCompanionProxyTcpEnabled(bool value) async {
    writes.add(('tcp', value));
    _tcp = value;
    notifyListeners();
  }

  @override
  Future<void> setCompanionProxyBleEnabled(bool value) async {
    writes.add(('ble', value));
    _ble = value;
    notifyListeners();
  }

  void setLicense({required bool proxy, required bool ble}) {
    licensed = proxy;
    bleLicensed = ble;
    notifyListeners();
  }
}

QuickActionsSettings _visibleActions(List<QuickActionItem> shown) =>
    QuickActionsSettings([
      ...shown,
      for (final action in QuickAction.values)
        if (!shown.any((item) => item.action == action))
          QuickActionItem(action, visible: false),
    ]);

Future<void> _open(
  WidgetTester tester,
  _Radio radio,
  AppSettingsService settings, {
  SettingsSectionsService? sections,
  bool useHeader = false,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<MeshCoreConnector>.value(value: radio),
        ChangeNotifierProvider<AppSettingsService>.value(value: settings),
        if (sections != null)
          ChangeNotifierProvider<SettingsSectionsService>.value(value: sections),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(settings.settings.uiScale),
          ),
          child: child!,
        ),
        home: useHeader
            ? Scaffold(appBar: AppBar(title: const AppBarTitle('Channels')))
            : Scaffold(body: QuickActionsButton(connector: radio)),
      ),
    ),
  );
  await tester.tap(find.byTooltip('Quick actions'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });
  tearDown(PrefsManager.reset);

  testWidgets('header puts quick actions before battery and reacts to proxy rights', (
    tester,
  ) async {
    final radio = _Radio();
    final sections = _ProxySections();
    final settings = AppSettingsService();
    addTearDown(radio.dispose);
    addTearDown(sections.dispose);
    addTearDown(settings.dispose);
    await settings.updateSettings(settings.settings.copyWith(
      snrIndicatorAllRepActivity: false,
      quickActions: _visibleActions(const [
        QuickActionItem(QuickAction.companionProxy, visible: true),
        QuickActionItem(QuickAction.tcpProxy, visible: true),
        QuickActionItem(QuickAction.bleProxy, visible: true),
      ]),
    ));

    Finder tile(QuickAction action) => find.byKey(ValueKey(action));
    InkWell ink(QuickAction action) => tester.widget<InkWell>(tile(action));
    AnimatedOpacity opacity(QuickAction action) => tester.widget<AnimatedOpacity>(
      find.ancestor(of: tile(action), matching: find.byType(AnimatedOpacity)),
    );

    const master = QuickAction.companionProxy;
    const tcp = QuickAction.tcpProxy;
    const ble = QuickAction.bleProxy;
    try {
      await _open(tester, radio, settings, sections: sections, useHeader: true);
      final toolbar = find.byType(AppBar, skipOffstage: false);
      final launch = find.descendant(
        of: toolbar,
        matching: find.byType(QuickActionsButton, skipOffstage: false),
        skipOffstage: false,
      );
      final battery = find.byType(BatteryIndicator, skipOffstage: false);
      expect(tester.getCenter(launch).dx, lessThan(tester.getCenter(battery).dx));
      for (final action in [master, tcp, ble]) {
        expect(ink(action).onTap, isNull);
        expect(opacity(action).opacity, lessThan(1));
      }

      sections.setLicense(proxy: true, ble: false);
      await tester.pumpAndSettle();
      expect(ink(master).onTap, isNotNull);
      expect(ink(tcp).onTap, isNull);
      expect(ink(ble).onTap, isNull);
      await tester.tap(tile(master));
      await tester.pumpAndSettle();
      expect(opacity(master).opacity, lessThan(1));
      expect(sections.writes, [('companion', true)]);
      expect(sections.waitForBleOnEnable, isTrue);
      sections.enabled.complete();
      await tester.pumpAndSettle();
      expect(opacity(master).opacity, 1);
      expect(ink(tcp).onTap, isNull);
      await tester.tap(tile(ble));
      await tester.pumpAndSettle();
      expect(sections.writes.last, ('tcp', true));

      sections.setLicense(proxy: true, ble: true);
      await tester.pumpAndSettle();
      await tester.tap(tile(tcp));
      await tester.pumpAndSettle();
      expect(sections.writes.last, ('ble', true));

      sections.setLicense(proxy: false, ble: false);
      await tester.pumpAndSettle();
      for (final action in [master, tcp, ble]) {
        expect(ink(action).onTap, isNull);
      }
      expect(sections.writes, hasLength(3));
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });

  testWidgets('panel toggles real settings and waits for the advert ACK', (tester) async {
    final radio = _Radio();
    final settings = AppSettingsService();
    addTearDown(radio.dispose);
    addTearDown(settings.dispose);
    await settings.updateSettings(settings.settings.copyWith(
      quickActions: _visibleActions(const [
        QuickActionItem(QuickAction.channelRetries, visible: true),
        QuickActionItem(QuickAction.adaptiveTxPower, visible: true),
        QuickActionItem(QuickAction.floodAdvert, visible: true),
        QuickActionItem(QuickAction.companionProxy, visible: true),
      ]),
    ));

    try {
      await _open(tester, radio, settings);
      final l10n = AppLocalizations.of(tester.element(find.byType(AlertDialog)));
      InkWell tile(QuickAction action) => tester.widget<InkWell>(find.byKey(ValueKey(action)));
      expect(tester.widget<AlertDialog>(find.byType(AlertDialog)).title, isNull);
      expect(tile(QuickAction.adaptiveTxPower).onTap, isNull);
      expect(tile(QuickAction.companionProxy).onTap, isNull);
      await tester.tap(find.text(l10n.quickActions_retries));
      await tester.pumpAndSettle();
      expect(settings.settings.channelMinHopsEnabled, isTrue);
      await tester.tap(find.text(l10n.adaptiveTxPower));
      await tester.pumpAndSettle();
      expect(settings.settings.adaptiveTxPower.enabled, isTrue);
      await tester.tap(find.text(l10n.quickActions_retries));
      await tester.pumpAndSettle();
      expect(settings.settings.channelMinHopsEnabled, isFalse);
      expect(settings.settings.adaptiveTxPower.enabled, isFalse);

      final advert = find.byKey(const ValueKey(QuickAction.floodAdvert));
      AnimatedOpacity opacity() => tester.widget<AnimatedOpacity>(
        find.ancestor(of: advert, matching: find.byType(AnimatedOpacity)),
      );
      await tester.tap(advert);
      await tester.pumpAndSettle();
      expect(opacity().opacity, lessThan(1));
      expect(tile(QuickAction.floodAdvert).onTap, isNull);
      expect(radio.adverts, [(true, true)]);
      radio.advertDone.complete();
      await tester.pumpAndSettle();
      expect(opacity().opacity, 1);

      await tester.tap(find.text(l10n.quickActions_configure));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(QuickActionsSettingsScreen), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });

  testWidgets('panel wraps labels and keeps actions reachable on a narrow screen', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 420);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final radio = _Radio();
    final settings = AppSettingsService();
    addTearDown(radio.dispose);
    addTearDown(settings.dispose);
    const label = 'Send the current status to the channel';
    await settings.updateSettings(settings.settings.copyWith(
      uiScale: 2,
      quickActions: _visibleActions(const [
        QuickActionItem(QuickAction.channelRetries, visible: true),
        QuickActionItem(
          QuickAction.channelMessage1,
          visible: true,
          name: label,
          text: 'Here',
          channelName: '#test',
        ),
      ]),
    ));

    try {
      await _open(tester, radio, settings);
      final caption = find.text(label);
      final text = tester.widget<Text>(caption);
      expect(text.softWrap, isTrue);
      expect(text.maxLines, isNull);
      expect(tester.getSize(caption).height, greaterThan(30));
      expect(tester.takeException(), isNull);
      final close = find.widgetWithText(FilledButton, 'Close');
      expect(close.hitTestable(), findsOneWidget);
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });

  testWidgets('editing and reordering presets persists independent button settings', (
    tester,
  ) async {
    final radio = _Radio();
    final settings = AppSettingsService();
    final reloaded = AppSettingsService();
    addTearDown(radio.dispose);
    addTearDown(settings.dispose);
    addTearDown(reloaded.dispose);
    const channelAction = QuickAction.channelMessage1;
    const cliAction = QuickAction.cliCommand1;
    const otherChannel = QuickAction.channelMessage2;
    const message = '  Here\nReady  ';
    await settings.updateSettings(settings.settings.copyWith(
      quickActions: _visibleActions(const [
        QuickActionItem(
          otherChannel,
          visible: true,
          name: 'Other channel',
          text: 'Untouched',
          channelName: '#other',
        ),
        QuickActionItem(channelAction, visible: false),
        QuickActionItem(cliAction, visible: false),
      ]),
    ));

    Finder row(QuickAction action) => find.byKey(ValueKey(action));
    Finder field(String label) => find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == label,
    );

    try {
      await _open(tester, radio, settings);
      final l10n = AppLocalizations.of(tester.element(find.byType(AlertDialog)));
      await tester.tap(find.text(l10n.quickActions_configure));
      await tester.pumpAndSettle();

      await tester.tap(row(channelAction));
      await tester.pumpAndSettle();
      final editor = find.byType(AlertDialog);
      expect(tester.widget<AlertDialog>(editor).title, isNull);
      final save = find.widgetWithText(FilledButton, l10n.common_save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.text(l10n.quickActions_required), findsNWidgets(2));
      await tester.enterText(field(l10n.quickActions_name), 'Check in');
      await tester.enterText(field(l10n.quickActions_text), message);
      await tester.enterText(field(l10n.channels_channelName), '#test');
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(editor, findsNothing);
      expect(
        find.descendant(of: row(channelAction), matching: find.text(message)),
        findsOneWidget,
      );
      expect(find.text('Untouched'), findsOneWidget);

      final visibility = find.descendant(
        of: row(channelAction),
        matching: find.byType(Switch),
      );
      expect(tester.widget<Switch>(visibility).value, isFalse);
      await tester.tap(visibility);
      await tester.pumpAndSettle();

      await tester.tap(row(cliAction));
      await tester.pumpAndSettle();
      expect(field(l10n.channels_channelName), findsNothing);
      await tester.enterText(field(l10n.quickActions_text), 'v');
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.text(l10n.companionCli_invalidCommand), findsOneWidget);
      await tester.enterText(field(l10n.quickActions_text), 'ver');
      await tester.tap(find.widgetWithText(TextButton, l10n.common_cancel));
      await tester.pumpAndSettle();

      final list = tester.widget<ReorderableListView>(find.byType(ReorderableListView));
      final handle = find.descendant(
        of: row(channelAction),
        matching: find.byType(ReorderableDragStartListener),
      );
      expect(tester.widget<ReorderableDragStartListener>(handle).index, 1);
      list.onReorderItem!(1, 0);
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(row(channelAction)).dy,
        lessThan(tester.getTopLeft(row(otherChannel)).dy),
      );

      await reloaded.loadSettings();
      final items = reloaded.settings.quickActions.items;
      expect(items.first.action, channelAction);
      expect(items.first.visible, isTrue);
      expect(items.first.name, 'Check in');
      expect(items.first.text, message);
      expect(items.first.channelName, '#test');
      expect(items[1].text, 'Untouched');
      expect(items[2].text, isEmpty);

      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(l10n.quickActions_title));
      await tester.pumpAndSettle();
      expect(
        tester.getCenter(find.text('Check in')).dx,
        lessThan(tester.getCenter(find.text('Other channel')).dx),
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });

  testWidgets('channel presets send by name and reject ambiguous targets', (tester) async {
    final radio = _Radio();
    final settings = AppSettingsService();
    addTearDown(radio.dispose);
    addTearDown(settings.dispose);
    radio.channels.add(Channel.fromHex(3, '#test', Channel.publicChannelPsk));
    await settings.updateSettings(settings.settings.copyWith(
      quickActions: _visibleActions(const [
        QuickActionItem(QuickAction.channelMessage1,
          visible: true, name: 'Check in', text: 'Here', channelName: '#test'),
      ]),
    ));

    try {
      await _open(tester, radio, settings);
      final l10n = AppLocalizations.of(tester.element(find.byType(AlertDialog)));
      await tester.tap(find.text('Check in'));
      await tester.pumpAndSettle();
      expect(radio.sent, [(3, 'Here', true)]);

      radio.channels.add(Channel.fromHex(5, '#test', Channel.publicChannelPsk));
      await tester.tap(find.text('Check in'));
      await tester.pumpAndSettle();
      expect(find.text(l10n.quickActions_channelMissing), findsOneWidget);
      expect(radio.sent, hasLength(1));
      await tester.tap(find.text(l10n.common_close));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });
}
