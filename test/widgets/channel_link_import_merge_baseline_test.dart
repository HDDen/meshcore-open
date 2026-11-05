import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/helpers/channel_qr_link.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/storage/channel_region_store.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:meshcore_open/storage/region_store.dart';
import 'package:meshcore_open/widgets/channel_link_import.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _nodeKey = 'aaaaaaaaaa000000000000000000000000000000000000000000000000000000';
const _secret = 'cbf8c4bc9379ab17b216721171f3ba89';
const _otherSecret = '00112233445566778899aabbccddeeff';

Channel _channel(int index, String name, [String key = _secret]) =>
    Channel(index: index, name: name, psk: Channel.parsePskHex(key));

ChannelQrLink _link({String name = 'New', String? region = 'ru-kda'}) =>
    ChannelQrLink(
      name: name,
      psk: Channel.parsePskHex(_secret),
      regionScope: region,
    );

class _NoPreferencesDirectory extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async {
    throw MissingPluginException('synthetic QR import preferences');
  }
}

/// Only the radio boundary is replaced. The real import dialogs and the real
/// region store run here; no camera, transport, history SQL or arbitrary sleep.
class _ImportNode extends MeshCoreConnector {
  final held = <Channel>[];
  final regions = <int, String>{};
  final written = <String>[];
  final regionsBeforeRadioWrite = <String>[];
  bool connected = true;
  bool offline = false;
  bool loaded = true;
  bool syncing = false;
  int slots = 8;
  String nodeKey = _nodeKey;
  final unconfirmed = <int>{};
  VoidCallback? afterRadioWrite;

  @override
  bool get isConnected => connected;
  @override
  bool get isOfflineMode => offline;
  @override
  bool get hasLoadedChannels => loaded;
  @override
  bool get isSyncingChannels => syncing;
  @override
  int get maxChannels => slots;
  @override
  String get selfPublicKeyHex => nodeKey;
  @override
  Set<int> get unconfirmedChannelSlots => Set.unmodifiable(unconfirmed);
  @override
  List<Channel> get channels => List.unmodifiable(held);
  @override
  String getChannelRegion(int channelIndex) => regions[channelIndex] ?? '';

  @override
  Future<void> setChannel(int index, String name, Uint8List psk) async {
    final regionStore = ChannelRegionStore()
      ..setPublicKeyHex = nodeKey
      ..registerChannel(Channel(index: index, name: name, psk: psk));
    regionsBeforeRadioWrite.add(await regionStore.loadRegion(index));
    written.add('channel $index $name ${Channel.formatPskHex(psk).toLowerCase()}');
    afterRadioWrite?.call();
  }

  @override
  Future<void> setChannelRegion(int channelIndex, String region) async {
    regions[channelIndex] = region;
    written.add('region $channelIndex $region');
  }
}

class _ImportHost {
  final node = _ImportNode();
  late AppLocalizations strings;
  Future<void>? operation;

  Future<void> get completion {
    final pending = operation;
    expect(pending, isNotNull, reason: 'the fixture must start the real import');
    return pending!;
  }

  Widget build(ChannelQrLink link, {int? scannedSlot, String? scannedNodeKey}) =>
      ChangeNotifierProvider<MeshCoreConnector>.value(
        value: node,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: Builder(builder: (context) {
              strings = AppLocalizations.of(context);
              return TextButton(
                onPressed: () {
                  operation = scannedSlot == null
                      ? ChannelLinkImport.confirmAndAdd(context, link)
                      : ChannelLinkImport.addScanned(
                          context,
                          connector: node,
                          link: link,
                          index: scannedSlot,
                          expectedNodeKey: scannedNodeKey,
                        );
                },
                child: const Text('Import fixture'),
              );
            }),
          ),
        ),
      );
}

Future<void> _withImport(
  WidgetTester tester,
  Future<void> Function(_ImportHost) check,
) async {
  final host = _ImportHost();
  try {
    await check(host);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    host.node.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PathProviderPlatform savedPaths;

  setUp(() async {
    savedPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _NoPreferencesDirectory();
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });

  tearDown(() {
    PrefsManager.reset();
    PathProviderPlatform.instance = savedPaths;
  });

  testWidgets('U09 baseline: scanned import persists the region before radio write', (tester) async {
    await _withImport(tester, (host) async {
      await tester.pumpWidget(host.build(_link(), scannedSlot: 4));
      await tester.tap(find.text('Import fixture'));
      await tester.pumpAndSettle();
      await host.completion;

      expect(find.byType(AlertDialog), findsNothing);
      expect(host.node.written, ['channel 4 New $_secret', 'region 4 ru-kda']);
      expect(host.node.regionsBeforeRadioWrite, ['ru-kda']);
      expect(RegionStore().loadRegions(), contains('ru-kda'));
    });
  });

  testWidgets('U09 baseline: cancelling link confirmation changes neither radio nor regions', (tester) async {
    await _withImport(tester, (host) async {
      await tester.pumpWidget(host.build(_link()));
      await tester.tap(find.text('Import fixture'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(host.node.written, isEmpty);
      expect(RegionStore().loadRegions(), isNot(contains('ru-kda')));

      await tester.tap(find.text(host.strings.common_cancel));
      await tester.pumpAndSettle();
      await host.completion;
      expect(host.node.written, isEmpty);
      expect(host.node.regionsBeforeRadioWrite, isEmpty);
      expect(RegionStore().loadRegions(), isNot(contains('ru-kda')));
    });
  });

  testWidgets('U09 baseline: a new link needs confirmation and uses the first free slot', (tester) async {
    await _withImport(tester, (host) async {
      host.node.held.add(_channel(0, 'Existing', _otherSecret));
      await tester.pumpWidget(host.build(_link()));
      await tester.tap(find.text('Import fixture'));
      await tester.pumpAndSettle();
      expect(host.node.written, isEmpty);

      await tester.tap(find.text(host.strings.common_add));
      await tester.pumpAndSettle();
      await host.completion;
      expect(host.node.written, ['channel 1 New $_secret', 'region 1 ru-kda']);
      expect(host.node.regionsBeforeRadioWrite, ['ru-kda']);
    });
  });

  testWidgets('U09 baseline: updating preserves the existing channel name and clears absent region', (tester) async {
    await _withImport(tester, (host) async {
      final existing = _channel(3, ' My Channel ', _otherSecret);
      host.node.held.add(existing);
      host.node.regions[3] = 'old-region';
      await (ChannelRegionStore()
            ..setPublicKeyHex = _nodeKey
            ..registerChannel(existing))
          .saveRegion(3, 'old-region');
      await tester.pumpWidget(host.build(_link(name: 'my channel', region: null)));
      await tester.tap(find.text('Import fixture'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(host.node.written, isEmpty);

      await tester.tap(find.text(host.strings.common_ok));
      await tester.pumpAndSettle();
      await host.completion;
      expect(host.node.written, [
        'channel 3  My Channel  $_secret',
        'region 3 ',
      ]);
      expect(host.node.regionsBeforeRadioWrite, ['']);
      expect(host.node.regions[3], '');
    });
  });

  testWidgets('U09 baseline: cancelling an update keeps the old saved region', (tester) async {
    await _withImport(tester, (host) async {
      final existing = _channel(3, 'New', _otherSecret);
      final regionStore = ChannelRegionStore()
        ..setPublicKeyHex = _nodeKey
        ..registerChannel(existing);
      host.node.held.add(existing);
      host.node.regions[3] = 'old-region';
      await regionStore.saveRegion(3, 'old-region');
      await tester.pumpWidget(host.build(_link()));
      await tester.tap(find.text('Import fixture'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(host.strings.common_cancel));
      await tester.pumpAndSettle();
      await host.completion;

      expect(host.node.written, isEmpty);
      expect(await regionStore.loadRegion(3), 'old-region');
      expect(RegionStore().loadRegions(), isNot(contains('ru-kda')));
    });
  });

  testWidgets('U09 baseline: the same PSK under another name is never added twice', (tester) async {
    await _withImport(tester, (host) async {
      host.node.held.add(_channel(6, 'Another name'));
      await tester.pumpWidget(host.build(_link(), scannedSlot: 4));
      await tester.tap(find.text('Import fixture'));
      await tester.pumpAndSettle();
      await host.completion;

      expect(find.byType(AlertDialog), findsNothing);
      expect(host.node.written, isEmpty);
      expect(RegionStore().loadRegions(), isNot(contains('ru-kda')));
    });
  });

  // U09 guards: unsafe imports must stop before writing a region or a radio
  // command. Scanning and message/clipboard links share the same checks.
  for (final scanned in [false, true]) {
    for (final state in ['offline', 'disconnected', 'loading', 'syncing']) {
      testWidgets('U09: $state blocks import, scanned=$scanned', (tester) async {
        await _withImport(tester, (host) async {
          host.node.offline = state == 'offline';
          host.node.connected = state != 'disconnected';
          host.node.loaded = state != 'loading';
          host.node.syncing = state == 'syncing';
          await tester.pumpWidget(host.build(_link(), scannedSlot: scanned ? 4 : null));
          await tester.tap(find.text('Import fixture'));
          await tester.pumpAndSettle();
          await host.completion;

          expect(find.byType(AlertDialog), findsNothing);
          expect(host.node.written, isEmpty);
          expect(host.node.regionsBeforeRadioWrite, isEmpty);
          expect(RegionStore().loadRegions(), isNot(contains('ru-kda')));
          final warning = state == 'offline'
              ? host.strings.app_offline_unableToMessage
              : state == 'disconnected'
              ? host.strings.scanner_notConnected
              : host.strings.channels_waitForSync;
          expect(find.text(warning), findsOneWidget);
        });
      });
    }
  }

  testWidgets('U09: a stale pre-scan slot skips occupied and unconfirmed slots', (tester) async {
    await _withImport(tester, (host) async {
      host.node.held.add(_channel(4, 'Occupied', _otherSecret));
      host.node.unconfirmed.add(0);
      await tester.pumpWidget(host.build(_link(), scannedSlot: 4));
      await tester.tap(find.text('Import fixture'));
      await tester.pumpAndSettle();
      await host.completion;

      expect(host.node.written, ['channel 1 New $_secret', 'region 1 ru-kda']);
      expect(host.node.regionsBeforeRadioWrite, ['ru-kda']);
    });
  });

  testWidgets('U09: unconfirmed slots are not treated as free capacity', (tester) async {
    await _withImport(tester, (host) async {
      host.node.slots = 2;
      host.node.unconfirmed.addAll([0, 1]);
      await tester.pumpWidget(host.build(_link(), scannedSlot: 0));
      await tester.tap(find.text('Import fixture'));
      await tester.pumpAndSettle();
      await host.completion;

      expect(host.node.written, isEmpty);
      expect(RegionStore().loadRegions(), isNot(contains('ru-kda')));
      expect(find.text(host.strings.channels_noFreeSlots), findsOneWidget);
    });
  });

  testWidgets('U09: confirmation uses current capacity rather than a remembered free slot', (tester) async {
    await _withImport(tester, (host) async {
      host.node.held.add(_channel(0, 'Existing', _otherSecret));
      await tester.pumpWidget(host.build(_link()));
      await tester.tap(find.text('Import fixture'));
      await tester.pumpAndSettle();
      host.node.held.add(_channel(1, 'Arrived meanwhile', _otherSecret));
      await tester.tap(find.text(host.strings.common_add));
      await tester.pumpAndSettle();
      await host.completion;

      expect(host.node.written, ['channel 2 New $_secret', 'region 2 ru-kda']);
    });
  });

  for (final state in ['disconnected', 'offline', 'syncing', 'another node']) {
    testWidgets('U09: $state during confirmation prevents the write', (tester) async {
      await _withImport(tester, (host) async {
        await tester.pumpWidget(host.build(_link()));
        await tester.tap(find.text('Import fixture'));
        await tester.pumpAndSettle();
        host.node.connected = state != 'disconnected';
        host.node.offline = state == 'offline';
        host.node.syncing = state == 'syncing';
        if (state == 'another node') {
          host.node.nodeKey = 'bb' * 32;
        }
        await tester.tap(find.text(host.strings.common_add));
        await tester.pumpAndSettle();
        await host.completion;

        expect(host.node.written, isEmpty);
        expect(host.node.regionsBeforeRadioWrite, isEmpty);
        expect(RegionStore().loadRegions(), isNot(contains('ru-kda')));
      });
    });
  }

  testWidgets('U09: a newly occupied name does not turn Add consent into Update consent', (tester) async {
    await _withImport(tester, (host) async {
      await tester.pumpWidget(host.build(_link()));
      await tester.tap(find.text('Import fixture'));
      await tester.pumpAndSettle();
      host.node.held.add(_channel(3, 'New', _otherSecret));
      await tester.tap(find.text(host.strings.common_add));
      await tester.pumpAndSettle();
      await host.completion;

      expect(host.node.written, isEmpty);
      expect(find.text(host.strings.channels_qrImportChanged), findsOneWidget);
      expect(RegionStore().loadRegions(), isNot(contains('ru-kda')));
    });
  });

  testWidgets('U09: a key added during confirmation is not duplicated', (tester) async {
    await _withImport(tester, (host) async {
      await tester.pumpWidget(host.build(_link()));
      await tester.tap(find.text('Import fixture'));
      await tester.pumpAndSettle();
      host.node.held.add(_channel(3, 'Already arrived'));
      await tester.tap(find.text(host.strings.common_add));
      await tester.pumpAndSettle();
      await host.completion;

      expect(host.node.written, isEmpty);
      expect(find.text(host.strings.channels_qrAlreadyAdded('Already arrived')), findsOneWidget);
    });
  });

  testWidgets('U09: replacing the Update target while confirming cancels the write', (tester) async {
    await _withImport(tester, (host) async {
      host.node.held.add(_channel(3, 'New', _otherSecret));
      await tester.pumpWidget(host.build(_link()));
      await tester.tap(find.text('Import fixture'));
      await tester.pumpAndSettle();
      host.node.held[0] = _channel(3, 'New', '11112222333344445555666677778888');
      await tester.tap(find.text(host.strings.common_ok));
      await tester.pumpAndSettle();
      await host.completion;

      expect(host.node.written, isEmpty);
      expect(find.text(host.strings.channels_qrImportChanged), findsOneWidget);
      expect(RegionStore().loadRegions(), isNot(contains('ru-kda')));
    });
  });

  testWidgets('U09: a scan returned for a different node cannot import into it', (tester) async {
    await _withImport(tester, (host) async {
      host.node.nodeKey = 'bb' * 32;
      await tester.pumpWidget(host.build(_link(), scannedSlot: 4, scannedNodeKey: _nodeKey));
      await tester.tap(find.text('Import fixture'));
      await tester.pumpAndSettle();
      await host.completion;

      expect(host.node.written, isEmpty);
      expect(find.text(host.strings.channels_qrImportChanged), findsOneWidget);
      expect(RegionStore().loadRegions(), isNot(contains('ru-kda')));
    });
  });

  testWidgets('U09: a node switch during radio write does not apply the region to the new node', (tester) async {
    await _withImport(tester, (host) async {
      host.node.afterRadioWrite = () {
        host.node.nodeKey = 'bb' * 32;
      };
      await tester.pumpWidget(host.build(_link(), scannedSlot: 4));
      await tester.tap(find.text('Import fixture'));
      await tester.pumpAndSettle();
      await host.completion;

      expect(host.node.written, ['channel 4 New $_secret']);
      expect(host.node.regionsBeforeRadioWrite, ['ru-kda']);
      expect(find.text(host.strings.channels_qrImportChanged), findsOneWidget);
    });
  });

  testWidgets('U09: capacity exhausted during confirmation stops before region staging', (tester) async {
    await _withImport(tester, (host) async {
      host.node.slots = 1;
      await tester.pumpWidget(host.build(_link()));
      await tester.tap(find.text('Import fixture'));
      await tester.pumpAndSettle();
      host.node.unconfirmed.add(0);
      await tester.tap(find.text(host.strings.common_add));
      await tester.pumpAndSettle();
      await host.completion;

      expect(host.node.written, isEmpty);
      expect(host.node.regionsBeforeRadioWrite, isEmpty);
      expect(RegionStore().loadRegions(), isNot(contains('ru-kda')));
      expect(find.text(host.strings.channels_noFreeSlots), findsOneWidget);
    });
  });

  testWidgets('U09: an unconfirmed Update target is not overwritten', (tester) async {
    await _withImport(tester, (host) async {
      host.node.held.add(_channel(3, 'New', _otherSecret));
      host.node.unconfirmed.add(3);
      await tester.pumpWidget(host.build(_link()));
      await tester.tap(find.text('Import fixture'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(host.strings.common_ok));
      await tester.pumpAndSettle();
      await host.completion;

      expect(host.node.written, isEmpty);
      expect(host.node.regionsBeforeRadioWrite, isEmpty);
      expect(RegionStore().loadRegions(), isNot(contains('ru-kda')));
    });
  });
}
