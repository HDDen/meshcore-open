import 'package:path/path.dart' as p;

/// Where this run keeps its data.
enum DataRootMode {
  /// Windows and Linux: a folder of the app's own, `userdata` next to the
  /// executable or the one `--data-dir` names, holding every directory the
  /// app writes to.
  portable,

  /// macOS, Android, iOS and the web: the system directories path_provider
  /// answers.
  system,
}

/// The data folder of this run and the arguments the app was started with,
/// recorded once at startup by `prepareDataRoot`.
abstract final class DataRoot {
  static const String argument = '--data-dir';
  static const String defaultFolderName = 'userdata';
  static const String lockFileName = 'profile.lock';

  /// The folders of a portable data folder, one per kind of directory the
  /// app asks path_provider for.
  static const String supportFolder = 'support';
  static const String cacheFolder = 'cache';
  static const String temporaryFolder = 'temp';
  static const String documentsFolder = 'documents';

  static DataRootMode mode = DataRootMode.system;

  /// The portable data folder; null in system mode.
  static String? path;

  /// What `main` received, `--data-dir` included, for a restart to hand on.
  static List<String> launchArguments = const [];

  static void resetForTesting() {
    mode = DataRootMode.system;
    path = null;
    launchArguments = const [];
  }
}

/// What the arguments and the executable's place say about the data folder.
class DataRootSelection {
  const DataRootSelection.system()
    : mode = DataRootMode.system,
      path = null,
      missingPath = false;

  const DataRootSelection.portable(String this.path)
    : mode = DataRootMode.portable,
      missingPath = false;

  /// `--data-dir` with nothing after it: the start stops rather than
  /// guessing which folder was meant.
  const DataRootSelection.missingPath()
    : mode = DataRootMode.portable,
      path = null,
      missingPath = true;

  final DataRootMode mode;
  final String? path;
  final bool missingPath;
}

/// The data folder for [args]. A relative `--data-dir` and the default
/// `userdata` count from the folder of [executablePath], not from the working
/// directory, so a shortcut or a terminal elsewhere opens the same folder.
/// [context] is the path style of the platform, handed in so both styles can
/// be tested anywhere. Where [portable] is false the app keeps the system
/// directories and the argument is ignored. The last `--data-dir` wins.
DataRootSelection selectDataRoot({
  required List<String> args,
  required String executablePath,
  required bool portable,
  required p.Context context,
}) {
  if (!portable) return const DataRootSelection.system();
  final appFolder = context.dirname(executablePath);
  String? given;
  for (final arg in args) {
    if (arg == DataRoot.argument) {
      given = '';
    } else if (arg.startsWith('${DataRoot.argument}=')) {
      given = arg.substring(DataRoot.argument.length + 1);
    }
  }
  if (given == null) {
    return DataRootSelection.portable(
      context.join(appFolder, DataRoot.defaultFolderName),
    );
  }
  var value = given.trim();
  // `--data-dir="C:\My Data\"` arrives as `C:\My Data"`, the closing
  // backslash read as an escape of the quote. No Windows name holds a quote.
  if (context.style == p.Style.windows) value = value.replaceAll('"', '');
  if (value.isEmpty) return const DataRootSelection.missingPath();
  return DataRootSelection.portable(
    context.normalize(
      context.isAbsolute(value) ? value : context.join(appFolder, value),
    ),
  );
}

/// How preparing the data folder ended.
sealed class DataRootOutcome {
  const DataRootOutcome();
}

final class DataRootReady extends DataRootOutcome {
  const DataRootReady();
}

/// The app cannot start on this data folder; [path] is shown to the user.
sealed class DataRootProblem extends DataRootOutcome {
  const DataRootProblem(this.path);

  final String path;
}

/// Another running copy of the app holds the folder's lock.
final class DataRootInUse extends DataRootProblem {
  const DataRootInUse(super.path);
}

/// The folder cannot be created or written to, or `--data-dir` named none
/// ([missingPath]).
final class DataRootUnavailable extends DataRootProblem {
  const DataRootUnavailable(super.path, {this.error, this.missingPath = false});

  final Object? error;
  final bool missingPath;
}
