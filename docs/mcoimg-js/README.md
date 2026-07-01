# MCOimg for vanilla JavaScript

This folder contains the browser-global JavaScript implementation and demo for
MCOimg.

## Files

- `mcoimg-codec.global.js` — legacy v1 and v2 codec in `window.MCOImg`.
- `mcoimg-v3-codec.global.js` — isolated v3 namespace in `window.MCOImgV3`.
  It contains the current decoder, Normal/High/Extreme encoder, metadata
  inspector, nonce, Base91/body/app-payload helpers, and deterministic worker
  partition/merge primitives.
- `mcoimg-browser.global.js` — version-neutral canvas, PNG, payload conversion,
  metadata, channel-envelope, cancellation, and Worker dispatch helpers.
- `mcoimg-v3-worker.global.js` — dedicated v3 Worker entry point that executes deterministic candidate partitions.
- `index.html` — interactive demo.
- `PORTING_PLAN.md` — completed implementation order and compatibility rules.
- `MIGRATION_V3.md` — transport identifiers, rollout and deprecation guide.
- `RELEASE_NOTES.md` — release contents, validation and remaining cross-runtime step.
- `SHA256SUMS` — checksums of the five public runtime/demo files.
- `tests/` — deterministic JS round-trip, candidate, metadata and fixture
  tests, plus Dart↔JS fixture generators/verifiers.

Load the globals in this order:

```html
<script src="./mcoimg-codec.global.js"></script>
<script src="./mcoimg-v3-codec.global.js"></script>
<script src="./mcoimg-browser.global.js"></script>
```

`mcoimg-browser.global.js` also works when only the v1/v2 codec is loaded. A v3
operation then reports that the v3 module is unavailable.

## Version-neutral API

The browser helper accepts the format version, compression level, desired output
and Worker settings in one options object:

```js
const text = await MCOImgBrowser.encodeCanvas(sourceCanvas, {
  formatVersion: 3,
  compressionLevel: 'high',
  paletteProfile: MCOImgV3.PaletteProfile.master8,
  transparentColor: null,
  output: 'text', // text | binary | png | image | encoded
  useWorkers: false,
});
```

Payload conversion is symmetric. `convertPayload()` outputs `text`, `binary`, `png`, or `image`; the `encoded` output is available on encoding functions such as `encodeCanvas()` and `encodeImage()`.

```js
const binary = await MCOImgBrowser.convertPayload(text, {
  output: 'binary',
});

const png = await MCOImgBrowser.convertPayload(binary, {
  output: 'png',
});

const image = MCOImgBrowser.decodePayload(text);
const info = MCOImgBrowser.inspectPayload(text);
```

The helper detects `im:` and `im3:` automatically. For ambiguous raw binary,
pass `formatVersion` explicitly; canonical v3 binary starts with the packed app
subtype/version byte `0x13`. A bare nonce-prefixed v3 body is a low-level format;
prefer canonical `0x13 | body` for files and interchange.

The low-level v3 codec can also be loaded and used by itself when canvas/PNG
helpers and legacy decoding are not needed:

```js
const codec = new MCOImgV3.MCOImageV3Codec();
const encoded = codec.encode(image, { compressionLevel: 'high' });
```

## Backward-compatible v1/v2 API

Existing positional helpers and direct `MCOImg.MCOImageCodec` usage remain
available:

```js
const {
  MCOImageCodec,
  PaletteProfile,
  MCOImageEncodingVersion,
} = MCOImg;

const codec = new MCOImageCodec();
const encoded = codec.encode({
  width: 11,
  height: 11,
  paletteProfile: PaletteProfile.master8,
  pixels: new Array(11 * 11).fill(0),
  encodingVersion: MCOImageEncodingVersion.v2,
});

const decoded = codec.decode(encoded.text);
const binary = codec.encodeBytes({
  width: 11,
  height: 11,
  paletteProfile: PaletteProfile.master8,
  pixels: new Array(11 * 11).fill(0),
});
```

The old positional browser helper also remains synchronous for v1/v2:

```js
const text = MCOImgBrowser.encodeCanvas(
  sourceCanvas,
  PaletteProfile.master8,
  null,
  MCOImageRgbaOutputFormat.text,
  { encodingVersion: MCOImageEncodingVersion.v2 },
);
```

## Formats

- **v1 legacy** — fixed palettes, no explicit transparency, up to `85×85`.
- **v2 legacy-compatible** — fixed and dynamic palettes, optional transparent
  color, up to `256×256`. The JavaScript encoder/decoder now includes the final
  Dart v2 candidate families, Regions variants and compression-level gates.
- **v3 current** — separate `im3:` and app-data format. The JS codec supports
  the current nonce-prefixed grammar, all 8 containers, all 16 block algorithms,
  fixed/dynamic palettes, Regions variants, strict metadata inspection and the
  complete Normal/High/Extreme candidate search, bounded Extreme reduced-cost
  beam search, exact rerank, and deterministic multi-worker partitioning.

MCOimg stores palette-indexed pixels. Fixed palettes use profile-local indexes.
Dynamic profiles use their defined global palette values.

## Compression and Workers

Compression values match Dart:

```js
high    = 0
normal  = 1
extreme = 2
```

The demo policy is:

- Normal: main thread;
- High: Workers only when explicitly enabled;
- Extreme: Workers enabled automatically when available;
- canvas/image changes use a trailing 2-second debounce: every subsequent
  change cancels the active encode, invalidates its result and restarts the
  delay. Encoding-option changes remain immediate.

The v1/v2 helper uses one cancellable Worker. MCOimg v3 splits independent
candidate families, backgrounds and scan/background pairs into stable
partitions, distributes them over `workerCount` classic Workers, then merges the
partition winners with the codec's canonical comparator. Completion order does
not affect the payload. `useWorkers: false` is always a synchronous fallback.

The dedicated worker URL is normally derived from the loaded
`mcoimg-v3-codec.global.js` URL. It may be supplied explicitly with
`v3WorkerScriptUrl` when scripts are renamed or served from different paths.

```js
const task = MCOImgBrowser.startCancellableEncode(image, {
  formatVersion: 3,
  compressionLevel: 'extreme',
  workerCount: 4,
  onProgress(progress) {
    console.log(progress.completed, progress.total, progress.percent); // 0..1
  },
});

const encoded = await task.result;
// task.cancel(); // terminates all workers and rejects with AbortError
```

`AbortSignal` is also accepted as `signal`. High uses the same partitioned
coordinator when `useWorkers: true`; Extreme selects it automatically whenever
`Worker` is available.

## Channel transport distinction

Legacy v1/v2 binary channel packets use data type `0xFFF0`.
MCOimg v3 uses the official MCO Advanced app-data type `0x0120`, with packed
subtype/version `0x13` before the nonce-prefixed v3 body. Raw MCOimg conversion
and channel-envelope parsing remain separate helper responsibilities. Parsed v3
results expose both `payload` (`0x13 | body`) and the bare nonce-prefixed `body`.
See `MIGRATION_V3.md` for the complete envelope and rollout guidance.

## Demo

Serve this folder over HTTP(S) before opening `index.html`; browsers commonly
block Worker loading from `file://` pages. For example:

```bash
cd docs/mcoimg-js
python -m http.server 8080
```

Then open `http://127.0.0.1:8080/`. The existing practical editor examples remain, with:

- v1/v2/v3 selection;
- Normal/High/Extreme selection for v2/v3;
- High Worker toggle and worker-count control;
- drawing, undo/redo, movement, crop/expand and resize;
- image and MCOimg binary import;
- PNG and binary export;
- text/binary metadata and hex inspection.

v3 payload import, inspection, image rendering, PNG export and
Normal/High/Extreme encoding are enabled. Extreme automatically uses the
partitioned worker coordinator when supported; the demo displays partition
progress and still falls back to the deterministic synchronous encoder. v1/v2
encoding remains available throughout.

## v1/v2 tests

From `docs/mcoimg-js`:

```bash
node tests/run-v2-tests.js
```

The suite covers:

- v1/v2 browser-dispatch compatibility;
- string and numeric compression-level normalization;
- all generated v2 candidates on fixed, dynamic, grayscale and transparent
  fixtures;
- Regions, bounds and metadata inspection;
- exact re-encoding of the checked-in JS fixtures.

Individual fixture commands:

```bash
node tests/generate-v2-js-fixtures.js
node tests/verify-v2-fixtures.js
```

### Dart↔JavaScript fixtures

The repository also contains runtime-neutral fixture data and two Dart harnesses:

```bash
# In the complete Flutter project, where Dart/Flutter and pubspec.yaml exist:
dart run docs/mcoimg-js/tests/generate_v2_dart_fixtures.dart

# Verify Dart-generated payloads in JavaScript:
node docs/mcoimg-js/tests/verify-v2-fixtures.js \
  docs/mcoimg-js/tests/v2-dart-fixtures.json

# Generate JavaScript payloads and verify them in Dart:
node docs/mcoimg-js/tests/generate-v2-js-fixtures.js
dart run docs/mcoimg-js/tests/verify_v2_js_fixtures.dart
```

The JavaScript suite is dependency-free. The Dart harnesses import the actual
`lib/helpers/mcoimg_codec.dart`, so they should be run from the complete Flutter
repository rather than from a partial source archive.


## v3 encoder/decoder tests

From the repository root:

```bash
node docs/mcoimg-js/tests/run-v3-tests.js
```

The dependency-free suite checks both independently assembled decoder fixtures
and generated encoder candidates. It covers:

- 39 manual wire fixtures spanning all 16 v3 block algorithms and all 8
  top-level containers;
- every candidate from representative Normal/High images, currently 432
  candidate round-trips in the coverage suite;
- bounded Extreme reduced-cost beam search, exact rerank, and the Dart limits
  (1536 pixels, 20 components/regions, 10×8 beam, 1536 evaluations, 32-layout
  exact pool);
- exact equality between synchronous and partitioned High/Extreme winners under
  normal, reversed and shuffled completion order;
- dedicated-worker message protocol, browser coordinator progress,
  cancellation, and synchronous fallback;
- official `0x0120` channel-data, outgoing-command, envelope and raw app-payload
  parsing, including UTF-8 sender names;
- horizontal, vertical and both snake scan orders;
- raw, RLE, short-RLE, constant and sparse adaptive bitplanes;
- flat, bitmap, sorted-delta, range-run and both Dynamic Global 512 banked
  local-palette descriptors;
- bounds, solid rectangles, Regions, shared/common/hybrid plans, transparency
  and Dynamic Global profiles;
- fixed-nonce deterministic encoding and nonce-only refresh;
- `body ↔ 0x13 app payload ↔ im3:` conversions, metadata, browser dispatch and
  PNG conversion;
- exact re-encoding of six checked-in JavaScript Normal/High fixtures.

The fixture generator/verifier runs each heavyweight High fixture in a fresh
Node process. This keeps validation deterministic across Node/V8 versions while
the public codec itself remains a normal synchronous API.

The checked-in manual wire fixtures can also be decoded by the Dart codec:

```bash
# Rebuild the deterministic JavaScript fixture file:
node docs/mcoimg-js/tests/v3-decoder-fixtures.js \
  --write=docs/mcoimg-js/tests/v3-js-decoder-fixtures.json

# In the complete Flutter project:
dart run docs/mcoimg-js/tests/verify_v3_js_decoder_fixtures.dart
```

To generate payloads with the current Dart v3 encoder and verify them in JS:

```bash
# In the complete Flutter project:
dart run docs/mcoimg-js/tests/generate_v3_dart_fixtures.dart

node docs/mcoimg-js/tests/verify-v3-dart-fixtures.js \
  docs/mcoimg-js/tests/v3-dart-fixtures.json
```

To rebuild and verify the checked-in JavaScript encoder fixtures:

```bash
node docs/mcoimg-js/tests/generate-v3-js-encoder-fixtures.js
node docs/mcoimg-js/tests/verify-v3-js-encoder-fixtures.js

# In the complete Flutter project, verify that Dart decodes every JS winner:
dart run docs/mcoimg-js/tests/verify_v3_js_encoder_fixtures.dart
```

`verify-v3-dart-fixtures.js` now performs two checks by default: it decodes the
Dart payloads and re-encodes the same images in JavaScript with the Dart nonce,
requiring an exact body match. Pass `--decode-only` after the fixture path when
only decoder interoperability is needed.

## Real-browser integration test

The Node unit suite uses deterministic Worker protocol tests. A separate suite
launches an installed Chromium/Chrome through the DevTools protocol and checks
actual browser Workers, canvas, PNG import/export, channel parsing, progress and
cancellation:

```bash
CHROME_BIN=/path/to/chromium node docs/mcoimg-js/tests/run-v3-real-browser.js
```

To run only the interactive demo UI regression (used-colors list, the v3
transparent-color picker and the restarted 2-second canvas debounce):

```bash
CHROME_BIN=/path/to/chromium node docs/mcoimg-js/tests/run-demo-ui-browser.js
```

Both runners use Node built-ins only; Playwright, Puppeteer and npm packages are
not required. To include the full browser test after the normal v3 suite:

```bash
MCOIMG_RUN_BROWSER=1 node docs/mcoimg-js/tests/run-v3-tests.js
```

## One-command Dart↔JavaScript verification

From the complete Flutter repository, with `pubspec.yaml` and Dart available:

```bash
node docs/mcoimg-js/tests/run-cross-runtime-tests.js
```

Optional scopes:

```bash
node docs/mcoimg-js/tests/run-cross-runtime-tests.js --v3-only
node docs/mcoimg-js/tests/run-cross-runtime-tests.js --v2-only
```

The orchestrator generates Dart payloads, requires exact JavaScript re-encoding
with the Dart nonce, checks JavaScript decoder fixtures in Dart, and verifies
JavaScript winners with the Dart decoder.

