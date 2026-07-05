'use strict';

const fs = require('fs');
const path = require('path');
const { loadMcoImg } = require('./load-codec');

const MCOImg = loadMcoImg();
const codec = new MCOImg.MCOImageCodec();
const fixtureCases = JSON.parse(fs.readFileSync(
  path.join(__dirname, 'v2-fixture-cases.json'),
  'utf8',
)).cases;

function samePixels(left, right) {
  return left.length === right.length && left.every((value, index) => value === right[index]);
}

let candidateCount = 0;
const summaries = [];
for (const fixture of fixtureCases) {
  const paletteProfile = MCOImg.PaletteProfile[fixture.paletteProfile];
  if (!Number.isInteger(paletteProfile)) {
    throw new Error(`Unknown palette profile in fixture ${fixture.name}: ${fixture.paletteProfile}`);
  }
  const image = new MCOImg.MCOImage({
    width: fixture.width,
    height: fixture.height,
    paletteProfile,
    pixels: fixture.pixels,
    transparentColor: fixture.transparentColor ?? null,
    encodingVersion: MCOImg.MCOImageEncodingVersion.v2,
  });
  const diagnostics = codec.debugEncode(image, {
    encodingVersion: MCOImg.MCOImageEncodingVersion.v2,
    compressionLevel: fixture.compressionLevel,
    maxRegions: fixture.maxRegions,
    outputTarget: MCOImg.MCOImageOutputTarget.binary,
  });

  for (const candidate of diagnostics.candidates) {
    const decoded = codec.decodeBytes(candidate.payload);
    if (decoded.width !== fixture.width || decoded.height !== fixture.height) {
      throw new Error(`${fixture.name}/${candidate.container}: dimensions changed`);
    }
    if (decoded.paletteProfile !== paletteProfile) {
      throw new Error(`${fixture.name}/${candidate.container}: palette profile changed`);
    }
    if (decoded.transparentColor !== (fixture.transparentColor ?? null)) {
      throw new Error(`${fixture.name}/${candidate.container}: transparent color changed`);
    }
    if (!samePixels(decoded.pixels, fixture.pixels)) {
      throw new Error(`${fixture.name}/${candidate.container}: pixel round-trip mismatch`);
    }
  }

  candidateCount += diagnostics.candidates.length;
  summaries.push({
    name: fixture.name,
    compressionLevel: fixture.compressionLevel,
    candidates: diagnostics.candidates.length,
    bestContainer: diagnostics.result.container,
    bestBytes: diagnostics.result.byteLength,
  });
}

console.log(JSON.stringify({
  cases: fixtureCases.length,
  candidateCount,
  summaries,
}, null, 2));
