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

  test('U22 baseline: the Linux runtime bundle includes its native assets', () {
    final cmake = _read('linux/CMakeLists.txt');
    final install = cmake.replaceAll(RegExp(r'\s+'), ' ');

    expect(cmake, contains('set(APPLICATION_ID "com.monitormx.mcoadvanced")'));
    for (final rule in [
      r'install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION '
          r'"${CMAKE_INSTALL_PREFIX}" COMPONENT Runtime)',
      r'install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION '
          r'"${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)',
      r'install(FILES "${FLUTTER_LIBRARY}" DESTINATION '
          r'"${INSTALL_BUNDLE_LIB_DIR}" COMPONENT Runtime)',
      r'install(DIRECTORY "${NATIVE_ASSETS_DIR}" DESTINATION '
          r'"${INSTALL_BUNDLE_LIB_DIR}" COMPONENT Runtime)',
      r'install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}" '
          r'DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)',
      r'if(NOT CMAKE_BUILD_TYPE MATCHES "Debug") install(FILES "${AOT_LIBRARY}" '
          r'DESTINATION "${INSTALL_BUNDLE_LIB_DIR}" COMPONENT Runtime) endif()',
    ]) {
      expect(install, contains(rule));
    }
    expect(cmake, contains('libonnxruntime_providers_shared.so'));
    expect(
      cmake,
      contains('target_compile_definitions(flserial PRIVATE __STDC_NO_THREADS__)'),
    );
  });

  test('U22 baseline: legacy serial symbols are scoped to x86_64 glibc', () {
    final serial = _read('third_party/flserial/src/native_libs/src/impl/unix.cpp');
    const guard =
        '#if defined(__linux__) && defined(__GLIBC__) && defined(__x86_64__)';
    final start = serial.indexOf(guard);
    expect(start, isNonNegative);
    const fallback =
        '#else\nstatic speed_t glibc_legacy_baud(speed_t baud) { return baud; }\n'
        '#endif';
    final end = serial.indexOf(fallback, start);
    expect(end, greaterThan(start));
    final legacyBranch = serial.substring(start, end);

    for (final symbol in ['cfsetispeed', 'cfsetospeed']) {
      final binding = '".symver $symbol, $symbol@GLIBC_2.2.5"';
      expect(legacyBranch, contains(binding));
      expect(binding.allMatches(serial), hasLength(1));
      expect(serial, contains('::$symbol(&options, glibc_legacy_baud(baud));'));
    }
  });

  test('U22 baseline: CI has a plain Linux release build', () {
    final workflow = _read('.github/workflows/build.yml');
    final job = RegExp(
      r'^  linux:\n([\s\S]*?)(?=^  \S|(?![\s\S]))',
      multiLine: true,
    ).firstMatch(workflow);
    expect(job, isNotNull);
    final steps = job!.group(1)!;
    expect(steps, contains('flutter build linux --release --no-pub'));
    expect(steps, isNot(contains('build_appimage.sh')));
  });

  test('U22: AppImage is opt-in and keeps the fork identity', () {
    final cmake = _read('linux/appimage.cmake.in');
    final gate = cmake.indexOf('STREQUAL "Release"');
    final optIn = cmake.indexOf(r'NOT "$ENV{MESHCORE_BUILD_APPIMAGE}" STREQUAL "1"');
    final invoke = cmake.indexOf('execute_process(');
    expect(gate, isNonNegative);
    expect(optIn, greaterThan(gate));
    expect(invoke, greaterThan(optIn));
    expect(cmake.substring(optIn, invoke), contains('return()'));

    final runner = _read('scripts/appimage/AppRun');
    expect(runner, contains(r'exec "$APPDIR/usr/bin/mco_advanced" "$@"'));
    final desktop = _read('scripts/appimage/com.monitormx.mcoadvanced.desktop');
    expect(desktop, contains('Exec=mco_advanced\n'));
    expect(desktop, contains('Icon=com.monitormx.mcoadvanced\n'));

    final packager = _read('scripts/build_appimage.sh');
    expect(packager, contains('--force-rpath'));
    final workflow = _read('.github/workflows/appimage.yml');
    expect(workflow, contains('  workflow_dispatch:'));
    expect(workflow, contains("MESHCORE_BUILD_APPIMAGE: '1'"));
    expect(workflow, contains('ubuntu-24.04-arm'));
    expect(workflow, contains('--network none'));
  });

  test('U26: Flutter pins agree across profiles, CI, AppImage and Nix', () {
    final manifest = jsonDecode(_read('scripts/appimage-tools.json'))
        as Map<String, dynamic>;
    final flutter = manifest['flutter'] as Map<String, dynamic>;
    final version = flutter['version'] as String;
    expect(version, matches(RegExp(r'^\d+\.\d+\.\d+$')));
    expect(flutter['source_revision'], matches(RegExp(r'^[a-f0-9]{40}$')));
    expect(flutter['sha256'], matches(RegExp(r'^[a-f0-9]{64}$')));
    expect(flutter['url'], endsWith('/flutter_linux_$version-stable.tar.xz'));

    final pin = RegExp(r'^  flutter: (\d+\.\d+\.\d+)$', multiLine: true);
    for (final suffix in ['', '.full', '.lite', '.lite-aeic']) {
      final profile = 'pubspec$suffix.yaml';
      expect(
        pin.allMatches(_read(profile)).map((match) => match.group(1)),
        [version],
        reason: profile,
      );
    }

    for (final name in ['build', 'deploy', 'flutter_dart']) {
      final workflow = _read('.github/workflows/$name.yml');
      expect(
        'flutter-version-file: pubspec.yaml'.allMatches(workflow),
        hasLength('uses: subosito/flutter-action@v2'.allMatches(workflow).length),
        reason: name,
      );
      expect(workflow, isNot(contains('flutter-version:')));
    }

    final flake = _read('flake.nix');
    expect(flake, contains('builtins.readFile ./scripts/appimage-tools.json'));
    expect(flake, contains('versionAtLeast pkgs.flutter.version flutterVersion'));
    expect(flake, contains('or newer from PATH'));
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
    expect(flake, contains('pkgs.lib.optional hasPackagedFlutter pkgs.flutter'));
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
