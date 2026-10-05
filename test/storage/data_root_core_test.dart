import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/storage/data_root_core.dart';
import 'package:path/path.dart' as p;

// Which data folder the arguments and the executable's place choose. Both
// path styles run on any host: the style is handed in, not read from it.

void main() {
  final windows = p.Context(style: p.Style.windows);
  final posix = p.Context(style: p.Style.posix);
  const windowsExe = r'D:\Apps\MCO\mco_advanced.exe';
  const linuxExe = '/home/denis/mco/bundle/mco_advanced';

  DataRootSelection onWindows(List<String> args) => selectDataRoot(
    args: args,
    executablePath: windowsExe,
    portable: true,
    context: windows,
  );

  DataRootSelection onLinux(List<String> args) => selectDataRoot(
    args: args,
    executablePath: linuxExe,
    portable: true,
    context: posix,
  );

  group('Windows', () {
    test('no argument: userdata next to the executable', () {
      final selection = onWindows(const []);
      expect(selection.mode, DataRootMode.portable);
      expect(selection.path, r'D:\Apps\MCO\userdata');
      expect(selection.missingPath, isFalse);
    });

    test('an absolute path is taken as it is', () {
      expect(
        onWindows([r'--data-dir=E:\Profiles\Two']).path,
        r'E:\Profiles\Two',
      );
    });

    test('a relative path counts from the executable folder', () {
      expect(
        onWindows([r'--data-dir=profiles\two']).path,
        r'D:\Apps\MCO\profiles\two',
      );
    });

    test('dot segments are folded', () {
      expect(
        onWindows([r'--data-dir=..\shared\.\data']).path,
        r'D:\Apps\shared\data',
      );
    });

    test('forward slashes become backslashes', () {
      expect(
        onWindows(['--data-dir=E:/Profiles/Two']).path,
        r'E:\Profiles\Two',
      );
    });

    test('spaces and Cyrillic are kept', () {
      expect(
        onWindows([r'--data-dir=C:\Мои данные\профиль 2']).path,
        r'C:\Мои данные\профиль 2',
      );
    });

    test('a quote left behind by a closing backslash is dropped', () {
      expect(onWindows([r'--data-dir=C:\My Data"']).path, r'C:\My Data');
    });
  });

  group('Linux', () {
    test('no argument: userdata next to the executable', () {
      expect(onLinux(const []).path, '/home/denis/mco/bundle/userdata');
    });

    test('an absolute path is taken as it is', () {
      expect(onLinux(['--data-dir=/srv/mco/two']).path, '/srv/mco/two');
    });

    test('a relative path counts from the executable folder', () {
      expect(onLinux(['--data-dir=two']).path, '/home/denis/mco/bundle/two');
    });

    test('dot segments are folded', () {
      expect(onLinux(['--data-dir=../data']).path, '/home/denis/mco/data');
    });

    test('a quote is part of a Linux name', () {
      expect(onLinux(['--data-dir=/tmp/a"']).path, '/tmp/a"');
    });
  });

  group('the argument', () {
    test('with an empty value names no folder', () {
      final selection = onWindows(['--data-dir=']);
      expect(selection.missingPath, isTrue);
      expect(selection.path, isNull);
    });

    test('with only spaces names no folder', () {
      expect(onLinux(['--data-dir=   ']).missingPath, isTrue);
    });

    test('without the equals sign names no folder', () {
      expect(onWindows(['--data-dir']).missingPath, isTrue);
    });

    test('given twice takes the last one', () {
      expect(
        onWindows([r'--data-dir=E:\One', r'--data-dir=E:\Two']).path,
        r'E:\Two',
      );
    });

    test('sits among other arguments', () {
      expect(
        onWindows(['--verbose', r'--data-dir=E:\One', 'extra']).path,
        r'E:\One',
      );
    });

    test('is not mistaken for a longer flag', () {
      expect(
        onWindows([r'--data-directory=E:\One']).path,
        r'D:\Apps\MCO\userdata',
      );
    });
  });

  test('platforms with system folders ignore the argument', () {
    final selection = selectDataRoot(
      args: [r'--data-dir=E:\One'],
      executablePath: windowsExe,
      portable: false,
      context: windows,
    );
    expect(selection.mode, DataRootMode.system);
    expect(selection.path, isNull);
    expect(selection.missingPath, isFalse);
  });
}
