# MCOimg v4 porting plan

How MCOimg v4 gets its JavaScript port, next to the v3 browser tooling in
`docs/mcoimg-js`, and its C++ port, into the South Edition companion firmware
(`meshcore-luch/MeshCore`), and what has to be in place before either starts.
The v3 ports went the same road; their tooling is reused wherever it fits.

## The reference

- The format is the one at tag `9.5.1-mod-1.9.0` of this repository:
  `lib/helpers/mcoimg_v4_codec.dart`, `lib/helpers/mcoimg_v4_model.dart` and,
  for the normative parts of rendering, `lib/widgets/mco_image_v4_view.dart`.
  Those files have not changed since the tag. Nothing older is a reference,
  the `v4-vector-stable` tag included: it predates the text figure.
- [`mcoimg_v4_reference.md`](mcoimg_v4_reference.md) describes that code and
  was checked against it statement by statement on 2026-09-06. Where the two
  still disagree, the code wins and the document is corrected.
- A text figure carries an MCOtxt v1 stream:
  [`MCOTXT_V1_PROTOCOL.md`](MCOTXT_V1_PROTOCOL.md). The tables are frozen as
  model generation `0` in `tools/MCOtxt/generated/model_manifest.json`
  (`"frozen": true`, seven languages); the C headers sit next to the Dart
  tables in that directory.
- A raster layer carries a v3 body without its packet nonce:
  [`mcoimg_v3_reference.md`](mcoimg_v3_reference.md).
- The format is canonical, so acceptance for a port with an encoder is
  byte-exact: decode a vector, encode the document again, compare with the
  canonical document bytes. A decoder-only port compares its document dump
  with the reference dump instead.
- A port must sort its failures the way the reference does: damaged input is
  one class, an unsupported extension (mode `2` or `3`, a second-escape
  command other than `0`, an MCOtxt stream the port has no tables for) is
  another, because the two earn different placeholders.

## What already exists

JavaScript, `docs/mcoimg-js`:

- `mcoimg-v3-codec.global.js` (`window.MCOImgV3`) holds the v3 decoder and
  encoder, Base91 and the app-payload helpers; `mcoimg-browser.global.js`
  dispatches by version; `mcoimg-v3-worker.global.js` runs encoder partitions.
- `tests/` holds 39 independently written binary fixtures, the Dart↔JS fixture
  generators and `run-cross-runtime-tests.js`, which drives both runtimes.
- There is no MCOtxt in JavaScript yet.

C++, fork directories `src/helpers/mcoimg/` and `src/helpers/mcotxt/`:

- `MCOImgTransport` recognises `im:` / `imN:` text and `0x0120` envelopes and
  reports version `4` as `UnsupportedVersion` today. `MCOImgDecoder::decodeV3`
  decodes a v3 body into a `PixelStore` under `MCOIMG_MAX_PIXELS`;
  `MCOImgRenderer` turns fixed and dynamic palettes into monochrome by
  threshold or Bayer dithering.
- Palette tables are generated from this repository by
  `tools/generate_mcoimg_tables.py`; decoder fixtures by
  `tools/generate_mcoimg_fixtures.py` into a header that
  `tools/mcoimg_fixture_check.cpp` / `run_mcoimg_fixture_check.bat` checks.
- `MCOtxtCodec`, `MCOtxtModels` and `MCOtxtTransport` decode MCOtxt v1 with
  the frozen tables; the recipe for carrying the decoder alone into another
  firmware is in that directory's README. Base91 is `helpers/Base91.*`, the
  UTF-8 helpers `helpers/UTF8Helpers.h`.

## Preliminary steps

In this order. Steps 3 and 4 gate the ports; 5 to 7 can overlap with them.

1. **Fix the format.** Done on 2026-09-06: the reference names the release
   tag as its source, modes `2` and `3` are reserved, the extension points and
   the two failure classes are named.
2. **Make `ELLIPSE_DEPTH` portable.** Done in the reference on 2026-09-06: the
   integer test (`L` an integer, both scaled coordinates divisible by `2L`) is
   the rule a port implements, and the reference's double-precision check with
   its `1e-9` tolerance is shown to accept the same streams within the
   coordinate range. Optional follow-up in Dart: switch the codec to the
   integer test, so the equivalence needs no argument at all.
3. **Dart tests for every command.** `test/helpers/mcoimg_v4_text_test.dart`
   covers the text figure and nothing else. Add, in the same style, tests for
   the header (every dimension mode and its canonicity rejections, background
   override, every profile), the style commands, each base figure, each
   alternate form, each path form with the per-component escape, `DOT_RUN`,
   the four repeat commands with chains and the colour run, nested groups, a
   `mixed` document with a raster layer, the transport tail, and one negative
   test per item of the reference's validation list, each asserting which of
   the two failure classes it lands in. Every positive test also pins the
   exact bytes the reference encoder produces; that is what turns it into a
   vector.
4. **Vectors and the reference dumper.** A `dart run` tool, next to
   `docs/mcoimg-js/tests/generate_v3_dart_fixtures.dart`, that writes a JSON
   fixture set from the documents of step 3 and reads any body back into a
   canonical dump. One fixture is: a name; the canonical document bytes; a
   full body with nonce and, where present, tail; the identity MD5; and either
   the document dump or the expected failure class. The dump is a JSON
   rendering of `MCOImageV4Document` with figures in stream order, colours as
   profile references, and the sticky text state resolved per figure. Its
   shape is defined once, here, and both ports print the same.
5. **Worked examples in the reference.** Bit-level traces for one figure of
   each kind and one whole document, generated by the tool of step 4 so they
   cannot drift from the vectors.
6. **Dependencies per target.** JavaScript needs an MCOtxt v1 decoder and its
   tables: teach `tools/MCOtxt/MCOtxt_model_trainer_with_diagnostics.py` to
   emit a JavaScript table alongside the Dart and C ones, and
   `verify_runtime_models.py` to check it against the manifest. C++ needs a
   nonce-less entry into the v3 decoder for raster layers; prepending a zero
   nonce byte to the layer payload works because the decoder never reads the
   nonce's value, so this may be a one-line wrapper. Both ports write their
   own bit reader and writer with the canonical integer primitives.
7. **Decisions the reference does not make.** Firmware: how vectors are
   rasterised on a monochrome e-ink panel, including the scale from a canvas
   of up to `256x256` to the panel; what stands in for a text figure with no
   font on the node; the limits on document size, figure count and group
   nesting depth without a heap; integer or fixed-point curves for ellipses
   and waves; whether raster layers go through the existing v3 renderer or
   are skipped. Browser: whether the port is decoder and renderer only or
   also encoder and editor; the API contract in the style of
   `docs/mcoimg-js/PORTING_PLAN.md`; whether encoding uses workers.

## JavaScript port

1. `mcoimg-v4-codec.global.js` in `window.MCOImgV4`: bit reader and writer,
   integer primitives, header and dimensions, the command stream with every
   alternate form, repeats and groups, raster layers through `MCOImgV3`,
   the transport tail, `im4:` text over Base91, identity MD5. The decoder
   comes first and is accepted against the vectors before any encoder work.
2. `mcotxt.global.js`: the MCOtxt v1 decoder with the frozen tables, checked
   against the MCOtxt conformance cases; the encoder only if the browser
   editor is in scope.
3. A canvas renderer for `output: 'image' | 'png'`, following the normative
   geometry and drawing text with whatever font the page has.
4. The encoder, if in scope, building the same candidate set as Dart and
   taking the shortest; byte-exact against the vectors.
5. `mcoimg-browser.global.js` dispatch for version `4`, the `index.html`
   selector, `run-cross-runtime-tests.js` gaining the v4 fixtures.

## C++ port

1. `MCOImgV4Decoder` in `src/helpers/mcoimg/` behind a `WITH_MCOIMG_V4` flag,
   normalised in `OptionalFeatureFlags.h` like the other features: parses into
   a bounded figure list with the same validation and the same two failure
   classes, decodes text through `MCOtxtCodec` into the shared scratch, and
   feeds raster layers to `decodeV3` with a zero nonce prepended.
2. `MCOImgTransport` routes version `4` to it instead of reporting
   `UnsupportedVersion`; `ChatLogScreen` gets a v4 content type next to the
   v3 one.
3. A vector rasteriser for the e-ink renderer: lines, rectangles and paths
   from integer segments, ellipses and quadratic curves by subdivision, fills
   by scan line with the non-zero rule, dots as filled circles, and the text
   stand-in decided in step 7 above.
4. Fixtures: `tools/generate_mcoimg_fixtures.py` learns to emit the v4 vectors
   into a second generated header, `tools/mcoimg_fixture_check.cpp` and the
   native gtest environment gain a v4 pass, and the flash and RAM cost is
   measured the way the MCOtxt port was.

## Cross-runtime validation and documentation

- One generator run produces the Dart, JavaScript and C artefacts, tables and
  vectors alike, so nothing can drift between them.
- Every port runs the same vectors: `run-cross-runtime-tests.js` for
  JavaScript, the fixture check and gtest for C++.
- Each port ships its README: the layout and API for `docs/mcoimg-js`, the
  module description in the fork's `src/helpers/mcoimg/README.md`, and the
  reference's "Implementation status" names what each port supports.
