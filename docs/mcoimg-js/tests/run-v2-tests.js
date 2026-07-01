'use strict';

const { spawnSync } = require('node:child_process');
const path = require('node:path');

const testDirectory = __dirname;
const tests = [
  'step2-dispatch-smoke.js',
  'v2-levels-regions.js',
  'v2-roundtrip-all-candidates.js',
  'verify-v2-fixtures.js',
];

for (const test of tests) {
  const testPath = path.join(testDirectory, test);
  process.stdout.write(`\n=== ${test} ===\n`);
  const result = spawnSync(process.execPath, [testPath], {
    cwd: path.resolve(testDirectory, '..', '..', '..'),
    stdio: 'inherit',
  });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status ?? 1);
}

process.stdout.write('\nAll JavaScript v1/v2 tests passed.\n');
