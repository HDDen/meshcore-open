/// Removing the registry entries of the one notification identity every build
/// before the data folder registered, once no copy of such a build is running
/// any more. Windows only, through `dart:ffi`: the question whether a copy
/// still serves that identity is COM's to answer, and the two keys are
/// deleted with one registry call each. Everywhere else the call is a no-op.
library;

export 'legacy_notification_registry_stub.dart'
    if (dart.library.io) 'legacy_notification_registry_io.dart';
