import 'app_logger.dart';

/// Common optional-module logging contract. Return false while logging is off
/// so a module can defer recording; avoid observer notifications during I/O.
bool logModuleDiagnostic(
  String message,
  String tag,
  String level, {
  AppLogger? logger,
}) {
  final output = logger ?? appLogger;
  if (!output.isEnabled) return false;
  switch (level) {
    case 'error':
      output.error(message, tag: tag, noNotify: true);
    case 'warning':
      output.warn(message, tag: tag, noNotify: true);
    default:
      output.info(message, tag: tag, noNotify: true);
  }
  return true;
}
