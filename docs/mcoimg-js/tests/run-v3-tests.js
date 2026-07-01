'use strict';

const { spawnSync } = require('node:child_process');
const path = require('node:path');

const tests = [
  'v3-decoder-fixtures.js',
  'v3-encoder-roundtrip.js',
  'v3-extreme-partitions.js',
  'v3-worker-entry-smoke.js',
  'v3-browser-workers.js',
  'v3-channel-envelope.js',
  'verify-v3-js-encoder-fixtures.js',
  'v3-browser-smoke.js',
];

for (const test of tests) {
  process.stdout.write(`\n=== ${test} ===\n`);
  const result = spawnSync(process.execPath, [path.join(__dirname, test)], {
    cwd: path.resolve(__dirname, '..', '..', '..'),
    stdio: 'inherit',
  });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status ?? 1);
}

if (process.env.MCOIMG_RUN_BROWSER === '1') {
  process.stdout.write('\n=== run-v3-real-browser.js ===\n');
  const result = spawnSync(process.execPath, [path.join(__dirname, 'run-v3-real-browser.js')], {
    cwd: path.resolve(__dirname, '..', '..', '..'),
    stdio: 'inherit',
    env: process.env,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status ?? 1);
}

process.stdout.write('\nAll JavaScript v3 encoder/decoder tests passed.\n');
