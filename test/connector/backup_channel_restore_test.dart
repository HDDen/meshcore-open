import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/helpers/backup_channel_restore.dart';
import 'package:meshcore_open/helpers/backup_channel_settings.dart';
import 'package:meshcore_open/helpers/backup_contact_restore.dart';
import 'package:meshcore_open/helpers/backup_contact_settings.dart';
import 'package:meshcore_open/helpers/backup_node_profile.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/models/channel_message.dart';
import 'package:meshcore_open/models/community.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/models/contact_group.dart';
import 'package:meshcore_open/models/message.dart';
import 'package:meshcore_open/review_mode/review_frames.dart';
import 'package:meshcore_open/services/backup_file_codec.dart';
import 'package:meshcore_open/services/backup_import_planner.dart';
import 'package:meshcore_open/storage/channel_identity_store.dart';
import 'package:meshcore_open/storage/channel_message_store.dart';
import 'package:meshcore_open/storage/channel_order_store.dart';
import 'package:meshcore_open/storage/channel_settings_store.dart';
import 'package:meshcore_open/storage/channel_store.dart';
import 'package:meshcore_open/storage/community_store.dart';
import 'package:meshcore_open/storage/contact_store.dart';
import 'package:meshcore_open/storage/contact_settings_store.dart';
import 'package:meshcore_open/storage/contact_group_store.dart';
import 'package:meshcore_open/storage/message_history_database.dart';
import 'package:meshcore_open/storage/message_history_storage.dart';
import 'package:meshcore_open/storage/message_store.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:meshcore_open/storage/region_store.dart';
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
  final profileWrites = <List<int>>[];
  int defaultScopeReads = 0;
  List<int> defaultScopeReply = [respCodeDefaultFloodScope];
  int? rejectedProfileCommand;
  final contacts = {
    _contact(0x81, 'Current contact').publicKeyHex:
        _contact(0x81, 'Current contact'),
  };
  final contactWrites = <Contact>[];
  int contactReads = 0;
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
          frequencyHz: 869495,
          bandwidthHz: 125000,
          spreadingFactor: 7,
          codingRate: 5,
          txPowerDbm: 14,
          maxTxPowerDbm: 22,
        )..[47] = 0x03); // SELF_INFO contact flags, including a reserved bit.
      case cmdGetBattAndStorage:
        connector.handleFrameForTest([respCodeBattAndStorage, 0x10, 0x0e]);
      case cmdGetCustomVar:
        connector.handleFrameForTest([respCodeCustomVars, 0]);
      case cmdGetAutoAddConfig:
        connector.handleFrameForTest([
          respCodeAutoAddConfig,
          if (overwriteOldest) autoAddOverwriteOldestFlag else 0,
        ]);
      case cmdGetDefaultFloodScope:
        defaultScopeReads++;
        connector.handleFrameForTest(defaultScopeReply);
      case cmdGetContacts:
        contactReads++;
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
      case cmdSetAdvertName || cmdSetAdvertLatLon || cmdSetOtherParams ||
          cmdSetRadioParams || cmdSetRadioTxPower || cmdSetPathHashMode ||
          cmdSetDefaultFloodScope:
        profileWrites.add(List.of(frame));
        connector.handleFrameForTest(
          frame.first == rejectedProfileCommand ? ReviewFrames.err(6) : ReviewFrames.ok(),
        );
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

  test('node profile applies selected writes on ACK and preserves contact flags', () async {
    const name = BackupNodeProfilePart.nodeName;
    const position = BackupNodeProfilePart.position;
    const privacy = BackupNodeProfilePart.privacy;
    final captured = radio.connector.snapshotNodeProfileBackup({name, position, privacy})!;
    final initial = await const BackupImportPlanner().inspect(
      await captured.encode(password: ''), password: '', nodeProfileOnly: true,
    );
    expect(initial.nodeProfile!.nodeName, 'Restore target');
    expect(initial.nodeProfile!.position, (latitudeE6: 0, longitudeE6: 0));
    expect(radio.profileWrites, isEmpty);
    expect(radio.reads, isEmpty);

    final source = BackupNodeProfile.fromBackup(
      name: 'Restored',
      position: {'latitude': 55, 'longitude': 37},
      privacy: {'telemetryLocation': 1, 'advertLocation': 1},
    );
    final preview = radio.connector.previewBackupNodeProfile(source)!;
    radio.rejectedProfileCommand = cmdSetAdvertLatLon;
    expect(await radio.connector.restoreBackupNodeProfile(preview, {name, position, privacy}), (
      confirmed: 1, status: BackupNodeProfileStatus.writeUnconfirmed,
    ));
    expect(radio.profileWrites, [
      buildSetAdvertNameFrame('Restored'),
      buildSetAdvertLatLonFrame(55, 37),
    ]);
    expect(radio.connector.selfName, 'Restored');
    expect(radio.connector.selfLatitude, 0);
    expect(radio.connector.advertLocationPolicy, 0);
    expect(await radio.connector.restoreBackupNodeProfile(preview, {name, privacy}), (
      confirmed: 0, status: BackupNodeProfileStatus.destinationChanged,
    ));
    expect(radio.profileWrites, hasLength(2));

    expect(await radio.connector.restoreBackupNodeProfile(preview, {privacy}), (
      confirmed: 1, status: BackupNodeProfileStatus.completed,
    ));
    expect(radio.profileWrites.last, [cmdSetOtherParams, 0x03, 0x04, 1, 0]);
    expect(radio.connector.telemetryModeLoc, 1);
    expect(radio.connector.advertLocationPolicy, 1);
    expect(radio.connector.selfPublicKeyHex, _node);
    expect(radio.reads, isEmpty);
    expect(radio.writes, isEmpty);
  });

  test('radio restore keeps repeat and applies only ACK-confirmed fields', () async {
    const tuning = BackupNodeProfilePart.tuning;
    const power = BackupNodeProfilePart.txPower;
    const width = BackupNodeProfilePart.pathHashWidth;
    radio.connector.handleFrameForTest(Uint8List(82)
      ..[0] = respCodeDeviceInfo
      ..[1] = 10
      ..[2] = 16
      ..[3] = 4
      ..[80] = 1);

    final capture = radio.connector.snapshotNodeProfileBackup({tuning, width})!;
    final initial = await const BackupImportPlanner().inspect(
      await capture.encode(password: ''), password: '', nodeProfileOnly: true,
    );
    expect(initial.nodeProfile!.tuning?.clientRepeat, isTrue);
    expect(initial.nodeProfile!.pathHashByteWidth, 1);
    expect(initial.nodeProfile!.txPowerDbm, isNull);
    expect(radio.profileWrites, isEmpty);

    final source = BackupNodeProfile.fromBackup(radio: {
      'frequencyHz': 869495,
      'bandwidthHz': 250000,
      'spreadingFactor': 8,
      'codingRate': 6,
      'txPowerDbm': 17,
      'pathHashByteWidth': 3,
    });
    final preview = radio.connector.previewBackupNodeProfile(source)!;
    expect(preview.unavailable, isEmpty);
    expect(preview.changes.tuning?.clientRepeat, isTrue);
    radio.rejectedProfileCommand = cmdSetPathHashMode;
    expect(await radio.connector.restoreBackupNodeProfile(preview, {tuning, width}), (
      confirmed: 1, status: BackupNodeProfileStatus.writeUnconfirmed,
    ));
    expect(radio.profileWrites, [
      buildSetRadioParamsFrame(869495, 250000, 8, 6, clientRepeat: true),
      buildSetPathHashModeFrame(2),
    ]);
    expect(radio.connector.currentBwHz, 250000);
    expect(radio.connector.currentTxPower, 14);
    expect(radio.connector.pathHashByteWidth, 1);
    expect(radio.reads, isEmpty);

    radio.rejectedProfileCommand = null;
    final retry = radio.connector.previewBackupNodeProfile(source)!;
    expect(retry.changes.tuning, isNull);
    expect(await radio.connector.restoreBackupNodeProfile(retry, {power, width}), (
      confirmed: 2, status: BackupNodeProfileStatus.completed,
    ));
    expect(radio.profileWrites.skip(2), [
      buildSetRadioTxPowerFrame(17), buildSetPathHashModeFrame(2),
    ]);
    expect(radio.connector.currentTxPower, 17);
    expect(radio.connector.pathHashByteWidth, 3);
  });

  test('older radios accept tuning without a repeat byte and skip unsupported choices', () async {
    const tuning = BackupNodeProfilePart.tuning;
    const power = BackupNodeProfilePart.txPower;
    const width = BackupNodeProfilePart.pathHashWidth;
    final fields = {
      'frequencyHz': 869495,
      'bandwidthHz': 125000,
      'spreadingFactor': 8,
      'codingRate': 5,
      'txPowerDbm': 23,
      'pathHashByteWidth': 3,
    };
    final repeat = radio.connector.previewBackupNodeProfile(
      BackupNodeProfile.fromBackup(radio: {...fields, 'clientRepeat': true}),
    )!;
    expect(repeat.changes.isEmpty, isTrue);
    expect(repeat.unavailable, {tuning, power, width});

    final source = BackupNodeProfile.fromBackup(radio: fields);
    final legacy = radio.connector.previewBackupNodeProfile(source)!;
    expect(legacy.unavailable, {power, width});
    expect(await radio.connector.restoreBackupNodeProfile(legacy, {tuning, power, width}), (
      confirmed: 1, status: BackupNodeProfileStatus.completed,
    ));
    expect(radio.profileWrites, [buildSetRadioParamsFrame(869495, 125000, 8, 5)]);

    radio.connector.handleFrameForTest([respCodeDeviceInfo, 10, 16, 4]);
    final unknown = radio.connector.previewBackupNodeProfile(source)!;
    expect(unknown.changes.isEmpty, isTrue);
    expect(unknown.unavailable, {tuning, power, width});
  });

  test('default scope uses the exact radio key and changes only after ACK', () async {
    const part = BackupNodeProfilePart.defaultFloodScope;
    final key = 'a7' * 16;
    final otherKey = 'f1' * 16;
    radio.defaultScopeReply = [
      respCodeDefaultFloodScope, 0x23, 0x75, 0x6b, // #uk
      ...List.filled(28, 0),
      ...List.filled(16, 0xa7),
    ];
    expect(await radio.connector.getDefaultRegionScope(), 'uk');
    final snapshot = radio.connector.snapshotNodeProfileBackup({part})!;
    final plan = await const BackupImportPlanner().inspect(
      await snapshot.encode(password: ''), password: '', nodeProfileOnly: true,
    );
    final captured = plan.nodeProfile!;
    expect(captured.defaultFloodScope, (name: '#uk', keyHex: key));
    expect(radio.connector.previewBackupNodeProfile(captured)!.changes.isEmpty, isTrue);

    final source = BackupNodeProfile.fromBackup(radio: {
      'defaultFloodScope': '#uk',
      'defaultFloodScopeKey': otherKey,
    });
    final preview = radio.connector.previewBackupNodeProfile(source)!;
    expect(preview.changes.defaultFloodScope, source.defaultFloodScope);
    radio.rejectedProfileCommand = cmdSetDefaultFloodScope;
    expect(await radio.connector.restoreBackupNodeProfile(preview, {part}), (
      confirmed: 0, status: BackupNodeProfileStatus.writeUnconfirmed,
    ));
    expect(radio.connector.previewBackupNodeProfile(captured)!.changes.isEmpty, isTrue);

    radio.rejectedProfileCommand = null;
    expect(await radio.connector.restoreBackupNodeProfile(preview, {part}), (
      confirmed: 1, status: BackupNodeProfileStatus.completed,
    ));
    final expected = [
      cmdSetDefaultFloodScope, 0x23, 0x75, 0x6b,
      ...List.filled(28, 0),
      ...List.filled(16, 0xf1),
    ];
    expect(radio.profileWrites, [expected, expected]);
    expect(radio.connector.previewBackupNodeProfile(source)!.changes.isEmpty, isTrue);
    expect(await radio.connector.restoreBackupNodeProfile(preview, {part}), (
      confirmed: 0, status: BackupNodeProfileStatus.destinationChanged,
    ));

    final cleared = BackupNodeProfile.fromBackup(radio: {'defaultFloodScope': ''});
    final clear = radio.connector.previewBackupNodeProfile(cleared)!;
    expect(await radio.connector.restoreBackupNodeProfile(clear, {part}), (
      confirmed: 1, status: BackupNodeProfileStatus.completed,
    ));
    expect(radio.profileWrites.last, [cmdSetDefaultFloodScope]);
    expect(radio.connector.defaultRegionScopeLabel, isNull);
    expect(radio.connector.previewBackupNodeProfile(cleared)!.changes.isEmpty, isTrue);
    expect(radio.defaultScopeReads, 1);
  });

  test('a truncated default scope reply does not establish an unset scope', () async {
    const part = BackupNodeProfilePart.defaultFloodScope;
    final source = BackupNodeProfile.fromBackup(radio: {'defaultFloodScope': 'uk'});
    radio.defaultScopeReply = [respCodeDefaultFloodScope, 0x75];
    await expectLater(radio.connector.getDefaultRegionScope(), throwsFormatException);
    expect(radio.connector.availableBackupRadioParts, isNot(contains(part)));
    expect(radio.connector.previewBackupNodeProfile(source)!.unavailable, {part});
    expect(radio.profileWrites, isEmpty);

    radio.defaultScopeReply = [respCodeDefaultFloodScope];
    expect(await radio.connector.getDefaultRegionScope(), '');
    expect(radio.connector.availableBackupRadioParts, contains(part));
    final preview = radio.connector.previewBackupNodeProfile(source)!;
    expect(preview.before.defaultFloodScope, emptyDefaultFloodScope);
    expect(preview.changes.defaultFloodScope, source.defaultFloodScope);
  });

  test('a backup captures the active node without requesting radio frames', () async {
    final otherNode = List.filled(32, 'b2').join();
    await (ChannelStore()..setPublicKeyHex = otherNode).saveChannels([
      _channel(0, 'Other node only', 9),
    ]);
    final contactReads = radio.contactReads;
    final snapshot = (await radio.connector.snapshotNodeBackup(
      includeChannels: true,
      includeContacts: false,
    ))!;
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
    expect(radio.contactReads, contactReads);
    expect(radio.writes, isEmpty);
    radio.connector.resetSyncProgressForTest();
    expect(await radio.connector.snapshotNodeBackup(
      includeChannels: true,
      includeContacts: false,
    ), isNull);
  });

  test('history import checks the full source key and writes only to SQLite',
      () async {
    final id = radio.slots[2]!.storageId;
    final scope = _node.substring(0, 10);
    Future<BackupImportPlan> inspect(String node) async {
      final contents = await const BackupFileCodec().encode({
        'format': BackupFileCodec.payloadFormat,
        'version': BackupFileCodec.formatVersion,
        'sourcePublicKey': node,
        'items': ['channelHistory'],
        'sections': {
          'channels': {
            'preferences': {
              'channel_messages_${scope}_$id': [
                {
                  'messageId': 'imported',
                  'text': 'Imported history',
                  'senderName': 'Sender',
                  'timestamp': 1700000000000,
                  'isOutgoing': false,
                  'status': ChannelMessageStatus.sent.index,
                  'channelIndex': 1,
                },
              ],
            },
          },
        },
      }, password: '');
      return const BackupImportPlanner().inspect(
        contents,
        password: '',
        messageHistoryOnly: true,
      );
    }

    final foreign = await inspect(scope.padRight(64, 'b'));
    expect(radio.connector.previewBackupMessageHistory(foreign.messageHistory!), isNull);
    final source = (await inspect(_node)).messageHistory!;
    final preview = radio.connector.previewBackupMessageHistory(source)!;
    expect(preview.channelTargets.keys, [2]);
    expect(await radio.connector.restoreBackupMessageHistory(preview), 1);
    final messages = await radio.connector.loadLatestPersistedChannelMessages(
      2,
      limit: 10,
    );
    expect(messages.single.text, 'Imported history');
    expect(messages.single.channelIndex, 2);
    final snapshot = (await radio.connector.snapshotMessageHistoryBackup(
      includeDirect: false,
      includeChannels: true,
    ))!;
    final restored = await const BackupImportPlanner().inspect(
      await snapshot.encode(password: ''),
      password: '',
      messageHistoryOnly: true,
    );
    expect(restored.messageHistory!.direct, isEmpty);
    expect(restored.messageHistory!.channels.keys, [id]);
    expect(
      restored.messageHistory!.channels[id]!.single['messageId'],
      'imported',
    );
    expect(radio.reads, isEmpty);
    expect(radio.writes, isEmpty);
    expect(radio.contactWrites, isEmpty);

    radio.connector.resetSyncProgressForTest();
    expect(await radio.connector.restoreBackupMessageHistory(preview), isNull);
    expect(await radio.connector.snapshotMessageHistoryBackup(
      includeDirect: false,
      includeChannels: true,
    ), isNull);
  });

  test('contact group backup preserves local groups and rejects a stale preview',
      () async {
    final groups = ContactGroupStore()..setPublicKeyHex = _node;
    final existing = ContactGroup(name: 'Local group', memberKeys: ['a2' * 32]);
    await groups.saveGroups([existing]);
    final reads = radio.contactReads;
    final snapshot = (await radio.connector.snapshotNodeBackup(
      includeChannels: false,
      includeContacts: false,
      includeContactGroups: true,
    ))!;
    final plan = await const BackupImportPlanner().inspect(
      await snapshot.encode(password: ''),
      password: '',
      contactGroupsOnly: true,
    );
    expect(plan.contactGroups!.single.memberKeys, existing.memberKeys);

    final incoming = [
      ContactGroup(name: 'local GROUP', memberKeys: ['a3' * 32]),
      ContactGroup(name: 'Imported group', memberKeys: ['a4' * 32]),
    ];
    final stale = (await radio.connector.previewBackupContactGroups(incoming))!;
    final edited = ContactGroup(name: 'Just added', memberKeys: ['a5' * 32]);
    await groups.saveGroups([existing, edited]);
    expect(await radio.connector.restoreBackupContactGroups(stale), isNull);
    expect(radio.connector.contactGroupsBackupRevision, 0);
    final preview = (await radio.connector.previewBackupContactGroups(incoming))!;
    expect(preview.skipped, 1);
    expect(await radio.connector.restoreBackupContactGroups(preview), 1);
    expect(radio.connector.contactGroupsBackupRevision, 1);
    final saved = await groups.loadGroups();
    expect(saved.map((group) => group.name), [
      'Local group', 'Just added', 'Imported group',
    ]);
    expect(saved.first.memberKeys, existing.memberKeys);
    expect(saved.last.memberKeys, ['a4' * 32]);
    expect(radio.reads, isEmpty);
    expect(radio.writes, isEmpty);
    expect(radio.contactReads, reads);
    expect(radio.contactWrites, isEmpty);
  });

  test('channel settings and order follow PSK and keep existing choices', () async {
    final channels = radio.connector.channels;
    final first = channels.singleWhere((channel) => channel.index == 0);
    final second = channels.singleWhere((channel) => channel.index == 2);
    final contactReads = radio.contactReads;
    await PrefsManager.instance.setStringList(RegionStore.key, ['#north']);
    final local = ChannelSettingsStore()..setPublicKeyHex = _node;
    local.replaceChannels(channels);
    await local.saveMCOtxtEnabled(first.index, true);
    final foreign = ChannelSettingsStore()..setPublicKeyHex = 'bb' * 32;
    foreign.replaceChannels(channels);
    await foreign.saveUrlImagesEnabled(first.index, false);
    await radio.connector.loadChannelSettings(
      channelBindings: channels,
      allowLegacyMigration: false,
    );
    expect(radio.connector.isChannelMCOtxtEnabled(first.index), isTrue);
    expect(await local.loadUrlImagesChoice(first.index), isFalse);

    final source = BackupChannelSettings({
      (first.storageId!, BackupChannelOption.smaz): true,
      (first.storageId!, BackupChannelOption.urlImages): true,
      (second.storageId!, BackupChannelOption.urlImages): true,
      (second.storageId!, BackupChannelOption.region): '#north',
      (second.storageId!, BackupChannelOption.cyr2latProfile): 'unknown',
    }, [second.storageId!, first.storageId!]);
    final stale = (await radio.connector.previewBackupChannelSettings(source))!;
    final secondBinding = (slot: second.index, id: second.storageId!, name: second.name);
    expect(stale.writes, {
      (secondBinding, BackupChannelOption.urlImages): true,
      (secondBinding, BackupChannelOption.region): '#north',
    });
    expect(stale.order.map((channel) => channel.slot), [2, 0]);
    await local.saveUrlImagesEnabled(2, false);
    expect(await radio.connector.restoreBackupChannelSettings(stale), isNull);
    expect(radio.connector.getChannelRegion(2), isEmpty);

    final preview = (await radio.connector.previewBackupChannelSettings(source))!;
    expect(preview.count, 2);
    expect(preview.order.map((channel) => channel.slot), [2, 0]);
    expect(await radio.connector.restoreBackupChannelSettings(preview), (
      count: 2, completed: true,
    ));
    expect(radio.connector.getChannelRegion(2), '#north');
    expect(radio.connector.isChannelMCOtxtEnabled(0), isTrue);
    expect(radio.connector.isChannelSmazEnabled(0), isFalse);
    expect(await local.loadUrlImagesChoice(2), isFalse);
    expect(await foreign.loadUrlImagesChoice(0), isFalse);
    final order = ChannelOrderStore()..setPublicKeyHex = _node;
    expect(await order.loadChannelOrder(), [2, 0]);
    expect(radio.connector.channels.map((channel) => channel.index), [2, 0]);
    final savedOrder = (await radio.connector.previewBackupChannelSettings(
      BackupChannelSettings({}, [first.storageId!, second.storageId!]),
    ))!;
    expect(savedOrder.order, isEmpty);
    expect(savedOrder.skipped, 1);

    final snapshot = (await radio.connector.snapshotNodeBackup(
      includeChannels: false,
      includeContacts: false,
      includeChannelSettings: true,
    ))!;
    final exported = await const BackupImportPlanner().inspect(
      await snapshot.encode(password: ''),
      password: '',
      channelSettingsOnly: true,
    );
    final settings = exported.channelSettings!;
    expect(settings.order, [second.storageId, first.storageId]);
    expect(settings.values[(second.storageId, BackupChannelOption.region)], '#north');
    expect(settings.values[(second.storageId, BackupChannelOption.urlImages)], isFalse);
    expect(settings.values[(first.storageId, BackupChannelOption.urlImages)], isNull);
    expect(radio.reads, isEmpty);
    expect(radio.writes, isEmpty);
    expect(radio.contactReads, contactReads);
    expect(radio.contactWrites, isEmpty);
  });

  test('contact options restore into SQLite without replacing a local codec', () async {
    final first = radio.contacts.keys.single;
    final second = _contact(0x82, 'Other contact');
    radio.contacts[second.publicKeyHex] = second;
    await radio.syncContacts();
    final contactReads = radio.contactReads;
    final local = ContactSettingsStore()..setPublicKeyHex = _node;
    final foreign = ContactSettingsStore()..setPublicKeyHex = 'bb' * 32;
    await radio.connector.setContactMCOtxtEnabled(first, true);
    await foreign.saveSmazEnabled(first, true);
    expect(radio.connector.isContactUrlImagesEnabled(first), isFalse);
    expect(radio.connector.isContactCyr2LatEnabled(second.publicKeyHex), isFalse);

    final missing = '93' * 32;
    final source = BackupContactSettings({
      (first, 'smaz_enabled'): '1',
      (first, 'url_images_enabled'): '1',
      (second.publicKeyHex, 'url_images_enabled'): '1',
      (second.publicKeyHex, 'cyr2lat_enabled'): '1',
      (second.publicKeyHex, 'cyr2lat_profile'): 'missing-profile',
      (missing, 'url_images_enabled'): '1',
    });
    final stale = radio.connector.previewBackupContactSettings(source)!;
    expect(stale.additions.values, hasLength(3));
    await local.saveUrlImagesEnabled(second.publicKeyHex, false);
    expect(await radio.connector.restoreBackupContactSettings(stale), isNull);
    expect(await local.loadUrlImagesChoice(first), isNull);

    final preview = radio.connector.previewBackupContactSettings(source)!;
    expect(preview.skipped, 4);
    expect(await radio.connector.restoreBackupContactSettings(preview), 2);
    expect(radio.connector.isContactMCOtxtEnabled(first), isTrue);
    expect(radio.connector.isContactSmazEnabled(first), isFalse);
    expect(radio.connector.isContactUrlImagesEnabled(first), isTrue);
    expect(radio.connector.isContactCyr2LatEnabled(second.publicKeyHex), isTrue);
    expect(await local.loadUrlImagesChoice(second.publicKeyHex), isFalse);
    expect(await foreign.loadUrlImagesChoice(first), isNull);
    expect(await local.loadUrlImagesChoice(missing), isNull);

    final snapshot = (await radio.connector.snapshotNodeBackup(
      includeChannels: false,
      includeContacts: false,
      includeContactSettings: true,
    ))!;
    final exported = await const BackupImportPlanner().inspect(
      await snapshot.encode(password: ''),
      password: '',
      contactSettingsOnly: true,
    );
    final values = exported.contactSettings!.values;
    expect(values[(first, 'mcotxt_enabled')], '1');
    expect(values[(second.publicKeyHex, 'url_images_enabled')], '0');
    expect(values[(second.publicKeyHex, 'cyr2lat_profile')], isNull);
    expect(radio.reads, isEmpty);
    expect(radio.writes, isEmpty);
    expect(radio.contactReads, contactReads);
    expect(radio.contactWrites, isEmpty);
  });

  test('communities restore by shared key and preserve the current node profile', () async {
    Community community(String id, String name, int key, List<String> hashtags) =>
        Community(
          id: id,
          name: name,
          secret: Uint8List.fromList(List.filled(32, key)),
          createdAt: DateTime.utc(2026),
          hashtagChannels: hashtags,
        );

    final active = CommunityStore()..setPublicKeyHex = _node;
    final other = CommunityStore()..setPublicKeyHex = 'bb' * 32;
    final local = community('same-id', 'Local', 1, ['local']);
    final otherProfile = community('other', 'Other profile', 8, []);
    await active.saveCommunities([local]);
    await other.saveCommunities([otherProfile]);
    final contactReads = radio.contactReads;

    final snapshot = (await radio.connector.snapshotNodeBackup(
      includeChannels: false,
      includeContacts: false,
      includeCommunities: true,
    ))!;
    expect(snapshot.containsCommunityKeys, isTrue);
    final exported = await const BackupImportPlanner().inspect(
      await snapshot.encode(password: ''),
      password: '',
      communitiesOnly: true,
    );
    expect(exported.communities!.map((item) => item.toJson()), [local.toJson()]);

    final imported = community('same-id', 'Imported', 2, ['weather']);
    final incoming = [
      community('old-id', 'Old name', 1, ['old']),
      imported,
      community('another-id', 'Duplicate', 2, []),
    ];
    final stale = (await radio.connector.previewBackupCommunities(incoming))!;
    final concurrent = community('edited', 'Added after preview', 3, []);
    await active.saveCommunities([local, concurrent]);
    expect(await radio.connector.restoreBackupCommunities(stale), isNull);
    expect(radio.connector.communitiesBackupRevision, 0);

    final preview = (await radio.connector.previewBackupCommunities(incoming))!;
    expect(preview.skipped, 2);
    expect(preview.added.single.id, isNot(local.id));
    expect(await radio.connector.restoreBackupCommunities(preview), 1);
    expect(await radio.connector.restoreBackupCommunities(preview), isNull);
    expect(radio.connector.communitiesBackupRevision, 1);
    final saved = await active.loadCommunities();
    expect(saved.map((item) => item.toJson()), [
      local.toJson(),
      concurrent.toJson(),
      {...imported.toJson(), 'id': preview.added.single.id},
    ]);
    expect((await other.loadCommunities()).single.toJson(), otherProfile.toJson());
    expect(radio.reads, isEmpty);
    expect(radio.writes, isEmpty);
    expect(radio.contactReads, contactReads);
    expect(radio.contactWrites, isEmpty);
  });

  test('discovery backup merges into the active profile without radio commands',
      () async {
    await radio.syncContacts();
    final reads = radio.contactReads;
    final existing = _contact(0x81, 'Already on radio');
    final found = _contact(0x92, 'Found locally');
    final imported = _contact(0x93, 'From another profile');
    void hear(Contact contact) => radio.connector.recordZeroHopDiscoveredContact(
      publicKey: contact.publicKey,
      type: advTypeRepeater,
      name: contact.name,
    );
    hear(found);

    final snapshot = (await radio.connector.snapshotNodeBackup(
      includeChannels: false,
      includeContacts: false,
      includeDiscoveredContacts: true,
    ))!;
    final saved = await const BackupImportPlanner().inspect(
      await snapshot.encode(password: ''),
      password: '',
      discoveredContactsOnly: true,
    );
    final savedRows = jsonDecode(saved.discoveredContactsJson!) as List<dynamic>;
    expect(savedRows.map((row) => row['name']), contains('Found locally'));
    expect(
      savedRows.singleWhere((row) => row['name'] == 'Found locally'),
      isNot(contains('path')),
    );

    final source = jsonEncode([
      for (final contact in [existing, found, imported])
        {
          'publicKey': base64Encode(contact.publicKey),
          'name': contact.name,
          'type': advTypeRepeater,
          'lastSeen': 1700000000000,
          'isActive': true,
        },
    ]);
    final stale = radio.connector.previewBackupDiscoveredContacts(source)!;
    hear(_contact(0x94, 'Heard after preview'));
    expect(await radio.connector.restoreBackupDiscoveredContacts(stale), isNull);
    final preview = radio.connector.previewBackupDiscoveredContacts(source)!;
    expect(preview.contacts.single.publicKeyHex, imported.publicKeyHex);
    expect(await radio.connector.restoreBackupDiscoveredContacts(preview), 1);
    final live = radio.connector.discoveredContacts.singleWhere(
      (contact) => contact.publicKeyHex == imported.publicKeyHex,
    );
    expect(live.isActive, isFalse);
    expect(radio.connector.knownContactKeys, isNot(contains(imported.publicKeyHex)));
    final persisted = (await storage.loadDiscoveredContacts()).map(
      (json) => jsonDecode(json)['name'],
    );
    expect(persisted, containsAll(['Found locally', 'Heard after preview', imported.name]));
    expect(radio.contactReads, reads);
    expect(radio.reads, isEmpty);
    expect(radio.contactWrites, isEmpty);
    expect(radio.writes, isEmpty);
  });

  test('combined export reads contacts from the radio and rejects an incomplete read', () async {
    await radio.syncContacts();
    final key = radio.contacts.keys.single;
    radio.contacts[key] = radio.contacts[key]!.copyWith(name: 'Name on radio');
    final reads = radio.contactReads;
    final snapshot = (await radio.connector.snapshotNodeBackup(
      includeChannels: true,
      includeContacts: true,
    ))!;
    final plan = await const BackupImportPlanner().inspect(
      await snapshot.encode(password: ''),
      password: '',
    );
    expect(plan.contacts!.single.name, 'Name on radio');
    expect(plan.channels, hasLength(2));
    expect(radio.contactReads, reads + 1);
    expect(radio.reads, isEmpty);
    expect(radio.contactWrites, isEmpty);
    expect(radio.writes, isEmpty);

    radio.incompleteContactList = true;
    expect(await radio.connector.snapshotNodeBackup(
      includeChannels: false,
      includeContacts: true,
    ), isNull);
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
