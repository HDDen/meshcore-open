import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/helpers/backup_channel_restore.dart';
import 'package:meshcore_open/helpers/backup_contact_restore.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/models/channel_message.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/models/message.dart';
import 'package:meshcore_open/review_mode/review_frames.dart';
import 'package:meshcore_open/services/backup_import_planner.dart';
import 'package:meshcore_open/storage/channel_identity_store.dart';
import 'package:meshcore_open/storage/channel_message_store.dart';
import 'package:meshcore_open/storage/channel_store.dart';
import 'package:meshcore_open/storage/contact_store.dart';
import 'package:meshcore_open/storage/message_history_database.dart';
import 'package:meshcore_open/storage/message_history_storage.dart';
import 'package:meshcore_open/storage/message_store.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _publicKey = Uint8List.fromList(List.filled(32, 0xa1));
final _node = pubKeyToHex(_publicKey);

Channel _channel(int index, String name, int key) => Channel(
  index: index,
  name: name,
  psk: Uint8List.fromList(List.filled(16, key)),
);

Contact _contact(int key, String name, {int pathLength = 1}) => Contact(
  publicKey: Uint8List.fromList(List.filled(32, key)),
  name: name,
  type: advTypeChat,
  pathLength: pathLength,
  path: Uint8List.fromList(pathLength < 0 ? [] : [0x77]),
  lastSeen: DateTime.utc(2026),
);

Uint8List _contactFrame(Contact contact) => buildUpdateContactPathFrame(
  contact.publicKey,
  contact.path,
  contact.pathLength,
  type: contact.type,
  flags: contact.flags,
  name: contact.name,
  lastAdvert: contact.lastSeen,
  lastModified: contact.lastSeen,
)..[0] = respCodeContact;

class _NoPreferencesDirectory extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async {
    throw MissingPluginException('synthetic backup restore preferences');
  }
}

class _Radio {
  _Radio() {
    connector.setReconnectContextForTest(
      transport: MeshCoreTransportType.tcp,
      state: MeshCoreConnectionState.connected,
    );
    connector.setFrameWriterForTest(_write);
  }

  final connector = MeshCoreConnector();
  final slots = {
    0: _channel(0, 'Unrelated', 1),
    2: _channel(2, 'Current', 2),
  };
  final reads = <int>[];
  final writes = <Channel>[];
  final contacts = {
    _contact(0x81, 'Current contact').publicKeyHex:
        _contact(0x81, 'Current contact'),
  };
  final contactWrites = <Contact>[];
  bool overwriteOldest = false;
  bool incompleteContactList = false;
  Contact? newlyLearnedContact;
  String? rejectedContactKey;
  final firstWrite = Completer<Channel>();
  bool holdFirstReply = false;
  bool ignoreAcceptedWrites = false;
  int? rejectSlot;

  Future<void> start() async {
    await connector.refreshDeviceInfo();
    await sync();
    reads.clear();
  }

  Future<void> sync() async {
    final done = Completer<void>();
    void observe() {
      if (connector.hasLoadedChannels &&
          !connector.isSyncingChannels &&
          !done.isCompleted) {
        done.complete();
      }
    }

    connector.addListener(observe);
    try {
      await connector.getChannels(force: true);
      observe();
      await done.future.timeout(const Duration(seconds: 5));
    } finally {
      connector.removeListener(observe);
    }
  }

  Future<void> syncContacts() async {
    await connector.getContacts(preserveExisting: true);
    expect(connector.hasLoadedContacts, isTrue);
    expect(connector.isLoadingContacts, isFalse);
  }

  void acknowledge(Channel channel) {
    if (!ignoreAcceptedWrites) slots[channel.index] = channel;
    connector.handleFrameForTest(ReviewFrames.ok());
  }

  Future<void> _write(Uint8List frame) async {
    switch (frame.first) {
      case cmdDeviceQuery:
        connector.handleFrameForTest([respCodeDeviceInfo, 8, 16, 4]);
      case cmdAppStart:
        connector.handleFrameForTest(ReviewFrames.selfInfo(
          publicKey: _publicKey,
          name: 'Restore target',
          latitudeE6: 0,
          longitudeE6: 0,
          frequencyHz: 869495000,
          bandwidthHz: 125000,
          spreadingFactor: 7,
          codingRate: 5,
          txPowerDbm: 14,
          maxTxPowerDbm: 22,
        ));
      case cmdGetBattAndStorage:
        connector.handleFrameForTest([respCodeBattAndStorage, 0x10, 0x0e]);
      case cmdGetCustomVar:
        connector.handleFrameForTest([respCodeCustomVars, 0]);
      case cmdGetAutoAddConfig:
        connector.handleFrameForTest([
          respCodeAutoAddConfig,
          if (overwriteOldest) autoAddOverwriteOldestFlag else 0,
        ]);
      case cmdGetContacts:
        connector.handleFrameForTest(ReviewFrames.contactsStart(
          contacts.length + (incompleteContactList ? 1 : 0),
        ));
        for (final contact in contacts.values) {
          connector.handleFrameForTest(_contactFrame(contact));
        }
        connector.handleFrameForTest([respCodeEndOfContacts, 0, 0, 0, 0]);
      case cmdGetContactByKey:
        final key = pubKeyToHex(frame.sublist(1, 1 + pubKeySize));
        final learned = newlyLearnedContact;
        if (learned?.publicKeyHex == key) contacts[key] = learned!;
        final contact = contacts[key];
        connector.handleFrameForTest(
          contact == null ? ReviewFrames.err(errCodeNotFound) : _contactFrame(contact),
        );
      case cmdAddUpdateContact:
        final response = Uint8List.fromList(frame)..[0] = respCodeContact;
        final contact = Contact.fromFrame(response)!;
        contactWrites.add(contact);
        if (contact.publicKeyHex == rejectedContactKey) {
          connector.handleFrameForTest(ReviewFrames.err(errCodeTableFull));
        } else {
          contacts[contact.publicKeyHex] = contact;
          connector.handleFrameForTest(ReviewFrames.ok());
        }
      case cmdGetChannel:
        final index = frame[1];
        reads.add(index);
        final channel = slots[index] ?? Channel.empty(index);
        connector.handleFrameForTest(ReviewFrames.channelInfo(
          index: index,
          name: channel.name,
          psk: channel.psk,
        ));
      case cmdSetChannel:
        final response = Uint8List.fromList(frame)..[0] = respCodeChannelInfo;
        final channel = Channel.fromFrame(response)!;
        writes.add(channel);
        if (!firstWrite.isCompleted) firstWrite.complete(channel);
        if (holdFirstReply && writes.length == 1) return;
        if (channel.index == rejectSlot) {
          connector.handleFrameForTest(ReviewFrames.err(6));
        } else {
          acknowledge(channel);
        }
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final storage = MessageHistoryStorage.instance;
  late PathProviderPlatform savedPaths;
  late _Radio radio;

  Future<List<Channel>> cachedChannels([String? node]) =>
      (ChannelStore()..setPublicKeyHex = node ?? _node).loadChannels();

  setUp(() async {
    savedPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _NoPreferencesDirectory();
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
    await storage.resetForTesting();
    await storage.initializeAndMigrate(
      databaseFactory: () => MessageHistoryDatabase.withExecutor(
        NativeDatabase.memory(),
      ),
    );
    expect(storage.hasDatabase, isTrue);
    ChannelIdentities.instance.resetForTesting();
    await ChannelIdentities.instance.load();
    radio = _Radio();
    await radio.start();
  });

  tearDown(() async {
    radio.connector.resetConnectionHandshakeForTest();
    radio.connector.resetSyncProgressForTest();
    radio.connector.dispose();
    ChannelIdentities.instance.resetForTesting();
    await storage.resetForTesting();
    PrefsManager.reset();
    PathProviderPlatform.instance = savedPaths;
  });

  test('a backup captures the active node without requesting radio frames', () async {
    final otherNode = List.filled(32, 'b2').join();
    await (ChannelStore()..setPublicKeyHex = otherNode).saveChannels([
      _channel(0, 'Other node only', 9),
    ]);
    final snapshot = radio.connector.snapshotChannelBackup()!;
    expect(snapshot.sourcePublicKey, _node);
    expect(snapshot.channelCount, 2);
    expect(snapshot.fileName, contains('Restore target'));
    final plan = await const BackupImportPlanner().inspect(
      await snapshot.encode(password: ''),
      password: '',
    );
    expect(plan.channels!.map((channel) => channel.name),
        ['Unrelated', 'Current']);
    expect(radio.reads, isEmpty);
    expect(radio.writes, isEmpty);
    radio.connector.resetSyncProgressForTest();
    expect(radio.connector.snapshotChannelBackup(), isNull);
  });

  group('contact backup restore', () {
    test('keeps existing keys and saves only the confirmed new contact', () async {
      await radio.syncContacts();
      final current = _contact(0x81, 'Different name in the backup');
      final added = _contact(0x82, 'New contact');
      final history = MessageStore()..setPublicKeyHex = _node;
      await history.saveMessages(current.publicKeyHex, [
        Message(
          senderKey: current.publicKey,
          text: 'Existing conversation',
          timestamp: DateTime.utc(2026),
          isOutgoing: false,
        ),
      ]);
      final preview = radio.connector.previewBackupContactRestore(
        sourcePublicKey: List.filled(32, 'be').join(),
        contacts: [current, added],
      )!;
      expect(preview.decisions.map((decision) => decision.action), [
        BackupContactAction.alreadyPresent,
        BackupContactAction.add,
      ]);
      expect(preview.decisions.last.usesFloodFallback, isTrue);
      expect(
        await radio.connector.restoreBackupContacts(preview),
        (confirmed: 1, status: BackupContactRestoreStatus.completed),
      );
      expect(radio.contactWrites.single.publicKeyHex, added.publicKeyHex);
      expect(radio.contactWrites.single.pathLength, -1);
      final cached = await (ContactStore()..setPublicKeyHex = _node).loadContacts();
      expect(cached.map((contact) => contact.name),
          unorderedEquals(['Current contact', 'New contact']));
      expect((await history.loadMessages(current.publicKeyHex)).single.text,
          'Existing conversation');
    });

    test('rejects overwrite-oldest and incomplete reads before any write', () async {
      await radio.syncContacts();
      final preview = radio.connector.previewBackupContactRestore(
        sourcePublicKey: _node,
        contacts: [_contact(0x82, 'New')],
      )!;
      radio.overwriteOldest = true;
      expect(
        await radio.connector.restoreBackupContacts(preview),
        (confirmed: 0, status: BackupContactRestoreStatus.overwriteUnsafe),
      );
      radio.overwriteOldest = false;
      radio.incompleteContactList = true;
      expect(
        await radio.connector.restoreBackupContacts(preview),
        (confirmed: 0, status: BackupContactRestoreStatus.syncFailed),
      );
      expect(radio.contactWrites, isEmpty);
      final cached = await (ContactStore()..setPublicKeyHex = _node).loadContacts();
      expect(cached.single.name, 'Current contact');
    });

    test('a key learned after preflight is never updated by restore', () async {
      await radio.syncContacts();
      final preview = radio.connector.previewBackupContactRestore(
        sourcePublicKey: _node,
        contacts: [_contact(0x82, 'From backup')],
      )!;
      radio.newlyLearnedContact = _contact(0x82, 'Just learned');
      expect(
        await radio.connector.restoreBackupContacts(preview),
        (confirmed: 0, status: BackupContactRestoreStatus.destinationChanged),
      );
      expect(radio.contactWrites, isEmpty);
      expect(radio.contacts[radio.newlyLearnedContact!.publicKeyHex]!.name,
          'Just learned');
    });

    test('a rejection stops later writes and persists the accepted prefix', () async {
      await radio.syncContacts();
      final rejected = _contact(0x83, 'Rejected');
      final preview = radio.connector.previewBackupContactRestore(
        sourcePublicKey: _node,
        contacts: [_contact(0x82, 'Added'), rejected, _contact(0x84, 'Later')],
      )!;
      radio.rejectedContactKey = rejected.publicKeyHex;
      expect(
        await radio.connector.restoreBackupContacts(preview),
        (confirmed: 1, status: BackupContactRestoreStatus.writeUnconfirmed),
      );
      expect(radio.contactWrites.map((contact) => contact.name), ['Added', 'Rejected']);
      expect(radio.contactWrites.first.path, [0x77]);
      final cached = await (ContactStore()..setPublicKeyHex = _node).loadContacts();
      expect(cached.map((contact) => contact.name),
          unorderedEquals(['Current contact', 'Added']));
    });
  });

  test('confirmed rename keeps slot, history and the other node cache', () async {
    final history = ChannelMessageStore()
      ..setPublicKeyHex = _node
      ..registerChannel(radio.slots[2]!);
    await history.saveChannelMessages(2, [
      ChannelMessage(
        senderName: 'Alice',
        text: 'Stored before restore',
        timestamp: DateTime.utc(2026),
        isOutgoing: false,
        channelIndex: 2,
        messageId: 'prior-message',
      ),
    ]);
    final otherNode = List.filled(32, 'b2').join();
    await (ChannelStore()..setPublicKeyHex = otherNode).saveChannels([
      _channel(2, 'Other node', 3),
    ]);

    final preview = radio.connector.previewBackupChannelRestore([
      _channel(0, 'From backup', 2),
      _channel(1, 'Added', 4),
    ])!;
    radio.holdFirstReply = true;
    final operation = radio.connector.restoreBackupChannels(preview);
    final first = await radio.firstWrite.future.timeout(const Duration(seconds: 5));
    expect(radio.writes, hasLength(1));
    expect(first.index, 2);
    expect(first.name, 'From backup');
    expect(radio.slots[2]!.name, 'Current');
    expect((await cachedChannels()).map((channel) => channel.name),
        unorderedEquals(['Unrelated', 'Current']));
    expect(
      await radio.connector.restoreBackupChannels(preview),
      (confirmed: 0, status: BackupChannelRestoreStatus.destinationChanged),
    );
    radio.acknowledge(first);
    expect(
      await operation,
      (confirmed: 2, status: BackupChannelRestoreStatus.completed),
    );
    expect(radio.writes.map((channel) => channel.index), [2, 1]);
    expect(radio.reads, [0, 1, 2, 3, 0, 1, 2, 3]);
    expect((await cachedChannels()).map((channel) => channel.name),
        unorderedEquals(['Unrelated', 'From backup', 'Added']));
    expect((await cachedChannels(otherNode)).single.name, 'Other node');
    final restoredHistory = ChannelMessageStore()
      ..setPublicKeyHex = _node
      ..registerChannel(radio.slots[2]!);
    expect((await restoredHistory.loadChannelMessages(2)).single.text,
        'Stored before restore');
  });

  test('a change discovered on the preflight read requires a new preview', () async {
    final preview = radio.connector.previewBackupChannelRestore([
      _channel(1, 'Added', 4),
    ])!;
    radio.slots[1] = _channel(1, 'Changed elsewhere', 3);
    expect(
      await radio.connector.restoreBackupChannels(preview),
      (confirmed: 0, status: BackupChannelRestoreStatus.destinationChanged),
    );
    expect(radio.writes, isEmpty);
    expect((await cachedChannels()).map((channel) => channel.name),
        contains('Changed elsewhere'));
  });

  test('ERR stops remaining writes and resyncs confirmed changes', () async {
    final preview = radio.connector.previewBackupChannelRestore([
      _channel(0, 'From backup', 2),
      _channel(1, 'Rejected', 3),
      _channel(3, 'Skipped', 4),
    ])!;
    radio.rejectSlot = 1;
    expect(
      await radio.connector.restoreBackupChannels(preview),
      (confirmed: 1, status: BackupChannelRestoreStatus.writeUnconfirmed),
    );
    expect(radio.writes.map((channel) => channel.index), [2, 1]);
    expect(radio.reads, [0, 1, 2, 3, 0, 1, 2, 3]);
    expect((await cachedChannels()).map((channel) => channel.name),
        unorderedEquals(['Unrelated', 'From backup']));
  });

  test('the same node in a new session needs a new preview', () async {
    final preview = radio.connector.previewBackupChannelRestore([
      _channel(1, 'Added', 3),
    ])!;
    radio.connector.resetSyncProgressForTest();
    await radio.sync();
    radio.reads.clear();
    expect(
      await radio.connector.restoreBackupChannels(preview),
      (confirmed: 0, status: BackupChannelRestoreStatus.destinationChanged),
    );
    expect(radio.reads, isEmpty);
    expect(radio.writes, isEmpty);
  });

  test('OK without matching readback does not record a rename', () async {
    final previous = radio.slots[2]!;
    final preview = radio.connector.previewBackupChannelRestore([
      _channel(0, 'From backup', 2),
    ])!;
    radio.ignoreAcceptedWrites = true;
    expect(
      await radio.connector.restoreBackupChannels(preview),
      (confirmed: 1, status: BackupChannelRestoreStatus.syncFailed),
    );
    expect((await cachedChannels()).map((channel) => channel.name),
        unorderedEquals(['Unrelated', 'Current']));
    expect(ChannelIdentities.instance.namesOf(ChannelIdentity.of(previous)!),
        ['Current']);
  });

  test('confirmed rename keeps its alias when another slot has the old name',
      () async {
    radio.slots[3] = _channel(3, 'Current', 2);
    await radio.sync();
    final preview = radio.connector.previewBackupChannelRestore([
      _channel(0, 'From backup', 2),
    ])!;

    expect(
      await radio.connector.restoreBackupChannels(preview),
      (confirmed: 1, status: BackupChannelRestoreStatus.completed),
    );
    expect(radio.slots[3]!.name, 'Current');
    expect(radio.slots[2]!.name, 'From backup');
    expect(
      ChannelIdentities.instance.namesOf(ChannelIdentity.of(radio.slots[2]!)!),
      unorderedEquals(['From backup', 'Current']),
    );
  });
}
