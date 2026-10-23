import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/helpers/background_work_tracker.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/services/message_retry_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoPreferencesDirectory extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async {
    throw MissingPluginException('synthetic preferences without a directory');
  }
}

class _Connector extends MeshCoreConnector {
  final route = Completer<void>();
  int routeClears = 0;

  @override
  bool get isConnected => true;

  @override
  Future<void> clearContactPath(Contact contact, {bool waitForAck = false}) {
    routeClears++;
    return route.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PathProviderPlatform savedPaths;
  setUpAll(() {
    savedPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _NoPreferencesDirectory();
  });
  tearDownAll(() {
    PathProviderPlatform.instance = savedPaths;
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });
  tearDown(PrefsManager.reset);

  testWidgets('connector shares its tracker with real retry configuration and retains cancelled route work', (tester) async {
    final c = _Connector();
    final retry = MessageRetryService();
    try {
      retry.setSendingPaused(true);
      c.attachRetryServiceForTest(retry);
      await retry.sendMessageWithRetry(
        contact: Contact(
          publicKey: Uint8List.fromList(List.generate(32, (i) => i + 1)),
          name: 'synthetic contact',
          type: advTypeChat,
          pathLength: 1,
          path: Uint8List.fromList([0xAB]),
          pathOverride: -1,
          lastSeen: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        ),
        text: 'synthetic message',
        preparedOutboundText: 'synthetic message',
        messageId: 'retry-binding',
      );
      await tester.pump();
      expect(c.backgroundWorkSnapshot.isBusy, isFalse);
      expect(retry.pendingMessageCount.value, 1);
      retry.setSendingPaused(false);
      await tester.pump();
      expect(c.routeClears, 1);
      expect(c.backgroundWorkSnapshot.countFor(BackgroundWorkKind.retry), 2);
      expect(c.backgroundWorkSnapshot.activeCount, 2);
      retry.untrack('retry-binding');
      expect(c.backgroundWorkSnapshot.countFor(BackgroundWorkKind.retry), 1);
      expect(retry.pendingMessageCount.value, 0);
      c.route.complete();
      await tester.pump();
      expect(c.backgroundWorkSnapshot.isBusy, isFalse);
    } finally {
      retry.setSendingPaused(true);
      if (!c.route.isCompleted) {
        c.route.complete();
      }
      await tester.pump();
      c.dispose();
      retry.dispose();
      await tester.pump(const Duration(seconds: 61));
    }
  }, timeout: const Timeout(Duration(seconds: 30)));
}
