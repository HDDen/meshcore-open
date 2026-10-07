/// The web build: no registry. See `legacy_notification_registry_io.dart`.
enum LegacyNotificationCleanup { absent, removed, inUse, failed }

abstract final class LegacyNotificationRegistry {
  static Future<LegacyNotificationCleanup> removeWhenUnused() async =>
      LegacyNotificationCleanup.absent;
}
