'use strict';

// Регрессии интеграции: настоящий кодек и адаптер, существующий app.js/init.
// DOM минимальный: реальную вёрстку и сетевые скрипты этот тест не запускает.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {TextEncoder} = require('node:util');

const root = path.resolve(__dirname, '..');
const site = path.join(root, 'hdden.ru/public_html/compress');
const html = fs.readFileSync(path.join(site, 'index.html'), 'utf8');
const appSource = fs.readFileSync(path.join(site, 'app.js'), 'utf8');
const codecPath = path.join(site, 'assets/mcotxt/mcotxt.js');
const adapterPath = path.join(site, 'assets/mcotxt/mcotxt-comparison.js');
const ids = Array.from(html.matchAll(/\bid="([^"]+)"/g), match => match[1]);

class Element {
  constructor() {
    this.value = ''; this.textContent = ''; this.innerHTML = ''; this.style = {};
    this.attributes = new Map(); this.listeners = new Map(); this.children = [];
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
}

function boot(options = {}) {
  const elements = new Map(ids.map(id => [id, new Element()]));
  const storage = new Map(Object.entries(options.saved || {}));
  const calls = [];
  let sequence = 0;
  const model = {clearCache: () => {}};
  const sandbox = {
    TextEncoder, Uint8Array, ArrayBuffer,
    crypto: {randomUUID: () => 'synthetic-' + (++sequence)},
    document: {getElementById: id => elements.get(id) || null},
    localStorage: {
      getItem: key => storage.has(key) ? storage.get(key) : null,
      setItem: (key, value) => storage.set(key, String(value))
    },
    NGramModel: {fromJSON: () => model},
    compress: () => new Uint8Array([0, 128, 255]),
    compressText: () => 'ASCII',
    window: {
      confirm: () => true, alert: () => {}, MESH_COMPRESSOR_MODEL_DATA: {},
      lzwCompressionHelper: {compressText: () => ({display: 'SYNTHETIC LZW', byteSize: 4})}
    }
  };
  const context = vm.createContext(sandbox);
  function runFile(file) { vm.runInContext(fs.readFileSync(file, 'utf8'), context, {filename: file, timeout: 5000}); }
  let codec = null;
  if (options.codec !== false) {
    runFile(codecPath);
    codec = sandbox.window.MCOtxt;
    sandbox.window.MCOtxt = Object.assign({}, codec, {
      encodeFrame: (text, encodeOptions) => {
        calls.push({text, options: JSON.parse(JSON.stringify(encodeOptions))});
        return codec.encodeFrame(text, encodeOptions);
      }
    });
  }
  if (options.adapter !== false) { runFile(adapterPath); }
  vm.runInContext(appSource, context, {filename: path.join(site, 'app.js'), timeout: 10000});
  return {elements, storage, calls, codec, window: sandbox.window,
    run: script => vm.runInContext(script, context, {timeout: 10000})};
}

function plain(value) { return JSON.parse(JSON.stringify(value)); }
let count = 0;
function test(name, action) {
  try { action(); count++; console.log('PASS ' + name); }
  catch (error) { console.error('FAIL ' + name); throw error; }
}

test('site vendors the exact canonical codec and loads scripts before app.js', () => {
  assert.ok(fs.readFileSync(codecPath).equals(fs.readFileSync(path.join(root, 'docs/mcotxt/assets/mcotxt.js'))));
  const scripts = Array.from(html.matchAll(/<script\b[^>]*src="([^"]+)"[^>]*>/g), match => match[1]);
  const codecIndex = scripts.indexOf('assets/mcotxt/mcotxt.js');
  const adapterIndex = scripts.indexOf('assets/mcotxt/mcotxt-comparison.js');
  assert.ok(codecIndex >= 0 && adapterIndex > codecIndex && scripts.indexOf('app.js') > adapterIndex);
  assert.equal(ids.filter(id => id === 'mcotxt-toggle-button').length, 1);
});

test('default Off adds no rows and does not invoke the planner', () => {
  const app = boot();
  assert.equal(app.run('state.settings.mcotxtEnabled'), false);
  assert.equal(app.elements.get('mcotxt-toggle-button').textContent, 'Выключен');
  assert.equal(app.elements.get('mcotxt-toggle-button').attributes.get('aria-pressed'), 'false');
  assert.equal(app.run('buildMCOtxtResultRows("Привет",12,1).length'), 0);
  assert.equal(app.calls.length, 0);
});

test('binary and Base91 rows encode one metadata-free frame, once', () => {
  const app = boot();
  const text = 'Связь через ретранслятор на вершине, всё в порядке.';
  const rows = plain(app.run('state.settings.mcotxtEnabled=true; buildMCOtxtResultRows(' + JSON.stringify(text) + ',' + Buffer.byteLength(text) + ',2)'));
  assert.equal(app.calls.length, 1);
  assert.deepEqual(app.calls[0], {text, options: {languages: ['ru', 'en'], base91: false}});
  const frame = app.codec.encodeFrame(text, {languages: ['ru', 'en'], base91: false});
  assert.equal(frame.ok, true);
  assert.equal(rows.length, 2);
  assert.equal(rows[0].label, 'MCOtxt binary (frame)');
  assert.equal(rows[0].byteSize, frame.data.length);
  assert.equal(rows[0].text, app.codec.toHex(frame.data));
  assert.equal(rows[0].text.length, rows[0].byteSize * 2);
  assert.equal(rows[1].label, 'MCOtxt Base91 (frame)');
  assert.equal(rows[1].text, app.codec.toBase91(frame.data));
  assert.equal(rows[1].byteSize, Buffer.byteLength(rows[1].text, 'utf8'));
  const restored = app.codec.decodeFrame({data: app.codec.fromBase91(rows[1].text)});
  assert.equal(restored.ok, true); assert.equal(restored.text, text);
  const difference = frame.data.length - Buffer.byteLength(text);
  assert.equal(rows[0].diffLabel, difference > 0 ? '+' + difference : String(difference));
  const percent = Math.round(difference / Buffer.byteLength(text) * 100);
  assert.equal(rows[0].percentLabel, (percent > 0 ? '+' : '') + percent + '%');
});

test('button toggles re-render old examples with the correct row span', () => {
  const app = boot();
  app.run('state.dictionaries=[]; state.examples=[{id:"a",text:"first"},{id:"b",text:"second"}]; renderResults();');
  assert.ok(!app.elements.get('results-body').innerHTML.includes('MCOtxt binary'));
  const click = app.elements.get('mcotxt-toggle-button').listeners.get('click');
  assert.equal(typeof click, 'function'); click();
  assert.equal(app.calls.length, 2);
  assert.equal(app.elements.get('mcotxt-toggle-button').textContent, 'Включен');
  assert.equal(app.elements.get('mcotxt-toggle-button').attributes.get('aria-pressed'), 'true');
  let rendered = app.elements.get('results-body').innerHTML;
  assert.equal((rendered.match(/MCOtxt binary \(frame\)/g) || []).length, 2);
  assert.equal((rendered.match(/rowspan="3"/g) || []).length, 2);
  const encodingsBeforeOff = app.calls.length;
  click();
  assert.equal(app.calls.length, encodingsBeforeOff);
  assert.ok(!app.elements.get('results-body').innerHTML.includes('MCOtxt binary'));
  assert.equal(JSON.parse(app.storage.get('compression-demo.settings')).mcotxtEnabled, false);
});

test('persisted MCOtxt coexists with dictionaries, Mesh-compressor and LZW', () => {
  const saved = {
    'compression-demo.examples': JSON.stringify([{id: 'keep', text: 'Мой пример', createdAt: 1}]),
    'compression-demo.dictionaries': JSON.stringify([{id: 'dict', name: 'User', enabled: true, mapping: {'я': 'ya'}, createdAt: 1}]),
    'compression-demo.settings': JSON.stringify({sortDirection: 'asc', byteLimit: '30', meshEnabled: true,
      lzwEnabled: true, mcotxtEnabled: true, customField: 'keep'})
  };
  const app = boot({saved});
  const rendered = app.elements.get('results-body').innerHTML;
  for (const label of ['User', 'Mesh-compressor binary', 'MCOtxt binary (frame)', 'MCOtxt Base91 (frame)', 'LZW-сжатие']) {
    assert.ok(rendered.includes(label), label);
  }
  assert.ok(rendered.includes('rowspan="7"'));
  app.elements.get('mcotxt-toggle-button').listeners.get('click')();
  const settings = JSON.parse(app.storage.get('compression-demo.settings'));
  assert.equal(settings.mcotxtEnabled, false);
  assert.equal(settings.meshEnabled, true); assert.equal(settings.lzwEnabled, true);
  assert.equal(settings.byteLimit, '30'); assert.equal(settings.sortDirection, 'asc');
  assert.equal(settings.customField, 'keep');
  assert.equal(app.storage.get('compression-demo.examples'), saved['compression-demo.examples']);
  assert.equal(app.storage.get('compression-demo.dictionaries'), saved['compression-demo.dictionaries']);
  const restarted = boot({saved: Object.fromEntries(app.storage)});
  assert.equal(restarted.run('state.settings.mcotxtEnabled'), false);
  assert.equal(restarted.run('state.examples[0].text'), 'Мой пример');
});

test('absent codec or adapter shows a neutral error, not a zero-byte saving', () => {
  for (const options of [{codec: false}, {adapter: false}]) {
    const app = boot(options);
    const rows = plain(app.run('state.settings.mcotxtEnabled=true; buildMCOtxtResultRows("hello",5,1)'));
    assert.equal(rows.length, 1);
    assert.ok(rows[0].text.includes('не загружен'));
    assert.equal(rows[0].byteSize, '—'); assert.equal(rows[0].diffLabel, '—');
    assert.equal(rows[0].percentLabel, '—'); assert.equal(rows[0].metricClass, 'metric-neutral');
  }
});

test('oversized input produces an error without breaking the next example', () => {
  const app = boot();
  app.run('state.settings.mcotxtEnabled=true; state.dictionaries=[]; state.examples=[{id:"long",text:"x".repeat(4097)},{id:"ok",text:"hello"}]; renderResults();');
  const rendered = app.elements.get('results-body').innerHTML;
  assert.ok(rendered.includes('resourceLimit'));
  assert.ok(rendered.includes('MCOtxt binary (frame)'));
  const rows = plain(app.run('buildMCOtxtResultRows("x".repeat(4097),4097,1)'));
  assert.equal(rows[0].byteSize, '—'); assert.equal(rows[0].metricClass, 'metric-neutral');
});

test('encoding exceptions are contained and escaped in table output', () => {
  const app = boot();
  app.window.MCOtxt = Object.assign({}, app.codec, {encodeFrame: () => { throw new Error('<script>oops</script>'); }});
  app.run('state.settings.mcotxtEnabled=true; state.dictionaries=[]; state.examples=[{id:"x",text:"hello"}]; renderResults();');
  const rendered = app.elements.get('results-body').innerHTML;
  assert.ok(rendered.includes('&lt;script&gt;oops&lt;/script&gt;'));
  assert.ok(!rendered.includes('<script>'));
  assert.ok(!rendered.includes('metric-good'));
});

test('Unicode normalization and empty input keep original byte accounting', () => {
  const app = boot();
  for (const text of ['', 'Привет😀', 'и\u0306\r\nhello\rworld', '<tag>&quoted']) {
    const rows = plain(app.run('state.settings.mcotxtEnabled=true; buildMCOtxtResultRows(' + JSON.stringify(text) + ',' + Buffer.byteLength(text) + ',1)'));
    assert.equal(rows.length, 2);
    const decoded = app.codec.decodeFrame({data: app.codec.fromHex(rows[0].text)});
    assert.equal(decoded.ok, true); assert.equal(decoded.text, app.codec.normalizeText(text));
    const originalBytes = Buffer.byteLength(text);
    const diff = rows[0].byteSize - originalBytes;
    assert.equal(rows[0].diffLabel, diff > 0 ? '+' + diff : String(diff));
    assert.equal(rows[0].percentLabel.endsWith('%'), true);
  }
});

console.log('All ' + count + ' MCOtxt site integration checks passed. Browser rendering is not covered.');
