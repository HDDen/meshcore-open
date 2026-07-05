(function(global) {
  'use strict';

  // Standalone browser-global port of the binary MCOimg v3 codec.
  // Pixel arrays contain palette indexes (fixed profiles) or Dynamic Global 512
  // indexes (dynamic profiles), matching the Dart codec.

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
    dynamicGlobal8: 9,
    dynamicGlobal16: 10,
    dynamicGlobal32: 11,
    dynamicGlobal64: 12,
    dynamicGlobal128: 13,
    dynamicGlobal256: 14,
    dynamicGlobal512: 15,
  });

  const PaletteProfileName = Object.freeze([
    'mono', 'master4', 'master8', 'master16', 'master32', 'master64',
    'grayscale16', 'grayscale32', 'grayscale8', 'dynamicGlobal8',
    'dynamicGlobal16', 'dynamicGlobal32', 'dynamicGlobal64',
    'dynamicGlobal128', 'dynamicGlobal256', 'dynamicGlobal512',
  ]);

  const ScanMode = Object.freeze({ h: 0, v: 1, s: 2, sv: 3 });
  const ScanModeName = Object.freeze(['h', 'v', 's', 'sv']);

  const MCOImageV3Container = Object.freeze({
    block: 0,
    compactBlock: 1,
    boundsBlock: 2,
    compactBoundsBlock: 3,
    regions: 4,
    compactRegionsStream: 5,
    solidBackground: 6,
    solidRects: 7,
  });
  const MCOImageV3ContainerName = Object.freeze([
    'block', 'compactBlock', 'boundsBlock', 'compactBoundsBlock',
    'regions', 'compactRegionsStream', 'solidBackground', 'solidRects',
  ]);

  const MCOImageV3BlockAlgorithm = Object.freeze({
    rawGlobal: 0,
    rawLocal: 1,
    compactRle: 2,
    compactSparse: 3,
    biColorMask: 4,
    rowRepeat: 5,
    lzPixels: 6,
    quadtree: 7,
    bitplanes: 8,
    adaptiveBitplanes: 9,
    directBitplanes: 10,
    compactRowDelta: 11,
    directRowDelta: 12,
    rowDelta: 13,
    varUintRle: 14,
    varUintSparse: 15,
  });
  const MCOImageV3BlockAlgorithmName = Object.freeze([
    'rawGlobal', 'rawLocal', 'compactRle', 'compactSparse', 'biColorMask',
    'rowRepeat', 'lzPixels', 'quadtree', 'bitplanes', 'adaptiveBitplanes',
    'directBitplanes', 'compactRowDelta', 'directRowDelta', 'rowDelta',
    'varUintRle', 'varUintSparse',
  ]);

  const MCOImageV3CompressionLevel = Object.freeze({ high: 0, normal: 1, extreme: 2 });
  const MCOImageV3CompressionLevelName = Object.freeze(['high', 'normal', 'extreme']);
  const MCOImageV3OutputFormat = Object.freeze({
    text: 'text', binary: 'binary', png: 'png', image: 'image', encoded: 'encoded',
  });

  class MCOImageV3CodecError extends Error {}
  class MCOImageV3InvalidInputError extends MCOImageV3CodecError {}
  class MCOImageV3InvalidPayloadError extends MCOImageV3CodecError {}
  class MCOImageV3NotImplementedError extends MCOImageV3CodecError {}

  class MCOImageV3 {
    constructor({ width, height, paletteProfile, pixels, transparentColor = null }) {
      this.width = width;
      this.height = height;
      this.paletteProfile = paletteProfile;
      this.pixels = Array.from(pixels);
      this.transparentColor = transparentColor == null ? null : Number(transparentColor);
      this.encodingVersion = 3;
    }
  }

  const DynamicGlobalIndices = Object.freeze({
    [PaletteProfile.dynamicGlobal8]: Object.freeze([0, 83, 63, 91, 210, 283, 401, 484]),
    [PaletteProfile.dynamicGlobal16]: Object.freeze([0, 84, 63, 100, 118, 155, 191, 210, 246, 292, 310, 338, 411, 447, 492, 511]),
    [PaletteProfile.dynamicGlobal32]: Object.freeze([0, 18, 85, 63, 64, 82, 91, 118, 128, 155, 173, 182, 201, 210, 237, 255, 265, 283, 310, 319, 320, 347, 374, 383, 393, 411, 429, 447, 448, 457, 475, 511]),
    [PaletteProfile.dynamicGlobal64]: Object.freeze([0, 9, 18, 27, 36, 45, 54, 63, 64, 73, 82, 91, 100, 109, 118, 127, 128, 137, 146, 155, 164, 173, 182, 191, 192, 201, 210, 219, 228, 237, 246, 255, 256, 265, 274, 283, 292, 301, 310, 319, 320, 329, 338, 347, 356, 365, 374, 383, 384, 393, 402, 411, 420, 429, 438, 447, 448, 457, 466, 475, 484, 493, 502, 511]),
    [PaletteProfile.dynamicGlobal128]: Object.freeze([0, 9, 18, 27, 36, 45, 54, 63, 64, 73, 82, 91, 100, 109, 118, 127, 128, 137, 146, 155, 164, 173, 182, 191, 192, 201, 210, 219, 228, 237, 246, 255, 256, 265, 274, 283, 292, 301, 310, 319, 320, 329, 338, 347, 356, 365, 374, 383, 384, 393, 402, 411, 420, 429, 438, 447, 448, 457, 466, 475, 484, 493, 502, 511, 1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 14, 15, 16, 17, 19, 20, 21, 22, 23, 24, 25, 26, 28, 29, 30, 31, 32, 33, 34, 35, 37, 38, 39, 40, 41, 42, 43, 44, 46, 47, 48, 49, 50, 51, 52, 53, 55, 56, 57, 58, 59, 60, 61, 62, 65, 66, 67, 68, 69, 70, 71, 72]),
    [PaletteProfile.dynamicGlobal256]: Object.freeze([0, 9, 18, 27, 36, 45, 54, 63, 64, 73, 82, 91, 100, 109, 118, 127, 128, 137, 146, 155, 164, 173, 182, 191, 192, 201, 210, 219, 228, 237, 246, 255, 256, 265, 274, 283, 292, 301, 310, 319, 320, 329, 338, 347, 356, 365, 374, 383, 384, 393, 402, 411, 420, 429, 438, 447, 448, 457, 466, 475, 484, 493, 502, 511, 1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 14, 15, 16, 17, 19, 20, 21, 22, 23, 24, 25, 26, 28, 29, 30, 31, 32, 33, 34, 35, 37, 38, 39, 40, 41, 42, 43, 44, 46, 47, 48, 49, 50, 51, 52, 53, 55, 56, 57, 58, 59, 60, 61, 62, 65, 66, 67, 68, 69, 70, 71, 72, 74, 75, 76, 77, 78, 79, 80, 81, 83, 84, 85, 86, 87, 88, 89, 90, 92, 93, 94, 95, 96, 97, 98, 99, 101, 102, 103, 104, 105, 106, 107, 108, 110, 111, 112, 113, 114, 115, 116, 117, 119, 120, 121, 122, 123, 124, 125, 126, 129, 130, 131, 132, 133, 134, 135, 136, 138, 139, 140, 141, 142, 143, 144, 145, 147, 148, 149, 150, 151, 152, 153, 154, 156, 157, 158, 159, 160, 161, 162, 163, 165, 166, 167, 168, 169, 170, 171, 172, 174, 175, 176, 177, 178, 179, 180, 181, 183, 184, 185, 186, 187, 188, 189, 190, 193, 194, 195, 196, 197, 198, 199, 200, 202, 203, 204, 205, 206, 207, 208, 209, 211, 212, 213, 214, 215, 216, 217, 218]),
    [PaletteProfile.dynamicGlobal512]: Object.freeze([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 224, 225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239, 240, 241, 242, 243, 244, 245, 246, 247, 248, 249, 250, 251, 252, 253, 254, 255, 256, 257, 258, 259, 260, 261, 262, 263, 264, 265, 266, 267, 268, 269, 270, 271, 272, 273, 274, 275, 276, 277, 278, 279, 280, 281, 282, 283, 284, 285, 286, 287, 288, 289, 290, 291, 292, 293, 294, 295, 296, 297, 298, 299, 300, 301, 302, 303, 304, 305, 306, 307, 308, 309, 310, 311, 312, 313, 314, 315, 316, 317, 318, 319, 320, 321, 322, 323, 324, 325, 326, 327, 328, 329, 330, 331, 332, 333, 334, 335, 336, 337, 338, 339, 340, 341, 342, 343, 344, 345, 346, 347, 348, 349, 350, 351, 352, 353, 354, 355, 356, 357, 358, 359, 360, 361, 362, 363, 364, 365, 366, 367, 368, 369, 370, 371, 372, 373, 374, 375, 376, 377, 378, 379, 380, 381, 382, 383, 384, 385, 386, 387, 388, 389, 390, 391, 392, 393, 394, 395, 396, 397, 398, 399, 400, 401, 402, 403, 404, 405, 406, 407, 408, 409, 410, 411, 412, 413, 414, 415, 416, 417, 418, 419, 420, 421, 422, 423, 424, 425, 426, 427, 428, 429, 430, 431, 432, 433, 434, 435, 436, 437, 438, 439, 440, 441, 442, 443, 444, 445, 446, 447, 448, 449, 450, 451, 452, 453, 454, 455, 456, 457, 458, 459, 460, 461, 462, 463, 464, 465, 466, 467, 468, 469, 470, 471, 472, 473, 474, 475, 476, 477, 478, 479, 480, 481, 482, 483, 484, 485, 486, 487, 488, 489, 490, 491, 492, 493, 494, 495, 496, 497, 498, 499, 500, 501, 502, 503, 504, 505, 506, 507, 508, 509, 510, 511]),
  });

  const TRANSPARENT_FLAG = 0x80;
  const IMPLICIT_WHITE_BACKGROUND_FLAG = 0x40;
  const SCAN_SHIFT = 4;
  const SCAN_MASK = 0x30;
  const PROFILE_MASK = 0x0f;
  const DIMENSION_MODE_SQUARE64 = 0;
  const DIMENSION_MODE_SMALL32 = 1;
  const DIMENSION_MODE_MEDIUM64 = 2;
  const DIMENSION_MODE_EXTENDED = 3;
  const CONTAINER_CONTEXT_CONTAINER_SHIFT = 5;
  const CONTAINER_CONTEXT_MASK = 0x1f;
  const MIN_SIZE = 1;
  const MAX_SIZE = 256;
  const MAX_REGIONS = 32;
  const MIN_LZ_MATCH_LENGTH = 3;
  const HYBRID_COMMON_REGION_ALGORITHM_MARKER = 31;

  const LOCAL_PALETTE_DESCRIPTOR_BITS = 2;
  const LOCAL_PALETTE_SMALL_LENGTH_LIMIT = 64;
  const LOCAL_PALETTE_MEDIUM_LENGTH_LIMIT = 128;
  const LOCAL_PALETTE_LARGE_LENGTH_LIMIT = 384;
  const LOCAL_PALETTE_DESCRIPTOR_BITMAP = 0;
  const LOCAL_PALETTE_DESCRIPTOR_SORTED_DELTA = 1;
  const LOCAL_PALETTE_DESCRIPTOR_RANGE_RUNS = 2;
  const LOCAL_PALETTE_DESCRIPTOR_BANK_BITMAPS = 3;
  const LOCAL_PALETTE_BANK_DESCRIPTOR_BITMAPS = 0;
  const LOCAL_PALETTE_BANK_DESCRIPTOR_ORDERED_8X64 = 1;

  const ROW_DELTA_OP_BITS = 2;
  const ROW_DELTA_OP_RAW = 0;
  const ROW_DELTA_OP_REPEAT = 1;
  const ROW_DELTA_OP_INDEXED = 2;
  const ROW_DELTA_OP_EXTENDED = 3;
  const ROW_DELTA_EXTENDED_BITS = 2;
  const ROW_DELTA_EXTENDED_MASK = 0;
  const ROW_DELTA_EXTENDED_SEGMENTS = 1;
  const ROW_DELTA_EXTENDED_SAME_SCALAR_MASK = 2;
  const ROW_DELTA_EXTENDED_REPEAT_RUN = 3;

  const COMPACT_ROW_DELTA_OP_BITS = 3;
  const COMPACT_ROW_DELTA_OP_REPEAT = 0;
  const COMPACT_ROW_DELTA_OP_RAW = 1;
  const COMPACT_ROW_DELTA_OP_INDEXED = 2;
  const COMPACT_ROW_DELTA_OP_SAME_SCALAR = 3;
  const COMPACT_ROW_DELTA_OP_SEGMENTS = 4;
  const COMPACT_ROW_DELTA_OP_TRIMMED_MASK = 5;
  const COMPACT_ROW_DELTA_OP_REPEAT_RUN = 6;
  const COMPACT_ROW_DELTA_OP_PREDICTED = 7;
  const ROW_DELTA_PREDICTOR_SAME = 0;
  const ROW_DELTA_PREDICTOR_LEFT = 1;
  const ROW_DELTA_PREDICTOR_RIGHT = 2;

  const BASE91_ALPHABET =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789' +
    '!#$%&()*+,./:;<=>?@[]^_`{|}~"';
  const BASE91_DECODE = new Map(
    Array.from(BASE91_ALPHABET).map((character, index) => [character.charCodeAt(0), index]),
  );

  function asBytes(value, label = 'bytes') {
    if (value instanceof Uint8Array) return value;
    if (value instanceof ArrayBuffer) return new Uint8Array(value);
    if (ArrayBuffer.isView(value)) {
      return new Uint8Array(value.buffer, value.byteOffset, value.byteLength);
    }
    if (Array.isArray(value)) return Uint8Array.from(value);
    throw new TypeError(`${label} must be a Uint8Array, ArrayBuffer, view, or byte array`);
  }

  function base91Encode(bytesLike) {
    const bytes = asBytes(bytesLike);
    let output = '';
    let queue = 0;
    let bitCount = 0;
    for (const byte of bytes) {
      queue |= byte << bitCount;
      bitCount += 8;
      if (bitCount > 13) {
        let value = queue & 8191;
        if (value > 88) {
          queue >>>= 13;
          bitCount -= 13;
        } else {
          value = queue & 16383;
          queue >>>= 14;
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
    if (typeof text !== 'string') throw new TypeError('basE91 input must be a string');
    const output = [];
    let value = -1;
    let queue = 0;
    let bitCount = 0;
    for (let i = 0; i < text.length; i++) {
      const decoded = BASE91_DECODE.get(text.charCodeAt(i));
      if (decoded === undefined) {
        throw new MCOImageV3InvalidPayloadError('Invalid basE91 character');
      }
      if (value < 0) {
        value = decoded;
      } else {
        value += decoded * 91;
        queue |= value << bitCount;
        bitCount += (value & 8191) > 88 ? 13 : 14;
        while (bitCount > 7) {
          output.push(queue & 0xff);
          queue >>>= 8;
          bitCount -= 8;
        }
        value = -1;
      }
    }
    if (value >= 0) output.push((queue | (value << bitCount)) & 0xff);
    return Uint8Array.from(output);
  }

  function bitLength(value) {
    if (!Number.isInteger(value) || value < 0) {
      throw new MCOImageV3InvalidPayloadError('Invalid non-negative integer');
    }
    if (value === 0) return 0;
    return 32 - Math.clz32(value);
  }

  function bitCount(value) {
    let current = value >>> 0;
    let count = 0;
    while (current !== 0) {
      count += current & 1;
      current >>>= 1;
    }
    return count;
  }

  function isDynamicProfile(profile) {
    return profile >= PaletteProfile.dynamicGlobal8 && profile <= PaletteProfile.dynamicGlobal512;
  }

  function isGrayscaleProfile(profile) {
    return profile === PaletteProfile.grayscale8 ||
      profile === PaletteProfile.grayscale16 ||
      profile === PaletteProfile.grayscale32;
  }

  function paletteSize(profile) {
    switch (profile) {
      case PaletteProfile.mono: return 2;
      case PaletteProfile.master4: return 4;
      case PaletteProfile.master8:
      case PaletteProfile.grayscale8:
      case PaletteProfile.dynamicGlobal8: return 8;
      case PaletteProfile.master16:
      case PaletteProfile.grayscale16:
      case PaletteProfile.dynamicGlobal16: return 16;
      case PaletteProfile.master32:
      case PaletteProfile.grayscale32:
      case PaletteProfile.dynamicGlobal32: return 32;
      case PaletteProfile.master64:
      case PaletteProfile.dynamicGlobal64: return 64;
      case PaletteProfile.dynamicGlobal128: return 128;
      case PaletteProfile.dynamicGlobal256: return 256;
      case PaletteProfile.dynamicGlobal512: return 512;
      default: throw new MCOImageV3InvalidPayloadError(`Unknown MCOimg v3 profile ${profile}`);
    }
  }

  function globalBits(profile) {
    switch (profile) {
      case PaletteProfile.mono: return 1;
      case PaletteProfile.master4: return 2;
      case PaletteProfile.master8:
      case PaletteProfile.grayscale8:
      case PaletteProfile.dynamicGlobal8: return 3;
      case PaletteProfile.master16:
      case PaletteProfile.grayscale16:
      case PaletteProfile.dynamicGlobal16: return 4;
      case PaletteProfile.master32:
      case PaletteProfile.grayscale32:
      case PaletteProfile.dynamicGlobal32: return 5;
      case PaletteProfile.master64:
      case PaletteProfile.dynamicGlobal64: return 6;
      case PaletteProfile.dynamicGlobal128: return 7;
      case PaletteProfile.dynamicGlobal256: return 8;
      case PaletteProfile.dynamicGlobal512: return 9;
      default: throw new MCOImageV3InvalidPayloadError(`Unknown MCOimg v3 profile ${profile}`);
    }
  }

  function profileFromId(id) {
    if (!Number.isInteger(id) || id < 0 || id >= PaletteProfileName.length) {
      throw new MCOImageV3InvalidPayloadError(`Unknown MCOimg v3 profile ${id}`);
    }
    return id;
  }

  function dynamicProfilePalette(profile) {
    const indices = DynamicGlobalIndices[profile];
    if (!indices) throw new MCOImageV3InvalidPayloadError('Not a dynamic palette profile');
    return Array.from(indices);
  }

  function globalIndexForProfileRef(profile, ref) {
    if (!Number.isInteger(ref) || ref < 0 || ref >= paletteSize(profile)) {
      throw new MCOImageV3InvalidPayloadError('Palette reference out of range');
    }
    if (!isDynamicProfile(profile)) return ref;
    return DynamicGlobalIndices[profile][ref];
  }

  function colorFromProfileRef(profile, ref) {
    return globalIndexForProfileRef(profile, ref);
  }

  function whiteIndexFor(profile) {
    // All current fixed profiles use palette entry 0 for white. Dynamic
    // profiles store pixels as Dynamic Global 512 indexes and white is 0.
    return 0;
  }

  function localBits(colorCount) {
    if (colorCount <= 1) return 0;
    return bitLength(colorCount - 1);
  }

  function geometryBits(size) {
    if (size <= 1) return 0;
    return bitLength(size - 1);
  }

  function validateDimensions(width, height) {
    if (!Number.isInteger(width) || !Number.isInteger(height) ||
        width < MIN_SIZE || height < MIN_SIZE || width > MAX_SIZE || height > MAX_SIZE) {
      throw new MCOImageV3InvalidPayloadError(
        `Image size must be ${MIN_SIZE}..${MAX_SIZE} in both axes`,
      );
    }
  }

  function algorithmFromId(value) {
    if (!Number.isInteger(value) || value < 0 || value >= MCOImageV3BlockAlgorithmName.length) {
      throw new MCOImageV3InvalidPayloadError(`Unknown MCOimg v3 algorithm ${value}`);
    }
    return value;
  }

  function containerFromId(value) {
    if (!Number.isInteger(value) || value < 0 || value >= MCOImageV3ContainerName.length) {
      throw new MCOImageV3InvalidPayloadError(`Unknown MCOimg v3 container ${value}`);
    }
    return value;
  }

  function scanFromId(value) {
    if (!Number.isInteger(value) || value < 0 || value >= ScanModeName.length) {
      throw new MCOImageV3InvalidPayloadError(`Unknown MCOimg v3 scan ${value}`);
    }
    return value;
  }

  function scanFromHeader(header) {
    return scanFromId((header & SCAN_MASK) >> SCAN_SHIFT);
  }

  function topLevelAlgorithm(container, context) {
    switch (container) {
      case MCOImageV3Container.block:
      case MCOImageV3Container.compactBlock:
      case MCOImageV3Container.boundsBlock:
      case MCOImageV3Container.compactBoundsBlock:
        return algorithmFromId(context);
      default:
        return MCOImageV3BlockAlgorithm.rawGlobal;
    }
  }

  function canUseCompactBlockHeader(algorithm) {
    return algorithm === MCOImageV3BlockAlgorithm.rawGlobal ||
      algorithm === MCOImageV3BlockAlgorithm.rawLocal ||
      algorithm === MCOImageV3BlockAlgorithm.biColorMask;
  }

  function blockAlgorithmUsesBackgroundRef(algorithm) {
    return algorithm === MCOImageV3BlockAlgorithm.compactSparse ||
      algorithm === MCOImageV3BlockAlgorithm.varUintSparse ||
      algorithm === MCOImageV3BlockAlgorithm.biColorMask;
  }

  function validateTopLevelScan(container, algorithm, scan) {
    let requiresHorizontal = false;
    switch (container) {
      case MCOImageV3Container.compactBlock:
      case MCOImageV3Container.regions:
      case MCOImageV3Container.compactRegionsStream:
      case MCOImageV3Container.solidBackground:
      case MCOImageV3Container.solidRects:
        requiresHorizontal = true;
        break;
      case MCOImageV3Container.compactBoundsBlock:
        requiresHorizontal = canUseCompactBlockHeader(algorithm);
        break;
    }
    if (requiresHorizontal && scan !== ScanMode.h) {
      throw new MCOImageV3InvalidPayloadError(
        `${MCOImageV3ContainerName[container]} requires horizontal top-level scan`,
      );
    }
    if (algorithm === MCOImageV3BlockAlgorithm.quadtree && scan !== ScanMode.h) {
      throw new MCOImageV3InvalidPayloadError('Quadtree requires horizontal scan');
    }
  }

  function validateImplicitWhiteBackground(container, algorithm, implicitWhiteBackground) {
    if (!implicitWhiteBackground) return;
    let allowed;
    if (container === MCOImageV3Container.block || container === MCOImageV3Container.compactBlock) {
      allowed = blockAlgorithmUsesBackgroundRef(algorithm);
    } else {
      allowed = true;
    }
    if (!allowed) {
      throw new MCOImageV3InvalidPayloadError(
        'Implicit white background is not valid for this container',
      );
    }
  }

  function blockAlgorithmLabel(algorithm) {
    switch (algorithm) {
      case MCOImageV3BlockAlgorithm.rawGlobal: return 'Raw global';
      case MCOImageV3BlockAlgorithm.rawLocal: return 'Raw local';
      case MCOImageV3BlockAlgorithm.compactRle: return 'RLE local';
      case MCOImageV3BlockAlgorithm.varUintRle: return 'RLE varuint';
      case MCOImageV3BlockAlgorithm.compactSparse: return 'Sparse background';
      case MCOImageV3BlockAlgorithm.varUintSparse: return 'Sparse varuint';
      case MCOImageV3BlockAlgorithm.biColorMask: return 'Bi-color mask';
      case MCOImageV3BlockAlgorithm.rowRepeat: return 'Row repeat';
      case MCOImageV3BlockAlgorithm.lzPixels: return 'LZ pixels';
      case MCOImageV3BlockAlgorithm.quadtree: return 'Quadtree';
      case MCOImageV3BlockAlgorithm.bitplanes: return 'Bitplanes';
      case MCOImageV3BlockAlgorithm.adaptiveBitplanes: return 'Adaptive bitplanes';
      case MCOImageV3BlockAlgorithm.directBitplanes: return 'Direct bitplanes';
      case MCOImageV3BlockAlgorithm.compactRowDelta: return 'Compact row delta';
      case MCOImageV3BlockAlgorithm.directRowDelta: return 'Direct row delta';
      case MCOImageV3BlockAlgorithm.rowDelta: return 'Row delta';
      default: return `Algorithm ${algorithm}`;
    }
  }

  function payloadAlgorithmLabel(container, algorithm) {
    if (container === MCOImageV3Container.solidBackground) return 'Solid background';
    if (container === MCOImageV3Container.solidRects) return 'Solid rectangles';
    if (container === MCOImageV3Container.regions ||
        container === MCOImageV3Container.compactRegionsStream) return 'Regions';
    const base = blockAlgorithmLabel(algorithm);
    if (container === MCOImageV3Container.boundsBlock ||
        container === MCOImageV3Container.compactBoundsBlock) return `${base} bounds`;
    return base;
  }

  class BitReader {
    constructor(bytesLike, byteIndex = 0) {
      this.bytes = asBytes(bytesLike);
      this.byteIndex = byteIndex;
      this.bitOffset = 0;
    }

    readBits(bits) {
      if (!Number.isInteger(bits) || bits < 0 || bits > 32) {
        throw new MCOImageV3InvalidPayloadError('Invalid bit length');
      }
      let result = 0;
      let shift = 0;
      let remaining = bits;
      while (remaining > 0) {
        if (this.byteIndex >= this.bytes.length) {
          throw new MCOImageV3InvalidPayloadError('Unexpected end of bits');
        }
        const available = 8 - this.bitOffset;
        const take = Math.min(available, remaining);
        const mask = take === 32 ? 0xffffffff : (2 ** take) - 1;
        result += (((this.bytes[this.byteIndex] >> this.bitOffset) & mask) * (2 ** shift));
        this.bitOffset += take;
        if (this.bitOffset === 8) {
          this.byteIndex++;
          this.bitOffset = 0;
        }
        shift += take;
        remaining -= take;
      }
      return result;
    }

    readBitVarUint() {
      let result = 0;
      let factor = 1;
      for (let i = 0; i < 5; i++) {
        const byte = this.readBits(8);
        result += (byte & 0x7f) * factor;
        if ((byte & 0x80) === 0) return result;
        factor *= 128;
      }
      throw new MCOImageV3InvalidPayloadError('Varuint is too long');
    }

    readRangeCompactUint(maxValue) {
      if (!Number.isInteger(maxValue) || maxValue < 0) {
        throw new MCOImageV3InvalidPayloadError('Invalid range compact uint limit');
      }
      const value = maxValue <= 7 ? this.readBits(bitLength(maxValue)) : this.readCompactUint();
      if (value > maxValue) {
        throw new MCOImageV3InvalidPayloadError('Range compact uint exceeds limit');
      }
      return value;
    }

    readBoundedCompactUint(maxValue) {
      if (!Number.isInteger(maxValue) || maxValue < 0) {
        throw new MCOImageV3InvalidPayloadError('Invalid bounded compact uint limit');
      }
      if (maxValue <= 7) return this.readBits(bitLength(maxValue));
      let value;
      if (this.readBits(1) === 0) {
        value = this.readBits(2);
      } else if (this.readBits(1) === 0) {
        value = this.readBits(4) + 4;
      } else if (this.readBits(1) === 0) {
        value = this.readBits(8) + 20;
      } else {
        if (maxValue < 276) {
          throw new MCOImageV3InvalidPayloadError('Invalid bounded compact uint escape');
        }
        value = this.readBits(bitLength(maxValue - 276)) + 276;
      }
      if (value > maxValue) {
        throw new MCOImageV3InvalidPayloadError('Bounded compact uint exceeds limit');
      }
      return value;
    }

    readCompactUint() {
      if (this.readBits(1) === 0) return this.readBits(2);
      if (this.readBits(1) === 0) return this.readBits(4) + 4;
      if (this.readBits(1) === 0) return this.readBits(8) + 20;
      return this.readBitVarUint();
    }

    finish() {
      if (this.bitOffset !== 0) {
        const unusedMask = (0xff << this.bitOffset) & 0xff;
        if ((this.bytes[this.byteIndex] & unusedMask) !== 0) {
          throw new MCOImageV3InvalidPayloadError('Non-zero padding bits');
        }
        this.byteIndex++;
        this.bitOffset = 0;
      }
      if (this.byteIndex !== this.bytes.length) {
        throw new MCOImageV3InvalidPayloadError('Trailing payload bytes');
      }
    }
  }

  function readDimensions(reader) {
    const mode = reader.readBits(2);
    let width;
    let height;
    switch (mode) {
      case DIMENSION_MODE_SQUARE64:
        width = reader.readBits(6) + 1;
        height = width;
        break;
      case DIMENSION_MODE_SMALL32:
        width = reader.readBits(5) + 1;
        height = reader.readBits(5) + 1;
        if (width === height) {
          throw new MCOImageV3InvalidPayloadError('Non-canonical small square dimensions');
        }
        break;
      case DIMENSION_MODE_MEDIUM64:
        width = reader.readBits(6) + 1;
        height = reader.readBits(6) + 1;
        if (width === height || (width <= 32 && height <= 32)) {
          throw new MCOImageV3InvalidPayloadError('Non-canonical medium dimensions');
        }
        break;
      case DIMENSION_MODE_EXTENDED: {
        const generalRectangle = reader.readBits(1) !== 0;
        if (!generalRectangle) {
          width = reader.readBits(8) + 1;
          height = width;
          if (width <= 64) {
            throw new MCOImageV3InvalidPayloadError('Non-canonical extended square dimensions');
          }
        } else {
          width = reader.readBits(8) + 1;
          height = reader.readBits(8) + 1;
          if (width === height || (width <= 64 && height <= 64)) {
            throw new MCOImageV3InvalidPayloadError('Non-canonical extended dimensions');
          }
        }
        break;
      }
      default:
        throw new MCOImageV3InvalidPayloadError('Unknown dimension mode');
    }
    validateDimensions(width, height);
    return { width, height };
  }

  function readColorRef(reader, profile) {
    return colorFromProfileRef(profile, reader.readBits(globalBits(profile)));
  }

  function readBackgroundRef(reader, profile, implicitWhiteBackground) {
    return implicitWhiteBackground ? whiteIndexFor(profile) : readColorRef(reader, profile);
  }

  function readContextualColorRef(reader, profile, context) {
    const totalBits = globalBits(profile);
    const lowBits = Math.min(totalBits, 5);
    const lowMask = (2 ** lowBits) - 1;
    if ((context & ~lowMask) !== 0) {
      throw new MCOImageV3InvalidPayloadError('Solid background color context is out of range');
    }
    const remainingBits = totalBits - lowBits;
    const colorRef = remainingBits > 0
      ? context | (reader.readBits(remainingBits) << lowBits)
      : context;
    return colorFromProfileRef(profile, colorRef);
  }

  function readSolidBackgroundColor(reader, profile, context, implicitWhiteBackground) {
    if (implicitWhiteBackground) {
      if (context !== 0) {
        throw new MCOImageV3InvalidPayloadError(
          'Implicit white solid background must use zero context',
        );
      }
      return whiteIndexFor(profile);
    }
    return readContextualColorRef(reader, profile, context);
  }

  function readLocalPalettePrefix(reader, profile) {
    const size = paletteSize(profile);
    if (size <= LOCAL_PALETTE_SMALL_LENGTH_LIMIT) {
      if (reader.readBits(1) !== 0) {
        return { descriptor: reader.readBits(LOCAL_PALETTE_DESCRIPTOR_BITS) };
      }
      return { length: reader.readBits(globalBits(profile)) + 1 };
    }
    if (reader.readBits(1) === 0) return { length: reader.readBits(6) + 1 };
    if (reader.readBits(1) === 0) return { length: reader.readBits(6) + 65 };
    if (reader.readBits(1) === 0) {
      const length = reader.readBits(8) + 129;
      if (length > size) throw new MCOImageV3InvalidPayloadError('Invalid local palette size');
      return { length };
    }
    if (reader.readBits(1) === 0) {
      const length = reader.readBits(7) + 385;
      if (length > size) throw new MCOImageV3InvalidPayloadError('Invalid local palette size');
      return { length };
    }
    return { descriptor: reader.readBits(LOCAL_PALETTE_DESCRIPTOR_BITS) };
  }

  function readLocalPaletteLength(reader, profile) {
    const size = paletteSize(profile);
    if (size <= LOCAL_PALETTE_SMALL_LENGTH_LIMIT) {
      return reader.readBits(globalBits(profile)) + 1;
    }
    if (reader.readBits(1) === 0) return reader.readBits(6) + 1;
    if (reader.readBits(1) === 0) return reader.readBits(6) + 65;
    if (size <= LOCAL_PALETTE_MEDIUM_LENGTH_LIMIT) {
      throw new MCOImageV3InvalidPayloadError('Invalid local palette length prefix');
    }
    const length = reader.readBits(bitLength(size - 129)) + 129;
    if (length > size) throw new MCOImageV3InvalidPayloadError('Invalid local palette size');
    return length;
  }

  function readLocalPaletteBitmapDescriptor(reader, profile) {
    const refs = [];
    for (let ref = 0; ref < paletteSize(profile); ref++) {
      if (reader.readBits(1) !== 0) refs.push(ref);
    }
    return refs;
  }

  function readLocalPaletteSortedDeltaDescriptor(reader, profile) {
    const count = readLocalPaletteLength(reader, profile);
    if (count <= 0 || count > paletteSize(profile)) {
      throw new MCOImageV3InvalidPayloadError('Invalid sorted local palette size');
    }
    const refs = [reader.readBits(globalBits(profile))];
    while (refs.length < count) refs.push(refs[refs.length - 1] + reader.readCompactUint() + 1);
    return refs;
  }

  function readLocalPaletteRangeRunsDescriptor(reader, profile) {
    const runCount = reader.readRangeCompactUint(paletteSize(profile) - 1) + 1;
    if (runCount <= 0 || runCount > paletteSize(profile)) {
      throw new MCOImageV3InvalidPayloadError('Invalid local palette range count');
    }
    const refs = [];
    let previousEnd = -1;
    for (let i = 0; i < runCount; i++) {
      const start = reader.readBits(globalBits(profile));
      const length = reader.readCompactUint() + 1;
      const end = start + length - 1;
      if (start <= previousEnd || end >= paletteSize(profile) ||
          refs.length + length > paletteSize(profile)) {
        throw new MCOImageV3InvalidPayloadError('Invalid local palette range');
      }
      for (let offset = 0; offset < length; offset++) refs.push(start + offset);
      previousEnd = end;
    }
    return refs;
  }

  function readLocalPaletteBankBitmapsDescriptor(reader, profile) {
    if (profile !== PaletteProfile.dynamicGlobal512) {
      throw new MCOImageV3InvalidPayloadError('Bank bitmap descriptor requires dynamicGlobal512');
    }
    const bankMask = reader.readBits(8);
    if (bankMask === 0) throw new MCOImageV3InvalidPayloadError('Empty bank bitmap palette');
    const refs = [];
    for (let bank = 0; bank < 8; bank++) {
      if ((bankMask & (1 << bank)) === 0) continue;
      const beforeBank = refs.length;
      for (let offset = 0; offset < 64; offset++) {
        if (reader.readBits(1) !== 0) refs.push((bank << 6) | offset);
      }
      if (refs.length === beforeBank) {
        throw new MCOImageV3InvalidPayloadError('Bank bitmap palette contains an empty bank');
      }
    }
    return refs;
  }

  function readLocalPaletteOrderedBanked8x64Descriptor(reader, profile) {
    if (profile !== PaletteProfile.dynamicGlobal512) {
      throw new MCOImageV3InvalidPayloadError('Ordered banked descriptor requires dynamicGlobal512');
    }
    const count = readLocalPaletteLength(reader, profile);
    const multipleBanks = reader.readBits(1) !== 0;
    if (!multipleBanks) {
      if (count > 64) {
        throw new MCOImageV3InvalidPayloadError('Single-bank palette contains too many colors');
      }
      const bank = reader.readBits(3);
      const refs = [];
      for (let i = 0; i < count; i++) refs.push((bank << 6) | reader.readBits(6));
      return refs;
    }
    const bankMask = reader.readBits(8);
    const bankTotal = bitCount(bankMask);
    if (bankTotal <= 1) {
      throw new MCOImageV3InvalidPayloadError('Invalid ordered banked palette mask');
    }
    if (count > bankTotal * 64) {
      throw new MCOImageV3InvalidPayloadError('Ordered banked palette contains too many colors');
    }
    const banks = [];
    for (let bank = 0; bank < 8; bank++) if ((bankMask & (1 << bank)) !== 0) banks.push(bank);
    const bankBits = bitLength(bankTotal - 1);
    const refs = [];
    const used = new Set();
    for (let i = 0; i < count; i++) {
      const bankIndex = reader.readBits(bankBits);
      if (bankIndex >= banks.length) {
        throw new MCOImageV3InvalidPayloadError('Invalid ordered banked palette bank index');
      }
      used.add(bankIndex);
      refs.push((banks[bankIndex] << 6) | reader.readBits(6));
    }
    if (used.size !== bankTotal) {
      throw new MCOImageV3InvalidPayloadError('Ordered banked palette contains an unused bank');
    }
    return refs;
  }

  function readLocalPaletteBankDescriptor(reader, profile) {
    if (profile !== PaletteProfile.dynamicGlobal512) {
      throw new MCOImageV3InvalidPayloadError('Bank palette descriptor requires dynamicGlobal512');
    }
    const subtype = reader.readBits(1);
    if (subtype === LOCAL_PALETTE_BANK_DESCRIPTOR_BITMAPS) {
      return readLocalPaletteBankBitmapsDescriptor(reader, profile);
    }
    if (subtype === LOCAL_PALETTE_BANK_DESCRIPTOR_ORDERED_8X64) {
      return readLocalPaletteOrderedBanked8x64Descriptor(reader, profile);
    }
    throw new MCOImageV3InvalidPayloadError('Unknown bank palette descriptor');
  }

  function readLocalPaletteDescriptorBody(reader, profile, descriptor) {
    let refs;
    switch (descriptor) {
      case LOCAL_PALETTE_DESCRIPTOR_BITMAP:
        refs = readLocalPaletteBitmapDescriptor(reader, profile);
        break;
      case LOCAL_PALETTE_DESCRIPTOR_SORTED_DELTA:
        refs = readLocalPaletteSortedDeltaDescriptor(reader, profile);
        break;
      case LOCAL_PALETTE_DESCRIPTOR_RANGE_RUNS:
        refs = readLocalPaletteRangeRunsDescriptor(reader, profile);
        break;
      case LOCAL_PALETTE_DESCRIPTOR_BANK_BITMAPS:
        refs = readLocalPaletteBankDescriptor(reader, profile);
        break;
      default:
        throw new MCOImageV3InvalidPayloadError('Unknown local palette descriptor');
    }
    if (refs.length === 0 || refs.length > paletteSize(profile)) {
      throw new MCOImageV3InvalidPayloadError('Invalid compact local palette size');
    }
    const colors = [];
    const seen = new Set();
    for (const ref of refs) {
      if (!Number.isInteger(ref) || ref < 0 || ref >= paletteSize(profile) || seen.has(ref)) {
        throw new MCOImageV3InvalidPayloadError('Invalid compact local palette');
      }
      seen.add(ref);
      colors.push(globalIndexForProfileRef(profile, ref));
    }
    return colors;
  }

  function readLocalPalette(reader, profile) {
    const prefix = readLocalPalettePrefix(reader, profile);
    if (prefix.descriptor !== undefined) {
      return readLocalPaletteDescriptorBody(reader, profile, prefix.descriptor);
    }
    const colors = [];
    const seen = new Set();
    for (let i = 0; i < prefix.length; i++) {
      const color = readColorRef(reader, profile);
      if (seen.has(color)) throw new MCOImageV3InvalidPayloadError('Duplicate local color');
      seen.add(color);
      colors.push(color);
    }
    return colors;
  }

  function readRegionGeometry(reader, imageWidth, imageHeight, compactGeometry) {
    const xBits = compactGeometry ? geometryBits(imageWidth) : 8;
    const yBits = compactGeometry ? geometryBits(imageHeight) : 8;
    const x = reader.readBits(xBits);
    const y = reader.readBits(yBits);
    if (x >= imageWidth || y >= imageHeight) {
      throw new MCOImageV3InvalidPayloadError('Invalid v3 region origin');
    }
    const widthBits = compactGeometry ? geometryBits(imageWidth - x) : xBits;
    const heightBits = compactGeometry ? geometryBits(imageHeight - y) : yBits;
    const width = reader.readBits(widthBits) + 1;
    const height = reader.readBits(heightBits) + 1;
    if (x + width > imageWidth || y + height > imageHeight) {
      throw new MCOImageV3InvalidPayloadError('Invalid v3 region');
    }
    return { x, y, width, height };
  }

  function readSignedCompactInt(reader) {
    const encoded = reader.readCompactUint();
    return (encoded & 1) === 0 ? Math.floor(encoded / 2) : -Math.floor((encoded + 1) / 2);
  }

  function readDeltaRegionGeometry(reader, previous, imageWidth, imageHeight) {
    const bounds = {
      x: previous.x + readSignedCompactInt(reader),
      y: previous.y + readSignedCompactInt(reader),
      width: previous.width + readSignedCompactInt(reader),
      height: previous.height + readSignedCompactInt(reader),
    };
    if (bounds.x < 0 || bounds.y < 0 || bounds.width <= 0 || bounds.height <= 0 ||
        bounds.x + bounds.width > imageWidth || bounds.y + bounds.height > imageHeight) {
      throw new MCOImageV3InvalidPayloadError('Invalid v3 delta region');
    }
    return bounds;
  }

  function rowLengthForScan(scan, width, height) {
    return scan === ScanMode.h || scan === ScanMode.s ? width : height;
  }

  function fromScanOrder(linear, width, height, scan) {
    if (linear.length !== width * height) {
      throw new MCOImageV3InvalidPayloadError('Decoded pixel count does not match dimensions');
    }
    if (scan === ScanMode.h) return Array.from(linear);
    const result = Array(width * height).fill(0);
    let index = 0;
    if (scan === ScanMode.v) {
      for (let x = 0; x < width; x++) for (let y = 0; y < height; y++) result[y * width + x] = linear[index++];
    } else if (scan === ScanMode.s) {
      for (let y = 0; y < height; y++) {
        if ((y & 1) === 0) {
          for (let x = 0; x < width; x++) result[y * width + x] = linear[index++];
        } else {
          for (let x = width - 1; x >= 0; x--) result[y * width + x] = linear[index++];
        }
      }
    } else if (scan === ScanMode.sv) {
      for (let x = 0; x < width; x++) {
        if ((x & 1) === 0) {
          for (let y = 0; y < height; y++) result[y * width + x] = linear[index++];
        } else {
          for (let y = height - 1; y >= 0; y--) result[y * width + x] = linear[index++];
        }
      }
    } else {
      throw new MCOImageV3InvalidPayloadError(`Unknown scan mode ${scan}`);
    }
    return result;
  }

  function readQuadtreeNode(reader, pixels, stride, x, y, width, height, palette, bits) {
    const isSolid = reader.readBits(1) !== 0;
    if (isSolid) {
      const colorIndex = reader.readBits(bits);
      if (colorIndex >= palette.length) {
        throw new MCOImageV3InvalidPayloadError('Quadtree color index out of range');
      }
      for (let dy = 0; dy < height; dy++) {
        const rowStart = (y + dy) * stride + x;
        for (let dx = 0; dx < width; dx++) pixels[rowStart + dx] = palette[colorIndex];
      }
      return;
    }
    if (width === 1 && height === 1) {
      throw new MCOImageV3InvalidPayloadError('Quadtree splits a single pixel');
    }
    if (width === 1) {
      const topHeight = Math.floor(height / 2);
      readQuadtreeNode(reader, pixels, stride, x, y, width, topHeight, palette, bits);
      readQuadtreeNode(reader, pixels, stride, x, y + topHeight, width, height - topHeight, palette, bits);
      return;
    }
    if (height === 1) {
      const leftWidth = Math.floor(width / 2);
      readQuadtreeNode(reader, pixels, stride, x, y, leftWidth, height, palette, bits);
      readQuadtreeNode(reader, pixels, stride, x + leftWidth, y, width - leftWidth, height, palette, bits);
      return;
    }
    const leftWidth = Math.floor(width / 2);
    const topHeight = Math.floor(height / 2);
    readQuadtreeNode(reader, pixels, stride, x, y, leftWidth, topHeight, palette, bits);
    readQuadtreeNode(reader, pixels, stride, x + leftWidth, y, width - leftWidth, topHeight, palette, bits);
    readQuadtreeNode(reader, pixels, stride, x, y + topHeight, leftWidth, height - topHeight, palette, bits);
    readQuadtreeNode(reader, pixels, stride, x + leftWidth, y + topHeight, width - leftWidth, height - topHeight, palette, bits);
  }

  function readShortBitplaneRunLength(reader, remainingLength) {
    if (remainingLength <= 0) {
      throw new MCOImageV3InvalidPayloadError('Invalid remaining bitplane run length');
    }
    if (reader.readBits(1) === 0) return 1;
    if (remainingLength < 2) throw new MCOImageV3InvalidPayloadError('Bitplane run exceeds remaining pixels');
    if (reader.readBits(1) === 0) return 2;
    if (remainingLength < 3) throw new MCOImageV3InvalidPayloadError('Bitplane run exceeds remaining pixels');
    if (reader.readBits(1) === 0) return 3;
    if (remainingLength < 4) throw new MCOImageV3InvalidPayloadError('Bitplane run exceeds remaining pixels');
    return reader.readRangeCompactUint(remainingLength - 4) + 4;
  }

  function readAdaptiveBitplaneRuns(reader, pixels, bit, pixelCount, shortLengths) {
    let value = reader.readBits(1);
    let position = 0;
    while (position < pixelCount) {
      const length = shortLengths
        ? readShortBitplaneRunLength(reader, pixelCount - position)
        : reader.readRangeCompactUint(pixelCount - position - 1) + 1;
      if (length <= 0 || position + length > pixelCount) {
        throw new MCOImageV3InvalidPayloadError('Adaptive bitplane RLE exceeds pixel count');
      }
      if (value !== 0) for (let i = 0; i < length; i++) pixels[position + i] |= 1 << bit;
      position += length;
      value ^= 1;
    }
  }

  function readSparseBitplane(reader, pixels, bit, pixelCount, minorityBit) {
    const count = reader.readRangeCompactUint(pixelCount - 1) + 1;
    if (count > pixelCount) {
      throw new MCOImageV3InvalidPayloadError('Sparse bitplane count exceeds pixel count');
    }
    let previous = -1;
    for (let i = 0; i < count; i++) {
      const remainingPositions = count - i - 1;
      const maxGap = pixelCount - previous - remainingPositions - 2;
      const gap = reader.readRangeCompactUint(maxGap);
      const position = previous + gap + 1;
      if (position <= previous || position >= pixelCount) {
        throw new MCOImageV3InvalidPayloadError('Sparse bitplane position out of range');
      }
      if (minorityBit === 0) pixels[position] &= ~(1 << bit);
      else pixels[position] |= 1 << bit;
      previous = position;
    }
  }

  function decodeAdaptiveBitplanesBody(reader, pixelCount, palette) {
    const bits = localBits(palette.length);
    const localPixels = Array(pixelCount).fill(0);
    for (let bit = 0; bit < bits; bit++) {
      const first = reader.readBits(1);
      if (first === 0) {
        for (let i = 0; i < pixelCount; i++) localPixels[i] |= reader.readBits(1) << bit;
        continue;
      }
      const second = reader.readBits(1);
      if (second === 0) {
        readAdaptiveBitplaneRuns(reader, localPixels, bit, pixelCount, false);
        continue;
      }
      const third = reader.readBits(1);
      if (third === 0) {
        readAdaptiveBitplaneRuns(reader, localPixels, bit, pixelCount, true);
        continue;
      }
      switch (reader.readBits(2)) {
        case 0:
          break;
        case 1:
          for (let i = 0; i < pixelCount; i++) localPixels[i] |= 1 << bit;
          break;
        case 2:
          readSparseBitplane(reader, localPixels, bit, pixelCount, 1);
          break;
        case 3:
          for (let i = 0; i < pixelCount; i++) localPixels[i] |= 1 << bit;
          readSparseBitplane(reader, localPixels, bit, pixelCount, 0);
          break;
      }
    }
    return localPixels.map((index) => {
      if (index >= palette.length) {
        throw new MCOImageV3InvalidPayloadError('Adaptive bitplane color index out of range');
      }
      return palette[index];
    });
  }

  function readCompactRowDeltaPredictor(reader) {
    if (reader.readBits(1) === 0) return ROW_DELTA_PREDICTOR_SAME;
    return reader.readBits(1) === 0 ? ROW_DELTA_PREDICTOR_LEFT : ROW_DELTA_PREDICTOR_RIGHT;
  }

  function compactRowDeltaPredictedValue(values, rowLength, row, x, predictor, useVirtualBaseRow) {
    if (row === 0 && useVirtualBaseRow) return 0;
    const previousStart = (row - 1) * rowLength;
    switch (predictor) {
      case ROW_DELTA_PREDICTOR_LEFT:
        return values[previousStart + (x === 0 ? rowLength - 1 : x - 1)];
      case ROW_DELTA_PREDICTOR_RIGHT:
        return values[previousStart + (x + 1 === rowLength ? 0 : x + 1)];
      default:
        return values[previousStart + x];
    }
  }

  function copyCompactRowDeltaPredictedRow(values, rowStart, rowLength, row, predictor, useVirtualBaseRow) {
    for (let x = 0; x < rowLength; x++) {
      values[rowStart + x] = compactRowDeltaPredictedValue(
        values, rowLength, row, x, predictor, useVirtualBaseRow,
      );
    }
  }

  function readRowDeltaValue(reader, valueBits, maxValue) {
    const value = reader.readBits(valueBits);
    if (value > maxValue) throw new MCOImageV3InvalidPayloadError('Row-delta value out of range');
    return value;
  }

  function readRowDeltaPredictor(reader, row, useVirtualBaseRow, allowShiftPredictors) {
    if (!allowShiftPredictors) return ROW_DELTA_PREDICTOR_SAME;
    const predictor = readCompactRowDeltaPredictor(reader);
    if (row === 0 && useVirtualBaseRow && predictor !== ROW_DELTA_PREDICTOR_SAME) {
      throw new MCOImageV3InvalidPayloadError('Shifted row-delta predictor cannot use virtual row');
    }
    return predictor;
  }

  function readRowDeltaMask(reader, result, rowStart, rowLength, valueBits, maxValue, sameScalar) {
    const positions = [];
    for (let x = 0; x < rowLength; x++) if (reader.readBits(1) !== 0) positions.push(x);
    if (positions.length === 0) throw new MCOImageV3InvalidPayloadError('Empty row-delta mask');
    if (sameScalar) {
      const value = readRowDeltaValue(reader, valueBits, maxValue);
      for (const x of positions) result[rowStart + x] = value;
    } else {
      for (const x of positions) result[rowStart + x] = readRowDeltaValue(reader, valueBits, maxValue);
    }
  }

  function readRowDeltaSegments(reader, result, rowStart, rowLength, valueBits, maxValue) {
    const positionBits = bitLength(rowLength - 1);
    const segmentCount = reader.readBits(bitLength(rowLength - 1)) + 1;
    let previousEnd = -1;
    for (let i = 0; i < segmentCount; i++) {
      const start = reader.readBits(positionBits);
      const length = reader.readBits(positionBits) + 1;
      if (start <= previousEnd || start + length > rowLength) {
        throw new MCOImageV3InvalidPayloadError('Invalid row-delta segment');
      }
      for (let x = start; x < start + length; x++) {
        result[rowStart + x] = readRowDeltaValue(reader, valueBits, maxValue);
      }
      previousEnd = start + length - 1;
    }
  }

  function readRowDeltaBody(reader, count, rowLength, valueBits, maxValue) {
    if (rowLength <= 0 || count % rowLength !== 0) {
      throw new MCOImageV3InvalidPayloadError('Invalid row-delta geometry');
    }
    if (count === 0) return [];
    const useVirtualBaseRow = reader.readBits(1) !== 0;
    const allowShiftPredictors = reader.readBits(1) !== 0;
    const result = Array(count).fill(0);
    if (!useVirtualBaseRow) {
      for (let x = 0; x < rowLength; x++) result[x] = readRowDeltaValue(reader, valueBits, maxValue);
    }
    const rowCount = count / rowLength;
    let row = useVirtualBaseRow ? 0 : 1;
    while (row < rowCount) {
      const rowStart = row * rowLength;
      const op = reader.readBits(ROW_DELTA_OP_BITS);
      if (op === ROW_DELTA_OP_RAW) {
        for (let x = 0; x < rowLength; x++) result[rowStart + x] = readRowDeltaValue(reader, valueBits, maxValue);
        row++;
        continue;
      }
      if (op === ROW_DELTA_OP_REPEAT) {
        copyCompactRowDeltaPredictedRow(result, rowStart, rowLength, row, ROW_DELTA_PREDICTOR_SAME, useVirtualBaseRow);
        row++;
        continue;
      }
      if (op === ROW_DELTA_OP_INDEXED) {
        const predictor = readRowDeltaPredictor(reader, row, useVirtualBaseRow, allowShiftPredictors);
        copyCompactRowDeltaPredictedRow(result, rowStart, rowLength, row, predictor, useVirtualBaseRow);
        const changeCount = reader.readBits(bitLength(rowLength));
        if (changeCount > rowLength) {
          throw new MCOImageV3InvalidPayloadError('Row-delta change count exceeds row length');
        }
        const positionBits = bitLength(rowLength - 1);
        let previousX = -1;
        for (let i = 0; i < changeCount; i++) {
          const x = reader.readBits(positionBits);
          if (x >= rowLength || x <= previousX) {
            throw new MCOImageV3InvalidPayloadError('Invalid row-delta change position');
          }
          result[rowStart + x] = readRowDeltaValue(reader, valueBits, maxValue);
          previousX = x;
        }
        row++;
        continue;
      }
      if (op !== ROW_DELTA_OP_EXTENDED) {
        throw new MCOImageV3InvalidPayloadError('Unknown row-delta row op');
      }
      const extendedOp = reader.readBits(ROW_DELTA_EXTENDED_BITS);
      if (extendedOp === ROW_DELTA_EXTENDED_REPEAT_RUN) {
        if (row + 2 > rowCount) throw new MCOImageV3InvalidPayloadError('Invalid row-delta repeat run');
        const repeatCount = reader.readRangeCompactUint(rowCount - row - 2) + 2;
        for (let repeat = 0; repeat < repeatCount; repeat++) {
          const repeatRow = row + repeat;
          copyCompactRowDeltaPredictedRow(
            result, repeatRow * rowLength, rowLength, repeatRow,
            ROW_DELTA_PREDICTOR_SAME, useVirtualBaseRow,
          );
        }
        row += repeatCount;
        continue;
      }
      const predictor = readRowDeltaPredictor(reader, row, useVirtualBaseRow, allowShiftPredictors);
      copyCompactRowDeltaPredictedRow(result, rowStart, rowLength, row, predictor, useVirtualBaseRow);
      switch (extendedOp) {
        case ROW_DELTA_EXTENDED_MASK:
          readRowDeltaMask(reader, result, rowStart, rowLength, valueBits, maxValue, false);
          break;
        case ROW_DELTA_EXTENDED_SEGMENTS:
          readRowDeltaSegments(reader, result, rowStart, rowLength, valueBits, maxValue);
          break;
        case ROW_DELTA_EXTENDED_SAME_SCALAR_MASK:
          readRowDeltaMask(reader, result, rowStart, rowLength, valueBits, maxValue, true);
          break;
        default:
          throw new MCOImageV3InvalidPayloadError('Unknown row-delta extended op');
      }
      row++;
    }
    return result;
  }

  function grayscaleDeltaFromCode(code) {
    if (code <= 0) throw new MCOImageV3InvalidPayloadError('Invalid grayscale delta');
    return (code & 1) !== 0 ? Math.floor((code + 1) / 2) : -Math.floor(code / 2);
  }

  function readCompactRowDeltaValue(
    reader, values, rowLength, row, x, valueBits, predictor,
    useVirtualBaseRow, useResidual, maxValue,
  ) {
    const value = useResidual
      ? compactRowDeltaPredictedValue(values, rowLength, row, x, predictor, useVirtualBaseRow) +
        grayscaleDeltaFromCode(reader.readCompactUint() + 1)
      : reader.readBits(valueBits);
    if (value < 0 || value > maxValue) {
      throw new MCOImageV3InvalidPayloadError('Compact row-delta value out of range');
    }
    return value;
  }

  function readCompactChangePositions(reader, count, rowLength) {
    const positions = [];
    let previousX = -1;
    for (let i = 0; i < count; i++) {
      const remainingPositions = count - i - 1;
      const maxGap = rowLength - previousX - remainingPositions - 2;
      const x = previousX + 1 + reader.readRangeCompactUint(maxGap);
      if (x >= rowLength) {
        throw new MCOImageV3InvalidPayloadError('Compact row-delta position out of range');
      }
      positions.push(x);
      previousX = x;
    }
    return positions;
  }

  function readCompactRowDeltaBody(reader, count, rowLength, valueBits, directGrayscale, maxValue) {
    if (rowLength <= 0 || count % rowLength !== 0) {
      throw new MCOImageV3InvalidPayloadError('Invalid compact row-delta geometry');
    }
    const useVirtualBaseRow = reader.readBits(1) !== 0;
    const result = Array(count).fill(0);
    if (!useVirtualBaseRow) {
      for (let x = 0; x < rowLength; x++) {
        const value = reader.readBits(valueBits);
        if (value > maxValue) {
          throw new MCOImageV3InvalidPayloadError('Compact row-delta first row value out of range');
        }
        result[x] = value;
      }
    }
    const rowCount = count / rowLength;
    let row = useVirtualBaseRow ? 0 : 1;
    while (row < rowCount) {
      const rowStart = row * rowLength;
      const op = reader.readBits(COMPACT_ROW_DELTA_OP_BITS);
      if (op === COMPACT_ROW_DELTA_OP_REPEAT || op === COMPACT_ROW_DELTA_OP_REPEAT_RUN) {
        const repeatCount = op === COMPACT_ROW_DELTA_OP_REPEAT
          ? 1
          : reader.readRangeCompactUint(rowCount - row - 2) + 2;
        if (row + repeatCount > rowCount) {
          throw new MCOImageV3InvalidPayloadError('Compact row-delta repeat exceeds row count');
        }
        for (let repeat = 0; repeat < repeatCount; repeat++) {
          const repeatRow = row + repeat;
          copyCompactRowDeltaPredictedRow(
            result, repeatRow * rowLength, rowLength, repeatRow,
            ROW_DELTA_PREDICTOR_SAME, useVirtualBaseRow,
          );
        }
        row += repeatCount;
        continue;
      }
      if (op === COMPACT_ROW_DELTA_OP_RAW) {
        for (let x = 0; x < rowLength; x++) {
          const value = reader.readBits(valueBits);
          if (value > maxValue) {
            throw new MCOImageV3InvalidPayloadError('Compact row-delta raw value out of range');
          }
          result[rowStart + x] = value;
        }
        row++;
        continue;
      }
      const predictor = readCompactRowDeltaPredictor(reader);
      if (row === 0 && useVirtualBaseRow && predictor !== ROW_DELTA_PREDICTOR_SAME) {
        throw new MCOImageV3InvalidPayloadError('Shifted compact predictor cannot use virtual row');
      }
      copyCompactRowDeltaPredictedRow(result, rowStart, rowLength, row, predictor, useVirtualBaseRow);
      if (op === COMPACT_ROW_DELTA_OP_PREDICTED) {
        row++;
        continue;
      }
      const useResidual = directGrayscale && reader.readBits(1) !== 0;
      if (op === COMPACT_ROW_DELTA_OP_INDEXED || op === COMPACT_ROW_DELTA_OP_SAME_SCALAR) {
        const changeCount = reader.readRangeCompactUint(rowLength - 1) + 1;
        if (changeCount > rowLength) {
          throw new MCOImageV3InvalidPayloadError('Compact row-delta change count exceeds row length');
        }
        const positions = readCompactChangePositions(reader, changeCount, rowLength);
        if (op === COMPACT_ROW_DELTA_OP_SAME_SCALAR) {
          const value = readCompactRowDeltaValue(
            reader, result, rowLength, row, positions[0], valueBits, predictor,
            useVirtualBaseRow, useResidual, maxValue,
          );
          for (const x of positions) result[rowStart + x] = value;
        } else {
          for (const x of positions) {
            result[rowStart + x] = readCompactRowDeltaValue(
              reader, result, rowLength, row, x, valueBits, predictor,
              useVirtualBaseRow, useResidual, maxValue,
            );
          }
        }
        row++;
        continue;
      }
      if (op === COMPACT_ROW_DELTA_OP_SEGMENTS || op === COMPACT_ROW_DELTA_OP_TRIMMED_MASK) {
        const positions = [];
        if (op === COMPACT_ROW_DELTA_OP_SEGMENTS) {
          const segmentCount = reader.readRangeCompactUint(rowLength - 1) + 1;
          if (segmentCount > rowLength) {
            throw new MCOImageV3InvalidPayloadError('Compact row-delta segment count exceeds row length');
          }
          let previousEnd = 0;
          for (let i = 0; i < segmentCount; i++) {
            const remainingSegments = segmentCount - i - 1;
            const maxGap = rowLength - previousEnd - remainingSegments - 1;
            const gap = reader.readRangeCompactUint(maxGap);
            const start = previousEnd + gap;
            const maxLength = rowLength - start - remainingSegments;
            const length = reader.readRangeCompactUint(maxLength - 1) + 1;
            if (start < previousEnd || start + length > rowLength) {
              throw new MCOImageV3InvalidPayloadError('Invalid compact row-delta segment');
            }
            for (let x = start; x < start + length; x++) positions.push(x);
            previousEnd = start + length;
          }
        } else {
          const start = reader.readRangeCompactUint(rowLength - 1);
          const span = reader.readRangeCompactUint(rowLength - start - 1) + 1;
          if (start + span > rowLength) {
            throw new MCOImageV3InvalidPayloadError('Invalid compact row-delta mask bounds');
          }
          for (let offset = 0; offset < span; offset++) if (reader.readBits(1) !== 0) positions.push(start + offset);
          if (positions.length === 0) {
            throw new MCOImageV3InvalidPayloadError('Empty compact row-delta mask');
          }
        }
        for (const x of positions) {
          result[rowStart + x] = readCompactRowDeltaValue(
            reader, result, rowLength, row, x, valueBits, predictor,
            useVirtualBaseRow, useResidual, maxValue,
          );
        }
        row++;
        continue;
      }
      throw new MCOImageV3InvalidPayloadError('Unsupported compact row-delta op');
    }
    return result;
  }

  function readRowRepeat(reader, count, rowLength, bits) {
    if (rowLength <= 0 || count % rowLength !== 0) {
      throw new MCOImageV3InvalidPayloadError('Invalid row-repeat geometry');
    }
    const result = Array(count).fill(0);
    for (let x = 0; x < rowLength; x++) result[x] = reader.readBits(bits);
    const rows = count / rowLength;
    for (let row = 1; row < rows; row++) {
      const rowStart = row * rowLength;
      const previousStart = rowStart - rowLength;
      if (reader.readBits(1) !== 0) {
        for (let x = 0; x < rowLength; x++) result[rowStart + x] = result[previousStart + x];
      } else {
        for (let x = 0; x < rowLength; x++) result[rowStart + x] = reader.readBits(bits);
      }
    }
    return result;
  }

  function decodeBitplanesBody(reader, count, palette) {
    const bits = localBits(palette.length);
    const localPixels = Array(count).fill(0);
    for (let bit = 0; bit < bits; bit++) {
      const isRle = reader.readBits(1) !== 0;
      if (!isRle) {
        for (let i = 0; i < count; i++) localPixels[i] |= reader.readBits(1) << bit;
        continue;
      }
      let value = reader.readBits(1);
      let position = 0;
      while (position < count) {
        const length = reader.readRangeCompactUint(count - position - 1) + 1;
        if (position + length > count) {
          throw new MCOImageV3InvalidPayloadError('Bitplane RLE exceeds pixel count');
        }
        if (value !== 0) for (let i = 0; i < length; i++) localPixels[position + i] |= 1 << bit;
        position += length;
        value ^= 1;
      }
    }
    return localPixels.map((index) => {
      if (index >= palette.length) {
        throw new MCOImageV3InvalidPayloadError('Bitplane color index out of range');
      }
      return palette[index];
    });
  }

  function mapLocalPixels(localPixels, palette, label = 'Shared palette color index out of range') {
    return localPixels.map((index) => {
      if (index >= palette.length) throw new MCOImageV3InvalidPayloadError(label);
      return palette[index];
    });
  }

  function decodeBlockBody(
    reader, width, height, profile, algorithm, scan,
    implicitWhiteBackground, inheritedBackgroundColor = null,
  ) {
    const count = width * height;
    switch (algorithm) {
      case MCOImageV3BlockAlgorithm.rawGlobal: {
        const result = [];
        for (let i = 0; i < count; i++) result.push(readColorRef(reader, profile));
        return result;
      }
      case MCOImageV3BlockAlgorithm.rawLocal: {
        const palette = readLocalPalette(reader, profile);
        const bits = localBits(palette.length);
        const result = [];
        for (let i = 0; i < count; i++) {
          const index = reader.readBits(bits);
          if (index >= palette.length) throw new MCOImageV3InvalidPayloadError('Local color index out of range');
          result.push(palette[index]);
        }
        return result;
      }
      case MCOImageV3BlockAlgorithm.varUintRle:
      case MCOImageV3BlockAlgorithm.compactRle: {
        const palette = readLocalPalette(reader, profile);
        const bits = localBits(palette.length);
        const result = [];
        while (result.length < count) {
          const colorIndex = reader.readBits(bits);
          if (colorIndex >= palette.length) {
            throw new MCOImageV3InvalidPayloadError(
              algorithm === MCOImageV3BlockAlgorithm.varUintRle
                ? 'Varuint RLE color index out of range'
                : 'Compact RLE color index out of range',
            );
          }
          const length = algorithm === MCOImageV3BlockAlgorithm.varUintRle
            ? reader.readBitVarUint()
            : reader.readBoundedCompactUint(count - result.length - 1) + 1;
          if (length <= 0 || result.length + length > count) {
            throw new MCOImageV3InvalidPayloadError('Invalid RLE length');
          }
          for (let i = 0; i < length; i++) result.push(palette[colorIndex]);
        }
        return result;
      }
      case MCOImageV3BlockAlgorithm.lzPixels: {
        const palette = readLocalPalette(reader, profile);
        const bits = localBits(palette.length);
        const result = [];
        while (result.length < count) {
          const isMatch = reader.readBits(1) !== 0;
          if (isMatch) {
            const remaining = count - result.length;
            if (result.length === 0 || remaining < MIN_LZ_MATCH_LENGTH) {
              throw new MCOImageV3InvalidPayloadError('Invalid LZ pixel match');
            }
            const distance = reader.readRangeCompactUint(result.length - 1) + 1;
            const length = reader.readRangeCompactUint(remaining - MIN_LZ_MATCH_LENGTH) + MIN_LZ_MATCH_LENGTH;
            if (distance > result.length || result.length + length > count) {
              throw new MCOImageV3InvalidPayloadError('Invalid LZ pixel match');
            }
            for (let i = 0; i < length; i++) result.push(result[result.length - distance]);
          } else {
            const length = reader.readRangeCompactUint(count - result.length - 1) + 1;
            if (result.length + length > count) {
              throw new MCOImageV3InvalidPayloadError('Invalid LZ pixel literal length');
            }
            for (let i = 0; i < length; i++) {
              const colorIndex = reader.readBits(bits);
              if (colorIndex >= palette.length) {
                throw new MCOImageV3InvalidPayloadError('LZ pixel color index out of range');
              }
              result.push(palette[colorIndex]);
            }
          }
        }
        return result;
      }
      case MCOImageV3BlockAlgorithm.quadtree: {
        if (scan !== ScanMode.h) throw new MCOImageV3InvalidPayloadError('Quadtree requires horizontal scan');
        const palette = readLocalPalette(reader, profile);
        const result = Array(count).fill(palette[0]);
        readQuadtreeNode(reader, result, width, 0, 0, width, height, palette, localBits(palette.length));
        return result;
      }
      case MCOImageV3BlockAlgorithm.bitplanes: {
        const palette = readLocalPalette(reader, profile);
        return decodeBitplanesBody(reader, count, palette);
      }
      case MCOImageV3BlockAlgorithm.adaptiveBitplanes: {
        const palette = readLocalPalette(reader, profile);
        return decodeAdaptiveBitplanesBody(reader, count, palette);
      }
      case MCOImageV3BlockAlgorithm.directBitplanes:
        if (isGrayscaleProfile(profile)) {
          return decodeAdaptiveBitplanesBody(reader, count, Array.from({ length: paletteSize(profile) }, (_, i) => i));
        }
        if (isDynamicProfile(profile)) {
          return decodeAdaptiveBitplanesBody(reader, count, dynamicProfilePalette(profile));
        }
        throw new MCOImageV3InvalidPayloadError('Direct bitplanes require a grayscale or dynamic profile');
      case MCOImageV3BlockAlgorithm.rowDelta: {
        const palette = readLocalPalette(reader, profile);
        const local = readRowDeltaBody(
          reader, count, rowLengthForScan(scan, width, height), localBits(palette.length), palette.length - 1,
        );
        return mapLocalPixels(local, palette, 'Row-delta color index out of range');
      }
      case MCOImageV3BlockAlgorithm.compactRowDelta: {
        const palette = readLocalPalette(reader, profile);
        const local = readCompactRowDeltaBody(
          reader, count, rowLengthForScan(scan, width, height), localBits(palette.length), false, palette.length - 1,
        );
        return mapLocalPixels(local, palette, 'Compact row-delta color index out of range');
      }
      case MCOImageV3BlockAlgorithm.directRowDelta:
        if (isGrayscaleProfile(profile)) {
          return readCompactRowDeltaBody(
            reader, count, rowLengthForScan(scan, width, height), globalBits(profile), true, paletteSize(profile) - 1,
          );
        }
        if (isDynamicProfile(profile)) {
          const profilePixels = readCompactRowDeltaBody(
            reader, count, rowLengthForScan(scan, width, height), globalBits(profile), false, paletteSize(profile) - 1,
          );
          const palette = dynamicProfilePalette(profile);
          return profilePixels.map((index) => palette[index]);
        }
        throw new MCOImageV3InvalidPayloadError('Direct row-delta requires a grayscale or dynamic profile');
      case MCOImageV3BlockAlgorithm.varUintSparse:
      case MCOImageV3BlockAlgorithm.compactSparse: {
        const background = inheritedBackgroundColor == null
          ? readBackgroundRef(reader, profile, implicitWhiteBackground)
          : inheritedBackgroundColor;
        const palette = readLocalPalette(reader, profile);
        if (palette.includes(background)) {
          throw new MCOImageV3InvalidPayloadError('Sparse palette contains background');
        }
        const bits = localBits(palette.length);
        const result = Array(count).fill(background);
        const segmentCount = algorithm === MCOImageV3BlockAlgorithm.varUintSparse
          ? reader.readBitVarUint()
          : reader.readBoundedCompactUint(count - 1) + 1;
        if (segmentCount <= 0 || segmentCount > count) {
          throw new MCOImageV3InvalidPayloadError('Invalid sparse segment count');
        }
        let pos = 0;
        for (let i = 0; i < segmentCount; i++) {
          if (algorithm === MCOImageV3BlockAlgorithm.varUintSparse) {
            const skip = reader.readBitVarUint();
            if (skip > count - pos) throw new MCOImageV3InvalidPayloadError('Invalid varuint sparse skip');
            pos += skip;
            if (pos >= count) throw new MCOImageV3InvalidPayloadError('Invalid varuint sparse segment start');
          } else {
            if (pos >= count) throw new MCOImageV3InvalidPayloadError('Invalid compact sparse segment count');
            pos += reader.readBoundedCompactUint(count - pos - 1);
          }
          const colorIndex = reader.readBits(bits);
          if (colorIndex >= palette.length) {
            throw new MCOImageV3InvalidPayloadError('Sparse color index out of range');
          }
          const length = algorithm === MCOImageV3BlockAlgorithm.varUintSparse
            ? reader.readBitVarUint()
            : reader.readBoundedCompactUint(count - pos - 1) + 1;
          if (length <= 0 || pos + length > count) {
            throw new MCOImageV3InvalidPayloadError('Invalid sparse segment length');
          }
          for (let j = 0; j < length; j++) result[pos + j] = palette[colorIndex];
          pos += length;
        }
        return result;
      }
      case MCOImageV3BlockAlgorithm.biColorMask: {
        const background = inheritedBackgroundColor == null
          ? readBackgroundRef(reader, profile, implicitWhiteBackground)
          : inheritedBackgroundColor;
        const foreground = readColorRef(reader, profile);
        const result = [];
        for (let i = 0; i < count; i++) result.push(reader.readBits(1) !== 0 ? foreground : background);
        return result;
      }
      case MCOImageV3BlockAlgorithm.rowRepeat: {
        const palette = readLocalPalette(reader, profile);
        const local = readRowRepeat(
          reader, count, rowLengthForScan(scan, width, height), localBits(palette.length),
        );
        return mapLocalPixels(local, palette, 'Row-repeat color index out of range');
      }
      default:
        throw new MCOImageV3InvalidPayloadError(`Unsupported MCOimg v3 algorithm ${algorithm}`);
    }
  }

  function decodeBlockBodyWithSharedPalette(
    reader, width, height, algorithm, scan, palette, backgroundColor,
  ) {
    const count = width * height;
    const bits = localBits(palette.length);
    switch (algorithm) {
      case MCOImageV3BlockAlgorithm.rawLocal: {
        const local = [];
        for (let i = 0; i < count; i++) local.push(reader.readBits(bits));
        return mapLocalPixels(local, palette);
      }
      case MCOImageV3BlockAlgorithm.varUintRle:
      case MCOImageV3BlockAlgorithm.compactRle: {
        const result = [];
        while (result.length < count) {
          const colorIndex = reader.readBits(bits);
          if (colorIndex >= palette.length) {
            throw new MCOImageV3InvalidPayloadError('Shared RLE palette index out of range');
          }
          const length = algorithm === MCOImageV3BlockAlgorithm.varUintRle
            ? reader.readBitVarUint()
            : reader.readBoundedCompactUint(count - result.length - 1) + 1;
          if (length <= 0 || result.length + length > count) {
            throw new MCOImageV3InvalidPayloadError('Invalid shared RLE length');
          }
          for (let i = 0; i < length; i++) result.push(palette[colorIndex]);
        }
        return result;
      }
      case MCOImageV3BlockAlgorithm.varUintSparse:
      case MCOImageV3BlockAlgorithm.compactSparse: {
        const segmentCount = algorithm === MCOImageV3BlockAlgorithm.varUintSparse
          ? reader.readBitVarUint()
          : reader.readBoundedCompactUint(count - 1) + 1;
        if (segmentCount <= 0 || segmentCount > count) {
          throw new MCOImageV3InvalidPayloadError('Invalid shared sparse segment count');
        }
        const result = Array(count).fill(backgroundColor);
        let pos = 0;
        for (let i = 0; i < segmentCount; i++) {
          if (algorithm === MCOImageV3BlockAlgorithm.varUintSparse) {
            const skip = reader.readBitVarUint();
            if (skip > count - pos) throw new MCOImageV3InvalidPayloadError('Invalid shared varuint sparse skip');
            pos += skip;
            if (pos >= count) throw new MCOImageV3InvalidPayloadError('Invalid shared varuint sparse segment start');
          } else {
            if (pos >= count) throw new MCOImageV3InvalidPayloadError('Invalid shared compact sparse segment count');
            pos += reader.readBoundedCompactUint(count - pos - 1);
          }
          const colorIndex = reader.readBits(bits);
          if (colorIndex >= palette.length || palette[colorIndex] === backgroundColor) {
            throw new MCOImageV3InvalidPayloadError('Invalid shared sparse color');
          }
          const length = algorithm === MCOImageV3BlockAlgorithm.varUintSparse
            ? reader.readBitVarUint()
            : reader.readBoundedCompactUint(count - pos - 1) + 1;
          if (length <= 0 || pos + length > count) {
            throw new MCOImageV3InvalidPayloadError('Invalid shared sparse segment length');
          }
          for (let j = 0; j < length; j++) result[pos + j] = palette[colorIndex];
          pos += length;
        }
        return result;
      }
      case MCOImageV3BlockAlgorithm.lzPixels: {
        const result = [];
        while (result.length < count) {
          const isMatch = reader.readBits(1) !== 0;
          if (isMatch) {
            const remaining = count - result.length;
            if (result.length === 0 || remaining < MIN_LZ_MATCH_LENGTH) {
              throw new MCOImageV3InvalidPayloadError('Invalid LZ pixel match');
            }
            const distance = reader.readRangeCompactUint(result.length - 1) + 1;
            const length = reader.readRangeCompactUint(remaining - MIN_LZ_MATCH_LENGTH) + MIN_LZ_MATCH_LENGTH;
            if (distance > result.length || result.length + length > count) {
              throw new MCOImageV3InvalidPayloadError('Invalid LZ pixel match');
            }
            for (let i = 0; i < length; i++) result.push(result[result.length - distance]);
          } else {
            const length = reader.readRangeCompactUint(count - result.length - 1) + 1;
            for (let i = 0; i < length; i++) {
              const colorIndex = reader.readBits(bits);
              if (colorIndex >= palette.length) {
                throw new MCOImageV3InvalidPayloadError('LZ shared palette index out of range');
              }
              result.push(palette[colorIndex]);
            }
          }
        }
        return result;
      }
      case MCOImageV3BlockAlgorithm.quadtree: {
        if (scan !== ScanMode.h) throw new MCOImageV3InvalidPayloadError('Quadtree requires horizontal scan');
        const result = Array(count).fill(palette[0]);
        readQuadtreeNode(reader, result, width, 0, 0, width, height, palette, bits);
        return result;
      }
      case MCOImageV3BlockAlgorithm.bitplanes:
        return decodeBitplanesBody(reader, count, palette);
      case MCOImageV3BlockAlgorithm.adaptiveBitplanes:
        return decodeAdaptiveBitplanesBody(reader, count, palette);
      case MCOImageV3BlockAlgorithm.rowDelta:
        return mapLocalPixels(
          readRowDeltaBody(reader, count, rowLengthForScan(scan, width, height), bits, palette.length - 1),
          palette,
        );
      case MCOImageV3BlockAlgorithm.compactRowDelta:
        return mapLocalPixels(
          readCompactRowDeltaBody(reader, count, rowLengthForScan(scan, width, height), bits, false, palette.length - 1),
          palette,
        );
      case MCOImageV3BlockAlgorithm.biColorMask: {
        const foregroundIndex = reader.readBits(bits);
        if (foregroundIndex >= palette.length) {
          throw new MCOImageV3InvalidPayloadError('Invalid shared bi-color foreground');
        }
        const foreground = palette[foregroundIndex];
        if (foreground === backgroundColor) {
          throw new MCOImageV3InvalidPayloadError('Shared bi-color foreground equals background');
        }
        const result = [];
        for (let i = 0; i < count; i++) result.push(reader.readBits(1) !== 0 ? foreground : backgroundColor);
        return result;
      }
      case MCOImageV3BlockAlgorithm.rowRepeat:
        return mapLocalPixels(
          readRowRepeat(reader, count, rowLengthForScan(scan, width, height), bits),
          palette,
        );
      default:
        throw new MCOImageV3InvalidPayloadError(
          'MCOimg v3 algorithm cannot use a shared region palette',
        );
    }
  }

  function decodeBoundsBlockBody(
    reader, width, height, profile, algorithm, scan,
    compactGeometry, implicitWhiteBackground,
  ) {
    const background = readBackgroundRef(reader, profile, implicitWhiteBackground);
    const bounds = readRegionGeometry(reader, width, height, compactGeometry);
    const croppedLinear = decodeBlockBody(
      reader, bounds.width, bounds.height, profile, algorithm, scan,
      implicitWhiteBackground, background,
    );
    const cropped = fromScanOrder(croppedLinear, bounds.width, bounds.height, scan);
    const pixels = Array(width * height).fill(background);
    for (let row = 0; row < bounds.height; row++) {
      const srcStart = row * bounds.width;
      const dstStart = (bounds.y + row) * width + bounds.x;
      for (let col = 0; col < bounds.width; col++) pixels[dstStart + col] = cropped[srcStart + col];
    }
    return pixels;
  }

  function decodeRegionsBody(
    reader, width, height, profile, regionCountContext,
    compactGeometry, implicitWhiteBackground,
  ) {
    const background = readBackgroundRef(reader, profile, implicitWhiteBackground);
    const regionCount = regionCountContext + 1;
    if (regionCount > MAX_REGIONS) throw new MCOImageV3InvalidPayloadError('Invalid v3 region count');
    const hasCommonBlockHeader = compactGeometry && reader.readBits(1) !== 0;
    const hasDeltaGeometry = compactGeometry && reader.readBits(1) !== 0;
    const hasSharedLocalPalette = compactGeometry && reader.readBits(1) !== 0;
    let hasHybridCommonHeader = false;
    let commonAlgorithm = null;
    let commonScan = null;
    if (hasCommonBlockHeader) {
      const commonAlgorithmId = reader.readBits(5);
      hasHybridCommonHeader = commonAlgorithmId === HYBRID_COMMON_REGION_ALGORITHM_MARKER;
      commonAlgorithm = algorithmFromId(hasHybridCommonHeader ? reader.readBits(5) : commonAlgorithmId);
      commonScan = canUseCompactBlockHeader(commonAlgorithm) ? ScanMode.h : scanFromId(reader.readBits(2));
    }
    const sharedLocalPalette = hasSharedLocalPalette ? readLocalPalette(reader, profile) : null;
    const pixels = Array(width * height).fill(background);
    let previousBounds = null;
    for (let i = 0; i < regionCount; i++) {
      const bounds = hasDeltaGeometry && i > 0
        ? readDeltaRegionGeometry(reader, previousBounds, width, height)
        : readRegionGeometry(reader, width, height, compactGeometry);
      previousBounds = bounds;
      const hasIndividualHeader = hasHybridCommonHeader ? reader.readBits(1) !== 0 : !hasCommonBlockHeader;
      const algorithm = hasIndividualHeader ? algorithmFromId(reader.readBits(5)) : commonAlgorithm;
      const scan = hasIndividualHeader
        ? (canUseCompactBlockHeader(algorithm) ? ScanMode.h : scanFromId(reader.readBits(2)))
        : commonScan;
      const linear = sharedLocalPalette == null
        ? decodeBlockBody(
          reader, bounds.width, bounds.height, profile, algorithm, scan,
          implicitWhiteBackground, background,
        )
        : decodeBlockBodyWithSharedPalette(
          reader, bounds.width, bounds.height, algorithm, scan,
          sharedLocalPalette, background,
        );
      const regionPixels = fromScanOrder(linear, bounds.width, bounds.height, scan);
      for (let row = 0; row < bounds.height; row++) {
        const srcStart = row * bounds.width;
        const dstStart = (bounds.y + row) * width + bounds.x;
        for (let col = 0; col < bounds.width; col++) pixels[dstStart + col] = regionPixels[srcStart + col];
      }
    }
    return pixels;
  }

  function decodeSolidRectsBody(
    reader, width, height, profile, rectCountContext, implicitWhiteBackground,
  ) {
    const background = readBackgroundRef(reader, profile, implicitWhiteBackground);
    const palette = readLocalPalette(reader, profile);
    const bits = localBits(palette.length);
    const rectCount = rectCountContext + (reader.readBits(1) << 5) + 1;
    if (rectCount > 64) throw new MCOImageV3InvalidPayloadError('Invalid solid rect count');
    const pixels = Array(width * height).fill(background);
    for (let i = 0; i < rectCount; i++) {
      const bounds = readRegionGeometry(reader, width, height, true);
      const colorIndex = reader.readBits(bits);
      if (colorIndex >= palette.length) {
        throw new MCOImageV3InvalidPayloadError('Solid rect color index out of range');
      }
      for (let row = 0; row < bounds.height; row++) {
        const start = (bounds.y + row) * width + bounds.x;
        for (let col = 0; col < bounds.width; col++) pixels[start + col] = palette[colorIndex];
      }
    }
    return pixels;
  }

  // ---------------------------------------------------------------------------
  // MCOimg v3 encoder (Normal / High). Extreme search and worker partitioning
  // are added in the following porting step; the wire writers and candidate
  // builders below are shared by all levels.

  const NORMAL_MAX_REGIONS = 12;
  const MAX_FREQUENT_BACKGROUND_CANDIDATES = 8;
  const MAX_NORMAL_BACKGROUND_CANDIDATES = 4;
  const MAX_EXHAUSTIVE_BACKGROUND_COLORS = 64;
  const MAX_EXHAUSTIVE_BACKGROUND_PIXELS = 4096;
  const MAX_BEAM_REGION_PIXELS = 4096;
  const REGION_BEAM_WIDTH = 3;
  const REGION_BEAM_DEPTH = 2;
  const REGION_BEAM_NEIGHBORS = 8;
  const MAX_EXTREME_REGION_PIXELS = 1536;
  const MAX_EXTREME_REGION_COMPONENTS = 20;
  const MAX_EXTREME_REGION_BACKGROUND_RANK = 5;
  const MAX_EXTREME_REGION_SEARCH_REGIONS = 20;
  const EXTREME_REGION_BEAM_WIDTH = 10;
  const EXTREME_REGION_BEAM_DEPTH = 8;
  const EXTREME_REGION_NEIGHBORS = 32;
  const EXTREME_REGION_RESULT_LIMIT = 10;
  const EXTREME_REGION_EXACT_RERANK_POOL_SIZE = 32;
  const EXTREME_REGION_EVALUATION_BUDGET = 1536;
  const MAX_LZ_MATCH_CANDIDATES = 48;
  const MAX_OPTIMAL_LZ_PIXELS = 1024;

  const ImageMode = Object.freeze({
    rawGlobal: 0,
    rawLocal: 1,
    rleLocal: 2,
    sparseBg: 3,
    regionsBg: 4,
    biColorMask: 5,
    rowDelta: 6,
    rowRepeat: 7,
    extended: 8,
  });
  const ImageModeName = Object.freeze([
    'rawGlobal', 'rawLocal', 'rleLocal', 'sparseBg', 'regionsBg',
    'biColorMask', 'rowDelta', 'rowRepeat', 'extended',
  ]);

  const NORMAL_BLOCK_ALGORITHMS = Object.freeze([
    MCOImageV3BlockAlgorithm.rawGlobal,
    MCOImageV3BlockAlgorithm.rawLocal,
    MCOImageV3BlockAlgorithm.compactRle,
    MCOImageV3BlockAlgorithm.varUintRle,
    MCOImageV3BlockAlgorithm.lzPixels,
    MCOImageV3BlockAlgorithm.quadtree,
    MCOImageV3BlockAlgorithm.bitplanes,
    MCOImageV3BlockAlgorithm.adaptiveBitplanes,
    MCOImageV3BlockAlgorithm.compactRowDelta,
    MCOImageV3BlockAlgorithm.rowDelta,
    MCOImageV3BlockAlgorithm.rowRepeat,
    MCOImageV3BlockAlgorithm.compactSparse,
    MCOImageV3BlockAlgorithm.varUintSparse,
    MCOImageV3BlockAlgorithm.biColorMask,
  ]);
  const FULL_BLOCK_ALGORITHMS = Object.freeze([
    MCOImageV3BlockAlgorithm.rawGlobal,
    MCOImageV3BlockAlgorithm.rawLocal,
    MCOImageV3BlockAlgorithm.compactRle,
    MCOImageV3BlockAlgorithm.varUintRle,
    MCOImageV3BlockAlgorithm.lzPixels,
    MCOImageV3BlockAlgorithm.quadtree,
    MCOImageV3BlockAlgorithm.bitplanes,
    MCOImageV3BlockAlgorithm.adaptiveBitplanes,
    MCOImageV3BlockAlgorithm.directBitplanes,
    MCOImageV3BlockAlgorithm.compactRowDelta,
    MCOImageV3BlockAlgorithm.directRowDelta,
    MCOImageV3BlockAlgorithm.rowDelta,
    MCOImageV3BlockAlgorithm.rowRepeat,
    MCOImageV3BlockAlgorithm.compactSparse,
    MCOImageV3BlockAlgorithm.varUintSparse,
    MCOImageV3BlockAlgorithm.biColorMask,
  ]);
  const NORMAL_TOP_LEVEL_BACKGROUND_INDEPENDENT = Object.freeze([
    MCOImageV3BlockAlgorithm.rawGlobal,
    MCOImageV3BlockAlgorithm.rawLocal,
    MCOImageV3BlockAlgorithm.compactRle,
    MCOImageV3BlockAlgorithm.varUintRle,
    MCOImageV3BlockAlgorithm.lzPixels,
    MCOImageV3BlockAlgorithm.quadtree,
    MCOImageV3BlockAlgorithm.rowRepeat,
  ]);
  const FULL_TOP_LEVEL_BACKGROUND_INDEPENDENT = Object.freeze([
    MCOImageV3BlockAlgorithm.rawGlobal,
    MCOImageV3BlockAlgorithm.rawLocal,
    MCOImageV3BlockAlgorithm.compactRle,
    MCOImageV3BlockAlgorithm.varUintRle,
    MCOImageV3BlockAlgorithm.lzPixels,
    MCOImageV3BlockAlgorithm.quadtree,
    MCOImageV3BlockAlgorithm.directBitplanes,
    MCOImageV3BlockAlgorithm.directRowDelta,
    MCOImageV3BlockAlgorithm.rowRepeat,
  ]);
  const TOP_LEVEL_BACKGROUND_SENSITIVE = Object.freeze([
    MCOImageV3BlockAlgorithm.bitplanes,
    MCOImageV3BlockAlgorithm.adaptiveBitplanes,
    MCOImageV3BlockAlgorithm.rowDelta,
    MCOImageV3BlockAlgorithm.compactRowDelta,
    MCOImageV3BlockAlgorithm.compactSparse,
    MCOImageV3BlockAlgorithm.varUintSparse,
    MCOImageV3BlockAlgorithm.biColorMask,
  ]);
  const NORMAL_REGION_BLOCK_ALGORITHMS = Object.freeze([
    MCOImageV3BlockAlgorithm.rawLocal,
    MCOImageV3BlockAlgorithm.compactRle,
    MCOImageV3BlockAlgorithm.varUintRle,
    MCOImageV3BlockAlgorithm.lzPixels,
    MCOImageV3BlockAlgorithm.quadtree,
    MCOImageV3BlockAlgorithm.bitplanes,
    MCOImageV3BlockAlgorithm.adaptiveBitplanes,
    MCOImageV3BlockAlgorithm.compactRowDelta,
    MCOImageV3BlockAlgorithm.rowDelta,
    MCOImageV3BlockAlgorithm.rowRepeat,
    MCOImageV3BlockAlgorithm.compactSparse,
    MCOImageV3BlockAlgorithm.varUintSparse,
    MCOImageV3BlockAlgorithm.biColorMask,
  ]);
  const FULL_REGION_BLOCK_ALGORITHMS = Object.freeze([
    MCOImageV3BlockAlgorithm.rawGlobal,
    MCOImageV3BlockAlgorithm.rawLocal,
    MCOImageV3BlockAlgorithm.compactRle,
    MCOImageV3BlockAlgorithm.varUintRle,
    MCOImageV3BlockAlgorithm.lzPixels,
    MCOImageV3BlockAlgorithm.quadtree,
    MCOImageV3BlockAlgorithm.bitplanes,
    MCOImageV3BlockAlgorithm.adaptiveBitplanes,
    MCOImageV3BlockAlgorithm.directBitplanes,
    MCOImageV3BlockAlgorithm.compactRowDelta,
    MCOImageV3BlockAlgorithm.directRowDelta,
    MCOImageV3BlockAlgorithm.rowDelta,
    MCOImageV3BlockAlgorithm.rowRepeat,
    MCOImageV3BlockAlgorithm.compactSparse,
    MCOImageV3BlockAlgorithm.varUintSparse,
    MCOImageV3BlockAlgorithm.biColorMask,
  ]);
  const NORMAL_SHARED_REGION_ALGORITHMS = NORMAL_REGION_BLOCK_ALGORITHMS;
  const FULL_SHARED_REGION_ALGORITHMS = Object.freeze([
    MCOImageV3BlockAlgorithm.rawLocal,
    MCOImageV3BlockAlgorithm.compactRle,
    MCOImageV3BlockAlgorithm.varUintRle,
    MCOImageV3BlockAlgorithm.compactSparse,
    MCOImageV3BlockAlgorithm.varUintSparse,
    MCOImageV3BlockAlgorithm.lzPixels,
    MCOImageV3BlockAlgorithm.quadtree,
    MCOImageV3BlockAlgorithm.bitplanes,
    MCOImageV3BlockAlgorithm.adaptiveBitplanes,
    MCOImageV3BlockAlgorithm.compactRowDelta,
    MCOImageV3BlockAlgorithm.rowDelta,
    MCOImageV3BlockAlgorithm.rowRepeat,
    MCOImageV3BlockAlgorithm.biColorMask,
  ]);
  const REGION_COST_BLOCK_ALGORITHMS = Object.freeze([
    MCOImageV3BlockAlgorithm.rawLocal,
    MCOImageV3BlockAlgorithm.compactRle,
    MCOImageV3BlockAlgorithm.lzPixels,
    MCOImageV3BlockAlgorithm.compactSparse,
    MCOImageV3BlockAlgorithm.bitplanes,
    MCOImageV3BlockAlgorithm.adaptiveBitplanes,
    MCOImageV3BlockAlgorithm.rowDelta,
    MCOImageV3BlockAlgorithm.rowRepeat,
    MCOImageV3BlockAlgorithm.biColorMask,
  ]);

  const NORMAL_REGION_OPTIONS = Object.freeze([
    { commonBlockHeader: false, hybridCommonHeader: false, deltaGeometry: false, sharedLocalPalette: false },
    { commonBlockHeader: false, hybridCommonHeader: false, deltaGeometry: true, sharedLocalPalette: false },
    { commonBlockHeader: false, hybridCommonHeader: false, deltaGeometry: false, sharedLocalPalette: true },
    { commonBlockHeader: false, hybridCommonHeader: false, deltaGeometry: true, sharedLocalPalette: true },
    { commonBlockHeader: true, hybridCommonHeader: false, deltaGeometry: false, sharedLocalPalette: false },
    { commonBlockHeader: true, hybridCommonHeader: false, deltaGeometry: true, sharedLocalPalette: false },
    { commonBlockHeader: true, hybridCommonHeader: false, deltaGeometry: false, sharedLocalPalette: true },
    { commonBlockHeader: true, hybridCommonHeader: false, deltaGeometry: true, sharedLocalPalette: true },
  ]);
  const FULL_REGION_OPTIONS = Object.freeze([
    ...NORMAL_REGION_OPTIONS,
    { commonBlockHeader: true, hybridCommonHeader: true, deltaGeometry: false, sharedLocalPalette: false },
    { commonBlockHeader: true, hybridCommonHeader: true, deltaGeometry: true, sharedLocalPalette: false },
    { commonBlockHeader: true, hybridCommonHeader: true, deltaGeometry: false, sharedLocalPalette: true },
    { commonBlockHeader: true, hybridCommonHeader: true, deltaGeometry: true, sharedLocalPalette: true },
  ]);

  class BitWriter {
    constructor() {
      this.bytes = [];
      this.current = 0;
      this.bitOffset = 0;
    }

    get bitLength() { return this.bytes.length * 8 + this.bitOffset; }

    writeBits(value, bits) {
      if (!Number.isInteger(bits) || bits < 0 || bits > 32) {
        throw new MCOImageV3InvalidInputError('Invalid bit length');
      }
      if (bits === 0) return this;
      if (!Number.isInteger(value) || value < 0 || value >= 2 ** bits) {
        throw new MCOImageV3InvalidInputError('Value does not fit bits');
      }
      let remaining = bits;
      let sourceShift = 0;
      while (remaining > 0) {
        const take = Math.min(8 - this.bitOffset, remaining);
        const mask = 2 ** take - 1;
        this.current |= ((Math.floor(value / (2 ** sourceShift)) & mask) << this.bitOffset);
        this.bitOffset += take;
        sourceShift += take;
        remaining -= take;
        if (this.bitOffset === 8) {
          this.bytes.push(this.current & 0xff);
          this.current = 0;
          this.bitOffset = 0;
        }
      }
      return this;
    }

    writeBitStream(bytesLike, sourceBitLength) {
      const bytes = asBytes(bytesLike, 'source bitstream');
      if (!Number.isInteger(sourceBitLength) || sourceBitLength < 0 || sourceBitLength > bytes.length * 8) {
        throw new MCOImageV3InvalidInputError('Invalid source bitstream length');
      }
      let remaining = sourceBitLength;
      let index = 0;
      while (remaining > 0) {
        const take = Math.min(8, remaining);
        this.writeBits(bytes[index] & (2 ** take - 1), take);
        remaining -= take;
        index++;
      }
      return this;
    }

    writeZeroBits(bits) {
      if (!Number.isInteger(bits) || bits < 0) throw new MCOImageV3InvalidInputError('Invalid bit length');
      while (bits > 0) {
        const take = Math.min(bits, 32);
        this.writeBits(0, take);
        bits -= take;
      }
      return this;
    }

    alignToByte() {
      if (this.bitOffset !== 0) {
        this.bytes.push(this.current & 0xff);
        this.current = 0;
        this.bitOffset = 0;
      }
      return this;
    }

    writeAlignedByte(value) {
      this.alignToByte();
      this.bytes.push(value & 0xff);
      return this;
    }

    writeBitVarUint(value) {
      if (!Number.isInteger(value) || value < 0) throw new MCOImageV3InvalidInputError('Negative varuint');
      let remaining = value;
      do {
        let byte = remaining & 0x7f;
        remaining = Math.floor(remaining / 128);
        if (remaining !== 0) byte |= 0x80;
        this.writeBits(byte, 8);
      } while (remaining !== 0);
      return this;
    }

    writeRangeCompactUint(value, maxValue) {
      if (!Number.isInteger(maxValue) || !Number.isInteger(value) || maxValue < 0 || value < 0 || value > maxValue) {
        throw new MCOImageV3InvalidInputError('Range compact uint is out of range');
      }
      if (maxValue <= 7) return this.writeBits(value, bitLength(maxValue));
      return this.writeCompactUint(value);
    }

    writeBoundedCompactUint(value, maxValue) {
      if (!Number.isInteger(maxValue) || !Number.isInteger(value) || maxValue < 0 || value < 0 || value > maxValue) {
        throw new MCOImageV3InvalidInputError('Bounded compact uint is out of range');
      }
      if (maxValue <= 7) return this.writeBits(value, bitLength(maxValue));
      if (value <= 3) return this.writeBits(0, 1).writeBits(value, 2);
      if (value <= 19) return this.writeBits(1, 2).writeBits(value - 4, 4);
      if (value <= 275) return this.writeBits(3, 3).writeBits(value - 20, 8);
      this.writeBits(7, 3);
      return this.writeBits(value - 276, bitLength(maxValue - 276));
    }

    writeCompactUint(value) {
      if (!Number.isInteger(value) || value < 0) throw new MCOImageV3InvalidInputError('Negative compact uint');
      if (value <= 3) return this.writeBits(0, 1).writeBits(value, 2);
      if (value <= 19) return this.writeBits(1, 2).writeBits(value - 4, 4);
      if (value <= 275) return this.writeBits(3, 3).writeBits(value - 20, 8);
      return this.writeBits(7, 3).writeBitVarUint(value);
    }

    toBytes() {
      this.alignToByte();
      return Uint8Array.from(this.bytes);
    }
  }

  function normalizeCompressionLevel(level) {
    if (typeof level === 'string') {
      const normalized = level.trim().toLowerCase();
      if (normalized === 'normal') return MCOImageV3CompressionLevel.normal;
      if (normalized === 'extreme') return MCOImageV3CompressionLevel.extreme;
      return MCOImageV3CompressionLevel.high;
    }
    if (level === MCOImageV3CompressionLevel.normal) return level;
    if (level === MCOImageV3CompressionLevel.extreme) return level;
    return MCOImageV3CompressionLevel.high;
  }

  function colorRefForProfile(profile, color) {
    if (!Number.isInteger(color)) throw new MCOImageV3InvalidInputError('Color must be an integer');
    if (!isDynamicProfile(profile)) {
      if (color < 0 || color >= paletteSize(profile)) {
        throw new MCOImageV3InvalidInputError(`Color ${color} is not available in ${PaletteProfileName[profile]}`);
      }
      return color;
    }
    const palette = DynamicGlobalIndices[profile];
    const ref = palette.indexOf(color);
    if (ref < 0) {
      throw new MCOImageV3InvalidInputError(`Color ${color} is not available in ${PaletteProfileName[profile]}`);
    }
    return ref;
  }

  function isColorValid(profile, color) {
    try { colorRefForProfile(profile, color); return true; } catch (_) { return false; }
  }

  function validateImageForEncode(imageLike) {
    if (!imageLike || typeof imageLike !== 'object') throw new MCOImageV3InvalidInputError('image is required');
    const width = Number(imageLike.width);
    const height = Number(imageLike.height);
    if (!Number.isInteger(width) || !Number.isInteger(height) || width < MIN_SIZE || height < MIN_SIZE || width > MAX_SIZE || height > MAX_SIZE) {
      throw new MCOImageV3InvalidInputError('Image size must be 1..256 in both axes');
    }
    const profile = Number(imageLike.paletteProfile);
    if (!Number.isInteger(profile) || profile < 0 || profile >= PaletteProfileName.length) {
      throw new MCOImageV3InvalidInputError('Unknown MCOimg v3 palette profile');
    }
    const pixels = Array.from(imageLike.pixels || []);
    if (pixels.length !== width * height) throw new MCOImageV3InvalidInputError('Invalid pixel count');
    for (const pixel of pixels) colorRefForProfile(profile, pixel);
    const transparentColor = imageLike.transparentColor == null ? null : Number(imageLike.transparentColor);
    if (transparentColor != null) colorRefForProfile(profile, transparentColor);
    return new MCOImageV3({ width, height, paletteProfile: profile, pixels, transparentColor });
  }

  function writeColorRef(writer, profile, color) {
    return writer.writeBits(colorRefForProfile(profile, color), globalBits(profile));
  }

  function isImplicitWhiteBackground(profile, color) {
    return color === whiteIndexFor(profile);
  }

  function writeBackgroundRef(writer, profile, color, implicitWhiteBackground) {
    if (!implicitWhiteBackground) writeColorRef(writer, profile, color);
  }

  function containerContextByte(container, context) {
    if (!Number.isInteger(container) || container < 0 || container >= 8) {
      throw new MCOImageV3InvalidInputError('MCOimg v3 container id does not fit');
    }
    if (!Number.isInteger(context) || context < 0 || context > CONTAINER_CONTEXT_MASK) {
      throw new MCOImageV3InvalidInputError('MCOimg v3 container context does not fit');
    }
    return (container << CONTAINER_CONTEXT_CONTAINER_SHIFT) | context;
  }

  function writeDimensions(writer, width, height) {
    if (width === height && width <= 64) {
      writer.writeBits(DIMENSION_MODE_SQUARE64, 2).writeBits(width - 1, 6);
      return;
    }
    if (width <= 32 && height <= 32) {
      writer.writeBits(DIMENSION_MODE_SMALL32, 2).writeBits(width - 1, 5).writeBits(height - 1, 5);
      return;
    }
    if (width <= 64 && height <= 64) {
      writer.writeBits(DIMENSION_MODE_MEDIUM64, 2).writeBits(width - 1, 6).writeBits(height - 1, 6);
      return;
    }
    writer.writeBits(DIMENSION_MODE_EXTENDED, 2);
    if (width === height) writer.writeBits(0, 1).writeBits(width - 1, 8);
    else writer.writeBits(1, 1).writeBits(width - 1, 8).writeBits(height - 1, 8);
  }

  function writeImagePreamble(writer, image, scan, implicitWhiteBackground, container, context) {
    const header = (image.transparentColor == null ? 0 : TRANSPARENT_FLAG) |
      (implicitWhiteBackground ? IMPLICIT_WHITE_BACKGROUND_FLAG : 0) |
      (scan << SCAN_SHIFT) |
      image.paletteProfile;
    writer.writeAlignedByte(header);
    writeDimensions(writer, image.width, image.height);
    writer.writeBits(containerContextByte(container, context), 8);
  }

  function writeRegionGeometry(writer, bounds, imageWidth, imageHeight, compactGeometry) {
    if (!bounds || bounds.x < 0 || bounds.y < 0 || bounds.width <= 0 || bounds.height <= 0 ||
        bounds.x + bounds.width > imageWidth || bounds.y + bounds.height > imageHeight) {
      throw new MCOImageV3InvalidInputError('Invalid v3 region geometry');
    }
    const xBits = compactGeometry ? geometryBits(imageWidth) : 8;
    const yBits = compactGeometry ? geometryBits(imageHeight) : 8;
    writer.writeBits(bounds.x, xBits).writeBits(bounds.y, yBits);
    if (!compactGeometry) {
      writer.writeBits(bounds.width - 1, xBits).writeBits(bounds.height - 1, yBits);
    } else {
      writer.writeBits(bounds.width - 1, geometryBits(imageWidth - bounds.x));
      writer.writeBits(bounds.height - 1, geometryBits(imageHeight - bounds.y));
    }
  }

  function writeSignedCompactInt(writer, value) {
    writer.writeCompactUint(value < 0 ? (-value * 2) - 1 : value * 2);
  }

  function writeDeltaRegionGeometry(writer, bounds, previous) {
    writeSignedCompactInt(writer, bounds.x - previous.x);
    writeSignedCompactInt(writer, bounds.y - previous.y);
    writeSignedCompactInt(writer, bounds.width - previous.width);
    writeSignedCompactInt(writer, bounds.height - previous.height);
  }

  function toScanOrder(pixels, width, height, scan) {
    if (scan === ScanMode.h) return Array.from(pixels);
    const result = [];
    if (scan === ScanMode.v) {
      for (let x = 0; x < width; x++) for (let y = 0; y < height; y++) result.push(pixels[y * width + x]);
    } else if (scan === ScanMode.s) {
      for (let y = 0; y < height; y++) {
        if ((y & 1) === 0) for (let x = 0; x < width; x++) result.push(pixels[y * width + x]);
        else for (let x = width - 1; x >= 0; x--) result.push(pixels[y * width + x]);
      }
    } else if (scan === ScanMode.sv) {
      for (let x = 0; x < width; x++) {
        if ((x & 1) === 0) for (let y = 0; y < height; y++) result.push(pixels[y * width + x]);
        else for (let y = height - 1; y >= 0; y--) result.push(pixels[y * width + x]);
      }
    } else throw new MCOImageV3InvalidInputError('Unknown scan mode');
    return result;
  }

  function extractBoundsPixels(image, bounds) {
    const result = [];
    for (let y = 0; y < bounds.height; y++) {
      const start = (bounds.y + y) * image.width + bounds.x;
      for (let x = 0; x < bounds.width; x++) result.push(image.pixels[start + x]);
    }
    return result;
  }

  function boundsForBackground(image, backgroundColor) {
    let minX = image.width, minY = image.height, maxX = -1, maxY = -1;
    for (let y = 0; y < image.height; y++) {
      for (let x = 0; x < image.width; x++) {
        if (image.pixels[y * image.width + x] === backgroundColor) continue;
        minX = Math.min(minX, x); minY = Math.min(minY, y);
        maxX = Math.max(maxX, x); maxY = Math.max(maxY, y);
      }
    }
    if (maxX < minX || maxY < minY) return null;
    return { x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1,
      area: (maxX - minX + 1) * (maxY - minY + 1) };
  }

  function localPalette(pixels) {
    const counts = new Map();
    for (const pixel of pixels) counts.set(pixel, (counts.get(pixel) || 0) + 1);
    const colors = Array.from(counts.keys()).sort((a, b) => (counts.get(b) - counts.get(a)) || (a - b));
    if (colors.length === 0) throw new MCOImageV3InvalidInputError('Empty local palette');
    return colors;
  }

  let activeLocalIndexMapCache = null;
  let activeLocalPixelsCache = null;
  let activeRunCache = null;
  let activeSparseAnalysisCache = null;
  let activeLocalPaletteVariantCache = null;
  let activeLzTokenCache = null;

  function valueListCacheKey(values) {
    return values.join('.');
  }

  function localIndexMap(palette) {
    const key = activeLocalIndexMapCache == null ? null : valueListCacheKey(palette);
    if (key != null && activeLocalIndexMapCache.has(key)) return activeLocalIndexMapCache.get(key);
    const result = new Map(palette.map((color, index) => [color, index]));
    if (key != null) activeLocalIndexMapCache.set(key, result);
    return result;
  }

  function mapPixelsToPalette(pixels, palette) {
    const key = activeLocalPixelsCache == null ? null : `${valueListCacheKey(pixels)}|${valueListCacheKey(palette)}`;
    if (key != null && activeLocalPixelsCache.has(key)) return activeLocalPixelsCache.get(key);
    const map = localIndexMap(palette);
    const result = pixels.map((color) => {
      const index = map.get(color);
      if (index == null) throw new MCOImageV3InvalidInputError('Local palette is missing a color');
      return index;
    });
    if (key != null) activeLocalPixelsCache.set(key, result);
    return result;
  }

  function buildRuns(pixels) {
    const key = activeRunCache == null ? null : valueListCacheKey(pixels);
    if (key != null && activeRunCache.has(key)) return activeRunCache.get(key);
    if (pixels.length === 0) return [];
    const runs = [];
    let color = pixels[0], length = 1;
    for (let i = 1; i < pixels.length; i++) {
      if (pixels[i] === color) length++;
      else { runs.push({ color, length }); color = pixels[i]; length = 1; }
    }
    runs.push({ color, length });
    if (key != null) activeRunCache.set(key, runs);
    return runs;
  }

  function buildSparseSegments(pixels, backgroundColor) {
    const segments = [];
    let index = 0;
    while (index < pixels.length) {
      if (pixels[index] === backgroundColor) { index++; continue; }
      const start = index;
      const color = pixels[index++];
      while (index < pixels.length && pixels[index] === color) index++;
      segments.push({ start, color, length: index - start });
    }
    return segments;
  }

  function sparseAnalysis(pixels, backgroundColor) {
    const key = activeSparseAnalysisCache == null ? null : `${backgroundColor}|${valueListCacheKey(pixels)}`;
    if (key != null && activeSparseAnalysisCache.has(key)) return activeSparseAnalysisCache.get(key);
    const foregroundColors = Array.from(new Set(pixels.filter((color) => color !== backgroundColor))).sort((a, b) => a - b);
    const result = { segments: buildSparseSegments(pixels, backgroundColor), foregroundColors };
    if (key != null) activeSparseAnalysisCache.set(key, result);
    return result;
  }

  function imageModeForAlgorithm(algorithm) {
    switch (algorithm) {
      case MCOImageV3BlockAlgorithm.rawGlobal: return ImageMode.rawGlobal;
      case MCOImageV3BlockAlgorithm.rawLocal: return ImageMode.rawLocal;
      case MCOImageV3BlockAlgorithm.compactRle:
      case MCOImageV3BlockAlgorithm.varUintRle: return ImageMode.rleLocal;
      case MCOImageV3BlockAlgorithm.compactSparse:
      case MCOImageV3BlockAlgorithm.varUintSparse: return ImageMode.sparseBg;
      case MCOImageV3BlockAlgorithm.biColorMask: return ImageMode.biColorMask;
      case MCOImageV3BlockAlgorithm.rowRepeat: return ImageMode.rowRepeat;
      case MCOImageV3BlockAlgorithm.rowDelta: return ImageMode.rowDelta;
      default: return ImageMode.extended;
    }
  }

  function modeTieRank(mode) {
    switch (mode) {
      case ImageMode.biColorMask: return 0;
      case ImageMode.sparseBg: return 1;
      case ImageMode.rowRepeat: return 2;
      case ImageMode.rleLocal: return 3;
      case ImageMode.rawLocal: return 4;
      case ImageMode.rawGlobal: return 5;
      case ImageMode.extended: return 6;
      case ImageMode.rowDelta: return 7;
      case ImageMode.regionsBg: return 8;
      default: return 99;
    }
  }

  function makeCandidate(payload, options = {}) {
    return Object.freeze({
      payload,
      body: payload,
      text: '',
      mode: options.mode ?? ImageMode.extended,
      modeName: ImageModeName[options.mode ?? ImageMode.extended],
      scan: options.scan ?? ScanMode.h,
      scanName: ScanModeName[options.scan ?? ScanMode.h],
      byteLength: payload.length,
      charLength: 0,
      boundsPresent: options.boundsPresent === true,
      boundsX: options.boundsX ?? null,
      boundsY: options.boundsY ?? null,
      boundsWidth: options.boundsWidth ?? null,
      boundsHeight: options.boundsHeight ?? null,
      backgroundColor: options.backgroundColor ?? null,
      transparentColor: options.transparentColor ?? null,
      regionCount: options.regionCount ?? 0,
      backgroundRank: options.backgroundRank ?? 0,
      codecVersion: 3,
      localPaletteSize: options.localPaletteSize ?? null,
      bitsPerLocalPixel: options.bitsPerLocalPixel ?? null,
      requestedEncodingVersion: 3,
      actualEncodingVersion: 3,
      paletteKind: options.paletteKind ?? 'fixed',
      container: options.container ?? 'block',
      algorithm: options.algorithm ?? null,
    });
  }

  function withPacketNonce(candidate, nonce) {
    const payload = new Uint8Array(candidate.payload.length + 1);
    payload[0] = nonce;
    payload.set(candidate.payload, 1);
    return makeCandidate(payload, { ...candidate, payload: undefined, body: undefined });
  }

  function localPaletteSizeFor(linear, algorithm, backgroundColor) {
    switch (algorithm) {
      case MCOImageV3BlockAlgorithm.rawLocal:
      case MCOImageV3BlockAlgorithm.compactRle:
      case MCOImageV3BlockAlgorithm.varUintRle:
      case MCOImageV3BlockAlgorithm.lzPixels:
      case MCOImageV3BlockAlgorithm.quadtree:
      case MCOImageV3BlockAlgorithm.bitplanes:
      case MCOImageV3BlockAlgorithm.adaptiveBitplanes:
      case MCOImageV3BlockAlgorithm.compactRowDelta:
      case MCOImageV3BlockAlgorithm.rowDelta:
      case MCOImageV3BlockAlgorithm.rowRepeat:
        return new Set(linear).size;
      case MCOImageV3BlockAlgorithm.compactSparse:
      case MCOImageV3BlockAlgorithm.varUintSparse:
        return new Set(linear.filter((color) => color !== backgroundColor)).size;
      case MCOImageV3BlockAlgorithm.biColorMask: return 2;
      default: return null;
    }
  }

  function bitsPerLocalPixelFor(linear, algorithm, backgroundColor) {
    const size = localPaletteSizeFor(linear, algorithm, backgroundColor);
    return size == null || size <= 0 ? null : localBits(size);
  }

  function normalBackgroundCandidates(image, preferredBackground) {
    const result = [], seen = new Set();
    const add = (color, rank) => {
      if (result.length >= MAX_NORMAL_BACKGROUND_CANDIDATES || !isColorValid(image.paletteProfile, color) || seen.has(color)) return;
      seen.add(color); result.push({ color, rank });
    };
    add(preferredBackground, 0);
    const counts = new Map();
    for (const pixel of image.pixels) counts.set(pixel, (counts.get(pixel) || 0) + 1);
    const colors = Array.from(counts.keys()).sort((a, b) => (counts.get(b) - counts.get(a)) || (a - b));
    for (let i = 0; i < colors.length && result.length < MAX_NORMAL_BACKGROUND_CANDIDATES; i++) add(colors[i], 1 + i);
    return result;
  }

  function fullBackgroundCandidates(image, explicitBackground, exhaustiveSmallImage) {
    const result = [], seen = new Set();
    const add = (color, rank) => {
      if (!isColorValid(image.paletteProfile, color) || seen.has(color)) return;
      seen.add(color); result.push({ color, rank });
    };
    if (explicitBackground != null) add(explicitBackground, 0);
    add(whiteIndexFor(image.paletteProfile), 1);
    const counts = new Map();
    for (const pixel of image.pixels) counts.set(pixel, (counts.get(pixel) || 0) + 1);
    const colors = Array.from(counts.keys()).sort((a, b) => (counts.get(b) - counts.get(a)) || (a - b));
    for (let i = 0; i < Math.min(MAX_FREQUENT_BACKGROUND_CANDIDATES, colors.length); i++) add(colors[i], 2 + i);
    if (exhaustiveSmallImage && image.pixels.length <= MAX_EXHAUSTIVE_BACKGROUND_PIXELS && colors.length <= MAX_EXHAUSTIVE_BACKGROUND_COLORS) {
      for (let i = 0; i < colors.length; i++) add(colors[i], 2 + i);
    }
    return result;
  }


  const PALETTE_RGB = Object.freeze({
    0: Object.freeze([16777215, 0]),
    1: Object.freeze([16777215, 12632256, 5658198, 0]),
    2: Object.freeze([16777215, 9276813, 0, 16655360, 15847680, 4702208, 4024831, 7930111]),
    3: Object.freeze([16777215, 10790052, 0, 13704705, 6426113, 16745472, 8077312, 15847680, 9468930, 4304896, 2649600, 8379647, 15103, 8854, 6947043, 3080292]),
    4: Object.freeze([16777215, 11776947, 6710886, 0, 16756899, 16733505, 16655360, 6426113, 16757603, 16745472, 12936705, 9324800, 16113243, 15847680, 11902210, 7891202, 9820790, 4702208, 2649600, 1920768, 12907007, 115711, 232888, 93583, 7706367, 15103, 143050, 8854, 14136063, 11700223, 8732159, 3080292]),
    5: Object.freeze([16777215, 14277081, 11776947, 9079690, 7303023, 5197647, 2368548, 0, 16756899, 16751241, 16733505, 16655360, 13704705, 9508096, 6426113, 4524544, 16757603, 16754773, 16749363, 16745472, 14972417, 12936705, 9324800, 8077312, 16246130, 16113243, 15847680, 14663938, 13349121, 11902210, 9468930, 7891202, 12052123, 9820790, 7195979, 4702208, 4304896, 3576833, 2649600, 1920768, 12907007, 11266559, 8379647, 115711, 46830, 109279, 232888, 93583, 9546495, 7706367, 3892479, 15103, 144353, 143050, 75952, 8854, 14136063, 11700223, 10118655, 8732159, 7930111, 6882013, 5439919, 3080292]),
    6: Object.freeze([16777215, 15658734, 14540253, 13421772, 12303291, 11184810, 10066329, 8947848, 7829367, 6710886, 5592405, 4473924, 3355443, 2236962, 1118481, 0]),
    7: Object.freeze([16777215, 16250871, 15724527, 15132390, 14606046, 14079702, 13553358, 12961221, 12434877, 11908533, 11382189, 10855845, 10263708, 9737364, 9211020, 8684676, 8092539, 7566195, 7039851, 6513507, 5921370, 5395026, 4868682, 4342338, 3750201, 3223857, 2697513, 2171169, 1579032, 1052688, 526344, 0]),
    8: Object.freeze([16777215, 14408667, 11974326, 9539985, 7171437, 4737096, 2368548, 0]),
  });
  const DYNAMIC_GLOBAL512_RGB = Object.freeze([16777215, 15848371, 14134915, 12289885, 10183486, 8145197, 6173471, 4268310, 2429195, 14277081, 16772581, 16770515, 16767174, 16305343, 16039845, 15448207, 14723460, 13801339, 11776947, 16766688, 16768200, 16773816, 13495503, 13233904, 13557242, 14734068, 15388643, 9079690, 14999726, 13289347, 11184479, 9014083, 7172404, 5461545, 3816478, 2302998, 7303023, 16773560, 16769162, 16042333, 14528311, 12882724, 10318104, 7622671, 4796424, 5197647, 12186600, 8576463, 5161909, 2598039, 1475705, 942940, 541759, 206370, 2368548, 16040104, 15178620, 13923927, 12146238, 9846061, 7482146, 5184536, 2821645, 0, 16756899, 16446440, 15721426, 14864825, 13877154, 12757383, 11178095, 9270876, 7298121, 16751241, 16769218, 16040607, 14656894, 13142370, 11168585, 8540218, 5977386, 3481627, 16733505, 9276813, 10790052, 6710886, 16727844, 16661021, 16659478, 16658190, 16656647, 16655360, 16327424, 15999744, 15671808, 15343872, 15016193, 14688257, 14360321, 14032641, 13704705, 13245697, 12786689, 12327681, 11868673, 11344128, 10885120, 10426112, 9967104, 9508096, 9180160, 8852224, 8459008, 8131072, 7803137, 7475201, 7081985, 6754049, 6426113, 6229505, 6032641, 5770497, 5573633, 5377024, 5180160, 4918016, 4721152, 4524544, 16757603, 16757345, 16757088, 16756574, 16756317, 16756059, 16755802, 16755288, 16755031, 16754773, 16754257, 16753485, 16752970, 16752454, 16751682, 16751166, 16750651, 16749879, 16749363, 16748845, 16748584, 16748066, 16747548, 16747287, 16746769, 16746251, 16745990, 16745472, 16548352, 16351488, 16154368, 15957504, 15760385, 15563521, 15366401, 15169537, 14972417, 14775297, 14512641, 14315777, 14053121, 13856001, 13593345, 13396481, 13133825, 12936705, 12542721, 12148737, 11754497, 11360513, 10900992, 10507008, 10112768, 9718784, 9324800, 9193472, 9062144, 8930816, 8799488, 8602624, 8471296, 8339968, 8208640, 8077312, 16246130, 16245871, 16245613, 16180074, 16179816, 16179557, 16179299, 16113760, 16113502, 16113243, 16112977, 16046919, 16046653, 15980595, 15980328, 15914270, 15914004, 15847946, 15847680, 15716096, 15584512, 15453185, 15321601, 15190017, 15058433, 14927106, 14795522, 14663938, 14532354, 14400770, 14203906, 14072322, 13940737, 13809153, 13612289, 13480705, 13349121, 13217537, 13020417, 12888577, 12691457, 12559874, 12362754, 12230914, 12033794, 11902210, 11639042, 11376130, 11112962, 10849794, 10521346, 10258178, 9995010, 9732098, 9468930, 9271810, 9140226, 8943106, 8745986, 8614146, 8417026, 8219906, 8088322, 7891202, 12052123, 11789719, 11527059, 11330191, 11067787, 10805126, 10542722, 10345854, 10083194, 9820790, 9558385, 9230188, 8967784, 8639587, 8377182, 8048985, 7786581, 7458384, 7195979, 6933571, 6670906, 6342962, 6080298, 5817889, 5555225, 5227281, 4964616, 4702208, 4636160, 4635648, 4569856, 4503808, 4503296, 4437248, 4371456, 4370944, 4304896, 4238592, 4172288, 4040448, 3974144, 3907585, 3841281, 3709441, 3643137, 3576833, 3444737, 3378177, 3245825, 3179265, 3047168, 2980608, 2848256, 2781696, 2649600, 2583296, 2516736, 2384896, 2318336, 2252032, 2185472, 2053632, 1987072, 1920768, 12907007, 12710143, 12513279, 12381951, 12185087, 11988479, 11791615, 11660287, 11463423, 11266559, 10938623, 10610431, 10282495, 9954303, 9691903, 9363711, 9035775, 8707583, 8379647, 7461375, 6543103, 5625087, 4706815, 3788543, 2870271, 1952255, 1033983, 115711, 115453, 114939, 114681, 114167, 48374, 47860, 47602, 47088, 46830, 46572, 46059, 45801, 45543, 110566, 110308, 110050, 109537, 109279, 108507, 107734, 172242, 171470, 170697, 169925, 234433, 233660, 232888, 231859, 231087, 164522, 163750, 162721, 161949, 95384, 94612, 93583, 9546495, 9349375, 9152255, 8954879, 8757759, 8495103, 8297983, 8100607, 7903487, 7706367, 7311615, 6851583, 6456831, 5996799, 5602047, 5142015, 4747263, 4024831, 3892479, 3432447, 3038207, 2578175, 2183679, 1723903, 1329407, 869375, 475135, 15103, 14844, 14584, 80117, 79858, 79598, 79339, 144872, 144612, 144353, 144094, 144092, 143833, 143831, 143572, 143570, 143311, 143309, 143050, 142791, 142788, 142529, 142270, 76732, 76473, 76214, 76211, 75952, 75693, 75690, 75431, 75172, 9634, 9375, 9116, 9113, 8854, 14136063, 13872639, 13609215, 13346047, 13082623, 12753663, 12490239, 12227071, 11963647, 11700223, 11502591, 11370495, 11173119, 10975487, 10843391, 10645759, 10448383, 10316287, 10118655, 9986559, 9788671, 9656575, 9524223, 9326591, 9194239, 9062143, 8864255, 8732159, 8664831, 8531967, 8464895, 8397567, 8264703, 8197375, 8130303, 7997439, 7930111, 7799035, 7667959, 7602676, 7471600, 7340524, 7209448, 7144165, 6947043, 6882013, 6750936, 6554323, 6423246, 6226633, 6095299, 5898686, 5767609, 5570996, 5439919, 5177767, 4915614, 4653462, 4391310, 4128901, 3866749, 3604597, 3342444, 3080292]);
  function compactUintBitLength(value) {
    if (value <= 3) return 3;
    if (value <= 19) return 6;
    if (value <= 275) return 11;
    let bytes = 1, current = value;
    while (current >= 128) { current = Math.floor(current / 128); bytes++; }
    return 3 + bytes * 8;
  }

  function rangeCompactUintBitLength(value, maxValue) {
    return maxValue <= 7 ? bitLength(maxValue) : compactUintBitLength(value);
  }

  function localPaletteFlatPrefixBitLength(profile, length) {
    const size = paletteSize(profile);
    if (length <= 0 || length > size) throw new MCOImageV3InvalidInputError('Invalid local palette size');
    if (size <= LOCAL_PALETTE_SMALL_LENGTH_LIMIT) return 1 + globalBits(profile);
    if (length <= LOCAL_PALETTE_SMALL_LENGTH_LIMIT) return 7;
    if (length <= LOCAL_PALETTE_MEDIUM_LENGTH_LIMIT) return 8;
    return 11;
  }

  function localPaletteDescriptorPrefixBitLength(profile) {
    return paletteSize(profile) <= LOCAL_PALETTE_SMALL_LENGTH_LIMIT
      ? 1 + LOCAL_PALETTE_DESCRIPTOR_BITS
      : 4 + LOCAL_PALETTE_DESCRIPTOR_BITS;
  }

  function localPaletteLengthBitLength(profile, length) {
    const size = paletteSize(profile);
    if (length <= 0 || length > size) throw new MCOImageV3InvalidInputError('Invalid local palette size');
    if (size <= LOCAL_PALETTE_SMALL_LENGTH_LIMIT) return globalBits(profile);
    if (length <= LOCAL_PALETTE_SMALL_LENGTH_LIMIT) return 7;
    if (length <= LOCAL_PALETTE_MEDIUM_LENGTH_LIMIT) return 8;
    return 2 + bitLength(size - 129);
  }

  function localPaletteRefRanges(profile, colors) {
    const refs = colors.map((color) => colorRefForProfile(profile, color));
    const ranges = [];
    let start = refs[0], previous = start;
    for (let i = 1; i < refs.length; i++) {
      const ref = refs[i];
      if (ref === previous + 1) previous = ref;
      else { ranges.push({ start, end: previous, length: previous - start + 1 }); start = previous = ref; }
    }
    ranges.push({ start, end: previous, length: previous - start + 1 });
    return ranges;
  }

  function isProfileSortedLocalPalette(profile, colors) {
    let previous = -1;
    const seen = new Set();
    for (const color of colors) {
      const ref = colorRefForProfile(profile, color);
      if (seen.has(color)) throw new MCOImageV3InvalidInputError('Duplicate local color');
      seen.add(color);
      if (ref <= previous) return false;
      previous = ref;
    }
    return true;
  }

  function localPaletteSortedDeltaBitCost(profile, colors) {
    let cost = localPaletteDescriptorPrefixBitLength(profile) +
      localPaletteLengthBitLength(profile, colors.length) + globalBits(profile);
    let previous = colorRefForProfile(profile, colors[0]);
    for (let i = 1; i < colors.length; i++) {
      const ref = colorRefForProfile(profile, colors[i]);
      cost += compactUintBitLength(ref - previous - 1);
      previous = ref;
    }
    return cost;
  }

  function localPaletteRangeRunsBitCost(profile, colors) {
    const runs = localPaletteRefRanges(profile, colors);
    let cost = localPaletteDescriptorPrefixBitLength(profile) +
      rangeCompactUintBitLength(runs.length - 1, paletteSize(profile) - 1);
    for (const run of runs) cost += globalBits(profile) + compactUintBitLength(run.length - 1);
    return cost;
  }

  function localPaletteBankBitmapsBitCost(colors) {
    let bankMask = 0;
    for (const color of colors) bankMask |= 1 << (colorRefForProfile(PaletteProfile.dynamicGlobal512, color) >> 6);
    return localPaletteDescriptorPrefixBitLength(PaletteProfile.dynamicGlobal512) + 1 + 8 + bitCount(bankMask) * 64;
  }

  function localPaletteOrderedBanked8x64BitCost(colors) {
    const refs = colors.map((color) => colorRefForProfile(PaletteProfile.dynamicGlobal512, color));
    let bankMask = 0;
    for (const ref of refs) bankMask |= 1 << (ref >> 6);
    const bankCount = bitCount(bankMask);
    const bankChoiceBits = bankCount <= 1 ? 0 : bitLength(bankCount - 1);
    return localPaletteDescriptorPrefixBitLength(PaletteProfile.dynamicGlobal512) + 1 +
      localPaletteLengthBitLength(PaletteProfile.dynamicGlobal512, colors.length) + 1 +
      (bankCount === 1 ? 3 : 8) + colors.length * (6 + bankChoiceBits);
  }

  function bestLocalPaletteDescriptor(profile, colors) {
    const flatBits = localPaletteFlatPrefixBitLength(profile, colors.length) + colors.length * globalBits(profile);
    const prefixBits = localPaletteDescriptorPrefixBitLength(profile);
    const candidates = [];
    const sorted = isProfileSortedLocalPalette(profile, colors);
    if (sorted) {
      candidates.push({ descriptor: LOCAL_PALETTE_DESCRIPTOR_BITMAP, bitCost: prefixBits + paletteSize(profile) });
      candidates.push({ descriptor: LOCAL_PALETTE_DESCRIPTOR_SORTED_DELTA, bitCost: localPaletteSortedDeltaBitCost(profile, colors) });
      candidates.push({ descriptor: LOCAL_PALETTE_DESCRIPTOR_RANGE_RUNS, bitCost: localPaletteRangeRunsBitCost(profile, colors) });
    }
    if (profile === PaletteProfile.dynamicGlobal512) {
      if (sorted) candidates.push({ descriptor: LOCAL_PALETTE_DESCRIPTOR_BANK_BITMAPS, bitCost: localPaletteBankBitmapsBitCost(colors) });
      candidates.push({ descriptor: 4, bitCost: localPaletteOrderedBanked8x64BitCost(colors) });
    }
    if (candidates.length === 0) return null;
    let best = candidates[0];
    for (let i = 1; i < candidates.length; i++) if (candidates[i].bitCost < best.bitCost) best = candidates[i];
    return best.bitCost < flatBits ? best.descriptor : null;
  }

  function writeLocalPaletteFlatPrefix(writer, profile, length) {
    const size = paletteSize(profile);
    if (length <= 0 || length > size) throw new MCOImageV3InvalidInputError('Invalid local palette size');
    if (size <= LOCAL_PALETTE_SMALL_LENGTH_LIMIT) {
      writer.writeBits(0, 1).writeBits(length - 1, globalBits(profile));
    } else if (length <= LOCAL_PALETTE_SMALL_LENGTH_LIMIT) {
      writer.writeBits(0, 1).writeBits(length - 1, 6);
    } else if (length <= LOCAL_PALETTE_MEDIUM_LENGTH_LIMIT) {
      writer.writeBits(1, 1).writeBits(0, 1).writeBits(length - 65, 6);
    } else if (length <= LOCAL_PALETTE_LARGE_LENGTH_LIMIT) {
      writer.writeBits(1, 1).writeBits(1, 1).writeBits(0, 1).writeBits(length - 129, 8);
    } else {
      writer.writeBits(1, 1).writeBits(1, 1).writeBits(1, 1).writeBits(0, 1).writeBits(length - 385, 7);
    }
  }

  function writeLocalPaletteDescriptorPrefix(writer, profile, descriptor) {
    if (descriptor < 0 || descriptor >= 4) throw new MCOImageV3InvalidInputError('Invalid local palette descriptor');
    if (paletteSize(profile) <= LOCAL_PALETTE_SMALL_LENGTH_LIMIT) writer.writeBits(1, 1);
    else writer.writeBits(1, 1).writeBits(1, 1).writeBits(1, 1).writeBits(1, 1);
    writer.writeBits(descriptor, LOCAL_PALETTE_DESCRIPTOR_BITS);
  }

  function writeLocalPaletteLength(writer, profile, length) {
    const size = paletteSize(profile);
    if (length <= 0 || length > size) throw new MCOImageV3InvalidInputError('Invalid local palette size');
    if (size <= LOCAL_PALETTE_SMALL_LENGTH_LIMIT) writer.writeBits(length - 1, globalBits(profile));
    else if (length <= LOCAL_PALETTE_SMALL_LENGTH_LIMIT) writer.writeBits(0, 1).writeBits(length - 1, 6);
    else if (length <= LOCAL_PALETTE_MEDIUM_LENGTH_LIMIT) writer.writeBits(1, 1).writeBits(0, 1).writeBits(length - 65, 6);
    else writer.writeBits(1, 1).writeBits(1, 1).writeBits(length - 129, bitLength(size - 129));
  }

  function writeLocalPaletteDescriptorBody(writer, profile, colors, descriptor) {
    if (descriptor === LOCAL_PALETTE_DESCRIPTOR_BITMAP) {
      const selected = new Set(colors.map((color) => colorRefForProfile(profile, color)));
      for (let ref = 0; ref < paletteSize(profile); ref++) writer.writeBits(selected.has(ref) ? 1 : 0, 1);
      return;
    }
    if (descriptor === LOCAL_PALETTE_DESCRIPTOR_SORTED_DELTA) {
      writeLocalPaletteLength(writer, profile, colors.length);
      let previous = colorRefForProfile(profile, colors[0]);
      writer.writeBits(previous, globalBits(profile));
      for (let i = 1; i < colors.length; i++) {
        const ref = colorRefForProfile(profile, colors[i]);
        writer.writeCompactUint(ref - previous - 1);
        previous = ref;
      }
      return;
    }
    if (descriptor === LOCAL_PALETTE_DESCRIPTOR_RANGE_RUNS) {
      const runs = localPaletteRefRanges(profile, colors);
      writer.writeRangeCompactUint(runs.length - 1, paletteSize(profile) - 1);
      for (const run of runs) writer.writeBits(run.start, globalBits(profile)).writeCompactUint(run.length - 1);
      return;
    }
    if (descriptor === LOCAL_PALETTE_DESCRIPTOR_BANK_BITMAPS) {
      if (profile !== PaletteProfile.dynamicGlobal512) throw new MCOImageV3InvalidInputError('Bank bitmap descriptor requires dynamicGlobal512');
      writer.writeBits(LOCAL_PALETTE_BANK_DESCRIPTOR_BITMAPS, 1);
      const refs = colors.map((color) => colorRefForProfile(profile, color));
      const selected = new Set(refs);
      let bankMask = 0;
      for (const ref of refs) bankMask |= 1 << (ref >> 6);
      writer.writeBits(bankMask, 8);
      for (let bank = 0; bank < 8; bank++) if ((bankMask & (1 << bank)) !== 0) {
        for (let offset = 0; offset < 64; offset++) writer.writeBits(selected.has((bank << 6) | offset) ? 1 : 0, 1);
      }
      return;
    }
    if (descriptor === 4) {
      if (profile !== PaletteProfile.dynamicGlobal512) throw new MCOImageV3InvalidInputError('Ordered banked descriptor requires dynamicGlobal512');
      writer.writeBits(LOCAL_PALETTE_BANK_DESCRIPTOR_ORDERED_8X64, 1);
      writeLocalPaletteLength(writer, profile, colors.length);
      const refs = colors.map((color) => colorRefForProfile(profile, color));
      let bankMask = 0;
      for (const ref of refs) bankMask |= 1 << (ref >> 6);
      const banks = [];
      for (let bank = 0; bank < 8; bank++) if ((bankMask & (1 << bank)) !== 0) banks.push(bank);
      const single = banks.length === 1;
      writer.writeBits(single ? 0 : 1, 1);
      if (single) {
        writer.writeBits(banks[0], 3);
        for (const ref of refs) writer.writeBits(ref & 0x3f, 6);
      } else {
        writer.writeBits(bankMask, 8);
        const bankBits = bitLength(banks.length - 1);
        const indexes = new Map(banks.map((bank, index) => [bank, index]));
        for (const ref of refs) writer.writeBits(indexes.get(ref >> 6), bankBits).writeBits(ref & 0x3f, 6);
      }
      return;
    }
    throw new MCOImageV3InvalidInputError('Unsupported local palette descriptor');
  }

  function writeLocalPalette(writer, profile, colors) {
    if (!Array.isArray(colors) || colors.length === 0 || colors.length > paletteSize(profile)) {
      throw new MCOImageV3InvalidInputError('Invalid local palette size');
    }
    const descriptor = bestLocalPaletteDescriptor(profile, colors);
    if (descriptor == null) {
      writeLocalPaletteFlatPrefix(writer, profile, colors.length);
      for (const color of colors) writeColorRef(writer, profile, color);
      return;
    }
    const wireDescriptor = descriptor === 4 ? LOCAL_PALETTE_DESCRIPTOR_BANK_BITMAPS : descriptor;
    writeLocalPaletteDescriptorPrefix(writer, profile, wireDescriptor);
    writeLocalPaletteDescriptorBody(writer, profile, colors, descriptor);
  }

  function firstUseLocalPalette(pixels) {
    const seen = new Set(), result = [];
    for (const pixel of pixels) if (!seen.has(pixel)) { seen.add(pixel); result.push(pixel); }
    return result;
  }

  function profileOrderLocalPalette(pixels, profile) {
    return Array.from(new Set(pixels)).sort((a, b) => (colorRefForProfile(profile, a) - colorRefForProfile(profile, b)) || (a - b));
  }

  function transitionLocalPalette(pixels, preferredFirstColor) {
    const colors = Array.from(new Set(pixels));
    if (colors.length < 2 || colors.length > 64) return null;
    const counts = new Map(), edges = new Map();
    for (const pixel of pixels) counts.set(pixel, (counts.get(pixel) || 0) + 1);
    const addEdge = (a, b) => {
      if (!edges.has(a)) edges.set(a, new Map());
      edges.get(a).set(b, (edges.get(a).get(b) || 0) + 1);
    };
    for (let i = 1; i < pixels.length; i++) {
      const a = pixels[i - 1], b = pixels[i];
      if (a !== b) { addEdge(a, b); addEdge(b, a); }
    }
    colors.sort((a, b) => (counts.get(b) - counts.get(a)) || (a - b));
    const remaining = new Set(colors);
    const first = preferredFirstColor != null && remaining.has(preferredFirstColor) ? preferredFirstColor : colors[0];
    const result = [first]; remaining.delete(first);
    while (remaining.size) {
      const previous = result[result.length - 1];
      let best = null, bestWeight = -1;
      for (const color of remaining) {
        const weight = edges.get(previous)?.get(color) || 0;
        if (best == null || weight > bestWeight ||
            (weight === bestWeight && ((counts.get(color) || 0) > (counts.get(best) || 0) ||
             ((counts.get(color) || 0) === (counts.get(best) || 0) && color < best)))) {
          best = color; bestWeight = weight;
        }
      }
      result.push(best); remaining.delete(best);
    }
    return result;
  }

  function paletteRgb(profile, color) {
    if (isDynamicProfile(profile)) return DYNAMIC_GLOBAL512_RGB[color];
    return PALETTE_RGB[profile][color];
  }

  function paletteRgbDistanceSquared(profile, left, right) {
    const a = paletteRgb(profile, left), b = paletteRgb(profile, right);
    const ar = (a >> 16) & 255, ag = (a >> 8) & 255, ab = a & 255;
    const br = (b >> 16) & 255, bg = (b >> 8) & 255, bb = b & 255;
    return (ar - br) ** 2 + (ag - bg) ** 2 + (ab - bb) ** 2;
  }

  function rgbOrderLocalPalette(pixels, profile, preferredFirstColor) {
    const colors = Array.from(new Set(pixels));
    if (colors.length < 3) return null;
    const counts = new Map();
    for (const pixel of pixels) counts.set(pixel, (counts.get(pixel) || 0) + 1);
    const remaining = new Set(colors);
    let current;
    if (preferredFirstColor != null && remaining.has(preferredFirstColor)) current = preferredFirstColor;
    else current = colors.reduce((a, b) => (counts.get(a) || 0) >= (counts.get(b) || 0) ? a : b);
    const result = [];
    while (remaining.size) {
      result.push(current); remaining.delete(current);
      if (!remaining.size) break;
      let best = null;
      for (const color of remaining) {
        if (best == null) { best = color; continue; }
        const d = paletteRgbDistanceSquared(profile, current, color);
        const bd = paletteRgbDistanceSquared(profile, current, best);
        if (d < bd || (d === bd && ((counts.get(color) || 0) > (counts.get(best) || 0) ||
            ((counts.get(color) || 0) === (counts.get(best) || 0) && color < best)))) best = color;
      }
      current = best;
    }
    return result;
  }

  function localPaletteVariants(pixels, profile, options = {}) {
    const cacheKey = activeLocalPaletteVariantCache == null ? null : [
      profile,
      options.indexOrderSensitive ? 1 : 0,
      options.includeTransitionOrder ? 1 : 0,
      options.includeBitplaneOptimizedOrder ? 1 : 0,
      options.includeRgbOrder ? 1 : 0,
      options.preferredFirstColor ?? '-',
      valueListCacheKey(pixels),
    ].join('|');
    if (cacheKey != null && activeLocalPaletteVariantCache.has(cacheKey)) {
      return activeLocalPaletteVariantCache.get(cacheKey);
    }
    const variants = [], seen = new Set();
    const add = (palette) => {
      if (!palette || palette.length === 0) return;
      const key = palette.join(',');
      if (!seen.has(key)) { seen.add(key); variants.push(palette); }
    };
    const frequency = localPalette(pixels);
    add(frequency);
    if (options.indexOrderSensitive && options.preferredFirstColor != null && frequency.includes(options.preferredFirstColor)) {
      add([options.preferredFirstColor, ...frequency.filter((color) => color !== options.preferredFirstColor)]);
    }
    if (options.indexOrderSensitive) add(firstUseLocalPalette(pixels));
    add(profileOrderLocalPalette(pixels, profile));
    if (options.indexOrderSensitive && options.includeTransitionOrder) add(transitionLocalPalette(pixels, options.preferredFirstColor));
    if (options.indexOrderSensitive && options.includeRgbOrder) add(rgbOrderLocalPalette(pixels, profile, options.preferredFirstColor));
    if (options.indexOrderSensitive && options.includeBitplaneOptimizedOrder) {
      for (const palette of bitplaneOptimizedLocalPalettes(pixels, profile, options.preferredFirstColor)) add(palette);
    }
    if (cacheKey != null) activeLocalPaletteVariantCache.set(cacheKey, variants);
    return variants;
  }

  function encodeLocalPaletteBlock(linear, profile, palette, writeBody) {
    const bits = localBits(palette.length);
    const localPixels = mapPixelsToPalette(linear, palette);
    const writer = new BitWriter();
    writeLocalPalette(writer, profile, palette);
    writeBody(writer, localPixels, bits);
    return { palette, localPixels, bits, bitLength: writer.bitLength, bytes: writer.toBytes() };
  }

  function writeBestLocalPaletteBlock(writer, linear, profile, options, writeBody) {
    let best = null;
    for (const palette of localPaletteVariants(linear, profile, options)) {
      try {
        const candidate = encodeLocalPaletteBlock(linear, profile, palette, writeBody);
        if (best == null || candidate.bitLength < best.bitLength) best = candidate;
      } catch (error) {
        if (!(error instanceof MCOImageV3CodecError)) throw error;
      }
    }
    if (best == null) throw new MCOImageV3InvalidInputError('Empty local palette');
    writer.writeBitStream(best.bytes, best.bitLength);
  }


  function buildBitplaneRuns(pixels, bit) {
    if (pixels.length === 0) return [];
    const runs = [];
    let current = (pixels[0] >> bit) & 1, length = 1;
    for (let i = 1; i < pixels.length; i++) {
      const value = (pixels[i] >> bit) & 1;
      if (value === current) length++;
      else { runs.push(length); current = value; length = 1; }
    }
    runs.push(length);
    return runs;
  }

  function residualRunLengthsBitCost(runs, totalLength) {
    let cost = 0, consumed = 0;
    for (const length of runs) {
      if (length <= 0 || consumed + length > totalLength) throw new MCOImageV3InvalidInputError('Invalid residual run lengths');
      cost += rangeCompactUintBitLength(length - 1, totalLength - consumed - 1);
      consumed += length;
    }
    if (consumed !== totalLength) throw new MCOImageV3InvalidInputError('Residual run lengths do not fill the input');
    return cost;
  }

  function writeResidualRunLengths(writer, runs, totalLength) {
    let consumed = 0;
    for (const length of runs) {
      writer.writeRangeCompactUint(length - 1, totalLength - consumed - 1);
      consumed += length;
    }
    if (consumed !== totalLength) throw new MCOImageV3InvalidInputError('Residual run lengths do not fill the input');
  }

  function shortBitplaneRunBitLength(length, remainingLength) {
    if (length <= 0 || remainingLength <= 0 || length > remainingLength) throw new MCOImageV3InvalidInputError('Invalid bitplane run');
    if (length <= 3) return length;
    return 3 + rangeCompactUintBitLength(length - 4, remainingLength - 4);
  }

  function shortBitplaneRunsBitCost(runs, totalLength) {
    let cost = 0, consumed = 0;
    for (const length of runs) { cost += shortBitplaneRunBitLength(length, totalLength - consumed); consumed += length; }
    if (consumed !== totalLength) throw new MCOImageV3InvalidInputError('Short bitplane runs do not fill the input');
    return cost;
  }

  function writeShortBitplaneRunLength(writer, length, remainingLength) {
    if (length <= 3) writer.writeBits((1 << (length - 1)) - 1, length);
    else writer.writeBits(7, 3).writeRangeCompactUint(length - 4, remainingLength - 4);
  }

  function sparseBitplanePositionCost(positions, pixelCount) {
    let cost = rangeCompactUintBitLength(positions.length - 1, pixelCount - 1), previous = -1;
    for (let i = 0; i < positions.length; i++) {
      const remainingPositions = positions.length - i - 1;
      const maxGap = pixelCount - previous - remainingPositions - 2;
      cost += rangeCompactUintBitLength(positions[i] - previous - 1, maxGap);
      previous = positions[i];
    }
    return cost;
  }

  function writeSparseBitplanePositions(writer, positions, pixelCount) {
    writer.writeRangeCompactUint(positions.length - 1, pixelCount - 1);
    let previous = -1;
    for (let i = 0; i < positions.length; i++) {
      const remainingPositions = positions.length - i - 1;
      const maxGap = pixelCount - previous - remainingPositions - 2;
      writer.writeRangeCompactUint(positions[i] - previous - 1, maxGap);
      previous = positions[i];
    }
  }

  function chooseAdaptiveBitplaneEncoding(pixels, bit) {
    if (pixels.length === 0) throw new MCOImageV3InvalidInputError('Adaptive bitplanes require at least one pixel');
    const runs = buildBitplaneRuns(pixels, bit);
    const startingBit = (pixels[0] >> bit) & 1;
    const onePositions = [], zeroPositions = [];
    for (let i = 0; i < pixels.length; i++) (((pixels[i] >> bit) & 1) === 0 ? zeroPositions : onePositions).push(i);
    const decisions = [
      { mode: 'raw', bitCost: 1 + pixels.length, startingBit, runs, minorityPositions: [] },
      { mode: 'legacyRle', bitCost: 3 + residualRunLengthsBitCost(runs, pixels.length), startingBit, runs, minorityPositions: [] },
      { mode: 'shortRle', bitCost: 4 + shortBitplaneRunsBitCost(runs, pixels.length), startingBit, runs, minorityPositions: [] },
    ];
    if (onePositions.length === 0 || zeroPositions.length === 0) {
      decisions.push({ mode: onePositions.length === 0 ? 'constantZero' : 'constantOne', bitCost: 5, startingBit, runs, minorityPositions: [] });
    } else {
      decisions.push({ mode: 'sparseOne', bitCost: 5 + sparseBitplanePositionCost(onePositions, pixels.length), startingBit, runs, minorityPositions: onePositions });
      decisions.push({ mode: 'sparseZero', bitCost: 5 + sparseBitplanePositionCost(zeroPositions, pixels.length), startingBit, runs, minorityPositions: zeroPositions });
    }
    let best = decisions[0];
    for (let i = 1; i < decisions.length; i++) if (decisions[i].bitCost < best.bitCost) best = decisions[i];
    return best;
  }

  function writeAdaptiveBitplanesBody(writer, pixels, bits) {
    for (let bit = 0; bit < bits; bit++) {
      const d = chooseAdaptiveBitplaneEncoding(pixels, bit);
      if (d.mode === 'raw') {
        writer.writeBits(0, 1);
        for (const pixel of pixels) writer.writeBits((pixel >> bit) & 1, 1);
      } else if (d.mode === 'legacyRle') {
        writer.writeBits(1, 2).writeBits(d.startingBit, 1);
        writeResidualRunLengths(writer, d.runs, pixels.length);
      } else if (d.mode === 'shortRle') {
        writer.writeBits(3, 3).writeBits(d.startingBit, 1);
        let consumed = 0;
        for (const length of d.runs) { writeShortBitplaneRunLength(writer, length, pixels.length - consumed); consumed += length; }
      } else if (d.mode === 'constantZero') writer.writeBits(7, 5);
      else if (d.mode === 'constantOne') writer.writeBits(15, 5);
      else if (d.mode === 'sparseOne') { writer.writeBits(23, 5); writeSparseBitplanePositions(writer, d.minorityPositions, pixels.length); }
      else if (d.mode === 'sparseZero') { writer.writeBits(31, 5); writeSparseBitplanePositions(writer, d.minorityPositions, pixels.length); }
    }
  }

  function adaptiveBitplanesCost(pixels, palette) {
    const local = mapPixelsToPalette(pixels, palette);
    let cost = 0;
    for (let bit = 0; bit < localBits(palette.length); bit++) cost += chooseAdaptiveBitplaneEncoding(local, bit).bitCost;
    return cost;
  }

  function optimizeBitplanesPaletteOrder(pixels, palette) {
    let bestPalette = Array.from(palette), bestCost = adaptiveBitplanesCost(pixels, bestPalette);
    const exhaustive = palette.length <= 8, passCount = exhaustive ? 2 : 1;
    for (let pass = 0; pass < passCount; pass++) {
      let improved = false, passPalette = bestPalette, passCost = bestCost;
      for (let left = 0; left < bestPalette.length - 1; left++) {
        const rightLimit = exhaustive ? bestPalette.length : left + 2;
        for (let right = left + 1; right < rightLimit; right++) {
          const candidate = Array.from(bestPalette);
          [candidate[left], candidate[right]] = [candidate[right], candidate[left]];
          const cost = adaptiveBitplanesCost(pixels, candidate);
          if (cost < passCost) { passPalette = candidate; passCost = cost; improved = true; }
        }
      }
      if (!improved) break;
      bestPalette = passPalette; bestCost = passCost;
    }
    return bestPalette;
  }

  function bitplaneOptimizedLocalPalettes(pixels, profile, preferredFirstColor) {
    const base = localPalette(pixels);
    if (base.length < 2) return [];
    const backgroundFirst = preferredFirstColor != null && base.includes(preferredFirstColor)
      ? [preferredFirstColor, ...base.filter((color) => color !== preferredFirstColor)] : null;
    const seeds = [base, backgroundFirst, profileOrderLocalPalette(pixels, profile),
      preferredFirstColor != null ? (rgbOrderLocalPalette(pixels, profile, preferredFirstColor) || base) : null,
      transitionLocalPalette(pixels, preferredFirstColor) || base].filter(Boolean);
    const result = [], seenSeed = new Set(), seenResult = new Set();
    for (const seed of seeds) {
      const key = seed.join(','); if (seenSeed.has(key)) continue; seenSeed.add(key);
      const optimized = optimizeBitplanesPaletteOrder(pixels, seed), outKey = optimized.join(',');
      if (!seenResult.has(outKey)) { seenResult.add(outKey); result.push(optimized); }
    }
    return result;
  }

  function writeLegacyBitplanesBody(writer, localPixels, bits) {
    for (let bit = 0; bit < bits; bit++) {
      const runs = buildBitplaneRuns(localPixels, bit);
      const rleBits = 2 + residualRunLengthsBitCost(runs, localPixels.length);
      const rawBits = 1 + localPixels.length;
      if (rleBits < rawBits) {
        writer.writeBits(1, 1).writeBits((localPixels[0] >> bit) & 1, 1);
        writeResidualRunLengths(writer, runs, localPixels.length);
      } else {
        writer.writeBits(0, 1);
        for (const pixel of localPixels) writer.writeBits((pixel >> bit) & 1, 1);
      }
    }
  }


  function encoderRowDeltaSegments(changes) {
    if (changes.length === 0) return [];
    const segments = [];
    let start = changes[0].x;
    let values = [changes[0].value];
    let previous = start;
    for (let i = 1; i < changes.length; i++) {
      const change = changes[i];
      if (change.x === previous + 1) values.push(change.value);
      else { segments.push({ x: start, length: values.length, values }); start = change.x; values = [change.value]; }
      previous = change.x;
    }
    segments.push({ x: start, length: values.length, values });
    return segments;
  }

  function encoderSameRowDeltaValue(changes) {
    if (changes.length === 0) return null;
    const value = changes[0].value;
    for (let i = 1; i < changes.length; i++) if (changes[i].value !== value) return null;
    return value;
  }

  function encoderRowDeltaChanges(values, rowLength, row, useVirtualBaseRow, predictor) {
    const changes = [];
    const rowStart = row * rowLength;
    for (let x = 0; x < rowLength; x++) {
      const predicted = compactRowDeltaPredictedValue(values, rowLength, row, x, predictor, useVirtualBaseRow);
      if (values[rowStart + x] !== predicted) changes.push({ x, value: values[rowStart + x] });
    }
    return changes;
  }

  function encoderRowDeltaPredictors(row, useVirtualBaseRow) {
    return row === 0 && useVirtualBaseRow
      ? [ROW_DELTA_PREDICTOR_SAME]
      : [ROW_DELTA_PREDICTOR_SAME, ROW_DELTA_PREDICTOR_LEFT, ROW_DELTA_PREDICTOR_RIGHT];
  }

  function encoderCompactPredictorBitCost(predictor) {
    return predictor === ROW_DELTA_PREDICTOR_SAME ? 1 : 2;
  }

  function writeEncoderCompactPredictor(writer, predictor) {
    if (predictor === ROW_DELTA_PREDICTOR_SAME) writer.writeBits(0, 1);
    else if (predictor === ROW_DELTA_PREDICTOR_LEFT) writer.writeBits(1, 2);
    else if (predictor === ROW_DELTA_PREDICTOR_RIGHT) writer.writeBits(3, 2);
    else throw new MCOImageV3InvalidInputError('Invalid row-delta predictor');
  }

  function encoderRepeatedRowCount(values, rowLength, row, useVirtualBaseRow) {
    const rowCount = values.length / rowLength;
    let count = 0;
    while (row + count < rowCount) {
      const current = row + count;
      let same = true;
      for (let x = 0; x < rowLength; x++) {
        if (values[current * rowLength + x] !== compactRowDeltaPredictedValue(
          values, rowLength, current, x, ROW_DELTA_PREDICTOR_SAME, useVirtualBaseRow,
        )) { same = false; break; }
      }
      if (!same) break;
      count++;
    }
    return count;
  }

  function bestEncoderRowDeltaDecision(values, rowLength, valueBits, row, useVirtualBaseRow, allowShiftPredictors) {
    let best = {
      op: ROW_DELTA_OP_RAW, extendedOp: -1, predictor: ROW_DELTA_PREDICTOR_SAME,
      changes: [], bitCost: ROW_DELTA_OP_BITS + rowLength * valueBits,
    };
    const predictors = allowShiftPredictors
      ? encoderRowDeltaPredictors(row, useVirtualBaseRow)
      : [ROW_DELTA_PREDICTOR_SAME];
    for (const predictor of predictors) {
      const changes = encoderRowDeltaChanges(values, rowLength, row, useVirtualBaseRow, predictor);
      if (changes.length === 0 && predictor === ROW_DELTA_PREDICTOR_SAME) {
        const bitCost = ROW_DELTA_OP_BITS;
        if (bitCost < best.bitCost) best = { op: ROW_DELTA_OP_REPEAT, extendedOp: -1, predictor, changes, bitCost };
        continue;
      }
      const predictorCost = allowShiftPredictors ? encoderCompactPredictorBitCost(predictor) : 0;
      const positionBits = bitLength(rowLength - 1);
      const indexedCost = ROW_DELTA_OP_BITS + predictorCost + bitLength(rowLength) +
        changes.length * (positionBits + valueBits);
      if (indexedCost < best.bitCost) best = { op: ROW_DELTA_OP_INDEXED, extendedOp: -1, predictor, changes, bitCost: indexedCost };
      if (changes.length === 0) continue;
      const maskCost = ROW_DELTA_OP_BITS + ROW_DELTA_EXTENDED_BITS + predictorCost + rowLength + changes.length * valueBits;
      if (maskCost < best.bitCost) best = { op: ROW_DELTA_OP_EXTENDED, extendedOp: ROW_DELTA_EXTENDED_MASK, predictor, changes, bitCost: maskCost };
      const segments = encoderRowDeltaSegments(changes);
      const segmentCost = ROW_DELTA_OP_BITS + ROW_DELTA_EXTENDED_BITS + predictorCost +
        bitLength(rowLength - 1) + segments.length * positionBits * 2 + changes.length * valueBits;
      if (segmentCost < best.bitCost) best = { op: ROW_DELTA_OP_EXTENDED, extendedOp: ROW_DELTA_EXTENDED_SEGMENTS, predictor, changes, bitCost: segmentCost };
      if (encoderSameRowDeltaValue(changes) != null) {
        const sameCost = ROW_DELTA_OP_BITS + ROW_DELTA_EXTENDED_BITS + predictorCost + rowLength + valueBits;
        if (sameCost < best.bitCost) best = { op: ROW_DELTA_OP_EXTENDED, extendedOp: ROW_DELTA_EXTENDED_SAME_SCALAR_MASK, predictor, changes, bitCost: sameCost };
      }
    }
    return best;
  }

  function rowDeltaVariantBitCost(values, rowLength, valueBits, useVirtualBaseRow, allowShiftPredictors) {
    let cost = useVirtualBaseRow ? 0 : rowLength * valueBits;
    const rowCount = values.length / rowLength;
    let row = useVirtualBaseRow ? 0 : 1;
    while (row < rowCount) {
      const repeatCount = encoderRepeatedRowCount(values, rowLength, row, useVirtualBaseRow);
      if (repeatCount >= 2) {
        const repeatRunCost = ROW_DELTA_OP_BITS + ROW_DELTA_EXTENDED_BITS + rangeCompactUintBitLength(repeatCount - 2, rowCount - row - 2);
        if (repeatRunCost < repeatCount * ROW_DELTA_OP_BITS) { cost += repeatRunCost; row += repeatCount; continue; }
      }
      cost += bestEncoderRowDeltaDecision(values, rowLength, valueBits, row, useVirtualBaseRow, allowShiftPredictors).bitCost;
      row++;
    }
    return cost;
  }

  function writeEncoderRowDeltaMask(writer, changes, rowLength, valueBits, sameScalar) {
    let ci = 0;
    for (let x = 0; x < rowLength; x++) {
      const changed = ci < changes.length && changes[ci].x === x;
      writer.writeBits(changed ? 1 : 0, 1);
      if (changed) ci++;
    }
    if (sameScalar) writer.writeBits(encoderSameRowDeltaValue(changes), valueBits);
    else for (const change of changes) writer.writeBits(change.value, valueBits);
  }

  function writeEncoderRowDeltaSegments(writer, changes, rowLength, valueBits) {
    const segments = encoderRowDeltaSegments(changes);
    const positionBits = bitLength(rowLength - 1);
    writer.writeBits(segments.length - 1, bitLength(rowLength - 1));
    for (const segment of segments) {
      writer.writeBits(segment.x, positionBits);
      writer.writeBits(segment.length - 1, positionBits);
      for (const value of segment.values) writer.writeBits(value, valueBits);
    }
  }

  function writeEncoderRowDeltaDecision(writer, values, rowLength, valueBits, row, decision, allowShiftPredictors) {
    writer.writeBits(decision.op, ROW_DELTA_OP_BITS);
    if (decision.op === ROW_DELTA_OP_REPEAT) return;
    if (decision.op === ROW_DELTA_OP_RAW) {
      const start = row * rowLength;
      for (let x = 0; x < rowLength; x++) writer.writeBits(values[start + x], valueBits);
      return;
    }
    if (decision.op === ROW_DELTA_OP_INDEXED) {
      if (allowShiftPredictors) writeEncoderCompactPredictor(writer, decision.predictor);
      writer.writeBits(decision.changes.length, bitLength(rowLength));
      const positionBits = bitLength(rowLength - 1);
      for (const change of decision.changes) {
        writer.writeBits(change.x, positionBits);
        writer.writeBits(change.value, valueBits);
      }
      return;
    }
    if (decision.op !== ROW_DELTA_OP_EXTENDED || decision.extendedOp === ROW_DELTA_EXTENDED_REPEAT_RUN) {
      throw new MCOImageV3InvalidInputError('Invalid row-delta decision');
    }
    writer.writeBits(decision.extendedOp, ROW_DELTA_EXTENDED_BITS);
    if (allowShiftPredictors) writeEncoderCompactPredictor(writer, decision.predictor);
    if (decision.extendedOp === ROW_DELTA_EXTENDED_MASK) writeEncoderRowDeltaMask(writer, decision.changes, rowLength, valueBits, false);
    else if (decision.extendedOp === ROW_DELTA_EXTENDED_SEGMENTS) writeEncoderRowDeltaSegments(writer, decision.changes, rowLength, valueBits);
    else if (decision.extendedOp === ROW_DELTA_EXTENDED_SAME_SCALAR_MASK) writeEncoderRowDeltaMask(writer, decision.changes, rowLength, valueBits, true);
    else throw new MCOImageV3InvalidInputError('Invalid row-delta extended op');
  }

  function writeEncoderRowDeltaVariant(writer, values, rowLength, valueBits, useVirtualBaseRow, allowShiftPredictors) {
    if (!useVirtualBaseRow) for (let x = 0; x < rowLength; x++) writer.writeBits(values[x], valueBits);
    const rowCount = values.length / rowLength;
    let row = useVirtualBaseRow ? 0 : 1;
    while (row < rowCount) {
      const repeatCount = encoderRepeatedRowCount(values, rowLength, row, useVirtualBaseRow);
      if (repeatCount >= 2) {
        const repeatRunCost = ROW_DELTA_OP_BITS + ROW_DELTA_EXTENDED_BITS + rangeCompactUintBitLength(repeatCount - 2, rowCount - row - 2);
        if (repeatRunCost < repeatCount * ROW_DELTA_OP_BITS) {
          writer.writeBits(ROW_DELTA_OP_EXTENDED, ROW_DELTA_OP_BITS);
          writer.writeBits(ROW_DELTA_EXTENDED_REPEAT_RUN, ROW_DELTA_EXTENDED_BITS);
          writer.writeRangeCompactUint(repeatCount - 2, rowCount - row - 2);
          row += repeatCount;
          continue;
        }
      }
      writeEncoderRowDeltaDecision(writer, values, rowLength, valueBits, row,
        bestEncoderRowDeltaDecision(values, rowLength, valueBits, row, useVirtualBaseRow, allowShiftPredictors),
        allowShiftPredictors);
      row++;
    }
  }

  function writeRowDeltaBodyEncoder(writer, values, rowLength, valueBits) {
    if (rowLength <= 0 || values.length % rowLength !== 0) throw new MCOImageV3InvalidInputError('Invalid row-delta geometry');
    if (values.length === 0) return;
    const costs = {};
    for (const shift of [false, true]) for (const virtual of [false, true]) {
      costs[`${shift}:${virtual}`] = rowDeltaVariantBitCost(values, rowLength, valueBits, virtual, shift);
    }
    const noShiftCost = Math.min(costs['false:false'], costs['false:true']);
    const shiftCost = Math.min(costs['true:false'], costs['true:true']);
    const allowShift = shiftCost < noShiftCost;
    const useVirtual = allowShift
      ? costs['true:true'] < costs['true:false']
      : costs['false:true'] < costs['false:false'];
    writer.writeBits(useVirtual ? 1 : 0, 1);
    writer.writeBits(allowShift ? 1 : 0, 1);
    writeEncoderRowDeltaVariant(writer, values, rowLength, valueBits, useVirtual, allowShift);
  }

  function encoderGrayscaleDeltaCode(delta) {
    if (delta === 0) return 0;
    return delta > 0 ? delta * 2 - 1 : (-delta) * 2;
  }

  function encoderCompactGrayscaleDelta(values, rowLength, row, change, predictor, useVirtualBaseRow) {
    return change.value - compactRowDeltaPredictedValue(
      values, rowLength, row, change.x, predictor, useVirtualBaseRow,
    );
  }

  function encoderCompactChangePositionsBitCost(changes, rowLength) {
    let cost = 0;
    let previousX = -1;
    for (let i = 0; i < changes.length; i++) {
      const remaining = changes.length - i - 1;
      const maxGap = rowLength - previousX - remaining - 2;
      cost += rangeCompactUintBitLength(changes[i].x - previousX - 1, maxGap);
      previousX = changes[i].x;
    }
    return cost;
  }

  function bestEncoderCompactValueEncoding(values, rowLength, row, changes, valueBits, predictor, useVirtualBaseRow, directGrayscale) {
    const absoluteCost = changes.length * valueBits;
    if (!directGrayscale) return { useResidual: false, bitCost: absoluteCost };
    let residualCost = 0;
    for (const change of changes) {
      const code = encoderGrayscaleDeltaCode(encoderCompactGrayscaleDelta(
        values, rowLength, row, change, predictor, useVirtualBaseRow,
      ));
      if (code <= 0) return { useResidual: false, bitCost: 1 + absoluteCost };
      residualCost += compactUintBitLength(code - 1);
    }
    return residualCost < absoluteCost
      ? { useResidual: true, bitCost: 1 + residualCost }
      : { useResidual: false, bitCost: 1 + absoluteCost };
  }

  function bestEncoderCompactSameScalarEncoding(values, rowLength, row, changes, valueBits, predictor, useVirtualBaseRow, directGrayscale) {
    const absolute = encoderSameRowDeltaValue(changes);
    let best = absolute == null ? null : { useResidual: false, bitCost: valueBits + (directGrayscale ? 1 : 0) };
    // The wire op assigns one decoded scalar to every changed position.
    // Residual form is therefore representable only when the final absolute
    // value is shared as well; equal deltas alone are insufficient when the
    // predictor varies across positions.
    if (!directGrayscale || absolute == null) return best;
    let sharedDelta = null;
    for (const change of changes) {
      const delta = encoderCompactGrayscaleDelta(values, rowLength, row, change, predictor, useVirtualBaseRow);
      if (sharedDelta != null && sharedDelta !== delta) return best;
      sharedDelta = delta;
    }
    const code = encoderGrayscaleDeltaCode(sharedDelta);
    if (code <= 0) return best;
    const residual = { useResidual: true, bitCost: 1 + compactUintBitLength(code - 1) };
    return residual.bitCost < best.bitCost ? residual : best;
  }

  function bestEncoderCompactRowDeltaDecision(values, rowLength, valueBits, row, useVirtualBaseRow, directGrayscale) {
    let best = {
      op: COMPACT_ROW_DELTA_OP_RAW, predictor: ROW_DELTA_PREDICTOR_SAME,
      changes: [], useResidual: false,
      bitCost: COMPACT_ROW_DELTA_OP_BITS + rowLength * valueBits,
    };
    for (const predictor of encoderRowDeltaPredictors(row, useVirtualBaseRow)) {
      const changes = encoderRowDeltaChanges(values, rowLength, row, useVirtualBaseRow, predictor);
      if (changes.length === 0) {
        const decision = {
          op: predictor === ROW_DELTA_PREDICTOR_SAME ? COMPACT_ROW_DELTA_OP_REPEAT : COMPACT_ROW_DELTA_OP_PREDICTED,
          predictor, changes, useResidual: false,
          bitCost: COMPACT_ROW_DELTA_OP_BITS + (predictor === ROW_DELTA_PREDICTOR_SAME ? 0 : encoderCompactPredictorBitCost(predictor)),
        };
        if (decision.bitCost < best.bitCost) best = decision;
        continue;
      }
      const predictorCost = encoderCompactPredictorBitCost(predictor);
      const positionCost = encoderCompactChangePositionsBitCost(changes, rowLength);
      const valuesEncoding = bestEncoderCompactValueEncoding(
        values, rowLength, row, changes, valueBits, predictor, useVirtualBaseRow, directGrayscale,
      );
      const indexedCost = COMPACT_ROW_DELTA_OP_BITS + predictorCost +
        rangeCompactUintBitLength(changes.length - 1, rowLength - 1) + positionCost + valuesEncoding.bitCost;
      if (indexedCost < best.bitCost) best = {
        op: COMPACT_ROW_DELTA_OP_INDEXED, predictor, changes,
        useResidual: valuesEncoding.useResidual, bitCost: indexedCost,
      };
      const sameScalar = bestEncoderCompactSameScalarEncoding(
        values, rowLength, row, changes, valueBits, predictor, useVirtualBaseRow, directGrayscale,
      );
      if (sameScalar) {
        const sameCost = COMPACT_ROW_DELTA_OP_BITS + predictorCost +
          rangeCompactUintBitLength(changes.length - 1, rowLength - 1) + positionCost + sameScalar.bitCost;
        if (sameCost < best.bitCost) best = {
          op: COMPACT_ROW_DELTA_OP_SAME_SCALAR, predictor, changes,
          useResidual: sameScalar.useResidual, bitCost: sameCost,
        };
      }
      const segments = encoderRowDeltaSegments(changes);
      let geometryCost = rangeCompactUintBitLength(segments.length - 1, rowLength - 1);
      let previousEnd = 0;
      for (let i = 0; i < segments.length; i++) {
        const segment = segments[i];
        const remaining = segments.length - i - 1;
        const gap = segment.x - previousEnd;
        const maxGap = rowLength - previousEnd - remaining - 1;
        const maxLength = rowLength - segment.x - remaining;
        geometryCost += rangeCompactUintBitLength(gap, maxGap) +
          rangeCompactUintBitLength(segment.length - 1, maxLength - 1);
        previousEnd = segment.x + segment.length;
      }
      const segmentCost = COMPACT_ROW_DELTA_OP_BITS + predictorCost + geometryCost + valuesEncoding.bitCost;
      if (segmentCost < best.bitCost) best = {
        op: COMPACT_ROW_DELTA_OP_SEGMENTS, predictor, changes,
        useResidual: valuesEncoding.useResidual, bitCost: segmentCost,
      };
      const span = changes[changes.length - 1].x - changes[0].x + 1;
      const maskCost = COMPACT_ROW_DELTA_OP_BITS + predictorCost +
        rangeCompactUintBitLength(changes[0].x, rowLength - 1) +
        rangeCompactUintBitLength(span - 1, rowLength - changes[0].x - 1) +
        span + valuesEncoding.bitCost;
      if (maskCost < best.bitCost) best = {
        op: COMPACT_ROW_DELTA_OP_TRIMMED_MASK, predictor, changes,
        useResidual: valuesEncoding.useResidual, bitCost: maskCost,
      };
    }
    return best;
  }

  function compactRowDeltaVariantBitCost(values, rowLength, valueBits, directGrayscale, useVirtualBaseRow) {
    let cost = useVirtualBaseRow ? 0 : rowLength * valueBits;
    const rowCount = values.length / rowLength;
    let row = useVirtualBaseRow ? 0 : 1;
    while (row < rowCount) {
      const repeatCount = encoderRepeatedRowCount(values, rowLength, row, useVirtualBaseRow);
      if (repeatCount >= 2) {
        cost += COMPACT_ROW_DELTA_OP_BITS + rangeCompactUintBitLength(repeatCount - 2, rowCount - row - 2);
        row += repeatCount;
      } else {
        cost += bestEncoderCompactRowDeltaDecision(
          values, rowLength, valueBits, row, useVirtualBaseRow, directGrayscale,
        ).bitCost;
        row++;
      }
    }
    return cost;
  }

  function writeEncoderCompactChangePositions(writer, changes, rowLength) {
    let previousX = -1;
    for (let i = 0; i < changes.length; i++) {
      const remaining = changes.length - i - 1;
      const maxGap = rowLength - previousX - remaining - 2;
      writer.writeRangeCompactUint(changes[i].x - previousX - 1, maxGap);
      previousX = changes[i].x;
    }
  }

  function writeEncoderCompactChangedValues(writer, values, rowLength, valueBits, row, changes, predictor, useVirtualBaseRow, useResidual) {
    for (const change of changes) {
      if (useResidual) {
        const code = encoderGrayscaleDeltaCode(encoderCompactGrayscaleDelta(
          values, rowLength, row, change, predictor, useVirtualBaseRow,
        ));
        writer.writeCompactUint(code - 1);
      } else writer.writeBits(change.value, valueBits);
    }
  }

  function writeEncoderCompactRowDeltaDecision(writer, values, rowLength, valueBits, row, decision, useVirtualBaseRow, directGrayscale) {
    writer.writeBits(decision.op, COMPACT_ROW_DELTA_OP_BITS);
    if (decision.op === COMPACT_ROW_DELTA_OP_REPEAT) return;
    const rowStart = row * rowLength;
    if (decision.op === COMPACT_ROW_DELTA_OP_RAW) {
      for (let x = 0; x < rowLength; x++) writer.writeBits(values[rowStart + x], valueBits);
      return;
    }
    writeEncoderCompactPredictor(writer, decision.predictor);
    if (decision.op === COMPACT_ROW_DELTA_OP_PREDICTED) return;
    if (directGrayscale) writer.writeBits(decision.useResidual ? 1 : 0, 1);
    const changes = decision.changes;
    if (decision.op === COMPACT_ROW_DELTA_OP_INDEXED || decision.op === COMPACT_ROW_DELTA_OP_SAME_SCALAR) {
      writer.writeRangeCompactUint(changes.length - 1, rowLength - 1);
      writeEncoderCompactChangePositions(writer, changes, rowLength);
      if (decision.op === COMPACT_ROW_DELTA_OP_SAME_SCALAR) {
        if (decision.useResidual) {
          const code = encoderGrayscaleDeltaCode(encoderCompactGrayscaleDelta(
            values, rowLength, row, changes[0], decision.predictor, useVirtualBaseRow,
          ));
          writer.writeCompactUint(code - 1);
        } else writer.writeBits(changes[0].value, valueBits);
      } else {
        writeEncoderCompactChangedValues(writer, values, rowLength, valueBits, row, changes,
          decision.predictor, useVirtualBaseRow, decision.useResidual);
      }
      return;
    }
    if (decision.op === COMPACT_ROW_DELTA_OP_SEGMENTS) {
      const segments = encoderRowDeltaSegments(changes);
      writer.writeRangeCompactUint(segments.length - 1, rowLength - 1);
      let previousEnd = 0;
      for (let i = 0; i < segments.length; i++) {
        const segment = segments[i];
        const remaining = segments.length - i - 1;
        const gap = segment.x - previousEnd;
        const maxGap = rowLength - previousEnd - remaining - 1;
        const maxLength = rowLength - segment.x - remaining;
        writer.writeRangeCompactUint(gap, maxGap);
        writer.writeRangeCompactUint(segment.length - 1, maxLength - 1);
        previousEnd = segment.x + segment.length;
      }
      writeEncoderCompactChangedValues(writer, values, rowLength, valueBits, row, changes,
        decision.predictor, useVirtualBaseRow, decision.useResidual);
      return;
    }
    if (decision.op === COMPACT_ROW_DELTA_OP_TRIMMED_MASK) {
      const start = changes[0].x;
      const span = changes[changes.length - 1].x - start + 1;
      writer.writeRangeCompactUint(start, rowLength - 1);
      writer.writeRangeCompactUint(span - 1, rowLength - start - 1);
      let ci = 0;
      for (let offset = 0; offset < span; offset++) {
        const changed = ci < changes.length && changes[ci].x === start + offset;
        writer.writeBits(changed ? 1 : 0, 1);
        if (changed) ci++;
      }
      writeEncoderCompactChangedValues(writer, values, rowLength, valueBits, row, changes,
        decision.predictor, useVirtualBaseRow, decision.useResidual);
      return;
    }
    throw new MCOImageV3InvalidInputError('Invalid compact row-delta op');
  }

  function writeCompactRowDeltaBodyEncoder(writer, values, rowLength, valueBits, directGrayscale) {
    if (rowLength <= 0 || values.length % rowLength !== 0) throw new MCOImageV3InvalidInputError('Invalid compact row-delta geometry');
    const rawCost = compactRowDeltaVariantBitCost(values, rowLength, valueBits, directGrayscale, false);
    const virtualCost = compactRowDeltaVariantBitCost(values, rowLength, valueBits, directGrayscale, true);
    const useVirtual = virtualCost < rawCost;
    writer.writeBits(useVirtual ? 1 : 0, 1);
    if (!useVirtual) for (let x = 0; x < rowLength; x++) writer.writeBits(values[x], valueBits);
    const rowCount = values.length / rowLength;
    let row = useVirtual ? 0 : 1;
    while (row < rowCount) {
      const repeatCount = encoderRepeatedRowCount(values, rowLength, row, useVirtual);
      if (repeatCount >= 2) {
        writer.writeBits(COMPACT_ROW_DELTA_OP_REPEAT_RUN, COMPACT_ROW_DELTA_OP_BITS);
        writer.writeRangeCompactUint(repeatCount - 2, rowCount - row - 2);
        row += repeatCount;
      } else {
        writeEncoderCompactRowDeltaDecision(writer, values, rowLength, valueBits, row,
          bestEncoderCompactRowDeltaDecision(values, rowLength, valueBits, row, useVirtual, directGrayscale),
          useVirtual, directGrayscale);
        row++;
      }
    }
  }

  function lzKey(pixels, position, localBits) {
    return ((pixels[position] << (localBits * 2)) | (pixels[position + 1] << localBits) | pixels[position + 2]);
  }

  function addLzPosition(map, pixels, position, localBits) {
    if (position + MIN_LZ_MATCH_LENGTH > pixels.length) return;
    const key = lzKey(pixels, position, localBits);
    let list = map.get(key);
    if (!list) { list = []; map.set(key, list); }
    list.push(position);
    if (list.length > 32) list.shift();
  }

  function buildGreedyLzTokens(pixels, localBits) {
    const cacheKey = activeLzTokenCache == null ? null : `g|${localBits}|${valueListCacheKey(pixels)}`;
    if (cacheKey != null && activeLzTokenCache.has(cacheKey)) return activeLzTokenCache.get(cacheKey);
    const tokens = [], pending = [], positions = new Map();
    const flush = () => { if (pending.length) tokens.push({ isMatch: false, literals: pending.splice(0) }); };
    let position = 0;
    while (position < pixels.length) {
      let bestLength = 0, bestDistance = 0;
      if (position + MIN_LZ_MATCH_LENGTH <= pixels.length) {
        const candidates = positions.get(lzKey(pixels, position, localBits));
        if (candidates) for (let i = candidates.length - 1; i >= 0; i--) {
          const previous = candidates[i], distance = position - previous;
          let length = MIN_LZ_MATCH_LENGTH;
          while (position + length < pixels.length && pixels[previous + length] === pixels[position + length]) length++;
          if (length > bestLength || (length === bestLength && (bestDistance === 0 || distance < bestDistance))) {
            bestLength = length; bestDistance = distance;
          }
        }
      }
      const remaining = pixels.length - position;
      const matchBits = bestLength >= MIN_LZ_MATCH_LENGTH
        ? 1 + rangeCompactUintBitLength(bestDistance - 1, position - 1) +
          rangeCompactUintBitLength(bestLength - MIN_LZ_MATCH_LENGTH, remaining - MIN_LZ_MATCH_LENGTH)
        : 0;
      const literalBits = bestLength >= MIN_LZ_MATCH_LENGTH
        ? 1 + rangeCompactUintBitLength(bestLength - 1, remaining - 1) + bestLength * localBits
        : 0;
      if (bestLength >= MIN_LZ_MATCH_LENGTH && matchBits < literalBits) {
        flush();
        tokens.push({ isMatch: true, distance: bestDistance, length: bestLength, literals: [] });
        for (let i = 0; i < bestLength; i++) addLzPosition(positions, pixels, position + i, localBits);
        position += bestLength;
      } else {
        pending.push(pixels[position]);
        addLzPosition(positions, pixels, position, localBits);
        position++;
      }
    }
    flush();
    if (cacheKey != null) activeLzTokenCache.set(cacheKey, tokens);
    return tokens;
  }

  function lzTokensBitCost(tokens, localBits, totalLength) {
    let cost = 0, produced = 0;
    for (const token of tokens) {
      const remaining = totalLength - produced;
      if (token.isMatch) {
        cost += 1 + rangeCompactUintBitLength(token.distance - 1, produced - 1) +
          rangeCompactUintBitLength(token.length - MIN_LZ_MATCH_LENGTH, remaining - MIN_LZ_MATCH_LENGTH);
        produced += token.length;
      } else {
        cost += 1 + rangeCompactUintBitLength(token.literals.length - 1, remaining - 1) + token.literals.length * localBits;
        produced += token.literals.length;
      }
    }
    return cost;
  }

  function buildOptimalLzTokens(pixels, localBits) {
    const cacheKey = activeLzTokenCache == null ? null : `o|${localBits}|${valueListCacheKey(pixels)}`;
    if (cacheKey != null && activeLzTokenCache.has(cacheKey)) return activeLzTokenCache.get(cacheKey);
    const n = pixels.length;
    if (n === 0) return [];
    const dp = new Array(n + 1).fill(Number.POSITIVE_INFINITY);
    const step = new Array(n).fill(null);
    dp[n] = 0;
    for (let pos = n - 1; pos >= 0; pos--) {
      const remaining = n - pos;
      for (let length = 1; length <= remaining; length++) {
        const cost = 1 + rangeCompactUintBitLength(length - 1, remaining - 1) + length * localBits + dp[pos + length];
        if (cost < dp[pos] || (cost === dp[pos] && (!step[pos] || pos + length > step[pos].end))) {
          dp[pos] = cost; step[pos] = { end: pos + length, distance: 0 };
        }
      }
      if (pos + MIN_LZ_MATCH_LENGTH > n || pos === 0) continue;
      const bestByDistanceCost = new Map();
      for (let previous = pos - 1; previous >= 0; previous--) {
        if (pixels[previous] !== pixels[pos] || pixels[previous + 1] !== pixels[pos + 1] || pixels[previous + 2] !== pixels[pos + 2]) continue;
        const distance = pos - previous;
        let maxLength = MIN_LZ_MATCH_LENGTH;
        while (pos + maxLength < n && pixels[pos + maxLength - distance] === pixels[pos + maxLength]) maxLength++;
        const distanceCost = rangeCompactUintBitLength(distance - 1, pos - 1);
        const existing = bestByDistanceCost.get(distanceCost);
        if (!existing || maxLength > existing.maxLength || (maxLength === existing.maxLength && distance < existing.distance)) {
          bestByDistanceCost.set(distanceCost, { distance, maxLength, distanceCost });
        }
      }
      for (const match of bestByDistanceCost.values()) {
        for (let length = MIN_LZ_MATCH_LENGTH; length <= match.maxLength; length++) {
          const cost = 1 + match.distanceCost +
            rangeCompactUintBitLength(length - MIN_LZ_MATCH_LENGTH, remaining - MIN_LZ_MATCH_LENGTH) + dp[pos + length];
          if (cost < dp[pos] || (cost === dp[pos] && (!step[pos] || pos + length > step[pos].end))) {
            dp[pos] = cost; step[pos] = { end: pos + length, distance: match.distance };
          }
        }
      }
    }
    if (!step[0]) return null;
    const tokens = [];
    let position = 0;
    while (position < n) {
      const s = step[position];
      if (!s || s.end <= position) return null;
      if (s.distance === 0) tokens.push({ isMatch: false, literals: pixels.slice(position, s.end) });
      else tokens.push({ isMatch: true, distance: s.distance, length: s.end - position, literals: [] });
      position = s.end;
    }
    if (cacheKey != null) activeLzTokenCache.set(cacheKey, tokens);
    return tokens;
  }

  function writeLzTokens(writer, tokens, localBits, totalLength) {
    let produced = 0;
    for (const token of tokens) {
      const remaining = totalLength - produced;
      if (token.isMatch) {
        writer.writeBits(1, 1);
        writer.writeRangeCompactUint(token.distance - 1, produced - 1);
        writer.writeRangeCompactUint(token.length - MIN_LZ_MATCH_LENGTH, remaining - MIN_LZ_MATCH_LENGTH);
        produced += token.length;
      } else {
        writer.writeBits(0, 1);
        writer.writeRangeCompactUint(token.literals.length - 1, remaining - 1);
        for (const value of token.literals) writer.writeBits(value, localBits);
        produced += token.literals.length;
      }
    }
    if (produced !== totalLength) throw new MCOImageV3InvalidInputError('LZ tokens do not fill block');
  }

  function writeQuadtreeNodeEncoder(writer, pixels, stride, x, y, width, height, bits) {
    const first = pixels[y * stride + x];
    let solid = true;
    for (let dy = 0; dy < height && solid; dy++) for (let dx = 0; dx < width; dx++) {
      if (pixels[(y + dy) * stride + x + dx] !== first) { solid = false; break; }
    }
    if (solid) { writer.writeBits(1, 1); writer.writeBits(first, bits); return; }
    writer.writeBits(0, 1);
    if (width === 1) {
      const top = Math.floor(height / 2);
      writeQuadtreeNodeEncoder(writer, pixels, stride, x, y, width, top, bits);
      writeQuadtreeNodeEncoder(writer, pixels, stride, x, y + top, width, height - top, bits);
    } else if (height === 1) {
      const left = Math.floor(width / 2);
      writeQuadtreeNodeEncoder(writer, pixels, stride, x, y, left, height, bits);
      writeQuadtreeNodeEncoder(writer, pixels, stride, x + left, y, width - left, height, bits);
    } else {
      const left = Math.floor(width / 2), top = Math.floor(height / 2);
      writeQuadtreeNodeEncoder(writer, pixels, stride, x, y, left, top, bits);
      writeQuadtreeNodeEncoder(writer, pixels, stride, x + left, y, width - left, top, bits);
      writeQuadtreeNodeEncoder(writer, pixels, stride, x, y + top, left, height - top, bits);
      writeQuadtreeNodeEncoder(writer, pixels, stride, x + left, y + top, width - left, height - top, bits);
    }
  }

  function writeRowRepeatEncoder(writer, pixels, rowLength, bits) {
    if (rowLength <= 0 || pixels.length % rowLength !== 0) throw new MCOImageV3InvalidInputError('Invalid row-repeat geometry');
    for (let x = 0; x < rowLength; x++) writer.writeBits(pixels[x], bits);
    const rows = pixels.length / rowLength;
    for (let row = 1; row < rows; row++) {
      const start = row * rowLength, previous = start - rowLength;
      let same = true;
      for (let x = 0; x < rowLength; x++) if (pixels[start + x] !== pixels[previous + x]) { same = false; break; }
      writer.writeBits(same ? 1 : 0, 1);
      if (!same) for (let x = 0; x < rowLength; x++) writer.writeBits(pixels[start + x], bits);
    }
  }

  function biColorForeground(linear, backgroundColor) {
    let foreground = null;
    for (const pixel of linear) {
      if (pixel === backgroundColor) continue;
      if (foreground == null) foreground = pixel;
      else if (pixel !== foreground) return null;
    }
    return foreground;
  }

  function writeBlockBodyEncoder(writer, linear, profile, algorithm, options) {
    const backgroundColor = options.backgroundColor;
    const rowLength = options.rowLength;
    const backgroundInherited = !!options.backgroundInherited;
    const high = !!options.useHighCompressionExtras;
    const reduced = !!options.reducedCostEvaluator;
    const optimizePaletteOrder = high && !reduced;
    const localBlock = (config, bodyWriter) => writeBestLocalPaletteBlock(writer, linear, profile, {
      indexOrderSensitive: !!config.indexOrderSensitive,
      includeTransitionOrder: optimizePaletteOrder,
      includeBitplaneOptimizedOrder: optimizePaletteOrder && !!config.includeBitplaneOptimizedOrder,
      includeRgbOrder: optimizePaletteOrder && !!config.includeRgbOrder,
      preferredFirstColor: config.preferredFirstColor,
    }, bodyWriter);
    switch (algorithm) {
      case MCOImageV3BlockAlgorithm.rawGlobal:
        for (const color of linear) writeColorRef(writer, profile, color);
        return;
      case MCOImageV3BlockAlgorithm.rawLocal:
        localBlock({}, (w, pixels, bits) => { for (const p of pixels) w.writeBits(p, bits); }); return;
      case MCOImageV3BlockAlgorithm.compactRle:
        localBlock({}, (w, pixels, bits) => { let consumed = 0; for (const run of buildRuns(pixels)) {
          w.writeBits(run.color, bits); w.writeBoundedCompactUint(run.length - 1, pixels.length - consumed - 1); consumed += run.length;
        }}); return;
      case MCOImageV3BlockAlgorithm.varUintRle:
        localBlock({}, (w, pixels, bits) => { for (const run of buildRuns(pixels)) { w.writeBits(run.color, bits); w.writeBitVarUint(run.length); } }); return;
      case MCOImageV3BlockAlgorithm.lzPixels:
        localBlock({}, (w, pixels, bits) => {
          const greedy = buildGreedyLzTokens(pixels, bits);
          let tokens = greedy;
          if (!reduced && !options.greedyLzOnly && pixels.length <= 1024) {
            const optimal = buildOptimalLzTokens(pixels, bits);
            if (optimal && lzTokensBitCost(optimal, bits, pixels.length) < lzTokensBitCost(greedy, bits, pixels.length)) tokens = optimal;
          }
          writeLzTokens(w, tokens, bits, pixels.length);
        }); return;
      case MCOImageV3BlockAlgorithm.quadtree:
        if (rowLength <= 0 || linear.length % rowLength !== 0) throw new MCOImageV3InvalidInputError('Invalid quadtree geometry');
        localBlock({}, (w, pixels, bits) => writeQuadtreeNodeEncoder(w, pixels, rowLength, 0, 0, rowLength, linear.length / rowLength, bits)); return;
      case MCOImageV3BlockAlgorithm.bitplanes:
        localBlock({ indexOrderSensitive: true, preferredFirstColor: backgroundColor }, (w, pixels, bits) => writeLegacyBitplanesBody(w, pixels, bits)); return;
      case MCOImageV3BlockAlgorithm.adaptiveBitplanes:
        localBlock({ indexOrderSensitive: true, includeBitplaneOptimizedOrder: true, includeRgbOrder: true, preferredFirstColor: backgroundColor },
          (w, pixels, bits) => writeAdaptiveBitplanesBody(w, pixels, bits)); return;
      case MCOImageV3BlockAlgorithm.directBitplanes:
        if (isGrayscaleProfile(profile)) writeAdaptiveBitplanesBody(writer, linear, globalBits(profile));
        else if (isDynamicProfile(profile)) writeAdaptiveBitplanesBody(writer, linear.map(c => colorRefForProfile(profile, c)), globalBits(profile));
        else throw new MCOImageV3InvalidInputError('Direct bitplanes require grayscale or dynamic profile');
        return;
      case MCOImageV3BlockAlgorithm.rowDelta:
        localBlock({ indexOrderSensitive: true, preferredFirstColor: backgroundColor }, (w, pixels, bits) => writeRowDeltaBodyEncoder(w, pixels, rowLength, bits)); return;
      case MCOImageV3BlockAlgorithm.compactRowDelta:
        localBlock({ indexOrderSensitive: true, preferredFirstColor: backgroundColor }, (w, pixels, bits) => writeCompactRowDeltaBodyEncoder(w, pixels, rowLength, bits, false)); return;
      case MCOImageV3BlockAlgorithm.directRowDelta:
        if (isGrayscaleProfile(profile)) writeCompactRowDeltaBodyEncoder(writer, linear, rowLength, globalBits(profile), true);
        else if (isDynamicProfile(profile)) writeCompactRowDeltaBodyEncoder(writer, linear.map(c => colorRefForProfile(profile, c)), rowLength, globalBits(profile), false);
        else throw new MCOImageV3InvalidInputError('Direct row-delta requires grayscale or dynamic profile');
        return;
      case MCOImageV3BlockAlgorithm.varUintSparse:
      case MCOImageV3BlockAlgorithm.compactSparse: {
        if (!backgroundInherited) writeBackgroundRef(writer, profile, backgroundColor, isImplicitWhiteBackground(profile, backgroundColor));
        const analysis = sparseAnalysis(linear, backgroundColor);
        if (!analysis.segments.length || !analysis.foregroundColors.length) throw new MCOImageV3InvalidInputError('Empty sparse body');
        writeLocalPalette(writer, profile, analysis.foregroundColors);
        const map = localIndexMap(analysis.foregroundColors), bits = localBits(analysis.foregroundColors.length);
        if (algorithm === MCOImageV3BlockAlgorithm.varUintSparse) writer.writeBitVarUint(analysis.segments.length);
        else writer.writeBoundedCompactUint(analysis.segments.length - 1, linear.length - 1);
        let pos = 0;
        for (const segment of analysis.segments) {
          if (algorithm === MCOImageV3BlockAlgorithm.varUintSparse) {
            writer.writeBitVarUint(segment.start - pos); writer.writeBits(map.get(segment.color), bits); writer.writeBitVarUint(segment.length);
          } else {
            writer.writeBoundedCompactUint(segment.start - pos, linear.length - pos - 1);
            writer.writeBits(map.get(segment.color), bits);
            writer.writeBoundedCompactUint(segment.length - 1, linear.length - segment.start - 1);
          }
          pos = segment.start + segment.length;
        }
        return;
      }
      case MCOImageV3BlockAlgorithm.biColorMask: {
        const foreground = biColorForeground(linear, backgroundColor);
        if (foreground == null) throw new MCOImageV3InvalidInputError('Not a bi-color image');
        if (!backgroundInherited) writeBackgroundRef(writer, profile, backgroundColor, isImplicitWhiteBackground(profile, backgroundColor));
        writeColorRef(writer, profile, foreground);
        for (const color of linear) writer.writeBits(color === foreground ? 1 : 0, 1);
        return;
      }
      case MCOImageV3BlockAlgorithm.rowRepeat:
        localBlock({}, (w, pixels, bits) => writeRowRepeatEncoder(w, pixels, rowLength, bits)); return;
      default: throw new MCOImageV3InvalidInputError('Unknown block algorithm');
    }
  }

  function tryBuildBlockBodyEncoding(image, linear, algorithm, options) {
    const writer = new BitWriter();
    try {
      writeBlockBodyEncoder(writer, linear, image.paletteProfile, algorithm, options);
    } catch (error) {
      if (error instanceof MCOImageV3CodecError) return null;
      throw error;
    }
    const bitLengthValue = writer.bitLength;
    if (bitLengthValue === 0) return null;
    return { bytes: writer.toBytes(), bitLength: bitLengthValue };
  }

  function tryBuildTopLevelCandidate(image, linear, algorithm, scan, options) {
    if (options.compactHeader && (scan !== ScanMode.h || !canUseCompactBlockHeader(algorithm))) return null;
    if (algorithm === MCOImageV3BlockAlgorithm.quadtree && scan !== ScanMode.h) return null;
    const implicit = blockAlgorithmUsesBackgroundRef(algorithm) && isImplicitWhiteBackground(image.paletteProfile, options.backgroundColor);
    const writer = new BitWriter();
    const container = options.compactHeader ? MCOImageV3Container.compactBlock : MCOImageV3Container.block;
    writeImagePreamble(writer, image, scan, implicit, container, algorithm);
    if (image.transparentColor != null) writeColorRef(writer, image.paletteProfile, image.transparentColor);
    const before = writer.bitLength;
    try {
      writeBlockBodyEncoder(writer, linear, image.paletteProfile, algorithm, {
        backgroundColor: options.backgroundColor,
        rowLength: rowLengthForScan(scan, image.width, image.height),
        backgroundInherited: false,
        greedyLzOnly: options.greedyLzOnly,
        useHighCompressionExtras: options.useHighCompressionExtras,
      });
    } catch (error) {
      if (error instanceof MCOImageV3CodecError) return null;
      throw error;
    }
    if (writer.bitLength === before) return null;
    const payload = writer.toBytes();
    return makeCandidate(payload, {
      mode: imageModeForAlgorithm(algorithm), scan,
      backgroundColor: options.backgroundColor, transparentColor: image.transparentColor,
      localPaletteSize: localPaletteSizeFor(linear, algorithm, options.backgroundColor),
      bitsPerLocalPixel: bitsPerLocalPixelFor(linear, algorithm, options.backgroundColor),
      paletteKind: isDynamicProfile(image.paletteProfile) ? 'dynamic' : 'fixed',
      container: MCOImageV3ContainerName[container], algorithm,
    });
  }

  function tryWrapBoundsCandidate(image, bounds, linear, body, algorithm, scan, options) {
    if (options.compactGeometry && canUseCompactBlockHeader(algorithm) && scan !== ScanMode.h) return null;
    if (algorithm === MCOImageV3BlockAlgorithm.quadtree && scan !== ScanMode.h) return null;
    const implicit = isImplicitWhiteBackground(image.paletteProfile, options.backgroundColor);
    const container = options.compactGeometry ? MCOImageV3Container.compactBoundsBlock : MCOImageV3Container.boundsBlock;
    const writer = new BitWriter();
    writeImagePreamble(writer, image, scan, implicit, container, algorithm);
    if (image.transparentColor != null) writeColorRef(writer, image.paletteProfile, image.transparentColor);
    writeBackgroundRef(writer, image.paletteProfile, options.backgroundColor, implicit);
    writeRegionGeometry(writer, bounds, image.width, image.height, options.compactGeometry);
    writer.writeBitStream(body.bytes, body.bitLength);
    const payload = writer.toBytes();
    return makeCandidate(payload, {
      mode: imageModeForAlgorithm(algorithm), scan,
      backgroundColor: options.backgroundColor, transparentColor: image.transparentColor,
      boundsPresent: true, boundsX: bounds.x, boundsY: bounds.y,
      boundsWidth: bounds.width, boundsHeight: bounds.height,
      localPaletteSize: localPaletteSizeFor(linear, algorithm, options.backgroundColor),
      bitsPerLocalPixel: bitsPerLocalPixelFor(linear, algorithm, options.backgroundColor),
      paletteKind: isDynamicProfile(image.paletteProfile) ? 'dynamic' : 'fixed',
      container: MCOImageV3ContainerName[container], algorithm,
    });
  }

  function tryBuildSolidBackgroundCandidate(image) {
    if (!image.pixels.length) return null;
    const color = image.pixels[0];
    for (const pixel of image.pixels) if (pixel !== color) return null;
    const implicit = isImplicitWhiteBackground(image.paletteProfile, color);
    const ref = implicit ? 0 : colorRefForProfile(image.paletteProfile, color);
    const writer = new BitWriter();
    writeImagePreamble(writer, image, ScanMode.h, implicit, MCOImageV3Container.solidBackground, ref & CONTAINER_CONTEXT_MASK);
    if (image.transparentColor != null) writeColorRef(writer, image.paletteProfile, image.transparentColor);
    if (!implicit) {
      const tail = ref >> 5;
      if (tail > 0) writer.writeBits(tail, Math.max(0, globalBits(image.paletteProfile) - 5));
    }
    return makeCandidate(writer.toBytes(), {
      mode: ImageMode.rawGlobal, scan: ScanMode.h, backgroundColor: color,
      transparentColor: image.transparentColor, localPaletteSize: 1, bitsPerLocalPixel: 0,
      paletteKind: isDynamicProfile(image.paletteProfile) ? 'dynamic' : 'fixed',
      container: MCOImageV3ContainerName[MCOImageV3Container.solidBackground],
    });
  }

  function solidRectVariantsEncoder(pixels, width, height, background, maxRects = 64) {
    const horizontal = [];
    for (let y = 0; y < height; y++) {
      let x = 0;
      while (x < width) {
        const color = pixels[y * width + x];
        if (color === background) { x++; continue; }
        const start = x;
        while (x < width && pixels[y * width + x] === color) x++;
        horizontal.push({ bounds: { x: start, y, width: x - start, height: 1 }, color });
      }
    }
    const vertical = [];
    for (let x = 0; x < width; x++) {
      let y = 0;
      while (y < height) {
        const color = pixels[y * width + x];
        if (color === background) { y++; continue; }
        const start = y;
        while (y < height && pixels[y * width + x] === color) y++;
        vertical.push({ bounds: { x, y: start, width: 1, height: y - start }, color });
      }
    }
    const merge = (runs, verticalMode) => {
      const merged = [], latest = new Map();
      for (const run of runs) {
        const b = run.bounds;
        const key = verticalMode ? `${b.y}:${b.height}:${run.color}` : `${b.x}:${b.width}:${run.color}`;
        const index = latest.get(key);
        if (index != null) {
          const previous = merged[index];
          const touches = verticalMode
            ? previous.bounds.x + previous.bounds.width === b.x
            : previous.bounds.y + previous.bounds.height === b.y;
          if (touches) {
            previous.bounds = {
              x: previous.bounds.x, y: previous.bounds.y,
              width: verticalMode ? previous.bounds.width + b.width : previous.bounds.width,
              height: verticalMode ? previous.bounds.height : previous.bounds.height + b.height,
            };
            continue;
          }
        }
        latest.set(key, merged.length);
        merged.push({ bounds: { ...b }, color: run.color });
      }
      return merged;
    };
    const result = [merge(horizontal, false), merge(vertical, true)];
    return result.filter(rects => rects.length > 0 && rects.length <= maxRects);
  }

  function tryBuildSolidRectsCandidate(image, backgroundColor, backgroundRank) {
    let best = null;
    for (const rects of solidRectVariantsEncoder(image.pixels, image.width, image.height, backgroundColor)) {
      const implicit = isImplicitWhiteBackground(image.paletteProfile, backgroundColor);
      const writer = new BitWriter();
      const code = rects.length - 1;
      writeImagePreamble(writer, image, ScanMode.h, implicit, MCOImageV3Container.solidRects, code & CONTAINER_CONTEXT_MASK);
      if (image.transparentColor != null) writeColorRef(writer, image.paletteProfile, image.transparentColor);
      writeBackgroundRef(writer, image.paletteProfile, backgroundColor, implicit);
      const palette = localPalette(rects.map(r => r.color));
      writeLocalPalette(writer, image.paletteProfile, palette);
      const map = localIndexMap(palette), bits = localBits(palette.length);
      writer.writeBits(code >> 5, 1);
      for (const rect of rects) {
        writeRegionGeometry(writer, rect.bounds, image.width, image.height, true);
        writer.writeBits(map.get(rect.color), bits);
      }
      const candidate = makeCandidate(writer.toBytes(), {
        mode: ImageMode.extended, scan: ScanMode.h, backgroundColor, backgroundRank,
        transparentColor: image.transparentColor, regionCount: rects.length,
        localPaletteSize: palette.length, bitsPerLocalPixel: bits,
        paletteKind: isDynamicProfile(image.paletteProfile) ? 'dynamic' : 'fixed',
        container: MCOImageV3ContainerName[MCOImageV3Container.solidRects],
      });
      if (!best || candidate.byteLength < best.byteLength) best = candidate;
    }
    return best;
  }

  function sortRegionsEncoder(regions) {
    return Array.from(regions, (region) => ({ ...region })).sort((left, right) =>
      (left.y - right.y) || (left.x - right.x) ||
      (left.height - right.height) || (left.width - right.width));
  }

  function regionListKeyEncoder(regions) {
    return regions.map((region) =>
      `${region.x},${region.y},${region.width},${region.height}`).join(';');
  }

  function regionAreaEncoder(region) {
    return region.width * region.height;
  }

  function findComponentRegionsEncoder(pixels, width, height, background) {
    const visited = new Uint8Array(pixels.length), regions = [];
    const neighbors = [[-1,-1],[0,-1],[1,-1],[-1,0],[1,0],[-1,1],[0,1],[1,1]];
    for (let start = 0; start < pixels.length; start++) {
      if (visited[start] || pixels[start] === background) continue;
      let minX = start % width, maxX = minX, minY = Math.floor(start / width), maxY = minY;
      const queue = [start]; visited[start] = 1;
      while (queue.length) {
        const index = queue.pop(), x = index % width, y = Math.floor(index / width);
        minX = Math.min(minX,x); maxX = Math.max(maxX,x); minY = Math.min(minY,y); maxY = Math.max(maxY,y);
        for (const [dx,dy] of neighbors) {
          const nx=x+dx, ny=y+dy;
          if (nx<0||ny<0||nx>=width||ny>=height) continue;
          const next=ny*width+nx;
          if (!visited[next] && pixels[next] !== background) { visited[next]=1; queue.push(next); }
        }
      }
      regions.push({ x:minX,y:minY,width:maxX-minX+1,height:maxY-minY+1 });
    }
    regions.sort((a,b)=>(a.y-b.y)||(a.x-b.x));
    return regions;
  }

  function regionsDoNotOverlapEncoder(regions) {
    for (let i=0;i<regions.length;i++) for (let j=i+1;j<regions.length;j++) {
      const a=regions[i],b=regions[j];
      if (a.x < b.x+b.width && a.x+a.width > b.x && a.y < b.y+b.height && a.y+a.height > b.y) return false;
    }
    return true;
  }

  function sameRegionListEncoder(left, right) {
    if (left.length !== right.length) return false;
    for (let index = 0; index < left.length; index++) {
      const a = left[index], b = right[index];
      if (a.x !== b.x || a.y !== b.y || a.width !== b.width || a.height !== b.height) return false;
    }
    return true;
  }

  function tightBoundsInRectEncoder(pixels, fullWidth, background, rect) {
    if (rect.width <= 0 || rect.height <= 0) return null;
    let minX = rect.x + rect.width, minY = rect.y + rect.height;
    let maxX = rect.x - 1, maxY = rect.y - 1;
    for (let y = rect.y; y < rect.y + rect.height; y++) {
      for (let x = rect.x; x < rect.x + rect.width; x++) {
        if (pixels[y * fullWidth + x] === background) continue;
        minX = Math.min(minX, x); minY = Math.min(minY, y);
        maxX = Math.max(maxX, x); maxY = Math.max(maxY, y);
      }
    }
    return maxX < minX || maxY < minY
      ? null
      : { x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1 };
  }

  function regionRowNonBackgroundCountEncoder(pixels, fullWidth, background, region, y) {
    let count = 0;
    for (let x = region.x; x < region.x + region.width; x++) {
      if (pixels[y * fullWidth + x] !== background) count++;
    }
    return count;
  }

  function regionColumnNonBackgroundCountEncoder(pixels, fullWidth, background, region, x) {
    let count = 0;
    for (let y = region.y; y < region.y + region.height; y++) {
      if (pixels[y * fullWidth + x] !== background) count++;
    }
    return count;
  }

  function partitionIfUsefulEncoder(original, parts) {
    if (parts.length < 2) return null;
    const savedArea = regionAreaEncoder(original) - parts.reduce((sum, part) => sum + regionAreaEncoder(part), 0);
    return savedArea > 0 ? { parts, savedArea } : null;
  }

  function betterRegionPartitionEncoder(left, right) {
    if (left == null) return right;
    if (right == null) return left;
    return left.savedArea >= right.savedArea ? left : right;
  }

  function bestEmptyRowSplitEncoder(pixels, fullWidth, background, region) {
    let best = null;
    for (let y = region.y; y < region.y + region.height; y++) {
      if (regionRowNonBackgroundCountEncoder(pixels, fullWidth, background, region, y) !== 0) continue;
      const parts = [
        tightBoundsInRectEncoder(pixels, fullWidth, background,
          { x: region.x, y: region.y, width: region.width, height: y - region.y }),
        tightBoundsInRectEncoder(pixels, fullWidth, background,
          { x: region.x, y: y + 1, width: region.width, height: region.y + region.height - y - 1 }),
      ].filter(Boolean);
      const partition = partitionIfUsefulEncoder(region, parts);
      if (partition && (best == null || partition.savedArea > best.savedArea)) best = partition;
    }
    return best;
  }

  function bestEmptyColumnSplitEncoder(pixels, fullWidth, background, region) {
    let best = null;
    for (let x = region.x; x < region.x + region.width; x++) {
      if (regionColumnNonBackgroundCountEncoder(pixels, fullWidth, background, region, x) !== 0) continue;
      const parts = [
        tightBoundsInRectEncoder(pixels, fullWidth, background,
          { x: region.x, y: region.y, width: x - region.x, height: region.height }),
        tightBoundsInRectEncoder(pixels, fullWidth, background,
          { x: x + 1, y: region.y, width: region.x + region.width - x - 1, height: region.height }),
      ].filter(Boolean);
      const partition = partitionIfUsefulEncoder(region, parts);
      if (partition && (best == null || partition.savedArea > best.savedArea)) best = partition;
    }
    return best;
  }

  function splitRegionByBestEmptyLineEncoder(pixels, fullWidth, background, region, output, maxRegions) {
    const split = betterRegionPartitionEncoder(
      bestEmptyRowSplitEncoder(pixels, fullWidth, background, region),
      bestEmptyColumnSplitEncoder(pixels, fullWidth, background, region),
    );
    if (!split) { output.push(region); return; }
    for (const part of split.parts) {
      splitRegionByBestEmptyLineEncoder(pixels, fullWidth, background, part, output, maxRegions);
      if (output.length > maxRegions) return;
    }
  }

  function splitRegionsByEmptyLinesEncoder(pixels, fullWidth, background, regions, maxRegions) {
    const output = [];
    for (const region of regions) {
      splitRegionByBestEmptyLineEncoder(pixels, fullWidth, background, region, output, maxRegions);
      if (output.length > maxRegions) return [];
    }
    return sameRegionListEncoder(output, regions) ? [] : output;
  }

  function bestSparseRowSplitEncoder(pixels, fullWidth, background, region, maxLineNonBackground) {
    let best = null, y = region.y;
    while (y < region.y + region.height) {
      const count = regionRowNonBackgroundCountEncoder(pixels, fullWidth, background, region, y);
      if (count > maxLineNonBackground) { y++; continue; }
      const startY = y;
      while (y < region.y + region.height &&
          regionRowNonBackgroundCountEncoder(pixels, fullWidth, background, region, y) <= maxLineNonBackground) y++;
      const endY = y - 1;
      const parts = [
        tightBoundsInRectEncoder(pixels, fullWidth, background,
          { x: region.x, y: region.y, width: region.width, height: startY - region.y }),
        tightBoundsInRectEncoder(pixels, fullWidth, background,
          { x: region.x, y: startY, width: region.width, height: endY - startY + 1 }),
        tightBoundsInRectEncoder(pixels, fullWidth, background,
          { x: region.x, y: endY + 1, width: region.width, height: region.y + region.height - endY - 1 }),
      ].filter(Boolean);
      const partition = partitionIfUsefulEncoder(region, parts);
      if (partition && (best == null || partition.savedArea > best.savedArea)) best = partition;
    }
    return best;
  }

  function bestSparseColumnSplitEncoder(pixels, fullWidth, background, region, maxLineNonBackground) {
    let best = null, x = region.x;
    while (x < region.x + region.width) {
      const count = regionColumnNonBackgroundCountEncoder(pixels, fullWidth, background, region, x);
      if (count > maxLineNonBackground) { x++; continue; }
      const startX = x;
      while (x < region.x + region.width &&
          regionColumnNonBackgroundCountEncoder(pixels, fullWidth, background, region, x) <= maxLineNonBackground) x++;
      const endX = x - 1;
      const parts = [
        tightBoundsInRectEncoder(pixels, fullWidth, background,
          { x: region.x, y: region.y, width: startX - region.x, height: region.height }),
        tightBoundsInRectEncoder(pixels, fullWidth, background,
          { x: startX, y: region.y, width: endX - startX + 1, height: region.height }),
        tightBoundsInRectEncoder(pixels, fullWidth, background,
          { x: endX + 1, y: region.y, width: region.x + region.width - endX - 1, height: region.height }),
      ].filter(Boolean);
      const partition = partitionIfUsefulEncoder(region, parts);
      if (partition && (best == null || partition.savedArea > best.savedArea)) best = partition;
    }
    return best;
  }

  function splitRegionByBestSparseLineEncoder(
    pixels, fullWidth, background, region, output, maxRegions, maxLineNonBackground,
  ) {
    const split = betterRegionPartitionEncoder(
      bestSparseRowSplitEncoder(pixels, fullWidth, background, region, maxLineNonBackground),
      bestSparseColumnSplitEncoder(pixels, fullWidth, background, region, maxLineNonBackground),
    );
    if (!split) { output.push(region); return; }
    for (const part of split.parts) {
      splitRegionByBestSparseLineEncoder(
        pixels, fullWidth, background, part, output, maxRegions, maxLineNonBackground,
      );
      if (output.length > maxRegions) return;
    }
  }

  function splitRegionsBySparseLinesEncoder(
    pixels, fullWidth, background, regions, maxRegions, maxLineNonBackground,
  ) {
    const output = [];
    for (const region of regions) {
      splitRegionByBestSparseLineEncoder(
        pixels, fullWidth, background, region, output, maxRegions, maxLineNonBackground,
      );
      if (output.length > maxRegions) return [];
    }
    return sameRegionListEncoder(output, regions) ? [] : output;
  }

  function greedyRectRegionVariantsEncoder(pixels, width, height, background, maxRegions, firstOnly = false) {
    const strategies = [[1,1,0],[1,1,1],[1,1,2],[-1,1,0],[1,-1,0],[-1,-1,0]];
    const output=[], seen=new Set();
    const runLength=(covered,x,y,h)=>{let n=0;for(let xx=x;xx>=0&&xx<width;xx+=h){const i=y*width+xx;if(covered[i]||pixels[i]===background)break;n++;}return n;};
    for (const [h,v,tie] of strategies) {
      const covered=new Uint8Array(pixels.length), regions=[];
      while (true) {
        let start=-1;
        for(let y=v>0?0:height-1;y!==(v>0?height:-1)&&start<0;y+=v) for(let x=h>0?0:width-1;x!==(h>0?width:-1);x+=h){const i=y*width+x;if(!covered[i]&&pixels[i]!==background){start=i;break;}}
        if(start<0)break;
        const sx=start%width, sy=Math.floor(start/width);
        let bestW=1,bestH=1,maxW=runLength(covered,sx,sy,h);
        for(let ch=1;;ch++){
          const y=sy+(ch-1)*v;if(y<0||y>=height)break;
          const rw=runLength(covered,sx,y,h);if(rw===0)break;maxW=Math.min(maxW,rw);
          const area=maxW*ch,bestArea=bestW*bestH;
          if(area>bestArea||(area===bestArea&&((tie===1&&maxW>bestW)||(tie===2&&ch>bestH)||(tie===0&&ch>bestH)))){bestW=maxW;bestH=ch;}
        }
        const rect={x:h>0?sx:sx-bestW+1,y:v>0?sy:sy-bestH+1,width:bestW,height:bestH};
        regions.push(rect); if(regions.length>maxRegions){regions.length=0;break;}
        for(let y=rect.y;y<rect.y+rect.height;y++)for(let x=rect.x;x<rect.x+rect.width;x++)covered[y*width+x]=1;
      }
      if(!regions.length)continue;
      const sorted = sortRegionsEncoder(regions);
      const key=regionListKeyEncoder(sorted);
      if(!seen.has(key)){
        seen.add(key);output.push(sorted);
        if (firstOnly) break;
      }
    }
    return output;
  }

  function unionBoundsEncoder(left, right) {
    const x = Math.min(left.x, right.x), y = Math.min(left.y, right.y);
    const maxX = Math.max(left.x + left.width, right.x + right.width);
    const maxY = Math.max(left.y + left.height, right.y + right.height);
    return { x, y, width: maxX - x, height: maxY - y };
  }

  function tightSplitRegionEncoder(pixels, fullWidth, background, region, vertical, cut) {
    const first = vertical
      ? { x: region.x, y: region.y, width: cut, height: region.height }
      : { x: region.x, y: region.y, width: region.width, height: cut };
    const second = vertical
      ? { x: region.x + cut, y: region.y, width: region.width - cut, height: region.height }
      : { x: region.x, y: region.y + cut, width: region.width, height: region.height - cut };
    return [
      tightBoundsInRectEncoder(pixels, fullWidth, background, first),
      tightBoundsInRectEncoder(pixels, fullWidth, background, second),
    ].filter(Boolean);
  }

  function regionBeamNeighborsEncoder(
    pixels, fullWidth, background, regions, maxRegions, useExtremeSearch = false,
  ) {
    const mergeNeighbors = [];
    if (regions.length > 1) {
      for (let left = 0; left < regions.length - 1; left++) {
        for (let right = left + 1; right < regions.length; right++) {
          const merged = unionBoundsEncoder(regions[left], regions[right]);
          const candidate = regions.filter((_, index) => index !== left && index !== right).concat([merged]);
          if (!regionsDoNotOverlapEncoder(candidate)) continue;
          const addedArea = regionAreaEncoder(merged) - regionAreaEncoder(regions[left]) - regionAreaEncoder(regions[right]);
          mergeNeighbors.push({ regions: sortRegionsEncoder(candidate), heuristic: addedArea });
        }
      }
    }
    mergeNeighbors.sort((left, right) => left.heuristic - right.heuristic);

    const splitNeighbors = [];
    if (regions.length < maxRegions) {
      for (let index = 0; index < regions.length; index++) {
        const region = regions[index];
        for (let cut = 1; cut < region.width; cut++) {
          const parts = tightSplitRegionEncoder(pixels, fullWidth, background, region, true, cut);
          addRegionSplitNeighborEncoder(splitNeighbors, regions, index, region, parts);
        }
        for (let cut = 1; cut < region.height; cut++) {
          const parts = tightSplitRegionEncoder(pixels, fullWidth, background, region, false, cut);
          addRegionSplitNeighborEncoder(splitNeighbors, regions, index, region, parts);
        }
      }
    }
    splitNeighbors.sort((left, right) => left.heuristic - right.heuristic);

    const result = [], seen = new Set();
    const neighborLimit = useExtremeSearch ? EXTREME_REGION_NEIGHBORS : REGION_BEAM_NEIGHBORS;
    const perKindLimit = Math.max(1, Math.floor(neighborLimit / 2));
    for (const neighbor of mergeNeighbors.slice(0, perKindLimit).concat(splitNeighbors.slice(0, perKindLimit))) {
      const key = regionListKeyEncoder(neighbor.regions);
      if (!seen.has(key)) { seen.add(key); result.push(neighbor.regions); }
    }
    return result;
  }

  function addRegionSplitNeighborEncoder(output, regions, replacedIndex, original, parts) {
    if (parts.length !== 2) return;
    const savedArea = regionAreaEncoder(original) - regionAreaEncoder(parts[0]) - regionAreaEncoder(parts[1]);
    if (savedArea <= 0) return;
    const candidate = regions.filter((_, index) => index !== replacedIndex).concat(parts);
    if (!regionsDoNotOverlapEncoder(candidate)) return;
    output.push({ regions: sortRegionsEncoder(candidate), heuristic: -savedArea });
  }

  function exactRegionPayloadCostEncoder(image, background, regions, high) {
    const planCache = regionPlanCacheEncoder(image, background, regions, high, false);
    let best = tryBuildRegionsCandidateEncoder(image, background, 0, regions, {
      compactGeometry: false,
      commonBlockHeader: false,
      hybridCommonHeader: false,
      deltaGeometry: false,
      sharedLocalPalette: false,
    }, high, false, planCache);
    for (const options of (high ? FULL_REGION_OPTIONS : NORMAL_REGION_OPTIONS)) {
      const candidate = tryBuildRegionsCandidateEncoder(image, background, 0, regions, {
        compactGeometry: true,
        ...options,
      }, high, false, planCache);
      if (candidate && (!best || candidate.byteLength < best.byteLength)) best = candidate;
    }
    return best ? { cost: best.byteLength, planCache } : null;
  }

  function normalSharedCompactRegionPayloadCostEncoder(image, background, regions) {
    const planCache = regionPlanCacheEncoder(image, background, regions, false, false);
    let best = null;
    for (const options of NORMAL_REGION_OPTIONS) {
      if (!options.sharedLocalPalette) continue;
      const candidate = tryBuildRegionsCandidateEncoder(image, background, 0, regions, {
        compactGeometry: true,
        ...options,
      }, false, false, planCache);
      if (candidate && (!best || candidate.byteLength < best.byteLength)) best = candidate;
    }
    return best ? { cost: best.byteLength, planCache } : null;
  }

  function fastRegionPayloadByteCostEncoder(image, background, regions, high) {
    const planCache = regionPlanCacheEncoder(image, background, regions, high, true);
    const individual = tryBuildRegionsCandidateEncoder(image, background, 0, regions, {
      compactGeometry: true,
      commonBlockHeader: false,
      hybridCommonHeader: false,
      deltaGeometry: false,
      sharedLocalPalette: false,
    }, high, true, planCache);
    if (!individual) return null;
    const common = tryBuildRegionsCandidateEncoder(image, background, 0, regions, {
      compactGeometry: true,
      commonBlockHeader: true,
      hybridCommonHeader: false,
      deltaGeometry: true,
      sharedLocalPalette: false,
    }, high, true, planCache);
    return common ? Math.min(individual.byteLength, common.byteLength) : individual.byteLength;
  }

  function regionPayloadByteCostEncoder(image, background, regions, high, reduced) {
    if (reduced) return fastRegionPayloadByteCostEncoder(image, background, regions, high);
    return exactRegionPayloadCostEncoder(image, background, regions, high)?.cost ?? null;
  }

  function findPayloadOptimizedRegionVariantsEncoder(
    image, background, initialVariants, maxRegions, high, useExtremeSearch,
  ) {
    const initialStates = [], seen = new Set();
    for (const regions of initialVariants) {
      if (!regions.length || regions.length > maxRegions || !regionsDoNotOverlapEncoder(regions)) continue;
      const normalized = sortRegionsEncoder(regions), key = regionListKeyEncoder(normalized);
      if (seen.has(key)) continue;
      seen.add(key);
      const cost = regionPayloadByteCostEncoder(image, background, normalized, high, useExtremeSearch);
      if (cost != null) initialStates.push({ regions: normalized, cost, exactPlanCache: null });
    }
    if (!initialStates.length) return [];
    initialStates.sort((left, right) => left.cost - right.cost);
    const bestExistingCost = initialStates[0].cost;
    const beamWidth = useExtremeSearch ? EXTREME_REGION_BEAM_WIDTH : REGION_BEAM_WIDTH;
    const beamDepth = useExtremeSearch ? EXTREME_REGION_BEAM_DEPTH : REGION_BEAM_DEPTH;
    const resultLimit = useExtremeSearch ? EXTREME_REGION_RESULT_LIMIT : REGION_BEAM_WIDTH;
    const evaluationBudget = useExtremeSearch ? EXTREME_REGION_EVALUATION_BUDGET : null;
    let evaluatedLayouts = initialStates.length;
    let budgetExhausted = false;
    let beam = initialStates.slice(0, beamWidth);
    const improved = [], evaluatedStates = [];

    for (let depth = 0; depth < beamDepth; depth++) {
      const next = [];
      for (const state of beam) {
        for (const regions of regionBeamNeighborsEncoder(
          image.pixels, image.width, background, state.regions, maxRegions, useExtremeSearch,
        )) {
          if (evaluationBudget != null && evaluatedLayouts >= evaluationBudget) {
            budgetExhausted = true;
            break;
          }
          const key = regionListKeyEncoder(regions);
          if (seen.has(key)) continue;
          seen.add(key);
          evaluatedLayouts++;
          const cost = regionPayloadByteCostEncoder(image, background, regions, high, useExtremeSearch);
          if (cost == null) continue;
          const candidate = { regions, cost, exactPlanCache: null };
          next.push(candidate);
          evaluatedStates.push(candidate);
          if (cost < bestExistingCost) improved.push(candidate);
        }
        if (budgetExhausted) break;
      }
      if (!next.length) break;
      next.sort((left, right) => left.cost - right.cost);
      beam = next.slice(0, beamWidth);
      emitV3EncodeProgress({
        phase: 'extreme-regions',
        backgroundColor: background,
        depth: depth + 1,
        depthTotal: beamDepth,
        evaluatedLayouts,
        evaluationBudget,
        budgetExhausted,
      });
      if (budgetExhausted) break;
    }

    const source = useExtremeSearch ? improved.concat(evaluatedStates) : improved;
    source.sort((left, right) => left.cost - right.cost);
    const reducedResult = [], resultKeys = new Set();
    const reducedLimit = useExtremeSearch ? EXTREME_REGION_EXACT_RERANK_POOL_SIZE : resultLimit;
    for (const state of source) {
      const key = regionListKeyEncoder(state.regions);
      if (!resultKeys.has(key)) { resultKeys.add(key); reducedResult.push(state); }
      if (reducedResult.length >= reducedLimit) break;
    }
    if (!useExtremeSearch || !reducedResult.length) return reducedResult;

    const exactResult = [];
    for (const state of reducedResult) {
      const exact = exactRegionPayloadCostEncoder(image, background, state.regions, high);
      if (exact) exactResult.push({
        regions: state.regions,
        cost: exact.cost,
        exactPlanCache: exact.planCache,
      });
    }
    if (!exactResult.length) return reducedResult.slice(0, resultLimit);
    exactResult.sort((left, right) => left.cost - right.cost);
    return exactResult.slice(0, resultLimit);
  }

  function findNormalSharedCompactRegionVariantsEncoder(
    image, background, initialVariants, maxRegions,
  ) {
    const initialStates = [], seen = new Set();
    for (const regions of initialVariants) {
      if (!regions.length || regions.length > maxRegions || !regionsDoNotOverlapEncoder(regions)) continue;
      const normalized = sortRegionsEncoder(regions), key = regionListKeyEncoder(normalized);
      if (seen.has(key)) continue;
      seen.add(key);
      const exact = normalSharedCompactRegionPayloadCostEncoder(image, background, normalized);
      if (exact) initialStates.push({ regions: normalized, cost: exact.cost, exactPlanCache: exact.planCache });
    }
    if (!initialStates.length) return [];
    initialStates.sort((left, right) => left.cost - right.cost);
    const bestExistingCost = initialStates[0].cost;
    let beam = initialStates.slice(0, REGION_BEAM_WIDTH);
    const improved = [];
    for (let depth = 0; depth < REGION_BEAM_DEPTH; depth++) {
      const next = [];
      for (const state of beam) {
        for (const regions of regionBeamNeighborsEncoder(
          image.pixels, image.width, background, state.regions, maxRegions, false,
        )) {
          const key = regionListKeyEncoder(regions);
          if (seen.has(key)) continue;
          seen.add(key);
          const exact = normalSharedCompactRegionPayloadCostEncoder(image, background, regions);
          if (!exact) continue;
          const candidate = { regions, cost: exact.cost, exactPlanCache: exact.planCache };
          next.push(candidate);
          if (candidate.cost < bestExistingCost) improved.push(candidate);
        }
      }
      if (!next.length) break;
      next.sort((left, right) => left.cost - right.cost);
      beam = next.slice(0, REGION_BEAM_WIDTH);
    }
    improved.sort((left, right) => left.cost - right.cost);
    const result = [], resultKeys = new Set();
    for (const state of improved) {
      const key = regionListKeyEncoder(state.regions);
      if (!resultKeys.has(key)) { resultKeys.add(key); result.push(state); }
      if (result.length >= REGION_BEAM_WIDTH) break;
    }
    return result;
  }

  function regionVariantsEncoder(image, backgroundColor, maxRegions, high, extreme = false) {
    if (maxRegions === 0) return [];
    const connected = findComponentRegionsEncoder(image.pixels, image.width, image.height, backgroundColor);
    if (!connected.length) return [];
    const useBoundedExtremeSearch = extreme &&
      image.pixels.length <= MAX_EXTREME_REGION_PIXELS &&
      connected.length <= MAX_EXTREME_REGION_COMPONENTS;
    const beamMaxRegions = useBoundedExtremeSearch
      ? Math.min(maxRegions, MAX_EXTREME_REGION_SEARCH_REGIONS)
      : maxRegions;
    const raw = [{ regions: connected, label: null }];
    const split = splitRegionsByEmptyLinesEncoder(
      image.pixels, image.width, backgroundColor, connected, maxRegions,
    );
    if (split.length) raw.push({ regions: split, label: 'split' });
    const sparseSplit = splitRegionsBySparseLinesEncoder(
      image.pixels, image.width, backgroundColor, connected, maxRegions, 2,
    );
    if (sparseSplit.length) raw.push({ regions: sparseSplit, label: 'sparse-split' });
    for (const regions of greedyRectRegionVariantsEncoder(
      image.pixels, image.width, image.height, backgroundColor, maxRegions, !high,
    )) raw.push({ regions, label: 'greedy' });

    const variants = [], seen = new Set();
    for (const variant of raw) {
      const regions = sortRegionsEncoder(variant.regions);
      if (!regions.length || regions.length > maxRegions || !regionsDoNotOverlapEncoder(regions)) continue;
      const key = regionListKeyEncoder(regions);
      if (!seen.has(key)) { seen.add(key); variants.push({ regions, label: variant.label, planCache: null }); }
    }

    if (high && variants.length && (useBoundedExtremeSearch || image.pixels.length <= MAX_BEAM_REGION_PIXELS)) {
      const beamVariants = findPayloadOptimizedRegionVariantsEncoder(
        image, backgroundColor, variants.map((variant) => variant.regions),
        beamMaxRegions, true, useBoundedExtremeSearch,
      );
      for (const state of beamVariants) {
        const key = regionListKeyEncoder(state.regions);
        if (!seen.has(key)) {
          seen.add(key);
          variants.push({ regions: state.regions, label: 'beam', planCache: state.exactPlanCache });
        }
      }
    }

    if (!high && variants.length && image.pixels.length <= MAX_BEAM_REGION_PIXELS) {
      const beamVariants = findNormalSharedCompactRegionVariantsEncoder(
        image, backgroundColor, variants.map((variant) => variant.regions), beamMaxRegions,
      );
      for (const state of beamVariants) {
        const key = regionListKeyEncoder(state.regions);
        if (!seen.has(key)) {
          seen.add(key);
          variants.push({ regions: state.regions, label: 'beam', planCache: state.exactPlanCache });
        }
      }
    }
    return variants;
  }

  function extractRegionPixelsEncoder(image, bounds) {
    const pixels=[];
    for(let y=0;y<bounds.height;y++){
      const start=(bounds.y+y)*image.width+bounds.x;
      for(let x=0;x<bounds.width;x++)pixels.push(image.pixels[start+x]);
    }
    return pixels;
  }

  function regionHeaderBitCost(algorithm) { return 5 + (canUseCompactBlockHeader(algorithm) ? 0 : 2); }

  let activeRegionBodyCache = null;
  let activeV3EncodeProgressCallback = null;

  function emitV3EncodeProgress(detail) {
    if (typeof activeV3EncodeProgressCallback !== 'function') return;
    try { activeV3EncodeProgressCallback(Object.freeze({ ...detail })); } catch (_) { /* progress is advisory */ }
  }

  function tryRegionBodyEncoder(image, rowMajor, bounds, algorithm, scan, backgroundColor, high, sharedPalette, reduced = false) {
    if(algorithm===MCOImageV3BlockAlgorithm.quadtree&&scan!==ScanMode.h)return null;
    if(canUseCompactBlockHeader(algorithm)&&scan!==ScanMode.h)return null;
    const cacheKey = activeRegionBodyCache == null ? null : [
      image.paletteProfile, bounds.width, bounds.height, algorithm, scan, backgroundColor,
      high ? 1 : 0, reduced ? 1 : 0, sharedPalette ? sharedPalette.join('.') : '-', rowMajor.join('.'),
    ].join('|');
    if (cacheKey != null && activeRegionBodyCache.has(cacheKey)) return activeRegionBodyCache.get(cacheKey);
    const linear=toScanOrder(rowMajor,bounds.width,bounds.height,scan);
    const writer=new BitWriter();
    try {
      if(sharedPalette) writeBlockBodyWithSharedPaletteEncoder(writer,linear,algorithm,sharedPalette,{
        backgroundColor,rowLength:rowLengthForScan(scan,bounds.width,bounds.height),greedyLzOnly:reduced||!high,reducedCostEvaluator:reduced,
      });
      else writeBlockBodyEncoder(writer,linear,image.paletteProfile,algorithm,{
        backgroundColor,rowLength:rowLengthForScan(scan,bounds.width,bounds.height),backgroundInherited:true,
        greedyLzOnly:reduced||!high,useHighCompressionExtras:high,reducedCostEvaluator:reduced,
      });
    } catch(error){if(error instanceof MCOImageV3CodecError)return null;throw error;}
    const bodyBitLength = writer.bitLength;
    if(bodyBitLength===0){ if(cacheKey!=null)activeRegionBodyCache.set(cacheKey,null); return null; }
    const result = {algorithm,scan,bytes:writer.toBytes(),bitLength:bodyBitLength};
    if(cacheKey!=null)activeRegionBodyCache.set(cacheKey,result);
    return result;
  }

  function writeBlockBodyWithSharedPaletteEncoder(writer, linear, algorithm, palette, options) {
    if(!linear.length)throw new MCOImageV3InvalidInputError('Empty shared block');
    const map=localIndexMap(palette), bits=localBits(palette.length);
    const pixels=linear.map(c=>{const i=map.get(c);if(i==null)throw new MCOImageV3InvalidInputError('Shared palette missing color');return i;});
    const rowLength=options.rowLength,bg=options.backgroundColor;
    switch(algorithm){
      case MCOImageV3BlockAlgorithm.rawLocal: for(const p of pixels)writer.writeBits(p,bits);return;
      case MCOImageV3BlockAlgorithm.compactRle:{let consumed=0;for(const run of buildRuns(pixels)){writer.writeBits(run.color,bits);writer.writeBoundedCompactUint(run.length-1,pixels.length-consumed-1);consumed+=run.length;}return;}
      case MCOImageV3BlockAlgorithm.varUintRle:for(const run of buildRuns(pixels)){writer.writeBits(run.color,bits);writer.writeBitVarUint(run.length);}return;
      case MCOImageV3BlockAlgorithm.lzPixels:{const greedy=buildGreedyLzTokens(pixels,bits);let tokens=greedy;if(!options.reducedCostEvaluator&&!options.greedyLzOnly&&pixels.length<=1024){const optimal=buildOptimalLzTokens(pixels,bits);if(optimal&&lzTokensBitCost(optimal,bits,pixels.length)<lzTokensBitCost(greedy,bits,pixels.length))tokens=optimal;}writeLzTokens(writer,tokens,bits,pixels.length);return;}
      case MCOImageV3BlockAlgorithm.quadtree:if(rowLength<=0||linear.length%rowLength!==0)throw new MCOImageV3InvalidInputError('Invalid quadtree');writeQuadtreeNodeEncoder(writer,pixels,rowLength,0,0,rowLength,linear.length/rowLength,bits);return;
      case MCOImageV3BlockAlgorithm.bitplanes:writeLegacyBitplanesBody(writer,pixels,bits);return;
      case MCOImageV3BlockAlgorithm.adaptiveBitplanes:writeAdaptiveBitplanesBody(writer,pixels,bits);return;
      case MCOImageV3BlockAlgorithm.rowDelta:writeRowDeltaBodyEncoder(writer,pixels,rowLength,bits);return;
      case MCOImageV3BlockAlgorithm.compactRowDelta:writeCompactRowDeltaBodyEncoder(writer,pixels,rowLength,bits,false);return;
      case MCOImageV3BlockAlgorithm.rowRepeat:writeRowRepeatEncoder(writer,pixels,rowLength,bits);return;
      case MCOImageV3BlockAlgorithm.biColorMask:{const fg=biColorForeground(linear,bg);if(fg==null)throw new MCOImageV3InvalidInputError('Not bi-color');writer.writeBits(map.get(fg),bits);for(const c of linear)writer.writeBits(c===fg?1:0,1);return;}
      case MCOImageV3BlockAlgorithm.compactSparse:
      case MCOImageV3BlockAlgorithm.varUintSparse:{const analysis=sparseAnalysis(linear,bg);if(!analysis.segments.length)throw new MCOImageV3InvalidInputError('Empty sparse');if(algorithm===MCOImageV3BlockAlgorithm.varUintSparse)writer.writeBitVarUint(analysis.segments.length);else writer.writeBoundedCompactUint(analysis.segments.length-1,linear.length-1);let pos=0;for(const segment of analysis.segments){const index=map.get(segment.color);if(index==null)throw new MCOImageV3InvalidInputError('Shared palette missing sparse color');if(algorithm===MCOImageV3BlockAlgorithm.varUintSparse){writer.writeBitVarUint(segment.start-pos);writer.writeBits(index,bits);writer.writeBitVarUint(segment.length);}else{writer.writeBoundedCompactUint(segment.start-pos,linear.length-pos-1);writer.writeBits(index,bits);writer.writeBoundedCompactUint(segment.length-1,linear.length-segment.start-1);}pos=segment.start+segment.length;}return;}
      default:throw new MCOImageV3InvalidInputError('Unsupported shared algorithm');
    }
  }

  function regionScansEncoder(high, reduced = false) {
    return high || reduced ? [ScanMode.h, ScanMode.v, ScanMode.s, ScanMode.sv] : [ScanMode.h, ScanMode.v, ScanMode.s];
  }

  function regionAlgorithmsEncoder(high, sharedPalette, reduced = false) {
    if (reduced) return REGION_COST_BLOCK_ALGORITHMS;
    if (sharedPalette) return high ? FULL_SHARED_REGION_ALGORITHMS : NORMAL_SHARED_REGION_ALGORITHMS;
    return high ? FULL_REGION_BLOCK_ALGORITHMS : NORMAL_REGION_BLOCK_ALGORITHMS;
  }

  function localPaletteOrderAffectsBodyEncoder(algorithm) {
    return algorithm === MCOImageV3BlockAlgorithm.bitplanes ||
      algorithm === MCOImageV3BlockAlgorithm.adaptiveBitplanes ||
      algorithm === MCOImageV3BlockAlgorithm.compactRowDelta ||
      algorithm === MCOImageV3BlockAlgorithm.rowDelta;
  }

  function regionBlockTieRankEncoder(block) {
    return modeTieRank(imageModeForAlgorithm(block.algorithm));
  }

  function isBetterRegionBlockEncoder(candidate, best) {
    if (!best) return true;
    if (candidate.cost !== best.cost) return candidate.cost < best.cost;
    return regionBlockTieRankEncoder(candidate) < regionBlockTieRankEncoder(best);
  }

  function paletteBitLengthEncoder(profile, palette) {
    const writer = new BitWriter();
    writeLocalPalette(writer, profile, palette);
    return writer.bitLength;
  }

  function sharedPaletteVariantSetsEncoder(image, prepared, backgroundColor, high, reduced = false) {
    const allPixels = prepared.flatMap((region) => region.pixels);
    return {
      invariant: localPaletteVariants(allPixels, image.paletteProfile, {
        indexOrderSensitive: false,
        includeTransitionOrder: false,
      }),
      sensitive: localPaletteVariants(allPixels, image.paletteProfile, {
        indexOrderSensitive: true,
        includeTransitionOrder: high && !reduced,
        includeBitplaneOptimizedOrder: high && !reduced,
        includeRgbOrder: high && !reduced,
        preferredFirstColor: backgroundColor,
      }),
    };
  }

  function bestRegionBlockEncoder(image, region, backgroundColor, high, sharedPalette, reduced = false) {
    let best = null;
    for (const scan of regionScansEncoder(high, reduced)) {
      for (const algorithm of regionAlgorithmsEncoder(high, sharedPalette != null, reduced)) {
        const body = tryRegionBodyEncoder(
          image, region.pixels, region.bounds, algorithm, scan, backgroundColor, high, sharedPalette, reduced,
        );
        if (!body) continue;
        const candidate = { ...body, cost: regionHeaderBitCost(algorithm) + body.bitLength };
        if (isBetterRegionBlockEncoder(candidate, best)) best = candidate;
      }
    }
    return best;
  }

  function bestIndividualRegionBlocksEncoder(image, prepared, backgroundColor, high, sharedPalette, reduced = false) {
    const blocks = [];
    for (const region of prepared) {
      const block = bestRegionBlockEncoder(image, region, backgroundColor, high, sharedPalette, reduced);
      if (!block) return null;
      blocks.push(block);
    }
    return blocks;
  }

  function bestCommonRegionPlanEncoder(image, prepared, backgroundColor, high, sharedPalette, reduced = false) {
    if (sharedPalette && prepared.length < 3) return null;
    let best = null;
    for (const scan of regionScansEncoder(high, reduced)) {
      for (const algorithm of regionAlgorithmsEncoder(high, sharedPalette != null, reduced)) {
        const bodies = [];
        let cost = regionHeaderBitCost(algorithm), failed = false;
        for (const region of prepared) {
          const body = tryRegionBodyEncoder(
            image, region.pixels, region.bounds, algorithm, scan, backgroundColor, high, sharedPalette, reduced,
          );
          if (!body) { failed = true; break; }
          bodies.push(body); cost += body.bitLength;
        }
        if (failed) continue;
        const candidate = { algorithm, scan, blocks: bodies, cost, sharedPalette };
        if (!best || cost < best.cost ||
            (cost === best.cost && modeTieRank(imageModeForAlgorithm(algorithm)) <
              modeTieRank(imageModeForAlgorithm(best.algorithm)))) best = candidate;
      }
    }
    return best;
  }

  function bestHybridRegionPlanEncoder(
    image, prepared, backgroundColor, high, sharedPalette, individualBlocks, reduced = false,
  ) {
    if (!sharedPalette && prepared.length < 3) return null;
    if (!individualBlocks) return null;
    let best = null;
    for (const scan of regionScansEncoder(high, reduced)) {
      for (const algorithm of regionAlgorithmsEncoder(high, sharedPalette != null, reduced)) {
        const blocks = [], usesCommon = [];
        let cost = 5 + regionHeaderBitCost(algorithm), commonCount = 0, exceptionCount = 0;
        for (let index = 0; index < prepared.length; index++) {
          const commonBlock = tryRegionBodyEncoder(
            image, prepared[index].pixels, prepared[index].bounds,
            algorithm, scan, backgroundColor, high, sharedPalette, reduced,
          );
          const individual = individualBlocks[index];
          const commonBits = commonBlock == null ? Infinity : 1 + commonBlock.bitLength;
          const exceptionBits = 1 + individual.cost;
          if (commonBlock && commonBits <= exceptionBits) {
            blocks.push(commonBlock); usesCommon.push(true); cost += commonBits; commonCount++;
          } else {
            blocks.push(individual); usesCommon.push(false); cost += exceptionBits; exceptionCount++;
          }
        }
        if (commonCount === 0 || exceptionCount === 0) continue;
        const candidate = { algorithm, scan, blocks, usesCommon, cost, sharedPalette };
        if (!best || cost < best.cost ||
            (cost === best.cost && modeTieRank(imageModeForAlgorithm(algorithm)) <
              modeTieRank(imageModeForAlgorithm(best.algorithm)))) best = candidate;
      }
    }
    return best;
  }

  function bestSharedIndividualPlanEncoder(image, prepared, backgroundColor, high, variants, reduced = false) {
    let best = null;
    for (const palette of variants.sensitive) {
      const blocks = bestIndividualRegionBlocksEncoder(image, prepared, backgroundColor, high, palette, reduced);
      if (!blocks) continue;
      const cost = paletteBitLengthEncoder(image.paletteProfile, palette) +
        blocks.reduce((sum, block) => sum + block.cost, 0);
      if (!best || cost < best.cost) best = { blocks, cost, sharedPalette: palette };
    }
    return best;
  }

  function bestSharedCommonPlanEncoder(image, prepared, backgroundColor, high, variants, reduced = false) {
    if (prepared.length < 3) return null;
    let best = null;
    for (const scan of regionScansEncoder(high, reduced)) {
      for (const algorithm of regionAlgorithmsEncoder(high, true, reduced)) {
        const palettes = localPaletteOrderAffectsBodyEncoder(algorithm)
          ? variants.sensitive : variants.invariant;
        for (const palette of palettes) {
          const bodies = [];
          let cost = paletteBitLengthEncoder(image.paletteProfile, palette) + regionHeaderBitCost(algorithm);
          let failed = false;
          for (const region of prepared) {
            const body = tryRegionBodyEncoder(
              image, region.pixels, region.bounds, algorithm, scan, backgroundColor, high, palette, reduced,
            );
            if (!body) { failed = true; break; }
            bodies.push(body); cost += body.bitLength;
          }
          if (failed) continue;
          const candidate = {
            algorithm, scan, blocks: bodies, cost, sharedPalette: palette,
          };
          if (!best || cost < best.cost ||
              (cost === best.cost && modeTieRank(imageModeForAlgorithm(algorithm)) <
                modeTieRank(imageModeForAlgorithm(best.algorithm)))) best = candidate;
        }
      }
    }
    return best;
  }

  function bestSharedHybridPlanEncoder(image, prepared, backgroundColor, high, variants, reduced = false) {
    let best = null;
    for (const palette of variants.sensitive) {
      const individualBlocks = bestIndividualRegionBlocksEncoder(
        image, prepared, backgroundColor, high, palette, reduced,
      );
      if (!individualBlocks) continue;
      const paletteBits = paletteBitLengthEncoder(image.paletteProfile, palette);
      for (const scan of regionScansEncoder(high, reduced)) {
        for (const algorithm of regionAlgorithmsEncoder(high, true, reduced)) {
          const blocks = [], usesCommon = [];
          let cost = paletteBits + 5 + regionHeaderBitCost(algorithm);
          let commonCount = 0, exceptionCount = 0;
          for (let index = 0; index < prepared.length; index++) {
            const commonBlock = tryRegionBodyEncoder(
              image, prepared[index].pixels, prepared[index].bounds,
              algorithm, scan, backgroundColor, high, palette, reduced,
            );
            const individual = individualBlocks[index];
            const commonBits = commonBlock == null ? Infinity : 1 + commonBlock.bitLength;
            const exceptionBits = 1 + individual.cost;
            if (commonBlock && commonBits <= exceptionBits) {
              blocks.push(commonBlock); usesCommon.push(true); cost += commonBits; commonCount++;
            } else {
              blocks.push(individual); usesCommon.push(false); cost += exceptionBits; exceptionCount++;
            }
          }
          if (commonCount === 0 || exceptionCount === 0) continue;
          const candidate = {
            algorithm, scan, blocks, usesCommon, cost, sharedPalette: palette,
          };
          if (!best || cost < best.cost ||
              (cost === best.cost && modeTieRank(imageModeForAlgorithm(algorithm)) <
                modeTieRank(imageModeForAlgorithm(best.algorithm)))) best = candidate;
        }
      }
    }
    return best;
  }

  let activeRegionPlanCacheEncoder = null;

  function regionPlanCacheKeyEncoder(backgroundColor, high, reduced, regions) {
    return `${backgroundColor}|${high ? 1 : 0}|${reduced ? 1 : 0}|${regionListKeyEncoder(regions)}`;
  }

  function regionPlanCacheEncoder(image, backgroundColor, regions, high, reduced = false) {
    const key = regionPlanCacheKeyEncoder(backgroundColor, high, reduced, regions);
    if (activeRegionPlanCacheEncoder != null && activeRegionPlanCacheEncoder.has(key)) {
      return activeRegionPlanCacheEncoder.get(key);
    }
    const cache = {
      prepared: regions.map((bounds) => ({ bounds, pixels: extractRegionPixelsEncoder(image, bounds) })),
      sharedVariants: null,
      individual: undefined,
      common: undefined,
      hybrid: undefined,
      sharedIndividual: undefined,
      sharedCommon: undefined,
      sharedHybrid: undefined,
      reduced,
    };
    if (activeRegionPlanCacheEncoder != null) activeRegionPlanCacheEncoder.set(key, cache);
    return cache;
  }

  function regionPlanForOptionsEncoder(image, backgroundColor, high, cache, options) {
    if (options.sharedLocalPalette) {
      cache.sharedVariants ??= sharedPaletteVariantSetsEncoder(
        image, cache.prepared, backgroundColor, high, cache.reduced,
      );
      if (options.hybridCommonHeader) {
        if (cache.sharedHybrid === undefined) {
          cache.sharedHybrid = bestSharedHybridPlanEncoder(
            image, cache.prepared, backgroundColor, high, cache.sharedVariants, cache.reduced,
          );
        }
        return cache.sharedHybrid;
      }
      if (options.commonBlockHeader) {
        if (cache.sharedCommon === undefined) {
          cache.sharedCommon = bestSharedCommonPlanEncoder(
            image, cache.prepared, backgroundColor, high, cache.sharedVariants, cache.reduced,
          );
        }
        return cache.sharedCommon;
      }
      if (cache.sharedIndividual === undefined) {
        cache.sharedIndividual = bestSharedIndividualPlanEncoder(
          image, cache.prepared, backgroundColor, high, cache.sharedVariants, cache.reduced,
        );
      }
      return cache.sharedIndividual;
    }

    if (cache.individual === undefined) {
      const blocks = bestIndividualRegionBlocksEncoder(
        image, cache.prepared, backgroundColor, high, null, cache.reduced,
      );
      cache.individual = blocks == null ? null : {
        blocks,
        cost: blocks.reduce((sum, block) => sum + block.cost, 0),
        sharedPalette: null,
      };
    }
    if (options.hybridCommonHeader) {
      if (cache.hybrid === undefined) {
        cache.hybrid = cache.individual == null ? null : bestHybridRegionPlanEncoder(
          image, cache.prepared, backgroundColor, high, null, cache.individual.blocks, cache.reduced,
        );
      }
      return cache.hybrid;
    }
    if (options.commonBlockHeader) {
      if (cache.common === undefined) {
        cache.common = bestCommonRegionPlanEncoder(
          image, cache.prepared, backgroundColor, high, null, cache.reduced,
        );
      }
      return cache.common;
    }
    return cache.individual;
  }

  function writeRegionHeaderEncoder(writer, algorithm, scan) {
    writer.writeBits(algorithm,5);
    if(!canUseCompactBlockHeader(algorithm))writer.writeBits(scan,2);
  }

  function tryBuildRegionsCandidateEncoder(image, backgroundColor, backgroundRank, regions, options, high, reduced = false, planCacheOverride = null) {
    const maxRegions = high ? MAX_REGIONS : NORMAL_MAX_REGIONS;
    if(regions.length < 2 || regions.length > maxRegions || !regionsDoNotOverlapEncoder(regions)) return null;
    if (options.commonBlockHeader && !options.compactGeometry) return null;
    if (options.hybridCommonHeader && !options.commonBlockHeader) return null;
    if (options.deltaGeometry && !options.compactGeometry) return null;
    if (options.sharedLocalPalette && !options.compactGeometry) return null;

    const planCache = planCacheOverride || regionPlanCacheEncoder(image, backgroundColor, regions, high, reduced);
    const prepared = planCache.prepared;
    const plan = regionPlanForOptionsEncoder(
      image, backgroundColor, high, planCache, options,
    );
    if (!plan || !plan.blocks) return null;

    const sharedPalette = plan.sharedPalette || null;
    const implicit=isImplicitWhiteBackground(image.paletteProfile,backgroundColor);
    const container=options.compactGeometry?MCOImageV3Container.compactRegionsStream:MCOImageV3Container.regions;
    const writer=new BitWriter();
    writeImagePreamble(writer,image,ScanMode.h,implicit,container,regions.length-1);
    if(image.transparentColor!=null)writeColorRef(writer,image.paletteProfile,image.transparentColor);
    writeBackgroundRef(writer,image.paletteProfile,backgroundColor,implicit);
    if(options.compactGeometry){
      writer.writeBits(options.commonBlockHeader?1:0,1);
      writer.writeBits(options.deltaGeometry?1:0,1);
      writer.writeBits(sharedPalette?1:0,1);
      if(options.commonBlockHeader){
        if(options.hybridCommonHeader){
          writer.writeBits(HYBRID_COMMON_REGION_ALGORITHM_MARKER,5);
          writer.writeBits(plan.algorithm,5);
        } else writer.writeBits(plan.algorithm,5);
        if(!canUseCompactBlockHeader(plan.algorithm))writer.writeBits(plan.scan,2);
      }
      if(sharedPalette)writeLocalPalette(writer,image.paletteProfile,sharedPalette);
    }
    let previous=null;
    for(let index=0;index<prepared.length;index++){
      const region=prepared[index];
      if(options.deltaGeometry&&index>0)writeDeltaRegionGeometry(writer,region.bounds,previous);
      else writeRegionGeometry(writer,region.bounds,image.width,image.height,options.compactGeometry);
      previous=region.bounds;
      const block=plan.blocks[index];
      if(options.hybridCommonHeader){
        const usesCommon=plan.usesCommon[index];
        writer.writeBits(usesCommon?0:1,1);
        if(!usesCommon)writeRegionHeaderEncoder(writer,block.algorithm,block.scan);
      } else if(!options.commonBlockHeader) writeRegionHeaderEncoder(writer,block.algorithm,block.scan);
      writer.writeBitStream(block.bytes,block.bitLength);
    }
    return makeCandidate(writer.toBytes(),{
      mode:ImageMode.regionsBg,scan:ScanMode.h,backgroundColor,backgroundRank,
      transparentColor:image.transparentColor,regionCount:regions.length,
      localPaletteSize:sharedPalette?sharedPalette.length:null,
      bitsPerLocalPixel:sharedPalette?localBits(sharedPalette.length):null,
      paletteKind:isDynamicProfile(image.paletteProfile)?'dynamic':'fixed',
      container:MCOImageV3ContainerName[container],
    });
  }

  let activeRegionLayoutCostCache = null;

  function regionLayoutByteCostEncoder(image, backgroundColor, regions, high, sharedOnly) {
    const key = activeRegionLayoutCostCache == null ? null : [
      backgroundColor, high ? 1 : 0, sharedOnly ? 1 : 0, regionListKeyEncoder(regions),
    ].join('|');
    if (key != null && activeRegionLayoutCostCache.has(key)) return activeRegionLayoutCostCache.get(key);
    let best = null;
    if (!sharedOnly) {
      const nonCompact = tryBuildRegionsCandidateEncoder(image, backgroundColor, 0, regions, {
        compactGeometry:false, commonBlockHeader:false, hybridCommonHeader:false,
        deltaGeometry:false, sharedLocalPalette:false,
      }, high);
      if (nonCompact) best = nonCompact.byteLength;
    }
    const optionsList = high ? FULL_REGION_OPTIONS : NORMAL_REGION_OPTIONS;
    for (const options of optionsList) {
      if (sharedOnly && !options.sharedLocalPalette) continue;
      const candidate = tryBuildRegionsCandidateEncoder(image, backgroundColor, 0, regions, {
        compactGeometry:true, ...options,
      }, high);
      if (candidate && (best == null || candidate.byteLength < best)) best = candidate.byteLength;
    }
    if (key != null) activeRegionLayoutCostCache.set(key, best);
    return best;
  }

  function compareEncoderCandidates(a,b){const byBytes=a.byteLength-b.byteLength;if(byBytes)return byBytes;return modeTieRank(a.mode)-modeTieRank(b.mode);}

  function finalizeEncodedCandidate(candidate, nonce) {
    const packet=withPacketNonce(candidate,nonce);
    const appPayload=new Uint8Array(packet.payload.length+1);appPayload[0]=MCOImageV3Codec.subtypeVersion;appPayload.set(packet.payload,1);
    const text=MCOImageV3Codec.textFromAppPayloadWithoutSender(appPayload);
    return Object.freeze({...packet,body:packet.payload,payload:packet.payload,appPayloadWithoutSender:appPayload,text,charLength:text.length});
  }

  function normalizedBackgroundsForEncode(image, options, high, preferred) {
    const source = Array.isArray(options.backgroundCandidates)
      ? options.backgroundCandidates.map((item, index) => typeof item === 'number'
        ? { color: item, rank: index }
        : { color: Number(item.color), rank: Number(item.rank ?? index) })
      : (high
        ? fullBackgroundCandidates(image, preferred, true)
        : normalBackgroundCandidates(image, preferred));
    const result = [];
    for (const item of source) {
      if (!Number.isInteger(item.color) || !isColorValid(image.paletteProfile, item.color)) continue;
      const rank = Number.isFinite(item.rank) ? Math.trunc(item.rank) : result.length;
      result.push(Object.freeze({ color: item.color, rank }));
    }
    return result;
  }

  function normalizedScansForEncode(options, high) {
    const source = Array.isArray(options.scanModes) && options.scanModes.length
      ? options.scanModes.map(Number)
      : (high ? [ScanMode.h, ScanMode.v, ScanMode.s, ScanMode.sv] : [ScanMode.h, ScanMode.v, ScanMode.s]);
    const result = [];
    for (const scan of source) {
      if (!Number.isInteger(scan) || scan < ScanMode.h || scan > ScanMode.sv) {
        throw new MCOImageV3InvalidInputError('Invalid scan mode');
      }
      if (!result.includes(scan)) result.push(scan);
    }
    return result;
  }

  function resetV3EncoderCaches() {
    activeRegionBodyCache = new Map();
    activeRegionLayoutCostCache = new Map();
    activeRegionPlanCacheEncoder = new Map();
    activeLocalIndexMapCache = new Map();
    activeLocalPixelsCache = new Map();
    activeRunCache = new Map();
    activeSparseAnalysisCache = new Map();
    activeLocalPaletteVariantCache = new Map();
    activeLzTokenCache = new Map();
  }

  function clearV3EncoderCaches() {
    activeRegionBodyCache?.clear();
    activeRegionLayoutCostCache?.clear();
    activeRegionPlanCacheEncoder?.clear();
    activeLocalIndexMapCache?.clear();
    activeLocalPixelsCache?.clear();
    activeRunCache?.clear();
    activeSparseAnalysisCache?.clear();
    activeLocalPaletteVariantCache?.clear();
    activeLzTokenCache?.clear();
    activeRegionBodyCache = null;
    activeRegionLayoutCostCache = null;
    activeRegionPlanCacheEncoder = null;
    activeLocalIndexMapCache = null;
    activeLocalPixelsCache = null;
    activeRunCache = null;
    activeSparseAnalysisCache = null;
    activeLocalPaletteVariantCache = null;
    activeLzTokenCache = null;
  }

  function runV3Encode(imageLike, options = {}, collectDiagnostics = false) {
    const image = imageLike instanceof MCOImageV3 ? imageLike : new MCOImageV3(imageLike);
    validateImageForEncode(image);
    const level = normalizeCompressionLevel(options.compressionLevel);
    const high = level !== MCOImageV3CompressionLevel.normal;
    const extreme = level === MCOImageV3CompressionLevel.extreme;
    const preferred = options.backgroundColor ?? image.transparentColor ?? whiteIndexFor(image.paletteProfile);
    const backgrounds = normalizedBackgroundsForEncode(image, options, high, preferred);
    const scans = normalizedScansForEncode(options, high);
    const includeNonScan = options.includeNonScanCandidates !== false;
    const nonce = Object.prototype.hasOwnProperty.call(options, 'packetNonce')
      ? Number(options.packetNonce)
      : MCOImageV3Codec.nextPacketNonce();
    if (!Number.isInteger(nonce) || nonce < 0 || nonce > 255) {
      throw new MCOImageV3InvalidInputError('packetNonce must be 0..255');
    }
    const partition = options._partition || null;
    const allowEmpty = options._allowEmptyResult === true;
    const previousProgress = activeV3EncodeProgressCallback;
    activeV3EncodeProgressCallback = typeof options._progressCallback === 'function'
      ? options._progressCallback
      : (typeof options.onProgress === 'function' ? options.onProgress : null);
    resetV3EncoderCaches();
    try {
      let best = null;
      const seen = new Map();
      const add = (candidate) => {
        if (!candidate) return;
        const key = Array.from(candidate.payload).join(',');
        const existing = seen.get(key);
        if (!existing || compareEncoderCandidates(candidate, existing) < 0) seen.set(key, candidate);
        if (!best || compareEncoderCandidates(candidate, best) < 0) best = candidate;
      };

      const processSolid = () => {
        if (includeNonScan) add(tryBuildSolidBackgroundCandidate(image));
      };

      const processBackground = (background) => {
        const bg = background.color;
        if (includeNonScan) {
          add(tryBuildSolidRectsCandidate(image, bg, background.rank));
          const maxRegions = high ? MAX_REGIONS : NORMAL_MAX_REGIONS;
          const useExtremeForBackground = extreme && background.rank <= MAX_EXTREME_REGION_BACKGROUND_RANK;
          const variants = regionVariantsEncoder(image, bg, maxRegions, high, useExtremeForBackground);
          for (const variant of variants) {
            add(tryBuildRegionsCandidateEncoder(image, bg, background.rank, variant.regions, {
              compactGeometry: false,
              commonBlockHeader: false,
              hybridCommonHeader: false,
              deltaGeometry: false,
              sharedLocalPalette: false,
            }, high, false, variant.planCache));
            const regionOptions = high ? FULL_REGION_OPTIONS : NORMAL_REGION_OPTIONS;
            for (const regionOption of regionOptions) {
              add(tryBuildRegionsCandidateEncoder(image, bg, background.rank, variant.regions, {
                compactGeometry: true,
                ...regionOption,
              }, high, false, variant.planCache));
            }
          }
        }
        const bounds = boundsForBackground(image, bg);
        if (bounds && !(bounds.width === image.width && bounds.height === image.height)) {
          const cropped = extractBoundsPixels(image, bounds);
          for (const scan of scans) {
            const linear = toScanOrder(cropped, bounds.width, bounds.height, scan);
            for (const algorithm of (high ? FULL_BLOCK_ALGORITHMS : NORMAL_BLOCK_ALGORITHMS)) {
              if (algorithm === MCOImageV3BlockAlgorithm.quadtree && scan !== ScanMode.h) continue;
              const body = tryBuildBlockBodyEncoding(image, linear, algorithm, {
                backgroundColor: bg,
                rowLength: rowLengthForScan(scan, bounds.width, bounds.height),
                backgroundInherited: true,
                greedyLzOnly: !high,
                useHighCompressionExtras: high,
              });
              if (!body) continue;
              add(tryWrapBoundsCandidate(image, bounds, linear, body, algorithm, scan, {
                backgroundColor: bg,
                compactGeometry: false,
                backgroundRank: background.rank,
              }));
              add(tryWrapBoundsCandidate(image, bounds, linear, body, algorithm, scan, {
                backgroundColor: bg,
                compactGeometry: true,
                backgroundRank: background.rank,
              }));
            }
          }
        }
        emitV3EncodeProgress({ phase: 'background', backgroundColor: bg, backgroundRank: background.rank });
      };

      const independent = high
        ? FULL_TOP_LEVEL_BACKGROUND_INDEPENDENT
        : NORMAL_TOP_LEVEL_BACKGROUND_INDEPENDENT;
      const processScanIndependent = (scan) => {
        const linear = toScanOrder(image.pixels, image.width, image.height, scan);
        for (const algorithm of independent) {
          if (canUseCompactBlockHeader(algorithm)) {
            if (scan === ScanMode.h) add(tryBuildTopLevelCandidate(image, linear, algorithm, scan, {
              backgroundColor: preferred,
              compactHeader: true,
              greedyLzOnly: !high,
              useHighCompressionExtras: high,
            }));
          } else {
            add(tryBuildTopLevelCandidate(image, linear, algorithm, scan, {
              backgroundColor: preferred,
              compactHeader: false,
              greedyLzOnly: !high,
              useHighCompressionExtras: high,
            }));
          }
        }
      };

      const processScanBackgroundSensitive = (scan, background) => {
        const linear = toScanOrder(image.pixels, image.width, image.height, scan);
        for (const algorithm of TOP_LEVEL_BACKGROUND_SENSITIVE) {
          if (canUseCompactBlockHeader(algorithm)) {
            if (scan === ScanMode.h) add(tryBuildTopLevelCandidate(image, linear, algorithm, scan, {
              backgroundColor: background.color,
              compactHeader: true,
              greedyLzOnly: !high,
              useHighCompressionExtras: high,
            }));
          } else {
            add(tryBuildTopLevelCandidate(image, linear, algorithm, scan, {
              backgroundColor: background.color,
              compactHeader: false,
              greedyLzOnly: !high,
              useHighCompressionExtras: high,
            }));
          }
        }
      };

      if (partition == null) {
        processSolid();
        for (const background of backgrounds) processBackground(background);
        for (const scan of scans) {
          processScanIndependent(scan);
          for (const background of backgrounds) processScanBackgroundSensitive(scan, background);
        }
      } else {
        switch (partition.type) {
          case 'solid': processSolid(); break;
          case 'background': processBackground(partition.background); break;
          case 'scan-independent': processScanIndependent(partition.scan); break;
          case 'scan-background': processScanBackgroundSensitive(partition.scan, partition.background); break;
          default: throw new MCOImageV3InvalidInputError(`Unknown v3 worker partition: ${partition.type}`);
        }
      }

      if (!best) {
        if (allowEmpty) {
          return Object.freeze({
            result: null,
            candidates: Object.freeze([]),
            compressionLevel: level,
            partitionOrder: partition?.order ?? null,
          });
        }
        throw new MCOImageV3InvalidInputError('No MCOimg v3 candidate');
      }
      const sorted = Array.from(seen.values()).sort(compareEncoderCandidates);
      const finalizedResult = finalizeEncodedCandidate(sorted[0], nonce);
      const finalizedCandidates = collectDiagnostics
        ? sorted.map((candidate) => finalizeEncodedCandidate(candidate, nonce))
        : [finalizedResult];
      return Object.freeze({
        result: finalizedResult,
        candidates: Object.freeze(finalizedCandidates),
        compressionLevel: level,
        partitionOrder: partition?.order ?? null,
      });
    } finally {
      clearV3EncoderCaches();
      activeV3EncodeProgressCallback = previousProgress;
    }
  }

  function createV3WorkerPlan(imageLike, options = {}) {
    const image = imageLike instanceof MCOImageV3 ? imageLike : new MCOImageV3(imageLike);
    validateImageForEncode(image);
    const level = normalizeCompressionLevel(options.compressionLevel);
    const high = level !== MCOImageV3CompressionLevel.normal;
    const preferred = options.backgroundColor ?? image.transparentColor ?? whiteIndexFor(image.paletteProfile);
    const backgrounds = normalizedBackgroundsForEncode(image, options, high, preferred);
    const scans = normalizedScansForEncode(options, high);
    const includeNonScan = options.includeNonScanCandidates !== false;
    const nonce = Object.prototype.hasOwnProperty.call(options, 'packetNonce')
      ? Number(options.packetNonce)
      : MCOImageV3Codec.nextPacketNonce();
    if (!Number.isInteger(nonce) || nonce < 0 || nonce > 255) {
      throw new MCOImageV3InvalidInputError('packetNonce must be 0..255');
    }
    const partitions = [];
    let order = 0;
    if (includeNonScan) partitions.push(Object.freeze({ type: 'solid', order: order++ }));
    for (const background of backgrounds) {
      partitions.push(Object.freeze({ type: 'background', order: order++, background }));
    }
    for (const scan of scans) {
      partitions.push(Object.freeze({ type: 'scan-independent', order: order++, scan }));
      for (const background of backgrounds) {
        partitions.push(Object.freeze({ type: 'scan-background', order: order++, scan, background }));
      }
    }
    const workerOptions = Object.freeze({
      compressionLevel: level,
      backgroundColor: preferred,
      backgroundCandidates: backgrounds.map((item) => ({ ...item })),
      scanModes: scans.slice(),
      includeNonScanCandidates: includeNonScan,
      packetNonce: nonce,
    });
    return Object.freeze({
      schema: 1,
      compressionLevel: level,
      packetNonce: nonce,
      totalPartitions: partitions.length,
      options: workerOptions,
      partitions: Object.freeze(partitions),
    });
  }

  function encodeV3Partition(imageLike, options, partition, progressCallback = null) {
    if (!partition || !Number.isInteger(partition.order)) {
      throw new MCOImageV3InvalidInputError('Invalid v3 worker partition');
    }
    const diagnostics = runV3Encode(imageLike, {
      ...(options || {}),
      _partition: partition,
      _allowEmptyResult: true,
      _progressCallback: progressCallback,
    }, false);
    return Object.freeze({
      order: partition.order,
      type: partition.type,
      result: diagnostics.result,
    });
  }

  function mergeV3PartitionResults(results) {
    let best = null;
    let bestOrder = Infinity;
    for (const item of results || []) {
      if (!item || !item.result) continue;
      const order = Number.isInteger(item.order) ? item.order : Infinity;
      if (!best) {
        best = item.result;
        bestOrder = order;
        continue;
      }
      const comparison = compareEncoderCandidates(item.result, best);
      if (comparison < 0 || (comparison === 0 && order < bestOrder)) {
        best = item.result;
        bestOrder = order;
      }
    }
    if (!best) throw new MCOImageV3InvalidInputError('No MCOimg v3 worker candidate');
    return best;
  }

  function parseBodyPreamble(bodyLike) {
    const body = asBytes(bodyLike, 'MCOimg v3 body');
    if (body.length < 4) throw new MCOImageV3InvalidPayloadError('MCOimg v3 payload too short');
    const packetNonce = body[0];
    const header = body[1];
    const scan = scanFromHeader(header);
    const hasTransparentColor = (header & TRANSPARENT_FLAG) !== 0;
    const implicitWhiteBackground = (header & IMPLICIT_WHITE_BACKGROUND_FLAG) !== 0;
    const profile = profileFromId(header & PROFILE_MASK);
    const reader = new BitReader(body, 2);
    const dimensions = readDimensions(reader);
    const containerByte = reader.readBits(8);
    const container = containerFromId(containerByte >> CONTAINER_CONTEXT_CONTAINER_SHIFT);
    const containerContext = containerByte & CONTAINER_CONTEXT_MASK;
    const algorithm = topLevelAlgorithm(container, containerContext);
    if (container === MCOImageV3Container.block && canUseCompactBlockHeader(algorithm)) {
      throw new MCOImageV3InvalidPayloadError('Scan-independent v3 block must use compactBlock');
    }
    if (container === MCOImageV3Container.compactBlock && !canUseCompactBlockHeader(algorithm)) {
      throw new MCOImageV3InvalidPayloadError('compactBlock cannot be used with scan-dependent algorithms');
    }
    validateTopLevelScan(container, algorithm, scan);
    validateImplicitWhiteBackground(container, algorithm, implicitWhiteBackground);
    return {
      body, packetNonce, header, scan, hasTransparentColor,
      implicitWhiteBackground, profile, reader,
      width: dimensions.width, height: dimensions.height,
      container, containerContext, algorithm,
    };
  }

  let packetNonceCounter = (Date.now() ^ Math.floor(Math.random() * 256)) & 0xff;
  let lastPacketNonce = null;

  class MCOImageV3Codec {
    encode(image, options = {}) {
      return runV3Encode(image, options, false).result;
    }

    encodeBytes(image, options = {}) {
      return this.encode(image, options).appPayloadWithoutSender;
    }

    debugEncode(image, options = {}) {
      return runV3Encode(image, options, true);
    }

    decodeText(text) {
      return this.decodeAppPayloadWithoutSender(MCOImageV3Codec.appPayloadWithoutSenderFromText(text));
    }

    decodeBytes(bytesLike) {
      const bytes = asBytes(bytesLike, 'MCOimg v3 bytes');
      if (bytes.length > 0 && bytes[0] === MCOImageV3Codec.subtypeVersion) {
        return this.decodeAppPayloadWithoutSender(bytes);
      }
      return this.decodeBody(bytes);
    }

    decodeBody(bodyLike) {
      const preamble = parseBodyPreamble(bodyLike);
      const {
        reader, width, height, profile, scan, container, containerContext,
        algorithm, hasTransparentColor, implicitWhiteBackground,
      } = preamble;
      const transparentColor = hasTransparentColor ? readColorRef(reader, profile) : null;
      let pixels;
      switch (container) {
        case MCOImageV3Container.block:
          pixels = fromScanOrder(
            decodeBlockBody(reader, width, height, profile, algorithm, scan, implicitWhiteBackground),
            width, height, scan,
          );
          break;
        case MCOImageV3Container.compactBlock:
          pixels = fromScanOrder(
            decodeBlockBody(reader, width, height, profile, algorithm, ScanMode.h, implicitWhiteBackground),
            width, height, ScanMode.h,
          );
          break;
        case MCOImageV3Container.boundsBlock:
          pixels = decodeBoundsBlockBody(
            reader, width, height, profile, algorithm, scan, false, implicitWhiteBackground,
          );
          break;
        case MCOImageV3Container.compactBoundsBlock:
          pixels = decodeBoundsBlockBody(
            reader, width, height, profile, algorithm, scan, true, implicitWhiteBackground,
          );
          break;
        case MCOImageV3Container.regions:
          pixels = decodeRegionsBody(
            reader, width, height, profile, containerContext, false, implicitWhiteBackground,
          );
          break;
        case MCOImageV3Container.compactRegionsStream:
          pixels = decodeRegionsBody(
            reader, width, height, profile, containerContext, true, implicitWhiteBackground,
          );
          break;
        case MCOImageV3Container.solidBackground:
          pixels = Array(width * height).fill(
            readSolidBackgroundColor(reader, profile, containerContext, implicitWhiteBackground),
          );
          break;
        case MCOImageV3Container.solidRects:
          pixels = decodeSolidRectsBody(
            reader, width, height, profile, containerContext, implicitWhiteBackground,
          );
          break;
        default:
          throw new MCOImageV3InvalidPayloadError('Unknown MCOimg v3 container');
      }
      reader.finish();
      return new MCOImageV3({
        width, height, paletteProfile: profile, pixels, transparentColor,
      });
    }

    decodeAppPayloadWithoutSender(payloadLike) {
      const payload = asBytes(payloadLike, 'MCOimg v3 app payload');
      if (payload.length < 2 || payload[0] !== MCOImageV3Codec.subtypeVersion) {
        const actual = payload.length === 0 ? 'empty' : `0x${payload[0].toString(16).padStart(2, '0')}`;
        throw new MCOImageV3InvalidPayloadError(
          `Unsupported MCOimg app subtype/version ${actual}`,
        );
      }
      return this.decodeBody(payload.subarray(1));
    }

    static createWorkerPlan(imageLike, options = {}) {
      return createV3WorkerPlan(imageLike, options);
    }

    static encodePartition(imageLike, options, partition, progressCallback = null) {
      return encodeV3Partition(imageLike, options, partition, progressCallback);
    }

    static mergePartitionResults(results) {
      return mergeV3PartitionResults(results);
    }

    static backgroundCandidatesFor(imageLike, options = {}) {
      const image = validateImageForEncode(imageLike);
      const level = normalizeCompressionLevel(options.compressionLevel);
      const preferred = options.backgroundColor ?? image.transparentColor ?? whiteIndexFor(image.paletteProfile);
      const candidates = level === MCOImageV3CompressionLevel.normal
        ? normalBackgroundCandidates(image, preferred)
        : fullBackgroundCandidates(image, preferred, true);
      return Object.freeze(candidates.map((candidate) => Object.freeze({ ...candidate })));
    }

    static nextPacketNonce() {
      packetNonceCounter = (packetNonceCounter + 1) & 0xff;
      let mixed = Date.now() ^ (packetNonceCounter * 0x9d);
      mixed ^= mixed >>> 8;
      mixed ^= mixed >>> 16;
      let nonce = mixed & 0xff;
      if (nonce === lastPacketNonce) nonce = (nonce + 1) & 0xff;
      lastPacketNonce = nonce;
      return nonce;
    }

    static refreshPacketNonce(bodyLike, options = {}) {
      const body = asBytes(bodyLike, 'MCOimg v3 body');
      if (body.length < 4) throw new MCOImageV3InvalidPayloadError('MCOimg v3 payload too short');
      const refreshed = body.slice();
      const nonce = options && Object.prototype.hasOwnProperty.call(options, 'nonce')
        ? Number(options.nonce)
        : MCOImageV3Codec.nextPacketNonce();
      if (!Number.isInteger(nonce) || nonce < 0 || nonce > 0xff) {
        throw new MCOImageV3InvalidInputError('nonce must be an integer from 0 to 255');
      }
      refreshed[0] = nonce;
      return refreshed;
    }

    static isTextPayload(text) {
      return typeof text === 'string' && text.startsWith(MCOImageV3Codec.textPrefix);
    }

    static textFromBody(bodyLike) {
      const body = asBytes(bodyLike, 'MCOimg v3 body');
      const payload = new Uint8Array(body.length + 1);
      payload[0] = MCOImageV3Codec.subtypeVersion;
      payload.set(body, 1);
      return MCOImageV3Codec.textFromAppPayloadWithoutSender(payload);
    }

    static textFromAppPayloadWithoutSender(payloadLike) {
      return `${MCOImageV3Codec.textPrefix}${base91Encode(asBytes(payloadLike))}`;
    }

    static appPayloadWithoutSenderFromText(text) {
      if (!MCOImageV3Codec.isTextPayload(text)) {
        throw new MCOImageV3InvalidPayloadError('Missing im3: prefix');
      }
      return base91Decode(text.slice(MCOImageV3Codec.textPrefix.length));
    }

    static bodyFromText(text) {
      const payload = MCOImageV3Codec.appPayloadWithoutSenderFromText(text);
      if (payload.length < 2 || payload[0] !== MCOImageV3Codec.subtypeVersion) {
        throw new MCOImageV3InvalidPayloadError('Invalid MCOimg v3 app payload');
      }
      return payload.slice(1);
    }

    static inspectText(text) {
      if (!MCOImageV3Codec.isTextPayload(text)) return null;
      try {
        return MCOImageV3Codec.inspectAppPayloadWithoutSender(
          MCOImageV3Codec.appPayloadWithoutSenderFromText(text),
        );
      } catch (error) {
        if (error instanceof MCOImageV3CodecError) return null;
        throw error;
      }
    }

    static inspectBody(bodyLike) {
      const preamble = parseBodyPreamble(bodyLike);
      return Object.freeze({
        version: MCOImageV3Codec.version,
        algorithm: payloadAlgorithmLabel(preamble.container, preamble.algorithm),
        binaryLength: preamble.body.length,
        width: preamble.width,
        height: preamble.height,
        paletteProfile: preamble.profile,
        paletteProfileName: PaletteProfileName[preamble.profile],
        scan: preamble.scan,
        scanName: ScanModeName[preamble.scan],
        container: preamble.container,
        containerName: MCOImageV3ContainerName[preamble.container],
        containerContext: preamble.containerContext,
        blockAlgorithm: preamble.algorithm,
        blockAlgorithmName: MCOImageV3BlockAlgorithmName[preamble.algorithm],
        packetNonce: preamble.packetNonce,
        hasTransparentColor: preamble.hasTransparentColor,
        implicitWhiteBackground: preamble.implicitWhiteBackground,
      });
    }

    static inspectAppPayloadWithoutSender(payloadLike) {
      const payload = asBytes(payloadLike, 'MCOimg v3 app payload');
      if (payload.length < 2 || payload[0] !== MCOImageV3Codec.subtypeVersion) {
        throw new MCOImageV3InvalidPayloadError('Invalid MCOimg v3 app payload');
      }
      const info = MCOImageV3Codec.inspectBody(payload.subarray(1));
      return Object.freeze({ ...info, appPayloadLength: payload.length, subtypeVersion: payload[0] });
    }
  }

  MCOImageV3Codec.textPrefix = 'im3:';
  MCOImageV3Codec.version = 3;
  MCOImageV3Codec.subtypeId = 0x01;
  MCOImageV3Codec.subtypeVersion = 0x13;
  MCOImageV3Codec.appDataType = 0x0120;
  MCOImageV3Codec.packetNonceLength = 1;
  MCOImageV3Codec.minSize = MIN_SIZE;
  MCOImageV3Codec.maxSize = MAX_SIZE;

  const capabilities = Object.freeze({
    encode: true,
    decode: true,
    inspect: true,
    extremeEncode: true,
    parallelEncode: true,
    workerPartitions: true,
  });

  global.MCOImgV3 = Object.freeze({
    PaletteProfile,
    PaletteProfileName,
    ScanMode,
    ScanModeName,
    MCOImageV3Container,
    MCOImageV3ContainerName,
    MCOImageV3BlockAlgorithm,
    MCOImageV3BlockAlgorithmName,
    MCOImageV3CompressionLevel,
    MCOImageV3CompressionLevelName,
    MCOImageV3OutputFormat,
    MCOImageV3CodecError,
    MCOImageV3InvalidInputError,
    MCOImageV3InvalidPayloadError,
    MCOImageV3NotImplementedError,
    MCOImageV3,
    MCOImageV3Codec,
    capabilities,
    base91Encode,
    base91Decode,
  });
})(typeof window !== 'undefined' ? window : globalThis);
