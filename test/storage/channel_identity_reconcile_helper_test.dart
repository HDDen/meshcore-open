import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/storage/channel_identity_reconcile_helper.dart';
import 'package:meshcore_open/storage/channel_order_store.dart';
import 'package:meshcore_open/storage/channel_store.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const publicKeyHex = '1234567890abcdef';
  const scopedKey = '1234567890';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
    ChannelIdentityReconcileHelper.enabled = true;
  });

  test(
    'moves settings and messages when channel keeps name but changes PSK',
    () async {
      final prefs = PrefsManager.instance;
      await prefs.setBool('channel_smaz_${scopedKey}0', true);
      await prefs.setString(
        'channel_messages_${scopedKey}0',
        jsonEncode([
          {'channelIndex': 0, 'text': 'old'},
        ]),
      );

      final result = await ChannelIdentityReconcileHelper().reconcile(
        publicKeyHex: publicKeyHex,
        previousChannels: [
          Channel.fromHex(0, 'Alpha', '00000000000000000000000000000001')
            ..unreadCount = 7,
        ],
        currentChannels: [
          Channel.fromHex(2, 'Alpha', '00000000000000000000000000000002'),
        ],
      );

      expect(result.changed, isTrue);
      expect(result.channels.single.index, equals(2));
      expect(result.channels.single.unreadCount, equals(7));
      expect(prefs.containsKey('channel_smaz_${scopedKey}0'), isFalse);
      expect(prefs.getBool('channel_smaz_${scopedKey}2'), isTrue);

      final movedMessages =
          jsonDecode(prefs.getString('channel_messages_${scopedKey}2')!)
              as List<dynamic>;
      expect(movedMessages.single['channelIndex'], equals(2));
    },
  );

  test('moves order and group membership when channel keeps PSK', () async {
    final prefs = PrefsManager.instance;
    await prefs.setBool('channel_mcmp_${scopedKey}1', true);
    await prefs.setString('channel_order_$scopedKey', jsonEncode([1, 5]));
    await prefs.setString(
      'channel_groups$scopedKey',
      jsonEncode([
        {
          'name': 'Group',
          'channels': [1, 5],
        },
      ]),
    );

    final result = await ChannelIdentityReconcileHelper().reconcile(
      publicKeyHex: publicKeyHex,
      previousChannels: [
        Channel.fromHex(1, 'Old name', '00000000000000000000000000000003'),
      ],
      currentChannels: [
        Channel.fromHex(3, 'New name', '00000000000000000000000000000003'),
      ],
    );

    expect(result.changed, isTrue);
    expect(prefs.containsKey('channel_mcmp_${scopedKey}1'), isFalse);
    expect(prefs.getBool('channel_mcmp_${scopedKey}3'), isTrue);
    expect(
      jsonDecode(prefs.getString('channel_order_$scopedKey')!),
      equals([3]),
    );

    final groups =
        jsonDecode(prefs.getString('channel_groups$scopedKey')!)
            as List<dynamic>;
    expect(groups.single['channels'], equals([3]));
  });

  test('clears settings for channels that no longer exist', () async {
    final prefs = PrefsManager.instance;
    await prefs.setBool('channel_smaz_${scopedKey}0', true);
    await prefs.setString('channel_region_${scopedKey}4', 'EU');

    final result = await ChannelIdentityReconcileHelper().reconcile(
      publicKeyHex: publicKeyHex,
      previousChannels: [
        Channel.fromHex(4, 'Gone', '00000000000000000000000000000004')
          ..unreadCount = 9,
      ],
      currentChannels: [
        Channel.fromHex(0, 'Different', '00000000000000000000000000000005'),
      ],
    );

    expect(result.changed, isTrue);
    expect(result.channels.single.unreadCount, equals(0));
    expect(prefs.containsKey('channel_smaz_${scopedKey}0'), isFalse);
    expect(prefs.containsKey('channel_region_${scopedKey}4'), isFalse);
  });

  test('does not match by duplicate channel names', () async {
    final prefs = PrefsManager.instance;
    await prefs.setBool('channel_smaz_${scopedKey}0', true);

    final result = await ChannelIdentityReconcileHelper().reconcile(
      publicKeyHex: publicKeyHex,
      previousChannels: [
        Channel.fromHex(0, 'Echo', '00000000000000000000000000000006')
          ..unreadCount = 4,
      ],
      currentChannels: [
        Channel.fromHex(1, 'Echo', '00000000000000000000000000000007'),
        Channel.fromHex(2, 'Echo', '00000000000000000000000000000008'),
      ],
    );

    expect(result.changed, isTrue);
    expect(result.channels.map((channel) => channel.unreadCount), [0, 0]);
    expect(prefs.containsKey('channel_smaz_${scopedKey}0'), isFalse);
    expect(prefs.containsKey('channel_smaz_${scopedKey}1'), isFalse);
    expect(prefs.containsKey('channel_smaz_${scopedKey}2'), isFalse);
  });

  test('clears reused slot before full channel sync completes', () async {
    final prefs = PrefsManager.instance;
    await prefs.setBool('channel_smaz_${scopedKey}0', true);

    final store = ChannelStore()..setPublicKeyHex = publicKeyHex;
    await store.saveChannels([
      Channel.fromHex(0, 'Deleted', '00000000000000000000000000000009'),
    ]);

    final result = await ChannelIdentityReconcileHelper()
        .reconcileChannelDuringSync(
          publicKeyHex: publicKeyHex,
          previousChannelsCache: const [],
          currentChannels: const [],
          receivedChannel: Channel.fromHex(
            0,
            'New',
            '0000000000000000000000000000000a',
          ),
          channelStore: store,
        );

    expect(result, isNotNull);
    expect(result!.changed, isTrue);
    expect(result.affectedIndexes, equals({0}));
    expect(result.channels.single.name, equals('New'));
    expect(result.channels.single.unreadCount, equals(0));
    expect(prefs.containsKey('channel_smaz_${scopedKey}0'), isFalse);
  });

  test(
    'keeps data written to a new channel before full sync finalizes',
    () async {
      final prefs = PrefsManager.instance;
      await prefs.setBool('channel_smaz_${scopedKey}0', true);

      final store = ChannelStore()..setPublicKeyHex = publicKeyHex;
      final orderStore = ChannelOrderStore()..setPublicKeyHex = publicKeyHex;
      await store.saveChannels([
        Channel.fromHex(0, 'Deleted', '0000000000000000000000000000000d'),
      ]);

      final helper = ChannelIdentityReconcileHelper();
      final received = Channel.fromHex(
        0,
        'New',
        '0000000000000000000000000000000e',
      );
      final duringSync = await helper.reconcileChannelDuringSync(
        publicKeyHex: publicKeyHex,
        previousChannelsCache: const [],
        currentChannels: const [],
        receivedChannel: received,
        channelStore: store,
      );

      expect(duringSync, isNotNull);
      expect(prefs.containsKey('channel_smaz_${scopedKey}0'), isFalse);

      await prefs.setString('channel_region_${scopedKey}0', 'EU');
      await prefs.setString(
        'channel_messages_${scopedKey}0',
        jsonEncode([
          {'channelIndex': 0, 'text': 'fresh'},
        ]),
      );
      await prefs.setString('channel_order_$scopedKey', jsonEncode([0]));
      await prefs.setString(
        'channel_groups$scopedKey',
        jsonEncode([
          {
            'name': 'Fresh group',
            'channels': [0],
          },
        ]),
      );

      final finalized = await helper.reconcileAfterSync(
        publicKeyHex: publicKeyHex,
        previousChannelsCache: const [],
        currentChannels: [received],
        channelStore: store,
        channelOrderStore: orderStore,
      );

      expect(finalized, isNotNull);
      expect(prefs.getString('channel_region_${scopedKey}0'), equals('EU'));
      final messages =
          jsonDecode(prefs.getString('channel_messages_${scopedKey}0')!)
              as List<dynamic>;
      expect(messages.single['text'], equals('fresh'));
      expect(
        jsonDecode(prefs.getString('channel_order_$scopedKey')!),
        equals([0]),
      );
      final groups =
          jsonDecode(prefs.getString('channel_groups$scopedKey')!)
              as List<dynamic>;
      expect(groups.single['channels'], equals([0]));
    },
  );

  test('uses sync snapshot when channels swap indexes incrementally', () async {
    final prefs = PrefsManager.instance;
    await prefs.setBool('channel_smaz_${scopedKey}0', true);
    await prefs.setBool('channel_mcmp_${scopedKey}1', true);

    final store = ChannelStore()..setPublicKeyHex = publicKeyHex;
    await store.saveChannels([
      Channel.fromHex(0, 'Alpha', '0000000000000000000000000000000b'),
      Channel.fromHex(1, 'Beta', '0000000000000000000000000000000c'),
    ]);

    final helper = ChannelIdentityReconcileHelper();
    final betaFirst = await helper.reconcileChannelDuringSync(
      publicKeyHex: publicKeyHex,
      previousChannelsCache: const [],
      currentChannels: const [],
      receivedChannel: Channel.fromHex(
        0,
        'Beta',
        '0000000000000000000000000000000c',
      ),
      channelStore: store,
    );
    final both = await helper.reconcileChannelDuringSync(
      publicKeyHex: publicKeyHex,
      previousChannelsCache: const [],
      currentChannels: betaFirst!.channels,
      receivedChannel: Channel.fromHex(
        1,
        'Alpha',
        '0000000000000000000000000000000b',
      ),
      channelStore: store,
    );

    expect(betaFirst.affectedIndexes, equals({0}));
    expect(both, isNotNull);
    expect(both!.affectedIndexes, equals({1}));
    expect(prefs.getBool('channel_mcmp_${scopedKey}0'), isTrue);
    expect(prefs.getBool('channel_smaz_${scopedKey}1'), isTrue);
    expect(prefs.containsKey('channel_smaz_${scopedKey}0'), isFalse);
    expect(prefs.containsKey('channel_mcmp_${scopedKey}1'), isFalse);
  });
}
