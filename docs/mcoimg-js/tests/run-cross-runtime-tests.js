'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const testDirectory = __dirname;
const repositoryRoot = path.resolve(testDirectory, '..', '..', '..');
const dart = process.env.DART_BIN || 'dart';
const v3Only = process.argv.includes('--v3-only');
const v2Only = process.argv.includes('--v2-only');

function fail(message) {
  console.error(message);
  process.exit(1);
}

if (v3Only && v2Only) {
  fail('Use either --v3-only or --v2-only, not both');
}

function commandExists(command) {
  const result = spawnSync(command, ['--version'], {
    cwd: repositoryRoot,
    encoding: 'utf8',
  });
  return !result.error && result.status === 0;
}

function run(command, args) {
  process.stdout.write(`\n> ${[command, ...args].join(' ')}\n`);
  const result = spawnSync(command, args, {
    cwd: repositoryRoot,
    stdio: 'inherit',
  });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status ?? 1);
}

if (!fs.existsSync(path.join(repositoryRoot, 'pubspec.yaml'))) {
  fail(
    `pubspec.yaml was not found at ${repositoryRoot}. ` +
    'Run this script from the complete Flutter project, preserving docs/mcoimg-js/tests/.',
  );
}
if (!commandExists(dart)) {
  fail(
    `Dart executable "${dart}" was not found. ` +
    'Set DART_BIN to the Dart executable bundled with Flutter if needed.',
  );
}

const relative = (name) => path.relative(
  repositoryRoot,
  path.join(testDirectory, name),
).split(path.sep).join('/');

if (!v3Only) {
  const dartFixtures = relative('v2-dart-fixtures.json');
  run(dart, ['run', relative('generate_v2_dart_fixtures.dart'), dartFixtures]);
  run(process.execPath, [relative('verify-v2-fixtures.js'), dartFixtures]);
  run(process.execPath, [relative('generate-v2-js-fixtures.js')]);
  run(dart, ['run', relative('verify_v2_js_fixtures.dart')]);
}

if (!v2Only) {
  const decoderFixtures = relative('v3-js-decoder-fixtures.json');
  const dartFixtures = relative('v3-dart-fixtures.json');
  run(process.execPath, [
    relative('v3-decoder-fixtures.js'),
    `--write=${decoderFixtures}`,
  ]);
  run(dart, ['run', relative('verify_v3_js_decoder_fixtures.dart'), decoderFixtures]);
  run(dart, ['run', relative('generate_v3_dart_fixtures.dart'), dartFixtures]);
  run(process.execPath, [relative('verify-v3-dart-fixtures.js'), dartFixtures]);
  run(process.execPath, [relative('generate-v3-js-encoder-fixtures.js')]);
  run(dart, ['run', relative('verify_v3_js_encoder_fixtures.dart')]);
}

process.stdout.write('\nAll requested Dart↔JavaScript fixture checks passed.\n');
