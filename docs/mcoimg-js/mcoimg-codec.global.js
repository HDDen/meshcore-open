(function(global) {
  'use strict';
// Vanilla browser-global port of the Flutter MCO image codec.
// Pixel arrays store palette indexes, not ARGB/RGB colors.
const PaletteProfile = Object.freeze({
  mono: 0,
  master4: 1,
  master8: 2,
  master16: 3,
  master32: 4,
  master64: 5,
  grayscale16: 6,
  grayscale32: 7,
  grayscale8: 8,
});

const PaletteProfileName = Object.freeze([
  'mono',
  'master4',
  'master8',
  'master16',
  'master32',
  'master64',
  'grayscale16',
  'grayscale32',
  'grayscale8',
]);

const PaletteDisplayOrder = Object.freeze([
  PaletteProfile.mono,
  PaletteProfile.grayscale8,
  PaletteProfile.grayscale16,
  PaletteProfile.grayscale32,
  PaletteProfile.master4,
  PaletteProfile.master8,
  PaletteProfile.master16,
  PaletteProfile.master32,
  PaletteProfile.master64,
]);

const PaletteDisplayName = Object.freeze({
  [PaletteProfile.mono]: 'Mono',
  [PaletteProfile.grayscale8]: 'Grayscale 8',
  [PaletteProfile.grayscale16]: 'Grayscale 16',
  [PaletteProfile.grayscale32]: 'Grayscale 32',
  [PaletteProfile.master4]: 'Master 4',
  [PaletteProfile.master8]: 'Master 8',
  [PaletteProfile.master16]: 'Master 16',
  [PaletteProfile.master32]: 'Master 32',
  [PaletteProfile.master64]: 'Master 64',
});

const ImageMode = Object.freeze({
  rawGlobal: 0,
  rawLocal: 1,
  rleLocal: 2,
  sparseBg: 3,
});

const ImageModeName = Object.freeze([
  'rawGlobal',
  'rawLocal',
  'rleLocal',
  'sparseBg',
]);

const ScanMode = Object.freeze({
  h: 0,
  v: 1,
  s: 2,
  sv: 3,
});

const ScanModeName = Object.freeze(['h', 'v', 's', 'sv']);

const MCOImagePalettes = Object.freeze({
  [PaletteProfile.mono]: Object.freeze([0xffffffff, 0xff000000]),
  [PaletteProfile.master4]: Object.freeze([
    0xffffffff, 0xffc0c0c0, 0xff565656, 0xff000000,
  ]),
  [PaletteProfile.master8]: Object.freeze([
    0xffffffff, 0xff8d8d8d, 0xff000000, 0xfffe2400,
    0xfff1d100, 0xff47c000, 0xff3d69ff, 0xff7900ff,
  ]),
  [PaletteProfile.master16]: Object.freeze([
    0xffffffff, 0xffa4a4a4, 0xff000000, 0xffd11e01,
    0xff620e01, 0xffff8400, 0xff7b4000, 0xfff1d100,
    0xff907c02, 0xff41b000, 0xff286e00, 0xff7fdcff,
    0xff003aff, 0xff002296, 0xff6a00e3, 0xff2f0064,
  ]),
  [PaletteProfile.master32]: Object.freeze([
    0xffffffff, 0xffb3b3b3, 0xff666666, 0xff000000,
    0xffffb0a3, 0xffff5541, 0xfffe2400, 0xff620e01,
    0xffffb363, 0xffff8400, 0xffc56601, 0xff8e4900,
    0xfff5de5b, 0xfff1d100, 0xffb59d02, 0xff786902,
    0xff95da76, 0xff47c000, 0xff286e00, 0xff1d4f00,
    0xffc4f1ff, 0xff01c3ff, 0xff038db8, 0xff016d8f,
    0xff7596ff, 0xff003aff, 0xff022eca, 0xff002296,
    0xffd7b2ff, 0xffb287ff, 0xff853dff, 0xff2f0064,
  ]),
  [PaletteProfile.master64]: Object.freeze([
    0xffffffff, 0xffd9d9d9, 0xffb3b3b3, 0xff8a8b8a,
    0xff6f6f6f, 0xff4f4f4f, 0xff242424, 0xff000000,
    0xffffb0a3, 0xffff9a89, 0xffff5541, 0xfffe2400,
    0xffd11e01, 0xff911500, 0xff620e01, 0xff450a00,
    0xffffb363, 0xffffa855, 0xffff9333, 0xffff8400,
    0xffe47601, 0xffc56601, 0xff8e4900, 0xff7b4000,
    0xfff7e572, 0xfff5de5b, 0xfff1d100, 0xffdfc102,
    0xffcbb101, 0xffb59d02, 0xff907c02, 0xff786902,
    0xffb7e69b, 0xff95da76, 0xff6dcd4b, 0xff47c000,
    0xff41b000, 0xff369401, 0xff286e00, 0xff1d4f00,
    0xffc4f1ff, 0xffabe9ff, 0xff7fdcff, 0xff01c3ff,
    0xff00b6ee, 0xff01aadf, 0xff038db8, 0xff016d8f,
    0xff91aaff, 0xff7596ff, 0xff3b64ff, 0xff003aff,
    0xff0233e1, 0xff022eca, 0xff022eca, 0xff002296,
    0xffd7b2ff, 0xffb287ff, 0xff9a65ff, 0xff853dff,
    0xff7900ff, 0xff6902dd, 0xff5301af, 0xff2f0064,
  ]),
  [PaletteProfile.grayscale8]: Object.freeze([
    0xffffffff, 0xffdbdbdb, 0xffb6b6b6, 0xff919191,
    0xff6d6d6d, 0xff484848, 0xff242424, 0xff000000,
  ]),
  [PaletteProfile.grayscale16]: Object.freeze([
    0xffffffff, 0xffeeeeee, 0xffdddddd, 0xffcccccc,
    0xffbbbbbb, 0xffaaaaaa, 0xff999999, 0xff888888,
    0xff777777, 0xff666666, 0xff555555, 0xff444444,
    0xff333333, 0xff222222, 0xff111111, 0xff000000,
  ]),
  [PaletteProfile.grayscale32]: Object.freeze([
    0xffffffff, 0xfff7f7f7, 0xffefefef, 0xffe6e6e6,
    0xffdedede, 0xffd6d6d6, 0xffcecece, 0xffc5c5c5,
    0xffbdbdbd, 0xffb5b5b5, 0xffadadad, 0xffa5a5a5,
    0xff9c9c9c, 0xff949494, 0xff8c8c8c, 0xff848484,
    0xff7b7b7b, 0xff737373, 0xff6b6b6b, 0xff636363,
    0xff5a5a5a, 0xff525252, 0xff4a4a4a, 0xff424242,
    0xff393939, 0xff313131, 0xff292929, 0xff212121,
    0xff181818, 0xff101010, 0xff080808, 0xff000000,
  ]),
});

class MCOImageCodecError extends Error {}
class MCOImageInvalidInputError extends MCOImageCodecError {}
class MCOImageInvalidPayloadError extends MCOImageCodecError {}
class MCOImageTooLargeError extends MCOImageCodecError {}

class MCOImage {
  constructor({ width, height, paletteProfile = PaletteProfile.master32, pixels }) {
    this.width = width;
    this.height = height;
    this.paletteProfile = normalizePaletteProfile(paletteProfile);
    this.pixels = Array.from(pixels);
  }
}

class MCOImageCodec {
  static prefix = 'im:';
  static version = 0;
  static minSize = 1;
  static maxSize = 85;
  static modeTieOrder = Object.freeze([
    ImageMode.sparseBg,
    ImageMode.rleLocal,
    ImageMode.rawLocal,
    ImageMode.rawGlobal,
  ]);

  encode(imageLike, options = {}) {
    const image = imageLike instanceof MCOImage
      ? imageLike
      : new MCOImage(imageLike);
    const maxChars = options.maxChars;
    const backgroundColor = options.backgroundColor;
    validateImage(image);
    if (backgroundColor !== undefined) {
      validateColor(backgroundColor, image.paletteProfile, 'backgroundColor');
    }

    let best = null;
    for (const scan of Object.values(ScanMode)) {
      const linear = toScanOrder(image.pixels, image.width, image.height, scan);
      for (const mode of Object.values(ImageMode)) {
        const payload = this._buildPayload(image, linear, mode, scan, {
          backgroundColor,
        });
        const text = `${MCOImageCodec.prefix}${base91Encode(payload)}`;
        const candidate = {
          text,
          mode,
          modeName: ImageModeName[mode],
          scan,
          scanName: ScanModeName[scan],
          byteLength: payload.length,
          charLength: text.length,
        };
        if (isBetterCandidate(candidate, best)) best = candidate;
      }
    }

    if (maxChars !== undefined && best.charLength > maxChars) {
      throw new MCOImageTooLargeError(
        `Encoded image is ${best.charLength} chars, max is ${maxChars}`,
      );
    }
    return best;
  }

  decode(text) {
    if (!text.startsWith(MCOImageCodec.prefix)) {
      throw new MCOImageInvalidPayloadError('Missing im: prefix');
    }

    const bytes = base91Decode(text.slice(MCOImageCodec.prefix.length));
    if (bytes.length < 4) {
      throw new MCOImageInvalidPayloadError('Payload too short');
    }

    const header = bytes[0];
    const version = (header >> 6) & 0x03;
    if (version !== MCOImageCodec.version) {
      throw new MCOImageInvalidPayloadError(`Unsupported version ${version}`);
    }

    const mode = modeFromBits((header >> 4) & 0x03);
    const scan = scanFromBits((header >> 2) & 0x03);
    const bgPresent = ((header >> 1) & 0x01) !== 0;
    if ((header & 0x01) !== 0) {
      throw new MCOImageInvalidPayloadError('Reserved header bit is set');
    }

    const profileHeader = bytes[1];
    const paletteProfile = profileFromBits((profileHeader >> 4) & 0x0f);
    if ((profileHeader & 0x0f) !== 0) {
      throw new MCOImageInvalidPayloadError('Reserved palette bits are set');
    }
    if (bgPresent !== (mode === ImageMode.sparseBg)) {
      throw new MCOImageInvalidPayloadError(
        'Background flag does not match mode',
      );
    }

    const width = bytes[2] + 1;
    const height = bytes[3] + 1;
    validateDimensions(width, height, true);

    const reader = new BitReader(bytes, 4);
    const linear = this._decodeByMode(reader, mode, width, height, paletteProfile);
    reader.finish();

    return new MCOImage({
      width,
      height,
      paletteProfile,
      pixels: fromScanOrder(linear, width, height, scan),
    });
  }

  _buildPayload(image, linear, mode, scan, { backgroundColor } = {}) {
    const writer = new BitWriter();
    const bgPresent = mode === ImageMode.sparseBg;
    writer.writeAlignedByte(
      (MCOImageCodec.version << 6) |
        (modeBits(mode) << 4) |
        (scanBits(scan) << 2) |
        (bgPresent ? 0x02 : 0),
    );
    writer.writeAlignedByte(profileBits(image.paletteProfile) << 4);
    writer.writeAlignedByte(image.width - 1);
    writer.writeAlignedByte(image.height - 1);

    switch (mode) {
      case ImageMode.rawGlobal:
        encodeRawGlobal(writer, linear, image.paletteProfile);
        break;
      case ImageMode.rawLocal:
        encodeRawLocal(writer, linear, image.paletteProfile);
        break;
      case ImageMode.rleLocal:
        encodeRleLocal(writer, linear, image.paletteProfile);
        break;
      case ImageMode.sparseBg:
        encodeSparseBg(writer, linear, image.paletteProfile, backgroundColor);
        break;
      default:
        throw new MCOImageInvalidInputError('Unknown image mode');
    }
    return writer.toBytes();
  }

  _decodeByMode(reader, mode, width, height, paletteProfile) {
    switch (mode) {
      case ImageMode.rawGlobal:
        return decodeRawGlobal(reader, width, height, paletteProfile);
      case ImageMode.rawLocal:
        return decodeRawLocal(reader, width, height, paletteProfile);
      case ImageMode.rleLocal:
        return decodeRleLocal(reader, width, height, paletteProfile);
      case ImageMode.sparseBg:
        return decodeSparseBg(reader, width, height, paletteProfile);
      default:
        throw new MCOImageInvalidPayloadError('Unknown image mode');
    }
  }
}

function encodeRawGlobal(writer, linear, profile) {
  const bits = globalBits(profile);
  for (const pixel of linear) writer.writeBits(pixel, bits);
}

function decodeRawGlobal(reader, width, height, profile) {
  const bits = globalBits(profile);
  return Array.from({ length: width * height }, () => reader.readBits(bits));
}

function encodeRawLocal(writer, linear, profile) {
  const local = buildLocalPalette(linear);
  const map = localIndexMap(local);
  const localBits = bitsForLocalPalette(local.length);
  writer.writeVarUint(local.length);
  writePalette(writer, local, profile);
  for (const pixel of linear) writer.writeBits(map.get(pixel), localBits);
}

function decodeRawLocal(reader, width, height, profile) {
  const count = width * height;
  const palette = readLocalPalette(reader, profile);
  const localBits = bitsForLocalPalette(palette.length);
  return Array.from({ length: count }, () => {
    const index = reader.readBits(localBits);
    if (index >= palette.length) {
      throw new MCOImageInvalidPayloadError('Local color index out of range');
    }
    return palette[index];
  });
}

function encodeRleLocal(writer, linear, profile) {
  const local = buildLocalPalette(linear);
  const map = localIndexMap(local);
  const localBits = bitsForLocalPalette(local.length);
  const runs = buildRuns(linear);
  writer.writeVarUint(local.length);
  writePalette(writer, local, profile);
  writer.writeVarUint(runs.length);
  for (const run of runs) {
    writer.writeBits(map.get(run.color), localBits);
    writer.writeVarUint(run.length);
  }
}

function decodeRleLocal(reader, width, height, profile) {
  const count = width * height;
  const palette = readLocalPalette(reader, profile);
  const localBits = bitsForLocalPalette(palette.length);
  const runCount = reader.readVarUint();
  const result = [];
  for (let i = 0; i < runCount; i++) {
    const index = reader.readBits(localBits);
    if (index >= palette.length) {
      throw new MCOImageInvalidPayloadError('RLE local color index out of range');
    }
    const length = reader.readVarUint();
    if (length <= 0 || result.length + length > count) {
      throw new MCOImageInvalidPayloadError('Invalid RLE length');
    }
    for (let j = 0; j < length; j++) result.push(palette[index]);
  }
  if (result.length !== count) {
    throw new MCOImageInvalidPayloadError('RLE data does not fill canvas');
  }
  return result;
}

function encodeSparseBg(writer, linear, profile, backgroundColor) {
  const bg = backgroundColor ?? mostFrequentColor(linear);
  writer.writeBits(bg, globalBits(profile));

  const nonBgColors = linear.filter((p) => p !== bg);
  const local = buildLocalPalette(nonBgColors);
  const map = localIndexMap(local);
  const localBits = bitsForLocalPalette(local.length);
  const segments = buildSparseSegments(linear, bg);

  writer.writeVarUint(local.length);
  writePalette(writer, local, profile);
  writer.writeVarUint(segments.length);
  let pos = 0;
  for (const segment of segments) {
    writer.writeVarUint(segment.start - pos);
    writer.writeBits(map.get(segment.color), localBits);
    writer.writeVarUint(segment.length);
    pos = segment.start + segment.length;
  }
}

function decodeSparseBg(reader, width, height, profile) {
  const count = width * height;
  const bg = reader.readBits(globalBits(profile));
  validateColor(bg, profile, 'backgroundColor', true);
  const palette = readLocalPalette(reader, profile, {
    excludedColor: bg,
    allowEmpty: true,
  });
  const localBits = bitsForLocalPalette(palette.length);
  const segmentCount = reader.readVarUint();
  const result = Array(count).fill(bg);
  let pos = 0;
  for (let i = 0; i < segmentCount; i++) {
    pos += reader.readVarUint();
    const index = reader.readBits(localBits);
    if (index >= palette.length) {
      throw new MCOImageInvalidPayloadError('Sparse local color index out of range');
    }
    const length = reader.readVarUint();
    if (length <= 0 || pos + length > count) {
      throw new MCOImageInvalidPayloadError('Invalid sparse segment');
    }
    for (let j = 0; j < length; j++) result[pos + j] = palette[index];
    pos += length;
  }
  return result;
}

function writePalette(writer, colors, profile) {
  const bits = globalBits(profile);
  for (const color of colors) writer.writeBits(color, bits);
}

function readLocalPalette(reader, profile, options = {}) {
  const { excludedColor, allowEmpty = false } = options;
  const k = reader.readVarUint();
  const maxColors = paletteSize(profile);
  if ((!allowEmpty && k === 0) || k > maxColors) {
    throw new MCOImageInvalidPayloadError('Invalid local palette size');
  }
  const bits = globalBits(profile);
  const colors = [];
  const seen = new Set();
  for (let i = 0; i < k; i++) {
    const color = reader.readBits(bits);
    validateColor(color, profile, 'localPalette', true);
    if (color === excludedColor || seen.has(color)) {
      throw new MCOImageInvalidPayloadError('Invalid local palette');
    }
    seen.add(color);
    colors.push(color);
  }
  return colors;
}

function isBetterCandidate(candidate, current) {
  if (current == null) return true;
  if (candidate.charLength !== current.charLength) {
    return candidate.charLength < current.charLength;
  }
  const candidateRank = MCOImageCodec.modeTieOrder.indexOf(candidate.mode);
  const currentRank = MCOImageCodec.modeTieOrder.indexOf(current.mode);
  if (candidateRank !== currentRank) return candidateRank < currentRank;
  return candidate.scan < current.scan;
}

function toScanOrder(pixels, width, height, scan) {
  return scanPositions(width, height, scan).map((i) => pixels[i]);
}

function fromScanOrder(linear, width, height, scan) {
  const result = Array(width * height).fill(0);
  const positions = scanPositions(width, height, scan);
  for (let i = 0; i < linear.length; i++) result[positions[i]] = linear[i];
  return result;
}

function scanPositions(width, height, scan) {
  const positions = [];
  switch (scan) {
    case ScanMode.h:
      for (let y = 0; y < height; y++) {
        for (let x = 0; x < width; x++) positions.push(y * width + x);
      }
      break;
    case ScanMode.v:
      for (let x = 0; x < width; x++) {
        for (let y = 0; y < height; y++) positions.push(y * width + x);
      }
      break;
    case ScanMode.s:
      for (let y = 0; y < height; y++) {
        if (y % 2 === 0) {
          for (let x = 0; x < width; x++) positions.push(y * width + x);
        } else {
          for (let x = width - 1; x >= 0; x--) positions.push(y * width + x);
        }
      }
      break;
    case ScanMode.sv:
      for (let x = 0; x < width; x++) {
        if (x % 2 === 0) {
          for (let y = 0; y < height; y++) positions.push(y * width + x);
        } else {
          for (let y = height - 1; y >= 0; y--) positions.push(y * width + x);
        }
      }
      break;
    default:
      throw new MCOImageInvalidInputError('Unknown scan mode');
  }
  return positions;
}

function buildLocalPalette(pixels) {
  const counts = new Map();
  for (const pixel of pixels) counts.set(pixel, (counts.get(pixel) ?? 0) + 1);
  return Array.from(counts.keys()).sort((a, b) => {
    const byFrequency = counts.get(b) - counts.get(a);
    return byFrequency !== 0 ? byFrequency : a - b;
  });
}

function localIndexMap(colors) {
  return new Map(colors.map((color, index) => [color, index]));
}

function buildRuns(pixels) {
  const runs = [];
  if (pixels.length === 0) return runs;
  let color = pixels[0];
  let length = 1;
  for (let i = 1; i < pixels.length; i++) {
    if (pixels[i] === color) {
      length++;
    } else {
      runs.push({ color, length });
      color = pixels[i];
      length = 1;
    }
  }
  runs.push({ color, length });
  return runs;
}

function buildSparseSegments(pixels, background) {
  const segments = [];
  let i = 0;
  while (i < pixels.length) {
    if (pixels[i] === background) {
      i++;
      continue;
    }
    const start = i;
    const color = pixels[i];
    let length = 0;
    while (i < pixels.length && pixels[i] === color) {
      length++;
      i++;
    }
    segments.push({ start, color, length });
  }
  return segments;
}

function mostFrequentColor(pixels) {
  const counts = new Map();
  for (const pixel of pixels) counts.set(pixel, (counts.get(pixel) ?? 0) + 1);
  let bestKey = pixels[0];
  let bestCount = -1;
  for (const [key, count] of counts.entries()) {
    if (count > bestCount || (count === bestCount && key < bestKey)) {
      bestKey = key;
      bestCount = count;
    }
  }
  return bestKey;
}

function bitsForLocalPalette(colorCount) {
  if (colorCount <= 1) return 1;
  return Math.ceil(Math.log2(colorCount));
}

function globalBits(profile) {
  switch (normalizePaletteProfile(profile)) {
    case PaletteProfile.mono:
      return 1;
    case PaletteProfile.master4:
      return 2;
    case PaletteProfile.master8:
    case PaletteProfile.grayscale8:
      return 3;
    case PaletteProfile.master16:
    case PaletteProfile.grayscale16:
      return 4;
    case PaletteProfile.master32:
    case PaletteProfile.grayscale32:
      return 5;
    case PaletteProfile.master64:
      return 6;
    default:
      throw new MCOImageInvalidInputError('Unknown palette profile');
  }
}

function paletteSize(profile) {
  return getPalette(profile).length;
}

function getPalette(profile) {
  const normalized = normalizePaletteProfile(profile);
  const palette = MCOImagePalettes[normalized];
  if (!palette) throw new MCOImageInvalidInputError('Unknown palette profile');
  return palette;
}

function whiteIndexFor(profile) {
  return 0;
}

function blackIndexFor(profile) {
  switch (normalizePaletteProfile(profile)) {
    case PaletteProfile.mono:
    case PaletteProfile.master8:
      return 1;
    case PaletteProfile.master4:
    case PaletteProfile.master16:
    case PaletteProfile.master32:
      return 3;
    case PaletteProfile.grayscale8:
      return 7;
    case PaletteProfile.grayscale16:
      return 15;
    case PaletteProfile.grayscale32:
      return 31;
    case PaletteProfile.master64:
      return 7;
    default:
      throw new MCOImageInvalidInputError('Unknown palette profile');
  }
}

function normalizePaletteProfile(profile) {
  if (typeof profile === 'number') return profile;
  if (typeof profile === 'string') {
    if (Object.prototype.hasOwnProperty.call(PaletteProfile, profile)) {
      return PaletteProfile[profile];
    }
    const index = PaletteProfileName.indexOf(profile);
    if (index >= 0) return index;
  }
  throw new MCOImageInvalidInputError(`Unknown palette profile ${profile}`);
}

function modeBits(mode) {
  return mode;
}

function scanBits(scan) {
  return scan;
}

function profileBits(profile) {
  return normalizePaletteProfile(profile);
}

function modeFromBits(value) {
  if (value < 0 || value >= ImageModeName.length) {
    throw new MCOImageInvalidPayloadError(`Unknown image mode ${value}`);
  }
  return value;
}

function scanFromBits(value) {
  if (value < 0 || value >= ScanModeName.length) {
    throw new MCOImageInvalidPayloadError(`Unknown scan mode ${value}`);
  }
  return value;
}

function profileFromBits(value) {
  if (value < 0 || value >= PaletteProfileName.length || value > 0x0f) {
    throw new MCOImageInvalidPayloadError(`Unknown palette profile ${value}`);
  }
  return value;
}

function validateImage(image) {
  validateDimensions(image.width, image.height);
  const expected = image.width * image.height;
  if (image.pixels.length !== expected) {
    throw new MCOImageInvalidInputError(
      `pixels.length must be ${expected}, got ${image.pixels.length}`,
    );
  }
  for (const pixel of image.pixels) {
    validateColor(pixel, image.paletteProfile, 'pixel');
  }
}

function validateDimensions(width, height, payload = false) {
  const ok =
    Number.isInteger(width) &&
    Number.isInteger(height) &&
    width >= MCOImageCodec.minSize &&
    height >= MCOImageCodec.minSize &&
    width <= MCOImageCodec.maxSize &&
    height <= MCOImageCodec.maxSize;
  if (ok) return;
  const message =
    `Image size must be ${MCOImageCodec.minSize}..${MCOImageCodec.maxSize} in both axes`;
  if (payload) throw new MCOImageInvalidPayloadError(message);
  throw new MCOImageInvalidInputError(message);
}

function validateColor(color, profile, label, payload = false) {
  const max = paletteSize(profile) - 1;
  const ok = Number.isInteger(color) && color >= 0 && color <= max;
  if (ok) return;
  const message = `${label} color must be 0..${max}, got ${color}`;
  if (payload) throw new MCOImageInvalidPayloadError(message);
  throw new MCOImageInvalidInputError(message);
}

class BitWriter {
  constructor() {
    this.bytes = [];
    this.bitOffset = 0;
  }

  writeAlignedByte(value) {
    this.alignToByte();
    this.bytes.push(value & 0xff);
  }

  writeBits(value, bitCount) {
    if (bitCount < 0) throw new MCOImageInvalidInputError('Negative bit count');
    let remaining = bitCount;
    let source = value;
    while (remaining > 0) {
      if (this.bitOffset === 0) this.bytes.push(0);
      const available = 8 - this.bitOffset;
      const take = Math.min(remaining, available);
      const mask = (1 << take) - 1;
      this.bytes[this.bytes.length - 1] |= (source & mask) << this.bitOffset;
      source >>= take;
      this.bitOffset = (this.bitOffset + take) & 7;
      remaining -= take;
    }
  }

  writeVarUint(value) {
    if (value < 0) throw new MCOImageInvalidInputError('Negative varuint');
    this.alignToByte();
    let current = value;
    do {
      let byte = current & 0x7f;
      current >>= 7;
      if (current !== 0) byte |= 0x80;
      this.bytes.push(byte);
    } while (current !== 0);
  }

  alignToByte() {
    if (this.bitOffset !== 0) this.bitOffset = 0;
  }

  toBytes() {
    this.alignToByte();
    return Uint8Array.from(this.bytes);
  }
}

class BitReader {
  constructor(bytes, byteIndex = 0) {
    this.bytes = bytes;
    this.byteIndex = byteIndex;
    this.bitOffset = 0;
  }

  readBits(bitCount) {
    if (bitCount < 0) {
      throw new MCOImageInvalidPayloadError('Negative bit count');
    }
    let result = 0;
    let shift = 0;
    let remaining = bitCount;
    while (remaining > 0) {
      if (this.byteIndex >= this.bytes.length) {
        throw new MCOImageInvalidPayloadError('Unexpected end of bits');
      }
      const available = 8 - this.bitOffset;
      const take = Math.min(remaining, available);
      const mask = (1 << take) - 1;
      result |= ((this.bytes[this.byteIndex] >> this.bitOffset) & mask) << shift;
      this.bitOffset += take;
      if (this.bitOffset === 8) {
        this.bitOffset = 0;
        this.byteIndex++;
      }
      shift += take;
      remaining -= take;
    }
    return result;
  }

  readVarUint(maxBytes = 5) {
    this.alignToByte();
    let result = 0;
    let shift = 0;
    for (let i = 0; i < maxBytes; i++) {
      if (this.byteIndex >= this.bytes.length) {
        throw new MCOImageInvalidPayloadError('Unexpected end of varuint');
      }
      const byte = this.bytes[this.byteIndex++];
      result |= (byte & 0x7f) << shift;
      if ((byte & 0x80) === 0) return result;
      shift += 7;
    }
    throw new MCOImageInvalidPayloadError('Varuint is too long');
  }

  alignToByte() {
    if (this.bitOffset !== 0) {
      if (this.byteIndex >= this.bytes.length) {
        throw new MCOImageInvalidPayloadError('Unexpected end of padding');
      }
      const unusedMask = (0xff << this.bitOffset) & 0xff;
      if ((this.bytes[this.byteIndex] & unusedMask) !== 0) {
        throw new MCOImageInvalidPayloadError('Non-zero padding bits');
      }
      this.byteIndex++;
      this.bitOffset = 0;
    }
  }

  finish() {
    if (this.bitOffset !== 0) {
      const unusedMask = (0xff << this.bitOffset) & 0xff;
      if ((this.bytes[this.byteIndex] & unusedMask) !== 0) {
        throw new MCOImageInvalidPayloadError('Non-zero padding bits');
      }
      this.byteIndex++;
      this.bitOffset = 0;
    }
    if (this.byteIndex !== this.bytes.length) {
      throw new MCOImageInvalidPayloadError('Trailing payload bytes');
    }
  }
}

const BASE91_ALPHABET =
  'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789' +
  '!#$%&()*+,./:;<=>?@[]^_`{|}~"';

const BASE91_DECODE = new Map(
  Array.from(BASE91_ALPHABET).map((char, index) => [char.charCodeAt(0), index]),
);

function base91Encode(bytes) {
  let output = '';
  let queue = 0;
  let bitCount = 0;
  for (const byte of bytes) {
    queue |= byte << bitCount;
    bitCount += 8;
    if (bitCount > 13) {
      let value = queue & 8191;
      if (value > 88) {
        queue >>= 13;
        bitCount -= 13;
      } else {
        value = queue & 16383;
        queue >>= 14;
        bitCount -= 14;
      }
      output += BASE91_ALPHABET[value % 91];
      output += BASE91_ALPHABET[Math.floor(value / 91)];
    }
  }
  if (bitCount > 0) {
    output += BASE91_ALPHABET[queue % 91];
    if (bitCount > 7 || queue > 90) {
      output += BASE91_ALPHABET[Math.floor(queue / 91)];
    }
  }
  return output;
}

function base91Decode(text) {
  const output = [];
  let value = -1;
  let queue = 0;
  let bitCount = 0;
  for (let i = 0; i < text.length; i++) {
    const decoded = BASE91_DECODE.get(text.charCodeAt(i));
    if (decoded == null) {
      throw new MCOImageInvalidPayloadError('Invalid basE91 character');
    }
    if (value < 0) {
      value = decoded;
    } else {
      value += decoded * 91;
      queue |= value << bitCount;
      bitCount += (value & 8191) > 88 ? 13 : 14;
      while (bitCount > 7) {
        output.push(queue & 0xff);
        queue >>= 8;
        bitCount -= 8;
      }
      value = -1;
    }
  }
  if (value >= 0) output.push((queue | (value << bitCount)) & 0xff);
  return Uint8Array.from(output);
}

function argbToCss(argb) {
  const rgb = argb & 0x00ffffff;
  return `#${rgb.toString(16).padStart(6, '0')}`;
}

function drawMCOImage(canvas, image, options = {}) {
  const scale = options.scale ?? 12;
  canvas.width = image.width * scale;
  canvas.height = image.height * scale;
  const ctx = canvas.getContext('2d');
  ctx.imageSmoothingEnabled = false;
  const palette = getPalette(image.paletteProfile);
  for (let y = 0; y < image.height; y++) {
    for (let x = 0; x < image.width; x++) {
      const colorIndex = Math.max(
        0,
        Math.min(palette.length - 1, image.pixels[y * image.width + x]),
      );
      ctx.fillStyle = argbToCss(palette[colorIndex]);
      ctx.fillRect(x * scale, y * scale, scale, scale);
    }
  }
}

function nearestPaletteIndex(profile, r, g, b) {
  const palette = getPalette(profile);
  let bestIndex = 0;
  let bestDistance = Number.POSITIVE_INFINITY;
  for (let i = 0; i < palette.length; i++) {
    const color = palette[i];
    const pr = (color >> 16) & 0xff;
    const pg = (color >> 8) & 0xff;
    const pb = color & 0xff;
    const dr = r - pr;
    const dg = g - pg;
    const db = b - pb;
    const distance = dr * dr + dg * dg + db * db;
    if (distance < bestDistance) {
      bestDistance = distance;
      bestIndex = i;
    }
  }
  return bestIndex;
}


  global.MCOImg = Object.freeze({
    PaletteProfile,
    PaletteProfileName,
    PaletteDisplayOrder,
    PaletteDisplayName,
    ImageMode,
    ImageModeName,
    ScanMode,
    ScanModeName,
    MCOImagePalettes,
    MCOImageCodecError,
    MCOImageInvalidInputError,
    MCOImageInvalidPayloadError,
    MCOImageTooLargeError,
    MCOImage,
    MCOImageCodec,
    globalBits,
    paletteSize,
    getPalette,
    whiteIndexFor,
    blackIndexFor,
    normalizePaletteProfile,
    base91Encode,
    base91Decode,
    argbToCss,
    drawMCOImage,
    nearestPaletteIndex,
  });
})(typeof window !== 'undefined' ? window : globalThis);
