/// Filled by the release wrapper or VSCode's tool/write_build_info.dart task.
/// Direct flutter run/build needs the generated --dart-define-from-file.
const appGitCommit = String.fromEnvironment('MCO_APP_COMMIT');
const moduleGitCommit = String.fromEnvironment('MCO_MODULE_COMMIT');
const appGitDirty = bool.fromEnvironment('MCO_APP_DIRTY');
const moduleGitDirty = bool.fromEnvironment('MCO_MODULE_DIRTY');

/// Prevent an old positive cache from being reused by a different build.
const appBuildIdentity = '$appGitCommit:$moduleGitCommit:$appGitDirty:$moduleGitDirty';
