import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/connector/pending_command_replies.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/models/message.dart';
import 'package:meshcore_open/storage/contact_discovery_store.dart';
import 'package:meshcore_open/storage/contact_identity_store.dart';
import 'package:meshcore_open/storage/contact_settings_store.dart';
import 'package:meshcore_open/storage/contact_store.dart';
import 'package:meshcore_open/storage/message_history_database.dart';
import 'package:meshcore_open/storage/message_history_storage.dart';
import 'package:meshcore_open/storage/message_store.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';

// U06c2 baseline on unchanged production code. The physical radio is scripted;
// sendFrame, its ACK queue, contact handlers and native SQLite are real. Removal
// is explicitly awaited here (already supported by the fork's batch UI).
// The accepted invariants are retained; U06c2 behavior cases below additionally
// exercise default ACK waiting and the deleted/in-flight contact guards.

class _NoDirectory extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async =>
      throw MissingPluginException('In-memory contact-removal baseline');
}

Uint8List _key(int seed) => Uint8List.fromList(
  List<int>.generate(32, (index) => (seed + index) & 0xFF),
);

final _nodeKey = _key(0x20);
final _targetKey = _key(0x50);
final _otherKey = _key(0x80);
final _linkedKey = _key(0xB0);
final _advertTime = DateTime.utc(2026, 1, 2, 3, 4, 5);

Contact _contact(Uint8List key, String name) => Contact(
  publicKey: key,
  name: name,
  type: advTypeRepeater,
  flags: contactFlagTeleBase,
  pathLength: 1,
  path: Uint8List.fromList([0x10, 0x11, 0x12]),
  pathHashWidth: 3,
  lastSeen: _advertTime,
);

Uint8List _contactFrame(Contact contact, {int code = respCodeContact}) {
  // Use the established frame builder; only the direction/code changes.
  final frame = buildUpdateContactPathFrame(
    contact.publicKey,
    contact.path,
    contact.pathLength < 0 ? 0xFF :
        ((contact.pathHashWidth - 1) << 6) | contact.pathLength,
    type: contact.type,
    flags: contact.flags,
    name: contact.name,
    lat: contact.latitude,
    lon: contact.longitude,
    lastAdvert: contact.lastSeen,
  );
  return Uint8List.fromList(frame)..[0] = code;
}

// A received advert and a manual raw import exercise two independent
// connector parsers. Accepted baseline has no feature fields; regressions
// below additionally exercise both optional 16-bit fields and truncation.
Uint8List _rxAdvert(Uint8List key, String name, {
  required Uint8List path,
  required int width,
  bool located = false,
  int timestamp = 1700000000,
  bool hasName = true,
  int type = advTypeRoom,
  int? feature1,
  int? feature2,
}) {
  final stamp = ByteData(4)..setUint32(0, timestamp, Endian.little);
  final position = ByteData(8)
    ..setInt32(0, 55750000, Endian.little)
    ..setInt32(4, 37625000, Endian.little);
  return Uint8List.fromList([
    pushCodeLogRxData, 20, (-70) & 0xFF,
    (payloadTypeADVERT << 2) | 1, // flood route
    ((width - 1) << 6) | (path.length ~/ width),
    ...path, ...key, ...stamp.buffer.asUint8List(),
    ...List<int>.filled(64, 0), // synthetic signature; parser does not verify it
    type | (located ? 0x10 : 0) | (hasName ? 0x80 : 0) |
        (feature1 != null ? 0x20 : 0) | (feature2 != null ? 0x40 : 0),
    if (located) ...position.buffer.asUint8List(),
    if (feature1 != null) ...[feature1 & 0xFF, (feature1 >> 8) & 0xFF],
    if (feature2 != null) ...[feature2 & 0xFF, (feature2 >> 8) & 0xFF],
    if (hasName) ...utf8.encode(name),
    if (hasName) 0,
  ]);
}

Uint8List _selfInfo() {
  final bytes = ByteData(64);
  bytes.setUint8(0, respCodeSelfInfo);
  bytes.setUint8(1, advTypeChat);
  bytes.setUint8(2, 14);
  bytes.setUint8(3, 22);
  bytes.buffer.asUint8List().setRange(4, 36, _nodeKey);
  bytes.setUint32(48, 869495, Endian.little);
  bytes.setUint32(52, 125000, Endian.little);
  bytes.setUint8(56, 7);
  bytes.setUint8(57, 5);
  bytes.buffer.asUint8List().setRange(58, 63, 'Owner'.codeUnits);
  return bytes.buffer.asUint8List();
}

Future<void> _until(FutureOr<bool> Function() ready, String description) async {
  final deadline = DateTime.now().add(const Duration(seconds: 4));
  while (!await ready()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Contact baseline timed out: $description');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

class _Operation {
  _Operation(Future<void> operation) {
    unawaited(operation.then<void>((_) {
      done = true;
    }, onError: (Object error, StackTrace stack) {
      failure = error;
      done = true;
    }));
  }

  bool done = false;
  Object? failure;

  Future<void> finish() async {
    await _until(() => done, 'operation completion');
    expect(failure, isNull);
  }
}

class _Harness {
  final connector = MeshCoreConnector();
  final radioContacts = <Contact>[
    _contact(_targetKey, 'Target repeater'),
    _contact(_otherKey, 'Unrelated repeater'),
  ];
  final sent = <Uint8List>[];
  Object? removeWriteFailure;
  // U13a can hold or reject an ADD independently of the removal fixture.
  bool holdAddAck = false;
  int? addError;
  Completer<void>? contactReadGate;
  Completer<void>? addWriteGate;

  String get node => pubKeyToHex(_nodeKey);
  String get targetHex => pubKeyToHex(_targetKey);
  String get otherHex => pubKeyToHex(_otherKey);
  Contact get target => connector.contacts.singleWhere((c) => c.publicKeyHex == targetHex);
  ContactStore get contacts => ContactStore()..setPublicKeyHex = node;
  ContactSettingsStore get options => ContactSettingsStore()..setPublicKeyHex = node;
  MessageStore get history => MessageStore()..setPublicKeyHex = node;

  Future<void> start() async {
    connector.setReconnectContextForTest(
      transport: MeshCoreTransportType.tcp,
      state: MeshCoreConnectionState.connected,
    );
    connector.setFrameWriterForTest(_write);
    await connector.refreshDeviceInfo();
    // getContacts awaits the connector's original async cache load before
    // syncing. No arbitrary sleep and no widget fake clock around SQLite.
    await connector.getContacts();
    await _until(() async => (await contacts.loadContacts()).length == 2,
        'initial SQL contact list');
    await connector.loadContactCache();
    expect(connector.hasLoadedContacts, isTrue);
    expect(connector.contacts, hasLength(2));
    sent.clear();
  }

  Future<void> _write(Uint8List frame) async {
    sent.add(Uint8List.fromList(frame));
    switch (frame[0]) {
      case cmdDeviceQuery:
        connector.handleFrameForTest([respCodeDeviceInfo, 1, 16, 0]);
        break;
      case cmdAppStart:
        connector.handleFrameForTest(_selfInfo());
        break;
      case cmdGetBattAndStorage:
        connector.handleFrameForTest([respCodeBattAndStorage, 0x10, 0x0E, ...List<int>.filled(8, 0)]);
        break;
      case cmdGetCustomVar:
        connector.handleFrameForTest([respCodeCustomVars, 0]);
        break;
      case cmdGetContacts:
        connector.handleFrameForTest([respCodeContactsStart, radioContacts.length, 0, 0, 0]);
        for (final contact in radioContacts) {
          connector.handleFrameForTest(_contactFrame(contact));
        }
        connector.handleFrameForTest([respCodeEndOfContacts, 0, 0, 0, 0]);
        break;
      case cmdSyncNextMessage:
        connector.handleFrameForTest([respCodeNoMoreMessages]);
        break;
      case cmdGetContactByKey:
        final key = pubKeyToHex(Uint8List.fromList(frame.sublist(1, 33)));
        connector.handleFrameForTest(_contactFrame(
          radioContacts.singleWhere((contact) => contact.publicKeyHex == key),
        ));
        await contactReadGate?.future;
        break;
      case cmdAddUpdateContact:
        if (holdAddAck) return;
        final rejected = addError;
        if (rejected != null) {
          connector.handleFrameForTest([respCodeErr, rejected]);
          return;
        }
        final response = Uint8List.fromList(frame)..[0] = respCodeContact;
        final updated = Contact.fromFrame(response)!;
        final index = radioContacts.indexWhere((contact) => contact.publicKeyHex == updated.publicKeyHex);
        if (index < 0) {
          radioContacts.add(updated);
        } else {
          radioContacts[index] = updated;
        }
        connector.handleFrameForTest([respCodeOk]);
        await addWriteGate?.future;
        break;
      case cmdResetPath:
        connector.handleFrameForTest([respCodeOk]);
        break;
      case cmdRemoveContact:
        final error = removeWriteFailure;
        if (error != null) throw error;
        // Explicitly held until the test replies. Actual ACK tracking is used.
        break;
      default:
        fail('Unexpected frame in contact baseline: ${frame[0]}');
    }
  }

  void replyToRemove({int? error}) {
    if (error == null || error == errCodeNotFound) {
      radioContacts.removeWhere((contact) => contact.publicKeyHex == targetHex);
    }
    connector.handleFrameForTest(error == null ? [respCodeOk] : [respCodeErr, error]);
  }

  Future<void> seedHistoryAndOptions() async {
    await ContactIdentities.instance.link(targetHex, pubKeyToHex(_linkedKey));
    for (final key in [_targetKey, _linkedKey]) {
      await history.saveMessages(pubKeyToHex(key), [Message(
        senderKey: key,
        text: 'SYNTHETIC_HISTORY_${key.first}',
        timestamp: _advertTime.add(Duration(seconds: key.first)),
        isOutgoing: false,
      )]);
    }
    await options.saveMcmpEnabled(targetHex, true);
    await options.saveSendingDelayEnabled(targetHex, true);
    await options.saveMcmpEnabled(otherHex, true);
    expect(await history.loadMessages(targetHex), hasLength(2));
  }

  Future<void> removedOnDisk() => _until(
    () async => (await contacts.loadContacts()).every((contact) => contact.publicKeyHex != targetHex),
    'removed target committed to SQL',
  );

  Future<void> settle() async {
    await Future<void>.delayed(Duration.zero);
    await _until(() => !connector.backgroundWorkSnapshot.isBusy, 'background work released');
    await contacts.loadContacts();
  }
}

Future<String?> _sqliteProblem() async {
  final database = MessageHistoryDatabase.withExecutor(NativeDatabase.memory());
  try {
    await database.customSelect('SELECT 1').get();
    return null;
  } catch (error) {
    return 'Native SQLite unavailable on this host: $error';
  } finally {
    try {
      await database.close();
    } catch (_) {
      // A failed SQLite open may leave no executor that can be closed.
    }
  }
}

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final sqliteProblem = await _sqliteProblem();
  final storage = MessageHistoryStorage.instance;
  late PathProviderPlatform originalPaths;
  late _Harness h;
  const badge = MethodChannel('meshcore_open/app_badge');

  setUpAll(() {
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _NoDirectory();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(badge, (_) async => null);
  });
  tearDownAll(() {
    PathProviderPlatform.instance = originalPaths;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(badge, null);
  });

  group('U06c2 baseline: fork removal and SQL history', () {
    setUp(() async {
      await storage.resetForTesting();
      SharedPreferences.setMockInitialValues({});
      PrefsManager.reset();
      await PrefsManager.initialize();
      await storage.initializeAndMigrate(databaseFactory: () =>
          MessageHistoryDatabase.withExecutor(NativeDatabase.memory()));
      await ContactIdentities.instance.load();
      h = _Harness();
      addTearDown(() async {
        try {
          for (final gate in [h.contactReadGate, h.addWriteGate]) {
            if (gate != null && !gate.isCompleted) gate.complete();
          }
          if (h.connector.pendingCommandReplyCountForTest > 0) {
            h.connector.handleFrameForTest([respCodeOk]);
          }
          await h.settle();
        } finally {
          h.connector.dispose();
          await storage.resetForTesting();
          ContactIdentities.instance.resetForTesting();
          PrefsManager.reset();
        }
      });
      await h.start();
    });

    for (final keepHistory in [false, true]) {
      test('explicit ACK gates removal and linked SQL history choice=$keepHistory', () async {
        await h.seedHistoryAndOptions();
        final target = h.target;
        final operation = _Operation(h.connector.deleteContact(
          target, waitForAck: true, keepMessages: keepHistory,
        ));
        await _until(() => h.sent.any((frame) => frame.first == cmdRemoveContact), 'remove written');
        expect(operation.done, isFalse);
        expect(h.connector.contacts.map((c) => c.publicKeyHex), contains(h.targetHex));
        expect((await h.contacts.loadContacts()).map((c) => c.publicKeyHex), contains(h.targetHex));
        expect(await h.history.loadMessages(h.targetHex), hasLength(2));
        h.replyToRemove();
        await operation.finish();
        await h.removedOnDisk();
        expect(h.connector.contacts.map((c) => c.publicKeyHex), [h.otherHex]);
        expect((await h.contacts.loadContacts()).map((c) => c.publicKeyHex), [h.otherHex]);
        expect(await h.history.loadMessages(h.targetHex), hasLength(keepHistory ? 2 : 0));
        expect(await h.history.loadMessages(pubKeyToHex(_linkedKey)), hasLength(keepHistory ? 2 : 0));
        expect(h.options.readSettings(h.targetHex)!.mcmpEnabled, isTrue);
        expect(h.options.readSettings(h.targetHex)!.sendingDelayEnabled, isTrue);
        expect(h.options.readSettings(h.otherHex)!.mcmpEnabled, isTrue);
        await _until(() async => (await ContactDiscoveryStore().loadContacts())
            .any((c) => c.publicKeyHex == h.targetHex && !c.isActive), 'inactive discovered record');
        await h.connector.getContacts();
        expect(h.connector.contacts.map((c) => c.publicKeyHex), [h.otherHex]);
      });
    }

    for (final error in [errCodeTableFull, 1]) {
      test('non-NOT_FOUND ERR=$error preserves contact, SQL history and settings', () async {
        await h.seedHistoryAndOptions();
        final operation = _Operation(h.connector.removeContact(h.target, waitForAck: true));
        await _until(() => h.sent.any((frame) => frame.first == cmdRemoveContact), 'remove written');
        h.replyToRemove(error: error);
        await _until(() => operation.done, 'firmware ERR handled');
        expect(operation.failure, isA<CommandFailedException>()
            .having((error) => error.errCode, 'errCode', error));
        expect(h.connector.contacts, hasLength(2));
        expect(await h.contacts.loadContacts(), hasLength(2));
        expect(await h.history.loadMessages(h.targetHex), hasLength(2));
        expect(h.options.readSettings(h.targetHex)!.mcmpEnabled, isTrue);
      });
    }

    test('NOT_FOUND is idempotent success and transport failure is not', () async {
      await h.seedHistoryAndOptions();
      final failure = StateError('Synthetic transport failure');
      h.removeWriteFailure = failure;
      await expectLater(h.connector.removeContact(h.target, waitForAck: true), throwsA(same(failure)));
      expect(h.connector.contacts, hasLength(2));
      expect(await h.history.loadMessages(h.targetHex), hasLength(2));
      h.removeWriteFailure = null;
      h.sent.clear();
      final removal = _Operation(h.connector.removeContact(h.target, waitForAck: true, keepMessages: true));
      await _until(() => h.sent.any((frame) => frame.first == cmdRemoveContact), 'second remove written');
      h.replyToRemove(error: errCodeNotFound);
      await removal.finish();
      await h.removedOnDisk();
      expect(h.connector.contacts.map((c) => c.publicKeyHex), [h.otherHex]);
      expect(await h.history.loadMessages(h.targetHex), hasLength(2));
    });

    test('missing ACK times out while preserving SQL history and the contact', () async {
      await h.seedHistoryAndOptions();
      await expectLater(
        h.connector.removeContact(h.target, waitForAck: true),
        throwsA(isA<TimeoutException>()),
      );
      expect(h.connector.contacts, hasLength(2));
      expect(await h.contacts.loadContacts(), hasLength(2));
      expect(await h.history.loadMessages(h.targetHex), hasLength(2));
      expect(h.options.readSettings(h.targetHex)!.mcmpEnabled, isTrue);
    });

    test('awaited deletion while disconnected fails without local changes', () async {
      h.connector.setReconnectContextForTest(
        transport: MeshCoreTransportType.tcp,
        state: MeshCoreConnectionState.disconnected,
      );
      await expectLater(h.connector.deleteContact(h.target, waitForAck: true), throwsException);
      expect(h.sent, isEmpty);
      expect(h.connector.contacts, hasLength(2));
      expect(await h.contacts.loadContacts(), hasLength(2));
    });

    test('discovered-only deletion sends no remove or add command and preserves stored contacts', () async {
      final discovered = _contact(_linkedKey, 'Discovered-only repeater');
      h.connector.handleFrameForTest(_contactFrame(discovered, code: pushCodeNewAdvert));
      expect(h.connector.discoveredContacts.map((c) => c.publicKeyHex), contains(discovered.publicKeyHex));
      h.sent.clear();
      await h.connector.deleteContact(discovered, waitForAck: true);
      expect(h.sent, isEmpty);
      expect(h.connector.contacts, hasLength(2));
      expect(h.connector.discoveredContacts.map((c) => c.publicKeyHex), isNot(contains(discovered.publicKeyHex)));
      expect(await h.contacts.loadContacts(), hasLength(2));
    });

    test('default deletion waits; implicit updates stay silent during and after removal', () async {
      await h.seedHistoryAndOptions();
      final target = h.target;
      final deletion = _Operation(h.connector.deleteContact(target, keepMessages: true));
      await _until(() => h.sent.any((f) => f.first == cmdRemoveContact), 'default remove written');
      expect(deletion.done, isFalse);
      expect(h.connector.contacts, hasLength(2));
      await h.connector.setContactPath(target, Uint8List.fromList([0x44]), 1);
      await h.connector.setContactFlags(target, isFavorite: true);
      expect(h.sent.map((f) => f.first), [cmdRemoveContact]);
      h.replyToRemove();
      await deletion.finish();
      await h.removedOnDisk();
      h.sent.clear();
      await h.connector.setContactPath(target, Uint8List.fromList([0x44]), 1);
      await h.connector.preparePathForContactSend(target);
      await h.connector.setContactFlags(target, isFavorite: true);
      expect(h.sent, isEmpty);
      expect(h.connector.contacts.map((c) => c.publicKeyHex), [h.otherHex]);
      expect(await h.history.loadMessages(h.targetHex), hasLength(2));
    });

    // U13a invariants were accepted on the unchanged import implementation.
    // Keep them when fixing the timestamp tail: the advert time and path
    // belong to the discovered node, independent of its import time.
    for (final width in [1, 2, 3]) {
      for (final located in [false, true]) {
        test('U13a baseline: manual discovery import preserves metadata '
            '(width=$width, location=$located)', () async {
          final route = Uint8List.fromList(
            List<int>.generate(2 * width, (i) => 0x40 + i),
          );
          final found = Contact(
            publicKey: _linkedKey,
            name: 'Discovered room',
            type: advTypeRoom,
            flags: contactFlagTeleBase | contactFlagTeleLoc,
            pathLength: 2,
            path: route,
            pathHashWidth: width,
            latitude: located ? 55.75 : null,
            longitude: located ? 37.625 : null,
            lastSeen: _advertTime,
            isActive: false,
          );
          h.connector.handleFrameForTest(
            _contactFrame(found, code: pushCodeNewAdvert),
          );
          h.sent.clear();
          expect(await h.connector.importDiscoveredContact(found), isTrue);
          expect(h.sent.map((frame) => frame.first), [cmdAddUpdateContact]);
          final frame = h.sent.single;
          expect(frame.sublist(1, 33), found.publicKey);
          expect(frame[33], advTypeRoom);
          expect(frame[34], found.flags);
          expect(frame[35], ((width - 1) << 6) | 2);
          expect(frame.sublist(36, 36 + route.length), route);
          expect(String.fromCharCodes(
            frame.sublist(100, 132).takeWhile((byte) => byte != 0),
          ), found.name);
          expect(ByteData.sublistView(frame).getUint32(132, Endian.little),
              _advertTime.millisecondsSinceEpoch ~/ 1000);
          if (located) {
            expect(ByteData.sublistView(frame).getInt32(136, Endian.little),
                55750000);
            expect(ByteData.sublistView(frame).getInt32(140, Endian.little),
                37625000);
          }
          final stored = h.connector.contacts.singleWhere(
            (contact) => contact.publicKeyHex == found.publicKeyHex,
          );
          expect(stored.path, route);
          expect(stored.pathLength, 2);
          expect(stored.pathHashWidth, width);
          expect(stored.flags, found.flags);
          expect(stored.latitude, found.latitude);
          expect(stored.longitude, found.longitude);
          expect(stored.lastSeen.isAtSameMomentAs(found.lastSeen), isTrue);
          expect(h.connector.discoveredContacts.singleWhere(
            (contact) => contact.publicKeyHex == found.publicKeyHex,
          ).isActive, isTrue);
          expect(h.connector.contacts, hasLength(3));
        });
      }
    }

    for (final located in [false, true]) {
      test('U13a: discovery ADD lets firmware stamp lastmod '
          '(location=$located)', () async {
        final found = _contact(_linkedKey, 'Old advert').copyWith(
          latitude: located ? 55.75 : null,
          longitude: located ? 37.625 : null,
          // Neither a cached lastmod nor a newer telemetry fix may replace
          // the original advert timestamp or the radio's import clock.
          lastModified: DateTime.utc(2025, 6, 1),
          telemetryFixAt: DateTime.utc(2026, 2, 1),
        );
        h.sent.clear();
        expect(await h.connector.importDiscoveredContact(found), isTrue);
        expect(h.sent.map((frame) => frame.first), [cmdAddUpdateContact]);
        final frame = h.sent.single;
        // Firmware keeps its RTC fallback only when bytes 144..147 are
        // absent. Without GPS there is no optional tail at all.
        expect(frame, hasLength(located ? 144 : 136));
        expect(ByteData.sublistView(frame).getUint32(132, Endian.little),
            _advertTime.millisecondsSinceEpoch ~/ 1000);
        if (located) {
          expect(ByteData.sublistView(frame).getInt32(136, Endian.little),
              55750000);
          expect(ByteData.sublistView(frame).getInt32(140, Endian.little),
              37625000);
        }
        final radioCopy = h.radioContacts.singleWhere(
          (contact) => contact.publicKeyHex == found.publicKeyHex,
        );
        expect(radioCopy.lastSeen.isAtSameMomentAs(found.lastSeen), isTrue);
        expect(radioCopy.latitude, found.latitude);
        expect(radioCopy.longitude, found.longitude);
        // The fixture parses the sent frame; it does not simulate an RTC.
        // Absence here confirms no phone-chosen lastmod crossed the wire.
        expect(radioCopy.lastModified, isNull);
      });
    }

    test('U13a baseline: discovery import activates only after ADD ACK', () async {
      final found = _contact(_linkedKey, 'Waiting for ACK');
      h.connector.handleFrameForTest(
        _contactFrame(found, code: pushCodeNewAdvert),
      );
      h.sent.clear();
      h.holdAddAck = true;
      final operation = _Operation(
        h.connector.importDiscoveredContact(found).then<void>((ok) {
          if (!ok) throw StateError('Import unexpectedly returned false');
        }),
      );
      await _until(() => h.sent.isNotEmpty, 'ADD written');
      expect(h.sent.map((frame) => frame.first), [cmdAddUpdateContact]);
      expect(operation.done, isFalse);
      expect(h.connector.contacts, hasLength(2));
      expect(h.connector.discoveredContacts.singleWhere(
        (contact) => contact.publicKeyHex == found.publicKeyHex,
      ).isActive, isFalse);
      h.connector.handleFrameForTest([respCodeOk]);
      await operation.finish();
      expect(h.connector.contacts, hasLength(3));
      expect(h.sent, hasLength(1));
    });

    test('U13a baseline: table-full ADD keeps discovery inactive', () async {
      final found = _contact(_linkedKey, 'Rejected import');
      h.connector.handleFrameForTest(
        _contactFrame(found, code: pushCodeNewAdvert),
      );
      h.sent.clear();
      h.addError = errCodeTableFull;
      await expectLater(h.connector.importDiscoveredContact(found),
          throwsA(isA<CommandFailedException>().having(
            (error) => error.errCode, 'firmware error', errCodeTableFull,
          )));
      expect(h.sent.map((frame) => frame.first), [cmdAddUpdateContact]);
      expect(h.connector.contacts, hasLength(2));
      expect(h.connector.discoveredContacts.singleWhere(
        (contact) => contact.publicKeyHex == found.publicKeyHex,
      ).isActive, isFalse);
    });

    test('U13a baseline: disconnected discovery import sends nothing', () async {
      h.connector.setReconnectContextForTest(
        transport: MeshCoreTransportType.tcp,
        state: MeshCoreConnectionState.disconnected,
      );
      h.sent.clear();
      expect(await h.connector.importDiscoveredContact(
        _contact(_linkedKey, 'Offline import'),
      ), isFalse);
      expect(h.sent, isEmpty);
      expect(h.connector.contacts, hasLength(2));
    });

    for (final width in [1, 2, 3]) {
      for (final located in [false, true]) {
        test('U14 baseline: plain RX advert and manual raw import preserve '
            'name, GPS and hop order (width=$width, location=$located)', () async {
          final route = Uint8List.fromList(
            List<int>.generate(2 * width, (index) => 0x40 + index),
          );
          final reversed = [...route.skip(width), ...route.take(width)];
          final frame = _rxAdvert(_linkedKey, 'Synthetic room',
              path: route, width: width, located: located);
          final keyHex = pubKeyToHex(_linkedKey);
          h.sent.clear();
          h.connector.handleFrameForTest(frame);
          await _until(() => h.connector.discoveredContacts.any(
            (contact) => contact.publicKeyHex == keyHex,
          ), 'raw advert discovered');
          final found = h.connector.discoveredContacts.singleWhere(
            (contact) => contact.publicKeyHex == keyHex,
          );
          expect(found.name, 'Synthetic room');
          expect(found.type, advTypeRoom);
          expect(found.path, reversed);
          expect(found.pathLength, 2);
          expect(found.pathHashWidth, width);
          expect(found.latitude, located ? 55.75 : null);
          expect(found.longitude, located ? 37.625 : null);
          expect(found.lastSeen.millisecondsSinceEpoch ~/ 1000, 1700000000);
          expect(found.isActive, isFalse);
          expect(h.connector.contacts, hasLength(2));
          expect(h.sent, isEmpty);
          final revision = h.connector.discoveredRevision;
          h.connector.handleFrameForTest(frame);
          expect(h.connector.discoveredRevision, revision);

          h.connector.importContact(frame);
          await _until(() => h.connector.contacts.any(
            (contact) => contact.publicKeyHex == keyHex,
          ), 'manual raw import acknowledged');
          final saved = h.connector.contacts.singleWhere(
            (contact) => contact.publicKeyHex == keyHex,
          );
          expect(saved.name, found.name);
          expect(saved.path, reversed);
          expect(saved.pathHashWidth, width);
          expect(saved.latitude, found.latitude);
          expect(saved.longitude, found.longitude);
          expect(h.sent.map((bytes) => bytes.first), [cmdAddUpdateContact]);
          expect(h.target.name, 'Target repeater');
          expect(h.connector.contacts, hasLength(3));
        });
      }
    }

    test('U14 baseline: a real name change updates discovery with no radio write',
        () async {
      final keyHex = pubKeyToHex(_linkedKey);
      final route = Uint8List.fromList([0x10]);
      h.sent.clear();
      h.connector.handleFrameForTest(_rxAdvert(_linkedKey, 'Before',
          path: route, width: 1));
      h.connector.handleFrameForTest(_rxAdvert(_linkedKey, 'After',
          path: route, width: 1, timestamp: 1700000001));
      final found = h.connector.discoveredContacts.singleWhere(
        (contact) => contact.publicKeyHex == keyHex,
      );
      expect(found.name, 'After');
      expect(found.lastSeen.millisecondsSinceEpoch ~/ 1000, 1700000001);
      expect(found.path, [0x10]);
      expect(h.sent, isEmpty);
    });

    test('U14 baseline: an unnamed node can acquire a real advertised name',
        () async {
      final keyHex = pubKeyToHex(_linkedKey);
      final route = Uint8List.fromList([0x10]);
      h.sent.clear();
      h.connector.handleFrameForTest(_rxAdvert(_linkedKey, '',
          path: route, width: 1, hasName: false));
      expect(h.connector.discoveredContacts.singleWhere(
        (contact) => contact.publicKeyHex == keyHex,
      ).name, isEmpty);
      h.connector.handleFrameForTest(_rxAdvert(_linkedKey, 'Now named',
          path: route, width: 1, timestamp: 1700000001));
      expect(h.connector.discoveredContacts.singleWhere(
        (contact) => contact.publicKeyHex == keyHex,
      ).name, 'Now named');
      expect(h.sent, isEmpty);
    });

    for (final features in [(0x1200, null), (null, 0x3400), (0x1200, 0x3400)]) {
      for (final width in [1, 3]) {
        test('U14: feature fields cannot become the name in RX or manual import '
            '(features=$features, width=$width)', () async {
          final route = Uint8List.fromList(
            List<int>.generate(2 * width, (i) => 0x40 + i),
          );
          final frame = _rxAdvert(_linkedKey, 'Feature room',
            path: route, width: width, located: width == 3,
            feature1: features.$1, feature2: features.$2,
          );
          h.sent.clear();
          h.connector.handleFrameForTest(frame);
          final keyHex = pubKeyToHex(_linkedKey);
          final found = h.connector.discoveredContacts.singleWhere(
            (contact) => contact.publicKeyHex == keyHex,
          );
          expect(found.name, 'Feature room');
          expect(found.type, advTypeRoom);
          expect(found.path, [...route.skip(width), ...route.take(width)]);
          expect(found.pathHashWidth, width);
          expect(found.latitude, width == 3 ? 55.75 : null);
          expect(found.longitude, width == 3 ? 37.625 : null);
          expect(h.sent, isEmpty);
          h.connector.importContact(frame);
          await _until(() => h.connector.contacts.any(
            (contact) => contact.publicKeyHex == keyHex,
          ), 'feature advert manually imported');
          final saved = h.connector.contacts.singleWhere(
            (contact) => contact.publicKeyHex == keyHex,
          );
          expect(saved.name, 'Feature room');
          expect(saved.path, found.path);
          expect(saved.pathHashWidth, width);
          expect(saved.latitude, found.latitude);
          expect(h.sent.map((bytes) => bytes.first), [cmdAddUpdateContact]);
        });
      }
    }

    for (final features in [(0x1200, null), (null, 0x3400), (0x1200, 0x3400)]) {
      test('U14: truncated declared feature fields are ignored by both parsers '
          '(features=$features)', () async {
        final complete = _rxAdvert(_linkedKey, '',
          path: Uint8List(0), width: 1, hasName: false,
          feature1: features.$1, feature2: features.$2,
        );
        final truncated = Uint8List.fromList(complete.sublist(0, complete.length - 1));
        h.sent.clear();
        h.connector.handleFrameForTest(truncated);
        h.connector.importContact(truncated);
        await Future<void>.delayed(Duration.zero);
        expect(h.connector.discoveredContacts.any(
          (contact) => contact.publicKeyHex == pubKeyToHex(_linkedKey),
        ), isFalse);
        expect(h.connector.contacts, hasLength(2));
        expect(h.sent, isEmpty);
      });
    }

    test('U14: truncated declared GPS is not interpreted as advert name', () async {
      final complete = _rxAdvert(_linkedKey, '',
        path: Uint8List(0), width: 1, located: true, hasName: false,
      );
      final truncated = Uint8List.fromList(complete.sublist(0, complete.length - 1));
      h.sent.clear();
      h.connector.handleFrameForTest(truncated);
      h.connector.importContact(truncated);
      await Future<void>.delayed(Duration.zero);
      expect(h.connector.discoveredContacts.any(
        (contact) => contact.publicKeyHex == pubKeyToHex(_linkedKey),
      ), isFalse);
      expect(h.sent, isEmpty);
    });

    test('U14: empty, missing and whitespace names keep discovery name and '
        'the unchanged revision fast path', () async {
      final route = Uint8List.fromList([0x10]);
      h.connector.handleFrameForTest(_rxAdvert(_linkedKey, 'Known room',
          path: route, width: 1));
      final keyHex = pubKeyToHex(_linkedKey);
      final known = h.connector.discoveredContacts.singleWhere(
        (contact) => contact.publicKeyHex == keyHex,
      );
      final revision = h.connector.discoveredRevision;
      h.sent.clear();
      for (final variant in [('', true), ('', false), ('  ', true)]) {
        h.connector.handleFrameForTest(_rxAdvert(_linkedKey, variant.$1,
          path: route, width: 1, hasName: variant.$2,
        ));
        final current = h.connector.discoveredContacts.singleWhere(
          (contact) => contact.publicKeyHex == keyHex,
        );
        expect(current.name, 'Known room');
        expect(identical(current, known), isTrue);
        expect(h.connector.discoveredRevision, revision);
      }
      expect(h.sent, isEmpty);
    });

    test('U14: newer nameless discovery keeps its name and accepts new time',
        () async {
      final route = Uint8List.fromList([0x10]);
      h.connector.handleFrameForTest(_rxAdvert(_linkedKey, 'Known room',
          path: route, width: 1));
      h.connector.handleFrameForTest(_rxAdvert(_linkedKey, '',
          path: route, width: 1, timestamp: 1700000001));
      final current = h.connector.discoveredContacts.singleWhere(
        (contact) => contact.publicKeyHex == pubKeyToHex(_linkedKey),
      );
      expect(current.name, 'Known room');
      expect(current.lastSeen.millisecondsSinceEpoch ~/ 1000, 1700000001);
    });

    test('U14: an active contact keeps name and node-owned route on empty name',
        () async {
      final before = h.target;
      h.sent.clear();
      h.connector.handleFrameForTest(_rxAdvert(before.publicKey, '',
        path: Uint8List.fromList([0x44, 0x45]), width: 1,
        type: advTypeRepeater,
        timestamp: _advertTime.millisecondsSinceEpoch ~/ 1000 + 1,
      ));
      expect(h.target.name, before.name);
      expect(h.target.lastSeen.millisecondsSinceEpoch ~/ 1000,
          _advertTime.millisecondsSinceEpoch ~/ 1000 + 1);
      expect(h.target.path, before.path);
      expect(h.target.pathHashWidth, before.pathHashWidth);
      expect(h.target.flags, before.flags);
      expect(h.sent, isEmpty);
    });

    test('U14: removing with a nameless snapshot keeps the discovered name',
        () async {
      h.connector.handleFrameForTest(_contactFrame(h.target, code: pushCodeNewAdvert));
      final known = h.connector.discoveredContacts.singleWhere(
        (contact) => contact.publicKeyHex == h.targetHex,
      );
      expect(known.name, 'Target repeater');
      h.sent.clear();
      final removal = _Operation(h.connector.removeContact(
        h.target.copyWith(name: ''), keepMessages: true,
      ));
      await _until(() => h.sent.any((frame) => frame.first == cmdRemoveContact),
          'nameless snapshot remove written');
      h.replyToRemove();
      await removal.finish();
      expect(h.connector.discoveredContacts.singleWhere(
        (contact) => contact.publicKeyHex == h.targetHex,
      ).name, 'Target repeater');
      expect(h.sent.map((frame) => frame.first), [cmdRemoveContact]);
    });

    test('explicit re-import after removal remains available and preserves local options', () async {
      await h.seedHistoryAndOptions();
      final target = h.target;
      final deletion = _Operation(h.connector.removeContact(target, keepMessages: true));
      await _until(() => h.sent.any((f) => f.first == cmdRemoveContact), 'remove written');
      h.replyToRemove();
      await deletion.finish();
      h.sent.clear();
      expect(await h.connector.importDiscoveredContact(target), isTrue);
      expect(h.connector.contacts.map((c) => c.publicKeyHex), contains(h.targetHex));
      expect(h.sent.where((f) => f.first == cmdAddUpdateContact), hasLength(1));
      await h.connector.setContactPath(target, Uint8List.fromList([0x44]), 1, waitForAck: true);
      expect(h.sent.where((f) => f.first == cmdAddUpdateContact), hasLength(2));
      expect(h.options.readSettings(h.targetHex)!.mcmpEnabled, isTrue);
      expect(await h.history.loadMessages(h.targetHex), hasLength(2));
    });

    test('a rejected default removal releases the guard for legitimate edits', () async {
      final target = h.target;
      final deletion = _Operation(h.connector.removeContact(target, keepMessages: true));
      await _until(() => h.sent.any((f) => f.first == cmdRemoveContact), 'remove written');
      h.replyToRemove(error: errCodeTableFull);
      await _until(() => deletion.done, 'rejected remove finished');
      expect(deletion.failure, isA<CommandFailedException>());
      h.sent.clear();
      await h.connector.setContactPath(target, Uint8List.fromList([0x44]), 1, waitForAck: true);
      expect(h.sent.where((f) => f.first == cmdAddUpdateContact), hasLength(1));
    });

    test('deletion while a fetched snapshot awaits IO completion prevents a later flag write', () async {
      final target = h.target;
      final gate = Completer<void>();
      h.contactReadGate = gate;
      final flags = _Operation(h.connector.setContactFlags(target, isFavorite: true));
      await _until(() => h.sent.any((f) => f.first == cmdGetContactByKey), 'snapshot written');
      final deletion = _Operation(h.connector.removeContact(target, keepMessages: true));
      await _until(() => h.sent.any((f) => f.first == cmdRemoveContact), 'remove written');
      h.replyToRemove();
      await deletion.finish();
      gate.complete();
      await flags.finish();
      await h.removedOnDisk();
      expect(h.sent.where((f) => f.first == cmdAddUpdateContact), isEmpty);
      expect(h.connector.contacts.map((c) => c.publicKeyHex), [h.otherHex]);
    });

    test('a flag write completing after deletion cannot restore its local contact row', () async {
      final target = h.target;
      final gate = Completer<void>();
      h.addWriteGate = gate;
      final flags = _Operation(h.connector.setContactFlags(target, isFavorite: true));
      await _until(() => h.sent.any((f) => f.first == cmdAddUpdateContact), 'flag write started');
      final deletion = _Operation(h.connector.removeContact(target, keepMessages: true));
      await _until(() => h.sent.any((f) => f.first == cmdRemoveContact), 'remove written');
      h.replyToRemove();
      await deletion.finish();
      gate.complete();
      await flags.finish();
      await h.removedOnDisk();
      expect(h.connector.contacts.map((c) => c.publicKeyHex), [h.otherHex]);
    });

    test('path queued behind another write rechecks membership after taking the lock', () async {
      final target = h.target;
      final other = h.connector.contacts.singleWhere((c) => c.publicKeyHex == h.otherHex);
      final gate = Completer<void>();
      h.addWriteGate = gate;
      final first = _Operation(h.connector.setContactPath(other, Uint8List.fromList([0x33]), 1));
      await _until(() => h.sent.any((f) => f.first == cmdAddUpdateContact), 'first path write');
      final queued = _Operation(h.connector.setContactPath(target, Uint8List.fromList([0x44]), 1));
      final deletion = _Operation(h.connector.removeContact(target, keepMessages: true));
      await _until(() => h.sent.any((f) => f.first == cmdRemoveContact), 'remove written');
      h.replyToRemove();
      await deletion.finish();
      gate.complete();
      await first.finish();
      await queued.finish();
      expect(h.sent.where((f) => f.first == cmdAddUpdateContact &&
          pubKeyToHex(Uint8List.fromList(f.sublist(1, 33))) == h.targetHex), isEmpty);
    });

    test('an ACK from the old radio cannot clear contacts or history after a scope change', () async {
      await h.seedHistoryAndOptions();
      final target = h.target;
      final deletion = _Operation(h.connector.removeContact(target));
      await _until(() => h.sent.any((f) => f.first == cmdRemoveContact), 'remove written');
      h.connector.setPacketReplayFixtureForTest(selfKey: _key(0xD0), contacts: [target]);
      h.replyToRemove();
      await _until(() => deletion.done, 'stale remove rejected');
      expect(deletion.failure, isA<StateError>());
      expect(h.connector.contacts.single.publicKeyHex, h.targetHex);
      expect(await h.contacts.loadContacts(), hasLength(2));
      expect(await h.history.loadMessages(h.targetHex), hasLength(2));
    });

    test('U11a: a telemetry fix persists locally without a radio write', () async {
      final original = h.target;
      expect(h.connector.updateContactLocationFromTelemetry(
        h.targetHex, 1, -2, expectedNodeKey: h.node,
      ), isTrue);
      expect(h.sent, isEmpty);
      final positioned = h.target;
      expect(positioned.latitude, 1);
      expect(positioned.longitude, -2);
      expect(positioned.telemetryFixAt, isNotNull);
      expect(positioned.lastSeen, original.lastSeen);
      expect(positioned.lastModified, original.lastModified);
      expect(positioned.lastMessageAt, original.lastMessageAt);
      expect(positioned.path, original.path);
      expect(positioned.pathHashWidth, original.pathHashWidth);
      expect(positioned.flags, original.flags);
      await _until(() async {
        final saved = await h.contacts.loadContacts();
        return saved.any((c) => c.publicKeyHex == h.targetHex &&
            c.telemetryFixAt?.millisecondsSinceEpoch ==
                positioned.telemetryFixAt!.millisecondsSinceEpoch);
      }, 'telemetry fix committed');
      await h.connector.loadContactCache();
      // SQL preserves milliseconds, whereas the original DateTime.now()
      // may contain microseconds. Compare the actual storage contract.
      expect(h.target.telemetryFixAt?.millisecondsSinceEpoch,
          positioned.telemetryFixAt!.millisecondsSinceEpoch);
      expect(h.target.lastSeen, original.lastSeen);
      expect(h.target.latitude, 1);
      expect(h.sent, isEmpty);
    });

    for (final preserve in [false, true]) {
      test('U11a: GPS survives contact sync preserveExisting=$preserve; newer advert wins', () async {
        final original = h.target;
        expect(h.connector.updateContactLocationFromTelemetry(
          h.targetHex, 1, -2, expectedNodeKey: h.node,
        ), isTrue);
        final fixAt = h.target.telemetryFixAt;
        await h.settle();
        await h.connector.getContacts(preserveExisting: preserve);
        expect(h.target.telemetryFixAt, fixAt);
        expect(h.target.latitude, 1);
        expect(h.target.longitude, -2);
        expect(h.target.lastSeen, original.lastSeen);
        expect(h.connector.contacts, hasLength(2));

        h.radioContacts[0] = original.copyWith(
          latitude: 3,
          longitude: -4,
          lastSeen: original.lastSeen.add(const Duration(seconds: 1)),
        );
        await h.connector.getContacts(preserveExisting: true);
        expect(h.target.telemetryFixAt, isNull);
        expect(h.target.latitude, 3);
        expect(h.target.longitude, -4);
        expect(h.target.lastSeen, h.radioContacts[0].lastSeen);
      });
    }

    test('U11a: flag writes keep the advert timestamp and local GPS metadata', () async {
      final advertAt = h.target.lastSeen;
      expect(h.connector.updateContactLocationFromTelemetry(
        h.targetHex, 1, -2, expectedNodeKey: h.node,
      ), isTrue);
      final fixAt = h.target.telemetryFixAt;
      await h.connector.setContactFlags(h.target, isFavorite: true);
      final update = h.sent.singleWhere((frame) => frame.first == cmdAddUpdateContact);
      expect(ByteData.sublistView(update, 132, 136).getUint32(0, Endian.little),
          advertAt.millisecondsSinceEpoch ~/ 1000);
      expect(h.target.telemetryFixAt, fixAt);
      expect(h.target.latitude, 1);
      expect(h.target.lastSeen, advertAt);
      expect(h.target.isFavorite, isTrue);
    });

    test('U11a: held GPS cannot resurrect a contact omitted by the node', () async {
      final original = h.target;
      expect(h.connector.updateContactLocationFromTelemetry(
        h.targetHex, 1, -2, expectedNodeKey: h.node,
      ), isTrue);
      await h.settle();
      h.radioContacts.removeAt(0);
      await h.connector.getContacts();
      expect(h.connector.getContactByPubKeyHex(h.targetHex), isNull);
      expect(h.connector.contacts.single.publicKeyHex, h.otherHex);
      // The old fix must also be forgotten after END, even if the radio
      // re-adds the very same contact and advert timestamp in another sync.
      h.radioContacts.insert(0, original);
      await h.connector.getContacts();
      expect(h.target.telemetryFixAt, isNull);
      expect(h.target.hasLocation, isFalse);
    });

    test('U11a: repeated raw adverts retain GPS without bumping contact revision', () async {
      final original = h.target;
      expect(h.connector.updateContactLocationFromTelemetry(
        h.targetHex, 1, -2, expectedNodeKey: h.node,
      ), isTrue);
      final fixAt = h.target.telemetryFixAt;
      final revision = h.connector.contactsRevision;
      Uint8List advertFrame(DateTime at) {
        final payload = BufferWriter()
          ..writeBytes(original.publicKey)
          ..writeUInt32LE(at.millisecondsSinceEpoch ~/ 1000)
          ..writeBytes(Uint8List(64)) // Synthetic, not a verified signature.
          ..writeByte(original.type | 0x10 | 0x80)
          ..writeInt32LE(3000000)
          ..writeInt32LE(-4000000)
          ..writeCString(original.name, maxNameSize);
        return Uint8List.fromList([
          pushCodeLogRxData, 40, 196, (payloadTypeADVERT << 2) | 1, 0,
          ...payload.toBytes(),
        ]);
      }
      h.connector.handleFrameForTest(advertFrame(original.lastSeen));
      h.connector.handleFrameForTest(advertFrame(
        original.lastSeen.subtract(const Duration(seconds: 1)),
      ));
      expect(h.connector.contactsRevision, revision);
      expect(h.target.telemetryFixAt, fixAt);
      expect(h.target.latitude, 1);
      expect(h.target.lastSeen, original.lastSeen);
      h.connector.handleFrameForTest(advertFrame(
        original.lastSeen.add(const Duration(seconds: 1)),
      ));
      expect(h.target.telemetryFixAt, isNull);
      expect(h.target.latitude, 3);
      expect(h.target.longitude, -4);
      expect(h.target.path, original.path);
      expect(h.target.pathHashWidth, original.pathHashWidth);
    });

    test('U11a: wrong node, absent contact and invalid GPS have no side effects', () async {
      final original = h.target;
      expect(h.connector.updateContactLocationFromTelemetry(
        h.targetHex, 1, -2, expectedNodeKey: 'another-node',
      ), isFalse);
      expect(h.connector.updateContactLocationFromTelemetry(
        pubKeyToHex(_linkedKey), 1, -2, expectedNodeKey: h.node,
      ), isFalse);
      for (final pair in [(0.0, 0.0), (91.0, 2.0), (1.0, double.nan)]) {
        expect(h.connector.updateContactLocationFromTelemetry(
          h.targetHex, pair.$1, pair.$2, expectedNodeKey: h.node,
        ), isFalse);
      }
      expect(h.target, same(original));
      expect(h.sent, isEmpty);
    });

    for (final width in [1, 2, 3]) {
      test('known contact route width=$width and freshest flags survive path/favorite writes', () async {
        final target = h.target;
        final route = Uint8List.fromList(List<int>.generate(width * 2, (index) => 0x30 + index));
        await h.connector.setContactPath(target, route, 2, pathHashWidth: width, waitForAck: true);
        final frame = h.sent.singleWhere((f) => f.first == cmdAddUpdateContact);
        expect(frame[35], ((width - 1) << 6) | 2);
        expect(frame.sublist(36, 36 + route.length), route);
        final local = h.connector.contacts.singleWhere((c) => c.publicKeyHex == h.targetHex);
        expect(local.pathHashWidth, width);
        expect(local.pathLength, 2);
        expect(local.path, route);
        // The radio's GET_CONTACT_BY_KEY snapshot is authoritative for flags.
        h.radioContacts[0] = local.copyWith(flags: contactFlagTeleBase | contactFlagTeleLoc);
        h.sent.clear();
        await h.connector.setContactFlags(local, isFavorite: true);
        final update = h.sent.singleWhere((f) => f.first == cmdAddUpdateContact);
        expect(update[34], contactFlagFavorite | contactFlagTeleBase | contactFlagTeleLoc);
        expect(update[35], ((width - 1) << 6) | 2);
        expect(update.sublist(36, 36 + route.length), route);
        expect(h.connector.contacts.singleWhere((c) => c.publicKeyHex == h.targetHex).isFavorite, isTrue);
      });
    }
  }, skip: sqliteProblem);
}
