'use strict';

const path = require('node:path');
require(path.resolve(__dirname, '..', 'mcoimg-v3-codec.global.js'));

const v3 = globalThis.MCOImgV3;
const codec = new v3.MCOImageV3Codec();

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function same(a, b) {
  return Buffer.from(a).equals(Buffer.from(b));
}

function makeImage() {
  const width = 10;
  const height = 8;
  const pixels = Array(width * height).fill(0);
  for (let y = 1; y < 4; y++) {
    for (let x = 1; x < 5; x++) pixels[y * width + x] = 2;
  }
  for (let y = 5; y < 7; y++) {
    for (let x = 6; x < 9; x++) pixels[y * width + x] = 5;
  }
  pixels[2 * width + 8] = 3;
  pixels[6 * width + 2] = 6;
  return {
    width,
    height,
    paletteProfile: v3.PaletteProfile.master8,
    pixels,
    transparentColor: 0,
  };
}

function partitionEncode(image, options) {
  const plan = v3.MCOImageV3Codec.createWorkerPlan(image, options);
  const progress = [];
  const results = plan.partitions.map((partition) =>
    v3.MCOImageV3Codec.encodePartition(
      image,
      plan.options,
      partition,
      (detail) => progress.push({ order: partition.order, detail }),
    ));
  return { plan, results, progress };
}

const image = makeImage();
const baseOptions = {
  packetNonce: 0x6d,
  backgroundCandidates: [
    { color: 0, rank: 0 },
    { color: 1, rank: 1 },
  ],
  scanModes: [v3.ScanMode.h, v3.ScanMode.v],
};

const highOptions = { ...baseOptions, compressionLevel: 'high' };
const extremeOptions = { ...baseOptions, compressionLevel: 'extreme' };
const high = codec.encode(image, highOptions);
const extreme = codec.encode(image, extremeOptions);
assert(extreme.body.length <= high.body.length,
  `Extreme result ${extreme.body.length} exceeds High ${high.body.length}`);

for (const [label, options, expected] of [
  ['high', highOptions, high],
  ['extreme', extremeOptions, extreme],
]) {
  const { plan, results, progress } = partitionEncode(image, options);
  assert(plan.totalPartitions === plan.partitions.length, `${label}: invalid plan count`);
  assert(plan.totalPartitions > 1, `${label}: worker plan was not partitioned`);
  assert(results.length === plan.totalPartitions, `${label}: missing partition result`);
  const merged = v3.MCOImageV3Codec.mergePartitionResults(results);
  const reversed = v3.MCOImageV3Codec.mergePartitionResults(results.slice().reverse());
  const interleaved = results.filter((_, index) => index % 2)
    .concat(results.filter((_, index) => index % 2 === 0));
  const shuffled = v3.MCOImageV3Codec.mergePartitionResults(interleaved);
  assert(same(merged.body, expected.body), `${label}: partition winner differs from sync winner`);
  assert(same(reversed.body, expected.body), `${label}: reverse completion changed winner`);
  assert(same(shuffled.body, expected.body), `${label}: shuffled completion changed winner`);
  const decoded = codec.decodeBody(merged.body);
  assert(same(decoded.pixels, image.pixels), `${label}: merged result does not round-trip`);
  if (label === 'extreme') {
    assert(progress.length > 0, 'Extreme search did not emit internal progress');
  }
}

const refreshed = v3.MCOImageV3Codec.refreshPacketNonce(extreme.body, { nonce: 0x91 });
assert(refreshed[0] === 0x91, 'nonce refresh failed');
assert(same(refreshed.subarray(1), extreme.body.subarray(1)),
  'nonce refresh changed compressed payload');

console.log(JSON.stringify({
  highBytes: high.body.length,
  extremeBytes: extreme.body.length,
  container: v3.MCOImageV3Codec.inspectBody(extreme.body).containerName,
  partitions: v3.MCOImageV3Codec.createWorkerPlan(image, extremeOptions).totalPartitions,
  deterministicMerge: 'ok',
  progress: 'ok',
}, null, 2));
