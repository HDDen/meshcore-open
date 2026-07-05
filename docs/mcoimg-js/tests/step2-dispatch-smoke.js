'use strict';

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = path.resolve(__dirname, '..');
const context = {
  console,
  Uint8Array,
  ArrayBuffer,
  TextDecoder,
  TextEncoder,
  Blob,
  URL,
  Promise,
  setTimeout,
  clearTimeout,
};
context.globalThis = context;
vm.createContext(context);

for (const file of [
  'mcoimg-codec.global.js',
  'mcoimg-v3-codec.global.js',
  'mcoimg-browser.global.js',
]) {
  vm.runInContext(
    fs.readFileSync(path.join(root, file), 'utf8'),
    context,
    { filename: file },
  );
}

const core = context.MCOImg;
const browser = context.MCOImgBrowser;

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

async function testVersion(version) {
  const image = {
    width: 2,
    height: 2,
    paletteProfile: core.PaletteProfile.master8,
    pixels: [0, 1, 2, 3],
    transparentColor: null,
    encodingVersion: version,
  };
  const encoded = await browser.startCancellableEncode(image, {
    formatVersion: version,
    compressionLevel: 'normal',
    useWorkers: false,
  }).result;
  assert(encoded.text.startsWith('im:'), `v${version}: missing im: prefix`);
  structuredClone(encoded);
  const binary = browser.payloadToBinary(encoded.text);
  assert(browser.payloadToText(binary) === encoded.text, `v${version}: text/binary mismatch`);
  const decoded = browser.decodePayload(binary, { input: 'binary' });
  assert(decoded.encodingVersion === version, `v${version}: wrong decoded version`);
  assert(decoded.width === 2 && decoded.height === 2, `v${version}: wrong size`);
  const info = browser.inspectPayload(encoded.text);
  assert(info && info.version === version, `v${version}: wrong metadata version`);
  return { chars: encoded.text.length, bytes: binary.length, algorithm: info.algorithm };
}

async function testCanvasObjectApi() {
  const rgba = new Uint8ClampedArray([
    255, 255, 255, 255,
    0, 0, 0, 255,
    254, 36, 0, 255,
    61, 105, 255, 255,
  ]);
  const canvas = {
    width: 2,
    height: 2,
    getContext() {
      return {
        getImageData() {
          return { width: 2, height: 2, data: rgba };
        },
      };
    },
  };
  const text = await browser.encodeCanvas(canvas, {
    formatVersion: 2,
    compressionLevel: 'normal',
    paletteProfile: core.PaletteProfile.master8,
    output: 'text',
    useWorkers: false,
  });
  assert(typeof text === 'string' && text.startsWith('im:'), 'canvas object API failed');

  const positionalText = browser.encodeCanvas(
    canvas,
    core.PaletteProfile.master8,
    null,
    core.MCOImageRgbaOutputFormat.text,
    { encodingVersion: 2 },
  );
  assert(typeof positionalText === 'string' && positionalText.startsWith('im:'), 'legacy canvas API failed');

  const binary = await browser.encodeCanvas(canvas, {
    formatVersion: 2,
    compressionLevel: 'normal',
    paletteProfile: core.PaletteProfile.master8,
    output: 'binary',
    useWorkers: false,
  });
  assert(binary instanceof Uint8Array && binary.length > 0, 'canvas binary output failed');

  const png = await browser.convertPayload(text, { output: 'png' });
  assert(browser.hasPngSignature(png), 'text-to-PNG conversion failed');
}

function testLegacyOnlyLoad() {
  const legacyContext = {
    console,
    Uint8Array,
    ArrayBuffer,
    TextDecoder,
    TextEncoder,
    Blob,
    URL,
    Promise,
    setTimeout,
    clearTimeout,
  };
  legacyContext.globalThis = legacyContext;
  vm.createContext(legacyContext);
  for (const file of ['mcoimg-codec.global.js', 'mcoimg-browser.global.js']) {
    vm.runInContext(
      fs.readFileSync(path.join(root, file), 'utf8'),
      legacyContext,
      { filename: file },
    );
  }
  assert(legacyContext.MCOImgBrowser, 'browser helper failed without v3 module');
  let error = '';
  try {
    legacyContext.MCOImgBrowser.codecFromOptions({ formatVersion: 3 });
  } catch (caught) {
    error = caught.message;
  }
  assert(/requires mcoimg-v3-codec/i.test(error), 'missing-v3 error is unclear');
}

(async () => {
  const v1 = await testVersion(1);
  const v2 = await testVersion(2);
  await testCanvasObjectApi();
  testLegacyOnlyLoad();
  assert(browser.inferTextFormatVersion('im3:abc') === 3, 'im3 detection failed');
  assert(browser.hasPngSignature(Uint8Array.from([137, 80, 78, 71, 13, 10, 26, 10])), 'PNG detection failed');

  const v2Body = browser.payloadToBinary(core.MCOImageCodec.textFromBinaryPayload(
    core.MCOImageCodec.binaryPayloadFromText('im:DH2W5FNA'),
  ));
  const v2Envelope = Uint8Array.from([1, 65, ...v2Body]);
  const v2Packet = Uint8Array.from([2, 0xf0, 0xff, ...v2Envelope]);
  const parsedV2 = browser.inspectMcoImageChannelPacket(v2Packet, {
    formatVersion: 2,
    layout: 'channelData',
  });
  assert(parsedV2.senderName === 'A', 'v2 channel sender parse failed');
  assert(parsedV2.dataType === 0xfff0, 'v2 channel data type failed');

  const v3AppPayload = Uint8Array.from([0x13, 0x7a, 0x00, 0x00, 0x00]);
  const v3Envelope = Uint8Array.from([1, 65, ...v3AppPayload]);
  const v3Packet = Uint8Array.from([2, 0x20, 0x01, ...v3Envelope]);
  const parsedV3 = browser.inspectMcoImageChannelPacket(v3Packet, {
    formatVersion: 3,
    layout: 'channelData',
    validate: false,
  });
  assert(parsedV3.senderName === 'A', 'v3 channel sender parse failed');
  assert(parsedV3.dataType === 0x0120, 'v3 channel data type failed');
  assert(parsedV3.subtypeVersion === 0x13, 'v3 subtype/version parse failed');
  assert(parsedV3.body[0] === 0x7a, 'v3 body offset failed');

  const v3Encoded = await browser.startCancellableEncode({
    width: 2,
    height: 2,
    paletteProfile: core.PaletteProfile.master8,
    pixels: [0, 1, 2, 3],
    transparentColor: null,
    encodingVersion: 3,
  }, {
    formatVersion: 3,
    compressionLevel: 'normal',
    packetNonce: 0x4d,
    useWorkers: false,
  }).result;
  assert(v3Encoded.text.startsWith('im3:'), 'v3 encoder did not return im3 text');
  assert(v3Encoded.appPayloadWithoutSender[0] === 0x13, 'v3 encoder app subtype/version failed');
  const v3Decoded = browser.decodePayload(v3Encoded.text);
  assert(v3Decoded.encodingVersion === 3, 'v3 encoder browser round-trip version failed');
  assert(v3Decoded.width === 2 && v3Decoded.height === 2, 'v3 encoder browser round-trip size failed');
  assert(Array.from(v3Decoded.pixels).join(',') === '0,1,2,3', 'v3 encoder browser round-trip pixels failed');

  console.log(JSON.stringify({
    v1,
    v2,
    canvasApi: 'ok',
    channelDispatch: 'ok',
    v3Encoder: { chars: v3Encoded.text.length, bytes: v3Encoded.appPayloadWithoutSender.length },
  }, null, 2));
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
