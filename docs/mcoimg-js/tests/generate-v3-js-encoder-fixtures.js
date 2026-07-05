'use strict';

const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { spawnSync } = require('node:child_process');

const sourcePath = path.join(__dirname, 'v2-fixture-cases.json');
const source = JSON.parse(fs.readFileSync(sourcePath, 'utf8'));
const caseArgument = process.argv.find((argument) => argument.startsWith('--case='));
const caseIndex = caseArgument == null ? null : Number(caseArgument.slice('--case='.length));
const positionalArguments = process.argv.slice(2).filter((argument) => !argument.startsWith('--'));
const outputPath = path.resolve(
  positionalArguments[0] || path.join(__dirname, 'v3-js-encoder-fixtures.json'),
);

if (caseIndex == null) {
  const fixtures = [];
  for (let index = 0; index < source.cases.length; index++) {
    console.error(`[v3 fixtures] ${index + 1}/${source.cases.length}: ${source.cases[index].name}`);
    const tempDirectory = fs.mkdtempSync(path.join(os.tmpdir(), 'mcoimg-v3-fixture-'));
    const stdoutPath = path.join(tempDirectory, 'stdout.json');
    const stderrPath = path.join(tempDirectory, 'stderr.txt');
    const stdoutFd = fs.openSync(stdoutPath, 'w');
    const stderrFd = fs.openSync(stderrPath, 'w');
    let child;
    try {
      child = spawnSync(process.execPath, [__filename, `--case=${index}`], {
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
      throw new Error(`fixture case ${index} failed:
${childStderr || childStdout}`);
    }
    fixtures.push(JSON.parse(childStdout));
  }
  fs.writeFileSync(outputPath, `${JSON.stringify({
    schema: 1,
    generator: 'mcoimg-v3-codec.global.js Normal/High encoder',
    fixtures,
  }, null, 2)}\n`);
  console.log(outputPath);
  process.exit(0);
}

if (!Number.isInteger(caseIndex) || caseIndex < 0 || caseIndex >= source.cases.length) {
  throw new RangeError(`invalid --case value: ${caseArgument}`);
}

require(path.resolve(__dirname, '..', 'mcoimg-v3-codec.global.js'));
const v3 = globalThis.MCOImgV3;
const codec = new v3.MCOImageV3Codec();

function same(left, right) {
  return left.length === right.length && left.every((value, index) => value === right[index]);
}

function generateFixture(index) {
  const raw = source.cases[index];
  const fixture = {
    ...raw,
    name: raw.compressionLevel === 'extreme'
      ? raw.name.replace(/-extreme$/, '-high')
      : raw.name,
    compressionLevel: raw.compressionLevel === 'extreme' ? 'high' : raw.compressionLevel,
  };
  const profile = v3.PaletteProfile[fixture.paletteProfile];
  if (profile == null) throw new Error(`${fixture.name}: unknown palette profile`);
  const image = new v3.MCOImageV3({
    width: fixture.width,
    height: fixture.height,
    paletteProfile: profile,
    pixels: fixture.pixels,
    transparentColor: fixture.transparentColor ?? null,
  });
  const encoded = codec.encode(image, {
    compressionLevel: fixture.compressionLevel,
    packetNonce: 0x40 + index,
  });
  const decoded = codec.decodeBody(encoded.body);
  if (decoded.width !== image.width || decoded.height !== image.height ||
      decoded.paletteProfile !== image.paletteProfile ||
      decoded.transparentColor !== image.transparentColor ||
      !same(decoded.pixels, image.pixels)) {
    throw new Error(`${fixture.name}: JavaScript v3 self round-trip failed`);
  }
  const info = v3.MCOImageV3Codec.inspectBody(encoded.body);
  return {
    ...fixture,
    bodyBase64: Buffer.from(encoded.body).toString('base64'),
    appPayloadBase64: Buffer.from(encoded.appPayloadWithoutSender).toString('base64'),
    text: encoded.text,
    byteLength: encoded.byteLength,
    charLength: encoded.charLength,
    subtypeVersion: v3.MCOImageV3Codec.subtypeVersion,
    packetNonce: encoded.body[0],
    mode: encoded.modeName,
    scan: encoded.scanName,
    container: info.containerName,
    algorithm: info.blockAlgorithmName,
    backgroundColor: encoded.backgroundColor,
    regionCount: encoded.regionCount,
  };
}

process.stdout.write(`${JSON.stringify(generateFixture(caseIndex))}\n`, () => process.exit(0));
