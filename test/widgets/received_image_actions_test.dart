import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/image_codec_support.dart';
import 'package:meshcore_open/services/received_image_store.dart';
import 'package:meshcore_open/widgets/received_image_actions.dart';

void main() {
  for (final outgoing in [false, true]) {
    for (final secondary in [false, true]) {
      testWidgets(
        'AEIC actions cover metadata: outgoing=$outgoing, right click=$secondary',
        (tester) async {
          final store = ReceivedImageStore(processAutomatically: false);
          addTearDown(store.dispose);
          final registered = await store.registerOutgoing(
            channelIndex: 0,
            senderPrefix: 0x1111,
            imgId: 1,
            previewPng: Uint8List(1),
            bitstream: Uint8List(1),
            rate: AeicRatePoint.ft32,
            chunkCount: 1,
          );
          final json = registered.toJson()..['isOutgoing'] = outgoing;
          final entry = ReceivedImageEntry.fromJson(json);
          var primaryTaps = 0;
          await tester.pumpWidget(
            MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('en'),
              home: Scaffold(
                body: ReceivedImageActions(
                  entry: entry,
                  store: store,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => primaryTaps++,
                        child: const SizedBox(
                          key: Key('image'),
                          width: 200,
                          height: 150,
                          child: ColoredBox(color: Colors.grey),
                        ),
                      ),
                      const SizedBox(
                        key: Key('metadata'),
                        width: 200,
                        height: 40,
                        child: ColoredBox(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.byKey(const Key('image')));
          await tester.pump();
          expect(primaryTaps, 1);
          expect(find.text('Packet info'), findsNothing);
          if (secondary) {
            await tester.tap(
              find.byKey(const Key('metadata')),
              kind: PointerDeviceKind.mouse,
              buttons: kSecondaryMouseButton,
            );
          } else {
            await tester.longPress(find.byKey(const Key('metadata')));
          }
          await tester.pumpAndSettle();
          expect(find.text('Packet info'), findsOneWidget);
          expect(find.text('Decode again'), findsOneWidget);
          expect(find.text('Delete'), findsOneWidget);
          expect(primaryTaps, 1);
          await tester.tap(find.text('Packet info'));
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsOneWidget);
          expect(find.text('1 of 1 packets'), findsOneWidget);
          await tester.tap(find.text('Close'));
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const Key('metadata')),
            kind: PointerDeviceKind.mouse,
            buttons: kSecondaryMouseButton,
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Delete'));
          await tester.pumpAndSettle();
          expect(store.entryFor(entry.streamId), isNull);
        },
      );
    }
  }
}
