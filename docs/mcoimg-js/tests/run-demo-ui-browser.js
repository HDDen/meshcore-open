'use strict';

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawn, spawnSync } = require('node:child_process');

const root = path.resolve(__dirname, '..');

function findBrowser() {
  const candidates = [
    process.env.CHROME_BIN,
    process.env.CHROMIUM_BIN,
    'chromium',
    'chromium-browser',
    'google-chrome',
    'google-chrome-stable',
  ].filter(Boolean);
  for (const candidate of candidates) {
    const result = spawnSync(candidate, ['--version'], { encoding: 'utf8' });
    if (!result.error && result.status === 0) return candidate;
  }
  return null;
}

function delay(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function fetchJson(url, timeoutMs = 1000) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(url, { signal: controller.signal });
    if (!response.ok) throw new Error(`${response.status} ${response.statusText}`);
    return await response.json();
  } finally {
    clearTimeout(timer);
  }
}

async function waitForPageTarget(debugPort, timeoutMs = 15000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const targets = await fetchJson(`http://127.0.0.1:${debugPort}/json/list`);
      const target = targets.find((item) => item.type === 'page' && item.webSocketDebuggerUrl);
      if (target) return target;
    } catch (_) {
      // Retry while Chromium starts.
    }
    await delay(100);
  }
  throw new Error('Chromium DevTools endpoint did not become ready');
}

class CdpConnection {
  constructor(url) {
    this.socket = new WebSocket(url);
    this.nextId = 1;
    this.pending = new Map();
    this.events = [];
  }

  async open() {
    await new Promise((resolve, reject) => {
      this.socket.addEventListener('open', resolve, { once: true });
      this.socket.addEventListener('error', reject, { once: true });
    });
    this.socket.addEventListener('message', (event) => {
      const message = JSON.parse(String(event.data));
      if (message.id != null) {
        const pending = this.pending.get(message.id);
        if (!pending) return;
        this.pending.delete(message.id);
        if (message.error) pending.reject(new Error(message.error.message));
        else pending.resolve(message.result || {});
        return;
      }
      if (message.method === 'Runtime.exceptionThrown' || message.method === 'Log.entryAdded') {
        this.events.push(message);
      }
    });
  }

  send(method, params = {}) {
    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      this.socket.send(JSON.stringify({ id, method, params }));
    });
  }

  close() {
    this.socket.close();
  }
}

async function run(browser) {
  const debugPort = 20000 + Math.floor(Math.random() * 1000);
  const userDataDirectory = fs.mkdtempSync(path.join(os.tmpdir(), 'mcoimg-demo-chromium-'));
  const detachedBrowser = process.platform !== 'win32';
  const chromium = spawn(browser, [
    '--headless=new',
    '--no-sandbox',
    '--disable-gpu',
    '--no-proxy-server',
    `--remote-debugging-port=${debugPort}`,
    `--user-data-dir=${userDataDirectory}`,
    'about:blank',
  ], {
    stdio: ['ignore', 'ignore', 'pipe'],
    detached: detachedBrowser,
  });

  let cdp = null;
  let stderr = '';
  chromium.stderr.setEncoding('utf8');
  chromium.stderr.on('data', (chunk) => { stderr += chunk; });

  try {
    const target = await waitForPageTarget(debugPort);
    cdp = new CdpConnection(target.webSocketDebuggerUrl);
    await cdp.open();
    await cdp.send('Page.enable');
    await cdp.send('Runtime.enable');
    await cdp.send('Log.enable');
    let demoHtml = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
    const localStorageShim = `<script>
      (() => {
        const store = new Map();
        const storage = {
          getItem(key) { return store.has(key) ? store.get(key) : null; },
          setItem(key, value) { store.set(key, String(value)); },
          removeItem(key) { store.delete(key); },
          clear() { store.clear(); },
        };
        try {
          Object.defineProperty(window, 'localStorage', {
            configurable: true,
            value: storage,
          });
        } catch (_) {
          window.localStorage = storage;
        }
      })();
    <\/script>`;
    demoHtml = demoHtml.replace('</head>', localStorageShim + '</head>');
    for (const scriptName of [
      'mcoimg-codec.global.js',
      'mcoimg-v3-codec.global.js',
      'mcoimg-browser.global.js',
    ]) {
      const source = fs.readFileSync(path.join(root, scriptName), 'utf8');
      demoHtml = demoHtml.replace(
        `<script src="./${scriptName}"></script>`,
        `<script>\n${source}\n</script>`,
      );
    }
    const frameTree = await cdp.send('Page.getFrameTree');
    await cdp.send('Page.setDocumentContent', {
      frameId: frameTree.frameTree.frame.id,
      html: demoHtml,
    });
    await delay(300);

    const evaluation = await cdp.send('Runtime.evaluate', {
      expression: `(async () => {
        const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
        const deadline = Date.now() + 15000;
        while (Date.now() < deadline && !document.querySelector('#palettePreview .swatch')) {
          await wait(50);
        }
        if (!document.querySelector('#palettePreview .swatch')) {
          throw new Error('Demo palette did not initialize: url=' + location.href + ', ready=' + document.readyState + ', title=' + document.title + ', scripts=' + Array.from(document.scripts).map((x) => x.src || 'inline').join('|') + ', body=' + document.body.innerText.slice(0, 200));
        }

        const compression = document.getElementById('compressionLevel');
        const format = document.getElementById('formatVersion');
        const workers = document.getElementById('useWorkers');
        const grid = document.getElementById('showGrid');
        const palette = document.getElementById('palette');
        if (format.value !== '3') throw new Error('Default codec version is not v3: ' + format.value);
        if (compression.value !== '0') throw new Error('Default compression is not High: ' + compression.value);
        if (!workers.checked) throw new Error('Workers are not enabled by default for High');

        compression.value = '1';
        compression.dispatchEvent(new Event('change', { bubbles: true }));
        compression.value = '0';
        compression.dispatchEvent(new Event('change', { bubbles: true }));
        if (!workers.checked) throw new Error('Switching to High did not enable Workers');
        workers.click();
        compression.value = '2';
        compression.dispatchEvent(new Event('change', { bubbles: true }));
        if (!workers.checked) throw new Error('Switching to Extreme did not enable Workers');
        workers.click();
        format.value = '2';
        format.dispatchEvent(new Event('change', { bubbles: true }));
        if (grid.checked) grid.click();
        const persistedPalette = palette.options.length > 1 ? palette.options[1].value : palette.value;
        palette.value = persistedPalette;
        palette.dispatchEvent(new Event('change', { bubbles: true }));
        const stored = JSON.parse(localStorage.getItem('mcoimg-demo-preferences-v1'));
        if (
          stored.encodingVersion !== 2 ||
          stored.compressionLevel !== 2 ||
          stored.paletteProfile !== Number(persistedPalette) ||
          stored.useWorkers !== false ||
          stored.showGrid !== false
        ) {
          throw new Error('Demo preferences were not written to localStorage correctly: ' + JSON.stringify(stored));
        }
        state.encodingVersion = 3;
        state.compressionLevel = MCOImageCompressionLevel.high;
        state.paletteProfile = PaletteProfile.master8;
        state.useWorkers = true;
        state.showGrid = true;
        applyStoredDemoPreferences();
        if (
          state.encodingVersion !== 2 ||
          state.compressionLevel !== MCOImageCompressionLevel.extreme ||
          state.paletteProfile !== Number(persistedPalette) ||
          state.useWorkers !== false ||
          state.showGrid !== false
        ) {
          throw new Error('Demo preferences were not restored from localStorage correctly');
        }

        compression.value = '1';
        compression.dispatchEvent(new Event('change', { bubbles: true }));
        format.value = '3';
        format.dispatchEvent(new Event('change', { bubbles: true }));
        await wait(50);

        const initialUsed = document.querySelectorAll('#usedColorsPreview .used-color-swatch').length;
        if (initialUsed < 1) throw new Error('Used-colors list is empty after initialization');

        const importedCanvas = document.createElement('canvas');
        importedCanvas.width = 11;
        importedCanvas.height = 7;
        const importedCanvasContext = importedCanvas.getContext('2d');
        importedCanvasContext.fillStyle = '#ff0000';
        importedCanvasContext.fillRect(0, 0, importedCanvas.width, importedCanvas.height);
        const importedBlob = await new Promise((resolve, reject) => {
          importedCanvas.toBlob((blob) => {
            if (blob) resolve(blob);
            else reject(new Error('First file-picker test canvas could not be converted to PNG'));
          }, 'image/png');
        });
        const fileInput = document.getElementById('imageFile');
        const selectedFiles = new DataTransfer();
        selectedFiles.items.add(new File([importedBlob], 'foo.png', { type: 'image/png' }));
        fileInput.files = selectedFiles.files;
        fileInput.dispatchEvent(new Event('change', { bubbles: true }));
        const firstImportDeadline = Date.now() + 5000;
        while (state.importingImage && Date.now() < firstImportDeadline) {
          await wait(25);
        }
        if (state.importingImage) {
          throw new Error('First PNG file selection did not finish importing');
        }
        if (state.width !== 11 || state.height !== 7) {
          throw new Error(
            'First PNG file selection did not replace/resize the canvas: ' +
            state.width + 'x' + state.height,
          );
        }
        const importedPngName = suggestedDownloadName('png');
        const importedBinName = suggestedDownloadName('binary');
        if (importedPngName !== 'foo.png' || importedBinName !== 'foo.mcoimg.bin') {
          throw new Error(
            'Imported source filename was not reused for downloads: ' +
            importedPngName + ' / ' + importedBinName,
          );
        }
        const clipboardCanvas = document.createElement('canvas');
        clipboardCanvas.width = 300;
        clipboardCanvas.height = 12;
        const clipboardContext = clipboardCanvas.getContext('2d');
        clipboardContext.fillStyle = '#0000ff';
        clipboardContext.fillRect(0, 0, clipboardCanvas.width, clipboardCanvas.height);
        const clipboardBlob = await new Promise((resolve, reject) => {
          clipboardCanvas.toBlob((blob) => {
            if (blob) resolve(blob);
            else reject(new Error('Clipboard test canvas could not be converted to PNG'));
          }, 'image/png');
        });
        const pasteEvent = new Event('paste', { bubbles: true, cancelable: true });
        Object.defineProperty(pasteEvent, 'clipboardData', {
          value: {
            items: [{
              type: 'image/png',
              getAsFile: () => new File([clipboardBlob], 'clipboard.png', { type: 'image/png' }),
            }],
            files: [],
          },
        });
        document.dispatchEvent(pasteEvent);
        const pasteDeadline = Date.now() + 5000;
        while (state.importingImage && Date.now() < pasteDeadline) {
          await wait(25);
        }
        if (state.importingImage) {
          throw new Error('Clipboard image import did not finish');
        }
        if (!pasteEvent.defaultPrevented) {
          throw new Error('Clipboard image paste did not prevent the browser default');
        }
        if (state.width !== 256 || state.height !== 12) {
          throw new Error(
            'Clipboard image did not resize/clamp the canvas: ' +
            state.width + 'x' + state.height,
          );
        }
        const pastedBinName = suggestedDownloadName('binary');
        if (!/^mcoimg-canvas-.*\.mcoimg\.bin$/.test(pastedBinName)) {
          throw new Error(
            'Clipboard image incorrectly retained the loaded source filename: ' + pastedBinName,
          );
        }

        document.getElementById('clear').click();
        await wait(50);
        const clearedBinName = suggestedDownloadName('binary');
        if (!/^mcoimg-canvas-.*\.mcoimg\.bin$/.test(clearedBinName)) {
          throw new Error('Clear canvas did not restore default binary naming: ' + clearedBinName);
        }

        document.getElementById('sample').click();
        await wait(50);
        const usedColors = Array.from(document.querySelectorAll('#usedColorsPreview .used-color-swatch'));
        if (usedColors.length < 2) {
          throw new Error('Used-colors list did not update after drawing the sample');
        }
        const label = document.getElementById('usedColorsLabel').textContent;
        if (label !== 'Used colors (' + usedColors.length + ')') {
          throw new Error('Unexpected used-colors label: ' + label);
        }

        document.getElementById('alphaSwatch').click();
        if (document.getElementById('alphaSwatch').getAttribute('aria-pressed') !== 'true') {
          throw new Error('Transparent-color picker did not enter picking mode');
        }
        const paletteSwatch = document.querySelector('#palettePreview .swatch');
        const selectedValue = paletteSwatch.dataset.colorValue;
        paletteSwatch.click();
        await wait(50);
        const alphaStatus = document.getElementById('alphaStatus').textContent;
        const alphaPressed = document.getElementById('alphaSwatch').getAttribute('aria-pressed');
        if (alphaPressed !== 'false' || alphaStatus !== 'color ' + selectedValue) {
          throw new Error(
            'Transparent-color selection failed in v3: pressed=' + alphaPressed +
            ', status=' + alphaStatus,
          );
        }

        // A settings change is immediate and also clears the pending alpha encode,
        // giving the debounce check a clean starting point.
        compression.value = '1';
        compression.dispatchEvent(new Event('change', { bubbles: true }));
        await wait(250);

        const metaEvents = [];
        const metaObserver = new MutationObserver(() => {
          metaEvents.push({
            time: performance.now(),
            text: document.getElementById('encodedMeta').textContent,
          });
        });
        metaObserver.observe(document.getElementById('encodedMeta'), {
          childList: true,
          characterData: true,
          subtree: true,
        });

        document.getElementById('sample').click();
        await wait(1050);
        document.getElementById('clear').click();
        const lastCanvasChangeAt = performance.now();

        await wait(1150);
        const earlyEncode = metaEvents.find((event) =>
          event.time >= lastCanvasChangeAt && event.text.startsWith('Encoding…')
        );
        if (earlyEncode) {
          throw new Error('Canvas encoding started before the restarted 2-second debounce elapsed');
        }

        const debounceDeadline = Date.now() + 3000;
        let encodeStart = null;
        while (!encodeStart && Date.now() < debounceDeadline) {
          encodeStart = metaEvents.find((event) =>
            event.time >= lastCanvasChangeAt && event.text.startsWith('Encoding…')
          );
          if (!encodeStart) await wait(25);
        }
        if (!encodeStart) {
          metaObserver.disconnect();
          throw new Error('Encoding did not start after the restarted canvas debounce');
        }
        const debounceDelay = encodeStart.time - lastCanvasChangeAt;
        if (debounceDelay < 1900 || debounceDelay > 3000) {
          metaObserver.disconnect();
          throw new Error('Unexpected canvas debounce delay: ' + debounceDelay.toFixed(1) + ' ms');
        }

        const completionDeadline = Date.now() + 15000;
        let finalMeta = document.getElementById('encodedMeta').textContent;
        while (Date.now() < completionDeadline && finalMeta.startsWith('Encoding')) {
          await wait(25);
          finalMeta = document.getElementById('encodedMeta').textContent;
        }
        metaObserver.disconnect();
        if (finalMeta.startsWith('Encoding')) {
          throw new Error('Debounced v3 encoding did not finish');
        }
        if (finalMeta.includes('Unknown encoding version')) {
          throw new Error('v3 preview rendering leaked into the legacy MCOImage wrapper');
        }
        if (!/^[0-9]+ chars, [0-9]+ bytes, v3 /.test(finalMeta)) {
          throw new Error('Unexpected final v3 encoding status: ' + finalMeta);
        }
        const decodedCanvas = document.getElementById('decoded');
        if (decodedCanvas.width <= 0 || decodedCanvas.height <= 0) {
          throw new Error('Decoded v3 preview canvas was not rendered');
        }

        document.getElementById('decode').click();
        await wait(50);
        const decodeMeta = document.getElementById('encodedMeta').textContent;
        if (decodeMeta.includes('Unknown encoding version')) {
          throw new Error('Textarea v3 decode preview leaked into the legacy MCOImage wrapper');
        }

        const originalStartCancellableEncode = browserCodec.startCancellableEncode.bind(browserCodec);
        let additionalEncodeCalls = 0;
        browserCodec.startCancellableEncode = (...args) => {
          additionalEncodeCalls += 1;
          return originalStartCancellableEncode(...args);
        };
        const originalDownloadBytes = browserCodec.downloadBytes.bind(browserCodec);
        let savedBinary = null;
        browserCodec.downloadBytes = (bytes, name, mimeType) => {
          savedBinary = {
            name,
            mimeType,
            size: bytes?.length ?? bytes?.byteLength ?? 0,
          };
        };
        await saveBinary();
        const saveDeadline = Date.now() + 2000;
        while (!savedBinary && Date.now() < saveDeadline) {
          await wait(25);
        }
        browserCodec.startCancellableEncode = originalStartCancellableEncode;
        browserCodec.downloadBytes = originalDownloadBytes;
        if (additionalEncodeCalls !== 0) {
          throw new Error('Save binary started a new encode instead of reusing the finished result');
        }
        return {
          usedColors: usedColors.length,
          transparentColor: selectedValue,
          firstFileImport: '11x7',
          pastedCanvasSize: state.width + 'x' + state.height,
          debounceDelay: Math.round(debounceDelay),
          finalMeta,
          savedBinaryName: savedBinary ? savedBinary.name : '(captured download unavailable in test runtime)',
        };
      })()`,
      awaitPromise: true,
      returnByValue: true,
    });

    if (evaluation.exceptionDetails) {
      throw new Error(
        evaluation.exceptionDetails.exception?.description ||
        evaluation.exceptionDetails.text ||
        'Demo UI test failed',
      );
    }
    const result = evaluation.result && evaluation.result.value;
    console.log(
      `MCOimg demo UI: PASS (used colors=${result.usedColors}, ` +
      `v3 transparent color=${result.transparentColor}, ` +
      `first file=${result.firstFileImport}, ` +
      `clipboard paste=${result.pastedCanvasSize}, ` +
      `canvas debounce=${result.debounceDelay}ms, preview status=${result.finalMeta}, saveBinary=${result.savedBinaryName})`,
    );
  } catch (error) {
    const events = cdp && cdp.events.length ? `\nDevTools events:\n${JSON.stringify(cdp.events, null, 2)}` : '';
    const browserError = stderr.trim() ? `\nChromium stderr:\n${stderr}` : '';
    throw new Error(`${error.message}${events}${browserError}`);
  } finally {
    if (cdp) cdp.close();
    const killBrowser = (signal) => {
      try {
        if (detachedBrowser && chromium.pid) process.kill(-chromium.pid, signal);
        else chromium.kill(signal);
      } catch (_) {
        // Already exited.
      }
    };
    killBrowser('SIGTERM');
    await Promise.race([new Promise((resolve) => chromium.once('exit', resolve)), delay(2000)]);
    if (chromium.exitCode == null && chromium.signalCode == null) killBrowser('SIGKILL');
    try {
      fs.rmSync(userDataDirectory, { recursive: true, force: true, maxRetries: 5, retryDelay: 100 });
    } catch (_) {
      // Temporary Chromium helpers may keep the directory briefly.
    }
  }
}

async function main() {
  const browser = findBrowser();
  if (!browser) throw new Error('Chromium/Chrome was not found. Set CHROME_BIN.');
  await run(browser);
}

main().catch((error) => {
  console.error(error && error.stack ? error.stack : error);
  process.exitCode = 1;
});
