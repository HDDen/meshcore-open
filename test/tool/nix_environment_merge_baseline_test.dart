import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

// These are source contracts, not a Nix evaluation or a Linux build. They
// protect the public build profiles and portable bundle while the optional
// development environment changes. No private module is needed to run them.
void main() {
  test('U15 baseline: lock entries describe the declared shell inputs', () {
    final flake = _read('flake.nix');
    final lock = jsonDecode(_read('flake.lock')) as Map<String, dynamic>;
    final nodes = lock['nodes'] as Map<String, dynamic>;
    final root = nodes[lock['root']] as Map<String, dynamic>;
    final inputs = root['inputs'] as Map<String, dynamic>;

    expect(lock['version'], 7);
    for (final name in ['nixpkgs', 'flake-utils']) {
      expect(flake, contains('$name.url ='));
      final node = nodes[inputs[name]] as Map<String, dynamic>;
      final locked = node['locked'] as Map<String, dynamic>;
      expect(locked['type'], 'github');
      expect(locked['rev'], matches(RegExp(r'^[0-9a-f]{40}$')));
      expect(locked['narHash'], startsWith('sha256-'));
    }
  });

  test('U15 baseline: entering the shell does not build or change app data', () {
    final match = RegExp(
      r"shellHook\s*=\s*''([\s\S]*?)'';",
    ).firstMatch(_read('flake.nix'));
    expect(match, isNotNull);
    final hook = match!.group(1)!;

    // The existing hook prints SDK installation instructions as a quoted
    // here-document. Those instructions must remain text, never run on entry.
    final executable = hook.replaceAll(
      RegExp(r"cat << 'EOF'\n[\s\S]*?\nEOF"),
      '',
    );
    expect(
      executable,
      isNot(
        matches(
          RegExp(
            r'^\s*(?:curl|wget|flutter|dart|git|nix|rm|cp|mv)\s',
            multiLine: true,
          ),
        ),
      ),
    );
    for (final path in [
      'pubspec.yaml',
      'pubspec_overrides.yaml',
      'use_translation_profile',
      'userdata',
      '--data-dir',
    ]) {
      expect(executable, isNot(contains(path)));
    }
  });

  test('U15 baseline: public profiles keep the stub and vendored USB', () {
    for (final suffix in ['', '.full', '.lite', '.lite-aeic']) {
      final profile = _read('pubspec$suffix.yaml');
      expect(
        profile,
        matches(RegExp(r'mco_service:\s*\n\s+path: packages/mco_service_stub')),
      );
      expect(profile, contains('path: third_party/flserial'));
    }
  });

  test('U15 baseline: Linux owns its bundle prefix and bundled ONNX lookup', () {
    final cmake = _read('linux/CMakeLists.txt');
    expect(cmake, contains('set(BINARY_NAME "mco_advanced")'));
    expect(
      cmake,
      matches(RegExp(
        r'if\(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT\)\s*'
        r'set\(CMAKE_INSTALL_PREFIX "\$\{BUILD_BUNDLE_DIR\}"',
      )),
    );
    expect(cmake, contains(r'set(CMAKE_INSTALL_RPATH "$ORIGIN/lib")'));
    expect(cmake, contains('set(USE_SYSTEM_ONNXRUNTIME OFF CACHE BOOL'));
    expect(cmake, contains('if(TARGET flutter_onnxruntime_plugin)'));
    expect(cmake, contains('RENAME "libonnxruntime.so.1"'));
  });

  test('U15: the shell uses Flutter Dart and a wrapped Linux compiler', () {
    final flake = _read('flake.nix');
    final nativeTools = RegExp(
      r'nativeBuildInputs\s*=\s*with pkgs;\s*\[([\s\S]*?)\];',
    ).firstMatch(flake);
    expect(nativeTools, isNotNull);
    for (final tool in ['cmake', 'ninja', 'pkg-config']) {
      expect(
        nativeTools!.group(1),
        matches(RegExp('^\\s*$tool\\s*' r'$', multiLine: true)),
      );
    }
    expect(flake, matches(RegExp(r'^\s*flutter\s*$', multiLine: true)));
    expect(
      flake,
      isNot(matches(RegExp(r'^\s*(?:dart|libclang)\s*$', multiLine: true))),
    );
    expect(
      flake,
      matches(RegExp(
        r'stdenv\s*=\s*if pkgs\.stdenv\.hostPlatform\.isLinux\s*'
        r'then pkgs\.clangStdenv else pkgs\.stdenv;',
      )),
    );
    expect(flake, isNot(contains('export PKG_CONFIG_PATH=')));
    expect(flake, isNot(contains('export CMAKE_INSTALL_PREFIX=')));
  });

  test('U15: Linux capture and optional secure storage headers stay scoped', () {
    final flake = _read('flake.nix');
    final linuxLibraries = RegExp(
      r'pkgs\.lib\.optionals pkgs\.stdenv\.hostPlatform\.isLinux\s*'
      r'\[([\s\S]*?)\];',
    ).firstMatch(flake);
    expect(linuxLibraries, isNotNull);
    expect(linuxLibraries!.group(1), contains('pkgs.libsysprof-capture'));
    expect(linuxLibraries.group(1), contains('pkgs.libsecret'));
  });
}
