'use strict';

// Запускает владелец: node tool/test_mcotxt_js.cjs
// Тот же классический файл, что загружает браузер. Ни npm, ни DOM не нужны.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = path.resolve(__dirname, '..');
const asset = path.join(root, 'docs/mcotxt/assets/mcotxt.js');
const source = fs.readFileSync(asset, 'utf8');
const fixturePath = path.join(root, 'test/MCOtxt/fixtures/js_reference_v1.json');
if (!fs.existsSync(fixturePath)) {
  throw new Error('Missing frozen Dart fixture. Run mcotxt_js_reference.dart --write first.');
}
const fixture = JSON.parse(fs.readFileSync(fixturePath, 'utf8'));
const context = vm.createContext({window: {}, Uint8Array, ArrayBuffer});
vm.runInContext(source, context, {filename: asset, timeout: 5000});
const codec = context.window.MCOtxt;
assert.deepEqual(Object.keys(context.window), ['MCOtxt']);
assert.equal(codec.codecVersion, fixture.codecVersion);
assert.equal(codec.modelGeneration, fixture.modelGeneration);

let checks = 0;
function test(name, action) {
  try { action(); checks++; console.log('PASS ' + name); }
  catch (error) { console.error('FAIL ' + name); throw error; }
}
function ok(result) {
  assert.equal(result.ok, true, JSON.stringify(result));
  return result;
}
function error(result, code) {
  assert.equal(result.ok, false, JSON.stringify(result));
  if (code !== undefined) { assert.equal(result.error.code, code); }
  assert.equal(typeof result.error.message, 'string');
}
function plain(value) { return JSON.parse(JSON.stringify(value)); }
function optionsFor(input) {
  const options = input.languageA === null
    ? {languages: codec.getLanguages().map(language => language.code)}
    : {languagePair: [input.languageA, input.languageB]};
  if (input.includeTimestamp) { options.timestamp = input.timestamp; }
  if (input.senderName !== null) { options.senderName = input.senderName; }
  if (input.replyAuthorName !== null) {
    options.replyAuthorName = input.replyAuthorName;
    options.replyTimestamp = input.replyTimestamp;
  }
  return options;
}
function metadata(result, expected, timestamp) {
  assert.equal(result.text, expected.text);
  assert.equal(result.metadata.timestamp, timestamp);
  assert.equal(result.metadata.senderName, expected.senderName);
  assert.equal(result.metadata.replyAuthorName, expected.replyAuthorName);
  assert.equal(result.metadata.replyTimestamp, expected.replyTimestamp);
}

// Проверяем все элементы моделей, а не только заявленные wireHash.
// Это статическое чтение литералов двух портов; модели не пересоздаются.
test('all seven embedded model literals equal the frozen Dart tables', () => {
  const pattern = /makeModel\((\d+),\s*'([0-9a-f]+)',\s*'([^']*)',\s*'([^']*)',\s*'([^']*)',\s*'([^']*)',\s*\[([^\]]*)\],\s*\[([^\]]*)\],\s*\[([^\]]*)\]\)/g;
  const declarations = Array.from(source.matchAll(pattern));
  assert.equal(declarations.length, 7);
  const numbers = text => Array.from(text.matchAll(/0x[0-9a-f]+|\d+/gi), match => Number(match[0]));
  for (const declaration of declarations) {
    const id = Number(declaration[1]), language = codec.getLanguages()[id];
    const dart = fs.readFileSync(path.join(root, 'lib/MCOtxt/models/generated/v1/model_' + language.code + '.dart'), 'utf8');
    const prefix = 'mcotxt' + language.code[0].toUpperCase() + language.code.slice(1);
    function array(field) {
      const match = dart.match(new RegExp(prefix + field + ' = <int>\\[([\\s\\S]*?)\\];'));
      assert.ok(match, prefix + field);
      return numbers(match[1]);
    }
    assert.equal(declaration[2], fixture.models[language.code]);
    assert.equal(language.wireHash, fixture.models[language.code]);
    assert.deepEqual(Array.from(declaration[3], ch => ch.codePointAt(0)), array('PrimarySymbols'));
    assert.deepEqual(Array.from(declaration[4], ch => ch.codePointAt(0)), array('ExtensionSymbols'));
    assert.deepEqual(numbers(declaration[7]), array('StartTop4Indexes'));
    assert.deepEqual(numbers(declaration[8]), array('PunctStartTop4Indexes'));
    assert.deepEqual(numbers(declaration[9]), array('Top4Indexes'));
    const mapping = dart.match(/UppercaseToLowercase = <int, int>\{([\s\S]*?)\};/)[1];
    const pairs = Array.from(mapping.matchAll(/(0x[0-9a-f]+): (0x[0-9a-f]+)/gi));
    assert.deepEqual(Array.from(declaration[5], ch => ch.codePointAt(0)), pairs.map(pair => Number(pair[1])));
    assert.deepEqual(Array.from(declaration[6], ch => ch.codePointAt(0)), pairs.map(pair => Number(pair[2])));
  }
});

for (const sample of fixture.cases) {
  test('Dart wire compatibility: ' + sample.id, () => {
    const input = sample.input, expected = sample.expected, options = optionsFor(input);
    const frame = ok(codec.encodeFrame(input.text, options));
    assert.equal(codec.toHex(frame.data), expected.frameHex);
    assert.equal(frame.bitLength, expected.bitLength);
    assert.equal(frame.encodingMode, expected.encodingMode);
    assert.equal(frame.languageA, expected.languageA);
    assert.equal(frame.languageB, expected.languageB);
    assert.deepEqual(plain(frame.usedTables), expected.usedTables);
    assert.equal(frame.originalText, input.text);
    assert.equal(frame.originalBytes, expected.originalBytes);
    assert.equal(frame.binaryBytes, expected.textEncodedBytes);
    assert.equal(ok(codec.decodeFrame(frame)).text, expected.text);

    const encoded = ok(codec.encode(input.text, options));
    if (sample.id === 'empty-sender-field') {
      // Намеренное новое правило encode: пустой sender опускается.
      // Приём старого Dart-поля ниже всё равно проверяется побайтным примером.
      const withoutName = ok(codec.encode(input.text, Object.assign({}, options, {senderName: undefined})));
      assert.equal(codec.toHex(encoded.data), codec.toHex(withoutName.data));
      assert.equal(encoded.data[0] & 2, 0);
    } else {
      assert.equal(codec.toHex(encoded.data), expected.bodyHex);
      assert.equal(encoded.binaryBytes, expected.bodyBytes);
      assert.equal(encoded.encodedBytes, expected.bodyBytes);
      assert.equal(codec.toTextTransport(encoded), expected.mct);
      const base91 = ok(codec.encode(input.text, Object.assign({}, options, {base91: true})));
      assert.equal(base91.data, expected.bodyBase91);
      assert.equal(base91.encodedBytes, expected.bodyBase91.length);
      assert.equal(base91.binaryBytes, expected.bodyBytes);
      assert.equal(ok(codec.decode(base91)).text, expected.text);
      if (expected.envelopeHex !== null) {
        const envelope = codec.wrapEnvelope(encoded, {outerSenderName: input.outerSenderName});
        assert.equal(codec.toHex(envelope.data), expected.envelopeHex);
      }
    }
    assert.equal(encoded.textEncodedBytes, expected.textEncodedBytes);
    const body = codec.fromHex(expected.bodyHex);
    assert.equal(codec.toBase91(body), expected.bodyBase91);
    assert.equal(codec.toHex(codec.fromBase91(expected.bodyBase91)), expected.bodyHex);
    const inherited = input.includeTimestamp ? expected.timestamp : null;
    metadata(ok(codec.decode({data: body, format: 'body'})), expected, inherited);
    metadata(ok(codec.decode({data: expected.mct})), expected, inherited);
    metadata(ok(codec.decode({data: codec.fromHex(expected.appPayloadHex), format: 'payload'})), expected, inherited);
    if (!input.includeTimestamp) {
      metadata(ok(codec.decode({data: expected.mct, inheritedTimestamp: 123})), expected, 123);
    }
    if (expected.envelopeHex !== null) {
      const envelope = codec.fromHex(expected.envelopeHex);
      const decoded = ok(codec.decode({data: envelope, format: 'envelope'}));
      metadata(decoded, expected, inherited);
      assert.equal(decoded.envelope.outerSenderName, input.outerSenderName);
      assert.equal(decoded.envelope.subtypeId, 3);
      assert.equal(decoded.envelope.version, 1);
      metadata(ok(codec.decode({data: envelope})), expected, inherited);
    }
  });
}

test('candidate languages select the best primary pair, with other models allowed', () => {
  const text = 'Привет! Hello, bonjour, українська мова.';
  const selected = ok(codec.encodeFrame(text, {languages: ['ru', 'en']}));
  const alternatives = [['en', 'ru'], ['en', null], ['ru', 'en'], ['ru', null]]
    .map(pair => ok(codec.encodeFrame(text, {languagePair: pair})));
  const size = alternatives.map(value => value.bitLength);
  assert.equal(selected.bitLength, Math.min(...size));
  assert.equal(ok(codec.decodeFrame(selected)).text, text);
  const onlyEnglish = ok(codec.encodeFrame('проверка русского текста', {languages: ['en']}));
  assert.equal(onlyEnglish.languageA, 'en');
  assert.ok(onlyEnglish.languages.indexOf('ru') >= 0);
  assert.equal(ok(codec.decodeFrame(onlyEnglish)).text, 'проверка русского текста');
});

test('sizes, savings, empty text and a sender-free benchmark', () => {
  const text = 'Связь через ретранслятор на вершине, встречаемся к обеду.';
  for (const base91 of [false, true]) {
    const result = ok(codec.encode(text, {senderName: '', base91: base91}));
    assert.equal(result.metadata.senderName, null);
    assert.equal(result.metadata.timestamp, null);
    assert.equal(result.encodedBytes, result.data.length);
    assert.equal(result.originalBytes, Buffer.byteLength(text, 'utf8'));
    assert.equal(result.compressionPercent, 100 * (1 - result.encodedBytes / result.originalBytes));
    assert.equal(result.textCompressionPercent, 100 * (1 - result.textEncodedBytes / result.originalBytes));
    assert.equal(result.textEncodedBytes, ok(codec.encodeFrame(text)).binaryBytes);
  }
  const empty = ok(codec.encode('', {senderName: ''}));
  assert.equal(empty.originalBytes, 0);
  assert.equal(empty.compressionPercent, null);
  assert.equal(empty.textCompressionPercent, null);
  assert.ok(ok(codec.encode('A')).compressionPercent < 0);
});

test('UTF8_RUN crosses 32-byte boundaries inside compressed text; case survives', () => {
  const text = 'Связь через ретранслятор на вершине. '.repeat(4) + '😀'.repeat(12) +
    '\nВНИМАНИЕ!\n' + 'Проверяем продолжение сообщения. '.repeat(4);
  const frame = ok(codec.encodeFrame(text, {languagePair: ['ru', 'en']}));
  assert.equal(frame.encodingMode, 'mcotxt');
  assert.equal(ok(codec.decodeFrame(frame)).text, text);
  for (const text of ['ABC DEF 123 !? abc XYZ', 'a\u0308 e\u0301 q\u0301', 'А АА ААА а ааа',
    'one  two\nthree... four', 'приветBonjourGUTENукраїнська', '😀я😀test😀']) {
    const result = ok(codec.encodeFrame(text));
    assert.equal(ok(codec.decodeFrame(result)).text, codec.normalizeText(text));
  }
});

test('Base91 handles every byte and binary views keep their actual slice', () => {
  const bytes = new Uint8Array(Array.from({length: 256}, (_, index) => index));
  assert.equal(codec.toHex(codec.fromBase91(codec.toBase91(bytes))), codec.toHex(bytes));
  const result = ok(codec.encode('Тест среза'));
  const buffer = new Uint8Array(result.data.length + 8);
  buffer.set(result.data, 4);
  const view = new DataView(buffer.buffer, 4, result.data.length);
  assert.equal(ok(codec.decode({data: view, format: 'body'})).text, 'Тест среза');
});

test('empty reply author, zero timestamps, Unicode and owned byte arrays', () => {
  const result = ok(codec.encode('😀<script> и\u0306\r\nhello', {
    senderName: 'Alice', timestamp: 0, replyAuthorName: '', replyTimestamp: 0
  }));
  const decoded = ok(codec.decode(result));
  assert.equal(decoded.text, '😀<script> й\nhello');
  assert.equal(decoded.metadata.timestamp, 0);
  assert.equal(decoded.metadata.replyAuthorName, '');
  assert.equal(decoded.metadata.replyTimestamp, 0);
  const saved = codec.toHex(result.data);
  result.data.fill(0);
  const next = ok(codec.encode('😀<script> и\u0306\r\nhello', {
    senderName: 'Alice', timestamp: 0, replyAuthorName: '', replyTimestamp: 0
  }));
  assert.equal(codec.toHex(next.data), saved);
  const languages = codec.getLanguages(); languages[0].code = 'broken';
  assert.equal(codec.getLanguages()[0].code, 'en');
});

function frameFromBits(bits) {
  const bytes = [];
  for (let i = 0; i < bits.length; i += 8) {
    bytes.push(parseInt((bits.slice(i, i + 8) + '0000000').slice(0, 8), 2));
  }
  let length = bits.length;
  const header = [];
  do { const byte = length & 127; length = Math.floor(length / 128); header.push(byte | (length ? 128 : 0)); } while (length);
  return new Uint8Array(header.concat(bytes));
}
const normalHeader = '001000001000';
test('strict malformed frame and token handling', () => {
  error(codec.decodeFrame({data: []}), 'unexpectedEnd');
  error(codec.decodeFrame({data: [128,128,128,128,128]}), 'invalidLength');
  error(codec.decodeFrame({data: [127,0]}), 'unexpectedEnd');
  error(codec.decodeFrame({data: frameFromBits('010000001000')}), 'unknownVersion');
  error(codec.decodeFrame({data: frameFromBits(normalHeader + '11110')}), 'invalidShift');
  error(codec.decodeFrame({data: frameFromBits(normalHeader + '1111011110')}), 'invalidShift');
  error(codec.decodeFrame({data: frameFromBits(normalHeader + '111111100')}), 'unknownExtendedControl');
  error(codec.decodeFrame({data: frameFromBits(normalHeader + '11111100011111111')}), 'invalidOtherLanguage');
  const unknownGenerationRaw = '00111100000001' + '1110010000' + '01000001';
  const raw = ok(codec.decodeFrame({data: frameFromBits(unknownGenerationRaw)}));
  assert.equal(raw.text, 'A'); assert.equal(raw.modelGeneration, 8);
  error(codec.decodeFrame({data: frameFromBits('001001001000')}), 'unsupportedModelGeneration');
  // RAW_UTF8 0x2390, затем запрещённая overlong-последовательность C0 AF.
  error(codec.decodeFrame({data: [32,0x23,0x90,0xc0,0xaf]}), 'invalidUtf8');
  assert.equal(ok(codec.decodeFrame({data: [48,0x23,0x90,0xef,0xbb,0xbf,65]})).text, 'A');
});

test('invalid input and app containers report structured failures', () => {
  for (const options of [null, {languages: []}, {languages: ['xx']}, {languagePair: ['ru','ru']},
    {timestamp: -1}, {timestamp: 1.2}, {replyAuthorName: 'A'}, {replyTimestamp: 0},
    {replyAuthorName: 7, replyTimestamp: 0}, {senderName: 1}, {base91: 1}, {modelGeneration: 1}]) {
    error(codec.encode('hello', options));
  }
  error(codec.encode(7));
  error(codec.encode('a'.repeat(codec.limits.maxEncodeCodepoints + 1)), 'resourceLimit');
  error(codec.decode({data: 'mct: '}), 'invalidBase91');
  error(codec.decode({data: 'mct:AA', type: 'unknown'}), 'invalidInput');
  error(codec.decode({data: [], format: 'body'}), 'unexpectedEnd');
  error(codec.decode({data: [8], format: 'body'}), 'invalidFlags');
  error(codec.decode({data: [4,2], format: 'body'}), 'invalidStringMode');
  error(codec.decode({data: [0,0x32,4,0], format: 'envelope'}), 'unsupportedFormat');
  error(codec.decode({data: [0,0x21], format: 'envelope'}), 'wrongSubtype');
  error(codec.decode({data: [-1], format: 'body'}), 'invalidInput');
  const valid = ok(codec.encode('hello'));
  error(codec.decode({data: Array.from(valid.data).concat([0]), format: 'body'}), 'trailingBytes');
  error(codec.decode({data: valid.data.slice(0, -1), format: 'body'}), 'unexpectedEnd');
  assert.throws(() => codec.fromHex('f'), /hexadecimal/);
  assert.throws(() => codec.fromHex('zz'), /hexadecimal/);
  const frame = ok(codec.encodeFrame('hello'));
  assert.throws(() => codec.toTextTransport(frame), /body/);
});

test('transport helpers preserve metadata and enforce the radio limit explicitly', () => {
  const body = ok(codec.encode('Контроль связи', {timestamp: 0xffffffff, senderName: 'А'}));
  assert.equal(ok(codec.decode({data: '  ' + codec.toTextTransport(body)})).metadata.timestamp, 0xffffffff);
  const envelope = codec.wrapEnvelope(body, {outerSenderName: 'Legacy', base91: true});
  assert.equal(ok(codec.decode(envelope)).envelope.outerSenderName, 'Legacy');
  const long = ok(codec.encode('0123456789'.repeat(100)));
  assert.throws(() => codec.wrapEnvelope(long), /165-byte/);
  assert.equal(ok(codec.decode(codec.wrapEnvelope(long, {enforceRadioLimit: false}))).text, '0123456789'.repeat(100));
  assert.equal(codec.toHex(codec.fromHex('00 ff 80')), '00ff80');
});

test('auto detection refuses a genuinely ambiguous binary container', () => {
  // Одни байты — допустимые body и envelope, но их тексты различаются.
  // body: timestamp=0x02010431, mode=UTF8, length=0.
  // envelope: empty outer name, 0x31, inherited time, UTF8 length=2.
  const bytes = [0,0x31,4,1,2,1,0];
  error(codec.decode({data: bytes}), 'ambiguousFormat');
  assert.equal(ok(codec.decode({data: bytes, format: 'body'})).text, '');
  assert.equal(ok(codec.decode({data: bytes, format: 'envelope'})).text, '\u0001\u0000');
});

console.log('All ' + checks + ' JS checks passed. Not a browser/device test or energy measurement.');
