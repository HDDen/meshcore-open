'use strict';

const path = require('node:path');

require(path.resolve(__dirname, '..', 'mcoimg-v3-codec.global.js'));

const v3 = globalThis.MCOImgV3;
const codec = new v3.MCOImageV3Codec();

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function same(left, right) {
  return left.length === right.length && left.every((value, index) => value === right[index]);
}

function assertImage(decoded, expected, label) {
  assert(decoded.width === expected.width, `${label}: width mismatch`);
  assert(decoded.height === expected.height, `${label}: height mismatch`);
  assert(decoded.paletteProfile === expected.paletteProfile, `${label}: palette mismatch`);
  assert(decoded.transparentColor === (expected.transparentColor ?? null), `${label}: transparency mismatch`);
  assert(same(decoded.pixels, expected.pixels), `${label}: pixels mismatch`);
}

function image(name, width, height, paletteProfile, pixels, transparentColor = null) {
  return {
    name,
    width,
    height,
    paletteProfile,
    pixels,
    transparentColor,
  };
}

const cases = [
  {
    image: image(
      'mono-checker-normal',
      9,
      7,
      v3.PaletteProfile.mono,
      Array.from({ length: 9 * 7 }, (_, index) => {
        const x = index % 9;
        const y = Math.floor(index / 9);
        return (x + y) & 1;
      }),
    ),
    options: { compressionLevel: 'normal', packetNonce: 0x31 },
  },
  {
    image: image(
      'master16-rich-normal',
      9,
      7,
      v3.PaletteProfile.master16,
      Array.from({ length: 9 * 7 }, (_, index) => {
        const x = index % 9;
        const y = Math.floor(index / 9);
        return (x * 3 + y * 5 + (index & 3)) % 16;
      }),
    ),
    options: { compressionLevel: v3.MCOImageV3CompressionLevel.normal, packetNonce: 0x42 },
  },
  {
    image: image(
      'master8-regions-normal',
      12,
      10,
      v3.PaletteProfile.master8,
      (() => {
        const pixels = Array(12 * 10).fill(0);
        for (let y = 2; y < 5; y++) for (let x = 3; x < 7; x++) pixels[y * 12 + x] = 2;
        for (let y = 6; y < 9; y++) for (let x = 8; x < 11; x++) pixels[y * 12 + x] = 5;
        pixels[1 * 12 + 10] = 3;
        return pixels;
      })(),
      0,
    ),
    options: { compressionLevel: 'normal', packetNonce: 0x53 },
  },
  {
    image: image(
      'grayscale8-high-direct',
      9,
      7,
      v3.PaletteProfile.grayscale8,
      Array.from({ length: 9 * 7 }, (_, index) => {
        const x = index % 9;
        const y = Math.floor(index / 9);
        return (x + y * 2) % 8;
      }),
    ),
    options: {
      compressionLevel: 'high',
      packetNonce: 0x64,
      includeNonScanCandidates: false,
      backgroundCandidates: [{ color: 0, rank: 0 }],
    },
  },
];

const algorithms = new Set();
const containers = new Set();
const summaries = [];
let candidateCount = 0;

for (const test of cases) {
  const diagnostics = codec.debugEncode(test.image, test.options);
  const result = diagnostics.result;
  assert(result.body[0] === test.options.packetNonce, `${test.image.name}: packet nonce mismatch`);
  assert(result.appPayloadWithoutSender[0] === v3.MCOImageV3Codec.subtypeVersion,
    `${test.image.name}: missing 0x13 app subtype/version`);
  assert(result.text.startsWith(v3.MCOImageV3Codec.textPrefix), `${test.image.name}: missing im3 prefix`);
  assert(result.byteLength === result.body.length, `${test.image.name}: body length metadata mismatch`);
  assert(result.charLength === result.text.length, `${test.image.name}: text length metadata mismatch`);

  assertImage(codec.decodeBody(result.body), test.image, `${test.image.name}/winner-body`);
  assertImage(codec.decodeBytes(result.appPayloadWithoutSender), test.image, `${test.image.name}/winner-app`);
  assertImage(codec.decodeText(result.text), test.image, `${test.image.name}/winner-text`);
  assert(same(v3.MCOImageV3Codec.bodyFromText(result.text), result.body),
    `${test.image.name}: text/body conversion mismatch`);
  assert(same(v3.MCOImageV3Codec.appPayloadWithoutSenderFromText(result.text), result.appPayloadWithoutSender),
    `${test.image.name}: text/app conversion mismatch`);

  const info = v3.MCOImageV3Codec.inspectBody(result.body);
  assert(info.version === 3 && info.packetNonce === test.options.packetNonce,
    `${test.image.name}: metadata mismatch`);

  for (let index = 0; index < diagnostics.candidates.length; index++) {
    const candidate = diagnostics.candidates[index];
    assertImage(codec.decodeBody(candidate.body), test.image, `${test.image.name}/candidate-${index}`);
    candidateCount++;
    containers.add(candidate.container);
    if (candidate.algorithm != null) algorithms.add(candidate.algorithm);
  }

  summaries.push({
    name: test.image.name,
    level: diagnostics.compressionLevel,
    candidates: diagnostics.candidates.length,
    bytes: result.body.length,
    container: info.containerName,
    algorithm: info.blockAlgorithmName,
  });
}

const expectedAlgorithms = Object.values(v3.MCOImageV3BlockAlgorithm)
  .filter((value) => Number.isInteger(value));
for (const algorithm of expectedAlgorithms) {
  assert(algorithms.has(algorithm),
    `encoder coverage missing ${v3.MCOImageV3BlockAlgorithmName[algorithm]}`);
}
for (const container of [
  'block',
  'compactBlock',
  'boundsBlock',
  'compactBoundsBlock',
  'regions',
  'compactRegionsStream',
  'solidRects',
]) {
  assert(containers.has(container), `encoder coverage missing ${container}`);
}

const solidImage = image('solid', 3, 2, v3.PaletteProfile.master4, Array(6).fill(2));
const solid = codec.encode(solidImage, { compressionLevel: 'normal', packetNonce: 0x75 });
assert(v3.MCOImageV3Codec.inspectBody(solid.body).containerName === 'solidBackground',
  'solidBackground winner was not generated');
assertImage(codec.decodeBody(solid.body), solidImage, 'solid/winner');
containers.add('solidBackground');

const deterministicImage = cases[0].image;
const deterministicOptions = {
  compressionLevel: 'normal',
  packetNonce: 0x5a,
  includeNonScanCandidates: false,
  backgroundCandidates: [{ color: 0, rank: 0 }],
};
const deterministicA = codec.encode(deterministicImage, deterministicOptions);
const deterministicB = codec.encode(deterministicImage, deterministicOptions);
assert(same(deterministicA.body, deterministicB.body), 'fixed nonce encoding is not deterministic');

const refreshed = v3.MCOImageV3Codec.refreshPacketNonce(deterministicA.body, { nonce: 0xa5 });
assert(refreshed[0] === 0xa5, 'refreshPacketNonce did not apply requested nonce');
assert(same(refreshed.slice(1), deterministicA.body.slice(1)), 'refreshPacketNonce changed compressed data');
assertImage(codec.decodeBody(refreshed), deterministicImage, 'refreshed nonce');

const normalBackgrounds = v3.MCOImageV3Codec.backgroundCandidatesFor(cases[2].image, {
  compressionLevel: 'normal',
});
const highBackgrounds = v3.MCOImageV3Codec.backgroundCandidatesFor(cases[2].image, {
  compressionLevel: 'high',
});
assert(normalBackgrounds.length > 0, 'normal background candidates missing');
assert(highBackgrounds.length >= normalBackgrounds.length, 'high background search is narrower than normal');

console.log(JSON.stringify({
  cases: summaries,
  candidates: candidateCount,
  algorithms: Array.from(algorithms).sort((a, b) => a - b)
    .map((value) => v3.MCOImageV3BlockAlgorithmName[value]),
  containers: Array.from(containers).sort(),
  deterministic: 'ok',
  nonceRefresh: 'ok',
  backgroundCandidates: { normal: normalBackgrounds.length, high: highBackgrounds.length },
}, null, 2));
