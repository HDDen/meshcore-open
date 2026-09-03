# MCOimg v4 reference

Status: experimental pre-release implementation. V4 may still change without
backward compatibility. This document describes the format as implemented in
`lib/helpers/mcoimg_v4_codec.dart`; where the two disagree, the code wins.

## Purpose

MCOimg v4 stores an editable sequence of figures in paint order. It is
optimized for small MeshCore payloads rather than full SVG precision. Canvas
dimensions are limited to `256x256`; rendering may scale the result further.
The editor defaults to a `128x128` coordinate grid and the `Master 8` palette
profile, while the user chooses width, height, and profile before drawing
starts.

A figure may also be a block of text. The text travels as an MCOtxt v1
stream rather than as glyphs, so the payload stays small and no font is
transmitted; see [Text](#text).

Alongside vector figures a document may carry raster layers. A raster layer is
an ordinary figure in the same stream, so it takes part in the z-order like any
other figure, and its pixels are carried as a v3 body. A document containing at
least one visible raster layer is encoded in `mixed` mode; a document without
one is encoded in `vector` mode.

The vector editor can also load a raster reference image, quantize it to the
selected palette profile, and temporarily hide or show it. The reference is only
a drawing aid and is not included in the document or payload; it is distinct
from a raster layer. Changing the grid or palette profile rebuilds it from the
originally loaded file.

Geometric tools use control-point input like the regular canvas: lines finish
on the second point, while rectangles, ellipses, and waves finish on the third.
Placed points remain visible until the figure is complete. Pencil strokes and
object movement remain drag gestures; a short pencil tap creates a single dot.

The separate Polyline tool accepts any number of vertices. The contour can be
finished open or closed; tapping the first vertex after three points also closes
it. An open polyline with a fill is virtually closed for filling only, without a
closing stroke segment.

Figure visibility is editor-only transient state. Hidden figures are not
serialized and cannot be recovered by a receiver; the order of visible figures
in the stream is also their z-order.

The compression level (`high` / `normal` / `extreme`) is an encoder setting
exposed in the editor. It does not appear on the wire and only governs how hard
the v3 encoder searches when encoding raster layers.

## MCO Advanced transport

V3 and v4 share the official `group_data` app-data type:

- `data_type = 0x0120`;
- MCOimg subtype id: `0x01`;
- v3 version: `0x03`, packed byte `0x13`;
- v4 version: `0x04`, packed byte `0x14`.

Envelope:

```text
senderNameLength(varuint) | senderName(UTF-8) | subtypeVersion(u8) | v4Body
```

A client must inspect subtype and version before decoding. Unknown MCOimg
versions should produce an unsupported-image placeholder, not enter the v3
decoder. Stored text uses `im4:` followed by Base91 of `v4Body`.

## V4 body

```text
nonce(u8)
canonicalDocument
transportTail(optional)
```

There is no explicit document length. The canonical document ends at its `END`
opcode followed by zero padding to the next byte boundary; whatever follows that
boundary is the transport tail. The nonce changes for a new transmission and is
excluded from image identity.

## Canonical document

All fields are packed least-significant bit first, exactly as in v3.

```text
mode(2)
paletteProfile(4)
dimensions
hasBackgroundOverride(1)
  backgroundPresent(1)?              // only when hasBackgroundOverride
  backgroundRef(profileColorBits)?   // only when backgroundPresent
commandStream
END(4)
zero padding to byte boundary
```

`mode` follows `MCOImageV4Mode`:

```text
0 vector     no raster layers
1 mixed      at least one raster layer in the stream
2 raster     reserved, rejected on decode
3 reserved   rejected on decode
```

The encoder derives the mode from the document: `mixed` when a visible raster
layer is present at the top level, `vector` otherwise. A decoder that meets mode
`2` or `3` reports an unsupported format rather than a damaged payload.

There is **no palette table on the wire and no initial-style block**. Colors are
written as profile color references; the document-local palette is a decoder-side
artifact built in order of first use. The decoder registers the profile white
before reading the background, so local index `0` is always the profile white;
next comes the background color when the override introduces a new one, and then
the profile black, which the fixed initial style refers to.

The initial style is fixed by the format: `fill = none`, `stroke = profile
black`, `strokeWidth = 1`. Any other starting style costs an ordinary style
command at the head of the stream.

`hasBackgroundOverride` is `0` when the background is the profile white, which
is the implicit default. When it is `1`, an optional color follows: a presence
bit and, if set, a `profileColorBits` reference; a cleared presence bit means a
transparent background.

Derived widths:

```text
xBits            = coordinateBits(width)
yBits            = coordinateBits(height)
scalarBits       = max(1, bitLength(max(width, height) - 1))
profileColorBits = max(1, bitLength(profileColorCount - 1))
localBits(size)  = max(1, bitLength(size - 1))
```

`profileColorCount` is the size of the selected profile: 2 for `mono` up to 64
for `master64`, and the dynamic profiles use their own index count (9 bits for
`dynamicGlobal512`). `localBits` is used only inside bounds-relative path forms.

`paletteProfile` follows `PaletteProfile` order:

```text
0 mono                 8 grayscale8
1 master4              9 dynamicGlobal8
2 master8             10 dynamicGlobal16
3 master16            11 dynamicGlobal32
4 master32            12 dynamicGlobal64
5 master64            13 dynamicGlobal128
6 grayscale16         14 dynamicGlobal256
7 grayscale32         15 dynamicGlobal512
```

A fixed-profile color reference is a profile-local color id; a dynamic-profile
reference is a profile color id that maps to a `global512` index. A document
model may hold at most 64 distinct colors; that limit is a model constraint and
is not encoded.

### Dimensions

Four canonical modes; a decoder rejects an encoding that a shorter mode could
have expressed.

```text
mode(2) = 0   square up to 64:      widthMinus1(6), height = width
mode(2) = 1   non-square up to 32:  widthMinus1(5), heightMinus1(5)
mode(2) = 2   non-square up to 64:  widthMinus1(6), heightMinus1(6)
mode(2) = 3   extended:             generalRectangle(1)
                                    0: widthMinus1(8), height = width
                                    1: widthMinus1(8), heightMinus1(8)
```

Canonicity rules enforced on decode: mode 1 rejects `width == height`; mode 2
rejects `width == height` and any pair that fits mode 1; extended square rejects
`width <= 64`; extended rectangle rejects `width == height` and any pair that
fits mode 2.

## Coordinates and rendering

Coordinates are signed and may leave the canvas by a margin that grows with the
canvas:

```text
margin(size)     = min(16, max(1, ceil(size / 8)))
valueCount(size) = size + 2 * margin(size)
coordinateBits(size) = max(1, bitLength(valueCount(size) - 1))
stored           = value + margin(size)
valid value      = -margin(size) .. size + margin(size) - 1
```

Stored codes outside `0 .. valueCount - 1` cannot occur because the field is
exactly `coordinateBits` wide; a decoded value outside the valid range is
rejected. Spare codes at the top of the field are invalid and are not normalized
over the axis.

Point `(x, y)` maps to logical position `(x + 0.5, y + 0.5)` in canvas bounds
`[0, width] x [0, height]`.

```text
scale = min(viewportWidth / width, viewportHeight / height)
offsetX = (viewportWidth - width * scale) / 2
offsetY = (viewportHeight - height * scale) / 2
screenX = offsetX + (x + 0.5) * scale
screenY = offsetY + (y + 0.5) * scale
```

The renderer clips output to the canvas but does not rewrite geometry, so a
figure whose anchors sit in the overscan margin is transmitted intact and simply
clipped when drawn. Antialiasing is implementation-dependent; geometry, non-zero
fill, square caps, and miter joins are normative. The dot primitive remains
circular.

Rectangles and ellipses are defined by control points on the cell-center grid.
Full-canvas background fill is a document-level color, so area figures do not
need special edge-reaching fill semantics.

## Integer primitives

`bitCompactUint`, written into the bit stream:

- `0 + 2 bits`: 0..3;
- `10 + 4 bits`: 4..19;
- `110 + 8 bits`: 20..275;
- `111 + bitVarUint7`: values above 275 in shortest form.

`bitVarUint7` is a 7-bit continuation integer written as whole bytes through the
bit writer, at most five bytes, shortest form. A continuation byte whose payload
is zero is non-canonical and rejected.

Signed short fields use ZigZag: `encoded = value < 0 ? -value * 2 - 1 : value * 2`.
A short delta of width `d` is valid only while the ZigZag code fits `d` bits.
Positive scalars store `value - 1`.

## Command stream

Base opcodes are 4 bits.

| opcode | command |
| --- | --- |
| 0 | `END` |
| 1 | `SET_FILL` |
| 2 | `SET_STROKE` |
| 3 | `SET_STROKE_WIDTH` |
| 4 | `DOT` |
| 5 | `LINE` |
| 6 | `RECT` |
| 7 | `ELLIPSE` |
| 8 | `RECT_AXIS_ALIGNED` |
| 9 | `PATH_ABSOLUTE` |
| 10 | `PATH_DELTA` |
| 11 | `WAVE` |
| 12 | `REPEAT_LAST` |
| 13 | `ELLIPSE_AXIS_ALIGNED` |
| 14 | `REPEAT_SHORT` |
| 15 | `EXTENDED` escape |

Opcode 15 is an escape followed by a 4-bit sub-opcode:

| sub-opcode | command |
| --- | --- |
| 0 | `LINE_DELTA` |
| 1 | `LINE_AXIS_DELTA` |
| 2 | `AREA_DELTA` |
| 3 | `WAVE_DELTA` |
| 4 | `PATH_ORTHOGONAL` |
| 5 | `PATH_BOUNDS` |
| 6 | `PATH_BOUNDS_DELTA` |
| 7 | `LINE_AXIS_ABSOLUTE` |
| 8 | `ELLIPSE_DEPTH` |
| 9 | `REPEAT_BACK` |
| 10 | `DOT_RUN` |
| 11 | `SET_STYLE` |
| 12 | `REPEAT_COLOR_RUN` |
| 13 | `GROUP` |
| 14 | `RASTER_LAYER` |
| 15 | `EXTENDED2` escape |

Every alternate form is a pure encoder choice: the encoder builds all applicable
candidates and emits the shortest. A decoder must accept all of them and gets the
same figures either way.

Below, `point` means `x(xBits) + y(yBits)` with the coordinate offset applied,
`color` means `present(1) + ref(profileColorBits)?`, and `selector(2)` selects a
short delta width from `[3, 4, 5, 6]`.

## Style commands

```text
SET_FILL          op(4) + color
SET_STROKE        op(4) + color
SET_STROKE_WIDTH  op(4) + widthMinus1(scalarBits)
SET_STYLE         op(4) + ext(4) + mask(3)
                  + fillColor?    // mask bit 0
                  + strokeColor?  // mask bit 1
                  + widthMinus1?  // mask bit 2, scalarBits
```

The header defines the initial style; the editor model stores absolute styles
and the encoder emits only transitions. For each transition the encoder compares
the separate `SET_*` commands against one combined `SET_STYLE` and emits the
shorter. `stroke = none` means no outline; width zero is not representable.

## Figures

```text
DOT                    op(4) + point
LINE                   op(4) + point + point
RECT                   op(4) + point + point + point
ELLIPSE                op(4) + point + point + point
RECT_AXIS_ALIGNED      op(4) + swapped(1) + point + point
ELLIPSE_AXIS_ALIGNED   op(4) + swapped(1) + point + point
WAVE                   op(4) + closed(1) + point + point
                       + negative(1) + depthMinus1(scalarBits)
```

- `DOT`: one point; diameter equals stroke width. A dot requires a stroke color.
- `LINE`: start and end points.
- `RECT`: three control points `A, C, B`; the fourth corner is `D = A + C - B`.
- `ELLIPSE`: three control points. The first two define the major axis; the third
  defines the minor axis along the major-axis normal.
- The axis-aligned forms apply when the third control point is derivable from the
  other two. `swapped = 0` means `third = (first.x, second.y)`; `swapped = 1`
  means `third = (second.x, first.y)`.
- `WAVE` is a quadratic Bezier. Signed depth follows the chord normal and marks
  the visible arc midpoint; the control point uses twice that depth. Endpoints
  remain on the point-center grid. Depth zero is invalid.

An open filled path or wave is closed for fill only. The closing outline is
drawn only when `closed = true`. The three control points of an area figure must
be distinct.

### Alternate figure forms

```text
LINE_DELTA           op(4) + ext(4) + selector(2)
                     + point + zz(dx)(d) + zz(dy)(d)

LINE_AXIS_ABSOLUTE   op(4) + ext(4) + vertical(1)
                     vertical:   x(xBits) + y0(yBits) + y1(yBits)
                     horizontal: y(yBits) + x0(xBits) + x1(xBits)

LINE_AXIS_DELTA      op(4) + ext(4) + vertical(1) + selector(2)
                     + point + zz(delta)(d)

AREA_DELTA           op(4) + ext(4) + isEllipse(1) + selector(2)
                     + point + 2 x (zz(dx)(d) + zz(dy)(d))

WAVE_DELTA           op(4) + ext(4) + closed(1) + negative(1)
                     + depthMinus1(scalarBits) + selector(2)
                     + point + zz(dx)(d) + zz(dy)(d)

ELLIPSE_DEPTH        op(4) + ext(4) + point + point
                     + negative(1) + depthMinus1(scalarBits)

DOT_RUN              op(4) + ext(4) + delta(1)
                     delta = 0: bitCompactUint(n - 2) + point x n
                     delta = 1: selector(2) + bitCompactUint(n - 2)
                                + point + (n - 1) x (zz(dx)(d) + zz(dy)(d))
```

`DOT_RUN` carries two or more consecutive dots that share one style. Unlike the
path forms it has no per-component escape, so the delta variant is offered only
when every step fits the selected width.

`ELLIPSE_DEPTH` replaces the third control point with a signed distance along the
major-axis normal from the axis midpoint. The encoder uses it only when the third
point is reproduced exactly by that reconstruction; the decoder rejects a depth
that does not land on an integer point.

## Paths

`pointCount` stores `actualCount - minimum`, with minimum 2 for open paths and 3
for closed paths.

```text
PATH_ABSOLUTE      op(4) + closed(1) + bitCompactUint(n - min)
                   + point x n

PATH_DELTA         op(4) + closed(1) + selector(2) + bitCompactUint(n - min)
                   + point
                   + per later X and Y component:
                       0 + zz(delta)(d)
                       1 + absoluteCoordinate(axisBits)

PATH_ORTHOGONAL    op(4) + ext(4) + closed(1) + selector(2)
                   + bitCompactUint(n - min) + point
                   + per later point: vertical(1) + zz(delta)(d)

PATH_BOUNDS        op(4) + ext(4) + closed(1) + bitCompactUint(n - min)
                   + originPoint
                   + boundsWidthMinus1(xBits) + boundsHeightMinus1(yBits)
                   + per point: localX(localBits(bw)) + localY(localBits(bh))

PATH_BOUNDS_DELTA  op(4) + ext(4) + closed(1) + selector(2)
                   + bitCompactUint(n - min) + originPoint
                   + boundsWidthMinus1(xBits) + boundsHeightMinus1(yBits)
                   + localX(localBits(bw)) + localY(localBits(bh))
                   + per later point: zz(dx)(d) + zz(dy)(d)
```

`PATH_ORTHOGONAL` applies only when every segment is axis-aligned; each later
point costs one direction bit plus one short delta instead of two components.

The bounds forms store the path's bounding box and then address points inside it,
so a small path on a large canvas pays only the bits its own extent needs. The
origin uses full canvas coordinates; the local fields use `localBits` of the
bounding-box size and are unsigned offsets from the origin.

`PATH_DELTA` is the only path form with a per-component escape: `0` selects the
short ZigZag delta, `1` selects a full absolute axis coordinate. The other delta
forms require every delta to fit the selected width and are simply not offered as
candidates otherwise.

Stroke sampling, RDP simplification, quantization, duplicate removal, and
collinear-point removal are non-normative encoder work. The decoder restores the
transmitted path exactly.

## Repeats

```text
REPEAT_LAST        op(4) + zz(dx)(xBits + 1) + zz(dy)(yBits + 1)

REPEAT_SHORT       op(4) + selector(2) + zz(dx)(d) + zz(dy)(d)

REPEAT_BACK        op(4) + ext(4) + distanceMinus1(3) + short(1)
                   short = 1: selector(2) + zz(dx)(d) + zz(dy)(d)
                   short = 0: zz(dx)(xBits + 1) + zz(dy)(yBits + 1)

REPEAT_COLOR_RUN   op(4) + ext(4) + strokeColorRun(1) + short(1)
                   short = 1: selector(2) + zz(dx)(d) + zz(dy)(d)
                   short = 0: zz(dx)(xBits + 1) + zz(dy)(yBits + 1)
                   + bitCompactUint(count - 2) + hasColorChanges(1)
                   + count - 1 optional colors when hasColorChanges
```

A repeat reproduces the geometry of an earlier figure translated by a signed
offset and takes its style from the current state. `REPEAT_LAST` and
`REPEAT_SHORT` refer to the last emitted figure; `REPEAT_BACK` refers to the
figure `distance` places back, where `distance` is 2 to 8. Repeats can chain: a
repeated figure joins the history and can itself be repeated.

`REPEAT_COLOR_RUN` emits a chain of `count` repeats, each translated by the same
offset from the previous one, starting from the last figure in history. When
`hasColorChanges` is set, every figure after the first carries its own optional
color, applied to the stroke when `strokeColorRun` is set and to the fill
otherwise. The run leaves the last applied color as the current style.

If a translated result would fall outside the coordinate range, the encoder emits
the full figure instead. A repeat with no prior figure is invalid.

## Groups

```text
GROUP  op(4) + ext(4) + bitCompactUint(figureCount - 1) + nested command stream
```

A group holds at least one figure. Its command stream uses the same opcodes and
its own nested style state, seeded from the style current at the group, and its
own nested history, which starts empty. The group ends when `figureCount` figures
have been produced; `END` inside a group is invalid, and so is a stream that
yields more figures than declared.

Raster layers cannot be nested in a group.

## Raster layers

```text
RASTER_LAYER  op(4) + ext(4) + originPoint + v3HeaderHigh(4)
              + bitCompactUint(payloadLength) + payload(payloadLength bytes)
```

The payload is a v3 body encoded without its packet nonce. Its first byte, the v3
image header, is split: the high nibble travels as `v3HeaderHigh` and the low
nibble is reconstructed from the document's `paletteProfile`, so the profile is
not duplicated. A decoder rebuilds `body[0] = (v3HeaderHigh << 4) | paletteProfile`,
prepends it to the payload, and decodes the result with the v3 decoder; a layer
whose decoded profile differs from the document profile is invalid.

The layer's own size, pixels, and transparent color come from the v3 image; only
the origin is stored by v4. `payloadLength` must be at least 2. Raster layers are
valid only in `mixed` mode and only at the top level of the stream.

## Text

```text
TEXT  op(4) + ext(4) = 15 + ext2(4) = 0
      + originPoint + mask(3)
      + widthMinus1(xBits)?           // mask bit 0
      + align(2)?                     // mask bit 1
      + fontSizeMinus1(scalarBits)?   // mask bit 2
      + bitCompactUint(bitLength) + bitLength bits of MCOtxt stream
```

Extended sub-opcode `15` is a second escape rather than a command: four more
bits choose one of sixteen commands, of which `0` is `TEXT` and the rest are
reserved. A decoder that meets a reserved one reports an unsupported format,
not a damaged payload.

`originPoint` is the top-left corner of the text area and lines grow
downward. `align` is `0` left, `1` center, `2` right; `3` is invalid. The area
width is stored in canvas cells, and a cleared mask bit 0 means the default,
`max(1, min(width, width - originX))`, from the anchor to the right canvas
edge. `fontSize` is the em height in canvas cells.

Alignment and font size are **sticky**, the way style is. A document starts at
left alignment and a font size of `max(1, width * 12 / 100)`, and every `TEXT`
command writes only the fields it changes, so a run of captions pays for a
change once. A group keeps its own text state, seeded from the state current
at the group and discarded when the group ends. A repeat leaves the state
alone and reproduces the text fields of the figure it copies; the reference
encoder never offers a repeat for text.

The text itself is an MCOtxt v1 stream, specified in
[`MCOTXT_V1_PROTOCOL.md`](MCOTXT_V1_PROTOCOL.md). It is embedded bit by bit,
because MCOtxt packs most-significant bit first while this format packs
least-significant bit first, and `bitCompactUint(bitLength)` precedes it: an
MCOtxt stream is not self-terminating, so its bit count has to travel with it.
The stream carries its own codec version and model generation, so a client
without the tables the text was written with rejects the whole image; it does so
as an unsupported format rather than as damage, which is what earns the reader
an "update the app" placeholder. An empty text is legal and draws nothing.

Only explicit line feeds, which the MCOtxt punctuation page carries, travel on
the wire. Where a line is broken to fit the area is left to the renderer.

**Rendering is not normative.** No font is transmitted, so two clients may lay
the same text out differently; the anchor, the area width and the em height
are the only things they are guaranteed to agree on. This app draws glyphs in
the stroke color of the current style and fills the area with its fill color,
over the area width and the height the text laid out to; a text with no stroke
color draws no glyphs. It lays each line out in a box of `1.2` em with the
leading split evenly, so the filled area is `lines * 1.2 * fontSize` tall and
the glyphs sit in the middle of it rather than following the font's own
metrics.

## Transport tail and replies

Tail starts with byte flags:

- bit 0: `targetNameLength(byteVarUint7) + targetName(UTF-8)`;
- bit 1: `replyTimestamp(uint32 LE)`;
- bits 2-7: reserved and zero.

`byteVarUint7` here is a byte-level shortest-form 7-bit continuation integer, not
the bit-stream primitive. An empty target name is invalid. The tail is absent
when neither field is present.

The tail is not part of the canonical document. It remains in chat transport but
is removed when saving to the gallery, an image pack, or `.mcoimg.bin`.

## Identity

Pack-tooling identity is:

```text
MD5(0x14 | 0x00 | canonicalDocument)
```

The subtype/version byte is followed by a zeroed nonce and the canonical document
bytes. Nonce and transport tail are excluded, so recipients and reply targets do
not alter image identity. Because the document boundary is found by parsing,
computing this hash requires a v4 parser rather than a byte-offset rule.

## Validation

The decoder fails closed. Rejected input includes truncated bit streams,
non-canonical `bitCompactUint` and `bitVarUint7`, non-canonical dimension modes,
reserved modes `2` and `3`, unknown palette profiles, out-of-range color
references, coordinates outside the overscan range, duplicate area control
points, wave depth zero, stroke width outside `1 .. max(width, height)`, dots
without a stroke color, paths with too few points, repeats without a matching
prior figure, `END` inside a group, groups that overflow their declared count,
raster layers outside `mixed` mode or inside a group, raster payloads shorter
than two bytes, raster layers whose profile disagrees with the document, a
reserved second-escape command, a text alignment of `3`, a text area width
outside `1 .. width`, a font size outside `1 .. max(width, height)`, an
MCOtxt stream this build cannot decode, non-zero padding, and unknown
transport-tail flags. Partially damaged drawings
are not rendered.

## Implementation status

The Dart codec, vector renderer and editor, text figures over MCOtxt, raster
layers with v3-encoded payloads, compression-level selection, the binary send
and receive path, replies, stable identity, gallery, and BIN/PNG import and
export are implemented.

A dedicated pure-raster mode (`mode = 2`), optional overlap removal between
layers, the JavaScript port, and cross-runtime fixtures remain follow-up phases.
