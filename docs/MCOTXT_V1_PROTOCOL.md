# MCOtxt v1 Protocol Reference

[Russian version / Русская версия](MCOTXT_V1_PROTOCOL_RU.md)

This document describes the MCOtxt v1 text codec implemented by MeshCore Open
Advanced: the bitstream, the static language models it predicts from, the
length-prefixed frame that embeds a stream in a byte container, the application
container that adds a timestamp, sender name and reply anchor, and the two
transports that carry that container over the mesh.

The Dart implementation in this repository is the reference for this document;
where the two disagree, the code wins. The most relevant files are:

- `lib/MCOtxt/mcotxt_codec.dart` — header, token tree, planner, decoder
- `lib/MCOtxt/mcotxt_frame.dart` — length-prefixed frame for byte containers
- `lib/MCOtxt/models/mcotxt_model.dart` — model shape and constraints
- `lib/MCOtxt/models/punctuation.dart` — the punctuation page
- `lib/MCOtxt/models/mcotxt_model_registry.dart` — language ids, normalisation
- `lib/MCOtxt/models/generated/v1/model_*.dart` — the bundled tables
- `lib/helpers/mcotxt_app_codec.dart` — application container, `mct:` transport
- `lib/helpers/channel_app_data_helper.dart` — MCO Advanced channel envelope
- `lib/helpers/channel_binary_data_helper.dart` — GROUP_DATA routing
- `lib/connector/meshcore_protocol.dart` — frame builders and size limits
- `tools/MCOtxt/` — model trainer, manifest and verification scripts

## Status and version history

MCOtxt v1 is the current and only version. Unlike MCMP, which compresses with
an arithmetic coder driven by a large n-gram model, MCOtxt predicts the next
letter from a static TOP-4 table per language and spends a variable-length
token on each character. A whole model is a few hundred bytes, so the same
tables are exported as a C header for microcontroller ports.

- The codec version is the first header field of every stream (`1` today) and
  the model generation the second (`0` today). Both use the escape described
  under [Header](#header), so neither is limited to three bits.
- The application container is MCO Advanced channel subtype `0x03`, wire
  revision `0x01`, packed as the byte `0x31`. Its text transport uses the
  prefix `mct:`.
- Language tables are identified by a SHA-256 wire hash recorded in
  `tools/MCOtxt/generated/model_manifest.json` together with the current
  `modelGeneration`. The manifest is **not frozen
  yet** (`"frozen": false`): the bundled English, Russian and French tables can
  still be regenerated before the freeze, and a regenerated table changes its
  hash. After the freeze a table may only change under a new language id or a
  new codec version.
- German, Italian, Ukrainian and Belarusian have reserved language ids but no
  tables. A decoder that meets one of them rejects the stream.

## Conventions

- The MCOtxt stream is a sequence of bits packed most-significant bit first
  into bytes; a bit field of `n` bits is written high bit first. The last byte
  is padded with zero bits.
- A stream is **not self-terminating**. Padding bits read back as TOP4 tokens,
  so every container must carry the exact bit count of the stream, never a
  byte count. The frame in this document is the agreed way to do that.
- Multi-byte integers in the application container are unsigned and
  little-endian. Timestamps are unsigned 32-bit Unix seconds.
- `varuint` is an unsigned base-128 integer: seven low-order value bits per
  byte, bit 7 set when another byte follows, least-significant group first. A
  decoder rejects a varuint that continues beyond five bytes.
- Text is Unicode; UTF-8 is used wherever raw bytes appear.
- A decoder rejects malformed or truncated input rather than recovering from
  it heuristically.

## Layers

```text
transport        GROUP_TEXT "Name: mct:<Base91>"   |   GROUP_DATA 0x0120 envelope
container        flags | [timestamp] | [senderName] | [reply] | text
string           mode byte (0 = MCOtxt frame, 1 = UTF-8)
frame            varuint(bitLength) | ceil(bitLength / 8) bytes
stream           version | generation | language header | tokens
```

An implementation that only needs to embed text in its own format (an image
caption, a form field) uses the stream and the frame and stops there. The
container and transports are how MeshCore Open Advanced sends chat messages.

## The MCOtxt v1 stream

### Header

| Bits | Field | Values |
|---:|---|---|
| 3 (+8) | version | Codec version, escaped field; `1` today. `0` and every other value: `unknownVersion`. |
| 3 (+8) | generation | Model-set generation, escaped field; `0` today. See [Model generations](#model-generations). |
| 3 | language A | `0`–`6` inline language id; `7` = an extended header follows. |
| 3 | language B | `0`–`6` inline language id; `7` = no second language. |

**Escaped fields.** `version` and `generation` share one shape: a value from
`0` to `6` is written in three bits; `7` and above are written as the three-bit
escape `7` followed by eight bits holding `value − 7`. The range is therefore
`0`–`262`, and every value has exactly one encoding, since the escape cannot
produce a value below `7` and the short form cannot reach `7`.

With inline fields and an inline language A the header is 12 bits long; every
escape adds eight bits. Language A is the active language when decoding
starts; language B, when present, is the partner of `TOGGLE_LANGUAGE`. Both
must be languages the selected generation has tables for, otherwise the
decoder reports `modelUnavailable`. A and B must differ.

When the language A field is `7`, the next 3 bits select an extended header
format:

| Format | Meaning | Header length |
|---:|---|---:|
| `0` | Language pair as two 8-bit global ids: A (must not be `255`), then B (`255` = none). | 28 bits |
| `1` | `RAW_UTF8` message mode: 4 zero padding bits follow, then the whole text as UTF-8 bytes. | 16 bits |
| `2`–`7` | Reserved: `unsupportedExtendedHeader`. | — |

Today every language id fits the inline field, so the reference encoder never
emits format `0`; the decoder accepts it for ids `0`–`6` and rejects unknown
ids. Format `1` is how a message that compresses badly is sent: see
[RAW_UTF8 message mode](#raw_utf8-message-mode).

### Token tree

After the header the stream is a sequence of tokens. Every token starts with a
prefix code; all prefixes except TOP4 begin with `1`.

| Code | Total bits | Token |
|---|---:|---|
| `00` | 2 | `TOP4` rank 0 |
| `010` | 3 | `TOP4` rank 1 |
| `0110` | 4 | `TOP4` rank 2 |
| `0111` | 4 | `TOP4` rank 3 |
| `10` + 5-bit id | 7 | `PRIMARY` literal: symbol `primary[id]` of the active language |
| `110` + 5-bit id | 8 | `PUNCTUATION`: entry `id` of the punctuation page |
| `1110` + 5-bit id | 9 | `EXTENSION` literal: symbol `extension[id]` of the active language |
| `11110` | 5 | `SHIFT`: one-symbol case inversion, applies to the next language symbol |
| `111110` | 6 | `TOGGLE_LANGUAGE`: swap the active language between A and B |
| `111111` + 3-bit sub-opcode | 9 + payload | extended control, see below |

Extended controls:

| Sub-opcode | Name | Payload | Total bits |
|---:|---|---|---:|
| `0` | `SWITCH_OTHER_LANGUAGE` | 8-bit global language id | 17 |
| `1` | `RESET_CONTEXT` | none | 9 |
| `2` | `UTF8_RUN` | 5-bit `n − 1`, then `n` UTF-8 bytes (`1 ≤ n ≤ 32`) | 14 + 8·n |
| `3` | `TOGGLE_CASE_MODE` | none | 9 |
| `4`–`7` | reserved | — | `unknownExtendedControl` |

A `TOP4` token names a rank in the four-entry prediction row selected by the
current context; a `PRIMARY` or `EXTENSION` literal names a symbol of the
active language directly. An id at or beyond the size of the table it indexes
is `invalidPrimaryId`, `invalidExtensionId`, `invalidPunctuationId` or
`invalidTop4Reference`.

`SWITCH_OTHER_LANGUAGE` makes any available language the active one without
touching the A/B pair. Its id is the global id (`0`–`6` today); `255` and
unknown ids are `invalidOtherLanguage`, a known language without tables is
`modelUnavailable`. `TOGGLE_LANGUAGE` requires a language B
(`toggleWithoutLanguageB`) and the active language to be A or B.

### Prediction context

The decoder keeps a context that selects the TOP4 row:

| Context | Row used by `TOP4` |
|---|---|
| `START` | `startTop4` of the active language |
| `AFTER_PUNCT` | `punctStartTop4` of the active language |
| `SYMBOL(prev)` | `top4[prev]`, the row of the previous language symbol |

Transitions:

- Decoding starts in `START`.
- A language symbol (from `TOP4`, `PRIMARY` or `EXTENSION`) moves to
  `SYMBOL(symbol)`. The symbol is always the lowercase table entry, whatever
  case was output.
- A `PUNCTUATION` token: SPACE (entry 0) keeps `SYMBOL(prev)` if that was the
  context and otherwise gives `START`; LF (entry 31) gives `START`; every other
  entry gives `AFTER_PUNCT`.
- `TOGGLE_LANGUAGE`, `SWITCH_OTHER_LANGUAGE`, `RESET_CONTEXT` and `UTF8_RUN`
  give `START`.
- `SHIFT` and `TOGGLE_CASE_MODE` leave the context unchanged.

SPACE is both entry 0 of the punctuation page and a symbol of every language
(always `primary[0]`). An encoder may use either; as a language symbol it is
predicted and updates the context to `SYMBOL(SPACE)`, as punctuation it costs
8 bits and keeps the previous context.

### Case

Models hold lowercase symbols only, together with an uppercase-to-lowercase
map. Two controls reconstruct case:

- `SHIFT` inverts the case of exactly the next language symbol.
- `TOGGLE_CASE_MODE` flips a persistent caps mode, initially off.

A symbol with an uppercase form is output uppercase when `capsMode XOR shift`
is true. Digits, SPACE and other symbols without an uppercase form are never
affected by caps mode, and `SHIFT` in front of one of them is `invalidShift`.
Further `invalidShift` cases: two `SHIFT` tokens in a row, a `SHIFT` followed by
anything other than a language symbol, and a stream that ends after `SHIFT`.

### UTF8_RUN

`UTF8_RUN` carries 1 to 32 bytes of raw UTF-8 for characters no available
model or the punctuation page can represent. The bytes must form complete,
valid UTF-8 (`invalidUtf8Fallback` otherwise); a run never splits a code
point. The active language is unchanged, the context becomes `START`. The
reference encoder uses it only as a fallback, never for text the tables can
express.

### RAW_UTF8 message mode

When the whole message is smaller as plain UTF-8, the encoder emits the 16-bit
header (`001` version, `000` generation, `111`, `001` format and four zero
padding bits) followed by the UTF-8 bytes of the normalised text. An escaped
version or generation adds eight bits, so the payload stays byte-aligned. The
decoder requires the padding bits to be zero, the remaining bit count to be a
multiple of eight, and the bytes to be valid UTF-8 (`invalidRawUtf8`). No
language tables are involved: the generation is read and reported but never
checked, so a `RAW_UTF8` message from a newer generation still decodes.

### Punctuation page

The page is shared by all languages and fixed for v1:

| Id | Char | Id | Char | Id | Char | Id | Char |
|---:|---|---:|---|---:|---|---:|---|
| 0 | SPACE `U+0020` | 8 | `—` `U+2014` | 16 | `„` `U+201E` | 24 | `\` `U+005C` |
| 1 | `.` | 9 | `_` | 17 | `‘` `U+2018` | 25 | `@` |
| 2 | `,` | 10 | `'` | 18 | `’` `U+2019` | 26 | `#` |
| 3 | `!` | 11 | `"` | 19 | `(` | 27 | `%` |
| 4 | `?` | 12 | `«` `U+00AB` | 20 | `)` | 28 | `&` |
| 5 | `:` | 13 | `»` `U+00BB` | 21 | `[` | 29 | `+` |
| 6 | `;` | 14 | `“` `U+201C` | 22 | `]` | 30 | `=` |
| 7 | `-` | 15 | `”` `U+201D` | 23 | `/` | 31 | LF `U+000A` |

Digits are deliberately absent: they are language symbols in every model.

### Input normalisation

Before encoding, the reference implementation:

1. replaces `CR LF` and lone `CR` with `LF`;
2. composes a fixed set of base + combining-mark pairs into their precomposed
   form: `a A` + grave or circumflex; `c C` + cedilla; `e E` + grave, acute,
   circumflex or diaeresis; `i I` + grave, circumflex or diaeresis; `o O` +
   circumflex or diaeresis; `u U` + grave, circumflex or diaeresis; and the
   Cyrillic pairs `е Е` + diaeresis (`ё Ё`), `и И` + breve (`й Й`), `і І` +
   diaeresis (`ї Ї`), `у У` + breve (`ў Ў`).

This is a partial NFC: only the listed pairs are composed. The decoder returns
the normalised text, which is what a sender should treat as the text actually
sent.

### Encoder

The reference encoder is a dynamic-programming search over positions ×
(active language, context); its output is the smallest stream it can find, not
a normative sequence of decisions. A conforming encoder may produce any stream
that decodes to the same normalised text. What the reference does:

- encodes with a fixed language pair when the application supplies one: the
  UI language as A and EN as B, or EN and RU when the UI is English, with a
  UI language that has no model replaced by RU when it is written in
  Cyrillic and by EN otherwise; without such a pair it tries every available language
  as A with every other available language or none as B, and keeps the
  candidate with the most encoded characters, then the fewest bits, then the
  fewest language switches, then the fewest declared languages, then the
  lowest A id, then the lowest B id;
- for each character considers the punctuation page, the active model, the
  toggled model (with `TOGGLE_LANGUAGE`) and every other model (with
  `SWITCH_OTHER_LANGUAGE`); `UTF8_RUN` is considered only when nothing else
  can represent the character, and then greedily covers the following
  unsupported characters up to 32 bytes;
- plans case separately with a two-state search over the caseable symbols
  (9 bits per `TOGGLE_CASE_MODE`, 5 per `SHIFT`), because case never changes
  the lowercase symbol the predictions run on;
- finally compares the MCOtxt stream with the `RAW_UTF8` candidate by padded
  byte count, then by bit count, and keeps MCOtxt on a full tie.

`MCOtxtCodec.encodeToBitLimit` binary-searches the longest text prefix whose
stream fits a bit budget, for containers with a fixed capacity.

### Decoder rules

A decoder reads tokens until the declared bit count is exhausted. It rejects:

- a version other than `1`; a generation this build has no tables for
  (`unsupportedModelGeneration`, checked after the header and never in
  `RAW_UTF8`); an unknown or unavailable language; a reserved extended header
  format or sub-opcode;
- a table id beyond the table it indexes;
- `TOGGLE_LANGUAGE` without a language B or outside the A/B pair;
- any `SHIFT` misuse listed above;
- invalid UTF-8 in `UTF8_RUN` or `RAW_UTF8`, non-zero `RAW_UTF8` padding, a
  `RAW_UTF8` payload that is not byte-aligned;
- a stream that ends inside a token (`unexpectedEnd`).

The error codes are `MCOtxtCodecError` in `lib/MCOtxt/mcotxt_errors.dart`.

## Language models

### Model generations

The `generation` header field names the complete set of tables a stream was
encoded with, all seven language ids at once rather than a single language.
The rules that move it:

- regenerating a table that already exists changes its wire hash and starts a
  new generation;
- adding tables to a reserved language (German, Italian, Ukrainian,
  Belarusian) keeps the generation, since no existing stream changes meaning;
- changing the punctuation page, the token tree, the prediction contexts or
  the table limits is a new codec version, not a new generation. Generations
  are numbered within a version, and the pair (version, generation) identifies
  the table set exactly.

A decoder keeps the sets it knows (`MCOtxtModelSet` in
`lib/MCOtxt/models/mcotxt_model_registry.dart`, generation `0` today) and
resolves the header's generation to one of them. A generation it does not have
is `unsupportedModelGeneration`, distinct from `unknownLanguage` and
`modelUnavailable`, so a client can tell "update me" from "bad data". An
encoder writes the latest generation it has unless asked for a specific one.
The current generation is recorded as `modelGeneration` in the model manifest.

### Language identifiers

| Wire id | Language | Tables in this build |
|---:|---|---|
| 0 | English | yes |
| 1 | Russian | yes |
| 2 | French | yes |
| 3 | German | reserved, none |
| 4 | Italian | reserved, none |
| 5 | Ukrainian | reserved, none |
| 6 | Belarusian | reserved, none |
| 7 | — | inline header: extended header / no language B |
| 255 | — | global id: no language B |

For ids `0`–`6` the global id equals the wire id.

### Model tables

A model consists of:

| Table | Size | Content |
|---|---|---|
| `primarySymbols` | 1–32 code points | Symbols reachable by 7-bit `PRIMARY` literals. Entry 0 is always SPACE. |
| `extensionSymbols` | 0–32 code points | Symbols reachable by 9-bit `EXTENSION` literals. |
| `startTop4` | 4 symbols | Prediction row for the `START` context. |
| `punctStartTop4` | 4 symbols | Prediction row for the `AFTER_PUNCT` context. |
| `top4` | 4 symbols per model symbol | Prediction row for `SYMBOL(prev)`, indexed by the position of `prev` in `primary ++ extension`. |
| `uppercaseToLowercase` | map | Uppercase code point → lowercase symbol. Every value must be a model symbol. |

Every prediction row holds four distinct model symbols. Primary and extension
never overlap, and apart from SPACE no model symbol is on the punctuation page.
The training alphabet of a language is SPACE, its lowercase letters and the
ASCII digits `0`–`9`; the trainer puts SPACE and the 31 letters that most often
miss the TOP-4 rows into `primary` (they save 2 bits per miss as 7-bit
literals) and the rest into `extension`. **The order of both lists is part of
the wire format**: it defines the literal ids.

### Bundled v1 tables

These tables form generation `0`. Symbol order below is the literal id order;
`␠` is SPACE. The complete TOP-4 rows are in
`tools/MCOtxt/generated/<lang>/model_<lang>.dart` and `.h` and are covered by
the wire hash.

**English, id 0**, hash `55988b3bb2a000adf6e768a8541df5a25fec1628b4ec661a10b577e3af8b3770`

```text
primary   (0..31)  ␠ o d a i l r m y t c p w s f g h b n e k u v x 1 j 3 2 8 4 z 5
extension (0..4)   q 6 7 9 0
START      h m t i
AFTER_PUNCT ␠ s t m
uppercase  A–Z → a–z
```

**Russian, id 1**, hash `d123c4978a635bf1b26fe37261b7e96a0206b3ba15b2a80542e560f00d1eb193`

```text
primary   (0..31)  ␠ с м у р к е л н и я т б д в г ч а з о ы п й х ж ш ю ь э щ ц ф
extension (0..11)  1 2 3 ё 4 5 8 7 6 9 0 ъ
START      п н ␠ д
AFTER_PUNCT ␠ т 1 к
uppercase  А–Я, Ё → а–я, ё
```

**French, id 2**, hash `910c5821a202a9b35313a9b939355f09d1c4293fe2ed246fed0123639d379ccb`

```text
primary   (0..31)  ␠ u t c m r l o i e a s n v p é j b d g h f q y ç à k 2 x 1 5 z
extension (0..20)  4 w 3 7 6 è 0 8 ê 9 ô î ù û ü ë œ â æ ï ÿ
START      b s t c
AFTER_PUNCT ␠ a e n
uppercase  A–Z and À Â Æ Ç É È Ê Ë Î Ï Ô Œ Ù Û Ü Ÿ → lowercase
```

The reserved languages are defined in the trainer with these lowercase
alphabets (plus SPACE and digits) and will get tables under their reserved
ids: German `a–z ä ö ü ß`, Italian `a–z à è é ì í ò ó ù ú`, Ukrainian
`абвгґдеєжзиіїйклмнопрстуфхцчшщьюя`, Belarusian
`абвгдеёжзійклмнопрстуўфхцчшыьэюя`.

### Wire hash and manifest

The wire hash of a model is the SHA-256 of a canonical JSON document with the
keys sorted, no whitespace, UTF-8, `ensure_ascii` off:

```json
{"codecVersion":1,"language":"ru","languageId":1,
 "primarySymbols":[...],"extensionSymbols":[...],
 "startTop4Indexes":[...],"punctStartTop4Indexes":[...],"top4Indexes":[...],
 "uppercaseMap":[{"lowercaseSymbolIndex":i,"uppercaseCodepoint":u},...]}
```

Index tables refer to positions in `primary ++ extension`; `top4Indexes` is
the flattened `4 × symbolCount` list; `uppercaseMap` is sorted by uppercase
code point. The hash is embedded in the generated Dart and C files and listed
in `model_manifest.json`; `tools/MCOtxt/verify_runtime_models.py` checks that
the three agree. Two implementations that share a hash decode each other's
streams for that language.

## Frame

A byte container embeds a stream as a **frame**:

| Field | Size | Description |
|---|---:|---|
| `bitLength` | varuint | Number of significant bits in the stream. |
| `stream` | `ceil(bitLength / 8)` bytes | The stream, last byte zero-padded. |

`bitLength` is 1 byte up to 127 bits and 2 bytes up to 16 383 bits. The frame
is implemented by `MCOtxtFrame` in `lib/MCOtxt/mcotxt_frame.dart`; the
application container below uses it for every MCOtxt string, and new byte
containers should too. A bit-packed host format does not need the byte padding
and keeps only the rule: the bit count is written ahead of the bits. The
MCOimg v4 text figure embeds a stream that way, as
`bitCompactUint(bitLength)` followed by exactly that many bits, re-packed
into that format's least-significant-bit-first order.

## Application container

The container is the body carried by both transports.

| Field | Size | Condition | Description |
|---|---:|---|---|
| `flags` | 1 byte | always | Container flags below. |
| `timestamp` | 4 bytes | flag `0x04` clear | Sender's message time, Unix seconds. |
| `senderName` | string | flag `0x02` | Sender name embedded in the body. |
| `replyAuthorName` | string | flag `0x01` | Author of the replied-to message. |
| `replyTimestamp` | 4 bytes | flag `0x01` | Timestamp anchoring the replied-to message. |
| `text` | string | always | The message text. |

### Flags

| Bit | Value | Meaning |
|---:|---:|---|
| 0 | `0x01` | A reply anchor is present: author string and 4-byte timestamp. |
| 1 | `0x02` | A sender name string is present. |
| 2 | `0x04` | The timestamp is inherited from the transport and the 4-byte field is absent. |

Reserved bits are rejected. Bytes left after the text string are rejected
("trailing bytes").

### Strings

Every string field starts with a mode byte:

| Mode | Layout |
|---:|---|
| `0x00` | MCOtxt frame: `varuint(bitLength)` + stream bytes. |
| `0x01` | UTF-8: `varuint(byteLength)` + bytes. |

Other modes are rejected. The reference encoder writes `text` in mode `0x00`
always (the codec's own `RAW_UTF8` mode covers text that does not compress)
and picks the shorter of the two for names, preferring MCOtxt on a tie. A
decoder accepts either mode in any string field.

### Timestamp and sender name

With flag `0x04` the container timestamp is the outer packet timestamp of the
transport that carried it; the reference text transport always sets `0x04`,
the binary transport never does. The application shows the container timestamp
as the message time for GROUP_DATA, and compares it with the packet timestamp
where both exist.

The sender name is present only where the transport carries none of its own:
room-server posts and the binary GROUP_DATA envelope (which then leaves its
outer name empty). A channel text message keeps the name in the outer
`Name: text` layer, and a direct message needs none. A decoder reports a name
only when flag `0x02` is set; it must not fill the field from the transport.

### Reply anchor

An anchor is the trimmed author name plus the timestamp of the replied-to
message, both required together. In channels and rooms the author name must
match and the timestamp must equal the candidate's outer or container
timestamp; a direct message carries an empty author name and matches by
timestamp alone. The application's tolerance is 0 seconds. An unresolved
anchor leaves the message readable and keeps the author as a mention.

## Transports

### Base91 text transport

Channels using GROUP_TEXT, room-server posts and direct messages carry:

```text
mct:<Base91( subtypeVersion 0x31 ‖ container )>
```

Unlike `mcmp3:`, the Base91 payload starts with the subtype byte, so the
text transport is self-identifying: a decoder checks subtype `0x03` and treats
a revision other than `0x01` as an unsupported version. Base91 is Joachim
Henke's basE91 with the standard alphabet in this order:

```text
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!#$%&()*+,./:;<=>?@[]^_`{|}~"
```

The coder is the one specified in `docs/MCMP_V3_PROTOCOL.md`; a character
outside the alphabet is a format error. Leading whitespace before `mct:` is
tolerated; the prefix alone with nothing after it is not a payload.

The outer MeshCore text stays `senderName: mct:...` for a channel. Container
flags on this transport are therefore:

| Conversation | Flags | Body fields |
|---|---:|---|
| channel | `0x04` (+ `0x01` for a reply) | text; reply author is the quoted sender's name |
| room server | `0x06` (+ `0x01`) | sender name, text |
| direct contact | `0x04` (+ `0x01`) | text; a reply author is transmitted as the empty string |

### Binary GROUP_DATA transport

On the radio this is `PAYLOAD_TYPE_GRP_DATA`. The companion command is
`CMD_SEND_CHANNEL_DATA` (`62`):

```text
[62][channelIndex][pathLength or 0xFF = flood][pathBytes][dataType u16 LE][payload]
```

and the node reports a received datagram as response `27`:

```text
[27][snr × 4, int8][2 reserved][channelIndex][pathLength][dataType u16 LE][dataLength u8][payload]
```

`dataType` is `0x0120`, the registered MeshCore GROUP_DATA namespace of MCO
Advanced; `payload` is the application envelope, at most 165 bytes:

| Field | Size | Value for MCOtxt |
|---|---:|---|
| `senderNameLength` | varuint | `0` |
| `senderName` | 0 bytes | empty: the name is inside the container |
| `subtypeVersion` | 1 byte | `0x31` = subtype `0x03`, revision `0x01` |
| `body` | remaining | the container, flags `0x02` (+ `0x01`) |

A receiver takes the sender name from the container when flag `0x02` is set
and falls back to the envelope name otherwise. A revision other than `0x01`
under subtype `0x03` is displayed as an unsupported-version placeholder rather
than dropped, so a newer client's messages stay visible.

### Byte layout of a channel message

Decrypted GROUP_DATA carrying a two-line message from `A` with no reply:

```text
data_type      = 20 01          2 bytes   0x0120
data_len       = N              1 byte
  envelope     = 00 31          2 bytes   no outer name, MCOtxt v1
  flags        = 02             1 byte    sender name present, timestamp present
  timestamp    = tt tt tt tt    4 bytes
  senderName   = 01 01 41       3 bytes   mode UTF-8, length 1, "A"
  text         = 00 LL ...      1 + 1..2 bytes, then ceil(bitLength / 8) bytes of stream
```

Before the text payload the application envelope costs 12 bytes with a
one-letter name: 2 envelope + 1 flags + 4 timestamp + 3 name + 2 text header.
A longer name adds its UTF-8 (or MCOtxt) length; a reply adds its author
string and 4 bytes.

The same message as text is `A: mct:<Base91>` with a 4-byte container before
the stream: flags `0x04`, text mode byte, one-byte bit count, and no timestamp
or name because both live in the outer packet. Base91 expands the bytes by
about 23 % and the prefix costs four characters.

## Application policy

How MeshCore Open Advanced applies the codec; other clients may differ.

- MCOtxt is switched on per channel and per contact, in the same place that
  picks MCMP, SMAZ or cyr2lat, and the four schemes are mutually exclusive.
  The stored keys are `channel_mcotxt_<node>` and `contact_mcotxt_<node>`.
- When selected, every eligible message uses the container; there is no
  "only if smaller" gate at this level. The codec's own `RAW_UTF8` mode is the
  size fallback.
- Structured payloads never enter the container: MCOimg text payloads (`im:`,
  v3 and v4 prefixes), GIF references `g:`, map markers `m:` and their `del:`
  commands, `V1|` payloads, shared contacts `<pubkey:type:name>`, and text that
  already carries a compression prefix.
- Channels use the binary GROUP_DATA transport when the app setting "Send
  extended data as binary (channels)" is on, otherwise the `mct:` text
  transport. Rooms and direct messages always use the text transport.
- The decoded timestamp, sender name and reply anchor are stored on the
  message as `containerTimestamp`, `containerSenderName`,
  `containerReplyAuthorName` and `containerReplyTimestamp`, the same fields an
  MCMP v3 container fills, so reply resolution and the clock-mismatch warning
  do not care which codec carried them.
- The compression ratio shown in the UI compares the UTF-8 length of the
  decoded text with the frame payload bytes of the text string; container and
  envelope overhead are excluded.
- An unsupported revision is shown as the placeholder text
  `MCOtxt v<N> не поддерживается: приложение поддерживает MCOtxt v1`, and a
  body that fails to decode as `MCOtxt v<N> не удалось раскодировать`. Both
  strings are currently hard-coded in Russian.

## Size overhead

Excluding the text stream itself:

- stream header: 12 bits per string (16 for `RAW_UTF8`), plus 8 for every
  escaped version or generation;
- frame: 1 byte of bit count up to 127 bits, 2 bytes beyond;
- string: 1 mode byte;
- container: 1 flags byte, plus 4 bytes of timestamp unless inherited, plus
  the sender name string when embedded, plus author string and 4 bytes for a
  reply;
- binary envelope: `varuint(0)` + `0x31` = 2 bytes, plus 2 bytes `data_type`
  and 1 byte `data_len` at the MeshCore layer;
- text transport: four `mct:` characters plus Base91 expansion of the subtype
  byte and the whole container.

On the validation hold-outs of the bundled corpora the stream itself costs
about 5.5 bits per character for Russian and about 5.2 for English and French,
measured with the earlier 9-bit header; the three extra header bits add under
0.1 bit per character on those corpora.

## Decoder validation checklist

A conforming decoder should:

- require the caller to supply the exact bit count and never infer it from a
  byte count;
- reject a version other than `1`, and outside `RAW_UTF8` a generation it has
  no tables for;
- reject languages it has no tables for, in the header and in
  `SWITCH_OTHER_LANGUAGE`;
- reject reserved header formats and sub-opcodes;
- reject table ids beyond the indexed table;
- enforce the `SHIFT` rules and the `TOGGLE_LANGUAGE` precondition;
- validate UTF-8 in `UTF8_RUN` and `RAW_UTF8`, and the `RAW_UTF8` padding and
  alignment;
- reject unknown container flags, unknown string modes, truncated fields and
  trailing bytes;
- require reply author and reply timestamp as one pair;
- report a sender name only when the container carries one;
- display an unsupported revision as a placeholder rather than dropping the
  message.

## Conformance references

Codec, frame and container coverage lives in
`test/MCOtxt/mcotxt_codec_test.dart`. `tools/MCOtxt/verify_runtime_models.py`
checks that the runtime Dart tables, the generated C headers and the manifest
carry the same wire hashes and that the manifest's `modelGeneration` has a
registered set; `tools/MCOtxt/freeze_model_manifest.py` freezes the
manifest once every reserved language has tables. The trainer and its
README live in `tools/MCOtxt/`.

## Implementations

- **MeshCore Open Advanced** (this repository): `lib/MCOtxt/` and
  `lib/helpers/mcotxt_app_codec.dart`, the reference. The app announces the
  codec to South Edition nodes as `cap=mctxt` in the `CMD_APP_START` name.
- **South Edition companion firmware** (Luchik, `src/helpers/mcotxt/` in that
  fork of MeshCore): a full v1 decoder for the node's display and for handing
  the text, as plain-text parts, to a connected app without the codec; a
  greedy encoder for a fixed language pair, which produces a valid stream that
  may be a few bits longer than this reference's search. Its C tables are the
  generated headers from `tools/MCOtxt/generated/`.
