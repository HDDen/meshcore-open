import 'dart:typed_data' as typed;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/widgets/contact_location_request_button.dart';

Contact _contact(int type, {bool active = true}) => Contact(
  publicKey: typed.Uint8List.fromList(List<int>.filled(32, 7)),
  name: 'Synthetic node', type: type, isActive: active,
  pathLength: -1, path: typed.Uint8List(0), lastSeen: DateTime.utc(2026),
);

void main() {
  for (final locale in ['en', 'ru']) {
    testWidgets('map location action is explicit, bounded and fits large text ($locale)', (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var taps = 0;
      Future<void> show(Contact contact, {bool connected = true, bool busy = false, bool locating = false}) async {
        await tester.pumpWidget(MaterialApp(
          key: UniqueKey(),
          locale: Locale(locale),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(body: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: ContactLocationRequestButton(
                contact: contact, isConnected: connected, busy: busy,
                locating: locating, onPressed: () => taps++,
              ),
            ),
          )),
        ));
        await tester.pump();
        expect(tester.takeException(), isNull);
      }

      for (final type in [advTypeRepeater, advTypeRoom]) {
        await show(_contact(type));
        expect(find.byType(OutlinedButton), findsNothing);
      }
      await show(_contact(advTypeChat, active: false));
      expect(find.byType(OutlinedButton), findsNothing);
      expect(taps, 0);

      for (final type in [advTypeChat, advTypeSensor]) {
        await show(_contact(type));
        expect(find.text(locale == 'ru' ? 'Обновить позицию' : 'Update location'), findsOneWidget);
        expect(tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed, isNotNull);
        await tester.tap(find.byType(OutlinedButton));
        await tester.pump();
      }
      expect(taps, 2);
      await show(_contact(advTypeChat), connected: false);
      expect(tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed, isNull);
      await show(_contact(advTypeChat), busy: true, locating: true);
      expect(tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed, isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(taps, 2);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }
}
