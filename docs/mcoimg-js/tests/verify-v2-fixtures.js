'use strict';

const fs = require('fs');
const path = require('path');
const { loadMcoImg } = require('./load-codec');

const fixturePath = process.argv[2]
  ? path.resolve(process.argv[2])
  : path.join(__dirname, 'v2-js-fixtures.json');
const decodeOnly = process.argv.includes('--decode-only');
const document = JSON.parse(fs.readFileSync(fixturePath, 'utf8'));
const MCOImg = loadMcoImg();
const codec = new MCOImg.MCOImageCodec();

function sameBytes(left, right) {
  return left.length === right.length && left.every((value, index) => value === right[index]);
}

function samePixels(left, right) {
  return left.length === right.length && left.every((value, index) => value === right[index]);
}

const summaries = [];
for (const fixture of document.fixtures) {
  const payload = new Uint8Array(Buffer.from(fixture.payloadBase64, 'base64'));
  const decoded = codec.decodeBytes(payload);
  const profile = MCOImg.PaletteProfile[fixture.paletteProfile];
  if (decoded.width !== fixture.width || decoded.height !== fixture.height ||
      decoded.paletteProfile !== profile ||
      decoded.transparentColor !== (fixture.transparentColor ?? null) ||
      !samePixels(decoded.pixels, fixture.pixels)) {
    throw new Error(`${fixture.name}: fixture decode mismatch`);
  }
  const expectedText = MCOImg.MCOImageCodec.textFromBinaryPayload(payload);
  if (fixture.text && fixture.text !== expectedText) {
    throw new Error(`${fixture.name}: fixture Base91 text does not match payload`);
  }

  let exact = null;
  if (!decodeOnly) {
    const encoded = codec.encode(new MCOImg.MCOImage({
      width: fixture.width,
      height: fixture.height,
      paletteProfile: profile,
      pixels: fixture.pixels,
      transparentColor: fixture.transparentColor ?? null,
      encodingVersion: MCOImg.MCOImageEncodingVersion.v2,
    }), {
      encodingVersion: MCOImg.MCOImageEncodingVersion.v2,
      compressionLevel: fixture.compressionLevel,
      maxRegions: fixture.maxRegions,
      outputTarget: MCOImg.MCOImageOutputTarget.binary,
    });
    exact = sameBytes(encoded.payload, payload);
    if (!exact) {
      throw new Error(
        `${fixture.name}: exact encoder mismatch (${encoded.payload.length} vs ${payload.length} bytes)`,
      );
    }
  }
  summaries.push({ name: fixture.name, bytes: payload.length, exact });
}

console.log(JSON.stringify({
  fixtureFile: path.basename(fixturePath),
  generator: document.generator || 'unknown',
  decodeOnly,
  fixtures: summaries,
}, null, 2));
