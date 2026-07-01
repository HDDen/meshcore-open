'use strict';

// Dedicated MCOimg v3 worker entry point. A worker can process one or more
// deterministic candidate-search partitions. The coordinator merges partition
// winners by the codec's canonical comparator, so completion order is irrelevant.
(function(global) {
  let loadedCodecScriptUrl = null;

  function ensureCodec(codecScriptUrl) {
    if (!codecScriptUrl) throw new Error('codecScriptUrl is required');
    if (loadedCodecScriptUrl !== codecScriptUrl) {
      importScripts(codecScriptUrl);
      loadedCodecScriptUrl = codecScriptUrl;
    }
    if (!global.MCOImgV3 || typeof global.MCOImgV3.MCOImageV3Codec !== 'function') {
      throw new Error('MCOImgV3 codec global is unavailable');
    }
    return global.MCOImgV3.MCOImageV3Codec;
  }

  function errorPayload(error, data, extra = {}) {
    return {
      type: 'error',
      ok: false,
      jobId: data.jobId ?? null,
      workerIndex: data.workerIndex ?? 0,
      message: error && error.message ? error.message : String(error),
      name: error && error.name ? error.name : 'Error',
      stack: error && error.stack ? error.stack : '',
      ...extra,
    };
  }

  function postSearchProgress(data, partition, detail) {
    global.postMessage({
      type: 'search-progress',
      ok: true,
      jobId: data.jobId ?? null,
      workerIndex: data.workerIndex ?? 0,
      partitionOrder: partition.order,
      partitionType: partition.type,
      detail: detail || null,
    });
  }

  global.onmessage = function(event) {
    const data = event.data || {};
    try {
      const Codec = ensureCodec(data.codecScriptUrl);
      if (data.command === 'encodePartitions') {
        const partitions = Array.isArray(data.partitions) ? data.partitions : [];
        const total = partitions.length;
        for (let index = 0; index < total; index++) {
          const partition = partitions[index];
          const result = Codec.encodePartition(
            data.image,
            data.options || {},
            partition,
            (detail) => postSearchProgress(data, partition, detail),
          );
          global.postMessage({
            type: 'partition-result',
            ok: true,
            jobId: data.jobId ?? null,
            workerIndex: data.workerIndex ?? 0,
            partitionOrder: partition.order,
            partitionType: partition.type,
            completed: index + 1,
            total,
            result,
          });
        }
        global.postMessage({
          type: 'complete',
          ok: true,
          jobId: data.jobId ?? null,
          workerIndex: data.workerIndex ?? 0,
          completed: total,
          total,
        });
        return;
      }

      // Compatibility with the original single-job worker contract.
      if (data.command === 'encode') {
        const codec = new Codec();
        const encoded = codec.encode(data.image, data.options || {});
        global.postMessage({
          type: 'complete',
          ok: true,
          jobId: data.jobId ?? null,
          workerIndex: data.workerIndex ?? 0,
          partitionIndex: data.partitionIndex ?? 0,
          encoded,
        });
        return;
      }

      throw new Error(`Unsupported v3 worker command: ${data.command}`);
    } catch (error) {
      global.postMessage(errorPayload(error, data));
    }
  };
})(self);
