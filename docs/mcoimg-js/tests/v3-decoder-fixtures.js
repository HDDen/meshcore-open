'use strict';

const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = path.resolve(__dirname, '..');
const context = { console, Uint8Array, ArrayBuffer, TextDecoder, TextEncoder };
context.globalThis = context;
vm.createContext(context);
vm.runInContext(
  fs.readFileSync(path.join(root, 'mcoimg-v3-codec.global.js'), 'utf8'),
  context,
  { filename: 'mcoimg-v3-codec.global.js' },
);

const v3 = context.MCOImgV3;
const {
  PaletteProfile: P,
  ScanMode: S,
  MCOImageV3Container: C,
  MCOImageV3BlockAlgorithm: A,
  MCOImageV3Codec: Codec,
} = v3;

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function assertArray(actual, expected, label) {
  const a = Array.from(actual);
  const e = Array.from(expected);
  assert(a.length === e.length && a.every((value, index) => value === e[index]),
    `${label}: expected [${e}], got [${a}]`);
}

function bitLength(value) {
  if (value <= 0) return 0;
  return Math.floor(Math.log2(value)) + 1;
}

function paletteSize(profile) {
  return [2, 4, 8, 16, 32, 64, 16, 32, 8, 8, 16, 32, 64, 128, 256, 512][profile];
}

function globalBits(profile) {
  return bitLength(paletteSize(profile) - 1);
}

class BitWriter {
  constructor() {
    this.bytes = [];
    this.current = 0;
    this.bitOffset = 0;
  }

  writeBits(value, bits) {
    assert(Number.isInteger(value) && value >= 0, `invalid write value ${value}`);
    assert(Number.isInteger(bits) && bits >= 0 && bits <= 32, `invalid write bits ${bits}`);
    if (bits < 32) assert(value < 2 ** bits || bits === 0, `value ${value} does not fit ${bits} bits`);
    let remaining = bits;
    let sourceShift = 0;
    while (remaining > 0) {
      const take = Math.min(8 - this.bitOffset, remaining);
      const mask = (2 ** take) - 1;
      this.current |= ((Math.floor(value / (2 ** sourceShift)) & mask) << this.bitOffset);
      this.bitOffset += take;
      sourceShift += take;
      remaining -= take;
      if (this.bitOffset === 8) {
        this.bytes.push(this.current);
        this.current = 0;
        this.bitOffset = 0;
      }
    }
    return this;
  }

  writeAlignedByte(value) {
    assert(this.bitOffset === 0, 'aligned byte written at a non-byte boundary');
    this.bytes.push(value & 0xff);
    return this;
  }

  writeBitVarUint(value) {
    assert(Number.isInteger(value) && value >= 0, 'invalid varuint');
    do {
      let byte = value & 0x7f;
      value = Math.floor(value / 128);
      if (value > 0) byte |= 0x80;
      this.writeBits(byte, 8);
    } while (value > 0);
    return this;
  }

  writeCompactUint(value) {
    assert(Number.isInteger(value) && value >= 0, 'invalid compact uint');
    if (value < 4) return this.writeBits(0, 1).writeBits(value, 2);
    if (value < 20) return this.writeBits(1, 1).writeBits(0, 1).writeBits(value - 4, 4);
    if (value < 276) return this.writeBits(1, 1).writeBits(1, 1).writeBits(0, 1).writeBits(value - 20, 8);
    return this.writeBits(1, 1).writeBits(1, 1).writeBits(1, 1).writeBitVarUint(value);
  }

  writeRangeCompactUint(value, maxValue) {
    assert(value >= 0 && value <= maxValue, `range uint ${value}/${maxValue}`);
    if (maxValue <= 7) return this.writeBits(value, bitLength(maxValue));
    return this.writeCompactUint(value);
  }

  writeBoundedCompactUint(value, maxValue) {
    assert(value >= 0 && value <= maxValue, `bounded uint ${value}/${maxValue}`);
    if (maxValue <= 7) return this.writeBits(value, bitLength(maxValue));
    if (value < 4) return this.writeBits(0, 1).writeBits(value, 2);
    if (value < 20) return this.writeBits(1, 1).writeBits(0, 1).writeBits(value - 4, 4);
    if (value < 276) return this.writeBits(1, 1).writeBits(1, 1).writeBits(0, 1).writeBits(value - 20, 8);
    assert(maxValue >= 276, 'bounded escape with too-small max');
    return this.writeBits(1, 1).writeBits(1, 1).writeBits(1, 1)
      .writeBits(value - 276, bitLength(maxValue - 276));
  }

  finish() {
    if (this.bitOffset !== 0) this.bytes.push(this.current);
    return Uint8Array.from(this.bytes);
  }
}

function writeDimensions(w, width, height) {
  if (width === height && width <= 64) {
    w.writeBits(0, 2).writeBits(width - 1, 6);
  } else if (width <= 32 && height <= 32) {
    w.writeBits(1, 2).writeBits(width - 1, 5).writeBits(height - 1, 5);
  } else if (width <= 64 && height <= 64) {
    w.writeBits(2, 2).writeBits(width - 1, 6).writeBits(height - 1, 6);
  } else if (width === height) {
    w.writeBits(3, 2).writeBits(0, 1).writeBits(width - 1, 8);
  } else {
    w.writeBits(3, 2).writeBits(1, 1).writeBits(width - 1, 8).writeBits(height - 1, 8);
  }
}

function writeColorRef(w, profile, color) {
  // All fixture colors for dynamicGlobal512 are already profile refs; fixed
  // profile indexes are also their wire references.
  w.writeBits(color, globalBits(profile));
}

function writeFlatPalette(w, profile, colors) {
  const size = paletteSize(profile);
  const length = colors.length;
  if (size <= 64) {
    w.writeBits(0, 1).writeBits(length - 1, globalBits(profile));
  } else if (length <= 64) {
    w.writeBits(0, 1).writeBits(length - 1, 6);
  } else if (length <= 128) {
    w.writeBits(1, 1).writeBits(0, 1).writeBits(length - 65, 6);
  } else if (length <= 384) {
    w.writeBits(1, 1).writeBits(1, 1).writeBits(0, 1).writeBits(length - 129, 8);
  } else {
    w.writeBits(1, 1).writeBits(1, 1).writeBits(1, 1).writeBits(0, 1).writeBits(length - 385, 7);
  }
  for (const color of colors) writeColorRef(w, profile, color);
}

function writeDescriptorPrefix(w, profile, descriptor) {
  if (paletteSize(profile) <= 64) w.writeBits(1, 1);
  else w.writeBits(1, 1).writeBits(1, 1).writeBits(1, 1).writeBits(1, 1);
  w.writeBits(descriptor, 2);
}

function writeLocalPaletteLength(w, profile, length) {
  const size = paletteSize(profile);
  if (size <= 64) return w.writeBits(length - 1, globalBits(profile));
  if (length <= 64) return w.writeBits(0, 1).writeBits(length - 1, 6);
  if (length <= 128) return w.writeBits(1, 1).writeBits(0, 1).writeBits(length - 65, 6);
  return w.writeBits(1, 1).writeBits(1, 1).writeBits(length - 129, bitLength(size - 129));
}

function writeRawAdaptivePlane(w, bits) {
  w.writeBits(0, 1);
  for (const bit of bits) w.writeBits(bit, 1);
}

function buildBody({
  nonce = 0x7a,
  width,
  height,
  profile = P.master4,
  scan = S.h,
  container,
  context: containerContext = 0,
  transparentColor = null,
  implicitWhite = false,
  write,
}) {
  const w = new BitWriter();
  const header = (transparentColor == null ? 0 : 0x80) |
    (implicitWhite ? 0x40 : 0) |
    (scan << 4) |
    profile;
  w.writeAlignedByte(header);
  writeDimensions(w, width, height);
  w.writeBits((container << 5) | containerContext, 8);
  if (transparentColor != null) writeColorRef(w, profile, transparentColor);
  if (write) write(w);
  return Uint8Array.from([nonce, ...w.finish()]);
}

function decodeFixture(label, options, expectedPixels, extra = {}) {
  const body = buildBody(options);
  const codec = new Codec();
  const image = codec.decodeBody(body);
  assert(image.width === options.width && image.height === options.height, `${label}: dimensions`);
  assert(image.paletteProfile === (options.profile ?? P.master4), `${label}: profile`);
  assertArray(image.pixels, expectedPixels, `${label}: pixels`);
  assert(image.transparentColor === (options.transparentColor ?? null), `${label}: transparency`);

  const app = Uint8Array.from([Codec.subtypeVersion, ...body]);
  assertArray(codec.decodeAppPayloadWithoutSender(app).pixels, expectedPixels, `${label}: app decode`);
  assertArray(codec.decodeBytes(app).pixels, expectedPixels, `${label}: auto app decode`);
  assertArray(codec.decodeBytes(body).pixels, expectedPixels, `${label}: auto body decode`);

  const text = Codec.textFromBody(body);
  assert(text.startsWith('im3:'), `${label}: text prefix`);
  assertArray(Codec.bodyFromText(text), body, `${label}: text/body conversion`);
  assertArray(Codec.appPayloadWithoutSenderFromText(text), app, `${label}: text/app conversion`);
  assertArray(codec.decodeText(text).pixels, expectedPixels, `${label}: text decode`);

  const info = Codec.inspectBody(body);
  assert(info.version === 3 && info.width === options.width && info.height === options.height, `${label}: metadata`);
  assert(info.packetNonce === body[0], `${label}: metadata nonce`);
  if (extra.containerName) assert(info.containerName === extra.containerName, `${label}: container metadata`);
  if (extra.algorithmName) assert(info.blockAlgorithmName === extra.algorithmName, `${label}: algorithm metadata`);
  return { label, bytes: body.length, textChars: text.length, body, image, info };
}

const results = [];

// All 16 block algorithms.
results.push(decodeFixture('rawGlobal', {
  width: 4, height: 2, container: C.compactBlock, context: A.rawGlobal,
  write(w) { [0, 1, 2, 3, 3, 2, 1, 0].forEach((v) => writeColorRef(w, P.master4, v)); },
}, [0, 1, 2, 3, 3, 2, 1, 0], { algorithmName: 'rawGlobal' }));

results.push(decodeFixture('rawLocal', {
  width: 4, height: 2, container: C.compactBlock, context: A.rawLocal,
  write(w) { writeFlatPalette(w, P.master4, [0, 3]); [0, 1, 0, 1, 1, 0, 1, 0].forEach((v) => w.writeBits(v, 1)); },
}, [0, 3, 0, 3, 3, 0, 3, 0]));

results.push(decodeFixture('compactRle', {
  width: 4, height: 2, container: C.block, context: A.compactRle,
  write(w) {
    writeFlatPalette(w, P.master4, [0, 3]);
    const runs = [[0, 3], [1, 2], [0, 3]];
    let done = 0;
    for (const [index, length] of runs) {
      w.writeBits(index, 1).writeBoundedCompactUint(length - 1, 8 - done - 1);
      done += length;
    }
  },
}, [0, 0, 0, 3, 3, 0, 0, 0]));

results.push(decodeFixture('compactSparse', {
  width: 4, height: 2, container: C.block, context: A.compactSparse,
  write(w) {
    writeColorRef(w, P.master4, 0);
    writeFlatPalette(w, P.master4, [3]);
    w.writeBoundedCompactUint(1, 7); // two segments
    let pos = 0;
    w.writeBoundedCompactUint(1, 7).writeBits(0, 0).writeBoundedCompactUint(1, 6); pos = 3;
    w.writeBoundedCompactUint(2, 4).writeBits(0, 0).writeBoundedCompactUint(0, 2); pos = 6;
    void pos;
  },
}, [0, 3, 3, 0, 0, 3, 0, 0]));

results.push(decodeFixture('biColorMask', {
  width: 4, height: 2, container: C.compactBlock, context: A.biColorMask,
  write(w) {
    writeColorRef(w, P.master4, 0);
    writeColorRef(w, P.master4, 3);
    [0, 1, 0, 1, 1, 0, 1, 0].forEach((v) => w.writeBits(v, 1));
  },
}, [0, 3, 0, 3, 3, 0, 3, 0]));

results.push(decodeFixture('rowRepeat', {
  width: 4, height: 2, container: C.block, context: A.rowRepeat,
  write(w) {
    writeFlatPalette(w, P.master4, [0, 3]);
    [0, 1, 0, 1].forEach((v) => w.writeBits(v, 1));
    w.writeBits(1, 1);
  },
}, [0, 3, 0, 3, 0, 3, 0, 3]));

results.push(decodeFixture('lzPixels', {
  width: 4, height: 2, container: C.block, context: A.lzPixels,
  write(w) {
    writeFlatPalette(w, P.master4, [0, 3]);
    w.writeBits(0, 1).writeRangeCompactUint(1, 7).writeBits(0, 1).writeBits(1, 1);
    w.writeBits(1, 1).writeRangeCompactUint(1, 1).writeRangeCompactUint(3, 3);
  },
}, [0, 3, 0, 3, 0, 3, 0, 3]));

results.push(decodeFixture('quadtree', {
  width: 2, height: 2, container: C.block, context: A.quadtree,
  write(w) {
    writeFlatPalette(w, P.master4, [0, 3]);
    w.writeBits(0, 1);
    for (const index of [0, 1, 1, 0]) w.writeBits(1, 1).writeBits(index, 1);
  },
}, [0, 3, 3, 0]));

results.push(decodeFixture('bitplanesRawAndRle', {
  width: 4, height: 2, container: C.block, context: A.bitplanes,
  write(w) {
    writeFlatPalette(w, P.master4, [0, 1, 2, 3]);
    // bit 0 raw: 0,1,0,1,0,1,0,1
    w.writeBits(0, 1); [0, 1, 0, 1, 0, 1, 0, 1].forEach((v) => w.writeBits(v, 1));
    // bit 1 RLE: four zeros, four ones.
    w.writeBits(1, 1).writeBits(0, 1).writeRangeCompactUint(3, 7).writeRangeCompactUint(3, 3);
  },
}, [0, 1, 0, 1, 2, 3, 2, 3]));

results.push(decodeFixture('adaptiveBitplanesRaw', {
  width: 4, height: 2, container: C.block, context: A.adaptiveBitplanes,
  write(w) {
    writeFlatPalette(w, P.master4, [0, 3]);
    writeRawAdaptivePlane(w, [0, 1, 0, 1, 1, 0, 1, 0]);
  },
}, [0, 3, 0, 3, 3, 0, 3, 0]));

results.push(decodeFixture('directBitplanes', {
  width: 4, height: 2, profile: P.grayscale8, container: C.block, context: A.directBitplanes,
  write(w) {
    const values = [0, 1, 2, 3, 4, 5, 6, 7];
    for (let bit = 0; bit < 3; bit++) writeRawAdaptivePlane(w, values.map((v) => (v >> bit) & 1));
  },
}, [0, 1, 2, 3, 4, 5, 6, 7]));

results.push(decodeFixture('compactRowDelta', {
  width: 4, height: 2, container: C.block, context: A.compactRowDelta,
  write(w) {
    writeFlatPalette(w, P.master4, [0, 3]);
    w.writeBits(0, 1); [0, 1, 0, 1].forEach((v) => w.writeBits(v, 1));
    w.writeBits(0, 3);
  },
}, [0, 3, 0, 3, 0, 3, 0, 3]));

results.push(decodeFixture('directRowDelta', {
  width: 4, height: 2, profile: P.grayscale8, container: C.block, context: A.directRowDelta,
  write(w) {
    w.writeBits(0, 1); [0, 1, 2, 3].forEach((v) => w.writeBits(v, 3));
    w.writeBits(0, 3);
  },
}, [0, 1, 2, 3, 0, 1, 2, 3]));

results.push(decodeFixture('rowDelta', {
  width: 4, height: 2, container: C.block, context: A.rowDelta,
  write(w) {
    writeFlatPalette(w, P.master4, [0, 3]);
    w.writeBits(0, 1).writeBits(0, 1);
    [0, 1, 0, 1].forEach((v) => w.writeBits(v, 1));
    w.writeBits(1, 2);
  },
}, [0, 3, 0, 3, 0, 3, 0, 3]));

results.push(decodeFixture('varUintRle', {
  width: 4, height: 2, container: C.block, context: A.varUintRle,
  write(w) {
    writeFlatPalette(w, P.master4, [0, 3]);
    w.writeBits(0, 1).writeBitVarUint(3).writeBits(1, 1).writeBitVarUint(2).writeBits(0, 1).writeBitVarUint(3);
  },
}, [0, 0, 0, 3, 3, 0, 0, 0]));

results.push(decodeFixture('varUintSparse', {
  width: 4, height: 2, container: C.block, context: A.varUintSparse,
  write(w) {
    writeColorRef(w, P.master4, 0);
    writeFlatPalette(w, P.master4, [3]);
    w.writeBitVarUint(2);
    w.writeBitVarUint(1).writeBits(0, 0).writeBitVarUint(2);
    w.writeBitVarUint(2).writeBits(0, 0).writeBitVarUint(1);
  },
}, [0, 3, 3, 0, 0, 3, 0, 0]));

// Adaptive bitplane mode grammar beyond the raw mode.
function adaptiveModeFixture(name, pixels, writePlane) {
  results.push(decodeFixture(name, {
    width: 8, height: 1, container: C.block, context: A.adaptiveBitplanes,
    write(w) { writeFlatPalette(w, P.master4, [0, 3]); writePlane(w); },
  }, pixels.map((v) => v ? 3 : 0)));
}

adaptiveModeFixture('adaptiveLegacyRle', [0, 0, 0, 0, 1, 1, 1, 1], (w) => {
  w.writeBits(1, 1).writeBits(0, 1).writeBits(0, 1)
    .writeRangeCompactUint(3, 7).writeRangeCompactUint(3, 3);
});
adaptiveModeFixture('adaptiveShortRle', [0, 0, 1, 1, 1, 0, 0, 0], (w) => {
  w.writeBits(1, 1).writeBits(1, 1).writeBits(0, 1).writeBits(0, 1);
  // 2,3,3: short codes 10, 110, 110.
  w.writeBits(1, 1).writeBits(0, 1);
  w.writeBits(1, 1).writeBits(1, 1).writeBits(0, 1);
  w.writeBits(1, 1).writeBits(1, 1).writeBits(0, 1);
});
adaptiveModeFixture('adaptiveConstantZero', Array(8).fill(0), (w) => {
  w.writeBits(1, 1).writeBits(1, 1).writeBits(1, 1).writeBits(0, 2);
});
adaptiveModeFixture('adaptiveConstantOne', Array(8).fill(1), (w) => {
  w.writeBits(1, 1).writeBits(1, 1).writeBits(1, 1).writeBits(1, 2);
});
adaptiveModeFixture('adaptiveSparseOne', [0, 1, 0, 0, 0, 0, 1, 0], (w) => {
  w.writeBits(1, 1).writeBits(1, 1).writeBits(1, 1).writeBits(2, 2);
  w.writeRangeCompactUint(1, 7); // two positions
  w.writeRangeCompactUint(1, 6); // position 1
  w.writeRangeCompactUint(4, 4); // position 6
});
adaptiveModeFixture('adaptiveSparseZero', [1, 0, 1, 1, 1, 1, 0, 1], (w) => {
  w.writeBits(1, 1).writeBits(1, 1).writeBits(1, 1).writeBits(3, 2);
  w.writeRangeCompactUint(1, 7);
  w.writeRangeCompactUint(1, 6);
  w.writeRangeCompactUint(4, 4);
});

// The four non-region top-level containers.
results.push(decodeFixture('boundsBlock', {
  width: 4, height: 4, container: C.boundsBlock, context: A.compactRle,
  write(w) {
    writeColorRef(w, P.master4, 0);
    w.writeBits(1, 8).writeBits(1, 8).writeBits(1, 8).writeBits(1, 8);
    writeFlatPalette(w, P.master4, [3]);
    w.writeBits(0, 0).writeBoundedCompactUint(3, 3);
  },
}, [0, 0, 0, 0, 0, 3, 3, 0, 0, 3, 3, 0, 0, 0, 0, 0], { containerName: 'boundsBlock' }));

results.push(decodeFixture('compactBoundsBlock', {
  width: 4, height: 4, container: C.compactBoundsBlock, context: A.rawGlobal,
  write(w) {
    writeColorRef(w, P.master4, 0);
    w.writeBits(1, 2).writeBits(1, 2).writeBits(1, 2).writeBits(1, 2);
    [1, 2, 3, 1].forEach((v) => writeColorRef(w, P.master4, v));
  },
}, [0, 0, 0, 0, 0, 1, 2, 0, 0, 3, 1, 0, 0, 0, 0, 0], { containerName: 'compactBoundsBlock' }));

results.push(decodeFixture('regions', {
  width: 4, height: 4, container: C.regions, context: 0,
  write(w) {
    writeColorRef(w, P.master4, 0);
    w.writeBits(1, 8).writeBits(1, 8).writeBits(1, 8).writeBits(1, 8);
    w.writeBits(A.rawLocal, 5);
    writeFlatPalette(w, P.master4, [1, 3]);
    [0, 1, 1, 0].forEach((v) => w.writeBits(v, 1));
  },
}, [0, 0, 0, 0, 0, 1, 3, 0, 0, 3, 1, 0, 0, 0, 0, 0], { containerName: 'regions' }));

results.push(decodeFixture('compactRegionsSharedDelta', {
  width: 4, height: 2, container: C.compactRegionsStream, context: 1,
  write(w) {
    writeColorRef(w, P.master4, 0);
    w.writeBits(1, 1).writeBits(1, 1).writeBits(1, 1);
    w.writeBits(A.rawLocal, 5);
    writeFlatPalette(w, P.master4, [1, 3]);
    // First region (0,0,2,2).
    w.writeBits(0, 2).writeBits(0, 1).writeBits(1, 2).writeBits(1, 1);
    [0, 1, 1, 0].forEach((v) => w.writeBits(v, 1));
    // Delta to (2,0,2,2): +2,0,0,0.
    w.writeCompactUint(4).writeCompactUint(0).writeCompactUint(0).writeCompactUint(0);
    [1, 0, 0, 1].forEach((v) => w.writeBits(v, 1));
  },
}, [1, 3, 3, 1, 3, 1, 1, 3], { containerName: 'compactRegionsStream' }));

results.push(decodeFixture('solidBackground', {
  width: 1, height: 1, container: C.solidBackground, context: 2,
}, [2], { containerName: 'solidBackground' }));

results.push(decodeFixture('solidRects', {
  width: 4, height: 4, container: C.solidRects, context: 0,
  write(w) {
    writeColorRef(w, P.master4, 0);
    writeFlatPalette(w, P.master4, [3]);
    w.writeBits(0, 1);
    w.writeBits(1, 2).writeBits(1, 2).writeBits(1, 2).writeBits(1, 2).writeBits(0, 0);
  },
}, [0, 0, 0, 0, 0, 3, 3, 0, 0, 3, 3, 0, 0, 0, 0, 0], { containerName: 'solidRects' }));

// Header options and scan reordering.
results.push(decodeFixture('implicitWhiteSolid', {
  width: 2, height: 2, container: C.solidBackground, context: 0, implicitWhite: true,
}, [0, 0, 0, 0]));

results.push(decodeFixture('transparentSolid', {
  width: 2, height: 2, container: C.solidBackground, context: 2, transparentColor: 3,
}, [2, 2, 2, 2]));

for (const [name, scan, linear, expected] of [
  ['scanV', S.v, [0, 1, 2, 3, 0, 1], [0, 2, 0, 1, 3, 1]],
  ['scanS', S.s, [0, 1, 2, 3, 0, 1], [0, 1, 2, 1, 0, 3]],
  ['scanSV', S.sv, [0, 1, 2, 3, 0, 1], [0, 3, 0, 1, 2, 1]],
]) {
  results.push(decodeFixture(name, {
    width: 3, height: 2, scan, container: C.block, context: A.compactRle,
    write(w) {
      writeFlatPalette(w, P.master4, [0, 1, 2, 3]);
      let done = 0;
      for (const value of linear) {
        w.writeBits(value, 2).writeBoundedCompactUint(0, linear.length - done - 1);
        done++;
      }
    },
  }, expected));
}

// Every local-palette wire descriptor.
function rawLocalDescriptorFixture(name, profile, writePalette, localIndexes, expectedPalette) {
  results.push(decodeFixture(name, {
    width: localIndexes.length, height: 1, profile, container: C.compactBlock, context: A.rawLocal,
    write(w) {
      writePalette(w);
      const bits = bitLength(expectedPalette.length - 1);
      localIndexes.forEach((index) => w.writeBits(index, bits));
    },
  }, localIndexes.map((index) => expectedPalette[index])));
}

rawLocalDescriptorFixture('paletteBitmap', P.master4, (w) => {
  writeDescriptorPrefix(w, P.master4, 0);
  [1, 0, 0, 1].forEach((bit) => w.writeBits(bit, 1));
}, [0, 1, 1, 0], [0, 3]);

rawLocalDescriptorFixture('paletteSortedDelta', P.master8, (w) => {
  writeDescriptorPrefix(w, P.master8, 1);
  writeLocalPaletteLength(w, P.master8, 3);
  w.writeBits(0, 3).writeCompactUint(1).writeCompactUint(1); // refs 0,2,4
}, [0, 1, 2, 1], [0, 2, 4]);

rawLocalDescriptorFixture('paletteRangeRuns', P.master8, (w) => {
  writeDescriptorPrefix(w, P.master8, 2);
  w.writeRangeCompactUint(1, 7); // two runs
  w.writeBits(0, 3).writeCompactUint(1); // 0..1
  w.writeBits(5, 3).writeCompactUint(1); // 5..6
}, [0, 1, 2, 3], [0, 1, 5, 6]);

rawLocalDescriptorFixture('paletteBankBitmaps', P.dynamicGlobal512, (w) => {
  writeDescriptorPrefix(w, P.dynamicGlobal512, 3);
  w.writeBits(0, 1).writeBits(0b00000101, 8);
  for (let offset = 0; offset < 64; offset++) w.writeBits(offset === 1 ? 1 : 0, 1);
  for (let offset = 0; offset < 64; offset++) w.writeBits(offset === 2 ? 1 : 0, 1);
}, [0, 1, 0, 1], [1, 130]);

rawLocalDescriptorFixture('paletteOrderedSingleBank', P.dynamicGlobal512, (w) => {
  writeDescriptorPrefix(w, P.dynamicGlobal512, 3);
  w.writeBits(1, 1);
  writeLocalPaletteLength(w, P.dynamicGlobal512, 3);
  w.writeBits(0, 1).writeBits(3, 3);
  [1, 9, 17].forEach((offset) => w.writeBits(offset, 6));
}, [0, 1, 2, 1], [193, 201, 209]);

rawLocalDescriptorFixture('paletteOrderedMultiBank', P.dynamicGlobal512, (w) => {
  writeDescriptorPrefix(w, P.dynamicGlobal512, 3);
  w.writeBits(1, 1);
  writeLocalPaletteLength(w, P.dynamicGlobal512, 4);
  w.writeBits(1, 1).writeBits(0b00000101, 8);
  [[0, 1], [1, 2], [0, 3], [1, 4]].forEach(([bankIndex, offset]) => w.writeBits(bankIndex, 1).writeBits(offset, 6));
}, [0, 1, 2, 3], [1, 130, 3, 132]);

// Non-canonical and malformed payloads must fail rather than decode loosely.
const canonical = results[0].body;
for (const [name, mutate] of [
  ['wrong app subtype', () => Uint8Array.from([0x12, ...canonical])],
  ['trailing byte', () => Uint8Array.from([...canonical, 0])],
]) {
  let failed = false;
  try {
    if (name === 'wrong app subtype') new Codec().decodeAppPayloadWithoutSender(mutate());
    else new Codec().decodeBody(mutate());
  } catch (error) {
    failed = error instanceof v3.MCOImageV3CodecError;
  }
  assert(failed, `${name}: malformed payload was accepted`);
}

const refreshed = Codec.refreshPacketNonce(canonical, { nonce: 0x55 });
assert(refreshed[0] === 0x55, 'nonce refresh did not replace nonce');
assertArray(refreshed.slice(1), canonical.slice(1), 'nonce refresh changed compressed bytes');
assert(canonical[0] !== refreshed[0], 'nonce refresh mutated input');
assert(Codec.inspectText('im:not-v3') === null, 'inspectText accepted a non-v3 prefix');
assert(Codec.appDataType === 0x0120 && Codec.subtypeVersion === 0x13, 'v3 namespace constants');
assert(v3.capabilities.decode === true && v3.capabilities.encode === true, 'v3 capabilities');

const outputArgument = process.argv.find((argument) => argument.startsWith('--write='));
if (outputArgument) {
  const outputPath = path.resolve(outputArgument.slice('--write='.length));
  const fixtureDocument = {
    schema: 1,
    generator: 'docs/mcoimg-js/tests/v3-decoder-fixtures.js',
    fixtures: results.map((item) => ({
      name: item.label,
      bodyBase64: Buffer.from(item.body).toString('base64'),
      appPayloadBase64: Buffer.from(Uint8Array.from([Codec.subtypeVersion, ...item.body])).toString('base64'),
      text: Codec.textFromBody(item.body),
      width: item.image.width,
      height: item.image.height,
      paletteProfile: item.info.paletteProfileName,
      pixels: Array.from(item.image.pixels),
      transparentColor: item.image.transparentColor,
      container: item.info.containerName,
      algorithm: item.info.blockAlgorithmName,
    })),
  };
  fs.writeFileSync(outputPath, `${JSON.stringify(fixtureDocument, null, 2)}\n`);
}

const summary = {
  fixtures: results.length,
  blockAlgorithms: new Set(results.map((item) => item.info.blockAlgorithmName)).size,
  containers: new Set(results.map((item) => item.info.containerName)).size,
  totalBytes: results.reduce((sum, item) => sum + item.bytes, 0),
  maxBytes: Math.max(...results.map((item) => item.bytes)),
};
console.log(JSON.stringify(summary, null, 2));
