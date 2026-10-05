import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/services/image_codec_file_store.dart';
import 'package:meshcore_open/services/received_image_blob_store_io.dart';
import 'package:meshcore_open/services/translation_file_store.dart';
import 'package:meshcore_open/storage/map_tile_cache_database.dart';
import 'package:meshcore_open/storage/mco_image_gallery_store.dart';
import 'package:meshcore_open/storage/message_history_database.dart';
import 'package:meshcore_open/storage/message_history_maintenance.dart';
import 'package:meshcore_open/storage/message_history_storage.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Which kind of directory each store keeps its files in, as path_provider
// answers at the moment the store asks. Every kind is a folder of its own
// here, so a store that moves to another kind, or stops asking path_provider,
// fails. Copying the data of one installation into another, kind by kind,
// relies on exactly this layout. The database tests need a native sqlite3
// the host can load and are skipped where it cannot.

const MethodChannel _pathProvider = MethodChannel(
  'plugins.flutter.io/path_provider',
);

/// The path_provider methods the app calls, and the folder each one answers.
const Map<String, String> _kinds = {
  'getApplicationSupportDirectory': 'support',
  'getApplicationCacheDirectory': 'cache',
  'getTemporaryDirectory': 'temp',
  'getApplicationDocumentsDirectory': 'documents',
};

Future<String?> _sqliteProblem() async {
  try {
    final database = MessageHistoryDatabase.withExecutor(
      NativeDatabase.memory(),
    );
    await database.customSelect('SELECT 1').get();
    await database.close();
    return null;
  } catch (error) {
    return 'sqlite3 is not available to this test host: $error';
  }
}

/// Paths compared whatever separator a store joined them with.
String _normalized(String path) => path.replaceAll(r'\', '/');

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final sqliteSkip = await _sqliteProblem();
  late Directory root;

  String folder(String kind) => '${root.path}${Platform.pathSeparator}$kind';

  String inFolder(String kind, String name) =>
      '${folder(kind)}${Platform.pathSeparator}$name';

  setUp(() {
    root = Directory.systemTemp.createTempSync('mco_storage_locations_');
    for (final kind in _kinds.values) {
      Directory(folder(kind)).createSync();
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProvider, (call) async {
          final kind = _kinds[call.method];
          return kind == null ? null : folder(kind);
        });
  });

  tearDown(() {
    PrefsManager.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProvider, null);
    root.deleteSync(recursive: true);
  });

  test('the history database is a file in the support directory', () async {
    final database = MessageHistoryDatabase();
    await database.customSelect('SELECT 1').get();
    await database.close();

    final expected = inFolder(
      'support',
      MessageHistoryStorage.databaseFileName,
    );
    expect(File(expected).existsSync(), isTrue);
    expect(await MessageHistoryMaintenance().databasePath(), expected);
  }, skip: sqliteSkip);

  test(
    'the tile record database and the old JSON index it replaces are in the '
    'support directory',
    () async {
      const url = 'https://tile.openstreetmap.org/1/0/0.png';
      final index = File(
        inFolder('support', MapTileCacheDatabase.legacyIndexFileName),
      );
      final json = JsonCacheInfoRepository.withFile(index);
      await json.open();
      await json.insert(
        CacheObject(
          url,
          key: url,
          relativePath: 'tile.png',
          validTill: DateTime.utc(2030),
        ),
      );
      await json.close();

      final repository = await MapTileCacheRepository.openForThisPlatform(
        useDatabase: true,
      );

      expect(repository, isNotNull);
      addTearDown(repository!.database.close);
      expect(await repository.database.countRecords(), 1);
      expect(index.existsSync(), isFalse);
      expect(
        File(
          inFolder('support', MapTileCacheDatabase.databaseFileName),
        ).existsSync(),
        isTrue,
      );
    },
    skip: sqliteSkip,
  );

  test('received images are in the support directory', () async {
    expect(
      _normalized(await FileReceivedImageBlobStore().ensureReady()),
      _normalized(inFolder('support', 'received_images')),
    );
  });

  test('installed image packs are in the support directory', () async {
    expect(
      _normalized(await MCOImageGalleryStore().packsDirectoryPath()),
      _normalized(inFolder('support', 'mcoimg_packs')),
    );
  });

  test('image codec models are in the documents directory', () async {
    expect(
      _normalized(await ImageCodecFileStore().modelDirectoryPath()),
      _normalized(inFolder('documents', 'image_codec_models')),
    );
  });

  test('translation models are in the documents directory', () async {
    expect(
      _normalized(await TranslationFileStore().modelDirectoryPath()),
      _normalized(inFolder('documents', 'translation_models')),
    );
  });

  test(
    'the preferences file is repaired in the support directory',
    () async {
      final file = File(inFolder('support', PrefsManager.fileName))
        ..writeAsStringSync('{"flutter.cut":');
      File(
        '${file.path}${PrefsManager.backupSuffix}',
      ).writeAsStringSync('{"flutter.kept":1}');
      SharedPreferences.setMockInitialValues({});
      PrefsManager.reset();

      await PrefsManager.initialize();

      expect(file.readAsStringSync(), '{"flutter.kept":1}');
    },
    skip: Platform.isWindows || Platform.isLinux
        ? null
        : 'the preferences file is repaired on Windows and Linux only',
  );
}
