import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/legacy_notification_registry_io.dart';
import 'package:meshcore_open/helpers/windows_notification_identity.dart';

// The removal of the legacy notification identity: the GUID bytes COM is
// handed, the keys it names, and the start that has nothing to remove, which
// must ask COM nothing. Whether a running copy is found is COM's business and
// is checked on a machine.

void main() {
  test('a GUID is laid out as COM reads it', () {
    expect(
      LegacyNotificationRegistry.guidBytes(
        WindowsNotificationIdentity.legacyGuid,
      ),
      [
        0x85, 0x8f, 0xea, 0xe7, 0xf5, 0x72, 0x36, 0x4f, //
        0x91, 0xf6, 0x03, 0x8f, 0x74, 0x0c, 0xcf, 0x86,
      ],
    );
    expect(
      LegacyNotificationRegistry.guidBytes(
        '00000001-0000-0000-c000-000000000046',
      ),
      [1, 0, 0, 0, 0, 0, 0, 0, 0xc0, 0, 0, 0, 0, 0, 0, 0x46],
    );
  });

  test('a string that is not a GUID is refused', () {
    expect(
      () => LegacyNotificationRegistry.guidBytes('e7ea8f8572f54f3691f6038f740ccf86'),
      throwsArgumentError,
    );
    expect(
      () => LegacyNotificationRegistry.guidBytes(
        '{e7ea8f85-72f5-4f36-91f6-038f740ccf8}',
      ),
      throwsArgumentError,
    );
  });

  test('the keys are the two the plugin writes for the legacy id', () {
    expect(LegacyNotificationRegistry.keys, [
      r'Software\Classes\AppUserModelId\org.meshcore.open.app',
      r'Software\Microsoft\Windows\CurrentVersion\PushNotifications\Backup'
          r'\org.meshcore.open.app',
    ]);
  });

  test(
    'keys that do not exist are reported absent without asking COM',
    () {
      final stamp = DateTime.now().microsecondsSinceEpoch;
      expect(
        LegacyNotificationRegistry.removeWhenUnusedSync(
          keys: [
            'Software\\MeshCoreOpen\\test-$stamp\\a',
            'Software\\MeshCoreOpen\\test-$stamp\\b',
          ],
          activatorGuid: WindowsNotificationIdentity.legacyGuid,
        ),
        LegacyNotificationCleanup.absent,
      );
    },
    skip: Platform.isWindows ? null : 'reads the Windows registry',
  );
}
