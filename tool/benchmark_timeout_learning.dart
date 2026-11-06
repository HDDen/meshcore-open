import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:ml_algo/ml_algo.dart';
import 'package:ml_dataframe/ml_dataframe.dart';

// Run from the repo root with the same package config/corpus before and after:
// dart --packages=.dart_tool/package_config.json tool/benchmark_timeout_learning.dart
// Add --ref bf7291f8 to read the pre-U12b feature list from Git.
// This measures the standalone numerical core, not the Flutter service wrapper,
// UI, background scheduling, SQL, energy or real-radio prediction accuracy.
const _sourcePath = 'lib/services/timeout_prediction_service.dart';
const _fitsPerRound = 100;
const _predictionsPerRound = 1000;

typedef _Fit = ({LinearRegressor model, List<String> features});

List<Map<String, double>> _corpus() => List.generate(100, (i) {
  final flood = i % 6 == 0;
  final hops = flood ? 0.0 : (i % 5).toDouble();
  final bytes = (20 + (i * 17) % 120).toDouble();
  return {
    'pathLength': hops,
    'messageBytes': bytes,
    'secSinceRx': ((i * 19) % 47).toDouble(),
    'isFlood': flood ? 1.0 : 0.0,
    'deliveryMs': 1800 + hops * 850 + bytes * 11 +
        (flood ? 2500 : 0) + (i * 13) % 97,
  };
});

_Fit _train(List<Map<String, double>> corpus, List<String> candidates) {
  // Same variance filter, DataFrame shape and LinearRegressor constructor as
  // _trainModel. Candidate names are read from the selected service source.
  final active = [
    for (final name in candidates)
      if (corpus.map((row) => row[name]!).toSet().length > 1) name,
  ];
  final header = [...active, 'deliveryMs'];
  final rows = corpus.map((row) => [
    for (final name in active) row[name]!,
    row['deliveryMs']!,
  ]);
  final data = DataFrame([header, ...rows], headerExists: true);
  return (model: LinearRegressor(data, 'deliveryMs'), features: active);
}

int _predict(_Fit fit, int index, double safetyMargin) {
  final sample = {
    'pathLength': (index % 5).toDouble(),
    'messageBytes': (20 + index % 120).toDouble(),
    'secSinceRx': (index % 47).toDouble(),
    'isFlood': 0.0,
  };
  final data = DataFrame(
    [fit.features.map((name) => sample[name]!).toList()],
    headerExists: false,
    header: fit.features,
  );
  final value = (fit.model.predict(data).rows.first.first as num).toDouble();
  if (!value.isFinite || value <= 0) {
    throw StateError('Non-positive or non-finite synthetic prediction: $value');
  }
  return (value * safetyMargin).ceil();
}

void main(List<String> args) {
  String? ref;
  if (args.isNotEmpty) {
    if (args.length != 2 || args.first != '--ref') {
      stderr.writeln('Usage: benchmark_timeout_learning.dart [--ref revision]');
      exitCode = 64;
      return;
    }
    ref = args[1];
  }
  final String source;
  if (ref == null) {
    source = File(_sourcePath).readAsStringSync();
  } else {
    final result = Process.runSync('git', [
      '-c', 'safe.directory=*', 'show', '$ref:$_sourcePath',
    ]);
    if (result.exitCode != 0) {
      stderr.write(result.stderr);
      exitCode = result.exitCode;
      return;
    }
    source = result.stdout as String;
  }
  final names = RegExp(r'final allNames = \[([^\]]+)\];').firstMatch(source);
  final margin = RegExp(r'_safetyMargin = ([0-9.]+);').firstMatch(source);
  if (names == null || margin == null ||
      !source.contains("LinearRegressor(data, 'deliveryMs')")) {
    throw StateError('Service training shape changed; update benchmark first');
  }
  final candidates = RegExp("'([^']+)'")
      .allMatches(names.group(1)!)
      .map((match) => match.group(1)!)
      .toList();
  final corpus = _corpus();
  if (candidates.isEmpty || candidates.any((name) => !corpus.first.containsKey(name))) {
    throw StateError('Unsupported service features: $candidates');
  }
  final safetyMargin = double.parse(margin.group(1)!);
  final fingerprint = sha256.convert(utf8.encode(source)).toString().substring(0, 8);
  stdout.writeln('Source=${ref ?? 'working tree'} fingerprint=$fingerprint '
      'features=${candidates.join(',')}');
  stdout.writeln('Fixed synthetic corpus: 100 rows; ml_algo numerical core.');
  stdout.writeln('Not the service wrapper, UI, radio, SQL, energy or accuracy.');
  for (var warmup = 0; warmup < 5; warmup++) {
    _predict(_train(corpus, candidates), warmup, safetyMargin);
  }
  for (var round = 1; round <= 3; round++) {
    var fit = _train(corpus, candidates);
    var checksum = 0;
    final training = Stopwatch()..start();
    for (var i = 0; i < _fitsPerRound; i++) {
      fit = _train(corpus, candidates);
      checksum += fit.features.length;
    }
    training.stop();
    final prediction = Stopwatch()..start();
    for (var i = 0; i < _predictionsPerRound; i++) {
      checksum += _predict(fit, i, safetyMargin);
    }
    prediction.stop();
    stdout.writeln('round=$round fits=$_fitsPerRound '
        'fitUs=${training.elapsedMicroseconds} '
        'predictions=$_predictionsPerRound predictUs=${prediction.elapsedMicroseconds} '
        'checksum=$checksum');
  }
}
