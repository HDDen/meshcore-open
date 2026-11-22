import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/bookmarked_message.dart';
import 'package:meshcore_open/widgets/message_bookmark.dart';

class _Node extends ChangeNotifier implements MeshCoreConnector {
  String key = 'aa' * 32;
  BookmarkedMessage? saved;
  @override
  String get storageKeyHex => key;
  @override
  bool isMessageBookmarked(BookmarkSourceType type, String source, String id) => saved?.messageId == id;
  @override
  Future<void> setBookmarkedMessage(BookmarkedMessage entry,
      {required bool isBookmarked, String? expectedNodeKey}) async {
    if (expectedNodeKey != key) {
      throw StateError('changed');
    }
    saved = isBookmarked ? entry : null;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final outgoing in [false, true]) {
    testWidgets('bookmark keeps the avatar gap without shifting or resizing the bubble ($outgoing)', (tester) async {
      const bodyKey = ValueKey('bookmark-body');
      Widget app(bool marked) => MaterialApp(home: Scaffold(body: SizedBox(
        width: 400,
        child: Row(mainAxisAlignment: outgoing ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [Flexible(child: MessageBookmarkBadge(marked: marked,
            child: const SizedBox(key: bodyKey, width: 80, height: 40)))],
        ),
      )));
      await tester.pumpWidget(app(false));
      final original = tester.getRect(find.byKey(bodyKey));
      await tester.pumpWidget(app(true));
      final body = tester.getRect(find.byKey(bodyKey));
      final icon = tester.getRect(find.byIcon(Icons.bookmark));
      expect(body.left - icon.right, 6);
      expect(icon.top - body.top, 16);
      expect(body, original);
      expect(body.width, 80);
      expect(tester.takeException(), isNull);
    });
  }

  for (final changeNode in [false, true]) {
    testWidgets('bookmark action uses the menu radio scope (changed=$changeNode)', (tester) async {
      final node = _Node();
      addTearDown(node.dispose);
      final entry = BookmarkedMessage(sourceType: BookmarkSourceType.contact,
        sourceId: 'bb' * 32, sourceName: 'Peer', messageId: 'one', senderName: 'Peer',
        text: 'text', timestamp: DateTime(2026), receivedAt: DateTime(2026), isOutgoing: false);
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Builder(builder: (context) => TextButton(
          onPressed: () => showModalBottomSheet<void>(context: context,
            builder: (_) => MessageBookmarkAction(connector: node, bookmark: entry)),
          child: const Text('open'),
        ))),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      if (changeNode) {
        node.key = 'cc' * 32;
      }
      await tester.tap(find.byType(ListTile));
      await tester.pumpAndSettle();
      expect(node.saved, changeNode ? isNull : same(entry));
      expect(find.byType(MessageBookmarkAction), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
