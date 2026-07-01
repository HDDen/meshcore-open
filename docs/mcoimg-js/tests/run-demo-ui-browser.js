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
        compression.value = '1';
        compression.dispatchEvent(new Event('change', { bubbles: true }));
        const format = document.getElementById('formatVersion');
        format.value = '3';
        format.dispatchEvent(new Event('change', { bubbles: true }));
        await wait(50);

        const initialUsed = document.querySelectorAll('#usedColorsPreview .used-color-swatch').length;
        if (initialUsed < 1) throw new Error('Used-colors list is empty after initialization');

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

        return { usedColors: usedColors.length, transparentColor: selectedValue };
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
      `v3 transparent color=${result.transparentColor})`,
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
