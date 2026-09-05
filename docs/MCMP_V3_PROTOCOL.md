# MCMP v3 Protocol Reference

[Russian version / Русская версия](MCMP_V3_PROTOCOL_RU.md)

This document describes the current MCMP v3 message container implemented by
MeshCore Open Advanced. It covers the binary body, its text and channel-data
transports, message signing by a MeshCore node, and signature verification by a
receiving application.

The Dart implementation in this repository is the reference for this document.
The most relevant files are:

- `lib/helpers/mcmp_app_codec.dart`
- `lib/helpers/mcmp_signature_verifier.dart`
- `lib/helpers/mesh_compressor.dart`
- `lib/helpers/channel_app_data_helper.dart`
- `lib/helpers/channel_binary_data_helper.dart`
- `lib/connector/meshcore_protocol.dart`
- `lib/connector/meshcore_connector.dart`

## Status and version history

MCMP v3 is the current format for new implementations. It adds a structured
message body, timestamps, precise reply anchors, optional sender names, and
optional Ed25519 signatures around MCMP-compressed text.

- **MCMP v1**, identified by the `mcmp:` prefix, is obsolete. Its decoder is
  disabled in the current application and its old model is not bundled.
- **MCMP v2**, identified by the `mcmp2:` prefix, is a legacy compression-only
  format. It remains readable for compatibility but should not be used for new
  protocol work.
- **MCMP v3**, identified by the `mcmp3:` prefix or the registered channel
  application subtype described below, is the format specified here.

For the current MCMP v3 format, the generic channel application envelope uses
subtype `0x02` and that subtype's wire revision `0x00`. Together they are packed
as byte `0x20`. The zero low nibble does not mean MCMP v0; it is the first wire
revision of the MCMP v3 application subtype.

## Conventions

- Multi-byte integers are unsigned and little-endian.
- Timestamps are unsigned 32-bit Unix timestamps in seconds.
- Text fields are UTF-8.
- `varuint` is an unsigned base-128 integer. Each byte carries seven low-order
  value bits; bit 7 means that another byte follows. Least-significant groups
  are written first.
- A decoder must reject malformed or truncated fields rather than attempting to
  recover them heuristically.

## MCMP v3 body

Every transport ultimately carries the same MCMP v3 body:

| Field | Size | Condition | Description |
|---|---:|---|---|
| `flags` | 1 byte | always | Container flags described below. |
| `timestamp` | 4 bytes | always | MCMP message time, Unix seconds. |
| `senderNameLength` | varuint | flag `0x04` | UTF-8 byte length of `senderName`. |
| `senderName` | variable | flag `0x04` | Sender name embedded in the body. |
| `signature` | 64 bytes | flag `0x02` | Ed25519 signature over the canonical bytes. |
| `replyAuthorNameLength` | varuint | flag `0x01` | UTF-8 byte length of the replied-to author name. |
| `replyAuthorName` | variable | flag `0x01` | Author of the replied-to message. |
| `replyTimestamp` | 4 bytes | flag `0x01` | Timestamp anchoring the replied-to message. |
| `compressedText` | remaining bytes | always | MCMP-compressed readable message text. |

### Flags

| Bit | Value | Meaning |
|---:|---:|---|
| 0 | `0x01` | A precise reply anchor is present. |
| 1 | `0x02` | A 64-byte Ed25519 signature is present. |
| 2 | `0x04` | The sender name is embedded in this body. |

All other bits are reserved. The current decoder rejects a body with any
reserved bit set.

The sender-name flag is transport-dependent. Normal channel messages keep the
displayed sender name in their outer GROUP_TEXT or GROUP_DATA envelope and do
not duplicate it in the body. Room-server messages embed the name because that
name is part of the signed author identity available after the post is relayed
by the room. Direct-contact messages currently do not embed it.

### Compressed text

`compressedText` is produced by `MeshCompressor.compressToBytes()` from the
original human-readable UTF-8 message. The current arithmetic model is
`assets/models/model-en-ru.json`; an independent arithmetic encoder or decoder
must use the same model and the same symbol/CDF construction to be byte- and
text-compatible.

The compressor may store raw UTF-8 when arithmetic coding would be larger. The
MCMP v3 container therefore treats the compressed segment as an opaque result
of the current MeshCompressor byte codec. It must be decoded before signature
verification because the signature covers the original readable text, not the
compressed representation.

At the byte-codec boundary used by v3:

- an empty segment decodes as an empty string;
- a first byte greater than `0x01` means that the complete segment is raw UTF-8;
- first byte `0x00` means a modern arithmetic stream without escape symbols;
- first byte `0x01` means a modern arithmetic stream with out-of-vocabulary
  Unicode escape symbols;
- for an arithmetic segment, bytes after the first byte contain the arithmetic
  bitstream, including its encoded EOF symbol.

The current encoder emits `[flags][arithmetic stream]` unless that result is
larger than raw UTF-8 and the first UTF-8 byte can be distinguished from the two
flag bytes. The decoder also contains legacy fallback readers, but a new v3
encoder must emit only the modern representation specified below.

### Compressor model

The model is part of the compressed-text format. Compatible implementations
must use the contents of `assets/models/model-en-ru.json`, not merely a similar
model with the same headline parameters. The current file has order `11`, a
vocabulary of `672` symbols, and `12` levels of context tables.

The model JSON has this schema:

```json
{
  "o": 11,
  "v": ["..."],
  "c": [
    {"context": {"symbol": 1}}
  ]
}
```

- `o` is the maximum context order;
- `v` is the symbol vocabulary;
- `c` is a list of `o + 1` tables; `c[n]` maps a context of length `n` to a
  table of following-symbol counts;
- a missing context or a context whose counts sum to zero does not participate
  in CDF construction.

EOF and ESC are added to the vocabulary when absent, after which the
vocabulary is sorted with Dart's standard `String.compareTo`, lexicographically
by UTF-16 code units. The current model already contains both symbols. Symbol
indexes, CDF order, and the resolution of equal frequencies depend on the
resulting vocabulary order.

Sorting is not a formality. The shipped file stores the vocabulary in code
point order rather than UTF-16 code unit order, so re-sorting genuinely changes
it. The vocabulary holds 293 symbols outside the BMP: under UTF-16 order each
of them compares by its leading surrogate from `0xD800..0xDBFF` and therefore
sorts before the symbols in `0xE000..0xFFFF`, while under code point order it
sorts after them. An implementation in a language whose strings compare by code
point (Python, Go, Rust, C++ `std::u32string`) must sort the vocabulary by
UTF-16 code units regardless. Otherwise the divergence shows up on neither
Latin nor Cyrillic text and surfaces only on messages carrying emoji or symbols
above `U+FE00`; vector 6 below covers that case.

### Special symbols and context

The compressor uses three control symbols:

| Purpose | Symbol | Value |
|---|---:|---:|
| beginning of text, BOS | `\x02` | `U+0002` |
| end of text, EOF | `\x03` | `U+0003` |
| escape for an out-of-vocabulary symbol | `\x04` | `U+0004` |

The initial context is BOS repeated `o` times. Text is traversed by Unicode
code point (`String.runes`), not by UTF-16 code units. After each symbol, the
actual source-text code point is appended to the context and only its final
`o` code points are retained. This also applies to a symbol carried through
ESC. EOF is encoded using the context left after the text.

Before encoding the first symbol, the encoder scans the entire text. If any
code point is absent from the vocabulary, `hasEscapes` is set for the whole
message. This flag simultaneously:

- becomes the first byte of the arithmetic segment;
- enables ESC sequences;
- gives ESC a non-zero base frequency in every CDF in the message.

The flag therefore cannot be determined incrementally: it changes the
intervals even for symbols that precede the first escape.

### CDF construction

Every CDF is normalized to `S = 2^20 = 1,048,576`. For a given context, the
implementation performs these steps.

1. For every order `n` from `o` down to `0`, take the final `n` code points of
   the context and look up `c[n][context]`. Let `total` be the sum of its
   counts. Skip tables with `total <= 0`.
2. Compute the active order's weight in `double`:

   ```text
   confidence = total / (total + 1.5)
   weight = (n + 1)^3 * ln(total + 1) * confidence
   ```

3. `maxMatchOrder` is the greatest active `n`. The base script boost is `32`
   when `maxMatchOrder <= 2`, and `8` otherwise.
4. Determine the context script from the rightmost non-BOS character. Common
   characters are skipped while looking for a different script. Code points
   are classified as follows:

   | Condition | Class |
   |---|---|
   | `< 0x0041` | Common |
   | `<= 0x024F` or `0x1E00..0x1EFF` | Latin |
   | `0x0400..0x052F` | Cyrillic |
   | `> 0xFFFF` | Common |
   | everything else | Other |

5. First determine the set of compatible classes. The reference
   implementation's extra script-compatibility table is empty, so the rule is:
   when the context script is known and is not Common, that class and Common
   are compatible; when the context script is unknown or Common, no set is
   created at all.

   Then assign every vocabulary symbol an initial epsilon frequency by the
   first rule that applies:
   - ESC: `500` when `hasEscapes`, otherwise `0`;
   - a set of compatible classes exists and the symbol's class belongs to it:
     the full script boost;
   - the symbol's class is Common: `max(1, scriptBoost ~/ 3)`;
   - all other symbols: `1`.

   Rule order matters. Common belongs to the compatible set whenever that set
   exists at all, so with a known context script the Common symbols receive the
   **full** boost rather than a third of it. The `max(1, scriptBoost ~/ 3)`
   rule fires only where no set was created: a context of nothing but BOS, or a
   context whose class is Common. Common is the largest class of all — it holds
   the space, the digits, every punctuation mark below `0x41`, and every code
   point above `0xFFFF`. Applying the rules in another order breaks the stream
   at the first letter that enters the context.
6. If the epsilon sum exceeds `S / 2`, replace every frequency with
   `max(1, floor(freq * (S / 2) / epsilonTotal))`, then calculate the sum
   again.
7. Distribute the remaining scale `S - epsilonTotal` among active orders. For
   each order:

   ```text
   factor = (weight / totalWeight) * (S - epsilonTotal) / total
   contribution(symbol) = floor(count(symbol) * factor)
   ```

   Contributions from all active orders are added to the symbol's epsilon.
8. Adjust the final sum to exactly `S`. Add the entire deficit to the first
   symbol with the largest frequency. To remove an excess, sort indexes by
   descending frequency, calculate `canRemove = freq - 1` for each index, and
   remove exactly `min(canRemove, remaining)`, with no clamping at zero.

   The excess-removal branch is unreachable on the normal path: step 7's
   contributions are truncated downwards, so their sum never exceeds
   `S - epsilonTotal` and the total is never above `S`. Reproduce it verbatim
   all the same, rather than as "reduce frequencies down to a floor of 1": a
   disabled ESC has frequency `0`, so `canRemove` is `-1`, and subtracting a
   negative value would raise that frequency to `1` while increasing the
   remaining deficit.
9. Build `[low, high)` intervals by cumulative sum in sorted-vocabulary order.

Steps 2, 6, and 7 in the reference implementation use IEEE-754 `double`,
`math.log()`, and truncation of positive values through `.toInt()`. Different
math libraries can theoretically move a CDF boundary by one and make the rest
of the stream incompatible. A port must be checked against the fixed vectors
below.

In the excess-removal branch, which is unreachable on the normal path,
`List.sort()` compares only frequencies and has no separate tie-break for equal
values. This does not affect normal encoding. A port should nevertheless match
the reference behavior in this defensive branch if altered arithmetic can make
the branch reachable at all. Integer weights or a new mandatory tie-break must
not be introduced into wire revision `0x00` without a separate format revision.

### Arithmetic coder

The coder uses an unsigned 32-bit state:

```text
FULL          = 2^32
HALF          = 2^31
QUARTER       = 2^30
THREE_QUARTER = 3 * 2^30
MASK          = 2^32 - 1
low           = 0
high          = MASK
pending       = 0
```

For a symbol with CDF interval `[symbolLow, symbolHigh)` and sum `total`:

```text
range = high - low + 1
high = low + floor(range * symbolHigh / total) - 1
low  = low + floor(range * symbolLow  / total)
```

After the update, renormalize the range while one of these three cases applies:

1. `high < HALF`: emit bit `0`;
2. `low >= HALF`: emit bit `1`, then subtract `HALF` from `low` and `high`;
3. `low >= QUARTER && high < THREE_QUARTER`: increment `pending`, then subtract
   `QUARTER` from `low` and `high`.

After the first or second case, emit all pending bits with the opposite value.
Then shift `low` and `high` left by one bit, set the low bit of `high`, and
mask both values to 32 bits.

Finish the stream exactly as follows: increment `pending`; emit `0` when
`low < QUARTER`, otherwise emit `1`; then emit the `pending` opposite bits.

The decoder starts with `low = 0`, `high = MASK`, and fills `value` with the
first 32 bits. Reads beyond the input array return zero. To select a symbol:

```text
range  = high - low + 1
scaled = floor(((value - low + 1) * total - 1) / range)
```

Select the first CDF interval whose `high > scaled`, update the bounds with the
same formulas, and apply symmetrical renormalization. Decoding stops at EOF.
The reference limits the loop to `4096` decoded symbols; the modern byte
decoder then re-encodes the result and requires an exact match with the input
bytes.

### Unicode escape coding

After ESC, the code point is carried by two uniform arithmetic symbols: one of
`11` variant identifiers and an offset within the selected block.

| ID | Range | Size |
|---:|---:|---:|
| 0 | `0x0400..0x04FF` | 256 |
| 1 | `0x0100..0x024F` | 336 |
| 2 | `0x2000..0x206F` | 112 |
| 3 | `0x2190..0x21FF` | 112 |
| 4 | `0x2600..0x27BF` | 448 |
| 5 | `0x1F300..0x1F5FF` | 768 |
| 6 | `0x1F600..0x1F64F` | 80 |
| 7 | `0x1F900..0x1F9FF` | 256 |
| 8 | `0xFE00..0xFE0F` | 16 |
| 9 | `0x1FA70..0x1FAFF` | 144 |
| 10 | fallback | — |

The block ID is encoded uniformly with `total = 11`. For IDs `0..9`, encode
`codepoint - blockStart` uniformly with `total = blockSize`. For ID `10`, split
the code point into three uniform 7-bit values with `total = 128`, least
significant group first:

```text
codepoint & 0x7F
(codepoint >> 7) & 0x7F
(codepoint >> 14) & 0x7F
```

### Byte-stream packing

Arithmetic bits are packed into bytes MSB-first. Unused low bits in the final
byte remain zero. The v3 byte codec retains that final byte and does not remove
trailing zero bytes.

The modern encoder selects a representation as follows:

1. Empty text becomes an empty `compressedText`.
2. Non-empty text first becomes
   `[hasEscapes:1][arithmetic stream including EOF]`.
3. If that array is strictly longer than the source UTF-8 and the first UTF-8
   byte is at least `0x02`, store the original UTF-8 instead.
4. Equal lengths keep the arithmetic form. UTF-8 beginning with `0x00` or
   `0x01` is also not selected because it cannot be distinguished from a flags
   byte.

For decoding, an empty array means empty text, a first byte greater than
`0x01` means raw UTF-8, and `0x00` or `0x01` selects the modern arithmetic
decoder.

Legacy `mcmp2:` is a separate compressor text transport. It uses the `!`, `"`,
and `#` markers, Base91, and removes trailing zero bytes before Base91. This
does not apply to `mcmp3:`: textual MCMP v3 encodes the complete body in Base91,
byte-for-byte identical to the body carried through GROUP_DATA.

### Fixed compressor vectors

Every example below uses an MCMP body without sender name, signature, or reply,
and timestamp `0x01020304`. The body's first five bytes are therefore always
`00 04 03 02 01`: zero container flags followed by the little-endian timestamp.

1. Empty text:

   ```text
   text:           ""
   compressedText: <empty>
   body hex:       0004030201
   text transport: mcmp3:XLZt$A
   ```

   This is a low-level body and transport vector. The public application helper
   `encodeTextTransport()` returns an empty input unchanged instead of creating
   an MCMP envelope, so the application's normal send path does not emit this
   payload.

2. Raw UTF-8:

   ```text
   text:           ok
   compressedText: 6f6b
   body hex:       00040302016f6b
   text transport: mcmp3:XLZt$APgD
   ```

3. Arithmetic stream without escapes:

   ```text
   text:           hello hello hello hello
   compressedText: 007d6a9f41a17e7be0
   body hex:       0004030201007d6a9f41a17e7be0
   text transport: mcmp3:XLZt$A1[?<Nuc]$VVB
   ```

4. Arithmetic stream with an escape for `U+10348`:

   ```text
   text:           hello hello hello hello 𐍈 hello hello hello hello
   compressedText: 017d7bfcf35d5311aecd94a7868487438f55afd500
   body hex:       0004030201017d7bfcf35d5311aecd94a7868487438f55afd500
   text transport: mcmp3:XLZt$A2[=K0[`SEDWTc`fvNVp/P8~fNA
   ```

5. Cyrillic, the script-boost path with a non-Latin class:

   ```text
   text:           Привет, как дела?
   compressedText: 00bfc4ad0b
   body hex:       000403020100bfc4ad0b
   text transport: mcmp3:XLZt$AT|.nTIA
   ```

6. An in-vocabulary emoji, which pins the vocabulary sort order:

   ```text
   text:           ok 👍
   compressedText: 0082b597
   body hex:       00040302010082b597
   text transport: mcmp3:XLZt$A5Fr^l
   ```

A compatible port must produce the exact `compressedText`, body, and `mcmp3:`
values above and recover the original text from each representation.

Vectors 1-4 are insensitive to vocabulary order: every symbol they encode sits
below the point where code point order diverges from UTF-16 code unit order.
Vector 6 is chosen so that the wrong vocabulary order changes the result, which
is exactly what it tests. Vector 5 covers the selection of a context script
other than Latin.

## Transports

The same MCMP v3 body can be carried in two ways:

- as Base91 text in an ordinary text message;
- as binary application data in a channel GROUP_DATA packet.

The binary form is more compact because it does not convert the body to
printable characters. The text form remains useful when the receiving client
or the repeaters along the route do not support binary application data.

### Base91 text transport

Channels using GROUP_TEXT, room-server posts, and direct-contact messages carry
the body as:

```text
mcmp3:<Base91(body)>
```

The prefix is the six ASCII bytes `mcmp3:`. Base91 uses this alphabet in the
listed order:

```text
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!#$%&()*+,./:;<=>?@[]^_`{|}~"
```

The algorithm is Joachim Henke's standard basE91; the alphabet above matches
the reference one, and the coding itself is defined as follows. The encoder
accumulates bits in a buffer `b` with a fill counter `n`, both starting at
zero:

```text
for each input byte:
  b |= byte << n
  n += 8
  if n > 13:
    v = b & 8191
    if v > 88:
      b >>= 13
      n -= 13
    else:
      v = b & 16383
      b >>= 14
      n -= 14
    emit alphabet[v % 91], then alphabet[v ~/ 91]

after the last byte, if n != 0:
  emit alphabet[b % 91]
  and, if n > 7 or b > 90, emit alphabet[b ~/ 91]
```

The decoder is symmetric. Characters are read in pairs as
`v = first + second * 91`, then `b |= v << n`, and the counter grows by `13`
when `(v & 8191) > 88` and by `14` otherwise; bytes are then pulled out of the
buffer while `n > 7`. A single trailing character `v` yields the final byte
`(b | (v << n)) & 0xFF`. A character outside the alphabet is a format error.

For a channel GROUP_TEXT message, the normal MeshCore outer text remains
`senderName: mcmp3:...`; `senderName` is not normally repeated in the MCMP body.

At the radio-protocol level this is `PAYLOAD_TYPE_GRP_TXT` (`0x05`). After the
channel payload is decrypted, its relevant logical fields are:

| Field | Size | Description |
|---|---:|---|
| `packetTimestamp` | 4 bytes | Outer channel packet time, unsigned little-endian Unix seconds. |
| `txtType` | 1 byte | MeshCore text subtype; plain text is `0x00`. |
| `text` | remaining bytes | `senderName: mcmp3:<Base91(body)>`. |

The Base91 form therefore has two layers: the normal MeshCore channel text
envelope and the printable MCMP body inside that text. The outer packet
timestamp is separate from the timestamp stored inside the MCMP body.

For a room-server message, the body does embed `senderName`. For a direct
contact the current application uses an unsigned body without an embedded
sender name, because the direct encrypted transport already identifies the
contact.

### Binary GROUP_DATA transport

At the radio-protocol level the binary form uses `PAYLOAD_TYPE_GRP_DATA`
(`0x06`). Once the channel payload is decrypted, MeshCore interprets it as:

| Field | Size | Value for MCMP v3 |
|---|---:|---|
| `data_type` | 2 bytes | `0x0120`, unsigned little-endian. |
| `data_len` | 1 byte | Number of bytes in `application_data`. |
| `application_data` | `data_len` bytes | MCO Advanced application envelope described below. |

`0x0120` is the registered MeshCore GROUP_DATA namespace for **MCO Advanced**.
The allocation is published in the official
[`MeshCore number allocations`](https://github.com/meshcore-dev/MeshCore/blob/main/docs/number_allocations.md)
table. Applications should preserve this value so MCMP v3 packets remain
compatible across clients. Development-only identifiers from `0xFF00` through
`0xFFFF` are not used by the current MCMP v3 transport.

Inside `application_data`, the MCO Advanced envelope is:

| Field | Size | Description |
|---|---:|---|
| `senderNameLength` | varuint | UTF-8 byte length of the outer sender name. |
| `senderName` | variable | Displayed channel sender name. |
| `subtypeVersion` | 1 byte | High nibble subtype `0x02`, low nibble revision `0x00`; value `0x20`. |
| `body` | remaining bytes | MCMP v3 body. |

Putting the layers together, the decrypted GROUP_DATA content is:

```text
data_type=0x0120 (u16 LE)
data_len (u8)
  senderNameLength (varuint)
  senderName (UTF-8)
  subtypeVersion=0x20 (u8)
  MCMP v3 body
```

The `data_type` tells MeshCore which application owns the packet. The high
nibble of `subtypeVersion` then tells MCO Advanced that this application packet
contains MCMP rather than another supported format. Finally, the MCMP body
carries the flags, timestamp, optional sender/signature/reply fields, and
compressed message text described earlier in this document.

A receiver that knows the `0x0120` namespace but not the subtype in the high
nibble, or not the revision in the low nibble, should keep the packet and show
a placeholder that names the namespace, the subtype and the revision, rather
than drop it: a newer client's messages then stay visible as messages, and a
stored copy of the payload lets a later version decode them. MCO Advanced
stores such a packet as an ordinary channel message with the whole
`application_data` attached and shows the placeholder in its place; it does the
same for MeshCore Open's namespace `0x0100`, whose internal layout it does not
read, naming only the namespace. Packets under any other `data_type` are
ignored.

The MCO Advanced application envelope, including its MCMP body, is limited to
165 bytes by the current end-to-end radio path. Channel encryption, the channel
hash, and the MeshCore MAC are added and checked by MeshCore itself; they are
outside the MCMP application envelope. The envelope's outer sender name is
authoritative for normal channel display and signature verification.

MeshCore describes GROUP_DATA itself as an unverified group datagram: the base
channel transport does not identify an individual author. When the signed flag
is present, MCMP's embedded Ed25519 signature provides the separate author
verification described below.

## Encoding and decoding

### Encoding

1. Select the message timestamp in Unix seconds.
2. Decide whether the body needs a sender name and/or precise reply anchor.
3. Compress the original readable text with `MeshCompressor.compressToBytes()`.
4. Build the exact flags byte.
5. If signing is enabled, build the canonical signing bytes specified below,
   ask the node to sign them, and set the signed flag only when a valid 64-byte
   signature was returned.
6. Serialize the body fields in their defined order.
7. Wrap the body in Base91 text or in the channel application envelope.

The current v3 sender uses the structured container whenever MCMP v3 applies;
it does not require the container to be smaller than plain UTF-8. If signing is
requested but the node cannot produce a signature, normal messages may be sent
as unsigned MCMP v3. Some application-level commands deliberately fall back to
plain text instead.

### Decoding

1. Remove the `mcmp3:` prefix and Base91-decode the body, or extract it from the
   `0x0120` / `0x20` channel application envelope.
2. Read and validate the flags byte.
3. Read the timestamp and every conditional metadata field in wire order.
4. Treat all remaining bytes as `compressedText` and decode them with the
   matching MeshCompressor model.
5. Preserve the decoded timestamp, signature, sender name, and reply anchor as
   message metadata.
6. If a signature is present, verify it using the original decoded text and the
   rules below.

## Signatures and verification

### What a valid signature binds

MCMP v3 uses Ed25519. A valid signature binds all of the following values:

- the MCMP v3 signing domain;
- whether the destination is a channel or room server;
- a 32-byte destination binding;
- the sender name;
- the MCMP timestamp;
- the exact container flags;
- the complete reply author and timestamp, when present;
- the original uncompressed human-readable message text.

The node signs with its private identity key. The application sends only the
canonical bytes to the node and receives a 64-byte signature; the private key
is never exported to the application.

Transport observations such as local `receivedAt`, route/path bytes, hop count,
SNR, RSSI, retransmission count, and the outer radio packet timestamp are not
part of the canonical MCMP data. They remain separate message metadata.

### Canonical signing bytes

The canonical byte string is the exact concatenation below. There is no length
prefix around the domain, destination binding, or final message text.

| Field | Encoding |
|---|---|
| `domain` | UTF-8 bytes of `MCOAPP:MCMP:SIGNED:v3` |
| `context` | one byte: `0x01` for channel, `0x02` for room |
| `binding` | exactly 32 bytes, as defined below |
| `senderNameLength` | varuint of UTF-8 byte length |
| `senderName` | UTF-8 bytes |
| `timestamp` | unsigned 32-bit little-endian Unix seconds |
| `flags` | the exact body flags byte |
| `replyAuthorNameLength` | varuint, only when reply flag is set |
| `replyAuthorName` | UTF-8 bytes, only when reply flag is set |
| `replyTimestamp` | unsigned 32-bit little-endian, only when reply flag is set |
| `text` | original uncompressed UTF-8 message bytes through end of input |

The canonical sender name is always present even when the channel body omits
the optional embedded name. The verifier must reconstruct the exact flags byte
from the decoded body, including the signed and sender-name bits.

### Destination bindings

For a **channel**, the binding is:

```text
HMAC-SHA256(key = channel PSK, message = UTF8("MCOAPP:MCMP:BIND:v3"))
```

The complete 32-byte HMAC result is used.

For a **room server**, the binding is the room's complete 32-byte public key,
unchanged.

These bindings keep an otherwise identical signed message associated with the
conversation for which it was created. The binding bytes are reconstructed by
the verifier and are not added separately to the transmitted MCMP body.

In both contexts the binding is 32 bytes long in the canonical data given to
Ed25519, but it occupies **0 bytes in the transmitted MCMP body**. The sender
and receiver independently reconstruct it from information they already have:
the channel PSK or the room server's full public key. Only the resulting
64-byte signature is stored in the body and sent over the network.

### Requesting a signature from the node

The application serializes signing sessions because the current firmware uses
one global signing buffer. The BLE/USB/TCP companion exchange is:

1. Send `CMD_SIGN_START` (`33`).
2. Await `RESP_CODE_SIGN_START` (`19`) or `RESP_CODE_ERR` (`1`). A sufficiently
   long start response includes the node's maximum accepted signing-data size.
3. Split the canonical bytes into chunks of at most 175 bytes. For each chunk,
   send `CMD_SIGN_DATA` (`34`) followed by the chunk and await `RESP_CODE_OK`
   (`0`) or `RESP_CODE_ERR`.
4. Send `CMD_SIGN_FINISH` (`35`).
5. Await `RESP_CODE_SIGNATURE` (`20`) followed by at least 64 signature bytes,
   or `RESP_CODE_ERR`. The application reads the first 64 bytes as the Ed25519
   signature.

The application-side safety limit for canonical signing data is 8192 bytes.
The current implementation makes at most five attempts, with a three-second
deadline per attempt, so an older node without the signing commands cannot
block message sending indefinitely.

### Channel verification

For a signed channel message, the receiving application:

1. Takes the authoritative displayed sender name from the outer GROUP_TEXT or
   GROUP_DATA envelope.
2. If the MCMP body also contains a sender name, requires its trimmed value to
   equal the trimmed outer name. A mismatch is `invalid`.
3. Finds known contacts whose trimmed names exactly match that outer name.
4. Reconstructs the channel binding and canonical bytes from the decoded
   message.
5. Attempts Ed25519 verification with each matching contact's complete 32-byte
   public key.
6. Reports `valid` only when one of those keys verifies the signature. The
   successfully verified full key may then be shown as a fingerprint.

Name comparison is case-sensitive after trimming leading and trailing
whitespace. Multiple contacts with the same name are recorded as a name
collision, but verification can still identify the particular full key that
signed the message.

### Room-server verification

For a signed room-server post, the receiving application:

1. Requires an embedded MCMP sender name. A signed room body without one is
   `invalid`.
2. Uses the original author's public-key prefix supplied by the room post to
   select known full contact keys.
3. Reconstructs the canonical bytes with room context and the room's full
   32-byte public key as the destination binding.
4. Attempts Ed25519 verification against the selected full contact keys.
5. Also requires the verified contact's trimmed name to equal the embedded
   signed sender name.
6. Reports `valid` and exposes the fingerprint only when both signature and
   name checks succeed.

The current room protocol normally supplies a four-byte author-key prefix. The
prefix narrows the candidates; Ed25519 verification against the complete key is
what confirms the signer.

### Direct-contact messages

Current direct-contact MCMP v3 messages are not Ed25519-signed. Their identity
status is `transportAuthenticated`, because the encrypted direct-contact
transport already associates the message with the selected contact. The MCMP
body still provides v3 compression, timestamp, and reply metadata.

### Verification statuses

| Status | Meaning |
|---|---|
| `none` | The message is not an MCMP v3 message requiring this status. |
| `unsigned` | MCMP v3 body decoded successfully but contains no signature. |
| `valid` | Ed25519 verification and all applicable sender-name checks passed. |
| `invalid` | Ed25519 verification failed for the available candidates, or a required sender-identity consistency check failed. |
| `unverifiable` | A signature exists, but no suitable known full contact key is available. |
| `transportAuthenticated` | Direct-contact identity is provided by its encrypted transport rather than an MCMP Ed25519 signature. |

A key fingerprint must be displayed only for `valid`, when the verifier has
returned the exact full key that passed verification. Signature bytes may be
preserved for diagnostics independently of the verification result.

## Timestamps, ordering, and replies

The MCMP timestamp is part of the signed canonical data. It is distinct from
the application's local receive time and, for transports that provide one,
from the outer packet timestamp.

- Channel GROUP_TEXT has an outer packet timestamp and an MCMP timestamp.
- MCMP GROUP_DATA does not provide a separate protocol packet timestamp to the
  application, so the decoded MCMP timestamp becomes the message timestamp.
- A room server supplies its own outer stored-post timestamp, while the MCMP
  body retains the sender's signed timestamp.
- `receivedAt` is assigned locally and orders persisted history. It is not
  signed and is not displayed as the author's message time.

For an incoming message, the application compares the MCMP timestamp with the
model's packet/post timestamp. If they differ by more than 30 minutes, it
displays a separate red clock diagnostic. This timestamp comparison is
independent of signature validity. Message details may also show the MCMP
timestamp whenever the two second values differ.

Structurally, a reply anchor consists of `replyAuthorName` and
`replyTimestamp`; both fields must be present together. When the enclosing
message has a valid signature, the anchor is covered by that signature. Anchor
resolution depends on the transport:

- in channels and room-server conversations, the trimmed author name must
  match exactly, while `replyTimestamp` must equal either the candidate's outer
  timestamp or its MCMP timestamp;
- in a direct-contact conversation, `replyAuthorName` is transmitted as an
  empty string because both participants are already known, and the original
  message is resolved by exact timestamp matching alone.

The current approximate-match tolerance is zero. If the original message is
unavailable, the reply remains readable. Channel and room-server replies also
retain the author name as a mention, but no concrete history record is linked.

## Size overhead

Excluding compressed text, the MCMP body has these fixed and variable costs:

- unsigned body without sender or reply: 5 bytes;
- signed body without sender or reply: 69 bytes;
- embedded sender: `varuint(UTF8 length) + UTF8 sender bytes`;
- reply anchor: `varuint(UTF8 author length) + UTF8 author bytes + 4 bytes`;
- binary channel envelope: `varuint(UTF8 sender length) + UTF8 sender bytes + 1 byte`;
- text transport: six `mcmp3:` characters plus Base91 expansion of the entire
  body.

The 32-byte destination binding and signing domain are included in the bytes
given to Ed25519 but are reconstructed during verification, so they consume no
radio payload space. The signature itself always consumes 64 body bytes.

## Decoder validation checklist

A conforming decoder should:

- reject unknown flag bits;
- keep a `0x0120` envelope whose subtype or revision it does not know and show
  it as a placeholder naming both, rather than drop it;
- reject truncated fixed-width integers and signatures;
- reject a varuint that is truncated or continues beyond five bytes;
- reject lengths that exceed the remaining body;
- reject invalid UTF-8 in metadata fields;
- require reply author and reply timestamp as one inseparable pair;
- decode the compressed segment with the matching MCMP model;
- preserve the exact decoded metadata needed to reconstruct canonical bytes;
- keep decoding separate from signature status: a readable message can be
  unsigned, invalid, or unverifiable;
- never associate a fingerprint with a message unless its full key actually
  passed verification.

## Conformance references

Container, transport, reply, and malformed-input coverage lives in
`test/mesh_compressor_test.dart`. Channel and room Ed25519 verification cases
live in `test/helpers/mcmp_signature_verifier_test.dart`. These tests exercise
the same public helpers referenced at the beginning of this document and are a
useful starting point for cross-runtime fixtures.

## Implementations

- **MeshCore Open Advanced** (this repository): `lib/helpers/mesh_compressor.dart`,
  `lib/helpers/mcmp_app_codec.dart` and `lib/helpers/mcmp_signature_verifier.dart`,
  the reference for the body, both transports, signing and verification.
- **South Edition companion firmware** (Luchik, `src/helpers/mcmp/` in that
  fork of MeshCore): a metadata-only reader. It recognises the three text
  prefixes and the binary envelope and parses the v3 header — flags,
  timestamp, embedded sender name, signature presence, reply anchor — without
  decompressing the text or verifying the signature, since the node holds
  neither the model nor the contact keys; its display shows a placeholder with
  the sender. It is a useful check that a header stays readable on its own:
  the compressed text is the only field it cannot interpret.
