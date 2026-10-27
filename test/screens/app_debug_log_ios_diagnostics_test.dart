import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:meshcore_open/helpers/ios_execution_diagnostics.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/screens/app_debug_log_screen.dart';
import 'package:meshcore_open/services/app_debug_log_service.dart';

import '../helpers/ios_execution_diagnostics_fixture.dart';

void main() {
  final messenger = TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger;
  const channel = MethodChannel('mco_test/copy_ios_diagnostics');

  for (final olderRunner in [false, true]) {
    testWidgets('copy captures a fresh read-only iOS snapshot, olderRunner=$olderRunner', (tester) async {
      final logs = AppDebugLogService()..setEnabled(true)..info('existing entry');
      final calls = <String>[];
      String? copied;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (olderRunner) {
          throw MissingPluginException();
        }
        return {...iosExecutionDiagnosticsFixture(), 'source': 'requested'};
      });
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      try {
        await tester.pumpWidget(ChangeNotifierProvider.value(
          value: logs,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: AppDebugLogScreen(readDiagnostics: () =>
                readIosExecutionDiagnostics(isIos: true, channel: channel)),
          ),
        ));
        expect(calls, isEmpty);
        await tester.tap(find.byIcon(Icons.copy));
        await tester.pumpAndSettle();
        expect(calls, ['diagnostics']);
        expect(copied, contains('existing entry'));
        expect(copied, contains('[iOSExecutionStats]'));
        expect(copied, contains(olderRunner ? 'older runner' : 'source=requested'));
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        messenger.setMockMethodCallHandler(channel, null);
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
        logs.dispose();
      }
    });
  }
}
