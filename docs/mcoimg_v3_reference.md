# MCOimg v3 reference

This document describes the current MCOimg v3 format as implemented by the
Dart reference codec in `lib/helpers/mcoimg_v3_codec.dart`.

The older v1/v2 formats are intentionally not specified here. They remain in
the project for compatibility with old messages and clients, but new
implementations should target v3.

## Reference implementation

The normative implementation files are:

- `lib/helpers/mcoimg_v3_codec.dart`: v3 image body encoder/decoder.
- `lib/helpers/channel_app_data_helper.dart`: official app payload envelope.
- `lib/helpers/channel_binary_data_helper.dart`: MeshCore channel binary
  routing for v3.
- `lib/helpers/mcoimg_types.dart`: shared image model, palette/profile enums,
  scan modes and compression level constants.
- `lib/helpers/mcoimg_palette.dart` and
  `lib/helpers/mcoimg_dynamic_palettes.dart`: fixed and dynamic palette tables.

When this document and the Dart code disagree, treat the Dart code as the
reference until the document is updated.

There is also a ready browser JavaScript port in `docs/mcoimg-js/`. It is useful
as an integration example and for browser-side testing. The hosted HTML demo is
available at https://hdden.ru/MCOimg.

## Concept

MCOimg v3 is a compact, lossless format for small palette-indexed images. It
does not dither, resize or quantize arbitrary bitmaps. The input image is
already represented as:

- `width`, `height`, each in `1..256`;
- a `PaletteProfile`;
- a row-major `pixels` array with `width * height` palette references;
- an optional `transparentColor` palette reference.

The codec tries many lossless representations and chooses the shortest binary
body. The chosen body can be carried in either:

- the official MeshCore group-data route, `data_type = 0x0120`;
- a text fallback, `im3:<base91>`.

The v3 body itself does not include a sender name. Sender metadata belongs to
the channel app envelope.

## Transport and envelope

### Official MeshCore channel binary route

MCOimg v3 uses the official MCO Advanced app data type:

```text
data_type = 0x0120
```

The channel app payload under this data type is:

```text
senderNameLen(varuint) | senderName(UTF-8) | subtypeVersion(u8) | packetNonce(u8) + compressed image body
```

`packetNonce` is refreshed for every send so the same image does not produce an
identical radio payload when resent.

For MCOimg v3:

```text
subtype id = 0x01 (content-type - MCOimg)
version    = 0x03 (content format version)
packed subtypeVersion = 0x13 (packed two variables into one byte)
```

The packed byte uses:

```text
bits 7..4: subtype id
bits 3..0: content version
```

### App payload without sender

For files, gallery storage and text fallback, the canonical app payload without
sender is:

```text
0x13 | v3 body
```

Do not store bare v3 bodies in portable files unless the surrounding container
already identifies them as MCOimg v3.

### Text fallback

The text form is:

```text
im3:<Base91(0x13 | v3 body)>
```

The Base91 alphabet and bit queue are implemented by `_V3Base91` in
`mcoimg_v3_codec.dart`. It is the same style of Base91 transport wrapper used
by previous MCOimg text formats, but the decoded payload is v3
`subtypeVersion | body`, not a v1/v2 body.

## Public Dart API

### Encoding

```dart
final image = MCOImage(
  width: width,
  height: height,
  paletteProfile: PaletteProfile.dynamicGlobal128,
  pixels: pixels,
  transparentColor: null,
  encodingVersion: MCOImageEncodingVersion.v3,
);

final encoded = MCOImageV3Codec().encode(
  image,
  compressionLevel: mcoImageCompressionLevelHigh,
);

final body = encoded.body;
final appPayload = encoded.toAppPayloadWithoutSender(); // 0x13 | body
final text = MCOImageV3Codec.textFromBody(body);        // im3:...
```

`encode()` returns `EncodedMCOImageV3`:

- `body`: bare v3 body, including the packet nonce;
- `byteLength`: `body.length`;
- `subtypeId`: normally `0x01`;
- `version`: normally `0x03`;
- `subtypeVersion`: normally `0x13`;
- `encodedCandidate`: diagnostic metadata for the selected candidate.

### Decoding

```dart
final image = MCOImageV3Codec().decodeBody(body);
final imageFromAppPayload =
    MCOImageV3Codec().decodeAppPayloadWithoutSender(appPayload);
final imageFromText = MCOImageV3Codec().decodeText(text);
```

### Inspection

```dart
final info = MCOImageV3Codec.inspectBody(body);
final infoFromText = MCOImageV3Codec.inspectText(text);
```

`MCOImagePayloadInfo` reports:

- `version`: `3`;
- `algorithm`: a human-readable selected algorithm/container label;
- `binaryLength`: body length in bytes.

### Packet nonce

Every v3 body starts with one byte of packet nonce. The nonce is deliberately
outside the compressed bitstream. It exists so a retransmitted or resent image
can get a fresh binary packet identity without recomputing the compression
candidate.

Without this byte, sending only the compressed image body would produce the
same payload every time for the same picture. Mesh repeaters and duplicate
filters can then treat later sends as the same already-heard packet because the
packet hash is identical, so the image may be repeated only once and then stop
being aired. Refreshing the nonce randomizes the packet hash while preserving
the image itself.

Use:

```dart
final refreshed = MCOImageV3Codec.refreshPacketNonce(body);
```

This changes `body[0]` and leaves the compressed image bytes unchanged.

## Compression levels

The encoder accepts the shared MCOimg compression constants:

```text
mcoImageCompressionLevelHigh    = 0
mcoImageCompressionLevelNormal  = 1
mcoImageCompressionLevelExtreme = 2
```

High is the default. Compression level is an encoder setting only; it is not
stored in the payload.

All levels emit the same v3 wire grammar. The level only changes which encoder
candidates are evaluated and how much CPU the encoder is allowed to spend.

The candidate counts below describe top-level candidate attempts before internal
palette descriptor/order variants, LZ parsing choices and row/bitplane
sub-choices. Let `B` be the number of background candidates and `V` be the
number of region-layout variants found for the current image.

| Compression level | Available algorithms | Candidate budget | Active limits | Multithreading |
| --- | --- | --- | --- | --- |
| Normal | Core block algorithms (`rawGlobal`, `rawLocal`, RLE, greedy `lzPixels`, `quadtree`, `bitplanes`, `adaptiveBitplanes`, row-delta, sparse and bicolor modes) plus lightweight regions. | Baseline block pass is about `17 + B*19` full-image attempts. Each cropped-bounds background can add up to `80` attempts. Regions add up to `V*9` attempts per background in diagnostic/full-enumeration mode, or one best region candidate per layout in normal selection mode. | `B <= 4`, scan modes `h`/`v`/`s`, up to 12 regions, non-hybrid region containers only, small shared-palette beam only when `pixelCount <= 4096`. | No. |
| High | Normal plus all scan modes, `directBitplanes`, `directRowDelta`, optimal LZ where budget allows, extended palette-order candidates and full non-Extreme regions. | Baseline block pass is about `30 + B*25` full-image attempts. Each cropped-bounds background can add up to `122` attempts. Regions add up to `V*13` attempts per background in diagnostic/full-enumeration mode, or one best region candidate per layout in normal selection mode. | `B` includes preferred/white/up to 8 frequent colors, plus every used color for small images when `pixelCount <= 4096` and `usedColorCount <= 64`; up to 32 regions; High region beam width 3/depth 2. | No. |
| Extreme | High plus bounded deep region search with reduced-cost evaluation and exact rerank. | Starts from the High budget. For eligible backgrounds it may evaluate up to `1536` reduced region layouts, rerank up to `32` of them exactly, and return up to `10` final deep-region layouts for full candidate evaluation. | Deep region search only for background rank `<= 5`, `pixelCount <= 1536`, `connectedComponentCount <= 20`; beam width 10/depth 8, evaluation budget 1536 layouts, final result limit 10. | Yes, the Flutter canvas partitions Extreme candidate groups across a worker pool. |

### Normal candidate set

Normal is intended to stay reasonably quick while still trying the strongest
cheap candidates.

- Background candidates: at most 4 candidates, starting with the explicit
  background, transparent color or white fallback, then the most frequent image
  colors.
- Top-level scan modes: `h`, `v`, `s`; `sv` is skipped.
- Bounds/full block algorithms:
  `rawGlobal`, `rawLocal`, `compactRle`, `varUintRle`, `lzPixels`,
  `quadtree`, `bitplanes`, `adaptiveBitplanes`, `compactRowDelta`,
  `rowDelta`, `rowRepeat`, `compactSparse`, `varUintSparse`, `biColorMask`.
- Full-image background-independent algorithms:
  `rawGlobal`, `rawLocal`, `compactRle`, `varUintRle`, `lzPixels`,
  `quadtree`, `rowRepeat`.
- Full-image background-sensitive algorithms:
  `bitplanes`, `adaptiveBitplanes`, `rowDelta`, `compactRowDelta`,
  `compactSparse`, `varUintSparse`, `biColorMask`.
- Region limit: up to 12 regions.
- Region scan modes: `h`, `v`, `s`.
- Region block algorithms:
  `rawLocal`, `compactRle`, `varUintRle`, `lzPixels`, `quadtree`,
  `bitplanes`, `adaptiveBitplanes`, `compactRowDelta`, `rowDelta`,
  `rowRepeat`, `compactSparse`, `varUintSparse`, `biColorMask`.
- Region container options: all non-hybrid combinations of common header,
  delta geometry and shared local palette, 8 combinations total.
- Region geometry variants: connected components, empty-line split,
  sparse-line split, and the first greedy rectangle variant.
- Normal shared-palette beam: when the image has at most 4096 pixels, Normal
  may run a small exact shared-palette compact-regions beam with width 3,
  depth 2 and up to 8 neighbors per state.
- LZ pixel parsing uses the greedy parser.
- Local palette search uses frequency, first-use and profile-order variants
  where relevant. Transition, RGB and bitplane-optimized palette orders are not
  enabled.

### High candidate set

High is the default and enables the full non-Extreme candidate table.

- Background candidates: explicit/preferred background, white fallback, up to
  8 most frequent colors, and, for small images, every used color when
  `pixelCount <= 4096` and `usedColorCount <= 64`.
- Top-level scan modes: all four scan modes, `h`, `v`, `s`, `sv`.
- Bounds/full block algorithms: Normal's list plus `directBitplanes` and
  `directRowDelta`.
- Full-image background-independent algorithms: Normal's list plus
  `directBitplanes` and `directRowDelta`.
- Full-image background-sensitive algorithms: same list as Normal.
- Region limit: up to 32 regions.
- Region scan modes: all four scan modes.
- Region block algorithms: Normal's region list plus `rawGlobal`,
  `directBitplanes` and `directRowDelta`.
- Shared-palette region algorithms: Normal's shared list, with the full
  high-compression body evaluator.
- Region container options: Normal's 8 combinations plus 4 hybrid common-header
  combinations, 12 combinations total.
- Region geometry variants: connected components, empty-line split,
  sparse-line split, all greedy rectangle tie-break variants, and payload-cost
  beam search when `pixelCount <= 4096`.
- High region beam: width 3, depth 2, up to 8 neighbors per state, returning up
  to 3 improved layouts.
- LZ pixel parsing uses the optimal parser when the block is within the codec
  budget; larger blocks fall back through the same safe encoding path.
- Local palette search also enables transition order, RGB order where enabled
  by the algorithm, and bitplane-optimized orders for adaptive bitplanes.

### Extreme candidate set

Extreme starts from High and adds the expensive bounded region search. It does
not add decoder-only grammar; it only spends more time looking for better
region layouts.

The deep Extreme region search is attempted only for background candidates with
rank `<= 5`, and only when:

```text
pixelCount <= 1536
connectedComponentCount <= 20
```

When enabled, it uses:

```text
max search regions: min(32, 20)
beam width:         10
beam depth:         8
neighbors/state:    32
evaluation budget:  1536 layouts
reduced rerank pool: 32 layouts
final result limit: 10 layouts
```

The beam first uses a reduced region-cost evaluator to stay bounded, then
reranks the best reduced-cost layouts with the exact v3 regions encoder. If the
image is outside the Extreme bounds, the encoder falls back to the High region
search for that background candidate.

### Threading and workers

Threading is not part of the MCOimg v3 wire format. It is an implementation
detail of the encoder and must not change the selected best candidate or the
decoded image.

The Dart reference codec API, `MCOImageV3Codec.encode()`, is synchronous. The
Flutter canvas integration runs encode jobs through cancellable background
compute so the UI can stay responsive while candidates are evaluated.

In the current Flutter implementation, candidate-level worker slicing is used
only for the Extreme level. Normal and High use the same v3 grammar and the same
cacheable encode result path, but they are not split across multiple worker
isolates in the Dart app.

For Extreme, the canvas partitions independent candidate groups and evaluates
them with a worker pool:

- mobile worker limit: `min(6, Platform.numberOfProcessors)`;
- desktop worker limit: `floor(Platform.numberOfProcessors * 0.85)`, with at
  least one worker;
- the actual worker count is also capped by the number of generated Extreme
  slices.

Browser or JavaScript ports may use Web Workers for the same kind of candidate
partitioning. This is optional implementation behavior: worker use must remain
result-equivalent to a single-threaded encode.

## Bit order and integer primitives

All bit fields are written least-significant-bit first within the byte stream.
For example, `writeBits(value, 3)` writes bit 0, then bit 1, then bit 2 of
`value`.

The body is byte-aligned only when `toBytes()` finalizes the stream. The final
padding bits, if any, must be zero. Decoders must reject non-zero padding bits
and trailing bytes.

### `bitVarUint`

`bitVarUint` is a little-endian 7-bit continuation integer written as whole
bytes through the bit writer:

```text
byte bits 0..6: payload
byte bit 7:     continuation flag
```

At most five bytes are accepted by the Dart decoder.

### `compactUint`

`compactUint` has short prefixes for small values. The prefix bits below are
listed in read/write order:

```text
0 + 2 bits              => 0..3
1,0 + 4 bits            => 4..19
1,1,0 + 8 bits          => 20..275
1,1,1 + bitVarUint      => 276+
```

### `rangeCompactUint(value, maxValue)`

If `maxValue <= 7`, store `value` in `bitLength(maxValue)` fixed bits.
Otherwise store `compactUint(value)`. Decoders must reject values above
`maxValue`.

### `boundedCompactUint(value, maxValue)`

If `maxValue <= 7`, store `value` in `bitLength(maxValue)` fixed bits.
Otherwise:

```text
0 + 2 bits                           => 0..3
1,0 + 4 bits                         => 4..19
1,1,0 + 8 bits                       => 20..275
1,1,1 + bitLength(maxValue-276) bits => 276..maxValue
```

The final escape is invalid when `maxValue < 276`.

## v3 body layout

A bare v3 body is:

```text
packetNonce(u8)
imageHeader(u8)
dimensions(bit-packed)
containerContext(u8)          // 3-bit container id + 5-bit context
transparentColor?             // present when imageHeader bit 7 is set
container body(bit-packed)
zero padding to next byte
```

### `packetNonce`

The first byte is not part of the compressed image state. Decoders should ignore
it for image reconstruction. Encoders may regenerate it before every send.

The nonce solves a practical mesh-network issue: sending the same encoded image
twice would otherwise produce the same byte-level payload. Repeaters and packet
deduplication logic may treat that as an already-seen packet instead of a new
send. By changing only this one byte before every send or resend, a client can
make the packet distinct without recompressing the image or changing any
rendered pixel data.

### `imageHeader`

```text
bit 7:      transparent-color flag
bit 6:      implicit-white-background flag
bits 5..4:  top-level scan id
bits 3..0:  palette profile id
```

Scan ids follow `ScanMode.index`:

| id | scan |
| -- | ---- |
| 0 | `h` |
| 1 | `v` |
| 2 | `s` |
| 3 | `sv` |

Profile ids follow `PaletteProfile.index`:

| id | profile | size | bits |
| -- | ------- | ---- | ---- |
| 0 | `mono` | 2 | 1 |
| 1 | `master4` | 4 | 2 |
| 2 | `master8` | 8 | 3 |
| 3 | `master16` | 16 | 4 |
| 4 | `master32` | 32 | 5 |
| 5 | `master64` | 64 | 6 |
| 6 | `grayscale16` | 16 | 4 |
| 7 | `grayscale32` | 32 | 5 |
| 8 | `grayscale8` | 8 | 3 |
| 9 | `dynamicGlobal8` | 8 | 3 |
| 10 | `dynamicGlobal16` | 16 | 4 |
| 11 | `dynamicGlobal32` | 32 | 5 |
| 12 | `dynamicGlobal64` | 64 | 6 |
| 13 | `dynamicGlobal128` | 128 | 7 |
| 14 | `dynamicGlobal256` | 256 | 8 |
| 15 | `dynamicGlobal512` | 512 | 9 |

Color references are profile-local fixed palette indexes for fixed profiles.
For dynamic profiles, pixels use Dynamic Global palette indexes, while some
direct algorithms convert them to profile-local color ids internally.

### Dimensions

Dimensions are canonical. Decoders should reject a dimension encoding when a
shorter mode could have represented the same size.

The first two bits select:

| mode | meaning | fields |
| ---- | ------- | ------ |
| 0 | square up to 64 | `widthMinus1:6`; `height = width` |
| 1 | non-square up to 32x32 | `widthMinus1:5`, `heightMinus1:5` |
| 2 | non-small rectangle up to 64x64 | `widthMinus1:6`, `heightMinus1:6` |
| 3 | extended up to 256x256 | see below |

Extended mode:

```text
generalRectangle:1
if generalRectangle == 0:
  widthMinus1:8
  height = width
else:
  widthMinus1:8
  heightMinus1:8
```

Valid dimensions are `1..256`.

### `containerContext`

`containerContext` is the shared top-level container byte. It chooses the body
container and gives that container a small 5-bit context value.

```text
bits 7..5: container id
bits 4..0: container-specific context
```

Container ids follow `MCOImageV3Container.index`:

| id | container | context |
| -- | --------- | ------- |
| 0 | `block` | block algorithm id |
| 1 | `compactBlock` | block algorithm id |
| 2 | `boundsBlock` | block algorithm id |
| 3 | `compactBoundsBlock` | block algorithm id |
| 4 | `regions` | `regionCount - 1` |
| 5 | `compactRegionsStream` | `regionCount - 1` |
| 6 | `solidBackground` | low 5 bits of the solid color reference |
| 7 | `solidRects` | low 5 bits of `rectCount - 1` |

For block-like containers the context is a
`MCOImageV3BlockAlgorithm.index`.

For region containers the context stores the region count, so counts 1..32 fit
as context values 0..31.

For `solidBackground`, the context stores the low 5 bits of the color
reference. If the solid color needs more than 5 bits and is not implicit white,
the remaining high bits are written in the body.

For `solidRects`, the context stores the low 5 bits of `rectCount - 1`. The
current encoder limits solid-rectangle candidates to 64 rectangles, so one extra
high bit is written in the body when needed.

## Containers

### `block`

`block` stores a full-image block with a scan-dependent algorithm. The pixels
are converted to the selected top-level scan order before decoding/encoding the
block body. After decoding, the result is converted back to row-major order.

`block` must not be used with scan-independent algorithms that can use
`compactBlock`.

### `compactBlock`

`compactBlock` stores a full-image block with canonical horizontal scan and no
top-level scan dependence. It is currently valid only for algorithms where
`_canUseCompactBlockHeader()` is true:

- `rawGlobal`
- `rawLocal`
- `biColorMask`

The header scan must be `h`.

### `boundsBlock`

`boundsBlock` stores a background color plus one rectangular block. The decoded
image starts as all background pixels; the decoded block overwrites the stored
bounds.

Body:

```text
backgroundRef?        // absent when implicit-white-background flag is set
bounds geometry       // non-compact 8-bit axis fields
block body
```

The block scan is the top-level scan unless the chosen algorithm is a compact
header algorithm in `compactBoundsBlock`.

### `compactBoundsBlock`

`compactBoundsBlock` is the compact geometry version of `boundsBlock`.
Geometry fields use the minimum bits needed for the current image size and
remaining extent.

For compact-header algorithms, top-level scan must be `h` and the block is read
as horizontal. For other algorithms, the normal top-level scan is used.

### `regions`

`regions` stores multiple rectangular blocks over a background. Geometry uses
non-compact 8-bit axis fields. This container exists for the same logical
layout as `compactRegionsStream`, but the compact stream is normally preferred.

### `compactRegionsStream`

`compactRegionsStream` stores multiple rectangular blocks over a background
with optional stream-level compression:

```text
backgroundRef?                  // absent for implicit white
hasCommonBlockHeader:1
hasDeltaGeometry:1
hasSharedLocalPalette:1
common header?                  // if hasCommonBlockHeader
shared local palette?           // if hasSharedLocalPalette
region[regionCount]
```

For each region:

```text
geometry                        // first full geometry, later delta if enabled
usesIndividualHeader?           // only when common header is enabled
algorithm/scan?                 // absent when common header applies
block body
```

When `hasDeltaGeometry` is true, region 0 uses full compact geometry and each
following region stores signed compact deltas from the previous region:

```text
dx, dy, dWidth, dHeight as signedCompactInt
```

`signedCompactInt` maps signed values by zigzag:

```text
encoded = value < 0 ? (-value * 2) - 1 : value * 2
```

and stores `encoded` as `compactUint`.

When `hasSharedLocalPalette` is true, compatible region block bodies reuse one
local palette stored before the region list.

`hasCommonBlockHeader` can be either strict or hybrid. A common algorithm id of
31 is a hybrid marker: the real common algorithm follows, then every region has
one override bit. Only override regions serialize their own algorithm/scan.

### `solidBackground`

`solidBackground` fills the whole image with one color. If the implicit white
flag is set, no color body bits are needed. Otherwise the low 5 bits of the
color reference are stored in the container context and any remaining high bits
are stored after the optional transparent color field.

### `solidRects`

`solidRects` stores a background color, one local palette for rectangle colors,
and several solid rectangles. It is intended for simple icon-like images with a
small number of filled rectangles.

Body:

```text
backgroundRef?                  // absent for implicit white
localPalette
high rect-count bit
rect[rectCount]
```

For every rectangle:

```text
compact bounds geometry
local color index
```

The low 5 bits of `rectCount - 1` live in the container context. One additional
high bit is stored in the body, so the stored count range is 1..64.

## Region and bounds geometry

Non-compact geometry uses 8 bits for each field:

```text
x:8
y:8
widthMinus1:8
heightMinus1:8
```

Compact geometry uses:

```text
x:bitLength(imageWidth)
y:bitLength(imageHeight)
widthMinus1:bitLength(imageWidth - x)
heightMinus1:bitLength(imageHeight - y)
```

The decoded rectangle must stay within the image.

## Local palettes

Many algorithms first store a local palette and then encode local color
indexes.

`localBits = bitLength(localPalette.length - 1)`.

For palette sizes up to 64, the flat prefix is:

```text
0
lengthMinus1:globalBits(profile)
```

For larger profiles, flat lengths are encoded as:

```text
0 + 6 bits                    => lengths 1..64
10 + 6 bits                   => lengths 65..128
110 + 8 bits                  => lengths 129..384
1110 + 7 bits                 => lengths 385..512
```

Descriptor palettes use:

```text
small profiles (<=64 colors): 1 + descriptor:2
large profiles:               1111 + descriptor:2
```

Descriptor ids:

| id | descriptor |
| -- | ---------- |
| 0 | bitmap |
| 1 | sorted delta |
| 2 | range runs |
| 3 | banked descriptor |

The encoder also has an internal ordered-banked descriptor variant. On the
wire it is selected through descriptor id 3 and then by the first bit inside
the banked descriptor body.

Descriptor bodies:

- bitmap: one bit per profile color, in profile order.
- sorted delta: local palette length, first ref in `globalBits`, then
  `compactUint(ref - previousRef - 1)` for each next ref.
- range runs: `rangeCompactUint(runCount - 1, paletteSize - 1) + 1`, followed
  by `start:globalBits` and `compactUint(length - 1)` for each run.
- bank bitmaps: selector bit `0`, `bankMask:8`, then per selected 64-color bank
  a 64-bit bitmap.
- ordered banked 8x64: selector bit `1`, local palette length, then either one
  explicit bank plus 6-bit offsets or a bank mask plus compact bank indexes and
  6-bit offsets.

Decoders must reject duplicate local colors and references outside the profile.

## Block algorithms

Block algorithm ids follow `MCOImageV3BlockAlgorithm.index`:

| id | algorithm |
| -- | --------- |
| 0 | `rawGlobal` |
| 1 | `rawLocal` |
| 2 | `compactRle` |
| 3 | `compactSparse` |
| 4 | `biColorMask` |
| 5 | `rowRepeat` |
| 6 | `lzPixels` |
| 7 | `quadtree` |
| 8 | `bitplanes` |
| 9 | `adaptiveBitplanes` |
| 10 | `directBitplanes` |
| 11 | `compactRowDelta` |
| 12 | `directRowDelta` |
| 13 | `rowDelta` |
| 14 | `varUintRle` |
| 15 | `varUintSparse` |

### `rawGlobal`

Store every pixel as a color reference using `globalBits(profile)`.

### `rawLocal`

Store a local palette, then every pixel as a local palette index.

### `compactRle`

Store a local palette. Then repeat until the block pixel count is filled:

```text
localColorIndex:localBits
runLengthMinus1:boundedCompactUint(remainingPixels - 1)
```

### `varUintRle`

Store a local palette. Then repeat until full:

```text
localColorIndex:localBits
runLength:bitVarUint
```

`runLength` must be positive and must not overrun the block.

### `lzPixels`

Store a local palette. Then repeat until full:

```text
isMatch:1
if isMatch == 0:
  literalLengthMinus1:rangeCompactUint(remainingPixels - 1)
  localColorIndex[ literalLength ]:localBits
else:
  distanceMinus1:rangeCompactUint(decodedPixels - 1)
  lengthMinus3:rangeCompactUint(remainingPixels - 3)
```

Matches require at least three pixels. Distance is one-based after adding one
to the encoded value.

### `quadtree`

Store a local palette. The block is decoded as a recursive 2D tree in
horizontal geometry only. Non-horizontal scan is invalid.

Each node starts with:

```text
isSolid:1
if isSolid:
  localColorIndex:localBits
else:
  children...
```

A non-solid `1x1` node is invalid. Split order is deterministic:

- if `width == 1`, split vertically into top and bottom children;
- else if `height == 1`, split horizontally into left and right children;
- otherwise split into four children in this order: top-left, top-right,
  bottom-left, bottom-right.

The split sizes use integer halves:

```text
leftWidth = width ~/ 2
topHeight = height ~/ 2
```

The second child in each axis receives the remaining pixels.

### `bitplanes`

Store a local palette. For each bit of local color indexes, low bit first:

```text
isRle:1
if isRle == 0:
  raw bit for every pixel
else:
  startingBit:1
  residual run lengths with rangeCompactUint
```

RLE run lengths fill the whole pixel count and alternate bit value after every
run.

### `adaptiveBitplanes`

Store a local palette unless used by a direct algorithm. For each bitplane,
one of these prefixes is written. Prefix bits are listed in stream read order:

```text
0                       raw bits
1,0 + startingBit       legacy RLE, rangeCompactUint run lengths
1,1,0 + startingBit     short RLE
1,1,1,0,0               constant zero
1,1,1,1,0               constant one
1,1,1,0,1               sparse one positions
1,1,1,1,1               sparse zero positions
```

Short RLE run lengths use:

```text
0                 => 1
1,0               => 2
1,1,0             => 3
1,1,1 + rangeCompactUint(length - 4, remaining - 4)
```

Sparse bitplane positions are written by `_writeSparseBitplanePositions`.
They are encoded as:

```text
countMinus1:rangeCompactUint(pixelCount - 1)
repeat count times:
  gapFromPreviousMinus1:rangeCompactUint(maxGap)
```

`previous` starts at `-1`. For position `i`, with `remainingPositions` still
unread after it:

```text
maxGap = pixelCount - previous - remainingPositions - 2
position = previous + gap + 1
```

### `directBitplanes`

This algorithm is valid only for grayscale and dynamic profiles. It skips a
local palette and runs `adaptiveBitplanes` directly on profile-local values.

For dynamic profiles, the body uses dynamic-profile color ids and maps them
back through `MCOImageDynamicPalette.globalIndexForProfileColorId()`.

### `rowDelta`

Store a local palette. The body stores rows relative to predicted rows. First:

```text
useVirtualBaseRow:1
allowShiftPredictors:1
first row values?        // absent when useVirtualBaseRow is true
row operations...
```

Operations are 2-bit:

| id | operation |
| -- | --------- |
| 0 | raw row |
| 1 | repeat predicted row |
| 2 | indexed changes |
| 3 | extended |

Extended operations are 2-bit:

| id | operation |
| -- | --------- |
| 0 | mask |
| 1 | segments |
| 2 | same-scalar mask |
| 3 | repeat run |

Predictors are:

| id | predictor |
| -- | --------- |
| 0 | same previous row |
| 1 | left-shifted previous row |
| 2 | right-shifted previous row |

The full row-delta grammar is in `_writeRowDeltaBody` and
`_readRowDeltaBody`.

### `compactRowDelta`

Store a local palette. The body is a denser row-delta grammar:

```text
useVirtualBaseRow:1
first row values?        // absent when useVirtualBaseRow is true
row operations...
```

Operations are 3-bit:

| id | operation |
| -- | --------- |
| 0 | repeat predicted row |
| 1 | raw row |
| 2 | indexed changes |
| 3 | same scalar |
| 4 | segments |
| 5 | trimmed mask |
| 6 | repeat run |
| 7 | predicted row, no changes |

For operations 2, 3, 4, 5 and 7, a compact predictor is read first:

```text
0   => same
1,0 => left
1,1 => right
```

For direct grayscale use, changed values may be residual-coded from the
predicted value.

### `directRowDelta`

This algorithm is valid only for grayscale and dynamic profiles. It skips a
local palette and runs `compactRowDelta` directly on profile-local values.

For grayscale profiles, residual value coding is enabled. For dynamic profiles,
the body uses dynamic-profile color ids without grayscale residuals.

### `compactSparse`

Store or inherit a background reference. Store a local palette of foreground
colors that must not contain the background. Then store sparse segments until
the segment count is consumed. Segments are runs of non-background pixels.

This variant uses bounded compact integers for segment counts, skips and
lengths:

```text
segmentCountMinus1:boundedCompactUint(pixelCount - 1)
repeat segmentCount times:
  skipBackgroundPixels:boundedCompactUint(pixelCount - currentPosition - 1)
  localColorIndex:localBits
  segmentLengthMinus1:boundedCompactUint(pixelCount - segmentStart - 1)
```

### `varUintSparse`

Store or inherit a background reference. Store a local palette of foreground
colors that must not contain the background. Then:

```text
segmentCount:bitVarUint
repeat segmentCount times:
  skipBackgroundPixels:bitVarUint
  localColorIndex:localBits
  segmentLength:bitVarUint
```

### `biColorMask`

Store or inherit a background reference. Then store one foreground color and a
one-bit mask over all pixels. A set bit selects foreground; an unset bit
selects background. This algorithm uses a compact block header when possible.

### `rowRepeat`

Store a local palette. Store the first row raw, then for each following row
store whether each pixel equals the pixel above it. Pixels that differ carry a
new local color index. See `_writeRowRepeat` and `_readRowRepeat`.

## Implicit white background

When the `implicit-white-background` header bit is set, eligible containers and
algorithms omit their background color reference and use the white color for
the active palette profile.

This is valid for:

- sparse/background block algorithms;
- bounds containers;
- regions containers;
- solid containers.

It is invalid for full block algorithms that have no background reference.

## Transparency

If the transparent-color flag is set, one color reference is stored after the
container/context byte and before the container body. This is metadata only.
The pixel stream still contains normal palette references. A renderer should
draw pixels equal to `transparentColor` with alpha zero.

## Encoder candidate search

A conforming decoder does not need to reproduce the encoder search. It only
needs to decode all valid containers and block algorithms.

To reproduce the Dart encoder's compression quality, implement candidate search
roughly as follows:

1. Build background candidates. Normal tests a preferred background plus the
   most frequent colors. High and Extreme can exhaustively test all used colors
   for small images.
2. Test full-image block containers across allowed scan orders and algorithms.
3. Test bounds containers when a background leaves a smaller non-background
   rectangle.
4. Test solid background and solid rectangles.
5. Test connected/split/greedy/beam region layouts.
6. For each local-palette algorithm, test local palette orders that matter:
   frequency, first-use, profile order, transition order, RGB order and
   bitplane-optimized order when enabled by the compression level.
7. Select the smallest payload. Ties prefer simpler/more stable modes using
   the Dart candidate ranking.

Encoder search is intentionally allowed to evolve without changing the wire
format.

## Decoder validation requirements

A robust port should reject:

- unknown subtype/version when reading canonical app payloads;
- unsupported palette, scan, container or algorithm ids;
- non-canonical dimension encodings;
- colors outside the selected profile;
- duplicate local palette colors;
- local indexes outside local palette length;
- invalid sparse, RLE, LZ, row-delta, quadtree or region ranges;
- non-zero final padding bits;
- trailing bytes after the bit reader finishes.

## Minimal Dart examples

### Encode for channel binary

```dart
final encoded = MCOImageV3Codec().encode(image);

final outbound = ChannelBinaryDataHelper.tryEncodeMcoImageV3Outbound(
  image: encoded,
  senderName: 'MyName',
);

if (outbound != null) {
  // outbound.dataType == 0x0120
  // outbound.payload == senderNameLen | senderName | 0x13 | refreshedBody
}
```

### Encode as text fallback

```dart
final encoded = MCOImageV3Codec().encode(image);
final text = MCOImageV3Codec.textFromBody(encoded.body);
```

### Decode channel app payload

```dart
final envelope = ChannelAppDataHelper.tryDecodeEnvelope(payload);
if (envelope?.subtypeId == ChannelAppDataHelper.mcoImageSubtype &&
    envelope?.version == ChannelAppDataHelper.mcoImageV3Version) {
  final image = MCOImageV3Codec().decodeBody(envelope!.body);
}
```

### Decode canonical file payload

```dart
final image = MCOImageV3Codec().decodeAppPayloadWithoutSender(fileBytes);
```

`image` is an `MCOImage` data object, not a Flutter widget and not a PNG. It is
the decoded indexed image:

- `image.width`, `image.height`: dimensions in pixels;
- `image.paletteProfile`: the palette profile used by the pixel indexes;
- `image.pixels`: immutable row-major palette references, length
  `width * height`;
- `image.transparentColor`: optional palette reference that should be rendered
  with alpha zero.

To read one decoded pixel:

```dart
final pixel = image.pixels[y * image.width + x];
```

Here `x` is the horizontal coordinate from left to right and `y` is the vertical
coordinate from top to bottom. Both are zero-based:

```text
x: 0 .. image.width - 1
y: 0 .. image.height - 1
```

`pixels` is a flat row-major list, so the index for `(x, y)` is
`y * image.width + x`.

For display or export, map each pixel reference through the palette table for
`image.paletteProfile` and apply `transparentColor` as alpha zero.

### Convert decoded image to RGBA or PNG

To render or save the decoded image, first convert the indexed pixels to an RGBA
buffer:

```dart
final rgba = Uint8List(image.width * image.height * 4);
final palette = image.paletteProfile.isDynamic
    ? MCOImageDynamicPalette.global512
    : MCOImagePalette.colorsFor(image.paletteProfile);

for (var i = 0; i < image.pixels.length; i++) {
  final colorIndex = image.paletteProfile.isDynamic
      ? image.pixels[i].clamp(0, MCOImageDynamicPalette.global512.length - 1)
      : image.pixels[i].clamp(0, palette.length - 1);
  final color = palette[colorIndex.toInt()];
  final offset = i * 4;

  rgba[offset] = (color.r * 255).round().clamp(0, 255).toInt();
  rgba[offset + 1] = (color.g * 255).round().clamp(0, 255).toInt();
  rgba[offset + 2] = (color.b * 255).round().clamp(0, 255).toInt();
  rgba[offset + 3] =
      image.transparentColor != null &&
          image.pixels[i] == image.transparentColor
      ? 0
      : (color.a * 255).round().clamp(0, 255).toInt();
}
```

After that, pass the RGBA buffer to the target platform image encoder. In
Flutter, the reference implementation uses `ui.decodeImageFromPixels(...)` with
`ui.PixelFormat.rgba8888`, then `ui.Image.toByteData(format:
ui.ImageByteFormat.png)`. See `MCOImageFileSaver.savePng(...)` in the Dart app
for the complete PNG export flow.

### Inspect without full rendering

```dart
final info = MCOImageV3Codec.inspectAppPayloadWithoutSender(fileBytes);
print('${info.algorithm}, ${info.binaryLength} bytes');
```

## Porting checklist

1. Port palette tables exactly, including dynamic profile mapping.
2. Implement the LSB-first bit reader/writer and integer primitives.
3. Implement app payload parsing: `0x13 | body`.
4. Implement the v3 body preamble, dimensions and container/context byte.
5. Implement local palette descriptors.
6. Implement block algorithms.
7. Implement containers, especially compact bounds and compact regions.
8. Add fixture tests against the Dart implementation.
9. Add roundtrip tests for every palette profile and every block/container
   family.
10. Only after decoder parity is solid, port encoder candidate search.
