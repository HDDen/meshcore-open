'use strict';

const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { spawnSync } = require('node:child_process');

const caseArgument = process.argv.find((argument) => argument.startsWith('--case='));
const caseIndex = caseArgument == null ? null : Number(caseArgument.slice('--case='.length));
const positionalArguments = process.argv.slice(2).filter((argument) => !argument.startsWith('--'));
const fixturePath = positionalArguments[0]
  ? path.resolve(positionalArguments[0])
  : path.join(__dirname, 'v3-js-encoder-fixtures.json');
const document = JSON.parse(fs.readFileSync(fixturePath, 'utf8'));

if (caseIndex == null) {
  const summaries = [];
  for (let index = 0; index < document.fixtures.length; index++) {
    const tempDirectory = fs.mkdtempSync(path.join(os.tmpdir(), 'mcoimg-v3-verify-'));
    const stdoutPath = path.join(tempDirectory, 'stdout.json');
    const stderrPath = path.join(tempDirectory, 'stderr.txt');
    const stdoutFd = fs.openSync(stdoutPath, 'w');
    const stderrFd = fs.openSync(stderrPath, 'w');
    let child;
    try {
      child = spawnSync(process.execPath, [__filename, fixturePath, `--case=${index}`], {
        stdio: ['ignore', stdoutFd, stderrFd],
        timeout: 180000,
      });
    } finally {
      fs.closeSync(stdoutFd);
      fs.closeSync(stderrFd);
    }
    const childStdout = fs.readFileSync(stdoutPath, 'utf8');
    const childStderr = fs.readFileSync(stderrPath, 'utf8');
    fs.rmSync(tempDirectory, { recursive: true, force: true });
    if (child.error) throw child.error;
    if (child.status !== 0) {
      throw new Error(`fixture ${index} failed:
${childStderr || childStdout}`);
    }
    summaries.push(JSON.parse(childStdout));
  }
  console.log(JSON.stringify({
    fixtureFile: path.basename(fixturePath),
    generator: document.generator,
    fixtures: summaries,
    exactReencode: 'ok',
  }, null, 2));
  process.exit(0);
}

if (!Number.isInteger(caseIndex) || caseIndex < 0 || caseIndex >= document.fixtures.length) {
  throw new RangeError(`invalid --case value: ${caseArgument}`);
}

require(path.resolve(__dirname, '..', 'mcoimg-v3-codec.global.js'));
const v3 = globalThis.MCOImgV3;
const codec = new v3.MCOImageV3Codec();

function same(left, right) {
  return left.length === right.length && left.every((value, index) => value === right[index]);
}

function verifyFixture(index) {
  const fixture = document.fixtures[index];
  const profile = v3.PaletteProfile[fixture.paletteProfile];
  const expectedBody = new Uint8Array(Buffer.from(fixture.bodyBase64, 'base64'));
  const expectedApp = new Uint8Array(Buffer.from(fixture.appPayloadBase64, 'base64'));
  const encoded = codec.encode({
    width: fixture.width,
    height: fixture.height,
    paletteProfile: profile,
    pixels: fixture.pixels,
    transparentColor: fixture.transparentColor ?? null,
  }, {
    compressionLevel: fixture.compressionLevel,
    packetNonce: fixture.packetNonce,
  });
  if (!same(encoded.body, expectedBody)) {
    throw new Error(`${fixture.name}: checked-in body no longer re-encodes exactly`);
  }
  if (!same(encoded.appPayloadWithoutSender, expectedApp)) {
    throw new Error(`${fixture.name}: checked-in app payload mismatch`);
  }
  if (encoded.text !== fixture.text) {
    throw new Error(`${fixture.name}: checked-in text mismatch`);
  }
  const decoded = codec.decodeBody(expectedBody);
  if (decoded.width !== fixture.width || decoded.height !== fixture.height ||
      decoded.paletteProfile !== profile ||
      decoded.transparentColor !== (fixture.transparentColor ?? null) ||
      !same(decoded.pixels, fixture.pixels)) {
    throw new Error(`${fixture.name}: checked-in fixture decode mismatch`);
  }
  const info = v3.MCOImageV3Codec.inspectBody(expectedBody);
  return {
    name: fixture.name,
    level: fixture.compressionLevel,
    bytes: expectedBody.length,
    container: info.containerName,
    algorithm: info.blockAlgorithmName,
  };
}

process.stdout.write(`${JSON.stringify(verifyFixture(caseIndex))}\n`, () => process.exit(0));
