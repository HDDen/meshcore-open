import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/services/additional_identity_inbox.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';

class _Inbox extends AdditionalIdentityInbox {
  int marked = 0;
  @override
  Future<void> markAllRead() async { marked++; }
}

class _Node extends MeshCoreConnector {
  _Node(this.inbox) : super(additionalIdentityInbox: inbox);
  final _Inbox inbox;
  final channelReads = <int>[];
  final contactReads = <String>[];
  @override
  List<Channel> get channels => [
    Channel(index: 1, name: 'First', psk: Uint8List(16)..[0] = 1),
    Channel(index: 3, name: 'Second', psk: Uint8List(16)..[0] = 2),
  ];
  @override
  void markChannelRead(int channelIndex) { channelReads.add(channelIndex); }
  @override
  void markContactRead(String contactKeyHex) { contactReads.add(contactKeyHex); }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });
  tearDown(PrefsManager.reset);
  for (final scope in [(true, false), (false, true), (true, true)]) {
    test('bulk read covers exactly the requested scopes $scope', () async {
      final inbox = _Inbox();
      final node = _Node(inbox);
      try {
        node.setContactUnreadCount('ab' * 32, 3);
        node.setContactUnreadCount('cd' * 32, 2);
        await node.markChatsRead(channels: scope.$1, contacts: scope.$2);
        expect(node.channelReads, scope.$1 ? [1, 3] : isEmpty);
        expect(node.contactReads.toSet(), scope.$2 ? {'ab' * 32, 'cd' * 32} : isEmpty);
        expect(inbox.marked, scope.$2 ? 1 : 0);
      } finally {
        node.dispose();
      }
    });
  }
  test('offline bulk read keeps unread state intact', () async {
    final inbox = _Inbox();
    final node = _Node(inbox);
    try {
      node.setReconnectContextForTest(transport: null, offlineMode: true);
      await node.markChatsRead(channels: true, contacts: true);
      expect(node.channelReads, isEmpty);
      expect(node.contactReads, isEmpty);
      expect(inbox.marked, 0);
    } finally {
      node.dispose();
    }
  });
}
