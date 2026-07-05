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
    rgbaPixelsToMCOImage,
  } = core;

  const MCOImageFormatVersion = Object.freeze({
    v1Legacy: 1,
    v2: 2,
    v3: 3,
  });

  const MCOImagePayloadInputFormat = Object.freeze({
    auto: 'auto',
    text: 'text',
    binary: 'binary',
    png: 'png',
  });

  const MCOImagePayloadOutputFormat = Object.freeze({
    text: 'text',
    binary: 'binary',
    png: 'png',
    image: 'image',
    encoded: 'encoded',
  });

  function normalizeFormatVersion(value, fallback = MCOImageFormatVersion.v2) {
    if (value === undefined || value === null || value === '') return fallback;
    if (value === 'v1' || value === 'v1Legacy' || value === 'legacy') {
      return MCOImageFormatVersion.v1Legacy;
    }
    if (value === 'v2') return MCOImageFormatVersion.v2;
    if (value === 'v3') return MCOImageFormatVersion.v3;
    const numeric = Number(value);
    if ([1, 2, 3].includes(numeric)) return numeric;
    throw new RangeError('formatVersion must be 1, 2, or 3');
  }

  function normalizeCompressionLevel(value, fallback = 0) {
    if (value === undefined || value === null || value === '') return fallback;
    if (value === 'high') return 0;
    if (value === 'normal') return 1;
    if (value === 'extreme') return 2;
    const numeric = Number(value);
    if ([0, 1, 2].includes(numeric)) return numeric;
    throw new RangeError('compressionLevel must be high, normal, extreme, 0, 1, or 2');
  }

  function v3Core() {
    return global.MCOImgV3 || null;
  }

  function inferTextFormatVersion(text) {
    const normalized = String(text).trim();
    if (normalized.startsWith('im3:')) return MCOImageFormatVersion.v3;
    if (normalized.startsWith('im:')) {
      const info = MCOImageCodec.inspectPayload(normalized);
      return info && info.version === 1
        ? MCOImageFormatVersion.v1Legacy
        : MCOImageFormatVersion.v2;
    }
    throw new RangeError('Text payload must start with im: or im3:');
  }

  function inferBinaryFormatVersion(bytesLike, options = {}) {
    if (options.formatVersion !== undefined || options.encodingVersion !== undefined) {
      return normalizeFormatVersion(
        options.formatVersion ?? options.encodingVersion,
      );
    }
    const bytes = binaryBytes(bytesLike, 'binary MCOimg payload');
    // Canonical v3 binary is appPayloadWithoutSender and starts with 0x13.
    if (bytes.length > 0 && bytes[0] === 0x13) {
      return MCOImageFormatVersion.v3;
    }
    const info = MCOImageCodec.inspectPayloadBytes(bytes);
    if (info && info.version === 1) return MCOImageFormatVersion.v1Legacy;
    return MCOImageFormatVersion.v2;
  }

  function codecFromOptions(options = {}, inferredVersion = null) {
    if (options.codec !== undefined) {
      if (!options.codec || typeof options.codec !== 'object') {
        throw new TypeError('options.codec must be a codec object');
      }
      return options.codec;
    }
    const formatVersion = normalizeFormatVersion(
      options.formatVersion ?? options.encodingVersion,
      inferredVersion ?? MCOImageFormatVersion.v2,
    );
    if (formatVersion === MCOImageFormatVersion.v3) {
      const v3 = v3Core();
      if (!v3 || typeof v3.MCOImageV3Codec !== 'function') {
        throw new Error(
          'MCOimg v3 requires mcoimg-v3-codec.global.js to be loaded before mcoimg-browser.global.js',
        );
      }
      return new v3.MCOImageV3Codec();
    }
    return new MCOImageCodec();
  }

  function imageForFormat(imageLike, formatVersion) {
    if (formatVersion === MCOImageFormatVersion.v3) {
      return {
        width: Number(imageLike.width),
        height: Number(imageLike.height),
        paletteProfile: Number(imageLike.paletteProfile),
        pixels: Array.from(imageLike.pixels || []),
        transparentColor: imageLike.transparentColor == null
          ? null
          : Number(imageLike.transparentColor),
        encodingVersion: MCOImageFormatVersion.v3,
      };
    }
    return imageLike instanceof MCOImage
      ? imageLike
      : new MCOImage({
        ...imageLike,
        encodingVersion: formatVersion,
      });
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
    paletteProfileOrOptions,
    transparentColor = null,
    outputFormat = MCOImageRgbaOutputFormat.text,
    options = {},
  ) {
    // New version-neutral object form:
    //   await encodeCanvas(canvas, { formatVersion: 3, paletteProfile, output })
    if (paletteProfileOrOptions &&
        typeof paletteProfileOrOptions === 'object' &&
        !Number.isInteger(paletteProfileOrOptions)) {
      return encodeCanvasUniversal(sourceCanvas, paletteProfileOrOptions);
    }

    // Backward-compatible v1/v2 positional form.
    return codecFromOptions(options).encodeRgbaPixels(
      canvasToRgbaInput(sourceCanvas),
      paletteProfileOrOptions,
      transparentColor,
      outputFormat,
      options,
    );
  }

  async function encodeCanvasUniversal(sourceCanvas, options = {}) {
    const formatVersion = normalizeFormatVersion(options.formatVersion, 2);
    const paletteProfile = options.paletteProfile;
    if (!Number.isInteger(paletteProfile)) {
      throw new TypeError('options.paletteProfile must be an integer palette profile');
    }
    const prepared = rgbaPixelsToMCOImage(
      canvasToRgbaInput(sourceCanvas),
      paletteProfile,
      options.transparentColor ?? null,
      {
        ...options,
        encodingVersion: formatVersion === 1 ? 1 : 2,
      },
    );
    const image = {
      width: prepared.width,
      height: prepared.height,
      paletteProfile: prepared.paletteProfile,
      pixels: prepared.pixels,
      transparentColor: formatVersion === 1 ? null : prepared.transparentColor,
      encodingVersion: formatVersion,
    };
    return encodeImage(image, {
      ...options,
      formatVersion,
      compressionLevel: normalizeCompressionLevel(options.compressionLevel, 0),
    });
  }

  async function encodeImage(imageLike, options = {}) {
    const formatVersion = normalizeFormatVersion(
      options.formatVersion ?? options.encodingVersion ?? imageLike.encodingVersion,
      MCOImageFormatVersion.v2,
    );
    const output = options.output ?? 'encoded';
    const task = startCancellableEncode(imageLike, {
      ...options,
      formatVersion,
      outputTarget: options.outputTarget ?? (output === 'binary' ? 'binary' : 'text'),
    });
    const encoded = await task.result;
    return encodedResultToOutput(encoded, output, {
      ...options,
      formatVersion,
    });
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
    paletteProfileOrOptions,
    transparentColor = null,
    outputFormat = MCOImageRgbaOutputFormat.text,
    options = {},
  ) {
    const canvas = await fileToCanvas(file);
    if (paletteProfileOrOptions &&
        typeof paletteProfileOrOptions === 'object' &&
        !Number.isInteger(paletteProfileOrOptions)) {
      return encodeCanvasUniversal(canvas, paletteProfileOrOptions);
    }
    return encodeCanvas(
      canvas,
      paletteProfileOrOptions,
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

  function imageWithFormatVersion(image, formatVersion) {
    if (!image || typeof image !== 'object') return image;
    if (image.encodingVersion === formatVersion) return image;
    try {
      image.encodingVersion = formatVersion;
      return image;
    } catch (_) {
      return { ...image, encodingVersion: formatVersion };
    }
  }

  function decodePayload(payload, options = {}) {
    const input = options.input ?? 'auto';
    const isText = input === 'text' || (input === 'auto' && typeof payload === 'string');
    if (isText) {
      const text = String(payload).trim();
      const formatVersion = normalizeFormatVersion(
        options.formatVersion,
        inferTextFormatVersion(text),
      );
      const codec = codecFromOptions(options, formatVersion);
      if (formatVersion === 3) {
        if (typeof codec.decodeText !== 'function') {
          throw new TypeError('The selected v3 codec does not implement decodeText()');
        }
        return imageWithFormatVersion(
          codec.decodeText(text),
          formatVersion,
        );
      }
      return imageWithFormatVersion(codec.decode(text), formatVersion);
    }

    const bytes = binaryBytes(payload, 'binary MCOimg payload');
    const formatVersion = inferBinaryFormatVersion(bytes, options);
    const codec = codecFromOptions(options, formatVersion);
    if (formatVersion === 3 && bytes[0] === 0x13 &&
        typeof codec.decodeAppPayloadWithoutSender === 'function') {
      return imageWithFormatVersion(
        codec.decodeAppPayloadWithoutSender(bytes),
        formatVersion,
      );
    }
    if (typeof codec.decodeBytes !== 'function') {
      throw new TypeError('The selected codec does not implement decodeBytes()');
    }
    return imageWithFormatVersion(codec.decodeBytes(bytes), formatVersion);
  }

  function payloadToBinary(payload, options = {}) {
    if (typeof payload !== 'string') {
      return binaryBytes(payload, 'binary MCOimg payload').slice();
    }
    const text = payload.trim();
    const formatVersion = normalizeFormatVersion(
      options.formatVersion,
      inferTextFormatVersion(text),
    );
    if (formatVersion === 3) {
      const v3 = v3Core();
      if (!v3 || typeof v3.MCOImageV3Codec.appPayloadWithoutSenderFromText !== 'function') {
        throw new Error('The loaded v3 codec cannot convert text to binary');
      }
      return binaryBytes(
        v3.MCOImageV3Codec.appPayloadWithoutSenderFromText(text),
        'MCOimg v3 app payload',
      ).slice();
    }
    return new Uint8Array(MCOImageCodec.binaryPayloadFromText(text));
  }

  function payloadToText(payload, options = {}) {
    if (typeof payload === 'string') return payload.trim();
    const bytes = binaryBytes(payload, 'binary MCOimg payload');
    const formatVersion = inferBinaryFormatVersion(bytes, options);
    if (formatVersion === 3) {
      const v3 = v3Core();
      if (!v3 || typeof v3.MCOImageV3Codec.textFromAppPayloadWithoutSender !== 'function') {
        throw new Error('The loaded v3 codec cannot convert binary to text');
      }
      return v3.MCOImageV3Codec.textFromAppPayloadWithoutSender(bytes);
    }
    return MCOImageCodec.textFromBinaryPayload(bytes);
  }

  function inspectPayload(payload, options = {}) {
    if (typeof payload === 'string') {
      const text = payload.trim();
      const formatVersion = normalizeFormatVersion(
        options.formatVersion,
        inferTextFormatVersion(text),
      );
      if (formatVersion === 3) {
        const v3 = v3Core();
        if (!v3 || typeof v3.MCOImageV3Codec.inspectText !== 'function') {
          throw new Error('The loaded v3 codec cannot inspect text payloads');
        }
        return v3.MCOImageV3Codec.inspectText(text);
      }
      return MCOImageCodec.inspectPayload(text);
    }
    const bytes = binaryBytes(payload, 'binary MCOimg payload');
    const formatVersion = inferBinaryFormatVersion(bytes, options);
    if (formatVersion === 3) {
      const v3 = v3Core();
      if (!v3 || typeof v3.MCOImageV3Codec.inspectAppPayloadWithoutSender !== 'function') {
        throw new Error('The loaded v3 codec cannot inspect binary payloads');
      }
      return v3.MCOImageV3Codec.inspectAppPayloadWithoutSender(bytes);
    }
    return MCOImageCodec.inspectPayloadBytes(bytes);
  }

  function imageToPngBytes(image) {
    if (typeof core.mcoImageToPngBytes !== 'function') {
      throw new Error('PNG conversion is unavailable in the loaded v1/v2 core');
    }
    // The shared PNG renderer only needs dimensions, palette indexes and
    // transparency. Its MCOImage wrapper deliberately knows only v1/v2, so do
    // not pass the v3 wire-version marker into that compatibility layer.
    if (image && Number(image.encodingVersion) === MCOImageFormatVersion.v3) {
      const portableImage = {
        width: image.width,
        height: image.height,
        paletteProfile: image.paletteProfile,
        pixels: image.pixels,
        transparentColor: image.transparentColor,
      };
      return core.mcoImageToPngBytes(portableImage);
    }
    return core.mcoImageToPngBytes(image);
  }

  function encodedResultToOutput(encoded, output, options = {}) {
    const normalized = output ?? 'encoded';
    if (normalized === 'encoded') return encoded;
    if (normalized === 'text') {
      if (typeof encoded.text === 'string') return encoded.text;
      if (encoded.appPayloadWithoutSender) {
        return payloadToText(encoded.appPayloadWithoutSender, options);
      }
      throw new Error('Encoded result does not expose a text payload');
    }
    if (normalized === 'binary') {
      if (encoded.appPayloadWithoutSender) {
        return binaryBytes(encoded.appPayloadWithoutSender).slice();
      }
      if (encoded.payload) return binaryBytes(encoded.payload).slice();
      if (typeof encoded.text === 'string') return payloadToBinary(encoded.text, options);
      throw new Error('Encoded result does not expose a binary payload');
    }
    if (normalized === 'image') {
      const text = encodedResultToOutput(encoded, 'text', options);
      return decodePayload(text, { ...options, input: 'text' });
    }
    if (normalized === 'png') {
      return imageToPngBytes(encodedResultToOutput(encoded, 'image', options));
    }
    throw new RangeError('output must be text, binary, png, image, or encoded');
  }

  function hasPngSignature(bytesLike) {
    let bytes;
    try {
      bytes = binaryBytes(bytesLike, 'PNG bytes');
    } catch (_) {
      return false;
    }
    return bytes.length >= 8 &&
      bytes[0] === 0x89 && bytes[1] === 0x50 &&
      bytes[2] === 0x4e && bytes[3] === 0x47 &&
      bytes[4] === 0x0d && bytes[5] === 0x0a &&
      bytes[6] === 0x1a && bytes[7] === 0x0a;
  }

  function detectedInputFormat(payload, requested = 'auto') {
    if (requested !== 'auto') return requested;
    if (typeof payload === 'string') return 'text';
    if (typeof Blob !== 'undefined' && payload instanceof Blob &&
        String(payload.type || '').startsWith('image/')) {
      return 'png';
    }
    if (hasPngSignature(payload)) return 'png';
    return 'binary';
  }

  async function pngPayloadToBlob(payload) {
    if (typeof Blob !== 'undefined' && payload instanceof Blob) return payload;
    const bytes = binaryBytes(payload, 'PNG bytes');
    return new Blob([bytes], { type: 'image/png' });
  }

  async function convertPayload(payload, options = {}) {
    const output = options.output ?? 'image';
    const input = detectedInputFormat(payload, options.input ?? 'auto');

    if (input === 'png') {
      if (output === 'png') {
        if (typeof Blob !== 'undefined' && payload instanceof Blob) {
          return new Uint8Array(await payload.arrayBuffer());
        }
        return binaryBytes(payload, 'PNG bytes').slice();
      }
      const canvas = await fileToCanvas(await pngPayloadToBlob(payload));
      return encodeCanvasUniversal(canvas, {
        ...options,
        input: undefined,
        output,
      });
    }

    const dispatchOptions = { ...options, input };
    if (output === 'text') return payloadToText(payload, dispatchOptions);
    if (output === 'binary') return payloadToBinary(payload, dispatchOptions);
    const image = decodePayload(payload, dispatchOptions);
    if (output === 'image') return image;
    if (output === 'png') return imageToPngBytes(image);
    throw new RangeError('output must be text, binary, png, or image');
  }

  function textToPngBytes(text, options = {}) {
    return imageToPngBytes(decodePayload(text, { ...options, input: 'text' }));
  }

  function binaryToPngBytes(binary, options = {}) {
    return imageToPngBytes(decodePayload(binary, { ...options, input: 'binary' }));
  }

  async function drawTextPayloadToCanvas(text, targetCanvas, options = {}) {
    return drawPngBytesToCanvas(textToPngBytes(text, options), targetCanvas);
  }

  async function drawBinaryPayloadToCanvas(binary, targetCanvas, options = {}) {
    return drawPngBytesToCanvas(binaryToPngBytes(binary, options), targetCanvas);
  }

  const ChannelBinaryDataFormat = Object.freeze({
    // Legacy v1/v2 developer namespace.
    legacyMcoImageDataType: 0xfff0,
    mcoImageDataType: 0xfff0,
    mcmpDataType: 0xfff1,

    // Official MCO Advanced app-data route used by MCOimg v3. The channel
    // envelope payload begins with subtypeVersion 0x13, followed by the v3
    // nonce-prefixed body.
    appDataType: 0x0120,
    mcoImageV3SubtypeVersion: 0x13,

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
      formatVersion = MCOImageFormatVersion.v2,
      codec = codecFromOptions({ formatVersion }, formatVersion),
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

    const isV3 = formatVersion === MCOImageFormatVersion.v3;
    if (isV3 && payload[0] !== ChannelBinaryDataFormat.mcoImageV3SubtypeVersion) {
      throw new RangeError(
        'MCOimg v3 app envelope does not start with subtype/version 0x13',
      );
    }

    if (validate) {
      decodePayload(payload, {
        input: 'binary',
        formatVersion,
        codec,
      });
    }

    return Object.freeze({
      senderName,
      senderNameLength: senderLengthInfo.value,
      envelopeLength: envelope.length,
      payloadOffset: senderEnd,
      payload,
      subtypeVersion: isV3 ? payload[0] : null,
      body: isV3 ? payload.slice(1) : payload.slice(),
    });
  }

  function parseChannelDataPacket(
    bytes,
    {
      expectedDataType,
      byteOrder,
      formatVersion,
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
      { formatVersion, codec, validate },
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
      formatVersion,
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
      { formatVersion, codec, validate },
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
      formatVersion,
      codec,
      validate,
    },
  ) {
    const envelope = parseMcoImageEnvelope(
      bytes,
      { formatVersion, codec, validate },
    );
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
      formatVersion,
      codec,
      validate,
    },
  ) {
    if (validate) {
      decodePayload(bytes, {
        input: 'binary',
        formatVersion,
        codec,
      });
    }
    const isV3 = formatVersion === MCOImageFormatVersion.v3;
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
      subtypeVersion: isV3 ? bytes[0] : null,
      body: isV3 ? bytes.slice(1) : bytes.slice(),
    });
  }

  function inspectMcoImageChannelPacket(packetBytes, options = {}) {
    const bytes = binaryBytes(packetBytes);
    const layout = options.layout ?? 'auto';
    const byteOrder = options.byteOrder ?? 'auto';
    const inferredFormatVersion = options.dataType === ChannelBinaryDataFormat.appDataType
      ? MCOImageFormatVersion.v3
      : MCOImageFormatVersion.v2;
    const formatVersion = normalizeFormatVersion(
      options.formatVersion ?? options.encodingVersion,
      inferredFormatVersion,
    );
    const expectedDataType = options.dataType ?? (
      formatVersion === MCOImageFormatVersion.v3
        ? ChannelBinaryDataFormat.appDataType
        : ChannelBinaryDataFormat.mcoImageDataType
    );
    const codec = codecFromOptions(options, formatVersion);
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
        formatVersion,
        codec,
        validate,
      }),
      outgoingCommand: () => parseOutgoingCommandPacket(bytes, {
        expectedDataType,
        byteOrder,
        formatVersion,
        codec,
        validate,
      }),
      envelope: () => parseEnvelopePacket(bytes, {
        expectedDataType,
        formatVersion,
        codec,
        validate,
      }),
      rawMcoImage: () => parseRawMcoImagePayload(bytes, {
        expectedDataType,
        formatVersion,
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

  function findCodecScriptUrl(formatVersion = MCOImageFormatVersion.v2) {
    if (typeof document === 'undefined') return null;
    const scripts = Array.from(document.getElementsByTagName('script'));
    const pattern = formatVersion === MCOImageFormatVersion.v3
      ? /mcoimg-v3-codec\.global\.js(?:[?#].*)?$/
      : /mcoimg-codec\.global\.js(?:[?#].*)?$/;
    const script = scripts.find((item) => item.src && pattern.test(item.src));
    return script ? script.src : null;
  }

  function findV3WorkerScriptUrl(codecScriptUrl = null) {
    if (typeof document !== 'undefined') {
      const scripts = Array.from(document.getElementsByTagName('script'));
      const explicit = scripts.find((item) =>
        item.src && /mcoimg-v3-worker\.global\.js(?:[?#].*)?$/.test(item.src));
      if (explicit) return explicit.src;
    }
    const source = codecScriptUrl || findCodecScriptUrl(MCOImageFormatVersion.v3);
    if (!source) return null;
    return source.replace(
      /mcoimg-v3-codec\.global\.js(?=([?#].*)?$)/,
      'mcoimg-v3-worker.global.js',
    );
  }

  function defaultWorkerCount() {
    const hardware = typeof navigator !== 'undefined'
      ? Number(navigator.hardwareConcurrency) || 2
      : 2;
    return Math.max(1, Math.min(8, hardware));
  }

  function shouldUseWorkers(formatVersion, compressionLevel, options) {
    if (options.useWorkers !== undefined) return options.useWorkers !== false;
    if (options.useWorker !== undefined) return options.useWorker !== false;
    if (formatVersion === MCOImageFormatVersion.v3) {
      return compressionLevel === 2;
    }
    // Preserve the previous v1/v2 browser-helper behavior.
    return true;
  }

  function cancellationError() {
    const error = new Error('Encoding was cancelled');
    error.name = 'AbortError';
    return error;
  }

  function cloneableEncodeOptions(options, compressionLevel, workerCount, formatVersion) {
    const result = {
      ...options,
      compressionLevel,
      workerCount,
      encodingVersion: formatVersion,
    };
    for (const key of [
      'useWorker', 'useWorkers', 'codec', 'codecScriptUrl', 'v3CodecScriptUrl',
      'v3WorkerScriptUrl', 'formatVersion', 'onProgress', 'signal',
    ]) delete result[key];
    return result;
  }

  function startSynchronousEncode(image, options, encodeOptions, formatVersion) {
    let cancelled = false;
    let settled = false;
    let rejectResult = null;
    const signal = options.signal || null;
    const userProgress = typeof options.onProgress === 'function' ? options.onProgress : null;
    const onAbort = () => task.cancel();
    const progress = (detail) => {
      if (cancelled || (signal && signal.aborted)) throw cancellationError();
      if (userProgress) userProgress(detail);
      if (cancelled || (signal && signal.aborted)) throw cancellationError();
    };
    const task = {
      result: null,
      formatVersion,
      workerCount: 0,
      get isCancelled() { return cancelled; },
      cancel() {
        if (cancelled || settled) return;
        cancelled = true;
        if (rejectResult) rejectResult(cancellationError());
      },
    };
    task.result = new Promise((resolve, reject) => {
      rejectResult = reject;
      Promise.resolve().then(() => {
        if (cancelled || (signal && signal.aborted)) throw cancellationError();
        const codec = codecFromOptions(options, formatVersion);
        if (typeof codec.encode !== 'function') {
          throw new TypeError('The selected codec does not implement encode()');
        }
        const encoded = codec.encode(image, {
          ...encodeOptions,
          onProgress: progress,
        });
        if (cancelled || (signal && signal.aborted)) throw cancellationError();
        return encoded;
      }).then((encoded) => {
        if (settled || cancelled) return;
        settled = true;
        if (signal && typeof signal.removeEventListener === 'function') {
          signal.removeEventListener('abort', onAbort);
        }
        resolve(encoded);
      }, (error) => {
        if (settled) return;
        settled = true;
        if (signal && typeof signal.removeEventListener === 'function') {
          signal.removeEventListener('abort', onAbort);
        }
        reject(error);
      });
    });
    if (signal && typeof signal.addEventListener === 'function') {
      if (signal.aborted) task.cancel();
      else signal.addEventListener('abort', onAbort, { once: true });
    }
    return task;
  }

  function startV3PartitionedEncode(image, options, encodeOptions, codecScriptUrl, workerCount) {
    const v3 = v3Core();
    if (!v3 || typeof v3.MCOImageV3Codec !== 'function') {
      throw new Error('MCOimg v3 codec is unavailable in the main thread');
    }
    const Codec = v3.MCOImageV3Codec;
    if (typeof Codec.createWorkerPlan !== 'function' ||
        typeof Codec.mergePartitionResults !== 'function') {
      throw new Error('This MCOimg v3 codec does not support partitioned workers');
    }
    const plan = Codec.createWorkerPlan(image, encodeOptions);
    const workerScriptUrl = options.v3WorkerScriptUrl || findV3WorkerScriptUrl(codecScriptUrl);
    if (!workerScriptUrl) {
      throw new Error('Could not locate mcoimg-v3-worker.global.js');
    }
    const actualWorkerCount = Math.max(
      1,
      Math.min(workerCount, Math.max(1, plan.partitions.length)),
    );
    const queues = Array.from({ length: actualWorkerCount }, () => []);
    plan.partitions.forEach((partition, index) => {
      queues[index % actualWorkerCount].push(partition);
    });

    const workers = [];
    const results = [];
    const userProgress = typeof options.onProgress === 'function' ? options.onProgress : null;
    const signal = options.signal || null;
    const jobId = `mcoimg-v3-${Date.now()}-${Math.random().toString(36).slice(2)}`;
    let completedPartitions = 0;
    let completedWorkers = 0;
    let cancelled = false;
    let settled = false;
    let rejectResult = null;
    const onAbort = () => task.cancel();

    const cleanup = () => {
      for (const worker of workers) worker.terminate();
      if (signal && typeof signal.removeEventListener === 'function') {
        signal.removeEventListener('abort', onAbort);
      }
    };
    const reportProgress = (event) => {
      if (!userProgress) return;
      const total = plan.totalPartitions;
      try {
        userProgress({
          phase: event.phase,
          completed: completedPartitions,
          total,
          percent: total === 0 ? 1 : completedPartitions / total,
          workerIndex: event.workerIndex,
          partitionOrder: event.partitionOrder ?? null,
          partitionType: event.partitionType ?? null,
          detail: event.detail ?? null,
        });
      } catch (_) {
        // Progress callbacks are advisory and must not invalidate encoding.
      }
    };
    const fail = (error) => {
      if (settled) return;
      settled = true;
      cleanup();
      rejectResult(error);
    };
    const task = {
      result: null,
      formatVersion: MCOImageFormatVersion.v3,
      workerCount: actualWorkerCount,
      totalPartitions: plan.totalPartitions,
      get isCancelled() { return cancelled; },
      cancel() {
        if (cancelled || settled) return;
        cancelled = true;
        fail(cancellationError());
      },
    };

    task.result = new Promise((resolve, reject) => {
      rejectResult = reject;
      for (let workerIndex = 0; workerIndex < actualWorkerCount; workerIndex++) {
        const worker = new Worker(workerScriptUrl);
        workers.push(worker);
        worker.onmessage = (event) => {
          if (settled) return;
          const data = event.data || {};
          if (data.jobId != null && data.jobId !== jobId) return;
          if (data.ok === false || data.type === 'error') {
            const error = new Error(data.message || 'Worker encoding failed');
            error.name = data.name || error.name;
            error.stack = data.stack || error.stack;
            fail(error);
            return;
          }
          if (data.type === 'search-progress') {
            reportProgress({
              phase: 'search',
              workerIndex: data.workerIndex,
              partitionOrder: data.partitionOrder,
              partitionType: data.partitionType,
              detail: data.detail,
            });
            return;
          }
          if (data.type === 'partition-result') {
            results.push(data.result);
            completedPartitions++;
            reportProgress({
              phase: 'partition',
              workerIndex: data.workerIndex,
              partitionOrder: data.partitionOrder,
              partitionType: data.partitionType,
            });
            return;
          }
          if (data.type === 'complete') {
            completedWorkers++;
            if (completedWorkers !== actualWorkerCount) return;
            try {
              const encoded = Codec.mergePartitionResults(results);
              settled = true;
              cleanup();
              resolve(encoded);
            } catch (error) {
              fail(error);
            }
          }
        };
        worker.onerror = (event) => {
          fail(new Error(event.message || 'Worker encoding failed'));
        };
        worker.postMessage({
          command: 'encodePartitions',
          codecScriptUrl,
          jobId,
          workerIndex,
          image,
          options: plan.options,
          partitions: queues[workerIndex],
        });
      }
    });

    if (signal && typeof signal.addEventListener === 'function') {
      if (signal.aborted) task.cancel();
      else signal.addEventListener('abort', onAbort, { once: true });
    }
    return task;
  }

  function startLegacyWorkerEncode(image, encodeOptions, codecScriptUrl, formatVersion) {
    const workerSource = `
      self.onmessage = function(event) {
        var data = event.data || {};
        try {
          importScripts(data.codecScriptUrl);
          var core = self.MCOImg;
          if (!core) throw new Error('Codec global was not created by worker script');
          var codec = new core.MCOImageCodec();
          var image = new core.MCOImage(data.image);
          var encoded = codec.encode(image, data.options || {});
          self.postMessage({ ok: true, encoded: encoded });
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
          reject(cancellationError());
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
      formatVersion,
      image: {
        width: image.width,
        height: image.height,
        paletteProfile: image.paletteProfile,
        pixels: image.pixels,
        transparentColor: image.transparentColor,
        encodingVersion: formatVersion,
      },
      options: encodeOptions,
    });
    return {
      result,
      formatVersion,
      workerCount: 1,
      get isCancelled() { return cancelled; },
      cancel() {
        if (cancelled || settled) return;
        cancelled = true;
        settled = true;
        worker.terminate();
        URL.revokeObjectURL(workerUrl);
        if (rejectResult) rejectResult(cancellationError());
      },
    };
  }

  function startCancellableEncode(imageLike, options = {}) {
    const formatVersion = normalizeFormatVersion(
      options.formatVersion ?? options.encodingVersion ?? imageLike.encodingVersion,
      MCOImageFormatVersion.v2,
    );
    const compressionLevel = normalizeCompressionLevel(options.compressionLevel, 0);
    const workerCount = Math.max(
      1,
      Math.min(8, Number(options.workerCount) || defaultWorkerCount()),
    );
    const requestedWorkers = shouldUseWorkers(formatVersion, compressionLevel, options);
    const workerAvailable = typeof Worker === 'function';
    const legacyWorkerAvailable = workerAvailable &&
      typeof Blob === 'function' &&
      typeof URL !== 'undefined' &&
      typeof URL.createObjectURL === 'function';
    const image = imageForFormat(imageLike, formatVersion);
    const encodeOptions = cloneableEncodeOptions(
      options,
      compressionLevel,
      workerCount,
      formatVersion,
    );

    if (!requestedWorkers || !workerAvailable ||
        (formatVersion !== MCOImageFormatVersion.v3 && !legacyWorkerAvailable)) {
      return startSynchronousEncode(image, options, encodeOptions, formatVersion);
    }

    const codecScriptUrl = options.codecScriptUrl ||
      (formatVersion === MCOImageFormatVersion.v3 ? options.v3CodecScriptUrl : null) ||
      findCodecScriptUrl(formatVersion);
    if (!codecScriptUrl) {
      throw new Error(
        `Could not locate the v${formatVersion} codec script for worker encoding`,
      );
    }

    if (formatVersion === MCOImageFormatVersion.v3) {
      return startV3PartitionedEncode(
        image,
        options,
        encodeOptions,
        codecScriptUrl,
        workerCount,
      );
    }
    return startLegacyWorkerEncode(image, encodeOptions, codecScriptUrl, formatVersion);
  }

  global.MCOImgBrowser = Object.freeze({
    MCOImageFormatVersion,
    MCOImagePayloadInputFormat,
    MCOImagePayloadOutputFormat,
    normalizeFormatVersion,
    normalizeCompressionLevel,
    inferTextFormatVersion,
    inferBinaryFormatVersion,
    codecFromOptions,
    canvasToImageData,
    canvasToRgbaInput,
    canvasToMCOImage,
    encodeCanvas,
    encodeCanvasUniversal,
    encodeImage,
    fileToCanvas,
    encodePngFile,
    pngBytesToBlob,
    drawPngBytesToCanvas,
    downloadBytes,
    decodePayload,
    payloadToBinary,
    payloadToText,
    inspectPayload,
    hasPngSignature,
    detectedInputFormat,
    convertPayload,
    textToPngBytes,
    binaryToPngBytes,
    drawTextPayloadToCanvas,
    drawBinaryPayloadToCanvas,
    ChannelBinaryDataFormat,
    parseMcoImageEnvelope,
    inspectMcoImageChannelPacket,
    extractMcoImagePayload,
    bytesToHex,
    findCodecScriptUrl,
    findV3WorkerScriptUrl,
    defaultWorkerCount,
    startCancellableEncode,
  });
})(typeof window !== 'undefined' ? window : globalThis);
