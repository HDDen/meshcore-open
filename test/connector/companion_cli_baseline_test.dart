import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/connector/pending_command_replies.dart';
import 'package:meshcore_open/models/companion_cli_entry.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:meshcore_open/storage/message_history_database.dart';
import 'package:meshcore_open/storage/message_history_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Исходные baseline ниже фиксируют соседние механизмы без обещаний новой
// late/prefix-защиты. Отдельный integration test проверяет подключённую консоль.
class _CliConnector extends MeshCoreConnector {
  @override
  bool get isConnected => true;
  @override
  String get selfPublicKeyHex => '01' * 32;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });
  tearDown(PrefsManager.reset);

  test('integration: firmware gate and actual connector dispatch retain the CLI reply or ERR', () async {
    final storage = MessageHistoryStorage.instance;
    await storage.resetForTesting();
    await storage.initializeAndMigrate(databaseFactory: () =>
      MessageHistoryDatabase.withExecutor(NativeDatabase.memory()));
    addTearDown(storage.resetForTesting);
    final connector = _CliConnector();
    try {
      connector.handleFrameForTest([respCodeDeviceInfo, 13, 0, 0]);
      expect(connector.supportsCompanionCli, isFalse);
      await expectLater(connector.companionCli.sendCommand('ver'), throwsException);
      connector.handleFrameForTest([respCodeDeviceInfo, 14, 0, 0]);
      expect(connector.supportsCompanionCli, isTrue);
      connector.setFrameWriterForTest((frame) async {
        expect(frame.first, cmdRunCliCommand);
        connector.handleFrameForTest([respCodeCliReply, ...frame.sublist(1, 4), ...'version'.codeUnits]);
      });
      await connector.companionCli.sendCommand('ver');
      expect(connector.companionCli.entries(shared: false).single.response, 'version');
      expect(connector.pendingCommandReplyCountForTest, 0);
      connector.setFrameWriterForTest((_) async {
        connector.handleFrameForTest([respCodeErr, 1]);
      });
      await connector.companionCli.sendCommand('board');
      expect(connector.companionCli.entries(shared: false).last.status, CompanionCliStatus.failed);
      expect(connector.companionCli.entries(shared: false).last.failure, 'protocol');
      expect(connector.pendingCommandReplyCountForTest, 0);
    } finally {
      connector.dispose();
    }
  }, timeout: const Timeout(Duration(seconds: 10)));

  test('baseline: existing remote CLI keeps destination type timestamp and terminator', () {
    final key = Uint8List.fromList(List.generate(32, (index) => index + 1));
    expect(buildSendCliCommandFrame(key, 'ver', timestampSeconds: 0x01020304), [
      2, 1, 0, 4, 3, 2, 1, 1, 2, 3, 4, 5, 6, 0x76, 0x65, 0x72, 0,
    ]);
  });

  test('baseline: local CLI text reaches raw subscribers without creating firmware contacts', () async {
    final connector = MeshCoreConnector();
    try {
      final incoming = Uint8List.fromList([29, ...'A1|synthetic reply'.codeUnits]);
      final next = connector.receivedFrames.first.timeout(const Duration(seconds: 3));
      connector.handleFrameForTest(incoming);
      expect(await next, incoming);
      expect(connector.contacts, isEmpty);
      expect(connector.channels, isEmpty);
    } finally {
      connector.dispose();
    }
  }, timeout: const Timeout(Duration(seconds: 10)));

  test('baseline: CLI text does not complete a different pending device request', () {
    final replies = PendingCommandReplies(staleAfter: const Duration(seconds: 15));
    final pending = replies.track(buildDeviceQueryFrame());
    expect(pending, isNotNull);
    expect(replies.completeReply(Uint8List.fromList([29, ...'B2|OK'.codeUnits])), isFalse);
    expect(replies.length, 1);
    expect(replies.completeReply(Uint8List.fromList([respCodeDeviceInfo, 14])), isTrue);
    expect(replies.length, 0);
  });
}
