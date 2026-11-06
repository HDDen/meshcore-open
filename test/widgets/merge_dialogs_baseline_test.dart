import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/helpers/link_handler.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/models/path_history.dart';
import 'package:meshcore_open/services/path_history_service.dart';
import 'package:meshcore_open/widgets/routing_sheet.dart';

Contact _contact(String name, List<int> prefix, int type) => Contact(
  publicKey: Uint8List(32)..setRange(0, prefix.length, prefix),
  name: name,
  type: type,
  pathLength: -1,
  path: Uint8List(0),
  lastSeen: DateTime.utc(2026, 1, 1),
);

class _RepeaterActivity extends ValueNotifier<int> {
  _RepeaterActivity() : super(0);

  bool get hasObservers => hasListeners;
}

// Read-only UI fixture: no connector constructor, native plugins or storage.
// An unexpected operation (including applying a route) fails the test.
class _Routes extends ChangeNotifier implements MeshCoreConnector {
  final List<Contact> entries;

  _Routes(this.entries);

  @override
  final _RepeaterActivity repeaterActivity = _RepeaterActivity();

  @override
  List<Contact> get contacts => entries;

  @override
  List<Contact> get allContacts => entries;

  @override
  int get pathHashByteWidth => 3;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #directRepeaters) {
      return <Never>[];
    }
    throw StateError('Unexpected routing operation: ${invocation.memberName}');
  }

  @override
  void dispose() {
    repeaterActivity.dispose();
    super.dispose();
  }
}

class _History extends ChangeNotifier implements PathHistoryService {
  final PathRecord record;

  _History({int repeats = 1}) : record = PathRecord(
    hopCount: 2 * repeats,
    tripTimeMs: 1500,
    timestamp: DateTime.utc(2026, 1, 1),
    wasFloodDiscovery: false,
    pathBytes: [
      for (var i = 0; i < repeats; i++) ...[0xa1, 0xb2, 0xc3, 0xd4],
    ],
    successCount: 1,
    failureCount: 0,
  );

  @override
  List<PathRecord> getRecentPaths(String contactPubKeyHex) => [record];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #getFloodStats) {
      return null;
    }
    throw StateError('Unexpected history operation: ${invocation.memberName}');
  }
}

Future<void> _show(
  WidgetTester tester,
  Locale locale,
  Widget home, {
  Widget Function(Widget)? wrap,
  Size size = const Size(1100, 1800),
  double textScale = 1,
  double keyboardInset = 0,
  BoxConstraints? dialogConstraints,
}) async {
  // Baseline defaults stay roomy; new layout cases explicitly constrain space.
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboardInset);
  final app = MaterialApp(
    locale: locale,
    theme: ThemeData(dialogTheme: DialogThemeData(constraints: dialogConstraints)),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: home,
  );
  await tester.pumpWidget(wrap == null ? app : wrap(app));
  await tester.pump();
}

Future<void> _settleDialog(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _scrollDialog(WidgetTester tester) async {
  // SelectableText also owns a Scrollable; use the overflowing vertical
  // viewport rather than assuming that the first descendant is the dialog.
  final scrolling = tester.stateList<ScrollableState>(find.descendant(
    of: find.byType(AlertDialog),
    matching: find.byType(Scrollable),
  )).where((state) => state.position.axis == Axis.vertical &&
      state.position.maxScrollExtent > 0).toList();
  expect(scrolling, isNotEmpty);
  final position = scrolling.first.position;
  position.jumpTo(position.maxScrollExtent);
  await tester.pump();
  expect(position.pixels, greaterThan(0));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const browser = MethodChannel('plugins.flutter.io/url_launcher');
  final launches = <MethodCall>[];
  var launchSucceeds = true;

  setUp(() {
    launches.clear();
    launchSucceeds = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(browser, (call) async {
          launches.add(call);
          return call.method == 'launch' && launchSucceeds;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(browser, null);
  });

  for (final language in ['en', 'ru']) {
    for (final action in ['cancel', 'open', 'failure']) {
      testWidgets('U11b2 baseline: external link $action ($language)', (tester) async {
        const url = 'https://example.invalid/article?source=synthetic';
        Future<void>? result;
        try {
          await _show(tester, Locale(language), Scaffold(
            body: Builder(builder: (context) => TextButton(
              onPressed: () {
                result = LinkHandler.handleLinkTap(context, url);
              },
              child: const Text('Open synthetic link'),
            )),
          ));
          final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)));
          await tester.tap(find.text('Open synthetic link'));
          await _settleDialog(tester);
          expect(find.text(l10n.chat_openLink), findsOneWidget);
          expect(find.text(l10n.chat_openLinkConfirmation), findsOneWidget);
          expect(find.widgetWithText(SelectableText, url), findsOneWidget);
          expect(launches, isEmpty); // No browser request before consent.

          launchSucceeds = action != 'failure';
          await tester.tap(action == 'cancel'
              ? find.widgetWithText(TextButton, l10n.common_cancel)
              : find.widgetWithText(FilledButton, l10n.chat_open));
          await _settleDialog(tester);
          await result;
          expect(find.byType(AlertDialog), findsNothing);
          if (action == 'cancel') {
            expect(launches, isEmpty);
          } else {
            expect(launches, hasLength(1));
            expect(launches.single.method, 'launch');
            final arguments = launches.single.arguments as Map;
            expect(arguments['url'], url);
            expect(arguments['useWebView'], isFalse);
            if (action == 'failure') {
              expect(find.text(l10n.chat_couldNotOpenLink(url)), findsOneWidget);
              expect(tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor, Colors.red);
            }
          }
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.view.resetViewInsets();
        }
      });
    }

    for (final layout in [
      (name: 'phone', size: const Size(320, 568), inset: 0.0),
      (name: 'landscape', size: const Size(568, 320), inset: 0.0),
      (name: 'keyboard', size: const Size(320, 568), inset: 240.0),
    ]) {
      testWidgets('U11b2: full link scrolls and consent stays reachable ($language, ${layout.name})', (tester) async {
        final url = 'https://example.invalid/${List.filled(30, 'long-segment').join('/')}';
        Future<void>? result;
        try {
          await _show(tester, Locale(language), Scaffold(
            body: Builder(builder: (context) => TextButton(
              onPressed: () {
                result = LinkHandler.handleLinkTap(context, url);
              },
              child: const Text('Open synthetic link'),
            )),
          ), size: layout.size, textScale: 2, keyboardInset: layout.inset);
          await tester.tap(find.text('Open synthetic link'));
          await _settleDialog(tester);
          final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)));
          expect(find.widgetWithText(SelectableText, url), findsOneWidget);
          expect(launches, isEmpty);
          await _scrollDialog(tester);
          final cancel = find.widgetWithText(TextButton, l10n.common_cancel);
          final open = find.widgetWithText(FilledButton, l10n.chat_open);
          expect(cancel.hitTestable(), findsOneWidget);
          expect(open.hitTestable(), findsOneWidget);
          await tester.tap(language == 'en' ? open : cancel);
          await _settleDialog(tester);
          await result;
          expect(find.byType(AlertDialog), findsNothing);
          expect(launches, hasLength(language == 'en' ? 1 : 0));
          if (launches.isNotEmpty) {
            expect((launches.single.arguments as Map)['url'], url);
          }
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.view.resetViewInsets();
        }
      });
    }

    for (final constrained in [false, true]) {
      testWidgets('${constrained ? 'U11b2: long route scrolls in a constrained dialog' : 'U11b2 baseline: route details retain per-path width and do not apply it'} ($language)', (tester) async {
        final contact = _contact('Target', [0x11], advTypeChat);
        final connector = _Routes([
          contact,
          _contact('North', [0xa1, 0xb2], advTypeRepeater),
          _contact('South', [0xc3, 0xd4], advTypeRepeater),
        ]);
        final repeats = constrained ? 8 : 1;
        final history = _History(repeats: repeats);
        try {
          await _show(tester, Locale(language), Scaffold(
            body: Builder(builder: (context) => TextButton(
              onPressed: () => ContactRoutingSheet.show(context, contact: contact),
              child: const Text('Show routing'),
            )),
          ), textScale: constrained ? 2 : 1,
          // Limit only the dialog: the routing sheet's own compact layout is
          // outside this substep. Its real long-press flow is still exercised.
          dialogConstraints: constrained
              ? const BoxConstraints(maxWidth: 240, maxHeight: 300)
              : null,
          wrap: (app) => MultiProvider(
            providers: [
              ChangeNotifierProvider<MeshCoreConnector>.value(value: connector),
              ChangeNotifierProvider<PathHistoryService>.value(value: history),
            ],
            child: app,
          ));
          final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)));
          await tester.tap(find.text('Show routing'));
          await _settleDialog(tester);
          final pathTile = find.byWidgetPredicate(
            (widget) => widget is ListTile && widget.onLongPress != null,
          );
          expect(pathTile, findsOneWidget);
          await tester.ensureVisible(pathTile);
          await tester.longPress(pathTile);
          await _settleDialog(tester);
          final dialog = find.byType(AlertDialog);
          expect(dialog, findsOneWidget);
          expect(find.text(l10n.chat_fullPath), findsOneWidget);
          expect(find.widgetWithText(SelectableText, List.filled(repeats, 'A1B2,C3D4').join(',')), findsOneWidget);
          expect(find.widgetWithText(SelectableText, List.filled(repeats, 'North → South').join(' → ')), findsOneWidget);
          expect(find.descendant(of: dialog, matching: find.text(l10n.contacts_pathTrace)), findsOneWidget);
          if (constrained) {
            await _scrollDialog(tester);
            expect(find.widgetWithText(TextButton, l10n.contacts_pathTrace).hitTestable(), findsOneWidget);
            expect(find.widgetWithText(TextButton, l10n.common_close).hitTestable(), findsOneWidget);
          }
          await tester.tap(find.widgetWithText(TextButton, l10n.common_close));
          await _settleDialog(tester);
          expect(dialog, findsNothing);
          expect(contact.path, isEmpty);
          expect(contact.pathOverride, isNull);
          expect(history.record.pathBytes, [
            for (var i = 0; i < repeats; i++) ...[0xa1, 0xb2, 0xc3, 0xd4],
          ]);
          expect(launches, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          // The panel owns one repeater listener; closing its tree releases it.
          final listenerRemains = connector.repeaterActivity.hasObservers;
          connector.dispose();
          history.dispose();
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.view.resetViewInsets();
          expect(listenerRemains, isFalse);
        }
      });
    }
  }
}
