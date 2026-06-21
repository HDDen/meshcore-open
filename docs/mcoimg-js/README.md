# MCO Image Codec for Vanilla JS

This folder contains a dependency-free vanilla JS port of the Flutter
`MCOImageCodec`.

- `mcoimg-codec.global.js` is the browser-global build for plain `<script>` usage.
- `index.html` is a browser demo with drawing tools, image import, PNG export,
  encoding, decoding, and rendering.
- The JS port is intended to stay byte-compatible with the Dart/Flutter codec
  for both legacy v1 payloads and the current v2 payloads.

## Usage

```html
<script src="./mcoimg-codec.global.js"></script>
<script>
const {
  MCOImageCodec,
  PaletteProfile,
  MCOImageEncodingVersion,
  drawMCOImage,
} = window.MCOImg;

const codec = new MCOImageCodec();

const encoded = codec.encode({
  width: 11,
  height: 11,
  paletteProfile: PaletteProfile.master8,
  pixels: new Array(11 * 11).fill(0), // fixed palettes use profile-local indexes
  encodingVersion: MCOImageEncodingVersion.v2,
});

console.log(encoded.text); // im:...

const decoded = codec.decode(encoded.text);
drawMCOImage(document.querySelector('canvas'), decoded, { scale: 12 });

// Binary transport selects the best candidate by byteLength, not Base91 size.
const binary = codec.encodeBytes({
  width: 11,
  height: 11,
  paletteProfile: PaletteProfile.master8,
  pixels: new Array(11 * 11).fill(0),
});
</script>
```

The payload always stores palette-indexed pixels, not arbitrary RGB pixels.
For fixed palettes such as `PaletteProfile.master8`, each pixel is a profile-local
index from `0` to `7`.

For dynamic palettes such as `PaletteProfile.dynamicGlobal512`, pixels are global
dynamic-palette indexes. The codec writes only the local palette needed by the
image, so the same dynamic profile can encode small images with far fewer than
512 transmitted colors.

## Format versions

The codec supports two public format families:

- **v1 legacy**: fixed palettes only, no explicit transparency, up to `85×85`.
  It is retained for compatibility with older clients.
- **v2 current**: fixed and dynamic palettes, 3-bit mode ids, optional explicit
  transparent color, larger canvases up to `256×256`, compact bounds/regions,
  palette descriptors, SOLID_BG, LZ, Quadtree, Bitplanes, and row-delta
  optimizations.

Encoding defaults to v2. To force legacy output, pass:

```js
codec.encode(image, {
  encodingVersion: MCOImageEncodingVersion.v1Legacy,
});
```

v1 cannot encode dynamic palettes or `transparentColor`.

## Explicit transparency

v2 can store an optional `transparentColor`. This is a palette index, not an
alpha bitmap. Every pixel equal to that palette value should be rendered with
alpha `0`; every other pixel remains opaque.

```js
const encoded = codec.encode({
  width: 20,
  height: 20,
  paletteProfile: PaletteProfile.master8,
  pixels,
  transparentColor: 0,
  encodingVersion: MCOImageEncodingVersion.v2,
});
```

## Dynamic palettes

The v2 JS port includes these dynamic profiles:

- `dynamicGlobal8`
- `dynamicGlobal16`
- `dynamicGlobal32`
- `dynamicGlobal64`
- `dynamicGlobal128`
- `dynamicGlobal256`
- `dynamicGlobal512`

For dynamic profiles, the encoder builds a local palette from the colors used by
the image. The current inline dynamic local palette limit is `64` colors. The
demo import pipeline reduces imported images to that limit by keeping the most
frequent colors and remapping the rest to the closest kept color.

## Diagnostics

`codec.debugEncode(image)` returns the selected result plus all candidates
considered by the encoder. This is useful when checking Dart/JS parity:

```js
const diagnostics = codec.debugEncode(image);
console.log(diagnostics.result.text);
console.table(diagnostics.candidates.map((candidate) => ({
  chars: candidate.charLength,
  bytes: candidate.byteLength,
  mode: candidate.modeName,
  scan: candidate.scanName,
  palette: candidate.paletteKind,
})));

console.log(MCOImageCodec.inspectPayload(diagnostics.result.text));
// { version: 2, algorithm: 'LZ pixels', binaryLength: ... }
```

## Demo

Open `index.html` in a browser. The demo uses the browser-global build, so it can
be opened directly from `file://` without ES module import restrictions.

The demo includes:

- pencil, fill, eyedropper, line, oval, and rectangle tools;
- undo/redo;
- canvas shift buttons;
- crop/expand, trim empty border, and aspect-ratio-preserving resize;
- optional grid display;
- image import with format-size limits;
- PNG export at the real image size;
- v2 explicit transparency controls;
- collapsible large palette display.

## Compatibility notes

- The codec is lossless relative to the already prepared palette index array.
  It does not store arbitrary RGB pixels.
- Image import, resizing, dithering, PNG export, and dynamic-palette reduction
  are demo/editor responsibilities, not codec payload features.
- When encoded candidates have equal final length, the encoder uses a stable
  tie order so Dart and JS choose the same payload where possible.
