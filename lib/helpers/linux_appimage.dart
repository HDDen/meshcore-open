import 'package:path/path.dart' as p;

import '../storage/data_root_core.dart';

/// Finds the launcher outside the read-only AppImage mount. Matching the
/// inner executable to APPDIR avoids using inherited values in a plain bundle.
String linuxAppImageLauncher({
  required String executablePath,
  required Map<String, String> environment,
  required p.Context context,
}) {
  final appDir = environment['APPDIR'];
  final image = environment['APPIMAGE'];
  if (appDir == null ||
      image == null ||
      !context.isAbsolute(appDir) ||
      !context.isAbsolute(image)) {
    return executablePath;
  }
  final inner = context.join(appDir, 'usr', 'bin', LegacyData.linuxExecutableName);
  if (!context.equals(executablePath, inner) ||
      context.equals(image, appDir) ||
      context.isWithin(appDir, image)) {
    return executablePath;
  }
  return image;
}
