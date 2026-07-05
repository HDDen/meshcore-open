'use strict';

const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = path.resolve(__dirname, '..');
const messages = [];
const context = {
  console,
  Uint8Array,
  Uint8ClampedArray,
  ArrayBuffer,
  TextDecoder,
  TextEncoder,
  setTimeout,
  clearTimeout,
  postMessage(message) { messages.push(message); },
};
context.self = context;
context.globalThis = context;
context.importScripts = function(url) {
  if (url !== 'codec.js') throw new Error(`unexpected script ${url}`);
  if (!context.MCOImgV3) {
    vm.runInContext(
      fs.readFileSync(path.join(root, 'mcoimg-v3-codec.global.js'), 'utf8'),
      context,
      { filename: 'mcoimg-v3-codec.global.js' },
    );
  }
};
vm.createContext(context);
vm.runInContext(
  fs.readFileSync(path.join(root, 'mcoimg-v3-worker.global.js'), 'utf8'),
  context,
  { filename: 'mcoimg-v3-worker.global.js' },
);

function assert(condition, message) { if (!condition) throw new Error(message); }

const image = {
  width: 5,
  height: 4,
  paletteProfile: 2,
  pixels: [
    0, 0, 0, 0, 0,
    0, 2, 2, 0, 0,
    0, 2, 2, 0, 0,
    0, 0, 0, 0, 3,
  ],
  transparentColor: 0,
};
context.importScripts('codec.js');
const Codec = context.MCOImgV3.MCOImageV3Codec;
const plan = Codec.createWorkerPlan(image, {
  compressionLevel: 'extreme',
  packetNonce: 0x44,
  backgroundCandidates: [{ color: 0, rank: 0 }],
  scanModes: [0],
});
messages.length = 0;
context.onmessage({ data: {
  command: 'encodePartitions',
  codecScriptUrl: 'codec.js',
  jobId: 'worker-smoke',
  workerIndex: 0,
  image,
  options: plan.options,
  partitions: plan.partitions,
} });

const results = messages
  .filter((message) => message.type === 'partition-result')
  .map((message) => message.result);
const complete = messages.find((message) => message.type === 'complete');
assert(results.length === plan.totalPartitions, 'worker omitted partition results');
assert(complete && complete.ok, 'worker did not post completion');
assert(!messages.some((message) => message.ok === false), 'worker posted an error');
const merged = Codec.mergePartitionResults(results);
const sync = new Codec().encode(image, {
  compressionLevel: 'extreme',
  packetNonce: 0x44,
  backgroundCandidates: [{ color: 0, rank: 0 }],
  scanModes: [0],
});
assert(Buffer.from(merged.body).equals(Buffer.from(sync.body)),
  'worker entry result differs from sync result');

console.log(JSON.stringify({
  partitions: results.length,
  progressMessages: messages.filter((message) => message.type === 'search-progress').length,
  protocol: 'ok',
}, null, 2));
