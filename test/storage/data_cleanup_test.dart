import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/storage/data_root_core.dart';
import 'package:meshcore_open/storage/data_transfer_io.dart';
import 'package:path/path.dart' as p;

// The question of deleting the old data after their copy: when it is asked,
// which old folders it names, and what deleting and keeping leave behind.
// The system folders are stand-ins under a temporary folder, named the way
// the app named its own.

void _write(String path, String contents) {
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(contents);
}

void main() {
  late Directory scratch;
  late String root;
  late String support;
  late String cache;
  late String temporary;
  late String documents;

  void writeState({
    String state = 'done',
    String cleanup = 'pending',
    Map<String, Object?>? sources,
  }) {
    _write(
      p.join(root, DataRoot.transferStateFileName),
      jsonEncode({
        'version': 1,
        'state': state,
        'cleanup': cleanup,
        'sources':
            sources ??
            {
              'support': support,
              'cache': cache,
              'temporary': temporary,
              'documents': documents,
            },
      }),
    );
  }

  Object? cleanupState() => readTransferState(root)!['cleanup'];

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('mco_cleanup_');
    root = p.join(scratch.path, 'userdata');
    _write(p.join(root, DataRoot.lockFileName), '1');
    support = p.join(
      scratch.path,
      'roaming',
      LegacyData.windowsCompany,
      LegacyData.windowsProduct,
    );
    cache = p.join(
      scratch.path,
      'local',
      LegacyData.windowsCompany,
      LegacyData.windowsProduct,
    );
    temporary = p.join(scratch.path, 'tmp');
    documents = p.join(scratch.path, 'documents');
    DataRoot.mode = DataRootMode.portable;
    DataRoot.path = root;
    resetDataTransferForTesting();
  });

  tearDown(() {
    DataRoot.resetForTesting();
    resetDataTransferForTesting();
    scratch.deleteSync(recursive: true);
  });

  test('is asked only after a finished copy, while the question is '
      'open', () async {
    _write(p.join(support, 'shared_preferences.json'), '{}');
    expect(await findDataCleanupOffer(), isNull);
    writeState(state: 'copying');
    expect(await findDataCleanupOffer(), isNull);
    writeState(cleanup: 'declined');
    expect(await findDataCleanupOffer(), isNull);
    writeState(cleanup: 'done');
    expect(await findDataCleanupOffer(), isNull);
    writeState();
    expect(await findDataCleanupOffer(), isNotNull);
    DataRoot.mode = DataRootMode.system;
    expect(await findDataCleanupOffer(), isNull);
  });

  test('waits for a later start than the copy', () async {
    _write(p.join(support, 'shared_preferences.json'), '{}');
    final transfer = await findDataTransferOffer(
      legacy: LegacyDataLocations(
        support: support,
        temporary: temporary,
        cache: cache,
        documents: documents,
      ),
    );
    await transferData(transfer!);

    expect(await findDataCleanupOffer(), isNull);

    resetDataTransferForTesting();
    final offer = await findDataCleanupOffer();
    expect(offer, isNotNull);
    expect(offer!.folders, [support]);
    expect(offer.copiedFolders, isEmpty);
  });

  test('names the old folders there still are, by the names the app gave '
      'them', () async {
    _write(p.join(cache, 'gif_cache', 'a.gif'), 'gif');
    _write(p.join(temporary, LegacyData.tileFolder, 'a.png'), 'png');
    _write(p.join(documents, 'image_codec_models', 'm.onnx'), 'model');
    final stranger = p.join(scratch.path, 'Users');
    _write(p.join(stranger, 'precious.txt'), 'not the app');
    writeState(
      sources: {
        'support': stranger,
        'cache': cache,
        'temporary': temporary,
        'documents': documents,
      },
    );

    final offer = (await findDataCleanupOffer())!;

    expect(offer.folders, [cache]);
    expect(offer.copiedFolders, {
      p.join(temporary, LegacyData.tileFolder): p.join(
        root,
        DataRoot.temporaryFolder,
        LegacyData.tileFolder,
      ),
      p.join(documents, 'image_codec_models'): p.join(
        root,
        DataRoot.documentsFolder,
        'image_codec_models',
      ),
    });
  });

  test('is settled without asking when the old data are gone', () async {
    writeState();

    expect(await findDataCleanupOffer(), isNull);
    expect(cleanupState(), 'done');
  });

  test('deleting takes the app folders whole and only the copied files of '
      'shared ones', () async {
    _write(p.join(support, 'shared_preferences.json'), '12345');
    _write(p.join(cache, 'gif_cache', 'a.gif'), '123');
    final tiles = p.join(temporary, LegacyData.tileFolder);
    _write(p.join(tiles, 'ours.png'), '1234');
    _write(p.join(tiles, 'theirs.png'), 'another app');
    _write(
      p.join(root, DataRoot.temporaryFolder, LegacyData.tileFolder, 'ours.png'),
      '1234',
    );
    final models = p.join(documents, 'image_codec_models');
    _write(p.join(models, 'm.onnx'), '12');
    _write(
      p.join(root, DataRoot.documentsFolder, 'image_codec_models', 'm.onnx'),
      '12',
    );
    writeState();
    final offer = (await findDataCleanupOffer())!;

    expect(await measureDataCleanup(offer), 14);
    expect(await deleteOldData(offer), isEmpty);

    expect(Directory(support).existsSync(), isFalse);
    expect(Directory(p.dirname(support)).existsSync(), isFalse);
    expect(Directory(cache).existsSync(), isFalse);
    expect(Directory(p.dirname(cache)).existsSync(), isFalse);
    expect(File(p.join(tiles, 'ours.png')).existsSync(), isFalse);
    expect(File(p.join(tiles, 'theirs.png')).existsSync(), isTrue);
    expect(Directory(models).existsSync(), isFalse);
    expect(Directory(documents).existsSync(), isTrue);
    expect(
      File(
        p.join(root, DataRoot.temporaryFolder, LegacyData.tileFolder, 'ours.png'),
      ).existsSync(),
      isTrue,
    );
    expect(cleanupState(), 'done');
  });

  test('a company folder that holds something else stays', () async {
    _write(p.join(support, 'shared_preferences.json'), '{}');
    final neighbour = p.join(
      p.dirname(support),
      'meshcore_open',
      'shared_preferences.json',
    );
    _write(neighbour, '{}');
    writeState();

    await deleteOldData((await findDataCleanupOffer())!);

    expect(Directory(support).existsSync(), isFalse);
    expect(File(neighbour).existsSync(), isTrue);
  });

  test(
    'a file held open keeps its folder, and the question stays open',
    () async {
      final held = File(p.join(support, 'message_history.sqlite'));
      _write(held.path, 'db');
      _write(p.join(support, 'shared_preferences.json'), '{}');
      writeState();
      final handle = held.openSync(mode: FileMode.append);
      addTearDown(handle.closeSync);

      final remaining = await deleteOldData((await findDataCleanupOffer())!);

      expect(remaining, [support]);
      expect(held.existsSync(), isTrue);
      expect(
        File(p.join(support, 'shared_preferences.json')).existsSync(),
        isFalse,
      );
      expect(cleanupState(), 'pending');
    },
    skip: Platform.isWindows
        ? null
        : 'only Windows keeps an open file from being deleted',
  );

  test('keeping the data settles the question', () async {
    _write(p.join(support, 'shared_preferences.json'), '{}');
    writeState();

    await declineDataCleanup((await findDataCleanupOffer())!);

    expect(cleanupState(), 'declined');
    expect(Directory(support).existsSync(), isTrue);
    expect(await findDataCleanupOffer(), isNull);
  });
}
