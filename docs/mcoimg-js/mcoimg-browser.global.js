(function(global) {
  'use strict';

  const core = global.MCOImg;
  if (!core) {
    throw new Error(
      'MCOImgBrowser requires mcoimg-codec.global.js to be loaded first',
    );
  }

  const {
    MCOImageCodec,
    MCOImage,
    MCOImageRgbaOutputFormat,
    MCOImageTextOutputFormat,
    MCOImageBinaryOutputFormat,
    rgbaPixelsToMCOImage,
  } = core;

  function codecFromOptions(options = {}) {
    if (options.codec !== undefined) {
      if (!options.codec ||
          typeof options.codec.encodeRgbaPixels !== 'function' ||
          typeof options.codec.convertTextPayload !== 'function' ||
          typeof options.codec.convertBinaryPayload !== 'function') {
        throw new TypeError('options.codec is not a compatible MCOImageCodec');
      }
      return options.codec;
    }
    return new MCOImageCodec();
  }

  function canvasToImageData(sourceCanvas) {
    if (!sourceCanvas ||
        !Number.isInteger(sourceCanvas.width) ||
        !Number.isInteger(sourceCanvas.height) ||
        typeof sourceCanvas.getContext !== 'function') {
      throw new TypeError(
        'sourceCanvas must provide width, height, and getContext()',
      );
    }
    if (sourceCanvas.width <= 0 || sourceCanvas.height <= 0) {
      throw new RangeError('Canvas must have a non-zero backing size');
    }
    const context = sourceCanvas.getContext('2d', {
      willReadFrequently: true,
    });
    if (!context || typeof context.getImageData !== 'function') {
      throw new Error('Readable 2D canvas context is unavailable');
    }
    return context.getImageData(
      0,
      0,
      sourceCanvas.width,
      sourceCanvas.height,
    );
  }

  function canvasToRgbaInput(sourceCanvas) {
    const imageData = canvasToImageData(sourceCanvas);
    return {
      width: imageData.width,
      height: imageData.height,
      data: imageData.data,
    };
  }

  function canvasToMCOImage(
    sourceCanvas,
    paletteProfile,
    transparentColor = null,
    options = {},
  ) {
    return rgbaPixelsToMCOImage(
      canvasToRgbaInput(sourceCanvas),
      paletteProfile,
      transparentColor,
      options,
    );
  }

  function encodeCanvas(
    sourceCanvas,
    paletteProfile,
    transparentColor = null,
    outputFormat = MCOImageRgbaOutputFormat.text,
    options = {},
  ) {
    return codecFromOptions(options).encodeRgbaPixels(
      canvasToRgbaInput(sourceCanvas),
      paletteProfile,
      transparentColor,
      outputFormat,
      options,
    );
  }

  async function fileToCanvas(file) {
    if (typeof Blob === 'undefined' || !(file instanceof Blob)) {
      throw new TypeError('file must be a File or Blob');
    }
    if (typeof document === 'undefined') {
      throw new Error('fileToCanvas requires a browser document');
    }

    let drawable;
    let width;
    let height;
    let cleanup = () => {};

    if (typeof createImageBitmap === 'function') {
      drawable = await createImageBitmap(file);
      width = drawable.width;
      height = drawable.height;
      cleanup = () => {
        if (typeof drawable.close === 'function') drawable.close();
      };
    } else {
      const objectUrl = URL.createObjectURL(file);
      drawable = await new Promise((resolve, reject) => {
        const image = new Image();
        image.onload = () => resolve(image);
        image.onerror = () => reject(new Error('Image could not be decoded'));
        image.src = objectUrl;
      });
      width = drawable.naturalWidth || drawable.width;
      height = drawable.naturalHeight || drawable.height;
      cleanup = () => URL.revokeObjectURL(objectUrl);
    }

    try {
      if (!width || !height) throw new Error('Image has no readable size');
      const canvas = document.createElement('canvas');
      canvas.width = width;
      canvas.height = height;
      const context = canvas.getContext('2d');
      if (!context) throw new Error('2D canvas context is unavailable');
      context.imageSmoothingEnabled = false;
      context.clearRect(0, 0, width, height);
      context.drawImage(drawable, 0, 0, width, height);
      return canvas;
    } finally {
      cleanup();
    }
  }

  async function encodePngFile(
    file,
    paletteProfile,
    transparentColor = null,
    outputFormat = MCOImageRgbaOutputFormat.text,
    options = {},
  ) {
    const canvas = await fileToCanvas(file);
    return encodeCanvas(
      canvas,
      paletteProfile,
      transparentColor,
      outputFormat,
      options,
    );
  }

  function pngBytesToBlob(pngBytes) {
    return new Blob([pngBytes], { type: 'image/png' });
  }

  async function drawPngBytesToCanvas(pngBytes, targetCanvas) {
    if (!targetCanvas || typeof targetCanvas.getContext !== 'function') {
      throw new TypeError('targetCanvas must be a canvas element');
    }
    const blob = pngBytesToBlob(pngBytes);
    let drawable;
    let cleanup = () => {};

    if (typeof createImageBitmap === 'function') {
      drawable = await createImageBitmap(blob);
      cleanup = () => {
        if (typeof drawable.close === 'function') drawable.close();
      };
    } else {
      const objectUrl = URL.createObjectURL(blob);
      drawable = await new Promise((resolve, reject) => {
        const image = new Image();
        image.onload = () => resolve(image);
        image.onerror = () => reject(new Error('PNG bytes could not be decoded'));
        image.src = objectUrl;
      });
      cleanup = () => URL.revokeObjectURL(objectUrl);
    }

    try {
      const width = drawable.naturalWidth || drawable.width;
      const height = drawable.naturalHeight || drawable.height;
      targetCanvas.width = width;
      targetCanvas.height = height;
      const context = targetCanvas.getContext('2d');
      if (!context) throw new Error('2D canvas context is unavailable');
      context.imageSmoothingEnabled = false;
      context.clearRect(0, 0, width, height);
      context.drawImage(drawable, 0, 0, width, height);
      return { width, height };
    } finally {
      cleanup();
    }
  }

  function downloadBytes(bytes, fileName, mimeType) {
    if (typeof document === 'undefined') {
      throw new Error('downloadBytes requires a browser document');
    }
    const blob = new Blob([bytes], {
      type: mimeType || 'application/octet-stream',
    });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = fileName;
    document.body.appendChild(link);
    link.click();
    link.remove();
    URL.revokeObjectURL(url);
  }

  function textToPngBytes(text, options = {}) {
    return codecFromOptions(options).convertTextPayload(
      text,
      MCOImageTextOutputFormat.png,
    );
  }

  function binaryToPngBytes(binary, options = {}) {
    return codecFromOptions(options).convertBinaryPayload(
      binary,
      MCOImageBinaryOutputFormat.png,
    );
  }

  async function drawTextPayloadToCanvas(text, targetCanvas, options = {}) {
    return drawPngBytesToCanvas(textToPngBytes(text, options), targetCanvas);
  }

  async function drawBinaryPayloadToCanvas(binary, targetCanvas, options = {}) {
    return drawPngBytesToCanvas(binaryToPngBytes(binary, options), targetCanvas);
  }

  const ChannelBinaryDataFormat = Object.freeze({
    mcoImageDataType: 0xfff0,
    mcmpDataType: 0xfff1,
    channelDataHeaderLength: 3,
    outgoingCommandHeaderLength: 5,
  });

  function binaryBytes(bytesLike, label = 'binary packet') {
    if (bytesLike instanceof Uint8Array) return bytesLike;
    if (ArrayBuffer.isView(bytesLike)) {
      return new Uint8Array(
        bytesLike.buffer,
        bytesLike.byteOffset,
        bytesLike.byteLength,
      );
    }
    if (bytesLike instanceof ArrayBuffer) return new Uint8Array(bytesLike);
    if (Array.isArray(bytesLike)) return Uint8Array.from(bytesLike);
    throw new TypeError(`${label} must be Uint8Array, ArrayBuffer, or byte array`);
  }

  function readUnsignedLeb128(bytes, startOffset) {
    let value = 0;
    let shift = 0;
    let offset = startOffset;

    while (true) {
      if (offset >= bytes.length) {
        throw new RangeError('Unexpected end while reading sender-name length');
      }
      const byte = bytes[offset++];
      value += (byte & 0x7f) * (2 ** shift);
      if ((byte & 0x80) === 0) {
        return { value, nextOffset: offset };
      }
      shift += 7;
      if (shift > 28) {
        throw new RangeError('Sender-name length varuint is too long');
      }
    }
  }

  function readUtf8(bytes) {
    if (typeof TextDecoder === 'function') {
      return new TextDecoder('utf-8', { fatal: true }).decode(bytes);
    }

    // Fallback for older browser runtimes.
    let encoded = '';
    for (const byte of bytes) {
      encoded += `%${byte.toString(16).padStart(2, '0')}`;
    }
    return decodeURIComponent(encoded);
  }

  function readUint16At(bytes, offset, byteOrder) {
    if (offset < 0 || offset + 2 > bytes.length) {
      throw new RangeError('Not enough bytes for data_type u16');
    }
    if (byteOrder === 'big') {
      return (bytes[offset] << 8) | bytes[offset + 1];
    }
    return bytes[offset] | (bytes[offset + 1] << 8);
  }

  function matchingDataTypeOrder(bytes, offset, expectedDataType, byteOrder) {
    const allowed = byteOrder === 'auto'
      ? ['little', 'big']
      : [byteOrder];

    for (const order of allowed) {
      if (readUint16At(bytes, offset, order) === expectedDataType) {
        return order;
      }
    }
    return null;
  }

  function parseMcoImageEnvelope(
    envelopeBytes,
    {
      codec = new MCOImageCodec(),
      validate = true,
    } = {},
  ) {
    const envelope = binaryBytes(envelopeBytes, 'channel envelope');
    const senderLengthInfo = readUnsignedLeb128(envelope, 0);
    const senderStart = senderLengthInfo.nextOffset;
    const senderEnd = senderStart + senderLengthInfo.value;

    if (senderEnd > envelope.length) {
      throw new RangeError('Sender name extends beyond the channel envelope');
    }

    const senderNameBytes = envelope.subarray(senderStart, senderEnd);
    const senderName = readUtf8(senderNameBytes);
    const payload = envelope.slice(senderEnd);

    if (payload.length === 0) {
      throw new RangeError('Channel envelope contains no MCOimg payload');
    }

    if (validate) {
      codec.decodeBytes(payload);
    }

    return Object.freeze({
      senderName,
      senderNameLength: senderLengthInfo.value,
      envelopeLength: envelope.length,
      payloadOffset: senderEnd,
      payload,
    });
  }

  function parseChannelDataPacket(
    bytes,
    {
      expectedDataType,
      byteOrder,
      codec,
      validate,
    },
  ) {
    if (bytes.length < ChannelBinaryDataFormat.channelDataHeaderLength + 1) {
      throw new RangeError('Channel binary packet is too short');
    }

    const matchedOrder = matchingDataTypeOrder(
      bytes,
      1,
      expectedDataType,
      byteOrder,
    );
    if (!matchedOrder) {
      throw new RangeError(
        `Channel packet data_type is not 0x${expectedDataType.toString(16)}`,
      );
    }

    const envelopeOffset = ChannelBinaryDataFormat.channelDataHeaderLength;
    const envelope = parseMcoImageEnvelope(
      bytes.subarray(envelopeOffset),
      { codec, validate },
    );

    return Object.freeze({
      layout: 'channelData',
      byteOrder: matchedOrder,
      dataType: expectedDataType,
      channelIndex: bytes[0],
      command: null,
      pathLength: 0,
      path: new Uint8Array(0),
      envelopeOffset,
      ...envelope,
    });
  }

  function parseOutgoingCommandPacket(
    bytes,
    {
      expectedDataType,
      byteOrder,
      codec,
      validate,
    },
  ) {
    if (bytes.length < ChannelBinaryDataFormat.outgoingCommandHeaderLength + 1) {
      throw new RangeError('Outgoing channel command packet is too short');
    }

    const pathLength = bytes[2];
    const dataTypeOffset = 3 + pathLength;
    const envelopeOffset = dataTypeOffset + 2;

    if (envelopeOffset > bytes.length) {
      throw new RangeError('Outgoing channel command path extends beyond packet');
    }

    const matchedOrder = matchingDataTypeOrder(
      bytes,
      dataTypeOffset,
      expectedDataType,
      byteOrder,
    );
    if (!matchedOrder) {
      throw new RangeError(
        `Outgoing command data_type is not 0x${expectedDataType.toString(16)}`,
      );
    }

    const envelope = parseMcoImageEnvelope(
      bytes.subarray(envelopeOffset),
      { codec, validate },
    );

    return Object.freeze({
      layout: 'outgoingCommand',
      byteOrder: matchedOrder,
      dataType: expectedDataType,
      command: bytes[0],
      channelIndex: bytes[1],
      pathLength,
      path: bytes.slice(3, 3 + pathLength),
      envelopeOffset,
      ...envelope,
    });
  }

  function parseEnvelopePacket(
    bytes,
    {
      expectedDataType,
      codec,
      validate,
    },
  ) {
    const envelope = parseMcoImageEnvelope(bytes, { codec, validate });
    return Object.freeze({
      layout: 'envelope',
      byteOrder: null,
      dataType: expectedDataType,
      command: null,
      channelIndex: null,
      pathLength: 0,
      path: new Uint8Array(0),
      envelopeOffset: 0,
      ...envelope,
    });
  }

  function parseRawMcoImagePayload(
    bytes,
    {
      expectedDataType,
      codec,
      validate,
    },
  ) {
    if (validate) codec.decodeBytes(bytes);
    return Object.freeze({
      layout: 'rawMcoImage',
      byteOrder: null,
      dataType: expectedDataType,
      command: null,
      channelIndex: null,
      pathLength: 0,
      path: new Uint8Array(0),
      envelopeOffset: null,
      senderName: '',
      senderNameLength: 0,
      envelopeLength: null,
      payloadOffset: 0,
      payload: bytes.slice(),
    });
  }

  function inspectMcoImageChannelPacket(packetBytes, options = {}) {
    const bytes = binaryBytes(packetBytes);
    const layout = options.layout ?? 'auto';
    const byteOrder = options.byteOrder ?? 'auto';
    const expectedDataType =
      options.dataType ?? ChannelBinaryDataFormat.mcoImageDataType;
    const codec = codecFromOptions(options);
    const validate = options.validate !== false;

    if (!['auto', 'channelData', 'outgoingCommand', 'envelope', 'rawMcoImage']
      .includes(layout)) {
      throw new RangeError(
        'layout must be auto, channelData, outgoingCommand, envelope, or rawMcoImage',
      );
    }
    if (!['auto', 'little', 'big'].includes(byteOrder)) {
      throw new RangeError('byteOrder must be auto, little, or big');
    }

    const parsers = {
      channelData: () => parseChannelDataPacket(bytes, {
        expectedDataType,
        byteOrder,
        codec,
        validate,
      }),
      outgoingCommand: () => parseOutgoingCommandPacket(bytes, {
        expectedDataType,
        byteOrder,
        codec,
        validate,
      }),
      envelope: () => parseEnvelopePacket(bytes, {
        expectedDataType,
        codec,
        validate,
      }),
      rawMcoImage: () => parseRawMcoImagePayload(bytes, {
        expectedDataType,
        codec,
        validate,
      }),
    };

    if (layout !== 'auto') return parsers[layout]();

    const failures = [];
    for (const candidate of [
      'channelData',
      'outgoingCommand',
      'envelope',
      'rawMcoImage',
    ]) {
      try {
        return parsers[candidate]();
      } catch (error) {
        failures.push(`${candidate}: ${error.message}`);
      }
    }

    throw new RangeError(
      'Could not locate a valid MCOimg payload in the packet. ' +
      failures.join(' | '),
    );
  }

  function extractMcoImagePayload(packetBytes, options = {}) {
    return inspectMcoImageChannelPacket(packetBytes, options).payload;
  }

  function bytesToHex(bytes, columns = 16) {
    const source = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
    const rows = [];
    for (let offset = 0; offset < source.length; offset += columns) {
      const slice = source.subarray(offset, offset + columns);
      rows.push(
        `${offset.toString(16).padStart(4, '0')}: ` +
        Array.from(slice, (byte) => byte.toString(16).padStart(2, '0')).join(' '),
      );
    }
    return rows.join('\n');
  }

  function findCodecScriptUrl() {
    if (typeof document === 'undefined') return null;
    const scripts = Array.from(document.getElementsByTagName('script'));
    const script = scripts.find((item) =>
      item.src && /mcoimg-codec\.global\.js(?:[?#].*)?$/.test(item.src),
    );
    return script ? script.src : null;
  }

  function startCancellableEncode(imageLike, options = {}) {
    const useWorker = options.useWorker !== false &&
      typeof Worker === 'function' &&
      typeof Blob === 'function' &&
      typeof URL !== 'undefined' &&
      typeof URL.createObjectURL === 'function';
    const image = imageLike instanceof MCOImage ? imageLike : new MCOImage(imageLike);
    const encodeOptions = { ...options };
    delete encodeOptions.useWorker;
    delete encodeOptions.codec;
    delete encodeOptions.codecScriptUrl;

    if (!useWorker) {
      let cancelled = false;
      const result = Promise.resolve().then(() => {
        if (cancelled) throw new Error('Encoding was cancelled');
        const encoded = codecFromOptions(options).encode(image, encodeOptions);
        if (cancelled) throw new Error('Encoding was cancelled');
        return encoded;
      });
      return {
        result,
        get isCancelled() { return cancelled; },
        cancel() { cancelled = true; },
      };
    }

    const codecScriptUrl = options.codecScriptUrl || findCodecScriptUrl();
    if (!codecScriptUrl) {
      throw new Error('Could not locate mcoimg-codec.global.js for worker encoding');
    }

    const workerSource = `
      self.onmessage = function(event) {
        var data = event.data || {};
        try {
          importScripts(data.codecScriptUrl);
          var core = self.MCOImg;
          var codec = new core.MCOImageCodec();
          var image = new core.MCOImage(data.image);
          var encoded = codec.encode(image, data.options || {});
          self.postMessage({
            ok: true,
            encoded: {
              text: encoded.text,
              mode: encoded.mode,
              modeName: encoded.modeName,
              scan: encoded.scan,
              scanName: encoded.scanName,
              byteLength: encoded.byteLength,
              charLength: encoded.charLength,
              boundsPresent: !!encoded.boundsPresent,
              boundsX: encoded.boundsX,
              boundsY: encoded.boundsY,
              boundsWidth: encoded.boundsWidth,
              boundsHeight: encoded.boundsHeight,
              backgroundColor: encoded.backgroundColor,
              transparentColor: encoded.transparentColor,
              regionCount: encoded.regionCount || 0,
              backgroundRank: encoded.backgroundRank || 0,
              codecVersion: encoded.codecVersion,
              dynamicReferenceEncoding: encoded.dynamicReferenceEncoding,
              localPaletteSize: encoded.localPaletteSize,
              usedBankCount: encoded.usedBankCount,
              bitsPerLocalPixel: encoded.bitsPerLocalPixel,
              requestedEncodingVersion: encoded.requestedEncodingVersion,
              actualEncodingVersion: encoded.actualEncodingVersion,
              paletteKind: encoded.paletteKind,
              container: encoded.container,
              payload: encoded.payload,
            },
          });
        } catch (error) {
          self.postMessage({
            ok: false,
            message: error && error.message ? error.message : String(error),
            name: error && error.name ? error.name : 'Error',
            stack: error && error.stack ? error.stack : '',
          });
        }
      };
    `;
    const blob = new Blob([workerSource], { type: 'text/javascript' });
    const workerUrl = URL.createObjectURL(blob);
    const worker = new Worker(workerUrl);
    let cancelled = false;
    let settled = false;
    let rejectResult = null;

    const result = new Promise((resolve, reject) => {
      rejectResult = reject;
      worker.onmessage = (event) => {
        if (settled) return;
        settled = true;
        worker.terminate();
        URL.revokeObjectURL(workerUrl);
        if (cancelled) {
          reject(new Error('Encoding was cancelled'));
          return;
        }
        const data = event.data || {};
        if (data.ok) resolve(data.encoded);
        else {
          const error = new Error(data.message || 'Worker encoding failed');
          error.name = data.name || error.name;
          error.stack = data.stack || error.stack;
          reject(error);
        }
      };
      worker.onerror = (event) => {
        if (settled) return;
        settled = true;
        worker.terminate();
        URL.revokeObjectURL(workerUrl);
        reject(new Error(event.message || 'Worker encoding failed'));
      };
    });

    worker.postMessage({
      codecScriptUrl,
      image: {
        width: image.width,
        height: image.height,
        paletteProfile: image.paletteProfile,
        pixels: image.pixels,
        transparentColor: image.transparentColor,
        encodingVersion: image.encodingVersion,
      },
      options: encodeOptions,
    });

    return {
      result,
      get isCancelled() { return cancelled; },
      cancel() {
        if (cancelled || settled) return;
        cancelled = true;
        settled = true;
        worker.terminate();
        URL.revokeObjectURL(workerUrl);
        if (rejectResult) rejectResult(new Error('Encoding was cancelled'));
      },
    };
  }

  global.MCOImgBrowser = Object.freeze({
    canvasToImageData,
    canvasToRgbaInput,
    canvasToMCOImage,
    encodeCanvas,
    fileToCanvas,
    encodePngFile,
    pngBytesToBlob,
    drawPngBytesToCanvas,
    downloadBytes,
    textToPngBytes,
    binaryToPngBytes,
    drawTextPayloadToCanvas,
    drawBinaryPayloadToCanvas,
    ChannelBinaryDataFormat,
    parseMcoImageEnvelope,
    inspectMcoImageChannelPacket,
    extractMcoImagePayload,
    bytesToHex,
    startCancellableEncode,
  });
})(typeof window !== 'undefined' ? window : globalThis);
