import 'package:path/path.dart' as p;

/// A writable-by-convention user location, never the installed program folder.
/// Relative XDG paths are invalid; fall back to an absolute HOME instead.
String? linuxDefaultDataDirectory(Map<String, String> environment, p.Context context) {
  final xdg = environment['XDG_DATA_HOME'];
  final home = environment['HOME'];
  final base = xdg != null && context.isAbsolute(xdg) ? xdg
      : home != null && context.isAbsolute(home) ? context.join(home, '.local', 'share')
      : null;
  return base == null ? null : context.normalize(context.join(base, 'mcoa', 'userdata'));
}
