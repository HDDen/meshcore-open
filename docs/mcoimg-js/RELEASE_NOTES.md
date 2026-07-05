# MCOimg JavaScript v3 release candidate — 2026-07-02

This archive contains the completed standalone JavaScript implementation of
MCOimg v3 plus the retained v1/v2 compatibility codec and browser demo.

## Patch fixes after release candidate

- added image paste from the system clipboard to the HTML demo: an `image/*`
  clipboard item replaces the current canvas, resizes it with the active format
  limit, clears undo/redo history and uses the normal unnamed-canvas download
  naming rather than retaining a previously loaded filename;
- downloads after a file import reuse the imported basename with the requested
  output extension, while Clear and clipboard imports restore timestamp-based
  names;
- fixed the v3 decoded-preview adapter in the HTML demo: successful v3 encoding
  no longer passes `encodingVersion: 3` into the legacy v1/v2 `MCOImage`
  wrapper and therefore no longer reports `Unknown encoding version`;
- automatic candidate recalculation in the demo now uses a trailing 2-second
  debounce after canvas/image changes; each new change cancels an active encode
  and restarts the delay;
- the demo now shows the colors actually present on the canvas, including a
  live count, per-color pixel counts in tooltips and a marker for the active
  transparent color;
- transparent-color picking now works for MCOimg v3 as well as v2;
- v3 transparent pixels are rendered as transparent in the editor preview;
- a dedicated real-browser demo UI regression test was added.

## Included

- isolated `MCOImgV3` encoder, decoder, metadata inspector and binary/text
  helpers;
- all 8 v3 containers and all 16 block algorithms;
- Normal, High and Extreme candidate search;
- bounded Extreme reduced evaluator and exact rerank;
- deterministic partitioned Web Workers for Extreme and optional High;
- cancellation, `AbortSignal`, progress and synchronous fallback;
- `im3:` and canonical `0x13 | body` conversions;
- official MeshCore MCO Advanced `data_type = 0x0120` envelope inspection;
- canvas, PNG, text, binary and decoded-image conversion helpers;
- interactive v1/v2/v3 demo;
- dependency-free Node tests and a real Chromium Worker/conversion suite;
- Dart↔JavaScript fixture generators, verifiers and one-command orchestrator.

## JavaScript validation completed in this archive

- 39 independently assembled v3 decoder fixtures;
- all 16 block algorithms;
- all 8 top-level containers;
- 432 representative Normal/High encoder candidates;
- Extreme reduced search and exact rerank;
- deterministic merge under normal, reversed and shuffled completion order;
- real Chromium Web Workers, progress and cancellation;
- text/binary/image/PNG round-trips in Chromium;
- `0x0120` channel-data, outgoing-command, envelope and raw app-payload parsing;
- six exact v3 Normal/High winner fixtures;
- full v1/v2 regression suite with 8,285 decoded candidates and six exact v2
  fixtures.

## Cross-runtime status

The archive contains the current Dart source files and all Dart↔JavaScript
harnesses, but it does not contain a Flutter/Dart SDK or a root `pubspec.yaml`.
Therefore the final Dart runtime execution cannot be performed inside this
standalone archive.

Run this from the complete Flutter repository:

```bash
node docs/mcoimg-js/tests/run-cross-runtime-tests.js
```

The command generates Dart payloads, requires exact JavaScript re-encoding with
the Dart nonce, checks JavaScript decoder fixtures in Dart, and verifies
JavaScript winners in the Dart decoder for both legacy v2 and current v3.

## Browser validation

With Chromium or Chrome available:

```bash
MCOIMG_RUN_BROWSER=1 node docs/mcoimg-js/tests/run-v3-tests.js
```

Or run only the real-browser suite:

```bash
CHROME_BIN=/path/to/chromium node docs/mcoimg-js/tests/run-v3-real-browser.js
```

The browser runner uses only Node built-ins and the Chrome DevTools protocol; it
does not require Playwright, Puppeteer or npm installation.

## Deployment note

Serve the demo and Worker scripts over HTTP(S). Direct `file://` opening can
prevent Worker loading in modern browsers. `useWorkers: false` remains a fully
deterministic fallback.

## Dart canvas editor: binary import reuse

- Loading an MCOimg `.bin` in `lib/screens/canvas_editor_screen.dart` now adopts
  the already encoded payload as the current candidate instead of immediately
  re-running the candidate search.
- For v3, import refreshes only the first one-byte packet nonce; bytes after the
  nonce remain unchanged.
- The imported payload stays cached until pixels or encoding settings actually
  change. Legacy v1/v2 payload bytes are preserved exactly.
- Any `.bin` filename accepted by the file picker is handled as an MCOimg binary,
  not only names ending in `.mcoimg.bin`.

## Dart analyzer cleanup

- Replaced relative imports from `docs/mcoimg-js/tests/*.dart` into `lib/` with
  `package:meshcore_open/...` imports.
- This removes all eight `avoid_relative_lib_imports` diagnostics reported by
  `flutter analyze` for the Dart↔JavaScript fixture tools.

## HTML demo defaults and persistent preferences

- The demo now starts with MCOimg v3 selected by default.
- Selecting High or Extreme compression automatically enables `Use Workers`;
  the checkbox can still be disabled manually afterward.
- Codec version, compression level, palette profile, `Use Workers`, and
  `Show grid` are persisted in `localStorage` and restored after page reload.
- Invalid or unavailable `localStorage` data is ignored safely and falls back
  to the built-in defaults.

### HTML demo file import reliability

- The **Load image/bin** button now uses the standard hidden file-input `click()` path instead of `showPicker()`.
- The selected input value is cleared only after the file has been fully read and applied, so the first selection cannot be invalidated early.
- Raster imports now await a single decode/load pipeline and display an explicit import error instead of silently doing nothing.
- The real-browser UI test covers the very first PNG selection through the file input.
