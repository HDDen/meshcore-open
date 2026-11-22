import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/models/bookmarked_message.dart';
import 'package:meshcore_open/storage/contact_identity_store.dart';
import '../support/history_test_environment.dart';

class _Node extends MeshCoreConnector {
  String scope = 'aa' * 32;
  @override
  String get storageKeyHex => scope;
}

BookmarkedMessage _entry(String peer, String id) => BookmarkedMessage(
  sourceType: BookmarkSourceType.contact, sourceId: peer, sourceName: 'Peer',
  messageId: id, senderName: 'Peer', text: 'text',
  timestamp: DateTime(2026), receivedAt: DateTime(2026), isOutgoing: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final environment = HistoryTestEnvironment();
  late _Node node;
  setUp(() async {
    await environment.setUp();
    ContactIdentities.instance.resetForTesting();
    await ContactIdentities.instance.load();
    node = _Node();
  });
  tearDown(() async {
    node.dispose();
    ContactIdentities.instance.resetForTesting();
    await environment.tearDown();
  });

  test('marking and unmarking follows linked contact keys', () async {
    final old = '11' * 32;
    final current = '22' * 32;
    await ContactIdentities.instance.link(old, current);
    await node.setBookmarkedMessage(_entry(old, 'one'), isBookmarked: true);
    expect(node.isMessageBookmarked(BookmarkSourceType.contact, current, 'one'), isTrue);
    await node.setBookmarkedMessage(_entry(current, 'one'), isBookmarked: false);
    expect(await node.loadBookmarkedMessages(), isEmpty);
  });

  test('a menu from another radio cannot save into the new radio', () async {
    final old = node.scope;
    node.scope = 'bb' * 32;
    await expectLater(node.setBookmarkedMessage(_entry('11' * 32, 'one'),
      isBookmarked: true, expectedNodeKey: old), throwsStateError);
    expect(await node.loadBookmarkedMessages(), isEmpty);
  });

  test('additional-identity recipients stay distinct in one contact', () async {
    final peer = '11' * 32;
    await node.setBookmarkedMessage(_entry(peer, 'identity:${'cc' * 32}:1'), isBookmarked: true);
    expect(node.isMessageBookmarked(BookmarkSourceType.contact, peer, 'identity:${'dd' * 32}:1'), isFalse);
    node.scope = 'bb' * 32;
    expect(await node.loadBookmarkedMessages(), isEmpty);
  });
}
