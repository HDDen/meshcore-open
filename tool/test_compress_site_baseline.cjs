'use strict';

// Владелец запускает до интеграции MCOtxt и после неё:
// node tool/test_compress_site_baseline.cjs
// Загружаем неизменённый app.js целиком, включая init. DOM минимальный:
// это проверки расчётов/состояния/HTML-строк, не отрисовка в браузере.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {TextEncoder} = require('node:util');

const siteRoot = path.resolve(__dirname, '../hdden.ru/public_html/compress');
const source = fs.readFileSync(path.join(siteRoot, 'app.js'), 'utf8');

class Element {
  constructor() {
    this.value = '';
    this.textContent = '';
    this.innerHTML = '';
    this.style = {};
    this.children = [];
    this.attributes = new Map();
    this.listeners = new Map();
    this.classes = new Set();
    this.classList = {toggle: (name, enabled) => enabled ? this.classes.add(name) : this.classes.delete(name)};
    this.content = {cloneNode: () => new Element()};
  }
  addEventListener(event, handler) { this.listeners.set(event, handler); }
  appendChild(child) { this.children.push(child); }
  querySelector() { return new Element(); }
  hasAttribute(name) { return this.attributes.has(name); }
  setAttribute(name, value) { this.attributes.set(name, value); }
  removeAttribute(name) { this.attributes.delete(name); }
  setSelectionRange(start, end) { this.selectionStart = start; this.selectionEnd = end; }
}

function boot(options = {}) {
  const storage = new Map(Object.entries(options.saved || {}));
  const elements = new Map();
  let sequence = 0;
  const sandbox = {
    TextEncoder,
    crypto: {randomUUID: () => 'synthetic-' + (++sequence)},
    localStorage: {
      getItem: key => storage.has(key) ? storage.get(key) : null,
      setItem: (key, value) => storage.set(key, String(value))
    },
    document: {getElementById: id => {
      if (!elements.has(id)) { elements.set(id, new Element()); }
      return elements.get(id);
    }},
    window: {confirm: () => true, alert: () => {}},
    console,
  };
  if (options.mesh) {
    const model = {clearCache: () => {}};
    sandbox.NGramModel = {fromJSON: () => model};
    sandbox.window.MESH_COMPRESSOR_MODEL_DATA = {};
    sandbox.compress = () => new Uint8Array([0, 128, 255]);
    sandbox.compressText = () => 'ASCII';
  }
  if (options.lzw) {
    sandbox.window.lzwCompressionHelper = {compressText: () => ({display: 'SYNTHETIC LZW', byteSize: 4})};
  }
  const context = vm.createContext(sandbox);
  vm.runInContext(source, context, {filename: path.join(siteRoot, 'app.js'), timeout: 5000});
  return {context, storage, elements, run: script => vm.runInContext(script, context, {timeout: 5000})};
}
function plain(value) { return JSON.parse(JSON.stringify(value)); }
let count = 0;
function test(name, action) {
  try { action(); count++; console.log('PASS ' + name); }
  catch (error) { console.error('FAIL ' + name); throw error; }
}

test('fresh startup seeds dictionaries and leaves existing optional methods disabled', () => {
  const app = boot();
  assert.equal(app.run('state.settings.meshEnabled'), false);
  assert.equal(app.run('state.settings.lzwEnabled'), false);
  assert.equal(app.run('state.dictionaries.length'), 3);
  assert.equal(JSON.parse(app.storage.get('compression-demo.dictionaries')).length, 3);
  assert.equal(app.run('buildMeshResultRows("hello", 5, 1).length'), 0);
  assert.equal(app.run('buildLzwResultRow("hello", 5, 1)'), null);
});

test('UTF-8 byte counts and signed differences use bytes, not Hex display length', () => {
  const app = boot();
  assert.equal(app.run('getUtf8ByteLength("Привет😀")'), 16);
  assert.equal(app.run('bytesToHex([0,128,255])'), '0080ff');
  const row = plain(app.run('buildCompressedResultRow({orderNumber:2,label:"Binary",text:"0080ff",byteSize:3,originalBytes:10})'));
  assert.equal(row.byteSize, 3);
  assert.equal(row.diffLabel, '-7');
  assert.equal(row.percentLabel, '-70%');
  assert.equal(row.metricClass, 'metric-good');
  const larger = app.run('buildCompressedResultRow({orderNumber:1,label:"X",text:"xx",byteSize:12,originalBytes:10})');
  assert.equal(larger.diffLabel, '+2');
  assert.equal(larger.percentLabel, '+20%');
  assert.equal(larger.metricClass, 'metric-bad');
});

test('original and empty-input rows have defined metric values', () => {
  const app = boot();
  const row = app.run('buildResultRow({orderNumber:1,label:"Original",text:"я",originalBytes:2,isOriginal:true})');
  assert.equal(row.byteSize, 2);
  assert.equal(row.diffLabel, '');
  assert.equal(row.percentLabel, '');
  assert.equal(row.metricClass, 'metric-neutral');
  const empty = app.run('buildCompressedResultRow({orderNumber:1,label:"X",text:"",byteSize:0,originalBytes:0})');
  assert.equal(empty.percentLabel, '0%');
  assert.equal(empty.metricClass, 'metric-neutral');
});

test('stored examples, dictionaries and settings survive startup and toggles', () => {
  const saved = {
    'compression-demo.examples': JSON.stringify([{id: 'keep', text: 'Мой пример', createdAt: 1}]),
    'compression-demo.dictionaries': JSON.stringify([{id: 'dict', name: 'User', enabled: true, mapping: {'я': 'ya'}, createdAt: 1}]),
    'compression-demo.settings': JSON.stringify({sortDirection: 'asc', byteLimit: '30', meshEnabled: true, lzwEnabled: true, customField: 'keep'})
  };
  const app = boot({saved, mesh: true, lzw: true});
  assert.equal(app.run('state.examples[0].text'), 'Мой пример');
  assert.equal(app.run('state.dictionaries[0].name'), 'User');
  app.run('toggleMeshMethod(); toggleLzwMethod();');
  const settings = JSON.parse(app.storage.get('compression-demo.settings'));
  assert.equal(settings.meshEnabled, false);
  assert.equal(settings.lzwEnabled, false);
  assert.equal(settings.byteLimit, '30');
  assert.equal(settings.customField, 'keep');
  assert.equal(app.storage.get('compression-demo.examples'), saved['compression-demo.examples']);
  assert.equal(app.storage.get('compression-demo.dictionaries'), saved['compression-demo.dictionaries']);
});

test('dictionary replacements remain ordered and ignore an empty search key', () => {
  const app = boot();
  assert.equal(app.run('applyDictionary("аб", {"а":"б","б":"c","":"bad"})'), 'cc');
  assert.equal(app.run('getUtf8ByteLength(applyDictionary("я", {"я":"ya"}))'), 2);
});

test('rendered history escapes text and labels and preserves sorting', () => {
  const app = boot();
  app.run('state.dictionaries=[{id:"d",name:"<dict>",enabled:true,mapping:{}}]; state.examples=[{id:"old",text:"<script>&",createdAt:1},{id:"new",text:"second",createdAt:2}]; renderResults();');
  let html = app.elements.get('results-body').innerHTML;
  assert.ok(html.includes('&lt;script&gt;&amp;'));
  assert.ok(html.includes('&lt;dict&gt;'));
  assert.ok(!html.includes('<script>'));
  assert.ok(html.indexOf('second') < html.indexOf('&lt;script&gt;'));
  app.run('toggleSortDirection();');
  html = app.elements.get('results-body').innerHTML;
  assert.ok(html.indexOf('&lt;script&gt;') < html.indexOf('second'));
});

test('mesh binary and Base91 rows use their actual representation sizes', () => {
  const app = boot({mesh: true});
  const rows = plain(app.run('state.settings.meshEnabled=true; buildMeshResultRows("source text", 11, 1)'));
  assert.equal(rows.length, 2);
  assert.equal(rows[0].text, '0080ff');
  assert.equal(rows[0].byteSize, 3);
  assert.equal(rows[1].text, 'ASCII');
  assert.equal(rows[1].byteSize, 5);
});

test('LZW row uses helper byte size and missing libraries do not crash rendering', () => {
  const available = boot({lzw: true});
  const row = available.run('state.settings.lzwEnabled=true; buildLzwResultRow("hello", 5, 1)');
  assert.equal(row.text, 'SYNTHETIC LZW');
  assert.equal(row.byteSize, 4);
  const missing = boot();
  assert.doesNotThrow(() => missing.run('state.settings.meshEnabled=true; state.settings.lzwEnabled=true; state.examples=[{id:"x",text:"hello"}]; renderResults();'));
  assert.ok(missing.elements.get('results-body').innerHTML.includes('не загружен'));
});

test('byte limit rejects an oversized edit without removing saved examples', () => {
  const app = boot();
  app.run('state.settings.byteLimit="4"; elements.sourceInput.value="яя"; handleSourceInput(); elements.sourceInput.value="яя😀"; handleSourceInput();');
  assert.equal(app.elements.get('source-input').value, 'яя');
  app.run('addExample();');
  assert.equal(app.run('state.examples[0].text'), 'яя');
  assert.equal(JSON.parse(app.storage.get('compression-demo.examples'))[0].text, 'яя');
  assert.equal(app.elements.get('source-input').value, '');
});

console.log('All ' + count + ' site baseline checks passed. Browser rendering is not covered.');
