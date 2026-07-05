# MCOimg codec format overview

MCOimg stores small palette-indexed images for MeshCore/LoRa transport. The
codec is lossless relative to the prepared palette-index array: it compresses
indexes, dimensions, transparency metadata and layout information, but it does
not resize or dither an arbitrary bitmap by itself.

The repository contains three wire versions:

| Version | Status | Text prefix | Binary/channel route | Maximum size |
| --- | --- | --- | --- | --- |
| v1 | legacy read compatibility | `im:` | legacy `0xFFF0` route | `85×85` |
| v2 | legacy compatibility | `im:` | legacy `0xFFF0` route | `256×256` |
| v3 | current | `im3:` | official MCO Advanced `0x0120`, subtype/version `0x13` | `256×256` |

New messages should use v3. v1/v2 decoding remains useful for stored messages
and older clients.

## Text and binary representations

### v1/v2

Legacy text is:

```text
im:<base91 legacy binary payload>
```

### v3

The canonical v3 app payload is:

```text
0x13 | v3 body
```

The high nibble of `0x13` is the MCOimg subtype (`0x01`); the low nibble is the
content version (`0x03`). The text representation encodes that complete app
payload:

```text
im3:<base91 of 0x13 | v3 body>
```

The official MeshCore channel envelope under `data_type = 0x0120` is:

```text
senderNameLength(varuint) | senderName(UTF-8) | 0x13 | v3 body
```

A `.bin` file produced by the version-neutral JavaScript helper is the canonical
app payload including `0x13`. The bare body is a low-level codec representation.

## Common image model

An image has:

- `width` and `height`;
- `paletteProfile`;
- a row-major `pixels` array;
- optional `transparentColor`.

Fixed palette pixels are profile-local indexes. Dynamic profiles store Dynamic
Global palette indexes; blocks can transmit compact local references to only the
colors they use.

Transparency is one optional palette value, not a separate alpha bitmap. Pixels
matching `transparentColor` render with alpha zero; other pixels remain opaque.

## Palette profiles

Fixed profiles:

- `mono`;
- `master4`, `master8`, `master16`, `master32`, `master64`;
- `grayscale8`, `grayscale16`, `grayscale32`.

Dynamic profiles:

- `dynamicGlobal8`, `dynamicGlobal16`, `dynamicGlobal32`;
- `dynamicGlobal64`, `dynamicGlobal128`, `dynamicGlobal256`;
- `dynamicGlobal512`.

Dynamic profiles may choose flat, bitmap, sorted-delta, range-run or banked
reference descriptors, depending on which exact representation is shortest.

## Scan orders

The encoder can test four scan orders:

- `H`: rows left-to-right;
- `V`: columns top-to-bottom;
- `S`: row serpentine;
- `SV`: column serpentine.

Algorithms that are scan-independent use canonical horizontal headers in v3.

## MCOimg v3 body preamble

The v3 body begins with:

```text
byte 0: packet nonce
byte 1:
  bit 7      transparent-color flag
  bit 6      implicit-white-background flag
  bits 5..4  scan order
  bits 3..0  palette profile

following bits:
  canonical dimension encoding
  container/context byte
  optional transparent-color reference
  container body
```

The packet nonce is outside the compressed bitstream and can be changed without
re-encoding the image.

### Canonical dimensions

The first two dimension bits select one of four encodings:

- square up to 64;
- non-square rectangle up to `32×32`;
- larger rectangle with both sides up to 64;
- extended square/rectangle up to `256×256`.

The decoder rejects longer non-canonical alternatives for a size that fits a
shorter form.

### Container/context byte

The high three bits select one of eight top-level containers. The low five bits
carry container-specific context, such as a block algorithm or compact color
reference.

## v3 containers

1. `block`
2. `compactBlock`
3. `boundsBlock`
4. `compactBoundsBlock`
5. `regions`
6. `compactRegionsStream`
7. `solidBackground`
8. `solidRects`

Bounds containers encode a cropped non-background rectangle. Regions containers
encode multiple rectangular areas over a background and can share palettes or
block headers. Solid containers cover constant images and collections of solid
rectangles with minimal overhead.

## v3 block algorithms

The current v3 grammar has 16 block algorithms:

1. `rawGlobal`
2. `rawLocal`
3. `compactRle`
4. `compactSparse`
5. `biColorMask`
6. `rowRepeat`
7. `lzPixels`
8. `quadtree`
9. `bitplanes`
10. `adaptiveBitplanes`
11. `directBitplanes`
12. `compactRowDelta`
13. `directRowDelta`
14. `rowDelta`
15. `varUintRle`
16. `varUintSparse`

Regions may use individual headers, a common header, a hybrid common/individual
plan, and shared local palettes. The final encoder compares exact serialized
candidate lengths and applies a deterministic tie-break.

## Compression levels

JavaScript and Dart use the same values:

```text
High    = 0
Normal  = 1
Extreme = 2
```

- Normal limits expensive search while retaining practical candidate families.
- High enables the full non-Extreme candidate search and stronger Regions plans.
- Extreme adds a bounded reduced-cost Regions beam and exact reranking of the
  best layouts.

The JavaScript v3 implementation can split deterministic candidate partitions
across Web Workers. Extreme uses workers automatically when available; High can
use them with `useWorkers: true`. Completion order never changes comparison
order or the selected payload.

## Strict v3 validation

The v3 decoder rejects:

- invalid palette/profile references;
- impossible container/algorithm combinations;
- non-canonical dimensions;
- invalid local palette descriptors;
- non-zero padding bits;
- trailing bytes;
- illegal scan modes;
- malformed Regions geometry or streams.

This strictness prevents multiple wire encodings for the same structural form
and helps maintain Dart/JavaScript parity.

## JavaScript API

Load compatibility, v3 and browser helpers in order:

```html
<script src="mcoimg-codec.global.js"></script>
<script src="mcoimg-v3-codec.global.js"></script>
<script src="mcoimg-browser.global.js"></script>
```

Encode a canvas:

```js
const text = await MCOImgBrowser.encodeCanvas(canvas, {
  formatVersion: 3,
  compressionLevel: 'high',
  paletteProfile: MCOImgV3.PaletteProfile.master8,
  output: 'text',
});
```

Convert or inspect any canonical text/binary payload:

```js
const binary = await MCOImgBrowser.convertPayload(text, { output: 'binary' });
const png = await MCOImgBrowser.convertPayload(binary, { output: 'png' });
const image = MCOImgBrowser.decodePayload(text);
const metadata = MCOImgBrowser.inspectPayload(text);
```

Use the low-level codec when the bare v3 body or nonce operation is needed:

```js
const codec = new MCOImgV3.MCOImageV3Codec();
const encoded = codec.encode(image, {
  compressionLevel: 'extreme',
});

const decoded = codec.decodeBody(encoded.body);
const refreshedBody = MCOImgV3.MCOImageV3Codec.refreshPacketNonce(encoded.body);
```

## Dart API

The current Dart implementation is `lib/helpers/mcoimg_v3_codec.dart`:

```dart
final codec = MCOImageV3Codec();
final encoded = codec.encode(
  image,
  compressionLevel: mcoImageCompressionLevelHigh,
);

final appPayload = encoded.toAppPayloadWithoutSender(); // 0x13 | body
final decoded = codec.decodeBody(encoded.body);
```

The legacy implementation remains in `lib/helpers/mcoimg_codec.dart`.

## Migration

See `docs/mcoimg-js/MIGRATION_V3.md` for rollout order, payload distinctions,
Worker deployment and deprecation boundaries.
