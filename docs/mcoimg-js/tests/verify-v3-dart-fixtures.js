'use strict';

const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const fixturePath = process.argv[2]
  ? path.resolve(process.argv[2])
  : path.join(__dirname, 'v3-dart-fixtures.json');
const decodeOnly = process.argv.includes('--decode-only');
const document = JSON.parse(fs.readFileSync(fixturePath, 'utf8'));
const root = path.resolve(__dirname, '..');
const context = { console, Uint8Array, ArrayBuffer, TextDecoder, TextEncoder };
context.globalThis = context;
vm.createContext(context);
vm.runInContext(
  fs.readFileSync(path.join(root, 'mcoimg-v3-codec.global.js'), 'utf8'),
  context,
  { filename: 'mcoimg-v3-codec.global.js' },
);

const v3 = context.MCOImgV3;
const codec = new v3.MCOImageV3Codec();

function same(left, right) {
  return left.length === right.length && left.every((value, index) => value === right[index]);
}

const summaries = [];
for (const fixture of document.fixtures) {
  const body = new Uint8Array(Buffer.from(fixture.bodyBase64, 'base64'));
  const app = new Uint8Array(Buffer.from(fixture.appPayloadBase64, 'base64'));
  const profile = v3.PaletteProfile[fixture.paletteProfile];
  const decodedBody = codec.decodeBody(body);
  const decodedApp = codec.decodeAppPayloadWithoutSender(app);
  const decodedText = codec.decodeText(fixture.text);
  for (const [surface, decoded] of [
    ['body', decodedBody],
    ['app', decodedApp],
    ['text', decodedText],
  ]) {
    if (decoded.width !== fixture.width || decoded.height !== fixture.height ||
        decoded.paletteProfile !== profile ||
        decoded.transparentColor !== (fixture.transparentColor ?? null) ||
        !same(decoded.pixels, fixture.pixels)) {
      throw new Error(`${fixture.name}: ${surface} decode mismatch`);
    }
  }
  if (!same(v3.MCOImageV3Codec.bodyFromText(fixture.text), body)) {
    throw new Error(`${fixture.name}: text/body conversion mismatch`);
  }
  if (!same(v3.MCOImageV3Codec.appPayloadWithoutSenderFromText(fixture.text), app)) {
    throw new Error(`${fixture.name}: text/app conversion mismatch`);
  }
  const info = v3.MCOImageV3Codec.inspectBody(body);
  if (!decodeOnly) {
    const jsEncoded = codec.encode({
      width: fixture.width,
      height: fixture.height,
      paletteProfile: profile,
      pixels: fixture.pixels,
      transparentColor: fixture.transparentColor ?? null,
    }, {
      compressionLevel: fixture.compressionLevel,
      packetNonce: body[0],
    });
    if (!same(jsEncoded.body, body)) {
      const jsInfo = v3.MCOImageV3Codec.inspectBody(jsEncoded.body);
      throw new Error(
        `${fixture.name}: Dart/JavaScript winner mismatch ` +
        `(Dart ${body.length} bytes ${info.containerName}/${info.blockAlgorithmName}; ` +
        `JS ${jsEncoded.body.length} bytes ${jsInfo.containerName}/${jsInfo.blockAlgorithmName})`,
      );
    }
  }
  summaries.push({
    name: fixture.name,
    bytes: body.length,
    container: info.containerName,
    algorithm: info.blockAlgorithmName,
    exactReencode: decodeOnly ? 'skipped' : 'ok',
  });
}

console.log(JSON.stringify({
  fixtureFile: path.basename(fixturePath),
  generator: document.generator || 'unknown',
  fixtures: summaries,
}, null, 2));
