# MCO image codec

`MCOImageCodec` encodes small palette-indexed images into compact text strings
for MeshCore/LoRa messages.

The codec is binary-first: metadata and bit-packed pixels are written into a
binary payload, then wrapped in basE91 text.

## Prefix

Every encoded image starts with:

```text
im:
```

Everything after the prefix is basE91 text.

The prefix is intentionally human-readable so chat/rendering code can detect an
image payload without decoding arbitrary message text.

## basE91

basE91 packs arbitrary binary bytes into printable text more densely than base64.
The codec uses the canonical 91-character alphabet; the final character is a
double quote, which is required for standard basE91 encoding.

## Version overview

Two format families are supported:

| Version    | Role          | Max size  | Palettes        | Transparency            | Notes                                    |
| ---        | ---           | ---       | ---             | ---                     | ---                                      |
| v1 legacy  | compatibility | `85×85`   | fixed only      | no                      | Older binary format with 2-bit mode ids. |
| v2 current | default       | `256×256` | fixed + dynamic | optional explicit color | Adds 3-bit mode ids, dynamic palettes, row-delta, regions, and transparent color flag. |

Decoders should keep v1 support so older messages remain readable. Encoders
should prefer v2 unless compatibility with older clients is required.

## Common concepts

### Pixels

The image stores a `width`, `height`, `paletteProfile`, and a flat `pixels`
array in row-major order before scan-order conversion.

Fixed palette pixels are profile-local color indexes. For example, `master8`
pixels are `0..7`.

Dynamic palette pixels are global dynamic palette indexes. The v2 dynamic
encoder transmits a compact local palette referencing only the dynamic colors
used by the payload.

### Scan orders

The encoder tries all scan orders and chooses the shortest final payload.

- `H`: rows
- `V`: columns
- `S`: row serpentine
- `SV`: column serpentine

### Bit packing

Bits are written LSB-first inside each byte.

Legacy aligned varuint values are byte-aligned. v2 block-internal varuint values
are bit-level LEB128-style bytes: each varuint byte is written as 8 bits at the
current bit position, without forcing byte alignment first.

## v1 legacy format

v1 is retained for compatibility. It supports fixed palettes only and has no
explicit transparent color.

### v1 header

```text
byte 0:
bits 7..6  version = 0 or 1
bits 5..4  mode
bits 3..2  scan order
bit  1     background flag
bit  0     bounds flag for version >= 1; reserved/must be 0 for version 0

byte 1:
bits 7..4  fixed palette profile id
bits 3..0  container id for version >= 1; reserved/must be 0 for version 0

byte 2: width - 1
byte 3: height - 1
```

Version 0 payloads are the older block-only shape. Version 1 keeps the legacy
mode layout but can use the low nibble container field and bounds flag where
implemented.

### v1 modes

v1 uses 2-bit mode ids:

- `RAW_GLOBAL`: bit-packed global palette indexes.
- `RAW_LOCAL`: frequency-sorted local palette plus bit-packed local indexes.
- `RLE_LOCAL`: local palette plus run-length encoded local indexes.
- `SPARSE_BG`: background color plus sparse non-background segments.

### v1 limitations

- Fixed palettes only.
- No explicit `transparentColor`.
- Maximum canvas dimension is `85`.
- Fewer block modes than v2.

## v2 current format

v2 is the default/current format.

### v2 header

```text
byte 0:
bits 7..6  version = 2
bits 5..3  mode
bits 2..1  scan order
bit  0     bounds flag

byte 1:
bit  7     palette kind: 0 = fixed, 1 = dynamic
bit  6     container: 0 = block, 1 = regions
bit  5     dynamic reference encoding
bit  4     transparent color flag
bits 3..0  profile id within the selected palette kind

byte 2: width - 1
byte 3: height - 1
```

If the transparent color flag is set, a color reference is written after the
header. The reference uses the selected palette profile.

If bounds are present, the payload also stores the background color and cropped
bounds before the block body. Pixels outside the bounds are filled with the
background color.

### v2 palette profiles

Fixed profiles:

- `mono`
- `grayscale8`
- `grayscale16`
- `grayscale32`
- `master4`
- `master8`
- `master16`
- `master32`
- `master64`

Dynamic profiles:

- `dynamicGlobal8`
- `dynamicGlobal16`
- `dynamicGlobal32`
- `dynamicGlobal64`
- `dynamicGlobal128`
- `dynamicGlobal256`
- `dynamicGlobal512`

Dynamic profiles use global dynamic palette indexes in the image pixel array.
The local palette transmitted inside a v2 payload maps those global indexes to
small local indexes for the selected block.

`dynamicGlobal512` can use either flat references or the `banked8x64` reference
encoding where that is shorter.

### v2 block modes

v2 uses 3-bit mode ids:

- `RAW_GLOBAL`: fixed palettes only; bit-packed global indexes.
- `RAW_LOCAL`: local palette plus bit-packed local indexes.
- `RLE_LOCAL`: local palette plus run-length encoded local indexes.
- `SPARSE_BG`: background color plus sparse non-background segments.
- `BI_COLOR_MASK`: background/foreground color plus a 1-bit mask.
- `ROW_REPEAT`: first row plus repeat/raw flags for following rows.
- `ROW_DELTA`: local palette plus per-row delta operations.
- `REGIONS_BG`: reserved as the regions container mode.

The encoder tries all valid modes and scan orders and chooses the shortest final
`im:<base91>` string.

### Local palette ordering

For v2 local-palette modes, the background color is preferred as the first local
palette entry when it is present. Remaining colors are ordered by descending
frequency, then by numeric color id. This stable ordering is important for
Dart/JS byte parity because local indexes affect row-delta costs.

### Row-delta body

`ROW_DELTA` is optimized for pixel art and small edits between neighboring rows.

The body starts with two flags:

```text
1 bit  use virtual base row
1 bit  allow shift predictors
```

Each row is encoded with one of these 2-bit operations:

- `RAW`: write the entire local row.
- `REPEAT`: copy the predicted previous row.
- `DELTA`: write changed positions and new values.
- `EXTENDED`: use one of the extended row encodings.

When shift predictors are enabled, rows can predict from:

- same previous row position;
- previous row shifted left;
- previous row shifted right.

Extended row encodings include:

- full change mask;
- changed segments;
- same-color change mask.

### Regions container

The v2 regions container splits an image into multiple rectangular regions over
a background. Each region can choose its own best block mode and scan order.
This is useful for sparse pixel art, separated shapes, or images with empty
areas.

The encoder can also split regions by empty lines and sparse lines, then choose
the shortest candidate.

### Explicit transparency

v2 can store one optional transparent color. It is not an alpha bitmap.

When `transparentColor` is set, every pixel equal to that palette value should be
rendered with alpha `0`; all other pixels remain opaque. v1 cannot encode
transparent color.

## Candidate selection

The encoder builds multiple candidates, including different backgrounds, bounds,
scan orders, block modes, and region layouts. It then chooses the shortest final
basE91 string.

When candidates have the same length, a stable tie order is used so Dart and JS
make the same choice where possible.

Current v2 mode tie preference is:

```text
BI_COLOR_MASK
SPARSE_BG
ROW_REPEAT
ROW_DELTA
RLE_LOCAL
RAW_LOCAL
RAW_GLOBAL
REGIONS_BG
```

## API sketch

```dart
final codec = MCOImageCodec();

final image = MCOImage(
  width: 11,
  height: 11,
  paletteProfile: PaletteProfile.master8,
  pixels: List<int>.filled(11 * 11, 0),
  transparentColor: null,
  encodingVersion: MCOImageEncodingVersion.v2,
);

final encoded = codec.encode(image, maxChars: 172);
print(encoded.text); // im:<base91Payload>

final decoded = codec.decode(encoded.text);
print(decoded.width);
print(decoded.height);
print(decoded.pixels);
```

The JavaScript API mirrors this shape through `window.MCOImg`.

## Losslessness

The codec is lossless relative to the already prepared palette index array. It
does not resize, dither, quantize, or convert normal bitmap images by itself.

Bitmap import and dynamic-palette reduction are editor/demo responsibilities.
For example, an importer may map RGB pixels to the closest palette color and may
limit dynamic imports to the inline local palette limit before calling
`MCOImageCodec.encode`.
