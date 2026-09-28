import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';

// The preferences file of Windows and Linux before the plugin opens it: a
// copy of a readable file, and a cut file set aside and the copy restored.

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('mco_prefs_file_');
  });

  tearDown(() {
    directory.deleteSync(recursive: true);
  });

  File file() => File(
    '${directory.path}${Platform.pathSeparator}${PrefsManager.fileName}',
  );
  File backup() => File('${file().path}${PrefsManager.backupSuffix}');
  List<File> quarantined() => directory
      .listSync()
      .whereType<File>()
      .where((f) => f.path.contains('.corrupt-'))
      .toList();

  const good = '{"flutter.app_settings":"{}","flutter.x":1}';
  const cut = '{"flutter.app_settings":"{}","flutter.x":';

  test('no file: nothing to do', () async {
    expect(
      await PrefsManager.prepareDesktopPreferencesFile(directory),
      PreferencesFileRepair.absent,
    );
    expect(directory.listSync(), isEmpty);
  });

  test('a file that decodes gets a copy, and the copy follows it', () async {
    file().writeAsStringSync(good);

    expect(
      await PrefsManager.prepareDesktopPreferencesFile(directory),
      PreferencesFileRepair.backedUp,
    );
    expect(backup().readAsStringSync(), good);
    expect(file().readAsStringSync(), good);
    expect(quarantined(), isEmpty);
    expect(File('${backup().path}.tmp').existsSync(), isFalse);

    const newer = '{"flutter.x":2}';
    file().writeAsStringSync(newer);
    await PrefsManager.prepareDesktopPreferencesFile(directory);
    expect(backup().readAsStringSync(), newer);
  });

  test('a cut file is set aside and the copy put in its place', () async {
    file().writeAsStringSync(good);
    await PrefsManager.prepareDesktopPreferencesFile(directory);
    file().writeAsStringSync(cut);

    expect(
      await PrefsManager.prepareDesktopPreferencesFile(directory),
      PreferencesFileRepair.restored,
    );
    expect(file().readAsStringSync(), good);
    expect(backup().readAsStringSync(), good);
    final aside = quarantined();
    expect(aside, hasLength(1));
    expect(aside.single.readAsStringSync(), cut);
  });

  test('a cut file with no usable copy is set aside alone', () async {
    file().writeAsStringSync(cut);

    expect(
      await PrefsManager.prepareDesktopPreferencesFile(directory),
      PreferencesFileRepair.quarantined,
    );
    expect(file().existsSync(), isFalse);
    expect(quarantined(), hasLength(1));

    // A copy that is itself cut is no copy.
    file().writeAsStringSync(cut);
    backup().writeAsStringSync(cut);
    expect(
      await PrefsManager.prepareDesktopPreferencesFile(directory),
      PreferencesFileRepair.quarantined,
    );
    expect(file().existsSync(), isFalse);
  });

  test('an empty file is restored from the copy, or left to the plugin',
      () async {
    file().writeAsStringSync('');

    expect(
      await PrefsManager.prepareDesktopPreferencesFile(directory),
      PreferencesFileRepair.absent,
    );
    expect(file().existsSync(), isTrue);
    expect(quarantined(), isEmpty);

    backup().writeAsStringSync(good);
    expect(
      await PrefsManager.prepareDesktopPreferencesFile(directory),
      PreferencesFileRepair.restored,
    );
    expect(file().readAsStringSync(), good);
    expect(quarantined(), hasLength(1));
  });

  test('a file that is JSON but not a map is unreadable to the plugin',
      () async {
    file().writeAsStringSync('[1, 2, 3]');
    expect(
      await PrefsManager.prepareDesktopPreferencesFile(directory),
      PreferencesFileRepair.quarantined,
    );
  });
}
