import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/screens/data_transfer_screen.dart';
import 'package:meshcore_open/storage/data_root_core.dart';

// The screens of the question of deleting the old data, shown before the app
// starts: the question, the deletion running, what it could not remove.

const _support =
    r'C:\Users\u\AppData\Roaming\com.meshcore\meshcore_open (Advanced mod)';
const _tiles = r'C:\Users\u\AppData\Local\Temp\map_tile_cache';

const _offer = DataCleanupOffer(
  target: r'D:\MCO\userdata',
  folders: [_support],
  copiedFolders: {_tiles: r'D:\MCO\userdata\temp\map_tile_cache'},
);

void main() {
  testWidgets('the question names the old folders and their size, and is '
      'answered once', (tester) async {
    final answers = <bool>[];
    await tester.pumpWidget(
      DataCleanupOfferApp(
        offer: _offer,
        size: Future.value(2048),
        onDecided: answers.add,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Delete the old data?'), findsOneWidget);
    expect(find.text(_support), findsOneWidget);
    expect(find.text(_tiles), findsOneWidget);
    expect(find.text('Size: 2.0 KB'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pump();
    await tester.tap(find.text('Keep'));
    await tester.pump();

    expect(answers, [true]);
  });

  testWidgets('keep is the other answer', (tester) async {
    final answers = <bool>[];
    await tester.pumpWidget(
      DataCleanupOfferApp(
        offer: _offer,
        size: Completer<int>().future,
        onDecided: answers.add,
      ),
    );
    await tester.pump();

    expect(find.text('Size: counting…'), findsOneWidget);
    await tester.tap(find.text('Keep'));
    await tester.pump();

    expect(answers, [false]);
  });

  testWidgets('the deletion says it is running', (tester) async {
    await tester.pumpWidget(const DataCleanupProgressApp());
    await tester.pump();

    expect(find.text('Deleting the old data…'), findsOneWidget);
  });

  testWidgets('what could not be removed is listed, and the app goes on '
      'when asked', (tester) async {
    var continued = 0;
    await tester.pumpWidget(
      DataCleanupPartialApp(
        remaining: const [_support],
        onContinue: () => continued++,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('(1)'), findsOneWidget);
    expect(find.text(_support), findsOneWidget);
    await tester.tap(find.text('Continue'));

    expect(continued, 1);
  });
}
