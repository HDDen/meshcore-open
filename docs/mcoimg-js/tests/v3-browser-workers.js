'use strict';

const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = path.resolve(__dirname, '..');
let context = null;

class FakeWorker {
  constructor(url) {
    this.url = url;
    this.onmessage = null;
    this.onerror = null;
    this.terminated = false;
    this.timers = [];
  }

  postMessage(data) {
    const delay = 5 + (2 - (data.workerIndex % 3)) * 7;
    const timer = setTimeout(() => {
      if (this.terminated) return;
      try {
        const Codec = context.MCOImgV3.MCOImageV3Codec;
        const partitions = data.partitions || [];
        for (let index = 0; index < partitions.length; index++) {
          if (this.terminated) return;
          const partition = partitions[index];
          const result = Codec.encodePartition(
            data.image,
            data.options,
            partition,
            (detail) => this.emit({
              type: 'search-progress',
              ok: true,
              jobId: data.jobId,
              workerIndex: data.workerIndex,
              partitionOrder: partition.order,
              partitionType: partition.type,
              detail,
            }),
          );
          this.emit({
            type: 'partition-result',
            ok: true,
            jobId: data.jobId,
            workerIndex: data.workerIndex,
            partitionOrder: partition.order,
            partitionType: partition.type,
            completed: index + 1,
            total: partitions.length,
            result,
          });
        }
        this.emit({
          type: 'complete',
          ok: true,
          jobId: data.jobId,
          workerIndex: data.workerIndex,
          completed: partitions.length,
          total: partitions.length,
        });
      } catch (error) {
        this.emit({
          type: 'error',
          ok: false,
          jobId: data.jobId,
          workerIndex: data.workerIndex,
          message: error.message,
          name: error.name,
          stack: error.stack,
        });
      }
    }, delay);
    this.timers.push(timer);
  }

  emit(data) {
    if (!this.terminated && typeof this.onmessage === 'function') {
      this.onmessage({ data });
    }
  }

  terminate() {
    this.terminated = true;
    for (const timer of this.timers) clearTimeout(timer);
    this.timers.length = 0;
  }
}

context = {
  console,
  Uint8Array,
  Uint8ClampedArray,
  ArrayBuffer,
  TextDecoder,
  TextEncoder,
  Promise,
  setTimeout,
  clearTimeout,
  Worker: FakeWorker,
  navigator: { hardwareConcurrency: 6 },
  AbortController,
};
context.globalThis = context;
vm.createContext(context);
for (const file of ['mcoimg-codec.global.js', 'mcoimg-v3-codec.global.js', 'mcoimg-browser.global.js']) {
  vm.runInContext(fs.readFileSync(path.join(root, file), 'utf8'), context, { filename: file });
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}
function same(a, b) {
  return Buffer.from(a).equals(Buffer.from(b));
}
function makeImage() {
  const width = 10;
  const height = 8;
  const pixels = Array(width * height).fill(0);
  for (let y = 1; y < 4; y++) for (let x = 1; x < 5; x++) pixels[y * width + x] = 2;
  for (let y = 5; y < 7; y++) for (let x = 6; x < 9; x++) pixels[y * width + x] = 5;
  pixels[2 * width + 8] = 3;
  return { width, height, paletteProfile: context.MCOImgV3.PaletteProfile.master8, pixels, transparentColor: 0 };
}

(async () => {
  const image = makeImage();
  assert(
    context.MCOImgBrowser.findV3WorkerScriptUrl(
      'https://example.test/assets/mcoimg-v3-codec.global.js?v=6',
    ) === 'https://example.test/assets/mcoimg-v3-worker.global.js?v=6',
    'v3 worker URL derivation failed',
  );
  const options = {
    formatVersion: 3,
    compressionLevel: 'extreme',
    packetNonce: 0x73,
    backgroundCandidates: [{ color: 0, rank: 0 }, { color: 1, rank: 1 }],
    scanModes: [0, 1],
    workerCount: 3,
    codecScriptUrl: 'fake-v3-codec.js',
    v3WorkerScriptUrl: 'fake-v3-worker.js',
  };
  const sync = new context.MCOImgV3.MCOImageV3Codec().encode(image, options);
  const progress = [];
  const task = context.MCOImgBrowser.startCancellableEncode(image, {
    ...options,
    onProgress: (event) => progress.push(event),
  });
  assert(task.workerCount === 3, 'browser did not create requested worker count');
  assert(task.totalPartitions === 9, 'unexpected partition count');
  const parallel = await task.result;
  assert(same(parallel.body, sync.body), 'browser workers changed the winning payload');
  assert(progress.some((event) => event.phase === 'partition' && event.percent === 1),
    'browser worker progress did not reach 100%');
  assert(!task.isCancelled, 'successful worker task is marked cancelled');

  const highOptions = {
    ...options,
    compressionLevel: 'high',
    useWorkers: true,
    packetNonce: 0x76,
  };
  const highExpected = new context.MCOImgV3.MCOImageV3Codec().encode(image, highOptions);
  const highTask = context.MCOImgBrowser.startCancellableEncode(image, highOptions);
  const highParallel = await highTask.result;
  assert(same(highParallel.body, highExpected.body), 'optional High workers changed payload');

  const cancelTask = context.MCOImgBrowser.startCancellableEncode(image, {
    ...options,
    packetNonce: 0x74,
  });
  cancelTask.cancel();
  let cancelError = null;
  try {
    await cancelTask.result;
  } catch (error) {
    cancelError = error;
  }
  assert(cancelError && cancelError.name === 'AbortError', 'cancel did not reject with AbortError');
  assert(cancelTask.isCancelled, 'cancelled task state was not preserved');

  const abortController = new AbortController();
  const abortTask = context.MCOImgBrowser.startCancellableEncode(image, {
    ...options,
    packetNonce: 0x77,
    signal: abortController.signal,
  });
  abortController.abort();
  let abortError = null;
  try {
    await abortTask.result;
  } catch (error) {
    abortError = error;
  }
  assert(abortError && abortError.name === 'AbortError', 'AbortSignal did not cancel workers');

  const fallback = context.MCOImgBrowser.startCancellableEncode(image, {
    ...options,
    useWorkers: false,
    packetNonce: 0x75,
  });
  assert(fallback.workerCount === 0, 'useWorkers:false did not use sync fallback');
  const fallbackResult = await fallback.result;
  const fallbackExpected = new context.MCOImgV3.MCOImageV3Codec().encode(image, {
    ...options,
    packetNonce: 0x75,
  });
  assert(same(fallbackResult.body, fallbackExpected.body), 'sync fallback changed payload');

  console.log(JSON.stringify({
    workers: task.workerCount,
    partitions: task.totalPartitions,
    deterministic: 'ok',
    progressEvents: progress.length,
    highWorkers: 'ok',
    cancellation: 'ok',
    abortSignal: 'ok',
    syncFallback: 'ok',
  }, null, 2));
})().catch((error) => {
  console.error(error && error.stack ? error.stack : error);
  process.exitCode = 1;
});
