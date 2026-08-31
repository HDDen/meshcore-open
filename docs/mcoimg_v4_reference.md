# MCOimg v4 reference

Status: experimental pre-release implementation. V4 may still change without
backward compatibility. The vector section is implemented; the raster section
is reserved for the next phase.

## Purpose

MCOimg v4 stores an editable sequence of vector figures in paint order. It is
optimized for small MeshCore payloads rather than full SVG precision. Canvas
dimensions are limited to `256x256`; rendering may scale the result further.
The editor defaults to a `32x32` coordinate grid, while the user chooses width
and height before drawing starts.

The vector editor can load a raster reference image, quantize it to the selected
palette profile, and temporarily hide or show it. The reference is only a
drawing aid and is not included in the document or payload. Changing the grid or
palette profile rebuilds it from the originally loaded file.

Geometric tools use control-point input like the regular canvas: lines finish
on the second point, while rectangles, ellipses, and waves finish on the third.
Placed points remain visible until the figure is complete. Pencil
strokes and object movement remain drag gestures; a short pencil tap creates a
single dot.

The separate Polyline tool accepts any number of vertices. The contour can be
finished open or closed; tapping the first vertex after three points also closes
it. An open polyline with a fill is virtually closed for filling only, without a
closing stroke segment.

Figure visibility is editor-only transient state. Hidden figures are not
serialized and cannot be recovered by a receiver; the order of visible figures
in the stream is also their z-order.

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
documentLength(byteVarUint7)
canonicalDocument(documentLength bytes)
transportTail(optional)
```

`documentLength` is canonical shortest-form and excludes the transport tail.
The nonce changes for a new transmission and is excluded from image identity.

## Canonical document

Fields after the header are packed least-significant bit first.

```text
mode(1)                         // 0 = vector, 1 = reserved raster
widthMinus1(8)
heightMinus1(8)
paletteProfile(4)
paletteCountMinus1(6)
palette[paletteCount]           // profileColorBits per entry
hasBackground(1)
backgroundLocalIndex?           // paletteBits
hasDefaultFill(1)
defaultFillLocalIndex?          // paletteBits
hasDefaultStroke(1)
defaultStrokeLocalIndex?        // paletteBits
defaultStrokeWidthMinus1        // scalarBits
commandStream
END(4)
zero padding to byte boundary
```

```text
xBits       = max(1, bitLength(width - 1))
yBits       = max(1, bitLength(height - 1))
scalarBits  = max(1, bitLength(max(width, height) - 1))
paletteBits = max(1, bitLength(paletteCount - 1))
profileColorBits = dynamic ? 9 : bitLength(profileColorCount - 1)
```

Coordinates are integer indices in `0 .. axisSize - 1`. Spare bit-field codes
are invalid; they are not normalized over the axis. The document palette has
1 to 64 unique colors from the selected v3 profile. A fixed-profile entry is a
profile-local color id; a dynamic-profile entry is a `global512` index that must
belong to that dynamic profile. Figures use short document-local palette indices.

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

For 128–512-color dynamic profiles, the editor exposes the whole profile but
adds only selected colors to the document-local palette, up to 64 entries.
A new v4 canvas defaults to `Master 8`. Grid visibility is inherited from the
regular v2/v3 canvas.

## Coordinates and rendering

Point `(x, y)` maps to logical position `(x + 0.5, y + 0.5)` in canvas bounds
`[0, width] x [0, height]`.

```text
scale = min(viewportWidth / width, viewportHeight / height)
offsetX = (viewportWidth - width * scale) / 2
offsetY = (viewportHeight - height * scale) / 2
screenX = offsetX + (x + 0.5) * scale
screenY = offsetY + (y + 0.5) * scale
```

The renderer clips output to the canvas but does not rewrite geometry. Anchor
points remain inside the canvas. Antialiasing is implementation-dependent;
geometry, non-zero fill, square caps, and miter joins are normative. The dot
primitive remains circular.

Rectangles and ellipses are defined by control points on the cell-center grid.
Full-canvas background fill is a document-level color, so area figures do not
need special edge-reaching fill semantics.

## Style state machine

The header defines the initial style. The editor model stores absolute styles;
the encoder emits only transitions.

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
| 8 | reserved |
| 9 | `PATH_ABSOLUTE` |
| 10 | `PATH_DELTA` |
| 11 | `WAVE` |
| 12 | `REPEAT_LAST` |
| 13-15 | reserved |

Opcodes are 4 bits. Optional colors use a presence bit plus a local palette
index. Positive scalars store `value - 1`. Width zero is not representable;
`stroke = none` means no outline.

## Figures

- `DOT`: one point; diameter equals stroke width.
- `LINE`: start and end points.
- `RECT`: three control points `A, C, B`; the fourth corner is calculated as
  `D = A + C - B`.
- `ELLIPSE`: three control points. The first two points define the major axis;
  the third point defines the minor axis along the major-axis normal.
- `PATH`: `closed`, point count, points.
- `WAVE`: `closed`, two endpoints, signed depth.

An open filled path or wave is closed for fill only. The closing outline is
drawn only when `closed = true`.

`WAVE` is a quadratic Bezier. Signed depth follows the chord normal and marks
the visible arc midpoint; the control point uses twice that depth. Endpoints
remain on the point-center grid.

## Paths

`pointCount` stores `actualCount - minimum`, with minimum 2 for open paths and
3 for closed paths. bitCompactUint is:

- `0 + 2 bits`: 0..3;
- `10 + 4 bits`: 4..19;
- `110 + 8 bits`: 20..275;
- `111 + bitVarUint7`: values above 275 in shortest form.

The encoder compares `PATH_ABSOLUTE` with four `PATH_DELTA` candidates. Delta
stores a two-bit selector for short widths `3/4/5/6`. The first point is
absolute. Each later X/Y component has an escape bit: `0` means short ZigZag
delta, `1` means a full absolute axis coordinate.

Stroke sampling, RDP simplification, quantization, duplicate removal, and
collinear-point removal are non-normative encoder work. The decoder restores
the transmitted path exactly.

## REPEAT_LAST

This repeats only the last emitted geometry with signed X/Y translation. Style
comes from the current state. Repeats can chain. If a translated result would
be invalid, the encoder must emit the full figure instead.

## Transport tail and replies

Tail starts with byte flags:

- bit 0: `targetNameLength(byteVarUint7) + targetName(UTF-8)`;
- bit 1: `replyTimestamp(uint32 LE)`;
- bits 2-7: reserved and zero.

Tail is not part of `documentLength`. It remains in chat transport but is
removed when saving to the gallery, an image pack, or `.mcoimg.bin`.

## Identity

Pack-tooling identity is:

```text
MD5(0x14 | 0x00 | canonicalDocumentLength | canonicalDocument)
```

Length is shortest-form byteVarUint7. Nonce and transport tail are excluded,
so recipients and reply targets do not alter image identity.

## Validation

The decoder fails closed for truncated input, non-canonical integers, unknown
opcodes, non-zero padding, repeat without a prior figure, invalid or duplicate
colors, invalid palette references, out-of-axis coordinates, invalid geometry,
invalid positive scalars, insufficient path points, and unknown tail flags.
Partially damaged drawings are not rendered.

## Implementation status

The Dart codec, vector renderer/editor, binary send/receive path, replies,
stable identity, gallery, and BIN/PNG import/export are implemented. Raster
mode, v3-candidate layers, optional overlap removal, and the JavaScript port
remain separate follow-up phases.
