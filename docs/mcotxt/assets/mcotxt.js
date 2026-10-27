/*
 * MCOtxt v1 / generation 0. Классический ES6-скрипт, без modules и зависимостей.
 * Источники: lib/MCOtxt/, lib/helpers/mcotxt_app_codec.dart.
 * Формат: docs/MCOTXT_V1_PROTOCOL_RU.md. Лицензия MIT, как у публичного проекта.
 * encode/decode возвращают {ok, ...}; преобразования и упаковка бросают MCOtxtError.
 */
(function (root) {
  'use strict';

  const LANGUAGE_CODES = ['en', 'ru', 'fr', 'de', 'it', 'uk', 'be'];
  const LANGUAGE_NAMES = ['English', 'Русский', 'Français', 'Deutsch', 'Italiano', 'Українська', 'Беларуская'];
  // Общая таблица пунктуации: порядок — wire format.
  const PUNCT = [32, 46, 44, 33, 63, 58, 59, 45, 8212, 95, 39, 34, 171, 187,
    8220, 8221, 8222, 8216, 8217, 40, 41, 91, 93, 47, 92, 64, 35, 37, 38, 43, 61, 10];
  const PUNCT_IDS = new Map(PUNCT.map((rune, index) => [rune, index]));
  const BASE91 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!#$%&()*+,./:;<=>?@[]^_`{|}~"';
  const BASE91_IDS = new Map(Array.from(BASE91, (symbol, index) => [symbol, index]));
  // Ограничения этой браузерной реализации, не лимиты радиопакета или формата.
  const MAX_CODEPOINTS = 4096;
  const MAX_DECODE_BYTES = 1024 * 1024;
  const HAS = (object, key) => Object.prototype.hasOwnProperty.call(object, key);

  class MCOtxtError extends Error {
    constructor(code, message) {
      super(message);
      this.name = 'MCOtxtError';
      this.code = code;
    }
  }

  function fail(code, message) { throw new MCOtxtError(code, message); }
  function requireString(value, name) {
    if (typeof value !== 'string') { fail('invalidInput', name + ' must be a string'); }
    return value;
  }
  function uint32(value, name) {
    if (!Number.isInteger(value) || value < 0 || value > 0xffffffff) {
      fail('invalidInput', name + ' must be an unsigned 32-bit integer (Unix seconds)');
    }
    return value;
  }
  function optionsObject(value) {
    if (value === undefined) { return {}; }
    if (!value || typeof value !== 'object' || Array.isArray(value)) {
      fail('invalidInput', 'Options must be an object');
    }
    return value;
  }
  function optionalBoolean(options, key, fallback) {
    if (options[key] === undefined) { return fallback; }
    if (typeof options[key] !== 'boolean') { fail('invalidInput', key + ' must be boolean'); }
    return options[key];
  }
  function safely(action) {
    try { return action(); }
    catch (error) {
      // Не выдаём частично разобранный пакет или placeholder за успешное сообщение.
      if (!(error instanceof MCOtxtError)) { throw error; }
      return {ok: false, error: {code: error.code, message: error.message}};
    }
  }
  function asBytes(value) {
    if (value instanceof ArrayBuffer) { return new Uint8Array(value.slice(0)); }
    if (ArrayBuffer.isView(value)) {
      return new Uint8Array(new Uint8Array(value.buffer, value.byteOffset, value.byteLength));
    }
    if (Array.isArray(value) && value.every(byte => Number.isInteger(byte) && byte >= 0 && byte <= 255)) {
      return new Uint8Array(value);
    }
    fail('invalidInput', 'Expected Uint8Array, ArrayBuffer, binary view or byte array');
  }
  function fromRunes(runes) { return runes.map(rune => String.fromCodePoint(rune)).join(''); }

  // UTF-8 реализован здесь: работа через file:// и в ES6 без TextEncoder/TextDecoder.
  // Непарные UTF-16 surrogate при кодировании заменяются U+FFFD, как utf8.encode.
  function utf8Encode(text) {
    const bytes = [];
    for (const symbol of text) {
      let rune = symbol.codePointAt(0);
      if (rune >= 0xd800 && rune <= 0xdfff) { rune = 0xfffd; }
      if (rune < 0x80) { bytes.push(rune); }
      else if (rune < 0x800) { bytes.push(0xc0 | (rune >> 6), 0x80 | (rune & 63)); }
      else if (rune < 0x10000) { bytes.push(0xe0 | (rune >> 12), 0x80 | ((rune >> 6) & 63), 0x80 | (rune & 63)); }
      else { bytes.push(0xf0 | (rune >> 18), 0x80 | ((rune >> 12) & 63), 0x80 | ((rune >> 6) & 63), 0x80 | (rune & 63)); }
    }
    return bytes;
  }
  function utf8Decode(bytes) {
    const runes = [];
    // Dart Utf8Decoder пропускает BOM только в начале конкретной UTF-8 строки.
    const start = bytes.length >= 3 && bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf ? 3 : 0;
    for (let i = start; i < bytes.length;) {
      const first = bytes[i++];
      if (first < 128) { runes.push(first); continue; }
      let count, rune, minimum;
      if (first >= 0xc2 && first <= 0xdf) { count = 1; rune = first & 31; minimum = 0x80; }
      else if (first >= 0xe0 && first <= 0xef) { count = 2; rune = first & 15; minimum = 0x800; }
      else if (first >= 0xf0 && first <= 0xf4) { count = 3; rune = first & 7; minimum = 0x10000; }
      else { fail('invalidUtf8', 'Invalid UTF-8 leading byte'); }
      if (i + count > bytes.length) { fail('invalidUtf8', 'Truncated UTF-8 code point'); }
      for (let n = 0; n < count; n++) {
        const next = bytes[i++];
        if ((next & 0xc0) !== 0x80) { fail('invalidUtf8', 'Invalid UTF-8 continuation'); }
        rune = rune * 64 + (next & 63);
      }
      if (rune < minimum || rune > 0x10ffff || (rune >= 0xd800 && rune <= 0xdfff)) {
        fail('invalidUtf8', 'Non-scalar or overlong UTF-8 code point');
      }
      runes.push(rune);
    }
    return fromRunes(runes);
  }

  // Только пары, которые составляет Dart registry. Полный String.normalize('NFC')
  // здесь был бы несовместим: например, a + diaeresis Dart оставляет раздельно.
  const COMPOSITIONS = [
    [0x61,0x300,0xe0], [0x61,0x302,0xe2], [0x41,0x300,0xc0], [0x41,0x302,0xc2],
    [0x63,0x327,0xe7], [0x43,0x327,0xc7], [0x65,0x300,0xe8], [0x65,0x301,0xe9],
    [0x65,0x302,0xea], [0x65,0x308,0xeb], [0x45,0x300,0xc8], [0x45,0x301,0xc9],
    [0x45,0x302,0xca], [0x45,0x308,0xcb], [0x69,0x300,0xec], [0x69,0x302,0xee],
    [0x69,0x308,0xef], [0x49,0x300,0xcc], [0x49,0x302,0xce], [0x49,0x308,0xcf],
    [0x6f,0x302,0xf4], [0x4f,0x302,0xd4], [0x75,0x300,0xf9], [0x75,0x302,0xfb],
    [0x75,0x308,0xfc], [0x55,0x300,0xd9], [0x55,0x302,0xdb], [0x55,0x308,0xdc],
    [0x435,0x308,0x451], [0x415,0x308,0x401], [0x438,0x306,0x439], [0x418,0x306,0x419],
    [0x456,0x308,0x457], [0x406,0x308,0x407], [0x443,0x306,0x45e], [0x423,0x306,0x40e]
  ];
  const COMPOSITION_MAP = new Map(COMPOSITIONS.map(pair => [pair[0] * 0x200000 + pair[1], pair[2]]));
  function normalizeText(text) {
    requireString(text, 'text');
    const runes = Array.from(text.replace(/\r\n?/g, '\n'), symbol => symbol.codePointAt(0));
    const out = [];
    for (let i = 0; i < runes.length; i++) {
      const composed = COMPOSITION_MAP.get(runes[i] * 0x200000 + runes[i + 1]);
      if (composed !== undefined) { out.push(composed); i++; }
      else { out.push(runes[i] >= 0xd800 && runes[i] <= 0xdfff ? 0xfffd : runes[i]); }
    }
    return fromRunes(out);
  }

  // Замороженные таблицы generation 0, перенесённые из model_<lang>.dart.
  // Индексы TOP4 относятся к primary + extension; порядок менять нельзя.
  // Не используются locale-dependent toUpperCase/toLowerCase: карты явные.
  function makeModel(id, hash, primary, extension, upper, lower, start, afterPunct, rows) {
    const symbols = Array.from(primary + extension, symbol => symbol.codePointAt(0));
    const upperRunes = Array.from(upper, symbol => symbol.codePointAt(0));
    const lowerRunes = Array.from(lower, symbol => symbol.codePointAt(0));
    if (rows.length !== symbols.length * 4 || upperRunes.length !== lowerRunes.length) {
      fail('invalidModel', 'Invalid embedded model ' + LANGUAGE_CODES[id]);
    }
    const model = {
      id: id, hash: hash, symbols: symbols,
      primary: Array.from(primary, symbol => symbol.codePointAt(0)),
      extension: Array.from(extension, symbol => symbol.codePointAt(0)),
      indexes: new Map(symbols.map((rune, index) => [rune, index])),
      upperToLower: new Map(upperRunes.map((rune, index) => [rune, lowerRunes[index]])),
      lowerToUpper: new Map(lowerRunes.map((rune, index) => [rune, upperRunes[index]])),
      start: start.map(index => symbols[index]),
      afterPunct: afterPunct.map(index => symbols[index]),
      rows: []
    };
    for (let i = 0; i < rows.length; i += 4) {
      const row = rows.slice(i, i + 4).map(index => symbols[index]);
      if (row.some(rune => rune === undefined) || new Set(row).size !== 4) {
        fail('invalidModel', 'Invalid TOP4 row');
      }
      model.rows.push(row);
    }
    return model;
  }
  const MODELS = [
    makeModel(0, '55988b3bb2a000adf6e768a8541df5a25fec1628b4ec661a10b577e3af8b3770',
      ' odailrmytcpwsfghbnekuvx1j3284z5', 'q6790',
      'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz', [16,7,9,4], [0,13,9,7], [
        9,3,4,13,18,6,0,21,0,1,19,3,18,9,5,0,18,9,13,0,5,1,0,19,19,0,18,1,19,
        1,0,3,0,1,19,13,0,16,1,19,1,16,3,19,19,13,0,1,19,4,3,0,0,9,19,16,0,1,
        6,4,0,1,16,19,19,3,1,4,19,21,1,3,15,0,4,19,0,6,13,18,19,0,13,4,9,13,
        0,6,19,4,29,3,0,9,11,4,36,0,31,27,21,1,3,19,0,36,33,2,0,27,31,36,0,7,
        33,36,0,36,29,33,19,30,8,4,0,36,33,27,21,0,7,9,0,36,35,28,0,5,10,6,0,
        33,2,35,0,36,7,35
      ]),
    makeModel(1, 'd123c4978a635bf1b26fe37261b7e96a0206b3ba15b2a80542e560f00d1eb193',
      ' смуркелниятбдвгчазоыпйхжшюьэщцф', '123ё4587690ъ',
      'ЁАБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ', 'ёабвгдежзийклмнопрстуфхцчшщъыьэюя', [21,8,0,13], [0,11,32,5], [
        8,21,1,14,11,6,0,19,0,6,19,17,0,11,13,24,19,17,6,9,19,17,0,9,0,11,8,4,
        9,27,19,6,17,19,6,9,0,11,8,7,0,11,18,7,19,17,0,27,19,4,20,6,17,19,6,9,
        0,6,17,19,19,13,17,9,6,11,17,9,0,7,5,11,17,0,8,9,0,11,13,14,0,22,25,7,
        19,4,9,17,0,11,16,5,19,0,17,3,6,8,13,9,6,9,17,5,0,11,16,1,0,8,5,1,11,
        5,8,7,6,17,35,9,9,6,17,0,9,19,7,6,0,42,32,36,0,42,37,33,0,42,34,33,0,
        11,2,7,0,42,34,37,0,42,37,40,0,40,42,33,0,39,42,37,0,37,38,42,0,41,42,
        37,0,42,2,5,6,10,35,9
      ]),
    makeModel(2, '910c5821a202a9b35313a9b939355f09d1c4293fe2ed246fed0123639d379ccb',
      ' utcmrloieasnvpéjbdghfqyçàk2x15z', '4w376è08ê9ôîùûüëœâæïÿ',
      'ABCDEFGHIJKLMNOPQRSTUVWXYZÀÂÆÇÈÉÊËÎÏÔÙÛÜŒŸ', 'abcdefghijklmnopqrstuvwxyzàâæçèéêëîïôùûüœÿ', [17,11,2,3], [0,10,9,12], [
        18,14,6,11,5,0,2,8,0,9,8,7,7,20,9,10,9,10,7,8,0,9,10,7,9,10,6,0,12,
        1,8,5,0,11,12,5,0,11,12,5,8,0,12,11,0,2,9,10,0,2,9,11,9,7,8,10,10,7,
        9,5,2,0,9,14,9,7,1,10,7,8,6,9,9,8,0,1,9,5,10,12,9,7,10,0,10,5,8,7,
        1,0,22,5,0,9,7,2,10,1,7,0,0,9,11,10,0,9,10,8,0,38,29,41,0,9,2,7,0,
        34,29,35,0,38,41,27,0,10,9,8,0,41,32,34,8,9,10,7,0,34,32,39,34,29,38,0,
        0,39,27,32,11,5,2,4,0,38,36,35,0,36,4,21,2,4,13,0,0,10,21,9,2,6,14,0,
        12,2,6,3,0,9,11,10,5,0,9,11,5,0,9,11,6,0,9,11,8,0,9,11,0,9,11,10,0,
        9,11,10,0,9,11,10,0,9,11,10
      ]),
    makeModel(3, '00b971288fee56f37535ce03b4ac0d8ebddfc12ecbd5ef282ab4b0f4a659f451',
      ' stbhoglimnruwkfecadzpüvjöä132y5', '94678ßx0q',
      'ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÜẞ', 'abcdefghijklmnopqrstuvwxyzäöüß', [6,9,4,19], [0,3,19,18], [
        18,19,9,8,0,2,16,17,0,16,18,2,16,8,18,0,0,18,16,2,11,8,10,21,16,12,11,
        0,7,16,8,0,10,17,16,2,5,16,8,18,0,19,16,18,0,16,6,18,1,2,10,11,16,8,
        18,5,16,5,18,0,16,18,0,11,10,11,0,8,4,14,5,0,12,10,7,17,16,18,0,8,12,
        16,2,0,1,16,21,15,37,11,3,17,5,16,8,12,16,18,5,12,10,11,7,6,2,26,12,10,
        0,39,27,29,0,27,39,36,0,39,35,28,2,0,16,5,0,39,4,35,0,4,39,36,0,35,39,
        34,0,27,28,34,0,28,27,33,0,27,28,34,16,0,2,8,0,8,2,16,0,39,34,35,12,0,
        2,1
      ]),
    makeModel(4, 'f6d073a1d6ae6344eaac445b86fb8a454b276a740fd40651956b1ff28f5af270',
      ' tlmpuircsgveoandbhzfqè1324wk768', '5yàì9ò0ùjéxíóú',
      'ABCDEFGHIJKLMNOPQRSTUVWXYZÀÈÉÌÍÒÓÙÚ', 'abcdefghijklmnopqrstuvwxyzàèéìíòóùú', [17,8,9,6], [0,6,14,7], [
        14,9,16,8,12,6,13,1,14,0,12,6,12,6,14,13,12,13,9,7,13,15,1,14,0,13,14,
        15,12,14,6,13,13,6,18,12,12,14,1,6,6,10,7,14,12,14,13,6,0,7,15,9,0,15,
        7,4,0,15,2,7,13,0,14,1,14,6,13,12,5,12,6,14,13,12,6,14,6,14,19,13,14,
        6,12,13,5,1,0,7,0,13,14,6,0,38,25,14,0,17,24,18,0,38,31,36,0,36,32,18,
        6,14,0,12,0,6,7,5,24,0,20,32,0,23,31,32,0,30,17,20,0,38,23,30,1,0,10,
        9,0,13,14,6,0,14,15,13,0,13,23,25,0,12,13,14,0,38,25,30,0,13,14,6,15,
        13,0,14,0,13,14,6,0,8,5,16,0,13,14,6,0,13,14,6,0,13,14,6
      ]),
    makeModel(5, '949992c57156526843cdb9634c5c14bee23218878f116ef90be2a8497274c131',
      ' ксрімунзблдоияаетвшчйгпжюцхєщфї', '23ь14586709ґ',
      'ЄІЇАБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЬЮЯҐ', 'єіїабвгдежзийклмнопрстуфхцчшщьюяґ', [0,17,7,11], [0,37,41,35], [
        23,18,7,17,12,15,13,6,17,34,14,23,12,15,16,13,0,11,7,10,12,15,0,16,0,18,
        17,10,15,12,16,4,15,0,7,4,6,15,12,4,16,34,13,14,12,15,16,6,0,5,18,11,0,
        18,17,2,0,1,17,18,0,7,17,10,0,7,3,5,15,13,12,34,0,15,13,4,13,12,16,6,
        13,15,16,12,0,7,17,12,12,15,4,3,3,12,4,16,16,7,0,13,0,28,17,18,16,4,25,
        14,0,12,13,17,0,17,5,11,12,16,15,6,4,12,15,17,0,27,31,7,0,32,39,41,0,
        32,33,41,0,7,1,2,32,41,0,37,0,33,40,41,0,18,41,32,41,0,39,32,38,0,32,
        33,0,41,1,5,0,41,1,5,39,0,42,22,0,12,15,7
      ]),
    makeModel(6, 'dd23c2b82288e0a4452f237ccd905055974779e3cc5cc6f3d03be1b24e5bb1fd',
      ' клмсервнядутчопзыйгбжашюхьэ2фц1', '4ё3685709іў',
      'ЁІЎАБВГДЕЖЗЙКЛМНОПРСТУФХЦЧШЫЬЭЮЯ', 'ёіўабвгдежзйклмнопрстуфхцчшыьэюя', [0,12,8,5], [0,12,28,38], [
        8,15,7,4,22,14,0,2,14,26,0,22,14,0,5,22,12,0,5,14,0,12,8,6,14,22,5,11,
        0,22,5,14,22,14,5,11,0,12,16,8,5,14,22,11,0,12,21,4,14,22,0,26,5,22,12,
        8,0,10,20,12,14,6,22,5,22,0,8,14,0,18,2,12,0,12,1,4,14,6,10,22,14,17,
        11,6,5,8,11,22,0,2,4,12,5,26,22,12,13,0,12,10,14,0,22,16,0,8,23,12,12,
        1,29,7,0,28,39,32,14,22,29,11,5,22,7,17,39,37,0,31,0,37,36,39,0,12,3,
        14,0,39,28,32,0,36,38,40,35,0,37,14,0,39,35,4,0,35,28,37,39,0,28,37,39,
        0,3,34,0,14,5,22,0,14,5,22
      ])
  ];

  class BitWriter {
    constructor() { this.bytes = []; this.length = 0; }
    write(value, count) {
      for (let shift = count - 1; shift >= 0; shift--) {
        const offset = this.length % 8;
        if (offset === 0) { this.bytes.push(0); }
        this.bytes[this.bytes.length - 1] |= ((value >>> shift) & 1) << (7 - offset);
        this.length++;
      }
    }
  }
  class BitReader {
    constructor(data, length) {
      if (!Number.isInteger(length) || length < 0 || length > data.length * 8) { fail('invalidInput', 'Invalid bitLength'); }
      this.data = data; this.length = length; this.position = 0;
    }
    read(count) {
      if (this.position + count > this.length) { fail('unexpectedEnd', 'Truncated MCOtxt bitstream'); }
      let value = 0;
      for (let i = 0; i < count; i++) {
        value = value * 2 + ((this.data[this.position >> 3] >> (7 - (this.position & 7))) & 1);
        this.position++;
      }
      return value;
    }
    get remaining() { return this.length - this.position; }
    field() { const value = this.read(3); return value === 7 ? 7 + this.read(8) : value; }
  }
  function varUint(value) {
    const out = [];
    do {
      const byte = value % 128;
      value = Math.floor(value / 128);
      out.push(byte + (value ? 128 : 0));
    } while (value);
    return out;
  }
  class ByteReader {
    constructor(data) { this.data = data; this.position = 0; }
    take(count) {
      if (count < 0 || this.position + count > this.data.length) { fail('unexpectedEnd', 'Truncated MCOtxt container'); }
      const out = this.data.slice(this.position, this.position + count);
      this.position += count;
      return out;
    }
    byte() { return this.take(1)[0]; }
    varUint() {
      let value = 0, factor = 1;
      for (let i = 0; i < 5; i++) {
        const byte = this.byte();
        value += (byte & 127) * factor;
        if (!(byte & 128)) { return value; }
        factor *= 128;
      }
      fail('invalidLength', 'Varuint is too long');
    }
    uint32() { const b = this.take(4); return b[0] + b[1] * 256 + b[2] * 65536 + b[3] * 16777216; }
    done() {
      if (this.position !== this.data.length) { fail('trailingBytes', 'Trailing MCOtxt bytes'); }
    }
  }
  function uint32Bytes(value) { return [value & 255, (value >>> 8) & 255, (value >>> 16) & 255, value >>> 24]; }
  function normalizedRune(model, rune) { return model.indexes.has(rune) ? rune : model.upperToLower.get(rune); }
  // context: 0=START, 1=AFTER_PUNCT, 2=SYMBOL(previousRune).
  function predictions(model, kind, previous) {
    return kind === 0 ? model.start : kind === 1 ? model.afterPunct : (model.rows[model.indexes.get(previous)] || []);
  }
  function punctuationContext(rune, kind, previous) {
    if (rune === 32) { return kind === 2 ? [2, previous] : [0, -1]; }
    return rune === 10 ? [0, -1] : [1, -1];
  }

  function decodeStream(data, bitLength) {
    const reader = new BitReader(data, bitLength);
    if (reader.field() !== 1) { fail('unknownVersion', 'Unsupported MCOtxt codec version'); }
    const generation = reader.field();
    let a = reader.read(3), b = reader.read(3);
    let raw = false;
    if (a === 7) {
      if (b === 1) { raw = true; }
      else if (b === 0) { a = reader.read(8); b = reader.read(8); }
      else { fail('unsupportedExtendedHeader', 'Unknown extended language header'); }
    } else if (b === 7) { b = 255; }
    if (raw) {
      if (reader.read(4) !== 0 || reader.remaining % 8) { fail('invalidRawUtf8', 'Invalid RAW_UTF8 alignment or padding'); }
      const bytes = [];
      while (reader.remaining) { bytes.push(reader.read(8)); }
      return {text: utf8Decode(bytes), encodingMode: 'rawUtf8', modelGeneration: generation,
        languageA: null, languageB: null, usedTables: [], languages: []};
    }
    if (!MODELS[a] || (b !== 255 && !MODELS[b])) { fail('unknownLanguage', 'Unknown language ID'); }
    if (generation !== 0) { fail('unsupportedModelGeneration', 'Model generation is not available: ' + generation); }
    let language = a, kind = 0, previous = -1, shift = false, caps = false;
    const out = [], used = [];
    function table(name) { if (used.indexOf(name) < 0) { used.push(name); } }
    function noShift() { if (shift) { fail('invalidShift', 'SHIFT must precede a language symbol'); } }
    function emit(rune) {
      if (rune === undefined) { fail('invalidSymbol', 'Invalid symbol or TOP4 index'); }
      const model = MODELS[language], upper = model.lowerToUpper.get(rune);
      if (shift && upper === undefined) { fail('invalidShift', 'SHIFT on a non-caseable symbol'); }
      out.push(upper !== undefined && caps !== shift ? upper : rune);
      kind = 2; previous = rune; shift = false;
      table(LANGUAGE_CODES[language]);
    }
    while (reader.remaining) {
      const model = MODELS[language];
      if (reader.read(1) === 0) {
        const rank = reader.read(1) === 0 ? 0 : reader.read(1) === 0 ? 1 : reader.read(1) === 0 ? 2 : 3;
        emit(predictions(model, kind, previous)[rank]); continue;
      }
      if (reader.read(1) === 0) { emit(model.primary[reader.read(5)]); continue; }
      if (reader.read(1) === 0) {
        noShift();
        const rune = PUNCT[reader.read(5)];
        out.push(rune);
        const context = punctuationContext(rune, kind, previous);
        kind = context[0]; previous = context[1]; table('punctuation'); continue;
      }
      if (reader.read(1) === 0) { emit(model.extension[reader.read(5)]); continue; }
      if (reader.read(1) === 0) {
        if (shift) { fail('invalidShift', 'Duplicate SHIFT'); }
        shift = true; continue;
      }
      if (reader.read(1) === 0) {
        noShift();
        if (b === 255 || (language !== a && language !== b)) { fail('toggleWithoutLanguageB', 'TOGGLE_LANGUAGE outside A/B'); }
        language = language === a ? b : a; kind = 0; previous = -1; continue;
      }
      noShift();
      const control = reader.read(3);
      if (control === 0) {
        language = reader.read(8);
        if (!MODELS[language]) { fail('invalidOtherLanguage', 'Invalid SWITCH_OTHER_LANGUAGE'); }
        kind = 0; previous = -1;
      } else if (control === 1) { kind = 0; previous = -1; }
      else if (control === 2) {
        const size = reader.read(5) + 1, bytes = [];
        for (let i = 0; i < size; i++) { bytes.push(reader.read(8)); }
        for (const symbol of utf8Decode(bytes)) { out.push(symbol.codePointAt(0)); }
        kind = 0; previous = -1;
      } else if (control === 3) { caps = !caps; }
      else { fail('unknownExtendedControl', 'Unknown MCOtxt control'); }
    }
    noShift();
    return {text: fromRunes(out), encodingMode: 'mcotxt', modelGeneration: generation,
      languageA: LANGUAGE_CODES[a], languageB: b === 255 ? null : LANGUAGE_CODES[b],
      usedTables: used, languages: used.filter(name => name !== 'punctuation')};
  }

  // Отдельная двухсостоянийная DP регистра, с теми же tie-breaks, что у Dart.
  function casePlan(runes) {
    const positions = [], wantsUpper = [];
    runes.forEach((rune, position) => {
      for (const model of MODELS) {
        const normalized = normalizedRune(model, rune);
        if (normalized !== undefined && model.lowerToUpper.has(normalized)) {
          positions.push(position); wantsUpper.push(normalized !== rune); break;
        }
      }
    });
    function better(a, b) {
      return b === null || a.bits < b.bits || (a.bits === b.bits &&
        (a.toggles < b.toggles || (a.toggles === b.toggles && a.shifts < b.shifts)));
    }
    let previous = [{bits: 0, toggles: 0, shifts: 0}, null];
    const backtrack = [];
    for (let i = 0; i < positions.length; i++) {
      const next = [null, null], decisions = [null, null];
      for (let before = 0; before <= 1; before++) {
        if (previous[before] === null) { continue; }
        for (let after = 0; after <= 1; after++) {
          const toggled = before !== after, shifted = wantsUpper[i] !== (after === 1);
          const cost = {bits: previous[before].bits + (toggled ? 9 : 0) + (shifted ? 5 : 0),
            toggles: previous[before].toggles + (toggled ? 1 : 0), shifts: previous[before].shifts + (shifted ? 1 : 0)};
          if (better(cost, next[after])) {
            next[after] = cost; decisions[after] = {before: before, toggled: toggled, shifted: shifted};
          }
        }
      }
      previous = next; backtrack.push(decisions);
    }
    const toggles = new Set(), shifts = new Set();
    let state = better(previous[0], previous[1]) ? 0 : 1;
    for (let i = positions.length - 1; i >= 0; i--) {
      const decision = backtrack[i][state];
      if (decision.toggled) { toggles.add(positions[i]); }
      if (decision.shifted) { shifts.add(positions[i]); }
      state = decision.before;
    }
    return {toggles: toggles, shifts: shifts};
  }

  function comparePlans(a, b) {
    return b.characters - a.characters || a.bits - b.bits || a.tokens - b.tokens ||
      a.switches - b.switches || b.top4 - a.top4;
  }
  const EMPTY_PLAN = {bits: 0, tokens: 0, switches: 0, top4: 0, characters: 0, prefix: [], tail: null};
  function addPlan(edge, tail) {
    return {bits: edge.bits + tail.bits, tokens: edge.prefix.length + tail.tokens,
      switches: edge.switches + tail.switches, top4: edge.top4 + tail.top4,
      characters: edge.characters + tail.characters, prefix: edge.prefix, tail: tail};
  }

  // Та же DP по position/language/context. Явный стек вместо JS-рекурсии:
  // длинный текст не должен падать из-за ограничения call stack браузера.
  function planPair(runes, a, b, casing) {
    const memo = new Map();
    function key(position, language, kind, previous) { return [position, language, kind, previous].join('|'); }
    function state(position, language, kind, previous) {
      return {position: position, language: language, kind: kind, previous: previous,
        key: key(position, language, kind, previous), edges: null, index: 0, best: null};
    }
    function edgesFor(s) {
      const edges = [], rune = runes[s.position];
      function edge(prefix, bits, target, context, top4, switches, consumed) {
        edges.push({prefix: prefix, bits: bits, top4: top4, switches: switches, characters: consumed,
          next: state(s.position + consumed, target, context[0], context[1])});
      }
      if (PUNCT_IDS.has(rune)) {
        edge([['punct', PUNCT_IDS.get(rune)]], 8, s.language,
          punctuationContext(rune, s.kind, s.previous), 0, 0, 1);
      }
      const toggled = b === null ? null : s.language === a ? b : s.language === b ? a : null;
      function symbolCandidate(target, kind, previous, languagePrefix, prefixBits) {
        const model = MODELS[target], normalized = normalizedRune(model, rune);
        if (normalized === undefined) { return; }
        const shifted = casing.shifts.has(s.position);
        if (shifted && !model.lowerToUpper.has(normalized)) { return; }
        const rank = predictions(model, kind, previous).indexOf(normalized);
        const index = model.indexes.get(normalized);
        if (index === undefined) { return; }
        const prefix = languagePrefix ? [languagePrefix] : [];
        if (casing.toggles.has(s.position)) { prefix.push(['caps', 0]); }
        if (shifted) { prefix.push(['shift', 0]); }
        let bits;
        if (rank >= 0) { prefix.push(['top4', rank]); bits = [2,3,4,4][rank]; }
        else if (index < model.primary.length) { prefix.push(['primary', index]); bits = 7; }
        else { prefix.push(['extension', index - model.primary.length]); bits = 9; }
        bits += prefixBits + (casing.toggles.has(s.position) ? 9 : 0) + (shifted ? 5 : 0);
        edge(prefix, bits, target, [2, normalized], rank >= 0 ? 1 : 0, languagePrefix ? 1 : 0, 1);
      }
      symbolCandidate(s.language, s.kind, s.previous, null, 0);
      if (toggled !== null) { symbolCandidate(toggled, 0, -1, ['toggle', 0], 6); }
      for (const model of MODELS) {
        if (model.id !== s.language && model.id !== toggled) { symbolCandidate(model.id, 0, -1, ['other', model.id], 17); }
      }
      if (!edges.length) {
        const bytes = [];
        let consumed = 0;
        for (let p = s.position; p < runes.length; p++) {
          if (PUNCT_IDS.has(runes[p]) || MODELS.some(model => normalizedRune(model, runes[p]) !== undefined)) { break; }
          const next = utf8Encode(String.fromCodePoint(runes[p]));
          if (bytes.length + next.length > 32) { break; }
          bytes.push.apply(bytes, next); consumed++;
          if (bytes.length === 32) { break; }
        }
        if (!consumed) { fail('invalidInput', 'No legal symbol or UTF8_RUN'); }
        edge([['utf8', bytes]], 14 + bytes.length * 8, s.language, [0, -1], 0, 0, consumed);
      }
      return edges;
    }
    const initial = state(0, a, 0, -1), stack = [initial];
    while (stack.length) {
      const s = stack[stack.length - 1];
      if (s.position >= runes.length) { memo.set(s.key, EMPTY_PLAN); stack.pop(); continue; }
      if (s.edges === null) { s.edges = edgesFor(s); }
      if (s.index === s.edges.length) { memo.set(s.key, s.best); stack.pop(); continue; }
      const edge = s.edges[s.index];
      if (!memo.has(edge.next.key)) { stack.push(edge.next); continue; }
      const candidate = addPlan(edge, memo.get(edge.next.key));
      // При равенстве сохраняем первый вариант, порядок кандидатов как в Dart.
      if (s.best === null || comparePlans(candidate, s.best) < 0) { s.best = candidate; }
      s.index++;
    }
    return {a: a, b: b, plan: memo.get(initial.key)};
  }
  function comparePairs(a, b) {
    return b.plan.characters - a.plan.characters || a.plan.bits - b.plan.bits ||
      a.plan.switches - b.plan.switches || (a.b === null ? 1 : 2) - (b.b === null ? 1 : 2) ||
      a.a - b.a || (a.b === null ? 255 : a.b) - (b.b === null ? 255 : b.b);
  }
  function languageId(code) {
    const id = LANGUAGE_CODES.indexOf(code);
    if (id < 0) { fail('unknownLanguage', 'Unknown language: ' + String(code)); }
    return id;
  }
  function resolvePairs(options) {
    if (options.modelGeneration !== undefined && options.modelGeneration !== 0) {
      fail('unsupportedModelGeneration', 'Only generation 0 is available for encoding');
    }
    if (options.languagePair !== undefined) {
      const pair = options.languagePair;
      if (!Array.isArray(pair) || pair.length < 1 || pair.length > 2) { fail('invalidInput', 'languagePair needs A and optional B'); }
      const a = languageId(pair[0]), b = pair.length === 1 || pair[1] === null ? null : languageId(pair[1]);
      if (a === b) { fail('invalidInput', 'Language A and B must differ'); }
      return [[a, b]];
    }
    const requested = options.languages === undefined ? ['ru', 'en'] : options.languages;
    if (!Array.isArray(requested) || requested.length === 0) { fail('invalidInput', 'languages must be a non-empty array'); }
    const ids = Array.from(new Set(requested.map(languageId))).sort((a, b) => a - b);
    const pairs = [];
    for (const a of ids) { for (const b of ids.concat([null])) { if (a !== b) { pairs.push([a, b]); } } }
    return pairs;
  }
  function writeToken(writer, token) {
    const type = token[0], value = token[1];
    if (type === 'top4') { writer.write([0,2,6,7][value], [2,3,4,4][value]); }
    else if (type === 'primary') { writer.write(2, 2); writer.write(value, 5); }
    else if (type === 'punct') { writer.write(6, 3); writer.write(value, 5); }
    else if (type === 'extension') { writer.write(14, 4); writer.write(value, 5); }
    else if (type === 'shift') { writer.write(30, 5); }
    else if (type === 'toggle') { writer.write(62, 6); }
    else {
      writer.write(63, 6);
      writer.write(type === 'other' ? 0 : type === 'caps' ? 3 : 2, 3);
      if (type === 'other') { writer.write(value, 8); }
      else if (type === 'utf8') {
        writer.write(value.length - 1, 5);
        value.forEach(byte => writer.write(byte, 8));
      }
    }
  }
  function encodeStream(text, options) {
    const normalized = normalizeText(text), runes = Array.from(normalized, symbol => symbol.codePointAt(0));
    if (runes.length > MAX_CODEPOINTS) { fail('resourceLimit', 'Text exceeds ' + MAX_CODEPOINTS + ' Unicode code points'); }
    const pairs = resolvePairs(options), casing = casePlan(runes);
    let best = null;
    for (const pair of pairs) {
      const candidate = planPair(runes, pair[0], pair[1], casing);
      if (best === null || comparePairs(candidate, best) < 0) { best = candidate; }
    }
    const writer = new BitWriter();
    writer.write(1, 3); writer.write(0, 3); writer.write(best.a, 3); writer.write(best.b === null ? 7 : best.b, 3);
    for (let path = best.plan; path !== null; path = path.tail) { path.prefix.forEach(token => writeToken(writer, token)); }
    const raw = [0x23, 0x90].concat(utf8Encode(normalized));
    const useRaw = raw.length < writer.bytes.length || (raw.length === writer.bytes.length && raw.length * 8 < writer.length);
    const data = new Uint8Array(useRaw ? raw : writer.bytes), bitLength = useRaw ? raw.length * 8 : writer.length;
    const decoded = decodeStream(data, bitLength);
    return Object.assign(decoded, {data: data, bitLength: bitLength, normalizedText: normalized,
      mcotxtCandidateBytes: writer.bytes.length, rawUtf8CandidateBytes: raw.length});
  }
  function frameBytes(stream) { return new Uint8Array(varUint(stream.bitLength).concat(Array.from(stream.data))); }
  function readFrame(reader) {
    const bitLength = reader.varUint(), data = reader.take(Math.ceil(bitLength / 8));
    const result = decodeStream(data, bitLength);
    result.bitLength = bitLength;
    return result;
  }

  function base91Encode(data) {
    let buffer = 0, bits = 0, out = '';
    for (const byte of data) {
      buffer |= byte << bits; bits += 8;
      if (bits > 13) {
        let value = buffer & 8191;
        if (value > 88) { buffer >>>= 13; bits -= 13; }
        else { value = buffer & 16383; buffer >>>= 14; bits -= 14; }
        out += BASE91[value % 91] + BASE91[Math.floor(value / 91)];
      }
    }
    if (bits) {
      out += BASE91[buffer % 91];
      if (bits > 7 || buffer > 90) { out += BASE91[Math.floor(buffer / 91)]; }
    }
    return out;
  }
  function base91Decode(text) {
    requireString(text, 'Base91 data');
    if (text.length > MAX_DECODE_BYTES * 2) { fail('resourceLimit', 'Base91 input is too large'); }
    let buffer = 0, bits = 0, value = -1;
    const out = [];
    for (const symbol of text) {
      const digit = BASE91_IDS.get(symbol);
      if (digit === undefined) { fail('invalidBase91', 'Character outside Base91 alphabet'); }
      if (value < 0) { value = digit; }
      else {
        value += digit * 91; buffer |= value << bits; bits += (value & 8191) > 88 ? 13 : 14;
        do { out.push(buffer & 255); buffer >>>= 8; bits -= 8; } while (bits > 7);
        value = -1;
      }
    }
    if (value >= 0) { out.push((buffer | (value << bits)) & 255); }
    return new Uint8Array(out);
  }
  function inputBytes(input) {
    if (!input || typeof input !== 'object' || !HAS(input, 'data')) { fail('invalidInput', 'Pass an object containing data'); }
    if (input.type !== undefined && input.type !== 'binary' && input.type !== 'base91') { fail('invalidInput', 'Unknown data type'); }
    if (input.type === 'binary' && typeof input.data === 'string') { fail('invalidInput', 'binary data must be bytes'); }
    const data = input.type === 'base91' || typeof input.data === 'string' ? base91Decode(input.data) : asBytes(input.data);
    if (data.length > MAX_DECODE_BYTES) { fail('resourceLimit', 'Input exceeds decoder byte limit'); }
    return data;
  }
  function percentage(size, original) { return original ? 100 * (1 - size / original) : null; }
  function outputObject(bytes, base91, format) {
    const data = base91 ? base91Encode(bytes) : new Uint8Array(bytes);
    return {ok: true, data: data, type: base91 ? 'base91' : 'binary', format: format,
      encodedBytes: data.length, binaryBytes: bytes.length};
  }
  function streamFields(stream) {
    return {normalizedText: stream.normalizedText === undefined ? stream.text : stream.normalizedText,
      decodedText: stream.text, encodingMode: stream.encodingMode, bitLength: stream.bitLength,
      languageA: stream.languageA, languageB: stream.languageB, languages: stream.languages.slice(),
      usedTables: stream.usedTables.slice(), codecVersion: 1, modelGeneration: stream.modelGeneration};
  }
  // Frame — самодостаточная запись одного текста, без flags/имён/timestamp.
  // В data остаётся varuint(bitLength), поэтому хвостовые нули не теряются.
  function encodeFrame(text, rawOptions) {
    return safely(() => {
      const options = optionsObject(rawOptions), stream = encodeStream(text, options), bytes = frameBytes(stream);
      const out = outputObject(bytes, optionalBoolean(options, 'base91', false), 'frame');
      return Object.assign(out, streamFields(stream), {originalText: text, originalBytes: utf8Encode(text).length,
        compressionPercent: percentage(out.encodedBytes, utf8Encode(text).length)});
    });
  }
  function decodeFrame(input) {
    return safely(() => {
      const bytes = inputBytes(input), reader = new ByteReader(bytes), stream = readFrame(reader);
      reader.done();
      return Object.assign({ok: true, text: stream.text, format: 'frame', binaryBytes: bytes.length, metadata: {}}, streamFields(stream));
    });
  }
  function nameBytes(text, options, usedLanguages) {
    const normalized = normalizeText(text), plain = utf8Encode(normalized);
    const stream = encodeStream(normalized, options), coded = Array.from(frameBytes(stream));
    const raw = [1].concat(varUint(plain.length), plain);
    if (1 + coded.length > raw.length) { return raw; }
    stream.languages.forEach(code => usedLanguages.add(code));
    return [0].concat(coded);
  }
  // Основной API: возвращаем body, а не payload/envelope. Пустой sender
  // сознательно опускаем; пустой replyAuthor с timestamp остаётся допустимым.
  function encode(text, rawOptions) {
    return safely(() => {
      const options = optionsObject(rawOptions), stream = encodeStream(text, options), frame = frameBytes(stream);
      const sender = options.senderName === undefined || options.senderName === null || options.senderName === ''
        ? null : normalizeText(requireString(options.senderName, 'senderName'));
      const hasReply = options.replyAuthorName !== undefined && options.replyAuthorName !== null;
      const hasReplyTime = options.replyTimestamp !== undefined && options.replyTimestamp !== null;
      if (hasReply !== hasReplyTime) { fail('invalidInput', 'replyAuthorName and replyTimestamp must be provided together'); }
      const replyAuthor = hasReply ? normalizeText(requireString(options.replyAuthorName, 'replyAuthorName')) : null;
      const replyTimestamp = hasReply ? uint32(options.replyTimestamp, 'replyTimestamp') : null;
      const inherits = options.timestamp === undefined || options.timestamp === null;
      const timestamp = inherits ? null : uint32(options.timestamp, 'timestamp');
      const usedLanguages = new Set();
      let bytes = [(sender !== null ? 2 : 0) | (hasReply ? 1 : 0) | (inherits ? 4 : 0)];
      if (!inherits) { bytes = bytes.concat(uint32Bytes(timestamp)); }
      if (sender !== null) { bytes = bytes.concat(nameBytes(sender, options, usedLanguages)); }
      if (hasReply) { bytes = bytes.concat(nameBytes(replyAuthor, options, usedLanguages), uint32Bytes(replyTimestamp)); }
      bytes = bytes.concat([0], Array.from(frame));
      stream.languages.forEach(code => usedLanguages.add(code));
      const out = outputObject(new Uint8Array(bytes), optionalBoolean(options, 'base91', false), 'body');
      const originalBytes = utf8Encode(text).length;
      return Object.assign(out, streamFields(stream), {
        originalText: text, originalBytes: originalBytes, compressionPercent: percentage(out.encodedBytes, originalBytes),
        textEncodedBytes: frame.length, textCompressionPercent: percentage(frame.length, originalBytes),
        textLanguages: stream.languages.slice(), languages: Array.from(usedLanguages),
        metadata: {timestamp: timestamp, timestampSource: inherits ? 'inherited' : 'embedded',
          senderName: sender, replyAuthorName: replyAuthor, replyTimestamp: replyTimestamp}
      });
    });
  }
  function readString(reader, languages) {
    const mode = reader.byte();
    if (mode === 1) { return {text: utf8Decode(reader.take(reader.varUint())), languages: []}; }
    if (mode !== 0) { fail('invalidStringMode', 'Unsupported string mode'); }
    const result = readFrame(reader);
    result.languages.forEach(code => languages.add(code));
    return result;
  }
  function decodeBody(bytes, input) {
    const reader = new ByteReader(bytes), flags = reader.byte(), languages = new Set();
    if (flags & ~7) { fail('invalidFlags', 'Unsupported app flags'); }
    const inherits = !!(flags & 4);
    const timestamp = inherits ? (input.inheritedTimestamp === undefined ? null : uint32(input.inheritedTimestamp, 'inheritedTimestamp')) : reader.uint32();
    const sender = flags & 2 ? readString(reader, languages).text : null;
    const replyAuthor = flags & 1 ? readString(reader, languages).text : null;
    const replyTimestamp = flags & 1 ? reader.uint32() : null;
    const text = readString(reader, languages); reader.done();
    return Object.assign({ok: true, text: text.text}, text.encodingMode === undefined ? {} : streamFields(text), {
      languages: Array.from(languages), textLanguages: text.languages.slice(),
      metadata: {flags: flags, timestamp: timestamp, timestampSource: inherits ? 'inherited' : 'embedded',
        senderName: sender, replyAuthorName: replyAuthor, replyTimestamp: replyTimestamp}
    });
  }
  function unpack(bytes, format) {
    if (format === 'body') { return {body: bytes, envelope: null}; }
    const reader = new ByteReader(bytes);
    const outerName = format === 'envelope' ? utf8Decode(reader.take(reader.varUint())) : null;
    const packed = reader.byte();
    if ((packed >> 4) !== 3) { fail('wrongSubtype', 'Envelope does not contain MCOtxt'); }
    if ((packed & 15) !== 1) { fail('unsupportedFormat', 'Unsupported MCOtxt app format'); }
    return {body: reader.take(bytes.length - reader.position),
      envelope: {subtypeId: 3, version: 1, outerSenderName: outerName}};
  }
  // mct: имеет однозначный префикс. Для остальных входов проверяем контейнеры
  // целиком, не только первый байт. Два валидных разбора требуют format от caller.
  function decode(input) {
    return safely(() => {
      if (!input || typeof input !== 'object') { fail('invalidInput', 'Pass {data, type, format}'); }
      if (input.type !== undefined && input.type !== 'binary' && input.type !== 'base91') { fail('invalidInput', 'Unknown data type'); }
      let format = input.format === undefined ? 'auto' : input.format;
      let bytes;
      const textData = typeof input.data === 'string' ? input.data.replace(/^\s+/, '') : null;
      if (textData !== null && textData.indexOf('mct:') === 0) {
        if (input.type === 'binary') { fail('invalidInput', 'mct: is text, not binary data'); }
        if (format !== 'auto' && format !== 'mct') { fail('invalidInput', 'mct: conflicts with format'); }
        bytes = base91Decode(textData.slice(4)); format = 'mct';
      } else { bytes = inputBytes(input); }
      if (bytes.length > MAX_DECODE_BYTES) { fail('resourceLimit', 'Input exceeds decoder byte limit'); }
      if (format === 'frame') { return decodeFrame(input); }
      function attempt(selected) {
        const unpacked = unpack(bytes, selected === 'mct' ? 'payload' : selected);
        return Object.assign(decodeBody(unpacked.body, input), {format: selected,
          binaryBytes: bytes.length, envelope: unpacked.envelope});
      }
      if (format === 'auto') {
        const successes = [];
        for (const candidate of ['body', 'envelope', 'payload']) {
          try { successes.push(attempt(candidate)); }
          catch (error) { if (!(error instanceof MCOtxtError)) { throw error; } }
        }
        if (!successes.length) { fail('invalidContainer', 'No valid MCOtxt body or envelope; pass an explicit format for details'); }
        if (successes.length > 1) { fail('ambiguousFormat', 'Ambiguous binary input; specify body, envelope or payload'); }
        return successes[0];
      }
      if (['body', 'envelope', 'payload', 'mct'].indexOf(format) < 0) { fail('invalidInput', 'Unknown input format'); }
      return attempt(format);
    });
  }
  function bodyInput(value) {
    const input = value && typeof value === 'object' && HAS(value, 'data') ? value : {data: value, format: 'body'};
    if (input.ok === false) { fail('invalidInput', 'Cannot wrap a failed encoding'); }
    if (input.format !== undefined && input.format !== 'body') { fail('invalidInput', 'Expected a body, not a frame or envelope'); }
    const bytes = inputBytes(input); decodeBody(bytes, {}); return bytes;
  }
  // Упаковка не меняет flags и время body. Размер радиотранспорта проверяется
  // отдельно: произвольный корректный frame может быть длиннее одного пакета.
  function toTextTransport(value) { return 'mct:' + base91Encode(new Uint8Array([0x31].concat(Array.from(bodyInput(value))))); }
  function wrapEnvelope(value, rawOptions) {
    const options = optionsObject(rawOptions), name = utf8Encode(options.outerSenderName === undefined ? '' : requireString(options.outerSenderName, 'outerSenderName'));
    const bytes = new Uint8Array(varUint(name.length).concat(name, [0x31], Array.from(bodyInput(value))));
    if (optionalBoolean(options, 'enforceRadioLimit', true) && bytes.length > 165) { fail('payloadTooLarge', 'Envelope exceeds the 165-byte channel payload limit'); }
    return outputObject(bytes, optionalBoolean(options, 'base91', false), 'envelope');
  }
  function toHex(value) { return Array.from(asBytes(value), byte => ('0' + byte.toString(16)).slice(-2)).join(''); }
  function fromHex(text) {
    const compact = requireString(text, 'hex').replace(/\s/g, '');
    if (compact.length % 2 || /[^0-9a-f]/i.test(compact)) { fail('invalidHex', 'Expected complete hexadecimal bytes'); }
    const bytes = [];
    for (let i = 0; i < compact.length; i += 2) { bytes.push(parseInt(compact.slice(i, i + 2), 16)); }
    return new Uint8Array(bytes);
  }

  // Один объект в window. В Node тест загружает тот же файл через vm, без require в кодеке.
  root.MCOtxt = Object.freeze({
    version: '1.0.0', codecVersion: 1, modelGeneration: 0,
    encode: encode, decode: decode, encodeFrame: encodeFrame, decodeFrame: decodeFrame,
    normalizeText: normalizeText, toTextTransport: toTextTransport, wrapEnvelope: wrapEnvelope,
    toHex: toHex, fromHex: fromHex, toBase91: value => base91Encode(asBytes(value)), fromBase91: base91Decode,
    getLanguages: () => MODELS.map(model => ({code: LANGUAGE_CODES[model.id], id: model.id,
      name: LANGUAGE_NAMES[model.id], modelGeneration: 0, wireHash: model.hash})),
    limits: Object.freeze({maxEncodeCodepoints: MAX_CODEPOINTS, maxDecodeBytes: MAX_DECODE_BYTES, channelPayloadBytes: 165}),
    MCOtxtError: MCOtxtError
  });
}(typeof window !== 'undefined' ? window : this));
