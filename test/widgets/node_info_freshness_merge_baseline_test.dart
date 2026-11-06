import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/widgets/mesh_ui.dart';
import 'package:meshcore_open/widgets/node_info_sheet.dart';

class _NoIo extends ChangeNotifier implements MeshCoreConnector {
  int widthReads = 0;

  @override
  int get pathHashByteWidth {
    widthReads++;
    return 2;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Viewing node details must not perform IO: ${invocation.memberName}');
}

String _row(WidgetTester tester, String label) {
  final row = find.descendant(of: find.byType(NodeInfoSheet), matching:
      find.byWidgetPredicate((widget) => widget is NodeInfoRow && widget.label == label));
  expect(row, findsOneWidget);
  final value = tester.widget<NodeInfoRow>(row).value;
  expect(find.descendant(of: row, matching: find.byWidgetPredicate((widget) =>
      widget is SelectableText && widget.data == value)), findsOneWidget);
  return value;
}

Future<void> _withInfo(WidgetTester tester, String locale, Contact contact,
    Future<void> Function(AppLocalizations, ValueNotifier<int>) run, {
  String? lastSeenText,
}) async {
  final connector = _NoIo();
  final actionCalls = ValueNotifier<int>(0);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1100, 1800);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  try {
    await tester.pumpWidget(MaterialApp(
      locale: Locale(locale),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Builder(builder: (context) => TextButton(
        onPressed: () {
          if (lastSeenText == null) {
            // The actual entry point used by nearby-contact details.
            showNodeInfoSheet(context, contact, connector: connector);
          } else {
            // The map supplies its own time label and actions to this widget.
            showMeshSheet<void>(context, builder: (_) => NodeInfoSheet(
              contact: contact,
              pathHashByteWidth: 2,
              lastSeenText: lastSeenText,
              actions: [TextButton(
                key: const ValueKey('owner-action'),
                onPressed: () => actionCalls.value++,
                child: const Text('Owner action'),
              )],
            ));
          }
        },
        child: const Text('Details'),
      ))),
    ));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(tester.element(find.text('Details')));
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.byType(NodeInfoSheet), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing); // No implicit login.
    expect(actionCalls.value, 0);
    expect(_row(tester, l10n.map_path), l10n.chat_hopsCount(1));
    expect(_row(tester, l10n.map_location), '55.750000, 37.620000');
    expect(_row(tester, l10n.map_publicKey), contact.publicKeyHex);
    await run(l10n, actionCalls);
    final close = find.descendant(of: find.byType(NodeInfoSheet), matching:
        find.byWidgetPredicate((widget) => widget is IconButton &&
            widget.icon is Icon && (widget.icon as Icon).icon == Icons.close));
    expect(close.hitTestable(), findsOneWidget);
    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(find.byType(NodeInfoSheet), findsNothing);
    expect(connector.widthReads, lastSeenText == null ? greaterThan(0) : 0);
    expect(tester.takeException(), isNull);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    connector.dispose();
    actionCalls.dispose();
  }
}

void main() {
  for (final locale in ['en', 'ru']) {
    for (final type in [advTypeChat, advTypeRepeater, advTypeRoom, advTypeSensor]) {
      Contact contact({bool withFix = false}) {
        final now = DateTime.now();
        return Contact(
          publicKey: Uint8List.fromList(List.generate(32, (index) => index + 1)),
          name: 'Synthetic node',
          type: type,
          pathLength: 1,
          pathHashWidth: 2,
          path: Uint8List.fromList([0x12, 0x34]),
          latitude: 55.75,
          longitude: 37.62,
          // Wide margins avoid a minute/day boundary during the UI pumps.
          lastSeen: now.subtract(const Duration(days: 3, hours: 6)),
          lastMessageAt: now.subtract(const Duration(hours: 1)),
          telemetryFixAt: withFix ? now.subtract(const Duration(minutes: 20)) : null,
        );
      }

      testWidgets('U11a3 baseline: legacy details retain advert time and full metadata ($locale, type=$type)', (tester) async {
        await _withInfo(tester, locale, contact(), (l10n, actionCalls) async {
          expect(_row(tester, l10n.map_lastSeen), l10n.time_daysAgo(3));
          expect(actionCalls.value, 0);
        });
      });

      testWidgets('U11a3 baseline: owner time label and actions keep priority with a telemetry fix ($locale, type=$type)', (tester) async {
        const label = 'Owner-provided freshness';
        await _withInfo(tester, locale, contact(withFix: true), (l10n, actionCalls) async {
          expect(_row(tester, l10n.map_lastSeen), label);
          final action = find.byKey(const ValueKey('owner-action'));
          expect(action.hitTestable(), findsOneWidget);
          await tester.tap(action);
          await tester.pumpAndSettle();
          expect(actionCalls.value, 1);
          expect(_row(tester, l10n.map_lastSeen), label);
        }, lastSeenText: label);
      });

      testWidgets('U11a3: a newer telemetry fix updates default details without rewriting advert time ($locale, type=$type)', (tester) async {
        final original = contact();
        final updated = original.copyWith(
          telemetryFixAt: DateTime.now().subtract(const Duration(minutes: 20, seconds: 30)),
        );
        await _withInfo(tester, locale, updated, (l10n, actionCalls) async {
          expect(_row(tester, l10n.map_lastSeen), l10n.time_minutesAgo(20));
          expect(updated.lastSeen, original.lastSeen);
          expect(updated.lastMessageAt, original.lastMessageAt);
          expect(actionCalls.value, 0);
        });
      });

      testWidgets('U11a3: an older telemetry fix cannot replace the advert time in details ($locale, type=$type)', (tester) async {
        final original = contact();
        final updated = original.copyWith(
          telemetryFixAt: original.lastSeen.subtract(const Duration(days: 2)),
        );
        await _withInfo(tester, locale, updated, (l10n, actionCalls) async {
          expect(_row(tester, l10n.map_lastSeen), l10n.time_daysAgo(3));
          expect(updated.lastSeen, original.lastSeen);
          expect(updated.lastMessageAt, original.lastMessageAt);
          expect(actionCalls.value, 0);
        });
      });
    }
  }
}
