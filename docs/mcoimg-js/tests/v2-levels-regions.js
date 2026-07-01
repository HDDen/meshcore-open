'use strict';

const { loadMcoImg } = require('./load-codec');
const MCOImg = loadMcoImg();
const codec = new MCOImg.MCOImageCodec();

function samePixels(left, right) {
  return left.length === right.length && left.every((value, index) => value === right[index]);
}

function makeImage(profile, width, height, pixels, transparentColor = null) {
  return new MCOImg.MCOImage({
    width,
    height,
    paletteProfile: profile,
    pixels,
    transparentColor,
    encodingVersion: MCOImg.MCOImageEncodingVersion.v2,
  });
}

const gradient = makeImage(
  MCOImg.PaletteProfile.grayscale16,
  16,
  10,
  Array.from({ length: 160 }, (_, index) => ((index % 16) + Math.floor(index / 16)) % 16),
);
const normal = codec.debugEncode(gradient, {
  compressionLevel: 'normal',
  outputTarget: 'binary',
  maxRegions: 16,
});
const high = codec.debugEncode(gradient, {
  compressionLevel: 'high',
  outputTarget: 'binary',
  maxRegions: 16,
});
const extreme = codec.debugEncode(gradient, {
  compressionLevel: 'extreme',
  outputTarget: 'binary',
  maxRegions: 16,
});
if (normal.compressionLevel !== MCOImg.MCOImageCompressionLevel.normal ||
    high.compressionLevel !== MCOImg.MCOImageCompressionLevel.high ||
    extreme.compressionLevel !== MCOImg.MCOImageCompressionLevel.extreme) {
  throw new Error('String compression-level normalization is broken');
}
if (high.candidates.length < normal.candidates.length ||
    extreme.candidates.length < normal.candidates.length) {
  throw new Error('High/Extreme unexpectedly search fewer candidates than Normal');
}

const width = 18;
const height = 14;
const regionPixels = new Array(width * height).fill(0);
function fillRect(x, y, w, h, color) {
  for (let yy = y; yy < y + h; yy++) {
    for (let xx = x; xx < x + w; xx++) regionPixels[yy * width + xx] = color;
  }
}
fillRect(1, 1, 5, 4, 1);
fillRect(2, 2, 3, 2, 2);
fillRect(11, 2, 5, 3, 3);
fillRect(4, 9, 4, 3, 4);
fillRect(12, 9, 3, 3, 5);
const regionsImage = makeImage(
  MCOImg.PaletteProfile.master16,
  width,
  height,
  regionPixels,
);
const regions = codec.debugEncode(regionsImage, {
  compressionLevel: 'extreme',
  outputTarget: 'binary',
  maxRegions: 32,
  backgroundCandidates: [{ color: 0, rank: 0 }],
});
const regionCandidates = regions.candidates.filter((candidate) =>
  String(candidate.container).startsWith('regions'));
if (regionCandidates.length === 0) throw new Error('Regions candidates were not generated');
if (!regionCandidates.some((candidate) =>
  String(candidate.container).includes('shared-fixed'))) {
  throw new Error('Shared-fixed Regions candidate was not generated');
}
for (const candidate of regionCandidates) {
  const decoded = codec.decodeBytes(candidate.payload);
  if (!samePixels(decoded.pixels, regionPixels)) {
    throw new Error(`Regions candidate failed round-trip: ${candidate.container}`);
  }
}

const binary = regions.result.payload;
const text = MCOImg.MCOImageCodec.textFromBinaryPayload(binary);
const textDecoded = codec.decode(text);
if (!samePixels(textDecoded.pixels, regionPixels)) {
  throw new Error('Binary -> Base91 text -> image round-trip failed');
}
const inspected = MCOImg.MCOImageCodec.inspectPayloadBytes(binary);
if (!inspected || inspected.version !== 2 || inspected.binaryLength !== binary.length) {
  throw new Error('v2 metadata inspection failed');
}

console.log(JSON.stringify({
  levels: {
    normalCandidates: normal.candidates.length,
    highCandidates: high.candidates.length,
    extremeCandidates: extreme.candidates.length,
  },
  regions: {
    candidates: regionCandidates.length,
    containers: Array.from(new Set(regionCandidates.map((candidate) => candidate.container))),
    best: regions.result.container,
    bytes: regions.result.byteLength,
  },
  metadata: inspected,
}, null, 2));
