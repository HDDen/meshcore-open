'use strict';

const fs = require('node:fs');
const http = require('node:http');
const os = require('node:os');
const path = require('node:path');
const { spawn, spawnSync } = require('node:child_process');

const root = path.resolve(__dirname, '..');

function mimeType(filePath) {
  switch (path.extname(filePath).toLowerCase()) {
    case '.html': return 'text/html; charset=utf-8';
    case '.js': return 'text/javascript; charset=utf-8';
    case '.json': return 'application/json; charset=utf-8';
    case '.png': return 'image/png';
    default: return 'application/octet-stream';
  }
}

function startServer(port) {
  const server = http.createServer((request, response) => {
    const rawPath = decodeURIComponent(new URL(request.url, 'http://127.0.0.1').pathname);
    const relative = rawPath === '/' ? 'tests/v3-real-browser.html' : rawPath.replace(/^\/+/, '');
    const filePath = path.resolve(root, relative);
    if (filePath !== root && !filePath.startsWith(`${root}${path.sep}`)) {
      response.writeHead(403).end('Forbidden');
      return;
    }
    fs.readFile(filePath, (error, contents) => {
      if (error) {
        response.writeHead(error.code === 'ENOENT' ? 404 : 500).end(error.message);
        return;
      }
      response.writeHead(200, {
        'Content-Type': mimeType(filePath),
        'Cache-Control': 'no-store',
      });
      response.end(contents);
    });
  });
  server.listen(port, '127.0.0.1');
  const stop = () => server.close(() => process.exit(0));
  process.on('SIGTERM', stop);
  process.on('SIGINT', stop);
}

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
  let lastError = null;
  while (Date.now() < deadline) {
    try {
      const targets = await fetchJson(`http://127.0.0.1:${debugPort}/json/list`);
      const target = targets.find((item) => item.type === 'page' && item.webSocketDebuggerUrl);
      if (target) return target;
    } catch (error) {
      lastError = error;
    }
    await delay(100);
  }
  throw new Error(`Chromium DevTools endpoint did not become ready: ${lastError || 'timeout'}`);
}

class CdpConnection {
  constructor(url) {
    if (typeof WebSocket !== 'function') {
      throw new Error('This test requires a Node.js runtime with global WebSocket support');
    }
    this.socket = new WebSocket(url);
    this.nextId = 1;
    this.pending = new Map();
    this.events = [];
  }

  async open() {
    if (this.socket.readyState === WebSocket.OPEN) return;
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
      if (message.method === 'Runtime.exceptionThrown' ||
          message.method === 'Log.entryAdded') {
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

async function runBrowserTest(browser) {
  const webPort = 18000 + Math.floor(Math.random() * 1000);
  const debugPort = 20000 + Math.floor(Math.random() * 1000);
  const userDataDirectory = fs.mkdtempSync(path.join(os.tmpdir(), 'mcoimg-chromium-'));
  const server = spawn(process.execPath, [__filename, '--serve', String(webPort)], {
    stdio: ['ignore', 'ignore', 'inherit'],
  });
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
  let browserStderr = '';
  chromium.stderr.setEncoding('utf8');
  chromium.stderr.on('data', (chunk) => { browserStderr += chunk; });

  let cdp = null;
  try {
    const target = await waitForPageTarget(debugPort);
    cdp = new CdpConnection(target.webSocketDebuggerUrl);
    await cdp.open();
    await cdp.send('Page.enable');
    await cdp.send('Runtime.enable');
    await cdp.send('Log.enable');
    const url = `http://127.0.0.1:${webPort}/tests/v3-real-browser.html`;
    await cdp.send('Page.navigate', { url });

    const deadline = Date.now() + 120000;
    while (Date.now() < deadline) {
      const evaluation = await cdp.send('Runtime.evaluate', {
        expression: `(() => {
          const node = document.getElementById('result');
          return node ? { status: node.dataset.status, text: node.textContent } : null;
        })()`,
        returnByValue: true,
      });
      const value = evaluation.result && evaluation.result.value;
      if (value && value.status === 'pass') {
        console.log(String(value.text || '').trim());
        return;
      }
      if (value && value.status === 'fail') {
        throw new Error(String(value.text || 'Real-browser test failed'));
      }
      await delay(200);
    }
    throw new Error('Real-browser test did not finish within 120 seconds');
  } catch (error) {
    const eventSummary = cdp && cdp.events.length
      ? `\nDevTools events:\n${JSON.stringify(cdp.events, null, 2)}`
      : '';
    const stderrSummary = browserStderr.trim() ? `\nChromium stderr:\n${browserStderr}` : '';
    throw new Error(`${error.message}${eventSummary}${stderrSummary}`);
  } finally {
    if (cdp) cdp.close();
    const killBrowser = (signal) => {
      try {
        if (detachedBrowser && chromium.pid) process.kill(-chromium.pid, signal);
        else chromium.kill(signal);
      } catch (_) {
        // The browser process group may already have exited.
      }
    };
    killBrowser('SIGTERM');
    server.kill('SIGTERM');
    await Promise.race([
      new Promise((resolve) => chromium.once('exit', resolve)),
      delay(2000),
    ]);
    if (chromium.exitCode == null && chromium.signalCode == null) {
      killBrowser('SIGKILL');
      await Promise.race([
        new Promise((resolve) => chromium.once('exit', resolve)),
        delay(1000),
      ]);
    }
    await delay(250);
    try {
      fs.rmSync(userDataDirectory, {
        recursive: true,
        force: true,
        maxRetries: 10,
        retryDelay: 100,
      });
    } catch (error) {
      // Some Chromium builds keep profile helper processes alive briefly after
      // the main process exits. A leftover temporary profile must not turn a
      // successful codec test into a failure.
      console.warn(`Could not remove temporary Chromium profile: ${error.message}`);
    }
  }
}

async function main() {
  const browser = findBrowser();
  if (!browser) {
    throw new Error(
      'Chromium/Chrome was not found. Set CHROME_BIN to run the real-browser suite.',
    );
  }
  await runBrowserTest(browser);
}

if (process.argv[2] === '--serve') {
  startServer(Number(process.argv[3]));
} else {
  main().catch((error) => {
    console.error(error && error.stack ? error.stack : error);
    process.exitCode = 1;
  });
}
