'use strict';

const path = require('node:path');

require(path.resolve(__dirname, '..', 'mcoimg-codec.global.js'));
require(path.resolve(__dirname, '..', 'mcoimg-v3-codec.global.js'));
require(path.resolve(__dirname, '..', 'mcoimg-browser.global.js'));

const v3 = globalThis.MCOImgV3;
const browser = globalThis.MCOImgBrowser;
const codec = new v3.MCOImageV3Codec();

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function same(left, right) {
  return Buffer.from(left).equals(Buffer.from(right));
}

function concat(...parts) {
  const length = parts.reduce((sum, part) => sum + part.length, 0);
  const result = new Uint8Array(length);
  let offset = 0;
  for (const part of parts) {
    result.set(part, offset);
    offset += part.length;
  }
  return result;
}

const encoded = codec.encode({
  width: 3,
  height: 2,
  paletteProfile: v3.PaletteProfile.master8,
  pixels: [0, 3, 0, 6, 2, 5],
  transparentColor: null,
}, {
  compressionLevel: 'normal',
  packetNonce: 0x5a,
});

const senderName = 'Денис';
const senderBytes = new TextEncoder().encode(senderName);
assert(senderBytes.length < 0x80, 'test sender unexpectedly needs a multibyte varuint');
const envelope = concat(
  Uint8Array.of(senderBytes.length),
  senderBytes,
  encoded.appPayloadWithoutSender,
);
const channelLittle = concat(Uint8Array.of(7, 0x20, 0x01), envelope);
const channelBig = concat(Uint8Array.of(7, 0x01, 0x20), envelope);
const outgoing = concat(
  Uint8Array.of(0x04, 7, 2, 0xaa, 0xbb, 0x20, 0x01),
  envelope,
);

const cases = [
  {
    name: 'channel-little',
    bytes: channelLittle,
    options: { layout: 'channelData', byteOrder: 'little', formatVersion: 3 },
    expectedLayout: 'channelData',
    expectedOrder: 'little',
  },
  {
    name: 'channel-big',
    bytes: channelBig,
    options: { layout: 'channelData', byteOrder: 'big', formatVersion: 3 },
    expectedLayout: 'channelData',
    expectedOrder: 'big',
  },
  {
    name: 'outgoing-command',
    bytes: outgoing,
    options: { layout: 'outgoingCommand', byteOrder: 'little', formatVersion: 3 },
    expectedLayout: 'outgoingCommand',
    expectedOrder: 'little',
  },
  {
    name: 'envelope',
    bytes: envelope,
    options: { layout: 'envelope', formatVersion: 3 },
    expectedLayout: 'envelope',
    expectedOrder: null,
  },
  {
    name: 'raw-app-payload',
    bytes: encoded.appPayloadWithoutSender,
    options: { layout: 'rawMcoImage', formatVersion: 3 },
    expectedLayout: 'rawMcoImage',
    expectedOrder: null,
  },
];

const summaries = [];
for (const testCase of cases) {
  const info = browser.inspectMcoImageChannelPacket(testCase.bytes, testCase.options);
  assert(info.layout === testCase.expectedLayout, `${testCase.name}: layout mismatch`);
  assert(info.byteOrder === testCase.expectedOrder, `${testCase.name}: byte order mismatch`);
  assert(info.dataType === 0x0120, `${testCase.name}: data type mismatch`);
  assert(info.subtypeVersion === 0x13, `${testCase.name}: subtype/version mismatch`);
  assert(same(info.payload, encoded.appPayloadWithoutSender), `${testCase.name}: payload mismatch`);
  assert(same(info.body, encoded.body), `${testCase.name}: body mismatch`);
  if (testCase.expectedLayout === 'rawMcoImage') {
    assert(info.senderName === '', `${testCase.name}: raw payload sender should be empty`);
  } else {
    assert(info.senderName === senderName, `${testCase.name}: sender mismatch`);
  }
  assert(
    same(browser.extractMcoImagePayload(testCase.bytes, testCase.options), encoded.appPayloadWithoutSender),
    `${testCase.name}: extractMcoImagePayload mismatch`,
  );
  summaries.push({
    name: testCase.name,
    layout: info.layout,
    byteOrder: info.byteOrder,
    payloadBytes: info.payload.length,
    bodyBytes: info.body.length,
  });
}

for (const [name, bytes, expectedLayout] of [
  ['auto-channel', channelLittle, 'channelData'],
  ['auto-outgoing', outgoing, 'outgoingCommand'],
  ['auto-envelope', envelope, 'envelope'],
  ['auto-raw', encoded.appPayloadWithoutSender, 'rawMcoImage'],
]) {
  const info = browser.inspectMcoImageChannelPacket(bytes, { formatVersion: 3 });
  assert(info.layout === expectedLayout, `${name}: auto layout mismatch`);
  assert(same(info.body, encoded.body), `${name}: auto body mismatch`);
}

console.log(JSON.stringify({
  appDataType: '0x0120',
  subtypeVersion: '0x13',
  senderName,
  cases: summaries,
  autoDetection: 'ok',
}, null, 2));
