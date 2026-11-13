import 'dart:async';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/l10n/contact_localization.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/models/path_selection.dart';
import 'package:meshcore_open/services/additional_identity_inbox.dart';
import 'package:meshcore_open/services/additional_identity_vault.dart';
import 'package:meshcore_open/services/path_history_service.dart';
import 'package:meshcore_open/services/storage_service.dart';
import 'package:meshcore_open/storage/node_state.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:meshcore_open/widgets/repeater_login_dialog.dart';
import 'package:meshcore_open/widgets/room_login_dialog.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _password = 'SYNTHETIC_PASSWORD';

class _NoPreferenceDirectory extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async =>
      throw MissingPluginException('Synthetic login preferences');
}

class _Activity extends ValueNotifier<int> {
  _Activity() : super(0);
  bool get observed => hasListeners;
}

class _Radio extends ChangeNotifier implements MeshCoreConnector {
  _Radio(int type, {this.additionalIdentityInbox}) : current = Contact(
    publicKey: Uint8List.fromList(List.filled(32, 0x71)),
    name: 'Synthetic managed node',
    type: type,
    pathLength: 1,
    path: Uint8List.fromList([0xa1, 0xb2]),
    pathHashWidth: 2,
    pathOverride: 1,
    pathOverrideBytes: Uint8List.fromList([0xa1, 0xb2]),
    lastSeen: DateTime.utc(2026, 1, 1),
  );

  Contact current;
  @override
  final AdditionalIdentityInbox? additionalIdentityInbox;
  final additionalLogins = <(String, String, String)>[];
  final additionalLoginResults = <bool>[];

  @override
  String get selfName => 'Radio node';

  @override
  String get selfPublicKeyHex => '11' * 32;

  @override
  Future<bool> loginToRoomAsAdditionalIdentity(
    String identityKey,
    Contact room,
    String password,
  ) async {
    additionalLogins.add((identityKey, room.publicKeyHex, password));
    return additionalLoginResults.removeAt(0);
  }

  final writes = <Uint8List>[];
  final modeChanges = <int?>[];
  final outcomes = <bool>[];
  final incoming = StreamController<Uint8List>.broadcast(sync: true);
  @override
  final _Activity repeaterActivity = _Activity();
  @override
  bool get isConnected => true;
  @override
  List<Contact> get contacts => [current];
  @override
  List<Contact> get allContacts => [current];
  @override
  int get pathHashByteWidth => 2;
  @override
  List<Never> get directRepeaters => const [];
  @override
  Stream<Uint8List> get receivedFrames => incoming.stream;

  @override
  Future<void> setPathOverride(Contact contact, {
    int? pathLen, Uint8List? pathBytes,
  }) async {
    expect(contact.publicKeyHex, current.publicKeyHex);
    modeChanges.add(pathLen);
    current = current.copyWith(
      pathOverride: pathLen,
      pathOverrideBytes: pathBytes,
      clearPathOverride: pathLen == null,
    );
    notifyListeners();
  }

  @override
  Future<PathSelection> preparePathForContactSend(Contact contact) async {
    expect(contact.publicKeyHex, current.publicKeyHex);
    return const PathSelection(
      pathBytes: [0xa1, 0xb2], hopCount: 1, useFlood: false,
    );
  }

  @override
  Future<void> sendContactFrame(Contact contact, Uint8List frame, {
    required bool useFlood,
    bool Function()? canSend,
    VoidCallback? onSending,
  }) async {
    expect(contact.publicKeyHex, current.publicKeyHex);
    expect(useFlood, isFalse);
    onSending?.call();
    writes.add(Uint8List.fromList(frame));
  }

  @override
  int calculateTimeout({required int pathLength, int messageBytes = 100,
    String? contactKey, int? deviceTimeoutMs}) => 500;

  @override
  void recordRepeaterPathResult(Contact contact, PathSelection selection,
      bool success, int? tripTimeMs) => outcomes.add(success);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected login operation: ${invocation.memberName}');

  @override
  void dispose() {
    repeaterActivity.dispose();
    additionalIdentityInbox?.dispose();
    unawaited(incoming.close());
    super.dispose();
  }
}

class _History extends ChangeNotifier implements PathHistoryService {
  @override
  List<Never> getRecentPaths(String contactPubKeyHex) => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #getFloodStats) {
      return null;
    }
    throw StateError('Unexpected login history operation: ${invocation.memberName}');
  }
}

Future<void> _withLogin(WidgetTester tester, String locale, int type,
    Future<void> Function(_Radio, AppLocalizations, List<(String, bool)>) run, {
  Size size = const Size(960, 1100),
  double textScale = 1,
  AdditionalIdentityInbox? inbox,
  ValueChanged<String>? onAdditionalLogin,
}) async {
  final radio = _Radio(type, additionalIdentityInbox: inbox);
  final history = _History();
  final logins = <(String, bool)>[];
  await StorageService().saveRepeaterPassword(radio.current.publicKeyHex, _password);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  try {
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<MeshCoreConnector>.value(value: radio),
        ChangeNotifierProvider<PathHistoryService>.value(value: history),
      ],
      child: MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(body: Builder(builder: (context) => TextButton(
          onPressed: () => showDialog<void>(context: context, builder: (_) {
            void onLogin(String password, bool admin) => logins.add((password, admin));
            return type == advTypeRoom
                ? RoomLoginDialog(
                    room: radio.current,
                    onLogin: onLogin,
                    onAdditionalLogin: onAdditionalLogin,
                  )
                : RepeaterLoginDialog(repeater: radio.current, onLogin: onLogin);
          }),
          child: const Text('Open synthetic login'),
        ))),
      ),
    ));
    await tester.tap(find.text('Open synthetic login'));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(tester.element(find.byType(AlertDialog)));
    await run(radio, l10n, logins);
    expect(tester.takeException(), isNull);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(radio.repeaterActivity.observed, isFalse);
    expect(radio.incoming.hasListener, isFalse);
    history.dispose();
    radio.dispose();
  }
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
}

Future<void> _finishLogin(WidgetTester tester, _Radio radio,
    List<(String, bool)> logins) async {
  // Stream cancellation and the mock password write may complete through the
  // real event loop. Pump without advancing the retry clock until the actual
  // onLogin callback arrives; the loading spinner cannot settle before that.
  final elapsed = Stopwatch()..start();
  while (logins.isEmpty) {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    if (elapsed.elapsed > const Duration(seconds: 3)) {
      fail('Login callback did not complete: outcomes=${radio.outcomes}, '
          'listener=${radio.incoming.hasListener}, writes=${radio.writes.length}');
    }
  }
  await tester.pumpAndSettle();
}

void main() {
  late PathProviderPlatform previousPaths;
  setUp(() async {
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _NoPreferenceDirectory();
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
    expect(NodeState.usesDatabase, isFalse);
  });
  tearDown(() {
    PrefsManager.reset();
    PathProviderPlatform.instance = previousPaths;
  });

  for (final locale in ['en', 'ru']) {
    for (final type in [advTypeRepeater, advTypeRoom]) {
      testWidgets('login routing is visible and modes match ($locale, type=$type)', (tester) async {
        await _withLogin(tester, locale, type, (radio, l10n, logins) async {
          expect(find.byType(ExpansionTile), findsNothing);
          expect(find.text(l10n.login_advanced), findsNothing);
          expect(find.text(l10n.login_routing), findsOneWidget);
          expect(find.text(radio.current.pathLabel(l10n, pathHashByteWidth: 2)), findsOneWidget);
          expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, _password);
          final menu = find.byWidgetPredicate((w) =>
              w is PopupMenuButton<String> && w.tooltip == l10n.login_routingMode);
          await _reveal(tester, menu);
          await tester.tap(menu);
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(PopupMenuItem<String>, l10n.login_forceFloodMode));
          await tester.pumpAndSettle();
          expect(radio.modeChanges, [-1]);
          expect(find.text(radio.current.pathLabel(l10n, pathHashByteWidth: 2)), findsOneWidget);
          await tester.tap(menu);
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(PopupMenuItem<String>, l10n.login_autoUseSavedPath));
          await tester.pumpAndSettle();
          expect(radio.modeChanges, [-1, null]);
          expect(radio.current.path, [0xa1, 0xb2]);
          expect(find.text(radio.current.pathLabel(l10n, pathHashByteWidth: 2)), findsOneWidget);

          final manage = find.widgetWithText(TextButton, l10n.login_managePaths);
          await _reveal(tester, manage);
          await tester.tap(manage);
          await tester.pumpAndSettle();
          final sheet = find.byType(BottomSheet);
          expect(sheet, findsOneWidget);
          expect(find.descendant(of: sheet,
              matching: find.text(l10n.routing_title)), findsOneWidget);
          expect(find.descendant(of: sheet,
              matching: find.text(l10n.chat_noPathHistoryYet)), findsOneWidget);
          expect(radio.repeaterActivity.observed, isTrue);
          // The bottom sheet has no app-bar Back button. Dismiss its barrier,
          // leaving the login dialog underneath intact.
          await tester.tapAt(const Offset(10, 10));
          await tester.pumpAndSettle();
          expect(radio.repeaterActivity.observed, isFalse);
          expect(find.byType(AlertDialog), findsOneWidget);
          expect(radio.writes, isEmpty);
          expect(logins, isEmpty);
          expect(await StorageService().getRepeaterPassword(radio.current.publicKeyHex), _password);
        });
      });
    }

    testWidgets('room routing remains reachable on a phone ($locale)', (tester) async {
      await _withLogin(tester, locale, advTypeRoom, (radio, l10n, logins) async {
        final manage = find.widgetWithText(TextButton, l10n.login_managePaths);
        await _reveal(tester, manage);
        expect(find.byType(ExpansionTile), findsNothing);
        expect(find.text(l10n.login_routing), findsOneWidget);
        expect(radio.writes, isEmpty);
        expect(logins, isEmpty);
      }, size: const Size(360, 740), textScale: 1.3);
    });
  }

  testWidgets('room login sends only as the selected additional key', (tester) async {
    final entry = (await tester.runAsync(() async {
      const seed = '9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60';
      final expanded = Uint8List.fromList((await Sha512().hash(hex.decode(seed))).bytes);
      expanded[0] &= 248;
      expanded[31] = (expanded[31] & 63) | 64;
      return AdditionalIdentityEntry.parse('Room identity', hex.encode(expanded));
    }))!;
    final key = entry.identity.publicKeyHex;
    final loginsAsAdditional = <String>[];
    await _withLogin(tester, 'en', advTypeRoom, (radio, l10n, logins) async {
      final sender = find.widgetWithText(ListTile, l10n.channels_senderNameLabel);
      expect(find.descendant(of: sender, matching: find.text('Radio node')), findsOneWidget);
      await tester.tap(sender);
      await tester.pumpAndSettle();
      final option = find.widgetWithText(ListTile, entry.name);
      expect(find.descendant(of: option, matching: find.text(key)), findsOneWidget);
      await tester.tap(option);
      await tester.pumpAndSettle();

      expect(find.descendant(of: sender, matching: find.text(entry.name)), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsNothing);
      const password = 'ROOM_PASS';
      await tester.enterText(find.byType(TextField), password);
      final login = find.widgetWithText(FilledButton, l10n.login_login);
      radio.additionalLoginResults.addAll([false, true]);
      await tester.tap(login);
      await tester.pumpAndSettle();
      expect(find.byType(RoomLoginDialog), findsOneWidget);
      expect(find.text(l10n.extraKeys_roomLoginFailed), findsOneWidget);
      expect(loginsAsAdditional, isEmpty);
      expect(radio.writes, isEmpty);

      await tester.tap(login);
      await tester.pumpAndSettle();
      expect(find.byType(RoomLoginDialog), findsNothing);
      expect(loginsAsAdditional, [key]);
      expect(radio.additionalLogins, [
        (key, radio.current.publicKeyHex, password),
        (key, radio.current.publicKeyHex, password),
      ]);
      expect(logins, isEmpty);
      expect(radio.writes, isEmpty);
      expect(await StorageService().getRepeaterPassword(radio.current.publicKeyHex), _password);
    },
      inbox: AdditionalIdentityInbox()..unlock([entry]),
      onAdditionalLogin: loginsAsAdditional.add,
    );
  });

  for (final admin in [false, true]) {
    testWidgets('room login keeps password policy and access callback (admin=$admin)', (tester) async {
      await _withLogin(tester, 'ru', advTypeRoom, (radio, l10n, logins) async {
        const password = 'NEW_SYNTHETIC';
        await tester.enterText(find.byType(TextField), password);
        if (admin) {
          await tester.tap(find.byType(CheckboxListTile));
          await tester.pump();
        }
        await tester.tap(find.widgetWithText(FilledButton, l10n.login_login));
        await tester.pump();
        expect(radio.writes, [<int>[
          cmdSendLogin, ...radio.current.publicKey, ...password.codeUnits, 0,
        ]]);
        expect(radio.incoming.hasListener, isTrue);
        radio.incoming.add(Uint8List.fromList([
          pushCodeLoginSuccess, admin ? 1 : 0, ...radio.current.publicKey.take(6),
        ]));
        await _finishLogin(tester, radio, logins);
        expect(find.byType(RoomLoginDialog), findsNothing);
        expect(logins, [(password, admin)]);
        expect(radio.outcomes, [true]);
        expect(await StorageService().getRepeaterPassword(radio.current.publicKeyHex),
            admin ? isNull : password);
      });
    });
  }
}
