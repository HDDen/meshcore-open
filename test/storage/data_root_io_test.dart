import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/storage/data_root_core.dart';
import 'package:meshcore_open/storage/data_root_io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences_linux/shared_preferences_linux.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_windows/shared_preferences_windows.dart';

// The data folder at work: the path_provider answers and the preference
// stores sent into it, its lock, and the start that ties them together. The
// Windows and Linux providers both run on any host, since what they answer
// is a folder of the data folder and nothing of the system. prepareDataRoot
// is only ever called here with an explicit --data-dir: without one it would
// make a folder next to the test runner's executable.

final String _sep = Platform.pathSeparator;

/// The support folder a preference store writes its file into.
Future<String?> _storeSupport(Object store) => switch (store) {
  SharedPreferencesWindows s => s.pathProvider.getApplicationSupportPath(),
  SharedPreferencesAsyncWindows s => s.pathProvider.getApplicationSupportPath(),
  SharedPreferencesLinux s => s.pathProvider.getApplicationSupportPath(),
  SharedPreferencesAsyncLinux s => s.pathProvider.getApplicationSupportPath(),
  _ => throw ArgumentError.value(store),
};

void main() {
  late Directory root;
  late PathProviderPlatform savedPaths;
  late SharedPreferencesStorePlatform savedStore;
  late SharedPreferencesAsyncPlatform? savedAsyncStore;

  String inRoot(String name) => '${root.path}$_sep$name';

  setUp(() {
    root = Directory.systemTemp.createTempSync('mco_data_root_');
    savedPaths = PathProviderPlatform.instance;
    savedStore = SharedPreferencesStorePlatform.instance;
    savedAsyncStore = SharedPreferencesAsyncPlatform.instance;
  });

  tearDown(() async {
    await releaseDataRootLock();
    PathProviderPlatform.instance = savedPaths;
    SharedPreferencesStorePlatform.instance = savedStore;
    SharedPreferencesAsyncPlatform.instance = savedAsyncStore;
    DataRoot.resetForTesting();
    root.deleteSync(recursive: true);
  });

  for (final windows in [true, false]) {
    group(windows ? 'Windows paths' : 'Linux paths', () {
      test('each kind of directory is a folder of the data folder, made when '
          'first asked for', () async {
        redirectPaths(root.path, windows: windows);

        expect(Directory(inRoot('support')).existsSync(), isFalse);
        expect((await getApplicationSupportDirectory()).path, inRoot('support'));
        expect((await getApplicationCacheDirectory()).path, inRoot('cache'));
        expect((await getTemporaryDirectory()).path, inRoot('temp'));
        expect(
          (await getApplicationDocumentsDirectory()).path,
          inRoot('documents'),
        );
        for (final name in ['support', 'cache', 'temp', 'documents']) {
          expect(Directory(inRoot(name)).existsSync(), isTrue, reason: name);
        }
      });

      test('the preference store writes its file into the support '
          'folder', () async {
        final SharedPreferencesStorePlatform store = windows
            ? SharedPreferencesWindows()
            : SharedPreferencesLinux();
        SharedPreferencesStorePlatform.instance = store;

        redirectPaths(root.path, windows: windows);

        expect(await _storeSupport(store), inRoot('support'));
        expect(await store.setValue('String', 'flutter.where', 'here'), isTrue);
        final file = File('${inRoot('support')}${_sep}shared_preferences.json');
        expect(file.readAsStringSync(), contains('flutter.where'));
      });

      test('the asynchronous preference store takes the same folder', () async {
        final SharedPreferencesAsyncPlatform store = windows
            ? SharedPreferencesAsyncWindows()
            : SharedPreferencesAsyncLinux();
        SharedPreferencesAsyncPlatform.instance = store;

        redirectPaths(root.path, windows: windows);

        expect(await _storeSupport(store), inRoot('support'));
      });
    });
  }

  group('lock', () {
    test('the first copy takes it and writes its process id', () async {
      expect(
        await lockDataRoot(root.path, patience: Duration.zero),
        isA<DataRootReady>(),
      );
      expect(File(inRoot('profile.lock')).readAsStringSync().trim(), '$pid');
    });

    test('a folder that cannot be made is unavailable', () async {
      final file = File(inRoot('file'))..writeAsStringSync('x');
      final folder = '${file.path}${_sep}data';

      final outcome = await lockDataRoot(folder, patience: Duration.zero);

      expect(outcome, isA<DataRootUnavailable>());
      outcome as DataRootUnavailable;
      expect(outcome.path, folder);
      expect(outcome.error, isNotNull);
      expect(outcome.missingPath, isFalse);
    });

    test(
      'another copy holding it keeps this one out',
      () async {
        expect(
          await lockDataRoot(root.path, patience: Duration.zero),
          isA<DataRootReady>(),
        );

        final second = await lockDataRoot(
          root.path,
          patience: Duration.zero,
          processId: -1,
        );

        expect(second, isA<DataRootInUse>());
        expect((second as DataRootInUse).path, root.path);
      },
      skip: Platform.isWindows
          ? null
          : 'a POSIX lock belongs to the process, so another copy needs a '
                'process of its own',
    );

    test('a lock this process already holds counts as taken', () async {
      expect(
        await lockDataRoot(root.path, patience: Duration.zero),
        isA<DataRootReady>(),
      );
      expect(
        await lockDataRoot(root.path, patience: Duration.zero),
        isA<DataRootReady>(),
      );
    });

    test('a released lock can be taken again', () async {
      expect(
        await lockDataRoot(root.path, patience: Duration.zero),
        isA<DataRootReady>(),
      );
      await releaseDataRootLock();

      expect(
        await lockDataRoot(root.path, patience: Duration.zero, processId: -1),
        isA<DataRootReady>(),
      );
    });
  });

  group('start', () {
    final portableHost = Platform.isWindows || Platform.isLinux;
    const notPortable = 'the data folder is portable on Windows and Linux only';

    test(
      'a folder given at start is the data folder, with its paths and its '
      'lock',
      () async {
        final folder = inRoot('profile');
        final args = ['--data-dir=$folder', '--other'];

        expect(await prepareDataRoot(args), isA<DataRootReady>());

        expect(DataRoot.mode, DataRootMode.portable);
        expect(DataRoot.path, folder);
        expect(DataRoot.launchArguments, args);
        expect(
          (await getApplicationSupportDirectory()).path,
          '$folder${_sep}support',
        );
        expect(File('$folder${_sep}profile.lock').existsSync(), isTrue);
      },
      skip: portableHost ? null : notPortable,
    );

    test(
      'an empty --data-dir stops the start before any folder is touched',
      () async {
        final outcome = await prepareDataRoot(['--data-dir=']);

        expect(outcome, isA<DataRootUnavailable>());
        expect((outcome as DataRootUnavailable).missingPath, isTrue);
        expect(DataRoot.mode, DataRootMode.system);
        expect(PathProviderPlatform.instance, same(savedPaths));
      },
      skip: portableHost ? null : notPortable,
    );
  });
}
