import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/models/channel_message.dart';
import 'package:meshcore_open/storage/channel_identity_store.dart';
import 'package:meshcore_open/storage/channel_message_store.dart';
import 'package:meshcore_open/storage/channel_name_keyed_store.dart';
import 'package:meshcore_open/storage/channel_region_store.dart';
import 'package:meshcore_open/storage/channel_settings_store.dart';
import 'package:meshcore_open/storage/channel_store.dart';
import 'package:meshcore_open/storage/message_history_database.dart';
import 'package:meshcore_open/storage/message_history_storage.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _node = 'aaaaaaaaaa000000000000000000000000000000000000000000000000000000';
const _otherNode = 'bbbbbbbbbb000000000000000000000000000000000000000000000000000000';
const _oldName = 'Before';
const _newName = 'After';
const _unrelatedName = 'Unrelated';

Channel _channel(int index, String name, {int seed = 1}) => Channel(
  index: index,
  name: name,
  psk: Uint8List.fromList(List<int>.generate(16, (i) => seed + i)),
);

ChannelMessage _message(int index, String id) => ChannelMessage(
  senderName: 'Alice',
  text: 'stored $id',
  timestamp: DateTime.utc(2026),
  isOutgoing: false,
  channelIndex: index,
  messageId: id,
);

class _NoPreferencesDirectory extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async {
    throw MissingPluginException('synthetic channel deletion preferences');
  }
}

/// Exercises the real delete method and frame builder. Refresh is a boundary
/// here: baseline tests pin storage guarantees without starting sync timers.
/// The change tests inject awaited real slot replies at the refresh boundary.
/// This does not simulate an entire radio queue or a physical reconnection.
class _DeleteConnector extends MeshCoreConnector {
  bool connected = false;
  int refreshes = 0;
  Object? writeFailure;
  Object? refreshFailure;
  Future<void> Function()? duringWrite;
  Future<void> Function()? duringRefresh;
  final frames = <Uint8List>[];

  _DeleteConnector() {
    setFrameWriterForTest((frame) async {
      frames.add(Uint8List.fromList(frame));
      final failure = writeFailure;
      if (failure != null) {
        throw failure;
      }
      await duringWrite?.call();
    });
  }

  @override
  bool get isConnected => connected;

  @override
  Future<void> stopScan() async {}

  @override
  Future<void> getChannels({int? maxChannels, bool force = false}) async {
    expect(force, isTrue);
    refreshes++;
    await duringRefresh?.call();
    final failure = refreshFailure;
    if (failure != null) {
      throw failure;
    }
  }
}

Future<String?> _sqliteProblem() async {
  final database = MessageHistoryDatabase.withExecutor(NativeDatabase.memory());
  try {
    await database.customSelect('SELECT 1').get();
    return null;
  } catch (error) {
    return 'SQLite unavailable: $error';
  } finally {
    try {
      await database.close();
    } catch (_) {
      // An executor that failed to open may not be closable.
    }
  }
}

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final sqliteProblem = await _sqliteProblem();
  final storage = MessageHistoryStorage.instance;
  late Directory directory;
  late File file;
  late PathProviderPlatform savedPaths;
  late _DeleteConnector connector;

  Future<void> openDatabase() async {
    await storage.initializeAndMigrate(
      databaseFactory: () =>
          MessageHistoryDatabase.withExecutor(NativeDatabase(file)),
    );
    expect(storage.hasDatabase, isTrue);
  }

  ChannelMessageStore messages(String node, List<Channel> channels) =>
      ChannelMessageStore()
        ..setPublicKeyHex = node
        ..replaceChannels(channels);

  Future<void> seed(String node, List<Channel> channels) async {
    await (ChannelStore()..setPublicKeyHex = node).saveChannels(channels);
    final history = messages(node, channels);
    final options = ChannelSettingsStore()
      ..setPublicKeyHex = node
      ..replaceChannels(channels);
    final regions = ChannelRegionStore()
      ..setPublicKeyHex = node
      ..replaceChannels(channels);
    for (final channel in channels) {
      await history.saveChannelMessages(
        channel.index,
        [_message(channel.index, '$node-${channel.name}')],
      );
      await options.saveMCOtxtEnabled(channel.index, true);
      await regions.saveRegion(channel.index, 'region-${channel.name}');
    }
  }

  Future<void> start({bool otherNode = false}) async {
    final old = _channel(2, _oldName);
    final current = _channel(2, _newName);
    final unrelated = _channel(4, _unrelatedName, seed: 33);
    // Seed before linking: both names have independent persisted rows. A
    // later rename must clear both rather than just the currently visible one.
    await seed(_node, [old, unrelated]);
    await seed(_node, [current, unrelated]);
    if (otherNode) {
      await seed(_otherNode, [_channel(5, _oldName), unrelated]);
      await seed(_otherNode, [_channel(5, _newName), unrelated]);
    }
    await ChannelIdentities.instance.link(
      ChannelIdentity.of(old)!,
      ChannelIdentity.of(current)!,
    );
    // Use the public, awaited loader to bind the existing stores to the
    // persisted snapshot. No initialize(), BLE plugin, sleeps or fake clock
    // around SQLite. Only afterwards does the synthetic transport connect.
    expect(
      await connector.enterOfflineHistory(scope: _node.substring(0, 10)),
      isTrue,
    );
    expect(
      connector.channels.map((c) => c.name),
      containsAll([_newName, _unrelatedName]),
    );
    expect(connector.getChannelMessages(current), hasLength(2));
    connector.connected = true;
  }

  Future<void> expectStored(String node, String name, bool exists) async {
    final history = messages(node, const []);
    final historyKey = ChannelNameKeyedStore.nameStorageKey(history.keyFor, name);
    expect(
      await storage.getString(MessageHistoryKind.channel, historyKey),
      exists ? isNotNull : isNull,
      reason: 'SQL history for $node / $name',
    );
    final options = ChannelSettingsStore()..setPublicKeyHex = node;
    final regions = ChannelRegionStore()..setPublicKeyHex = node;
    for (final prefix in [options.keyForMCOtxt, regions.keyFor]) {
      expect(
        PrefsManager.instance.containsKey(
          ChannelNameKeyedStore.nameStorageKey(prefix, name),
        ),
        exists,
        reason: 'saved option/region for $node / $name',
      );
    }
  }

  group('U08b2 baseline: fork channel deletion', () {
    setUp(() async {
      savedPaths = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _NoPreferencesDirectory();
      SharedPreferences.setMockInitialValues({});
      PrefsManager.reset();
      await PrefsManager.initialize();
      await storage.resetForTesting();
      directory = await Directory.systemTemp.createTemp('mcoa-channel-delete-');
      file = File('${directory.path}${Platform.pathSeparator}history.sqlite');
      await openDatabase();
      ChannelIdentities.instance.resetForTesting();
      await ChannelIdentities.instance.load();
      connector = _DeleteConnector();
    });

    tearDown(() async {
      connector.connected = false;
      connector.dispose();
      ChannelIdentities.instance.resetForTesting();
      await storage.resetForTesting();
      PrefsManager.reset();
      PathProviderPlatform.instance = savedPaths;
      await directory.delete(recursive: true);
    });

    test('local delete clears aliases on disk and keeps an unrelated channel', () async {
      await start();
      await connector.deleteChannel(2);
      expect(connector.frames, [buildSetChannelFrame(2, '', Uint8List(16))]);
      expect(connector.refreshes, 1);
      expect(connector.getChannelMessages(_channel(2, _newName)), isEmpty);
      await storage.resetForTesting();
      await openDatabase();
      await expectStored(_node, _oldName, false);
      await expectStored(_node, _newName, false);
      await expectStored(_node, _unrelatedName, true);
      // Reload identities as well: removal must survive an app restart.
      ChannelIdentities.instance.resetForTesting();
      await ChannelIdentities.instance.load();
      expect(
        ChannelIdentities.instance.namesOf(
          ChannelIdentity.of(_channel(2, _newName))!,
        ),
        [_newName],
      );
    });

    test('local delete preserves another node and its alias group', () async {
      await start(otherNode: true);
      await connector.deleteChannel(2);
      await expectStored(_node, _oldName, false);
      await expectStored(_node, _newName, false);
      await expectStored(_otherNode, _oldName, true);
      await expectStored(_otherNode, _newName, true);
      expect(
        ChannelIdentities.instance.namesOf(
          ChannelIdentity.of(_channel(2, _newName))!,
        ),
        unorderedEquals([_oldName, _newName]),
      );
    });

    test('allNodes clears both scopes without changing the other radio slots', () async {
      await start(otherNode: true);
      await connector.deleteChannel(2, allNodes: true);
      for (final node in [_node, _otherNode]) {
        await expectStored(node, _oldName, false);
        await expectStored(node, _newName, false);
        await expectStored(node, _unrelatedName, true);
      }
      final otherChannels = await (ChannelStore()
            ..setPublicKeyHex = _otherNode)
          .loadChannels();
      expect(otherChannels.map((c) => c.name), contains(_newName));
      expect(connector.frames, hasLength(1));
    });

    test('a failed transport write leaves history, options and aliases intact', () async {
      await start();
      final failure = StateError('synthetic write failure');
      connector.writeFailure = failure;
      await expectLater(connector.deleteChannel(2), throwsA(same(failure)));
      expect(connector.refreshes, 0);
      await expectStored(_node, _oldName, true);
      await expectStored(_node, _newName, true);
      expect(connector.getChannelMessages(_channel(2, _newName)), hasLength(2));
    });

    test('disconnected delete is a no-op', () async {
      await start();
      connector.connected = false;
      await connector.deleteChannel(2);
      expect(connector.frames, isEmpty);
      expect(connector.refreshes, 0);
      await expectStored(_node, _oldName, true);
      await expectStored(_node, _newName, true);
    });

    test('a failed refresh does not undo explicit local cleanup', () async {
      await start();
      final failure = StateError('synthetic refresh failure');
      connector.refreshFailure = failure;
      await expectLater(connector.deleteChannel(2), throwsA(same(failure)));
      await expectStored(_node, _oldName, false);
      await expectStored(_node, _newName, false);
      await expectStored(_node, _unrelatedName, true);
    });

    // U08b2 regressions and additional invariants for the deletion change.
    // Await the real slot handler so every SQL read/replay has finished before
    // asserting or closing the database; no arbitrary settling sleeps.
    Future<void> slotReply(Channel channel) async {
      final frame = Uint8List(50);
      frame[0] = respCodeChannelInfo;
      frame[1] = channel.index;
      frame.setRange(2, 2 + channel.name.length, channel.name.codeUnits);
      frame.setRange(34, 50, channel.psk);
      await connector.handleChannelInfoForTest(frame);
    }

    test('U08b2: cleanup follows refresh even when the slot binding disappears', () async {
      await start();
      connector.duringRefresh = () async {
        // Cleanup has not run yet, and cannot rely on the binding remaining
        // registered by the time refresh returns.
        await expectStored(_node, _newName, true);
        await slotReply(Channel(index: 2, name: '', psk: Uint8List(16)));
      };
      await connector.deleteChannel(2);
      await expectStored(_node, _oldName, false);
      await expectStored(_node, _newName, false);
      await expectStored(_node, _unrelatedName, true);
    });

    test('U08b2: another slot keeps aliases, options, regions and images', () async {
      await start(otherNode: true);
      await slotReply(_channel(5, _oldName));
      var imageDeletes = 0;
      connector.setChannelImageDeleteForTest((_, _) async {
        imageDeletes++;
      });
      await connector.deleteChannel(2, allNodes: true);
      await expectStored(_node, _oldName, true);
      await expectStored(_node, _newName, true);
      await expectStored(_otherNode, _oldName, true);
      await expectStored(_otherNode, _newName, true);
      expect(imageDeletes, 0);
      expect(connector.getChannelMessages(_channel(5, _oldName)), hasLength(2));
      expect(
        ChannelIdentities.instance.namesOf(
          ChannelIdentity.of(_channel(5, _oldName))!,
        ),
        unorderedEquals([_oldName, _newName]),
      );
    });

    test('U08b2: a same-name slot with another PSK still shares name-keyed data', () async {
      await start();
      await slotReply(_channel(5, _newName, seed: 65));
      await connector.deleteChannel(2);
      await expectStored(_node, _oldName, true);
      await expectStored(_node, _newName, true);
    });

    test('U08b2: a sibling discovered during refresh also keeps shared data', () async {
      await start();
      connector.duringRefresh = () => slotReply(_channel(5, _oldName));
      await connector.deleteChannel(2);
      await expectStored(_node, _oldName, true);
      await expectStored(_node, _newName, true);
    });

    test('U08b2: a replacement keeps its SQL, options and live transcript', () async {
      await start();
      final replacement = _channel(2, 'Replacement', seed: 65);
      var imageDeletes = 0;
      connector.setChannelImageDeleteForTest((_, _) async {
        imageDeletes++;
      });
      connector.duringRefresh = () async {
        await seed(_node, [replacement]);
        await slotReply(replacement);
      };
      await connector.deleteChannel(2);
      await expectStored(_node, _oldName, false);
      await expectStored(_node, _newName, false);
      await expectStored(_node, 'Replacement', true);
      expect(connector.getChannelMessages(replacement), hasLength(1));
      // The existing image callback can delete by legacy slot: do not call it
      // with a slot that now belongs to someone else.
      expect(imageDeletes, 0);
    });

    test('U08b2: a same-name replacement cannot lose shared name-keyed history', () async {
      await start();
      final replacement = _channel(2, _newName, seed: 65);
      connector.duringRefresh = () => slotReply(replacement);
      await connector.deleteChannel(2);
      await expectStored(_node, _oldName, true);
      await expectStored(_node, _newName, true);
      // One slot reply does not establish a rekey: reconciliation compares
      // the entire before/after lists when the sync finishes. The new pair
      // initially reads only its own name, while the old alias group and
      // both SQL rows must remain intact throughout deletion cleanup.
      expect(
        connector.getChannelMessages(replacement)
            .map((message) => message.messageId),
        ['$_node-$_newName'],
      );
      final preserved = await messages(
        _node,
        [_channel(2, _newName)],
      ).loadChannelMessages(2);
      expect(
        preserved.map((message) => message.messageId),
        unorderedEquals(['$_node-$_oldName', '$_node-$_newName']),
      );

      await connector.completeChannelSyncForTest();
      expect(
        connector.getChannelMessages(replacement)
            .map((message) => message.messageId),
        unorderedEquals(['$_node-$_oldName', '$_node-$_newName']),
      );
    });

    test('U08b2: shared PSK images stay while independently named history is cleared', () async {
      await start();
      await slotReply(_channel(5, 'Same key, another name'));
      var imageDeletes = 0;
      connector.setChannelImageDeleteForTest((_, _) async {
        imageDeletes++;
      });
      await connector.deleteChannel(2);
      await expectStored(_node, _oldName, false);
      await expectStored(_node, _newName, false);
      expect(imageDeletes, 0);
    });

    test('U08b2: a refresh error after an empty reply still clears captured names', () async {
      await start();
      final failure = StateError('synthetic partial refresh failure');
      connector.duringRefresh = () async {
        await slotReply(Channel(index: 2, name: '', psk: Uint8List(16)));
      };
      connector.refreshFailure = failure;
      await expectLater(connector.deleteChannel(2), throwsA(same(failure)));
      await expectStored(_node, _oldName, false);
      await expectStored(_node, _newName, false);
      await expectStored(_node, _unrelatedName, true);
    });

    test('U08b2: rebinding to another node cannot redirect cleanup', () async {
      await start(otherNode: true);
      connector.duringRefresh = () async {
        connector.connected = false;
        await connector.exitOfflineHistory();
        expect(
          await connector.enterOfflineHistory(
            scope: _otherNode.substring(0, 10),
          ),
          isTrue,
        );
        connector.connected = true;
      };
      await connector.deleteChannel(2);
      await expectStored(_node, _oldName, false);
      await expectStored(_node, _newName, false);
      await expectStored(_otherNode, _oldName, true);
      await expectStored(_otherNode, _newName, true);
      expect(connector.getChannelMessages(_channel(5, _newName)), hasLength(2));
    });

    test('U08b2: switching nodes during the write does not refresh the new radio', () async {
      await start(otherNode: true);
      connector.duringWrite = () async {
        connector.connected = false;
        await connector.exitOfflineHistory();
        expect(
          await connector.enterOfflineHistory(
            scope: _otherNode.substring(0, 10),
          ),
          isTrue,
        );
        connector.connected = true;
      };
      await connector.deleteChannel(2);
      expect(connector.refreshes, 0);
      await expectStored(_node, _oldName, false);
      await expectStored(_node, _newName, false);
      await expectStored(_otherNode, _oldName, true);
      await expectStored(_otherNode, _newName, true);
    });

    test('U08b2: image IDs survive forgetting the alias group', () async {
      await start();
      final rekeyed = _channel(2, _newName, seed: 65);
      await ChannelIdentities.instance.link(
        ChannelIdentity.of(_channel(2, _newName))!,
        ChannelIdentity.of(rekeyed)!,
      );
      final originalIds = {
        _channel(2, _oldName).storageId!,
        rekeyed.storageId!,
      };
      final deleted = <Set<String>>[];
      connector.setChannelImageDeleteForTest((index, ids) async {
        expect(index, 2);
        deleted.add(Set.of(ids));
      });
      await connector.deleteChannel(2);
      expect(deleted, [originalIds]);
    });
  }, skip: sqliteProblem);
}
