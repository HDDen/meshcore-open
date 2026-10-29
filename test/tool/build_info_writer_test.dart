import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/write_build_info.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('mcoa-build-info-');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  test('writes current app/module SHA and dirty flags into ignored build metadata', () {
    Directory('${root.path}/lib_serv/.git').createSync(recursive: true);
    final defines = collectGitBuildInfo(root, readGit: (directory, args) {
      final app = directory.path == root.path;
      if (args.first == 'rev-parse') return (app ? 'a' : 'b') * 40;
      return app ? ' M lib/main.dart' : '';
    });
    final file = writeGitBuildInfo(root, defines);
    expect(jsonDecode(file.readAsStringSync()), {
      'MCO_APP_COMMIT': 'a' * 40,
      'MCO_MODULE_COMMIT': 'b' * 40,
      'MCO_APP_DIRTY': true,
      'MCO_MODULE_DIRTY': false,
    });
    expect(file.parent.uri, Directory('${root.path}/.dart_tool').uri);
    // Re-running before another launch replaces the previous commit.
    defines['MCO_APP_COMMIT'] = 'c' * 40;
    writeGitBuildInfo(root, defines);
    expect(jsonDecode(file.readAsStringSync())['MCO_APP_COMMIT'], 'c' * 40);
  });

  test('an ordinary module folder does not borrow the app repository identity', () {
    Directory('${root.path}/lib_serv').createSync();
    final defines = collectGitBuildInfo(root, readGit: (directory, args) {
      expect(directory.path, root.path);
      return args.first == 'rev-parse' ? 'a' * 40 : '';
    });
    expect(defines['MCO_MODULE_COMMIT'], '');
    expect(defines['MCO_MODULE_DIRTY'], isFalse);
  });

  test('a worktree Git file is a module repository; invalid SHA fails', () {
    Directory('${root.path}/lib_serv').createSync();
    File('${root.path}/lib_serv/.git').writeAsStringSync('gitdir: synthetic');
    final defines = collectGitBuildInfo(root, readGit: (directory, args) =>
      args.first == 'rev-parse' ? 'd' * 40 : ' M changed');
    expect(defines['MCO_MODULE_COMMIT'], 'd' * 40);
    expect(defines['MCO_MODULE_DIRTY'], isTrue);
    expect(() => collectGitBuildInfo(root, readGit: (_, _) => 'short'),
      throwsFormatException);
  });
}
