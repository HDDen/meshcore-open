import 'dart:io';

/// Runs the actual current pubKeyToHex body in a standalone Dart VM benchmark.
/// meshcore_protocol.dart imports Flutter widgets, so directly importing it
/// would require dart:ui. Extract just the top-level conversion function and
/// its optional hex-digit constant; never replace it with a hand-copied model.
Future<void> main() async {
  final sourceFile = File.fromUri(
    Platform.script.resolve('../lib/connector/meshcore_protocol.dart'),
  );
  final source = (await sourceFile.readAsString()).replaceAll('\r\n', '\n');
  final start = source.indexOf('String pubKeyToHex(Uint8List pubKey) {');
  if (start < 0) {
    throw StateError('pubKeyToHex declaration changed; review the benchmark');
  }
  // Only the function's top-level closing brace starts in column zero.
  final closing = source.indexOf('\n}\n', start);
  if (closing < 0) {
    throw StateError('Cannot locate the end of pubKeyToHex');
  }
  final function = source.substring(start, closing + 2);
  final digits = RegExp(
    r"^const String _hexDigits = '[0-9a-f]+';\s*$",
    multiLine: true,
  ).firstMatch(source)?.group(0)?.trim() ?? '';
  var fingerprint = 0x811c9dc5;
  for (final code in '$digits\n$function'.codeUnits) {
    fingerprint = ((fingerprint ^ code) * 0x01000193) & 0xffffffff;
  }

  final directory = await Directory.systemTemp.createTemp('mcoa-key-hex-bench-');
  try {
    final benchmark = File('${directory.path}${Platform.pathSeparator}main.dart');
    await benchmark.writeAsString(
      "import 'dart:typed_data';\n$digits\n$function\n$_harness",
    );
    stdout.writeln('Current pubKeyToHex fingerprint=${fingerprint.toRadixString(16)}');
    final result = await Process.run(Platform.resolvedExecutable, [benchmark.path]);
    stdout.write(result.stdout);
    stderr.write(result.stderr);
    exitCode = result.exitCode;
  } finally {
    await directory.delete(recursive: true);
  }
}

const _harness = r'''
String reference(Uint8List bytes) =>
    bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();

void main() {
  final corpus = <Uint8List>[
    for (final length in [0, 1, 2, 3, 6, 16, 32, 64, 176, 256])
      Uint8List.fromList(List<int>.generate(length, (i) => (i * 73 + length) & 255)),
  ];
  for (final bytes in corpus) {
    if (pubKeyToHex(bytes) != reference(bytes)) {
      throw StateError('Hex mismatch for length=${bytes.length}');
    }
  }
  int convert(int iterations) {
    var checksum = 0;
    for (var i = 0; i < iterations; i++) {
      for (final bytes in corpus) {
        final result = pubKeyToHex(bytes);
        checksum = (checksum + result.length +
            (result.isEmpty ? 0 : result.codeUnitAt(result.length - 1))) & 0x7fffffff;
      }
    }
    return checksum;
  }
  convert(2000);
  const iterations = 25000;
  print('Fixed synthetic corpus; actual function; no BLE, SQL, UI or energy measurement.');
  for (var round = 1; round <= 3; round++) {
    final timer = Stopwatch()..start();
    final checksum = convert(iterations);
    timer.stop();
    print('round=$round conversions=${iterations * corpus.length} '
        'elapsedUs=${timer.elapsedMicroseconds} checksum=$checksum; allOutputs=equal');
  }
}
''';
