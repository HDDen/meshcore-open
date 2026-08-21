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

MCMP v3's application format version is `3`. In the generic channel application
envelope it currently uses subtype `0x02` and that subtype's wire revision
`0x00`, packed as byte `0x20`. The zero low nibble does not mean MCMP v0; it is
the first wire revision of the MCMP v3 application subtype.

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
encoder should emit only the modern form above. Arithmetic interval updates,
EOF/ESC symbols, Unicode code-point escapes, and model CDF construction are
normatively defined by `lib/helpers/mesh_compressor.dart` together with the
bundled model; they are not redefined by the v3 container.

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

A precise reply anchor consists of `replyAuthorName` and `replyTimestamp`. Both
must be present together. When the enclosing message has a valid signature, the
anchor is covered by that signature. The receiver resolves it against local
history by exact author and timestamp matching; if the original is unavailable,
the message remains readable without a resolved quote target.

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
