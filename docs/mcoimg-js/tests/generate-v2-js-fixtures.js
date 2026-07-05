'use strict';

const fs = require('fs');
const path = require('path');
const { loadMcoImg } = require('./load-codec');

const MCOImg = loadMcoImg();
const codec = new MCOImg.MCOImageCodec();
const sourcePath = path.join(__dirname, 'v2-fixture-cases.json');
const outputPath = path.resolve(process.argv[2] || path.join(__dirname, 'v2-js-fixtures.json'));
const source = JSON.parse(fs.readFileSync(sourcePath, 'utf8'));

const fixtures = source.cases.map((fixture) => {
  const profile = MCOImg.PaletteProfile[fixture.paletteProfile];
  const image = new MCOImg.MCOImage({
    width: fixture.width,
    height: fixture.height,
    paletteProfile: profile,
    pixels: fixture.pixels,
    transparentColor: fixture.transparentColor ?? null,
    encodingVersion: MCOImg.MCOImageEncodingVersion.v2,
  });
  const result = codec.encode(image, {
    encodingVersion: MCOImg.MCOImageEncodingVersion.v2,
    compressionLevel: fixture.compressionLevel,
    maxRegions: fixture.maxRegions,
    outputTarget: MCOImg.MCOImageOutputTarget.binary,
  });
  const payload = new Uint8Array(result.payload);
  return {
    ...fixture,
    payloadBase64: Buffer.from(payload).toString('base64'),
    text: MCOImg.MCOImageCodec.textFromBinaryPayload(payload),
    byteLength: result.byteLength,
    charLength: result.charLength,
    mode: MCOImg.ImageModeName[result.mode],
    scan: MCOImg.ScanModeName[result.scan],
    container: result.container,
    backgroundColor: result.backgroundColor,
    regionCount: result.regionCount,
    dynamicReferenceEncoding: result.dynamicReferenceEncodingName ?? null,
  };
});

fs.writeFileSync(outputPath, `${JSON.stringify({
  schema: 1,
  generator: 'mcoimg-codec.global.js',
  fixtures,
}, null, 2)}\n`);
console.log(outputPath);
