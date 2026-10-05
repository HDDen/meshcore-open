import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/services/map_tile_cache_service.dart';
import 'package:meshcore_open/storage/data_root_core.dart';
import 'package:meshcore_open/storage/data_transfer_io.dart';
import 'package:meshcore_open/storage/map_tile_cache_database.dart';
import 'package:meshcore_open/storage/message_history_storage.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

// The copy of an earlier installation's data into a new data folder: where
// the old folders were, when the copy is offered, what it takes and what it
// leaves, and what a copy cut short or failed leaves behind. The system
// folders are stand-ins under a temporary folder. The test with databases
// needs a native sqlite3 and is skipped where the host has none.

String? _sqliteProblem() {
  try {
    sqlite3.openInMemory().close();
    return null;
  } on Object catch (error) {
    return 'sqlite3 is not available to this test host: $error';
  }
}

void _write(String path, String contents) {
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(contents);
}

Set<String> _names(String folder) => {
  for (final entity in Directory(folder).listSync()) p.basename(entity.path),
};

void main() {
  final sqliteSkip = _sqliteProblem();
  late Directory scratch;
  late String root;
  late LegacyDataLocations legacy;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('mco_transfer_');
    root = p.join(scratch.path, 'userdata');
    _write(p.join(root, DataRoot.lockFileName), '1');
    legacy = LegacyDataLocations(
      support: p.join(scratch.path, 'roaming', 'app'),
      temporary: p.join(scratch.path, 'tmp'),
      cache: p.join(scratch.path, 'local', 'app'),
      documents: p.join(scratch.path, 'documents'),
    );
    DataRoot.mode = DataRootMode.portable;
    DataRoot.path = root;
  });

  tearDown(() {
    DataRoot.resetForTesting();
    scratch.deleteSync(recursive: true);
  });

  test('the old folder names match the runners and the stores', () {
    final runner = File('windows/runner/Runner.rc').readAsStringSync();
    expect(
      runner,
      contains('VALUE "CompanyName", "${LegacyData.windowsCompany}"'),
    );
    expect(
      runner,
      contains('VALUE "ProductName", "${LegacyData.windowsProduct}"'),
    );
    final cmake = File('linux/CMakeLists.txt').readAsStringSync();
    expect(
      cmake,
      contains('set(APPLICATION_ID "${LegacyData.linuxApplicationId}")'),
    );
    expect(
      cmake,
      contains('set(BINARY_NAME "${LegacyData.linuxExecutableName}")'),
    );
    expect(LegacyData.databases, [
      MessageHistoryStorage.databaseFileName,
      MapTileCacheDatabase.databaseFileName,
    ]);
    expect(LegacyData.tileDatabase, MapTileCacheDatabase.databaseFileName);
    expect(LegacyData.tileFolder, MapTileCacheService.cacheKey);
  });

  group('the old system folders', () {
    final windows = p.Context(style: p.Style.windows);
    final posix = p.Context(style: p.Style.posix);

    LegacyDataLocations? onLinux(
      Map<String, String> environment, {
      bool Function(String path)? exists,
    }) => legacyDataLocations(
      windows: false,
      environment: environment,
      systemTemp: '/ignored',
      documents: '/home/u/Documents',
      exists: exists ?? (_) => false,
      context: posix,
    );

    test('on Windows are the roaming and local application data', () {
      final found = legacyDataLocations(
        windows: true,
        environment: {
          'APPDATA': r'C:\Users\u\AppData\Roaming',
          'LOCALAPPDATA': r'C:\Users\u\AppData\Local',
        },
        systemTemp: r'C:\Users\u\AppData\Local\Temp',
        documents: r'C:\Users\u\Documents',
        exists: (_) => false,
        context: windows,
      )!;
      expect(
        found.support,
        r'C:\Users\u\AppData\Roaming\com.meshcore\meshcore_open (Advanced mod)',
      );
      expect(
        found.cache,
        r'C:\Users\u\AppData\Local\com.meshcore\meshcore_open (Advanced mod)',
      );
      expect(found.temporary, r'C:\Users\u\AppData\Local\Temp');
      expect(found.documents, r'C:\Users\u\Documents');
    });

    test('on Windows need the roaming folder', () {
      expect(
        legacyDataLocations(
          windows: true,
          environment: const {},
          systemTemp: r'C:\Temp',
          documents: null,
          exists: (_) => false,
          context: windows,
        ),
        isNull,
      );
    });

    test('on Linux follow the XDG variables', () {
      final found = onLinux({
        'HOME': '/home/u',
        'XDG_DATA_HOME': '/data',
        'XDG_CACHE_HOME': '/cache',
        'TMPDIR': '/scratch',
      })!;
      expect(found.support, '/data/com.monitormx.mcoadvanced');
      expect(found.cache, '/cache/com.monitormx.mcoadvanced');
      expect(found.temporary, '/scratch');
      expect(found.documents, '/home/u/Documents');
    });

    test('on Linux fall back to the folders in the home', () {
      final found = onLinux({'HOME': '/home/u'})!;
      expect(found.support, '/home/u/.local/share/com.monitormx.mcoadvanced');
      expect(found.cache, '/home/u/.cache/com.monitormx.mcoadvanced');
      expect(found.temporary, '/tmp');
    });

    test('on Linux take the folder named after the executable when the one '
        'named after the application id is missing', () {
      const byName = '/home/u/.local/share/mco_advanced';
      final found = onLinux(
        {'HOME': '/home/u'},
        exists: (path) => path == byName,
      )!;
      expect(found.support, byName);
    });

    test('on Linux need a home', () {
      expect(onLinux(const {}), isNull);
    });
  });

  test('the marker records each copy and skips lines it cannot read', () {
    final at = DateTime.utc(2026, 10, 5, 12, 30);
    final text =
        '$copiedMarkerHeader'
        '${copiedMarkerLine(at, r'D:\MCO\userdata')}'
        'not a record\n'
        '${copiedMarkerLine(at, '/home/u/mco/userdata')}';

    final records = parseCopiedMarker(text);

    expect(records.map((record) => record.target), [
      r'D:\MCO\userdata',
      '/home/u/mco/userdata',
    ]);
    expect(records.first.at, at);
  });

  group('a new data folder', () {
    test('holds nothing but its housekeeping files', () {
      expect(isNewDataFolder(p.join(scratch.path, 'missing')), isTrue);
      expect(isNewDataFolder(root), isTrue);
      _write(p.join(root, DataRoot.windowStateFileName), '1280 720');
      expect(isNewDataFolder(root), isTrue);
      _write(p.join(root, 'notes.txt'), 'mine');
      expect(isNewDataFolder(root), isFalse);
    });

    test('is what a copy cut short leaves, once cleared', () async {
      _write(p.join(legacy.support, 'shared_preferences.json'), '{}');
      _write(p.join(root, DataRoot.windowStateFileName), '1280 720');
      _write(
        p.join(root, DataRoot.transferStateFileName),
        '{"state":"copying"}',
      );
      _write(p.join(root, 'support.partial', 'shared_preferences.json'), '{}');
      _write(p.join(root, 'temp', LegacyData.tileFolder, 'a.png'), 'a');

      expect(await findDataTransferOffer(legacy: legacy), isNotNull);
      expect(_names(root), {
        DataRoot.lockFileName,
        DataRoot.windowStateFileName,
      });
    });

    test('is not made of a finished copy', () {
      _write(p.join(root, DataRoot.transferStateFileName), '{"state":"done"}');
      _write(p.join(root, 'support', 'shared_preferences.json'), '{}');

      clearInterruptedTransfer(root);

      expect(
        File(p.join(root, 'support', 'shared_preferences.json')).existsSync(),
        isTrue,
      );
      expect(isNewDataFolder(root), isFalse);
    });
  });

  group('the offer', () {
    test('lists the folders there are', () async {
      _write(p.join(legacy.support, 'shared_preferences.json'), '{}');

      final offer = await findDataTransferOffer(legacy: legacy);

      expect(offer, isNotNull);
      expect(offer!.target, root);
      expect(offer.sources, [legacy.support]);
      expect(offer.copiedBefore, isEmpty);
    });

    test('needs data in the old folder', () async {
      expect(await findDataTransferOffer(legacy: legacy), isNull);
      _write(
        p.join(legacy.support, LegacyData.copiedMarkerFileName),
        copiedMarkerHeader,
      );
      expect(await findDataTransferOffer(legacy: legacy), isNull);
    });

    test('is not made to a folder already in use', () async {
      _write(p.join(legacy.support, 'shared_preferences.json'), '{}');
      _write(p.join(root, 'support', 'shared_preferences.json'), '{}');

      expect(await findDataTransferOffer(legacy: legacy), isNull);
    });

    test('is not made where the system folders are kept', () async {
      _write(p.join(legacy.support, 'shared_preferences.json'), '{}');
      DataRoot.mode = DataRootMode.system;

      expect(await findDataTransferOffer(legacy: legacy), isNull);
    });

    test('counts the bytes the copy takes', () async {
      _write(p.join(legacy.support, 'shared_preferences.json'), '12345');
      _write(p.join(legacy.support, LegacyData.sharedImageCacheIndex), '{}');
      _write(p.join(legacy.cache!, 'gif_cache', 'a.gif'), '123');

      final offer = await findDataTransferOffer(legacy: legacy);

      expect(await measureDataTransfer(offer!), 8);
    });

    test('is made again to another new folder, noting the earlier '
        'copy', () async {
      _write(p.join(legacy.support, 'shared_preferences.json'), '{}');
      await transferData((await findDataTransferOffer(legacy: legacy))!);

      DataRoot.path = p.join(scratch.path, 'profile2');
      final offer = await findDataTransferOffer(legacy: legacy);

      expect(offer, isNotNull);
      expect(offer!.copiedBefore.single.target, root);
    });
  });

  test('the copy takes what the app uses and leaves the originals', () async {
    final support = legacy.support;
    _write(p.join(support, 'shared_preferences.json'), '{"flutter.a":1}');
    _write(p.join(support, LegacyData.sharedImageCacheIndex), '{}');
    _write(p.join(support, 'mcoimg_packs', 'pack', 'info.json'), '{}');
    // The history with rows still in its log, as a running copy keeps it.
    final history = sqlite3.open(p.join(support, 'message_history.sqlite'));
    addTearDown(history.close);
    history
      ..execute('PRAGMA journal_mode = WAL')
      ..execute('CREATE TABLE messages (text TEXT)')
      ..execute("INSERT INTO messages VALUES ('one'), ('two')");
    final tiles = sqlite3.open(p.join(support, LegacyData.tileDatabase));
    tiles
      ..execute('CREATE TABLE tile_records (relative_path TEXT NOT NULL)')
      ..execute("INSERT INTO tile_records VALUES ('kept.png')")
      ..close();
    final oldTiles = p.join(legacy.temporary, LegacyData.tileFolder);
    _write(p.join(oldTiles, 'kept.png'), 'tile');
    _write(p.join(oldTiles, 'orphan.png'), 'left by an old cache');
    _write(p.join(legacy.cache!, 'gif_cache', 'a.gif'), 'gif');
    final codec = p.join(legacy.documents!, 'image_codec_models');
    final translation = p.join(legacy.documents!, 'translation_models');
    _write(p.join(codec, 'model.onnx'), 'model');
    _write(p.join(translation, 'model.gguf'), 'model');

    final offer = await findDataTransferOffer(legacy: legacy);
    expect(offer, isNotNull);
    expect(offer!.sources, [
      support,
      legacy.cache,
      oldTiles,
      codec,
      translation,
    ]);
    final progress = <(int, int)>[];

    await transferData(
      offer,
      onProgress: (copied, total) => progress.add((copied, total)),
    );

    String inRoot(List<String> parts) => p.joinAll([root, ...parts]);
    expect(
      File(inRoot(['support', 'shared_preferences.json'])).readAsStringSync(),
      '{"flutter.a":1}',
    );
    expect(
      File(inRoot(['support', LegacyData.sharedImageCacheIndex])).existsSync(),
      isFalse,
    );
    expect(
      File(inRoot(['support', 'mcoimg_packs', 'pack', 'info.json'])).existsSync(),
      isTrue,
    );
    final copy = sqlite3.open(
      inRoot(['support', 'message_history.sqlite']),
      mode: OpenMode.readOnly,
    );
    addTearDown(copy.close);
    expect(
      copy
          .select('SELECT text FROM messages ORDER BY rowid')
          .map((row) => row['text']),
      ['one', 'two'],
    );
    expect(
      File(inRoot(['support', LegacyData.tileDatabase])).existsSync(),
      isTrue,
    );
    expect(
      File(inRoot(['temp', LegacyData.tileFolder, 'kept.png'])).existsSync(),
      isTrue,
    );
    expect(
      File(inRoot(['temp', LegacyData.tileFolder, 'orphan.png'])).existsSync(),
      isFalse,
    );
    expect(
      File(inRoot(['cache', 'gif_cache', 'a.gif'])).readAsStringSync(),
      'gif',
    );
    expect(
      File(
        inRoot(['documents', 'image_codec_models', 'model.onnx']),
      ).existsSync(),
      isTrue,
    );
    expect(
      File(
        inRoot(['documents', 'translation_models', 'model.gguf']),
      ).existsSync(),
      isTrue,
    );
    expect(_names(root).where((name) => name.endsWith('.partial')), isEmpty);
    final state = readTransferState(root)!;
    expect(state['state'], 'done');
    expect(state['cleanup'], 'pending');

    final marker = File(p.join(support, LegacyData.copiedMarkerFileName));
    expect(parseCopiedMarker(marker.readAsStringSync()).single.target, root);
    expect(
      File(p.join(support, LegacyData.sharedImageCacheIndex)).existsSync(),
      isTrue,
    );
    expect(File(p.join(oldTiles, 'orphan.png')).existsSync(), isTrue);
    expect(progress.last.$2, greaterThan(0));
    expect(progress.last.$1, progress.last.$2);
    expect(await findDataTransferOffer(legacy: legacy), isNull);
  }, skip: sqliteSkip);

  test('a failed copy leaves the data folder as it was and the old data '
      'untouched', () async {
    _write(p.join(legacy.support, 'shared_preferences.json'), '{"flutter.a":1}');
    _write(p.join(legacy.cache!, 'gif_cache', 'a.gif'), 'gif');
    final offer = await findDataTransferOffer(legacy: legacy);
    // A file where the cache folder is to be made.
    _write(p.join(root, 'cache.partial'), 'in the way');

    await expectLater(
      transferData(offer!),
      throwsA(isA<DataTransferException>()),
    );

    expect(_names(root), {DataRoot.lockFileName});
    expect(
      File(p.join(legacy.support, 'shared_preferences.json')).readAsStringSync(),
      '{"flutter.a":1}',
    );
    expect(
      File(p.join(legacy.support, LegacyData.copiedMarkerFileName)).existsSync(),
      isFalse,
    );
  });
}
