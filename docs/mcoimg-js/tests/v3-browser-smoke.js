'use strict';

const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = path.resolve(__dirname, '..');
const context = {
  console,
  Uint8Array,
  Uint8ClampedArray,
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
for (const file of ['mcoimg-codec.global.js', 'mcoimg-v3-codec.global.js', 'mcoimg-browser.global.js']) {
  vm.runInContext(fs.readFileSync(path.join(root, file), 'utf8'), context, { filename: file });
}

function assert(condition, message) { if (!condition) throw new Error(message); }
function same(a, b) { return Array.from(a).join(',') === Array.from(b).join(','); }

const { MCOImageV3Codec } = context.MCOImgV3;
const browser = context.MCOImgBrowser;
const body = Uint8Array.from([0x7a, 0x01, 0x00, 0xc2]); // 1x1 master4 solid color 2.
const app = Uint8Array.from([0x13, ...body]);
const text = MCOImageV3Codec.textFromBody(body);

assert(browser.inferTextFormatVersion(text) === 3, 'browser text format dispatch');
assert(browser.inferBinaryFormatVersion(app) === 3, 'browser binary format dispatch');
assert(same(browser.payloadToBinary(text), app), 'browser text to binary');
assert(browser.payloadToText(app) === text, 'browser binary to text');
const image = browser.decodePayload(text);
assert(image.encodingVersion === 3 && image.width === 1 && image.height === 1 && image.pixels[0] === 2,
  'browser v3 decode');
const info = browser.inspectPayload(text);
assert(info.version === 3 && info.containerName === 'solidBackground', 'browser v3 inspect');
const png = browser.textToPngBytes(text);
assert(browser.hasPngSignature(png), 'browser v3 PNG conversion');

console.log(JSON.stringify({ dispatch: 'ok', conversion: 'ok', decode: 'ok', inspect: 'ok', png: png.length }, null, 2));
