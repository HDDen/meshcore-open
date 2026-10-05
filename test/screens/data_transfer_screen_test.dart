import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/screens/data_transfer_screen.dart';
import 'package:meshcore_open/storage/data_root_core.dart';

// The screens of the copy of an earlier installation's data: the question,
// the progress, the failure.

DataTransferOffer _offer({List<DataTransferRecord> copiedBefore = const []}) =>
    DataTransferOffer(
      target: r'D:\MCO\userdata',
      legacy: const LegacyDataLocations(support: r'C:\old', temporary: r'C:\tmp'),
      sources: const [r'C:\old'],
      copiedBefore: copiedBefore,
    );

void main() {
  testWidgets('the question names the folders and the size, and the copy '
      'is answered once', (tester) async {
    final answers = <bool>[];
    await tester.pumpWidget(
      DataTransferOfferApp(
        offer: _offer(
          copiedBefore: [
            DataTransferRecord(DateTime.utc(2026, 10, 5, 9), r'E:\other'),
          ],
        ),
        size: Future.value(1536),
        onDecided: answers.add,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Data of an earlier installation found'), findsOneWidget);
    expect(find.textContaining(r'D:\MCO\userdata'), findsOneWidget);
    expect(find.text(r'C:\old'), findsOneWidget);
    expect(find.text('Size: 1.5 KB'), findsOneWidget);
    expect(find.textContaining(r'E:\other'), findsOneWidget);

    await tester.tap(find.text('Copy'));
    await tester.pump();
    await tester.tap(find.text('Start with empty data'));
    await tester.pump();

    expect(answers, [true]);
  });

  testWidgets('empty data is the other answer', (tester) async {
    final answers = <bool>[];
    await tester.pumpWidget(
      DataTransferOfferApp(
        offer: _offer(),
        size: Future.value(0),
        onDecided: answers.add,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('These data have already been copied:'), findsNothing);
    await tester.tap(find.text('Start with empty data'));
    await tester.pump();

    expect(answers, [false]);
  });

  testWidgets('the size reads as counting until it is counted', (
    tester,
  ) async {
    final size = Completer<int>();
    await tester.pumpWidget(
      DataTransferOfferApp(
        offer: _offer(),
        size: size.future,
        onDecided: (_) {},
      ),
    );
    await tester.pump();
    expect(find.text('Size: counting…'), findsOneWidget);

    // The future reports in a microtask after the pump that runs it, so the
    // rebuild it asks for comes with the next frame.
    size.complete(3 * 1024 * 1024);
    await tester.pumpAndSettle();
    expect(find.text('Size: 3.0 MB'), findsOneWidget);
  });

  testWidgets('the progress shows the bytes copied of the total', (
    tester,
  ) async {
    final progress = ValueNotifier<(int, int)>((0, 2048));
    await tester.pumpWidget(DataTransferProgressApp(progress: progress));
    await tester.pump();
    expect(find.text('Copied 0 B of 2.0 KB'), findsOneWidget);

    progress.value = (1024, 2048);
    await tester.pump();
    expect(find.text('Copied 1.0 KB of 2.0 KB'), findsOneWidget);
  });

  testWidgets('a failed copy says why', (tester) async {
    await tester.pumpWidget(const DataTransferFailedApp(error: 'disk full'));
    await tester.pumpAndSettle();

    expect(find.text('The data could not be copied'), findsOneWidget);
    expect(find.text('Details: disk full'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
  });
}
