import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/helpers/contact_removal_guard.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';

class _NoDirectory extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async =>
      throw MissingPluginException('Synthetic removal options');
}

// Full ACK/history/resync coverage adapted from upstream is in
// remove_contact_merge_baseline_test.dart, using native SQLite and the real
// connector ACK queue rather than a complete review-mode app initialization.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PathProviderPlatform originalPaths;
  setUpAll(() {
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _NoDirectory();
  });
  tearDownAll(() => PathProviderPlatform.instance = originalPaths);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });
  tearDown(PrefsManager.reset);

  test('reported auto-add flags cover each supported contact type independently', () {
    final connector = MeshCoreConnector();
    addTearDown(connector.dispose);
    const flags = {
      advTypeChat: autoAddChatFlag,
      advTypeRepeater: autoAddRepeaterFlag,
      advTypeRoom: autoAddRoomServerFlag,
      advTypeSensor: autoAddSensorFlag,
    };
    for (final selected in flags.entries) {
      connector.handleFrameForTest([respCodeAutoAddConfig, selected.value]);
      for (final type in flags.keys) {
        expect(connector.autoAddsContactType(type), type == selected.key);
      }
      expect(connector.autoAddsContactType(255), isFalse);
    }
    connector.handleFrameForTest([respCodeAutoAddConfig, 0]);
    expect(flags.keys.any(connector.autoAddsContactType), isFalse);
  });

  test('removal guard is scoped and retains overlapping removals until both finish', () async {
    final guard = ContactRemovalGuard();
    final first = Completer<void>();
    final second = Completer<void>();
    final a = guard.run(nodeKey: 'A', contactKey: 'target', operation: () => first.future);
    final b = guard.run(nodeKey: 'A', contactKey: 'target', operation: () => second.future);
    expect(guard.isRemoving('A', 'target'), isTrue);
    expect(guard.isRemoving('B', 'target'), isFalse);
    expect(guard.isRemoving('A', 'other'), isFalse);
    first.complete();
    await a;
    expect(guard.isRemoving('A', 'target'), isTrue);
    second.complete();
    await b;
    expect(guard.isRemoving('A', 'target'), isFalse);
  });

  test('failed removal releases the guard and preserves the original error', () async {
    final guard = ContactRemovalGuard();
    final failure = StateError('Synthetic removal failure');
    await expectLater(guard.run(nodeKey: 'A', contactKey: 'target',
        operation: () async => throw failure), throwsA(same(failure)));
    expect(guard.isRemoving('A', 'target'), isFalse);
  });
}
