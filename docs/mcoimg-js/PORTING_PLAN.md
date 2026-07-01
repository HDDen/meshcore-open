# MCOimg JavaScript v2/v3 porting plan

This document fixes the implementation order and public API before the wire-format work begins.

## Current state

- `mcoimg-codec.global.js` contains the browser-global v1/v2 codec.
- v1 is complete and retained only for compatibility.
- v2 is ported from the final `lib/helpers/mcoimg_codec.dart`: fixed/dynamic
  palettes, all current candidate families, bounds, Regions variants,
  compression gates, deterministic tie-breaks, decoder and metadata paths are
  implemented in `mcoimg-codec.global.js`.
- `mcoimg-browser.global.js` now contains version-neutral browser/canvas/PNG,
  payload-conversion, channel-envelope, cancellation and Worker dispatch helpers.
- `index.html` has v1/v2/v3 selection, Normal/High/Extreme selection, and the
  High/Extreme Worker policy controls.
- `mcoimg-v3-codec.global.js` is an isolated v3 module. The complete decoder,
  inspector, Base91/app-payload helpers, nonce handling, all containers, palette
  descriptors and all 16 block algorithms are ported. Normal/High/Extreme
  encoding is implemented, including the bounded reduced-cost Regions beam,
  exact rerank and deterministic candidate partitions for browser Workers.

## Public-file layout

- `mcoimg-codec.global.js`
  - v1/v2 only
  - global namespace: `window.MCOImg`
  - retained after v1/v2 become legacy
- `mcoimg-v3-codec.global.js`
  - v3 only
  - global namespace: `window.MCOImgV3`
  - owns the v3 encoder, decoder, inspector, metadata, Base91 and binary helpers
- `mcoimg-browser.global.js`
  - version-neutral browser helpers
  - dispatches to `MCOImg` or `MCOImgV3`
  - canvas/PNG/channel packet helpers remain simple entry points
- `mcoimg-v3-worker.global.js`
  - worker entry point for v3 candidate partitions
  - used internally by the browser helper / v3 parallel coordinator
- `index.html`
  - v1/v2/v3 format selector
  - Normal/High/Extreme selector for v2/v3
  - optional High parallelism and automatic Extreme parallelism

## Stable usage contract

The low-level codecs remain explicit:

```js
const v2 = new MCOImg.MCOImageCodec();
const v3 = new MCOImgV3.MCOImageV3Codec();
```

The browser helper provides the version-neutral API:

```js
const result = await MCOImgBrowser.encodeCanvas(canvas, {
  formatVersion: 3,
  compressionLevel: 'extreme',
  output: 'text',       // text | binary | png | image | encoded
  useWorkers: true,
  workerCount: 4,
});
```

Conversion stays symmetric and simple:

```js
MCOImgBrowser.convertPayload(input, {
  input: 'auto',        // auto | text | binary | png
  output: 'text',       // text | binary | png | image | encoded | image
});

MCOImgBrowser.inspectPayload(input, { input: 'auto' });
```

The existing explicit helpers (`textToPngBytes`, `binaryToPngBytes`,
`extractMcoImagePayload`, etc.) remain available for compatibility.

## Worker model

- Normal remains single-threaded by default.
- Extreme uses workers by default when `Worker` is available.
- High remains single-threaded by default but accepts `useWorkers: true`.
- Worker count defaults to `min(navigator.hardwareConcurrency || 2, 8)`.
- The v3 coordinator partitions independent candidate families/backgrounds and
  performs the final deterministic comparison on the main coordinating worker.
- Candidate ordering and tie-break rules must be identical to Dart regardless of
  completion order.
- `useWorkers: false` always provides a deterministic synchronous fallback.

## Implementation steps

### Step 1 — audit and API contract ✅

- inventory current globals, demo controls, conversion helpers and worker wrapper;
- define file split and version-neutral browser API;
- define deterministic worker/tie-break rules.

### Step 2 — demo/API dispatch foundation ✅

- add v3 to the format selector;
- retain compression-level selector for v2/v3;
- add optional High worker control and worker-count control;
- load and dispatch separate v1/v2 and v3 codecs;
- keep existing examples and conversion helpers working.

## Current progress

- Step 1 completed: source/API audit and file split fixed.
- Step 2 completed: v3 selector and isolated namespace, version-neutral browser
  dispatch, conversion/inspection entry points, Worker policy controls, dedicated
  worker entry-point contract, and v1/v2 smoke tests.
- Step 3 completed: final v2 algorithms and descriptors, compact bounds, all
  Regions stream/shared/common/extended variants, bounded region beam search,
  exact candidate ordering, compression-level normalization and deterministic
  round-trip/fixture tests.
- JavaScript fixtures pass exact re-encoding. Dart↔JS fixture generators and
  verifiers are included; they must be executed in the complete Flutter project
  because this partial archive does not contain a Dart runtime or `pubspec.yaml`.
- Step 4 completed: the standalone v3 decoder/metadata path now supports the
  nonce-prefixed body, `0x13` app payload, `im3:`, all dimension modes, all
  8 containers, all 16 block algorithms, fixed/dynamic palettes, Regions
  common/hybrid/shared forms, PNG conversion and strict trailing-bit checks.
- A dependency-free suite contains 39 independently written binary fixtures,
  covering every algorithm/container and every local-palette descriptor.
  Dart↔JS decoder fixture generators/verifiers are included; Dart execution
  still requires the complete Flutter project and its toolchain.
- Step 5 completed: the standalone v3 Normal/High encoder now generates block,
  bounds, solid-background, solid-rect and Regions candidates; supports all 16
  block algorithms, fixed/dynamic/local/shared palettes, common/hybrid headers,
  deterministic fixed-nonce output and final tie-breaks.
- The encoder coverage suite decodes every one of 432 representative candidates
  and reaches all 16 algorithms and all 8 containers. Six checked-in JS winners
  re-encode byte-for-byte. Dart↔JS exact-winner and decoder fixture harnesses are
  included; Dart execution still requires the full Flutter project/toolchain.
- Step 6 completed: the Dart Extreme reduced evaluator, bounded 10×8 deep
  Regions beam, 1536-layout budget, 32-layout exact rerank pool and exact plan
  cache reuse are ported. Stable solid/background/scan partitions are executed
  by `mcoimg-v3-worker.global.js`; the browser coordinator merges winners
  deterministically, supports optional High workers, automatic Extreme workers,
  progress, cancellation/AbortSignal and synchronous fallback.
- Step 7 completed in the standalone archive: real Chromium canvas/PNG/Worker
  integration, channel-envelope coverage, raw v3 metadata consistency,
  migration/release documentation and a one-command Dart↔JavaScript
  orchestrator were added. The actual Dart runtime command remains an external
  acceptance check because this archive has no SDK or root `pubspec.yaml`.

### Step 3 — finish v2 parity ✅

- compare every v2 encoder candidate, bounds/regions variant, palette descriptor,
  compression-level gate, tie-break and decoder path with Dart;
- finish missing paths without changing v1;
- add deterministic v2 round-trip, metadata and cross-runtime fixture harnesses.

### Step 4 — v3 decoder and metadata port ✅

- port v3 bit reader, headers, containers, palette descriptors and all 16 current
  block algorithms;
- support the current one-byte packet nonce;
- implement `decode`, `decodeBytes`, Base91, `inspectPayload`, metadata and PNG
  conversion before enabling v3 encoding in the demo.

### Step 5 — v3 Normal/High encoder port ✅

- port common candidate generation, block/bounds candidates, balanced Normal,
  High regions, shared/common/hybrid plans and exact Dart tie-breaks;
- maintain byte-compatible payloads with Dart.

### Step 6 — v3 Extreme and worker parallelism ✅

- port the Extreme reduced region evaluator, deep beam search, exact rerank
  and Extreme-specific plan caches;
- partition safe independent work across workers;
- support optional workers for High;
- preserve the exact candidate set, ordering and tie-break.

### Step 7 — integration, fixtures and documentation ✅

- v3 is enabled in the demo with real progress, cancellation and Worker policy;
- text/binary/PNG/image conversions were verified in a real Chromium runtime;
- official `0x0120` channel-data, outgoing-command, envelope and raw app-payload
  parsing are covered by deterministic tests;
- Dart↔JavaScript generators/verifiers are wrapped by
  `tests/run-cross-runtime-tests.js` for the complete Flutter repository;
- channel identifiers, body/app-payload distinctions, rollout and
  migration/deprecation boundaries are documented;
- release notes and a dependency-free real-browser runner are included.

## Compatibility rules

- v1/v2 code must not import or depend on the v3 implementation.
- v3 code must not mutate `window.MCOImg`.
- Browser helpers may depend on both globals but must work with only v1/v2 loaded.
- v3 uses its own MeshCore app-data subtype/data-type metadata; raw MCOimg body
  conversion remains separate from the channel envelope helpers.
- No candidate may be removed merely to simplify the JavaScript port.
- Parallel execution may change completion order, never comparison order.
