import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/models/community.dart';
import 'package:meshcore_open/screens/community_qr_scanner_screen.dart';
import 'package:meshcore_open/storage/community_store.dart';
import 'package:meshcore_open/storage/node_state.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:meshcore_open/widgets/qr_scanner_widget.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/wrapping_label_expectations.dart';

const _node = 'aaaaaaaaaa000000000000000000000000000000000000000000000000000000';
const _nodeKey = 'communities_v1aaaaaaaaaa';
const _otherKey = 'communities_v1bbbbbbbbbb';

Community _community(String id, String name, int seed) => Community(
  id: id,
  name: name,
  secret: Uint8List.fromList(List.generate(32, (index) => seed + index)),
  createdAt: DateTime.utc(2026, 1, 1),
  hashtagChannels: ['ops'],
);

final _known = _community('known', 'Local Ops', 0x10);
final _other = _community('other', 'Other Node', 0x70);
final _incoming = _community('incoming', 'Visitors', 0x30);

class _NoPreferenceDirectory extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async =>
      throw MissingPluginException('Synthetic Community QR preferences');
}

// The real CommunityStore uses mock preference fallback; no DB is opened.
// No real connector is created. Any unexpected protocol operation fails.
class _Radio extends ChangeNotifier implements MeshCoreConnector {
  bool loaded = true;
  bool syncing = false;
  final reserved = <int>{1};
  final slots = <Channel>[
    Channel(index: 0, name: 'Existing zero', psk: Uint8List(16)),
    Channel(index: 2, name: 'Existing two', psk: Uint8List(16)),
  ];
  final reads = <Symbol>{};
  final writes = <(int, String, Uint8List)>[];

  @override
  String get selfPublicKeyHex => _node;

  @override
  Future<void> setChannel(int index, String name, Uint8List psk) async {
    writes.add((index, name, Uint8List.fromList(psk)));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isGetter) {
      final member = invocation.memberName;
      switch (member) {
        case #hasLoadedChannels:
          reads.add(member);
          return loaded;
        case #isSyncingChannels:
          reads.add(member);
          return syncing;
        case #channels:
          reads.add(member);
          return List<Channel>.unmodifiable(slots);
        case #unconfirmedChannelSlots:
          reads.add(member);
          return Set<int>.unmodifiable(reserved);
        case #maxChannels:
          reads.add(member);
          return 4;
      }
    }
    throw StateError('Unexpected Community QR operation: ${invocation.memberName}');
  }
}

Map<String, Object> _preferences() {
  final prefs = PrefsManager.instance;
  return {for (final key in prefs.getKeys()) key: prefs.get(key)!};
}

// Processing keeps an indeterminate spinner behind the non-opaque sheet.
// pumpAndSettle cannot finish there. Pump bounded frames and yield the real
// event loop for mocked plugin/storage Futures; do not advance minutes.
Future<void> _until(WidgetTester tester, bool Function() ready, String reason) async {
  final elapsed = Stopwatch()..start();
  while (!ready()) {
    if (elapsed.elapsed > const Duration(seconds: 3)) {
      fail('Community QR baseline timed out: $reason');
    }
    await tester.pump(const Duration(milliseconds: 16));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
  }
}

Future<void> _withScanner(WidgetTester tester, String locale, _Radio radio,
    Future<void> Function(List<Community?>, AppLocalizations) run, {
  Size size = const Size(1100, 1800),
  double sheetTextScale = 1,
  Community? storedMember,
}) async {
  final results = <Community?>[];
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  try {
    expect(QrScannerWidget.isSupported, isFalse,
        reason: 'Run this callback/UI baseline on a host without native camera support');
    expect(NodeState.usesDatabase, isFalse);
    if (storedMember != null) {
      await tester.runAsync(() => (CommunityStore()..setPublicKeyHex = _node)
          .saveCommunities([storedMember]));
    }
    await tester.pumpWidget(ChangeNotifierProvider<MeshCoreConnector>.value(
      value: radio,
      child: MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(sheetTextScale),
          ),
          child: child!,
        ),
        home: Builder(builder: (context) => Scaffold(
          body: Center(child: FilledButton(
            onPressed: () async {
              results.add(await Navigator.of(context).push<Community>(
                // Only the modal's text scale is under test. Keep the
                // unsupported-camera placeholder and scanner app bar stable.
                MaterialPageRoute(builder: (scannerContext) => MediaQuery(
                  data: MediaQuery.of(scannerContext).copyWith(
                    textScaler: TextScaler.noScaling,
                  ),
                  child: const CommunityQrScannerScreen(),
                )),
              ));
            },
            child: const Text('Open scanner'),
          )),
        )),
      ),
    ));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(tester.element(find.text('Open scanner')));
    await tester.tap(find.text('Open scanner'));
    await tester.pumpAndSettle();
    expect(find.byType(QrScannerWidget), findsOneWidget);
    expect(radio.reads, isEmpty);
    expect(radio.writes, isEmpty);
    await run(results, l10n);
    expect(tester.takeException(), isNull);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    radio.dispose();
  }
}

Future<void> _scan(WidgetTester tester, String data) async {
  final scanner = tester.widget<QrScannerWidget>(find.byType(QrScannerWidget));
  expect(scanner.validator!(data), isTrue);
  // Inject at the real scanner callback boundary; the camera isn't started.
  // A second detection while processing must not open another sheet or join.
  scanner.onScanned(data);
  scanner.onScanned(data);
  await _until(tester, () => find.byType(BottomSheet).evaluate().length == 1,
      'one confirmation sheet opens');
  await tester.pump(const Duration(milliseconds: 300));
  expect(find.byType(QrScannerProcessingBody), findsOneWidget);
}

Finder _inSheet(Finder finder) => find.descendant(
  of: find.byType(BottomSheet), matching: finder,
);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  expect(finder, findsOneWidget);
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  // The processing spinner keeps ticking while a sheet is open.
  await tester.pump(const Duration(milliseconds: 300));
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _resumed(WidgetTester tester) async {
  await _until(tester, () => find.byType(QrScannerWidget).evaluate().length == 1 &&
      find.byType(BottomSheet).evaluate().isEmpty, 'scanner resumes');
  expect(find.byType(QrScannerProcessingBody), findsNothing);
}

Future<void> _returned(WidgetTester tester, List<Community?> results) async {
  await _until(tester, () => results.length == 1 &&
      find.byType(CommunityQrScannerScreen).evaluate().isEmpty, 'scanner route returns');
  expect(find.text('Open scanner'), findsOneWidget);
}

Finder get _close => _inSheet(find.byWidgetPredicate((widget) =>
    widget is IconButton && widget.icon is Icon &&
    (widget.icon as Icon).icon == Icons.close));

void _complete(WidgetTester tester, String text, {bool wraps = false}) {
  expectCompleteWrappingLabel(tester, _inSheet(find.text(text)), wraps: wraps);
}

void _scrolls(WidgetTester tester) {
  final vertical = _inSheet(find.byWidgetPredicate((widget) =>
      widget is Scrollable && widget.axisDirection == AxisDirection.down));
  expect(vertical, findsOneWidget);
  expect(tester.state<ScrollableState>(vertical).position.maxScrollExtent, greaterThan(0));
  expect(MediaQuery.textScalerOf(tester.element(find.byType(BottomSheet))).scale(16), 32);
}

enum _JoinCase { localOnly, freeSlot, incomplete, syncing, full }

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PathProviderPlatform savedPaths;
  setUpAll(() {
    savedPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _NoPreferenceDirectory();
  });
  tearDownAll(() => PathProviderPlatform.instance = savedPaths);
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      _nodeKey: jsonEncode([_known.toJson()]),
      _otherKey: jsonEncode([_other.toJson()]),
    });
    PrefsManager.reset();
    await PrefsManager.initialize();
  });
  tearDown(PrefsManager.reset);

  // On Windows/Linux QrScannerWidget never constructs a camera controller.
  // Other hosts need their own camera-platform fake, not real permissions.
  final skipCameraHost = QrScannerWidget.isSupported;
  for (final locale in ['en', 'ru']) {
    testWidgets('U11b11 baseline: Cancel, Close and barrier keep data and resume with cooldown ($locale)', (tester) async {
      final radio = _Radio();
      await _withScanner(tester, locale, radio, (results, l10n) async {
        final before = _preferences();
        for (final (index, action) in ['cancel', 'close', 'barrier'].indexed) {
          final candidate = _community('cancel-$index', 'Candidate $index', 0x40 + index);
          final data = candidate.toQrJson();
          await _scan(tester, data);
          expect(_inSheet(find.text(l10n.community_joinTitle)), findsOneWidget);
          final checkbox = _inSheet(find.byType(CheckboxListTile));
          expect(tester.widget<CheckboxListTile>(checkbox).value, isTrue);
          expect(_preferences(), before);
          if (action == 'cancel') {
            await _tap(tester, _inSheet(find.widgetWithText(OutlinedButton, l10n.common_cancel)));
          } else if (action == 'close') {
            await _tap(tester, _close);
          } else {
            await tester.tapAt(const Offset(8, 8));
            await tester.pump(const Duration(milliseconds: 300));
          }
          await _resumed(tester);
          final resumed = tester.widget<QrScannerWidget>(find.byType(QrScannerWidget));
          expect(resumed.validator!(data), isFalse);
          expect(resumed.validator!(_incoming.toQrJson()), isTrue);
          resumed.onValidationFailed!(data);
          await tester.pump();
          expect(find.text(l10n.community_invalidQrCode), findsNothing);
          expect(_preferences(), before);
          expect(results, isEmpty);
          expect(radio.reads, isEmpty);
          expect(radio.writes, isEmpty);
        }
      });
    }, skip: skipCameraHost);

    for (final acknowledge in [false, true]) {
      testWidgets('U11b11 baseline: existing secret keeps local data (ack=$acknowledge, $locale)', (tester) async {
        final radio = _Radio();
        await _withScanner(tester, locale, radio, (results, l10n) async {
          final before = _preferences();
          final qr = Community(id: 'remote', name: 'Remote label',
              secret: _known.secret, createdAt: DateTime.utc(2026, 2, 1)).toQrJson();
          await _scan(tester, qr);
          expect(_inSheet(find.text(l10n.community_alreadyMember)), findsOneWidget);
          expect(_inSheet(find.text(_known.name)), findsOneWidget);
          expect(_inSheet(find.text(l10n.community_shortId(_known.shortCommunityId))), findsOneWidget);
          expect(_inSheet(find.text('Remote label')), findsNothing);
          expect(_inSheet(find.byType(CheckboxListTile)), findsNothing);
          if (acknowledge) {
            await _tap(tester, _inSheet(find.widgetWithText(FilledButton, l10n.common_ok)));
            await _returned(tester, results);
            expect(results, [null]);
          } else {
            await _tap(tester, _close);
            await _resumed(tester);
            expect(results, isEmpty);
            expect(tester.widget<QrScannerWidget>(find.byType(QrScannerWidget)).validator!(qr), isFalse);
          }
          expect(_preferences(), before);
          expect(radio.reads, isEmpty);
          expect(radio.writes, isEmpty);
        });
      }, skip: skipCameraHost);
    }

    for (final mode in _JoinCase.values) {
      testWidgets('U11b11 baseline: join saves locally and respects channel consent/slot guards ($locale, ${mode.name})', (tester) async {
        final radio = _Radio();
        if (mode == _JoinCase.incomplete) {
          radio.loaded = false;
        } else if (mode == _JoinCase.syncing) {
          radio.syncing = true;
        } else if (mode == _JoinCase.full) {
          radio.reserved.add(3);
        }
        await _withScanner(tester, locale, radio, (results, l10n) async {
          final before = _preferences();
          await _scan(tester, _incoming.toQrJson());
          expect(_inSheet(find.text(_incoming.name)), findsOneWidget);
          final checkbox = _inSheet(find.byType(CheckboxListTile));
          expect(tester.widget<CheckboxListTile>(checkbox).value, isTrue);
          if (mode == _JoinCase.localOnly) {
            await _tap(tester, checkbox);
            expect(tester.widget<CheckboxListTile>(checkbox).value, isFalse);
          }
          expect(_preferences(), before);
          expect(radio.reads, isEmpty);
          expect(radio.writes, isEmpty);
          await _tap(tester, _inSheet(find.widgetWithText(FilledButton, l10n.community_join)));
          await _returned(tester, results);
          final returned = results.single!;
          expect(returned.communityId, _incoming.communityId);
          expect(returned.id, isNotEmpty);
          final stored = await (CommunityStore()..setPublicKeyHex = _node).loadCommunities();
          expect(stored, hasLength(2)); // Duplicate callback cannot join twice.
          expect(stored.singleWhere((c) => c.id == _known.id).toJson(), _known.toJson());
          expect(stored.singleWhere((c) => c.communityId == _incoming.communityId).toJson(), returned.toJson());
          expect(returned.name, _incoming.name);
          expect(returned.secret, _incoming.secret);
          expect(returned.hashtagChannels, isEmpty); // QR doesn't carry hashtags.
          expect({..._preferences()}..remove(_nodeKey), {...before}..remove(_nodeKey));

          if (mode == _JoinCase.freeSlot) {
            expect(radio.writes, hasLength(1));
            final (slot, name, psk) = radio.writes.single;
            expect(slot, 3); // Slots 0/2 used, 1 unconfirmed: don't overwrite.
            expect(name, '${_incoming.name} ${l10n.channels_public}');
            expect(psk, _incoming.deriveCommunityPublicPsk());
          } else {
            expect(radio.writes, isEmpty);
          }
          final expectedReads = switch (mode) {
            _JoinCase.localOnly => <Symbol>{},
            _JoinCase.incomplete => {#hasLoadedChannels},
            _JoinCase.syncing => {#hasLoadedChannels, #isSyncingChannels},
            _JoinCase.freeSlot || _JoinCase.full => {
              #hasLoadedChannels, #isSyncingChannels, #channels,
              #unconfirmedChannelSlots, #maxChannels,
            },
          };
          expect(radio.reads, expectedReads);
        });
      }, skip: skipCameraHost);
    }

    for (final (orientation, size) in [
      ('phone', const Size(320, 568)),
      ('landscape', const Size(568, 360)),
    ]) {
      final longName = locale == 'ru'
          ? 'Сообщество для подробной проверки всех сведений и доступности действий на коротком экране с сохранением полного длинного названия'
          : 'Community with a complete descriptive name and every action accessible on a short screen with its full uninterrupted list of details';
      testWidgets(
        'U11b11: join consent, Cancel and Join stay accessible ($locale, $orientation, scale=2)',
        (tester) async {
          final radio = _Radio();
          await _withScanner(tester, locale, radio, (results, l10n) async {
            final before = _preferences();
            final cancelled = _community('cancel-long', longName, 0x50);
            await _scan(tester, cancelled.toQrJson());
            _scrolls(tester);
            _complete(tester, l10n.community_joinTitle);
            _complete(tester, l10n.community_joinConfirmation(longName));
            _complete(tester, longName, wraps: true);
            _complete(tester, l10n.community_shortId(cancelled.shortCommunityId));
            final checkbox = _inSheet(find.byType(CheckboxListTile));
            expect(tester.widget<CheckboxListTile>(checkbox).value, isTrue);
            _complete(tester, l10n.community_addPublicChannel);
            _complete(tester, l10n.community_addPublicChannelHint);
            await _tap(tester, checkbox);
            expect(tester.widget<CheckboxListTile>(checkbox).value, isFalse);
            await _tap(tester, _inSheet(find.widgetWithText(OutlinedButton, l10n.common_cancel)));
            await _resumed(tester);
            expect(_preferences(), before);
            expect(results, isEmpty);

            // Different QR data bypasses the existing same-code cooldown.
            final joined = _community('join-long', '$longName 2', 0x51);
            await _scan(tester, joined.toQrJson());
            _scrolls(tester);
            expect(tester.widget<CheckboxListTile>(checkbox).value, isTrue);
            await _tap(tester, checkbox);
            expect(tester.widget<CheckboxListTile>(checkbox).value, isFalse);
            expect(_preferences(), before);
            await _tap(tester, _inSheet(find.widgetWithText(FilledButton, l10n.community_join)));
            await _returned(tester, results);
            expect(results.single!.name, joined.name);
            expect(results.single!.communityId, joined.communityId);
            final stored = await (CommunityStore()..setPublicKeyHex = _node).loadCommunities();
            expect(stored, hasLength(2));
            expect(stored.singleWhere((c) => c.id == _known.id).toJson(), _known.toJson());
            expect(stored.singleWhere((c) => c.communityId == joined.communityId).toJson(),
                results.single!.toJson());
            expect({..._preferences()}..remove(_nodeKey), {...before}..remove(_nodeKey));
            expect(radio.reads, isEmpty);
            expect(radio.writes, isEmpty);
          }, size: size, sheetTextScale: 2);
        },
        skip: skipCameraHost,
      );

      testWidgets(
        'U11b11: member details, Close and OK stay accessible ($locale, $orientation, scale=2)',
        (tester) async {
          final radio = _Radio();
          final member = Community(id: _known.id, name: longName,
              secret: _known.secret, createdAt: _known.createdAt,
              hashtagChannels: _known.hashtagChannels);
          await _withScanner(tester, locale, radio, (results, l10n) async {
            final before = _preferences();
            final first = Community(id: 'first', name: 'First remote label',
                secret: member.secret, createdAt: member.createdAt).toQrJson();
            await _scan(tester, first);
            _scrolls(tester);
            _complete(tester, l10n.community_alreadyMember);
            _complete(tester, l10n.community_alreadyMemberMessage(longName));
            _complete(tester, longName, wraps: true);
            _complete(tester, l10n.community_shortId(member.shortCommunityId));
            await _tap(tester, _close);
            await _resumed(tester);
            expect(results, isEmpty);
            expect(_preferences(), before);

            final second = Community(id: 'second', name: 'Second remote label',
                secret: member.secret, createdAt: member.createdAt).toQrJson();
            await _scan(tester, second);
            _scrolls(tester);
            _complete(tester, longName, wraps: true);
            await _tap(tester, _inSheet(find.widgetWithText(FilledButton, l10n.common_ok)));
            await _returned(tester, results);
            expect(results, [null]);
            expect(_preferences(), before);
            expect(radio.reads, isEmpty);
            expect(radio.writes, isEmpty);
          }, size: size, sheetTextScale: 2, storedMember: member);
        },
        skip: skipCameraHost,
      );
    }
  }
}
