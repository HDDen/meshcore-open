import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:path_provider_linux/path_provider_linux.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_windows/path_provider_windows.dart';
import 'package:shared_preferences_linux/shared_preferences_linux.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_windows/shared_preferences_windows.dart';

import 'data_root_core.dart';

/// The byte the lock covers, past anything written to the file, so that the
/// process id at its start stays readable while another copy holds the lock.
const int _lockedByte = 4096;

RandomAccessFile? _lock;

/// Chooses the data folder, sends every path_provider answer into it and
/// takes its lock. Runs first in `main`, before anything reads or writes a
/// file. Only an explicit `--data-dir` may be used in tests: without one the
/// folder would be made next to the test runner's executable.
Future<DataRootOutcome> prepareDataRoot(List<String> args) async {
  DataRoot.launchArguments = List.unmodifiable(args);
  if (Platform.isWindows || Platform.isLinux) {
    final selection = selectDataRoot(
      args: args,
      executablePath: Platform.resolvedExecutable,
      portable: true,
      context: p.context,
    );
    final folder = selection.path;
    if (folder == null) {
      return const DataRootUnavailable(
        '${DataRoot.argument}=',
        missingPath: true,
      );
    }
    DataRoot.mode = DataRootMode.portable;
    DataRoot.path = folder;
    redirectPaths(folder, windows: Platform.isWindows);
    return lockDataRoot(folder);
  }
  if (Platform.isMacOS) {
    return lockDataRoot((await getApplicationSupportDirectory()).path);
  }
  return const DataRootReady();
}

/// Sends the four directories the app asks path_provider for into [root],
/// each a folder of its own, made when first asked for. The preference stores
/// of Windows and Linux keep a path provider of their own and get the same
/// one, or they would go on writing to the system folder.
void redirectPaths(String root, {required bool windows}) {
  final store = SharedPreferencesStorePlatform.instance;
  final asyncStore = SharedPreferencesAsyncPlatform.instance;
  // The stores' path provider fields are marked for tests, but nothing else
  // sets their folder.
  if (windows) {
    final provider = _PortableWindowsPaths(root);
    PathProviderPlatform.instance = provider;
    if (store is SharedPreferencesWindows) {
      // ignore: invalid_use_of_visible_for_testing_member
      store.pathProvider = provider;
    }
    if (asyncStore is SharedPreferencesAsyncWindows) {
      // ignore: invalid_use_of_visible_for_testing_member
      asyncStore.pathProvider = provider;
    }
  } else {
    final provider = _PortableLinuxPaths(root);
    PathProviderPlatform.instance = provider;
    if (store is SharedPreferencesLinux) {
      // ignore: invalid_use_of_visible_for_testing_member
      store.pathProvider = provider;
    }
    if (asyncStore is SharedPreferencesAsyncLinux) {
      // ignore: invalid_use_of_visible_for_testing_member
      asyncStore.pathProvider = provider;
    }
  }
}

/// Takes the lock of [folder], making the folder and its lock file when they
/// are missing. A lock another copy holds answers [DataRootInUse] once
/// [patience] has passed: the restart after the history migration starts the
/// new process just before the old one exits. A lock this process already
/// holds counts as taken: a hot restart leaves the previous isolate's file
/// open, and on Windows a lock belongs to the handle, not to the process.
/// [processId] stands in for this process in tests.
Future<DataRootOutcome> lockDataRoot(
  String folder, {
  Duration patience = const Duration(seconds: 2),
  int? processId,
}) async {
  final lockPath = p.join(folder, DataRoot.lockFileName);
  final RandomAccessFile handle;
  try {
    await Directory(folder).create(recursive: true);
    handle = await File(lockPath).open(mode: FileMode.append);
  } on FileSystemException catch (error) {
    return DataRootUnavailable(folder, error: error);
  }
  final deadline = DateTime.now().add(patience);
  while (true) {
    try {
      await handle.lock(FileLock.exclusive, _lockedByte, _lockedByte + 1);
      break;
    } on FileSystemException {
      if (await _heldBy(lockPath, processId ?? pid)) {
        await handle.close();
        return const DataRootReady();
      }
      if (!DateTime.now().isBefore(deadline)) {
        await handle.close();
        return DataRootInUse(folder);
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }
  try {
    await handle.truncate(0);
    await handle.setPosition(0);
    await handle.writeString('$pid\n');
    await handle.flush();
  } on FileSystemException catch (error) {
    await handle.close();
    return DataRootUnavailable(folder, error: error);
  }
  _lock = handle;
  return const DataRootReady();
}

Future<bool> _heldBy(String lockPath, int processId) async {
  try {
    final owner = int.tryParse((await File(lockPath).readAsString()).trim());
    return owner == processId;
  } on FileSystemException {
    return false;
  }
}

/// Lets the lock go before the process ends on purpose, as the restart after
/// the history migration does; the new process waits for it.
Future<void> releaseDataRootLock() async {
  final handle = _lock;
  _lock = null;
  if (handle == null) return;
  try {
    await handle.unlock(_lockedByte, _lockedByte + 1);
  } on FileSystemException {
    // Closing the file lets the lock go as well.
  }
  await handle.close();
}

/// The four path_provider answers of a portable data folder.
mixin _PortablePaths on PathProviderPlatform {
  String get root;

  Future<String> _folder(String name) async {
    final directory = Directory(p.join(root, name));
    if (!directory.existsSync()) await directory.create(recursive: true);
    return directory.path;
  }

  @override
  Future<String?> getApplicationSupportPath() =>
      _folder(DataRoot.supportFolder);

  @override
  Future<String?> getApplicationCachePath() => _folder(DataRoot.cacheFolder);

  @override
  Future<String?> getTemporaryPath() => _folder(DataRoot.temporaryFolder);

  @override
  Future<String?> getApplicationDocumentsPath() =>
      _folder(DataRoot.documentsFolder);
}

/// Extends the platform's own provider, which the Windows preference store's
/// field is typed as; whatever this does not answer stays the platform's.
class _PortableWindowsPaths extends PathProviderWindows with _PortablePaths {
  _PortableWindowsPaths(this.root);

  @override
  final String root;
}

class _PortableLinuxPaths extends PathProviderLinux with _PortablePaths {
  _PortableLinuxPaths(this.root);

  @override
  final String root;
}
