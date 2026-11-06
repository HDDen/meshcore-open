import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/helpers/cli_history_writes.dart';
import 'package:meshcore_open/helpers/ui_notification_batcher.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/models/path_selection.dart';
import 'package:meshcore_open/screens/repeater_cli_screen.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:meshcore_open/storage/message_history_database.dart';
import 'package:meshcore_open/storage/message_history_storage.dart';
import 'package:meshcore_open/storage/repeater_cli_store.dart';
import 'package:meshcore_open/widgets/radio_disconnected_banner.dart';
import 'package:provider/provider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _reply = 'SYNTHETIC_REPEATER_REPLY';

class _NoPreferenceDirectory extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async =>
      throw MissingPluginException('Synthetic repeater CLI preferences');
}

// Настоящие экран, parser и RepeaterCommandService. Подменены только транспорт
// и входящий stream: тест не подключает радио, не читает реальную историю.
class _Connector extends MeshCoreConnector {
  final repeater = Contact(
    publicKey: Uint8List.fromList(List.generate(32, (index) => index + 1)),
    name: 'Synthetic relay',
    type: advTypeRepeater,
    pathLength: -1,
    path: Uint8List(0),
    lastSeen: DateTime.utc(2026, 10, 28),
  );
  final incoming = StreamController<Uint8List>.broadcast(sync: true);
  final writes = <Uint8List>[];
  bool replyImmediately = true;
  String nodeKey = 'ab' * 32;
  int timeoutMs = 1000;
  bool connected = true;

  @override
  bool get isConnected => connected;
  @override
  String get selfPublicKeyHex => nodeKey;
  @override
  List<Contact> get contacts => [repeater];
  @override
  Stream<Uint8List> get receivedFrames => incoming.stream;

  @override
  Future<PathSelection> preparePathForContactSend(Contact contact) async =>
      const PathSelection(pathBytes: [], hopCount: -1, useFlood: true);

  @override
  int calculateTimeout({
    required int pathLength,
    int messageBytes = 100,
    String? contactKey,
    int? deviceTimeoutMs,
  }) => timeoutMs;

  @override
  Future<void> sendContactFrame(Contact contact, Uint8List frame, {
    required bool useFlood,
    bool Function()? canSend,
    VoidCallback? onSending,
  }) async {
    if (canSend?.call() == false) return;
    onSending?.call();
    writes.add(Uint8List.fromList(frame));
    if (replyImmediately) {
      answer(_reply);
    }
  }

  String get sentText => utf8.decode(writes.last.sublist(13).takeWhile((byte) => byte != 0).toList());

  void answer(String text, {Uint8List? sender, Uint8List? request}) {
    final original = request == null ? sentText : utf8.decode(request.sublist(13).takeWhile((byte) => byte != 0).toList());
    final prefix = RegExp(r'^[0-9A-F]{2}\|').hasMatch(original) ? original.substring(0, 3) : '';
    // Literal legacy contact response: code/key prefix/path/type/time/text/NUL.
    incoming.add(Uint8List.fromList([
      respCodeContactMsgRecv, ...(sender ?? repeater.publicKey).take(6),
      0, txtTypeCliData, 0, 0, 0, 0, ...utf8.encode('$prefix$text'), 0,
    ]));
  }

  @override
  void dispose() {
    unawaited(incoming.close());
    super.dispose();
  }
}

void main() {
  late _Connector connector;
  late PathProviderPlatform previousPaths;
  setUp(() async {
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _NoPreferenceDirectory();
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
    await MessageHistoryStorage.instance.resetForTesting();
    await MessageHistoryStorage.instance.initializeAndMigrate(
      databaseFactory: () => MessageHistoryDatabase.withExecutor(NativeDatabase.memory()));
    connector = _Connector();
  });
  tearDown(() async {
    connector.dispose();
    await MessageHistoryStorage.instance.resetForTesting();
    PrefsManager.reset();
    PathProviderPlatform.instance = previousPaths;
  });

  // Native SQLite needs the real event loop. Flutter's fake clock alone
  // cannot complete it; each barrier also lets the UI enqueue its next write.
  Future<void> drainSql(WidgetTester tester) async {
    for (var phase = 0; phase < 4; phase++) {
      var completed = false;
      unawaited(CliHistoryWrites.ordered(() async { completed = true; }));
      final elapsed = Stopwatch()..start();
      while (!completed) {
        await tester.pump();
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
        if (elapsed.elapsed > const Duration(seconds: 3)) {
          fail('CLI SQLite queue did not complete in the real event loop');
        }
      }
      await tester.pump();
    }
  }

  Future<void> settle(WidgetTester tester) async {
    await drainSql(tester);
    await tester.pumpAndSettle();
  }

  Future<AppLocalizations> show(WidgetTester tester, String locale, {double textScale = 1}) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ChangeNotifierProvider<MeshCoreConnector>.value(
      value: connector,
      child: MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: RepeaterCliScreen(repeater: connector.repeater, password: ''),
      ),
    ));
    await drainSql(tester);
    await tester.pump(const Duration(milliseconds: 150));
    return AppLocalizations.of(tester.element(find.byType(RepeaterCliScreen)));
  }

  Future<void> settleReply(WidgetTester tester) async {
    await drainSql(tester);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 250));
    await drainSql(tester);
  }

  Future<void> send(WidgetTester tester, AppLocalizations l10n, {String command = 'ver'}) async {
    expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send)).onPressed, isNotNull,
      reason: 'SQLite history must finish loading before sending');
    await tester.enterText(find.byType(TextField), command);
    await tester.tap(find.byTooltip(l10n.repeater_cliSend));
    await settleReply(tester);
  }

  Future<List<Map<String, Object>>> sqlSnapshot(WidgetTester tester) async {
    final rows = await tester.runAsync(
      () => RepeaterCliStore().load(
        connector.selfPublicKeyHex,
        connector.repeater.publicKeyHex,
      ),
    );
    expect(rows, isNotNull);
    return [
      for (final row in rows!) {
        'id': row.id,
        'node': row.nodeKey,
        'repeater': row.repeaterKey,
        'nodeName': row.nodeName,
        'repeaterName': row.repeaterName,
        'at': row.createdAt.millisecondsSinceEpoch,
        'type': row.type,
        'text': row.text,
      },
    ];
  }

  Future<void> revealScrollEnd(
    WidgetTester tester,
    Finder scrollView,
    Finder lastText,
  ) async {
    expect(scrollView, findsOneWidget);
    final scrollable = find.descendant(
      of: scrollView,
      matching: find.byType(Scrollable),
    );
    expect(scrollable, findsOneWidget);
    // Align the text itself, not trailing padding that may be taller than
    // the viewport. Reaching maxScrollExtent can scroll the text past it.
    await Scrollable.ensureVisible(tester.element(lastText), alignment: 1);
    await tester.pump();
    final viewport = tester.getRect(scrollView);
    final text = tester.getRect(lastText);
    final style = tester.widget<Text>(lastText).style;
    final lineHeight = MediaQuery.textScalerOf(tester.element(lastText))
        .scale(style?.fontSize ?? 14) * (style?.height ?? 1);
    expect(viewport.height, greaterThanOrEqualTo(lineHeight),
        reason: 'The scroll viewport must fit a full line, not just a sliver');
    expect(text.bottom, lessThanOrEqualTo(viewport.bottom + 1));
    expect(text.bottom, greaterThan(viewport.top));
  }

  for (final locale in ['en', 'ru']) {
    for (final withHistory in [false, true]) {
      for (final layout in [
        (name: 'phone', size: const Size(320, 568), keyboard: 0.0),
        (name: 'landscape', size: const Size(568, 360), keyboard: 0.0),
        (name: 'keyboard', size: const Size(1000, 1400), keyboard: 1040.0),
      ]) {
        testWidgets(
          'U11b5: warning and output scroll without displacing input '
          '($locale, ${layout.name}, scale=2, history=$withHistory)',
          (tester) async {
            addTearDown(tester.view.resetViewInsets);
            try {
              final l10n = await show(tester, locale, textScale: 2);
              if (withHistory) {
                await send(tester, l10n);
              }
              final stored = await sqlSnapshot(tester);
              await tester.enterText(find.byType(TextField), 'get name');
              tester.view.physicalSize = layout.size;
              tester.view.viewInsets = FakeViewPadding(bottom: layout.keyboard);
              connector.connected = false;
              connector.notifyListeners();
              await settleReply(tester);
              expect(tester.takeException(), isNull);

              final field = find.byType(TextField);
              final sendButton = find.widgetWithIcon(IconButton, Icons.send);
              final availableBottom = layout.size.height - layout.keyboard;
              expect(tester.getRect(field).top, greaterThanOrEqualTo(0));
              expect(tester.getRect(field).bottom,
                  lessThanOrEqualTo(availableBottom));
              expect(tester.getRect(sendButton).bottom,
                  lessThanOrEqualTo(availableBottom));
              expect(tester.widget<IconButton>(sendButton).onPressed, isNull);
              expect(tester.widget<TextField>(field).controller!.text, 'get name');

              // Read the end of the warning through its real scroll viewport;
              // merely finding the text would not catch clipping.
              final warningScroll = find.ancestor(
                of: find.byType(RadioDisconnectedBanner),
                matching: find.byType(SingleChildScrollView),
              ).first;
              final identity = find.text(
                '${connector.repeater.name} · ${connector.selfPublicKeyHex}',
              );
              expect(identity, findsOneWidget);
              expect(tester.widget<Text>(identity).maxLines, isNull);
              await revealScrollEnd(tester, warningScroll,
                  find.text(l10n.repeater_radioDisconnectedHint));
              if (withHistory) {
                final output = find.byType(ListView);
                expect(output, findsOneWidget);
                expect(tester.getSize(output).height, greaterThan(0));
                // Resizing can leave a lazy list away from its last row.
                // Build/reveal that row before asking for its element.
                tester.widget<ListView>(output).controller!.jumpTo(0);
                await tester.pump();
                await tester.scrollUntilVisible(
                  find.text(_reply),
                  80,
                  scrollable: find.descendant(
                    of: output,
                    matching: find.byType(Scrollable),
                  ).first,
                  maxScrolls: 30,
                );
                expect(find.text(_reply), findsOneWidget);
                await Scrollable.ensureVisible(
                  tester.element(find.text(_reply)),
                  alignment: 1,
                );
                await tester.pump();
                final transcript = tester.getRect(output);
                final reply = tester.getRect(find.text(_reply));
                expect(reply.bottom, lessThanOrEqualTo(transcript.bottom + 1));
                expect(reply.bottom, greaterThan(transcript.top));
              } else {
                final emptyHint = find.text(l10n.repeater_typeCommandOrUseQuick);
                final emptyScroll = find.ancestor(
                  of: emptyHint,
                  matching: find.byType(SingleChildScrollView),
                ).first;
                await revealScrollEnd(tester, emptyScroll, emptyHint);
              }
              expect(connector.writes, hasLength(withHistory ? 1 : 0));
              expect(await sqlSnapshot(tester), stored);

              connector.connected = true;
              connector.notifyListeners();
              await settleReply(tester);
              expect(find.text(l10n.repeater_radioDisconnected), findsNothing);
              expect(tester.widget<TextField>(field).controller!.text, 'get name');
              expect(connector.writes, hasLength(withHistory ? 1 : 0));
              expect(await sqlSnapshot(tester), stored);
              expect(sendButton.hitTestable(), findsOneWidget);
              await tester.tap(sendButton);
              await settleReply(tester);
              expect(connector.writes, hasLength(withHistory ? 2 : 1));
              expect(connector.writes.last.first, cmdSendTxtMsg);
              expect(connector.sentText, endsWith('|get name'));
              expect(await sqlSnapshot(tester), hasLength(stored.length + 2));
              expect(tester.takeException(), isNull);
            } finally {
              await tester.pumpWidget(const SizedBox.shrink());
              await drainSql(tester);
            }
          },
        );
      }
    }
  }

  for (final locale in ['en', 'ru']) {
    for (final withHistory in [false, true]) {
      testWidgets('U11b5 baseline: disconnection preserves draft and SQL history ($locale, history=$withHistory)', (tester) async {
        try {
          final l10n = await show(tester, locale);
          if (withHistory) {
            await send(tester, l10n);
          }
          final stored = await sqlSnapshot(tester);
          expect(stored, withHistory ? isNotEmpty : isEmpty);
          final sendButton = find.widgetWithIcon(IconButton, Icons.send);
          expect(tester.widget<IconButton>(sendButton).onPressed, isNotNull);
          expect(find.text(l10n.repeater_radioDisconnected), findsNothing);
          await tester.enterText(find.byType(TextField), 'get name');

          connector.connected = false;
          connector.notifyListeners();
          await settleReply(tester);
          expect(find.text(l10n.repeater_radioDisconnected), findsOneWidget);
          expect(find.text(l10n.repeater_radioDisconnectedHint), findsOneWidget);
          expect(tester.widget<IconButton>(sendButton).onPressed, isNull);
          expect(
            tester.widget<TextField>(find.byType(TextField)).controller!.text,
            'get name',
          );
          expect(
            find.text(withHistory ? _reply : l10n.repeater_noCommandsSent),
            findsOneWidget,
          );
          // The keyboard Send action must obey the same connection guard.
          await tester.testTextInput.receiveAction(TextInputAction.send);
          await settleReply(tester);
          expect(connector.writes, hasLength(withHistory ? 1 : 0));
          expect(await sqlSnapshot(tester), stored);

          connector.connected = true;
          connector.notifyListeners();
          await settleReply(tester);
          expect(find.text(l10n.repeater_radioDisconnected), findsNothing);
          expect(tester.widget<IconButton>(sendButton).onPressed, isNotNull);
          expect(
            tester.widget<TextField>(find.byType(TextField)).controller!.text,
            'get name',
          );
          expect(connector.writes, hasLength(withHistory ? 1 : 0));
          expect(await sqlSnapshot(tester), stored);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await drainSql(tester);
        }
      });
    }
  }

  for (final locale in ['ru', 'en']) {
    testWidgets('baseline: clear is confirmed locally and does not send a radio command ($locale)', (tester) async {
      final l10n = await show(tester, locale);
      await send(tester, l10n);
      expect(connector.writes.single.first, cmdSendTxtMsg);
      expect(connector.sentText, '00|ver');
      expect(find.text(_reply), findsOneWidget);

      await tester.tap(find.byTooltip(l10n.repeater_clearHistory));
      await settle(tester);
      expect(find.text(l10n.repeater_cliClearHistoryConfirm), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, l10n.common_cancel));
      await settle(tester);
      expect(find.text(_reply), findsOneWidget);

      await tester.tap(find.byTooltip(l10n.repeater_clearHistory));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, l10n.common_clear));
      await settle(tester);
      expect(find.text(_reply), findsNothing);
      expect(find.text(l10n.repeater_noCommandsSent), findsOneWidget);
      expect(connector.writes, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final locale in ['ru', 'en']) {
    for (final textScale in [1.0, 1.5]) {
      testWidgets(
        'command recall and menu fit without another transmission ($locale, scale=$textScale)',
        (tester) async {
          final l10n = await show(tester, locale, textScale: textScale);
          await send(tester, l10n);
          await tester.tap(find.byTooltip(l10n.repeater_previousCommand));
          await tester.pump();
          expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'ver');
          await tester.tap(find.byTooltip(l10n.repeater_nextCommand));
          await tester.pump();
          expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '');

          await tester.tap(find.byType(PopupMenuButton<String>));
          await settle(tester);
          expect(tester.takeException(), isNull);
          expect(find.widgetWithText(PopupMenuItem<String>, l10n.repeater_debugNextCommand), findsOneWidget);
          expect(find.widgetWithText(PopupMenuItem<String>, l10n.repeater_cliCopyTranscript), findsOneWidget);
          expect(find.widgetWithText(PopupMenuItem<String>, l10n.repeater_cliShareTranscript), findsOneWidget);
          final items = tester.widgetList<PopupMenuItem<String>>(find.byType(PopupMenuItem<String>)).toList();
          final debugIndex = items.indexWhere((item) => item.value == 'debug');
          expect(items[debugIndex + 1].value, 'clear');
          expect(connector.writes, hasLength(1));
          await tester.tapAt(const Offset(8, 850));
          await settle(tester);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  testWidgets('baseline: a reply from another repeater cannot finish this console command', (tester) async {
    final l10n = await show(tester, 'en');
    connector.replyImmediately = false;
    await send(tester, l10n);
    connector.answer('OTHER_RELAY_REPLY', sender: Uint8List.fromList(List.filled(32, 200)));
    await tester.pump();
    expect(find.text('OTHER_RELAY_REPLY'), findsNothing);
    connector.answer(_reply);
    await settleReply(tester);
    expect(find.text(_reply), findsOneWidget);
    expect(connector.writes, hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('transcript reloads after closing the screen and menu clear deletes only local history', (tester) async {
    var l10n = await show(tester, 'en');
    await send(tester, l10n);
    await tester.pumpWidget(const SizedBox.shrink());
    l10n = await show(tester, 'en');
    await settleReply(tester);
    expect(find.text(_reply), findsOneWidget);
    expect(connector.writes, hasLength(1));
    await tester.tap(find.byType(PopupMenuButton<String>));
    await settle(tester);
    await tester.tap(find.byWidgetPredicate((widget) => widget is PopupMenuItem<String> && widget.value == 'clear'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, l10n.common_clear));
    await settle(tester);
    final stored = await tester.runAsync(() => RepeaterCliStore().load(
      connector.selfPublicKeyHex, connector.repeater.publicKeyHex));
    expect(stored, isEmpty);
    expect(connector.writes, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('local clear preserves region load mode, raw indentation and its blank terminator', (tester) async {
    final l10n = await show(tester, 'en');
    await send(tester, l10n, command: 'region load');
    await tester.tap(find.byTooltip(l10n.repeater_clearHistory));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, l10n.common_clear));
    await settle(tester);
    await send(tester, l10n, command: '  Synthetic-region');
    expect(connector.sentText, '  Synthetic-region');
    await send(tester, l10n, command: '');
    expect(connector.sentText, '');
    expect(connector.writes, hasLength(3));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a node change disables sending through the old console instance', (tester) async {
    final l10n = await show(tester, 'en');
    await send(tester, l10n);
    connector.nodeKey = 'cd' * 32;
    connector.notifyListeners();
    // Connector delivers UI notifications through its existing batching window.
    await tester.pump(UiNotificationBatcher.minimum);
    expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send)).onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'board');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    expect(connector.writes, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a pending reply is persisted after closing the console without using its dead context', (tester) async {
    final l10n = await show(tester, 'en');
    connector.replyImmediately = false;
    await send(tester, l10n);
    await tester.pumpWidget(const SizedBox.shrink());
    connector.answer(_reply);
    await settleReply(tester);
    final stored = await tester.runAsync(() => RepeaterCliStore().load(
      connector.selfPublicKeyHex, connector.repeater.publicKeyHex));
    expect(stored!.map((entry) => entry.text), ['ver', _reply]);
    expect(connector.writes, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed first SQL write leaves the draft and does not send to the node', (tester) async {
    final l10n = await show(tester, 'en');
    await tester.runAsync(MessageHistoryStorage.instance.resetForTesting);
    await tester.enterText(find.byType(TextField), 'ver');
    await tester.tap(find.byTooltip(l10n.repeater_cliSend));
    await settle(tester);
    expect(connector.writes, isEmpty);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'ver');
    expect(find.text(l10n.companionCli_historyError), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('reopening a pending console keeps one service and distinguishes the two replies', (tester) async {
    connector.replyImmediately = false;
    connector.timeoutMs = 3000;
    var l10n = await show(tester, 'en');
    await send(tester, l10n);
    final first = connector.writes.single;
    await tester.pumpWidget(const SizedBox.shrink());
    l10n = await show(tester, 'en');
    await send(tester, l10n, command: 'board');
    final second = connector.writes.last;
    expect(first.sublist(13, 16), '00|'.codeUnits);
    expect(second.sublist(13, 16), '01|'.codeUnits);
    connector.answer('FIRST_REPLY', request: first);
    await settleReply(tester);
    expect(find.text('FIRST_REPLY'), findsOneWidget);
    expect(find.text('SECOND_REPLY'), findsNothing);
    connector.answer('SECOND_REPLY', request: second);
    await settleReply(tester);
    expect(find.text('SECOND_REPLY'), findsOneWidget);
    final stored = await tester.runAsync(() => RepeaterCliStore().load(
      connector.selfPublicKeyHex, connector.repeater.publicKeyHex));
    expect(stored!.map((entry) => entry.text), ['ver', 'board', 'FIRST_REPLY', 'SECOND_REPLY']);
    expect(connector.writes, hasLength(2));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
