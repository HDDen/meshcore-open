# MCO image codec

`MCOImageCodec` encodes small palette-indexed images into compact text strings
for MeshCore/LoRa messages.

## Prefix

Every encoded image starts with:

```text
im:
```

The prefix is human-readable and lets chat code detect that the message body is
an image payload. Everything after the prefix is basE91 text.

## Binary-first format

All metadata is stored inside the binary payload before basE91 wrapping:

- version
- mode
- scan order
- palette profile
- optional background flag
- width and height

This avoids older text-heavy formats such as `im1:w15h8H:<payload>` and keeps
the transmitted string shorter.

Current payload header:

```text
byte 0:
bits 7..6  version = 0
bits 5..4  mode
bits 3..2  scan order
bit  1     background flag
bit  0     reserved, must be 0

byte 1:
bits 7..4  palette profile id, 0..15
bits 3..0  reserved, must be 0

byte 2: width - 1
byte 3: height - 1
```

## Why basE91

basE91 packs arbitrary binary bytes into printable text more densely than
base64. The codec uses the canonical 91-character alphabet; the final character
is a double quote, which is required for standard basE91 encoding.

## Palette profiles

- `mono`: global palette indexes `0..1`, 1 bit per color
- `master4`: global palette indexes `0..3`, 2 bits per color
- `master8`: global palette indexes `0..7`, 3 bits per color
- `master16`: global palette indexes `0..15`, 4 bits per color
- `master32`: global palette indexes `0..31`, 5 bits per color
- `master64`: global palette indexes `0..63`, 6 bits per color

The actual RGB palette is shared by both sides and is not transmitted.
The header reserves 4 bits for palette profile id, so the format can address up
to 16 built-in palette profiles without transmitting custom RGB tables.

## Modes

The encoder tries all modes and scan orders, then chooses the shortest final
`im:<base91>` string.

- `RAW_GLOBAL`: bit-packed global palette indexes.
- `RAW_LOCAL`: a frequency-sorted local palette plus bit-packed local indexes.
- `RLE_LOCAL`: a local palette plus run-length encoded local indexes.
- `SPARSE_BG`: a background color plus sparse non-background segments.

Scan orders:

- `H`: rows
- `V`: columns
- `S`: row serpentine
- `SV`: column serpentine

When encoded strings have equal length, the tie order is:

`SPARSE_BG`, `RLE_LOCAL`, `RAW_LOCAL`, `RAW_GLOBAL`, then scan enum order.

## Bit packing

Bits are written LSB-first inside each byte. Varuint values use unsigned LEB128
and always start on a byte boundary. The writer aligns before each varuint, and
the reader performs the same alignment before reading varuints.

## Example

```dart
import 'package:meshcore_open/helpers/mcoimg_codec.dart';

final codec = MCOImageCodec();

final image = MCOImage(
  width: 11,
  height: 11,
  paletteProfile: PaletteProfile.master32,
  pixels: List<int>.filled(11 * 11, 0),
);

final encoded = codec.encode(image, maxChars: 172);
print(encoded.text); // im:<base91Payload>

final decoded = codec.decode(encoded.text);
print(decoded.width);
print(decoded.height);
print(decoded.pixels);
```

The codec is lossless relative to the already prepared palette index array.
It does not resize, dither, or convert normal bitmap images.
