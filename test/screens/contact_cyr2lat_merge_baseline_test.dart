import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/helpers/contact_history_candidates.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/app_settings.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/models/message.dart';
import 'package:meshcore_open/screens/chat_screen.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/services/chat_text_scale_service.dart';
import 'package:provider/provider.dart';

import '../support/wrapping_label_expectations.dart';

const _alpha = 'synthetic-a';
const _beta = 'synthetic-b';
const _loads = <Symbol>{
  #ensureContactMcmpSettingLoaded,
  #ensureContactMCOtxtSettingLoaded,
  #ensureContactSmazSettingLoaded,
  #ensureContactCyr2LatSettingLoaded,
  #ensureContactSendingDelaySettingLoaded,
  #ensureContactQuickAnswerIdsLoaded,
};

class _Settings extends AppSettingsService {
  _Settings({String alpha = 'Alpha', String beta = 'Beta'}) : value = AppSettings(
    hideRadioStatsButton: true,
    canvasActive: false,
    cyr2latProfiles: [
      Cyr2LatProfile(id: _alpha, name: alpha, charMap: const {'я': 'ya'}),
      Cyr2LatProfile(id: _beta, name: beta, charMap: const {'я': 'ja'}),
    ],
  );

  final AppSettings value;

  @override
  AppSettings get settings => value;
}

// No real connector, transport, DB or preference service is constructed.
// Only empty-chat reads and the explicitly tested UI callbacks are allowed.
class _Radio extends ChangeNotifier implements MeshCoreConnector {
  _Radio(int type) : target = Contact(
    publicKey: Uint8List.fromList(List.filled(32, 0xab)),
    name: 'Synthetic',
    type: type,
    pathLength: 0,
    path: Uint8List(0),
    lastSeen: DateTime.utc(2026, 1, 1),
  );

  final Contact target;
  final failures = StreamController<void>.broadcast();
  final profileWrites = <String?>[];
  final compressionWrites = <(String, bool)>[];
  final flagWrites = <(bool?, bool?, bool?)>[];
  final loads = <Symbol>[];
  final activeContacts = <String?>[];
  final compression = <String, bool>{
    'mcmp': false, 'mcotxt': false, 'smaz': false, 'cyr2lat': true,
  };
  String? profile = _alpha;
  int indicatorLeases = 0;

  void _key(Object? key) => expect(key, target.publicKeyHex);

  @override
  Future<void> setContactFlags(Contact contact, {
    bool? isFavorite, bool? teleBase, bool? teleLoc, bool? teleEnv,
  }) async {
    _key(contact.publicKeyHex);
    expect(isFavorite, isNull);
    flagWrites.add((teleBase, teleLoc, teleEnv));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final member = invocation.memberName;
    final args = invocation.positionalArguments;
    if (invocation.isGetter) {
      switch (member) {
        case #contacts:
          return <Contact>[target];
        case #uiRevision:
          return 0;
        case #mcmpSigningFailures:
          return failures.stream;
        case #isOfflineMode:
        case #isConnected:
        case #isLoadingContacts:
        case #isSyncingChannels:
        case #isShowingQueuedMessageSyncProgress:
        case #supportsCompanionRadioStats:
          return false;
      }
    }
    if (member == #getMessages || member == #contactHistoryCandidates) {
      _key((args.single as Contact).publicKeyHex);
      return member == #getMessages
          ? const <Message>[]
          : Future<List<ContactHistoryCandidate>>.value(const []);
    }
    if (member == #setActiveContact) {
      final key = args.single as String?;
      if (key != null) {
        _key(key);
      }
      activeContacts.add(key);
      return null;
    }
    if (member == #acquireRadioStatsPolling) {
      // The indicator's existing lease lifecycle must balance at teardown;
      // no timer or actual radio polling runs in this fake.
      indicatorLeases++;
      return null;
    }
    if (member == #releaseRadioStatsPolling) {
      indicatorLeases--;
      return null;
    }
    if (member == #prepareContactOutboundText) {
      _key((args.first as Contact).publicKeyHex);
      expect(args[1], isEmpty); // Only the empty composer's byte counter.
      return '';
    }
    if (_loads.contains(member)) {
      _key(args.single);
      loads.add(member);
      return null;
    }
    const reads = <Symbol, String>{
      #isContactMcmpEnabled: 'mcmp',
      #isContactMCOtxtEnabled: 'mcotxt',
      #isContactSmazEnabled: 'smaz',
      #isContactCyr2LatEnabled: 'cyr2lat',
    };
    if (reads.containsKey(member)) {
      _key(args.single);
      return compression[reads[member]]!;
    }
    const setters = <Symbol, String>{
      #setContactMcmpEnabled: 'mcmp',
      #setContactMCOtxtEnabled: 'mcotxt',
      #setContactSmazEnabled: 'smaz',
      #setContactCyr2LatEnabled: 'cyr2lat',
    };
    if (setters.containsKey(member)) {
      _key(args.first);
      final name = setters[member]!;
      final value = args[1] as bool;
      compression[name] = value;
      compressionWrites.add((name, value));
      return Future<void>.value();
    }
    if (member == #setContactCyr2LatProfileId) {
      _key(args.first);
      profile = args[1] as String?;
      profileWrites.add(profile);
      return Future<void>.value();
    }
    if (args.length == 1) {
      switch (member) {
        case #getPendingContactMessages:
          _key(args.single);
          return const <Message>[];
        case #getUnreadCountForContactKey:
          _key(args.single);
          return 0;
        case #getContactCyr2LatProfileId:
          _key(args.single);
          return profile;
        case #contactMcmpVersion:
          _key(args.single);
          return 3;
        case #contactMcmpUseSign:
        case #isContactMCOtxtPlainWhenSmaller:
          _key(args.single);
          return true;
        case #isContactUrlImagesEnabled:
        case #isContactSendingDelayEnabled:
          _key(args.single);
          return false;
        case #getContactQuickAnswerIds:
          _key(args.single);
          return const <String>[];
      }
    }
    throw StateError('Unexpected contact settings operation: $member');
  }

  @override
  void dispose() {
    unawaited(failures.close());
    super.dispose();
  }
}

Future<void> _withChat(WidgetTester tester, String locale, int type,
    Future<void> Function(_Radio, _Settings, AppLocalizations) run, {
  bool startWithMcmp = false,
  Size size = const Size(1100, 1800),
  double dialogTextScale = 1,
  String alpha = 'Alpha',
  String beta = 'Beta',
}) async {
  final radio = _Radio(type);
  if (startWithMcmp) {
    radio.compression['mcmp'] = true;
    radio.compression['cyr2lat'] = false;
  }
  final settings = _Settings(alpha: alpha, beta: beta);
  final initialSettings = settings.value.toJson();
  final scale = ChatTextScaleService();
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  try {
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<MeshCoreConnector>.value(value: radio),
        ChangeNotifierProvider<AppSettingsService>.value(value: settings),
        ChangeNotifierProvider<ChatTextScaleService>.value(value: scale),
      ],
      child: MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(dialogTextScale),
          ),
          child: child!,
        ),
        // The route above uses the requested text scale. Keep the underlying
        // chat's fonts unchanged: this regression targets the actual modal,
        // rather than unrelated empty-chat/app-bar layouts behind it.
        home: Builder(builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
          child: ChatScreen(contact: radio.target),
        )),
      ),
    ));
    await tester.pumpAndSettle();
    expect(radio.profileWrites, isEmpty);
    expect(radio.compressionWrites, isEmpty);
    expect(radio.flagWrites, isEmpty);
    final l10n = AppLocalizations.of(tester.element(find.byType(ChatScreen)));
    await run(radio, settings, l10n);
    expect(settings.value.toJson(), initialSettings);
    expect(tester.takeException(), isNull);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(radio.activeContacts, [radio.target.publicKeyHex, null]);
    expect(radio.failures.hasListener, isFalse);
    expect(radio.indicatorLeases, 0);
    radio.dispose();
    scale.dispose();
    settings.dispose();
  }
}

Future<void> _open(WidgetTester tester, _Radio radio) async {
  await tester.tap(find.byType(PopupMenuButton<String>));
  await tester.pumpAndSettle();
  final item = find.byWidgetPredicate((widget) =>
      widget is PopupMenuItem<String> && widget.value == 'settings');
  expect(item.hitTestable(), findsOneWidget);
  await tester.tap(item);
  await tester.pumpAndSettle();
  expect(find.byType(AlertDialog), findsOneWidget);
  expect(radio.loads.toSet(), _loads);
}

Finder get _field => find.descendant(of: find.byType(AlertDialog),
    matching: find.byType(DropdownButtonFormField<String>));

Future<DropdownButton<String>> _dropdown(WidgetTester tester) async {
  final arrow = find.descendant(of: _field,
      matching: find.byIcon(Icons.arrow_drop_down));
  expect(arrow, findsOneWidget);
  await tester.ensureVisible(arrow);
  await tester.pumpAndSettle();
  expect(arrow.hitTestable(), findsOneWidget);
  return tester.widget<DropdownButton<String>>(find.descendant(of: _field,
      matching: find.byType(DropdownButton<String>)));
}

Future<void> _select(WidgetTester tester, String label, {
  bool checkWrapping = false,
}) async {
  await _dropdown(tester);
  await tester.tap(find.descendant(of: _field,
      matching: find.byIcon(Icons.arrow_drop_down)));
  await tester.pumpAndSettle();
  final option = await revealDropdownOption(tester, label);
  if (checkWrapping) {
    expectCompleteWrappingLabel(tester, option, wraps: true);
  }
  await tester.tap(option);
  await tester.pumpAndSettle();
}

Future<void> _toggle(WidgetTester tester, String label) async {
  final tile = find.descendant(of: find.byType(AlertDialog),
      matching: find.widgetWithText(SwitchListTile, label));
  expect(tile, findsOneWidget);
  await tester.ensureVisible(tile);
  await tester.pumpAndSettle();
  expect(tile.hitTestable(), findsOneWidget);
  await tester.tap(tile);
  await tester.pumpAndSettle();
}

Future<void> _close(WidgetTester tester, AppLocalizations l10n) async {
  final button = find.descendant(of: find.byType(AlertDialog),
      matching: find.widgetWithText(TextButton, l10n.common_close));
  expect(button.hitTestable(), findsOneWidget);
  await tester.tap(button);
  await tester.pumpAndSettle();
  expect(find.byType(AlertDialog), findsNothing);
}

Future<void> _barrier(WidgetTester tester) async {
  // AlertDialog's default inset keeps this corner outside the dialog.
  await tester.tapAt(const Offset(8, 8));
  await tester.pumpAndSettle();
  expect(find.byType(AlertDialog), findsNothing);
}

void main() {
  for (final locale in ['en', 'ru']) {
    for (final type in [advTypeChat, advTypeRoom]) {
      testWidgets('U11b10 baseline: profile persists immediately across Close and barrier ($locale, type=$type)', (tester) async {
        await _withChat(tester, locale, type, (radio, settings, l10n) async {
          await _open(tester, radio);
          final dropdown = await _dropdown(tester);
          expect(dropdown.value, _alpha);
          expect(dropdown.items!.map((item) => item.value),
              settings.value.cyr2latProfiles.map((profile) => profile.id));
          expect(radio.profileWrites, isEmpty);
          await _select(tester, 'Beta');
          expect(radio.profile, _beta);
          expect(radio.profileWrites, [_beta]); // Before closing the dialog.
          expect(radio.compressionWrites, isEmpty);
          expect(radio.flagWrites, isEmpty);
          await _close(tester, l10n);
          expect(radio.flagWrites, [(false, false, false)]);

          await _open(tester, radio);
          expect((await _dropdown(tester)).value, _beta);
          await _select(tester, 'Alpha');
          expect(radio.profileWrites, [_beta, _alpha]);
          await _barrier(tester);
          await _open(tester, radio);
          expect((await _dropdown(tester)).value, _alpha);
          await _barrier(tester);
          expect(radio.profileWrites, [_beta, _alpha]);
          expect(radio.compressionWrites, isEmpty);
          expect(radio.flagWrites, [(false, false, false)]);
          expect(radio.compression['cyr2lat'], isTrue);
        });
      });

      testWidgets('U11b10 baseline: compression switching hides but retains the chosen profile ($locale, type=$type)', (tester) async {
        await _withChat(tester, locale, type, (radio, settings, l10n) async {
          await _open(tester, radio);
          expect(_field, findsNothing);
          await _toggle(tester, l10n.channels_cyr2latCompression);
          expect(radio.compressionWrites, [
            ('cyr2lat', true), ('mcmp', false), ('mcotxt', false), ('smaz', false),
          ]);
          expect((await _dropdown(tester)).value, _alpha);
          await _select(tester, 'Beta');
          expect(radio.profileWrites, [_beta]);

          await _toggle(tester, l10n.channels_mcmpCompression);
          expect(_field, findsNothing);
          expect(radio.compressionWrites.skip(4), [
            ('mcmp', true), ('smaz', false), ('mcotxt', false), ('cyr2lat', false),
          ]);
          expect(radio.profile, _beta);
          await _close(tester, l10n);
          await _open(tester, radio);
          expect(_field, findsNothing);
          await _toggle(tester, l10n.channels_cyr2latCompression);
          expect((await _dropdown(tester)).value, _beta);
          expect(radio.compressionWrites.skip(8), [
            ('cyr2lat', true), ('mcmp', false), ('mcotxt', false), ('smaz', false),
          ]);
          expect(radio.compression, {
            'mcmp': false, 'mcotxt': false, 'smaz': false, 'cyr2lat': true,
          });
          expect(radio.profileWrites, [_beta]);
          await _barrier(tester);
          expect(radio.flagWrites, [(false, false, false)]);
        }, startWithMcmp: true);
      });

      for (final (orientation, size) in [
        ('phone', const Size(320, 568)),
        ('landscape', const Size(568, 360)),
      ]) {
        testWidgets(
          'U11b10: complete profile names wrap in the field and menu ($locale, type=$type, $orientation, scale=2)',
          (tester) async {
            final alpha = locale == 'ru'
                ? 'Профиль Альфа для кириллицы с полным длинным названием без сокращений и потери символов'
                : 'Alpha profile for Cyrillic text with every character preserved in a complete readable name';
            final beta = locale == 'ru'
                ? 'Профиль Бета для кириллицы с другим полным длинным названием без сокращений и потери символов'
                : 'Beta profile for Cyrillic text with another complete readable name and every character preserved';
            await _withChat(tester, locale, type, (radio, settings, l10n) async {
              await _open(tester, radio);
              final dropdown = await _dropdown(tester);
              expect(MediaQuery.textScalerOf(tester.element(_field)).scale(16), 32);
              expect(dropdown.value, _alpha);
              expect(dropdown.items!.map((item) => item.value),
                  settings.value.cyr2latProfiles.map((profile) => profile.id));
              expectCompleteWrappingLabel(tester,
                  find.descendant(of: _field, matching: find.text(alpha)), wraps: true);
              expect(radio.profileWrites, isEmpty);

              await _select(tester, beta, checkWrapping: true);
              expect((await _dropdown(tester)).value, _beta);
              expectCompleteWrappingLabel(tester,
                  find.descendant(of: _field, matching: find.text(beta)), wraps: true);
              expect(radio.profileWrites, [_beta]); // Saved before Close.
              expect(radio.compressionWrites, isEmpty);
              expect(radio.flagWrites, isEmpty);
              await _close(tester, l10n);

              await _open(tester, radio);
              expect((await _dropdown(tester)).value, _beta);
              expectCompleteWrappingLabel(tester,
                  find.descendant(of: _field, matching: find.text(beta)), wraps: true);
              await _select(tester, alpha, checkWrapping: true);
              expect((await _dropdown(tester)).value, _alpha);
              expectCompleteWrappingLabel(tester,
                  find.descendant(of: _field, matching: find.text(alpha)), wraps: true);
              await _barrier(tester);

              await _open(tester, radio);
              expect((await _dropdown(tester)).value, _alpha);
              await _close(tester, l10n);
              expect(radio.profileWrites, [_beta, _alpha]);
              expect(radio.compressionWrites, isEmpty);
              expect(radio.flagWrites, [(false, false, false), (false, false, false)]);
            }, size: size, dialogTextScale: 2, alpha: alpha, beta: beta);
          },
        );
      }
    }
  }
}
