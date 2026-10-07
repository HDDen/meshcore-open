import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../storage/data_root_core.dart';

/// The identity a copy of the app shows its Windows notifications under.
///
/// A click on a toast reaches the app through COM: the notifications plugin
/// registers a class object for its activator GUID in every running
/// process, Windows asks COM for that GUID, and with one GUID for every copy
/// COM hands the click to whichever process it finds first. The app user
/// model id is shared the same way: its registry entry names one activator,
/// written by the copy that started last. Both therefore come from the data
/// folder, so every copy and every `--data-dir` profile has an identity of
/// its own, the same at every launch, and the click lands in the copy that
/// showed the notification. The display name carries the folder, so Windows
/// lists the copies apart in its notification settings.
class WindowsNotificationIdentity {
  const WindowsNotificationIdentity({
    required this.appUserModelId,
    required this.guid,
    required this.displayName,
  });

  /// The one identity of every build before the data folder, and the
  /// namespace the per-folder GUIDs are derived in.
  static const String legacyAppUserModelId = 'org.meshcore.open.app';
  static const String legacyGuid = 'e7ea8f85-72f5-4f36-91f6-038f740ccf86';

  /// For the data folder at [dataPath], or the legacy identity when the app
  /// runs on the system directories ([dataPath] null). [context] is the
  /// path style, Windows at runtime, handed in for the tests.
  factory WindowsNotificationIdentity.forDataFolder(
    String? dataPath, {
    required String appName,
    p.Context? context,
  }) {
    if (dataPath == null) {
      return WindowsNotificationIdentity(
        appUserModelId: legacyAppUserModelId,
        guid: legacyGuid,
        displayName: appName,
      );
    }
    final ctx = context ?? p.context;
    final normalized = ctx.normalize(dataPath);
    // A Windows path names one folder whatever its case.
    final key = ctx.style == p.Style.windows
        ? normalized.toLowerCase()
        : normalized;
    final guid = const Uuid().v5(legacyGuid, key);
    final label = _label(normalized, ctx);
    return WindowsNotificationIdentity(
      appUserModelId:
          '$legacyAppUserModelId.${guid.replaceAll('-', '').substring(0, 16)}',
      guid: guid,
      displayName: label == null ? appName : '$appName ($label)',
    );
  }

  /// The folder's name, or the app folder's for the default `userdata`;
  /// null at a drive root, which has no name worth showing.
  static String? _label(String path, p.Context ctx) {
    var folder = path;
    if (ctx.basename(folder).toLowerCase() == DataRoot.defaultFolderName) {
      folder = ctx.dirname(folder);
    }
    final name = ctx.basename(folder);
    return name.isEmpty || ctx.rootPrefix(name) == name ? null : name;
  }

  final String appUserModelId;
  final String guid;
  final String displayName;
}
