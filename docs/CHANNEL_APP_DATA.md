# Channel application data (GROUP_DATA)

[Russian version / Русская версия](CHANNEL_APP_DATA_RU.md)

This document is the part every binary channel format of MCO Advanced shares:
how a typed channel datagram travels, which application namespace it claims,
how the MCO Advanced envelope under namespace `0x0120` is laid out, which
subtypes exist under it, and what a receiver does with a payload it cannot
read. The bodies inside the envelope are specified by their own documents and
are deliberately not repeated here:

- MCMP v3 container: [`MCMP_V3_PROTOCOL.md`](MCMP_V3_PROTOCOL.md)
- MCOtxt v1 container: [`MCOTXT_V1_PROTOCOL.md`](MCOTXT_V1_PROTOCOL.md)
- MCOimg v3 body: [`mcoimg_v3_reference.md`](mcoimg_v3_reference.md)
- MCOimg v4 body: [`mcoimg_v4_reference.md`](mcoimg_v4_reference.md)
- companion frames, field by field: [`BLE_PROTOCOL.md`](BLE_PROTOCOL.md)

The Dart implementation in this repository is the reference for this document:

- `lib/helpers/channel_app_data_helper.dart` — the `0x0120` envelope:
  identifiers, `encodeEnvelope`, `tryDecodeEnvelope`
- `lib/helpers/channel_binary_data_helper.dart` — decode order, the legacy
  namespaces, `tryDescribeUnknownAppData`, the `UnknownChannelAppData`
  sentinel
- `lib/connector/meshcore_protocol.dart` — `buildSendChannelDataFrame`,
  `parseChannelDataReceivedFrame`, `maxChannelDataLength`
- `lib/connector/meshcore_connector.dart` — `_handleIncomingChannelData`,
  `_addUnknownAppDataMessage`
- `lib/widgets/unknown_app_data_placeholder.dart` — the placeholder text
- `test/helpers/channel_binary_data_unknown_test.dart` — the receiver rules
  as tests

## Conventions

- Multi-byte integers are unsigned and little-endian.
- Text is UTF-8.
- `varuint` is an unsigned base-128 integer: each byte carries seven value
  bits, least-significant group first, and bit 7 set means another byte
  follows. Zero is one zero byte. The reference decoders accept at most five
  bytes and reject a longer or a truncated one.
- Identifiers are written as MeshCore's registry writes them: `0x0120`.

## Transport

A typed channel datagram is a MeshCore packet of payload type
`PAYLOAD_TYPE_GRP_DATA` (`0x06`), encrypted under the channel key exactly as
a `GROUP_TEXT` message is. Decrypted, its content is:

| Field | Size | Meaning |
|---|---:|---|
| `data_type` | 2 bytes LE | the application namespace, see below |
| `data_len` | 1 byte | number of bytes in `application_data` |
| `application_data` | `data_len` bytes | the application payload |

`application_data` is at most 165 bytes (`maxChannelDataLength`); the
firmware derives the same limit from its packet payload size less one cipher
block and this three-byte header. A receiving node drops a datagram shorter
than three bytes or whose `data_len` exceeds what follows it, and hands every
other datagram to its client as it is, whatever the `data_type`. The one
exception is a South Edition node with MCOtxt conversion on, which hands an
MCOtxt envelope to an app without that codec as plain text; the MCOtxt
document describes it.

Between a companion node and its client the datagram travels in two frames.
Their fields, the packed path byte included, are described in
[`BLE_PROTOCOL.md`](BLE_PROTOCOL.md):

```text
CMD_SEND_CHANNEL_DATA (62 = 0x3E), client -> node
[62][channel_idx][path_len][path...][data_type u16 LE][application_data]

RESP_CODE_CHANNEL_DATA_RECV (27 = 0x1B), node -> client
[27][snr x 4, int8][2 reserved][channel_idx][path_len][data_type u16 LE][data_len][application_data]
```

In the command `path_len = 0xFF` asks for flood delivery and no path bytes
follow; any other value is the length of the route that follows. The command
carries no `data_len`: the node takes `application_data` to the end of the
frame and writes the length itself. In the response `path_len` is the packet's
packed path byte, `0xFF` when the packet carried no path. With the RX log on,
the raw packet reaches the client through `PUSH_CODE_LOG_RX_DATA` as well; once
decrypted it shows the same three-byte header.

## Namespaces

`data_type` names the application a datagram belongs to. Ranges are allocated
in MeshCore's
[`docs/number_allocations.md`](https://github.com/meshcore-dev/MeshCore/blob/main/docs/number_allocations.md):
a project uses the development range while it is being built and requests a
value of its own before publishing.

| `data_type` | Owner | MCO Advanced on receipt |
|---|---|---|
| `0x0000`–`0x00FF` | reserved by MeshCore | ignored |
| `0x0100` | MeshCore Open | kept as a placeholder naming the namespace; the layout is not read |
| `0x0110`–`0x011F` | Ripple | ignored |
| `0x0120` | **MCO Advanced** | the envelope below |
| `0x0130`–`0x013F` | StreamSensor | ignored |
| other values in `0x0100`–`0xFEFF` | requested by pull request to the registry | ignored |
| `0xFF00`–`0xFFFF` | development and proof of concept, no request needed | ignored, except the two legacy values below |

Two values from the development range predate the allocation of `0x0120` and
are still understood. Their payload is `senderNameLength(varuint) | senderName
| body`, with no subtype byte:

| `data_type` | Body | Status |
|---|---|---|
| `0xFFF0` | MCOimg v1/v2 image, the binary form of an `im:` text | still sent for an `im:` image while binary sending is on; still decoded |
| `0xFFF1` | MCMP v2 compressed text | still sent by a channel set to MCMP v2 while binary sending is on; still decoded |

Everything newer goes under `0x0120` with a subtype of its own. Binary sending
as a whole is the app setting *Send extended data as binary (channels)*
(`ChannelBinaryDataHelper.sendEnabled`); with it off, every format falls back
to its text transport.

One more value is in use without a registry row: the image chunk transport
(`lib/services/image_chunk_transport.dart`) claims `0xAE1C` for AEIC image
chunks. The connector offers a received datagram to that transport before the
envelope path, only while image messages are enabled.

## The MCO Advanced envelope (`0x0120`)

`application_data` under `0x0120` is:

| Field | Size | Meaning |
|---|---:|---|
| `senderNameLength` | varuint | UTF-8 byte length of `senderName` |
| `senderName` | `senderNameLength` bytes | the sender's channel display name; may be empty |
| `subtypeVersion` | 1 byte | high nibble: subtype id; low nibble: that subtype's wire revision |
| `body` | remaining bytes | defined by the subtype's own document |

```text
data_type = 20 01            0x0120
data_len  = N
  senderNameLength (varuint)
  senderName (UTF-8)
  subtypeVersion (u8)
  body
```

`senderName` is the outer sender name of the channel message, the counterpart
of the `Name: ` prefix in a `GROUP_TEXT` message: it is what a client displays
and what a signature verifier binds. A subtype may leave it empty and carry the
name inside its body, as MCOtxt does; the reference decoder shows an empty
outer name as `Unknown` unless the body supplies one.

Subtype id and revision are each `0`–`15`. The id names a format; the revision
changes only when the body changes in a way the previous decoder must not
attempt, so a decoder keys its parser on the pair. A revision counts within its
subtype: byte `0x20` is MCMP subtype `0x02` at wire revision `0x00`, not
"MCMP v0".

The whole envelope, name and body included, has to fit `data_len`, so the body
budget for a given name is
`165 - varuintLength(nameLength) - nameLength - 1`.

### Subtypes

| Subtype | Id | Revision | Byte | Body | Specification |
|---|---:|---:|---:|---|---|
| MCOimg | `0x01` | `0x03` | `0x13` | MCOimg v3: packet nonce and compressed image | [`mcoimg_v3_reference.md`](mcoimg_v3_reference.md) |
| MCOimg | `0x01` | `0x04` | `0x14` | MCOimg v4 body | [`mcoimg_v4_reference.md`](mcoimg_v4_reference.md) |
| MCMP | `0x02` | `0x00` | `0x20` | MCMP v3 container: flags, timestamp, optional sender, signature and reply anchor, compressed text | [`MCMP_V3_PROTOCOL.md`](MCMP_V3_PROTOCOL.md) |
| MCOtxt | `0x03` | `0x01` | `0x31` | MCOtxt v1 container; outer name empty, the name travels inside | [`MCOTXT_V1_PROTOCOL.md`](MCOTXT_V1_PROTOCOL.md) |
| — | `0x04`–`0x0F` | | | unassigned | |

A new format takes the next free id in this table and a document of its own;
an incompatible change to a body takes the next revision of its subtype. In
the reference both live in `ChannelAppDataHelper` (`ChannelAppDataSubtype` and
the `*Version` constants).

## What a receiver does

The rules below are the ones MCO Advanced follows and the ones another client
of these namespaces is expected to follow, so that a newer sender's messages
stay visible as messages instead of disappearing.

The reference decodes each received datagram in this order
(`_handleIncomingChannelData`):

1. the AEIC chunk transport gets first refusal while image messages are
   enabled (`0xAE1C`);
2. the two legacy namespaces `0xFFF0` and `0xFFF1` (`tryDecodeInbound`);
3. the `0x0120` envelope (`tryDecodeAppData`), dispatched on subtype and
   revision;
4. whatever is left from a namespace with a known owner
   (`tryDescribeUnknownAppData`) becomes a placeholder message;
5. any other `data_type` is ignored.

### Known subtype, unreadable body

A codec reports its own trouble first, with its own text, because it knows
what it could not read:

| Case | Outcome |
|---|---|
| MCOimg at a revision other than `0x03` or `0x04`, or a v4 body the decoder refuses as an unsupported format | the unsupported-image placeholder (`mcoimg-unsupported:<revision>` in storage), body kept |
| MCOtxt at a revision other than `0x01` | the MCOtxt unsupported-revision text (`MCOtxtAppCodec.unsupportedFormatText`) |
| MCOtxt v1 body that fails to decode | the MCOtxt decode-failed text (`MCOtxtAppCodec.decodeFailedText`) |
| MCMP at a revision other than `0x00`, or a body `McmpAppCodec.decodeBody` rejects | not reported by MCMP: falls through to the placeholder below, naming subtype `2` and the revision |
| MCOimg body at a known revision that its decoder rejects | falls through the same way, naming subtype `1` and the revision |

The placeholder therefore means "this build could not read it", which covers
a format newer than the build as well as a damaged body; its wording says the
app *may* need an update for that reason.

### Unknown subtype, or a namespace whose layout is not ours

A datagram from a namespace with a known owner that nothing above could read
is kept, not dropped:

- Under `0x0120` the envelope is parsed as far as it goes: the outer sender
  name, the subtype id and the revision are taken when the envelope is well
  formed; a payload that is not an envelope keeps only the namespace.
- Under `0x0100` nothing is read, the layout belongs to MeshCore Open. Only the
  namespace is named.
- The message is stored as an ordinary channel message whose text is a
  sentinel and whose `rawPayload` is the whole `application_data`, so a later
  build that knows the format can decode it from history. The sentinel is
  `mcoapp-unknown:0x0120:<subtype>.<revision>` with decimal ids, or
  `mcoapp-unknown:0x0100` when there is nothing to add
  (`UnknownChannelAppData.sentinelText` / `parseSentinel`).
- The screens never show the sentinel. `unknownAppDataPlaceholderText` renders
  it as a localized line: *Received a packet of an unknown subtype (0x0120 MCO
  Advanced, subtype 3 version 2); the app may need an update*, or *Received a
  packet in a format this app cannot read (0x0100 MeshCore Open); the app may
  need an update* when only the namespace is known. It appears in the bubble,
  in a reply quote, in the reply banner and in the channels list preview; the
  message search, which runs without localization, shows the sentinel itself.
- The sender name is the outer envelope name when it was read, otherwise
  `Unknown`. Hop count, hash width and SNR of the frame are kept as for any
  message.
- No notification is raised; the unread count is enough.
- The RX-log copy of such a packet is ignored: the node hands every datagram
  over as a frame as well, so nothing is lost, and no route is merged into a
  message nobody can read.

### Rules for another implementation

- Decode on the pair of subtype and revision; never feed a body of one
  revision to the decoder of another.
- Keep an envelope whose subtype or revision you do not know, show a
  placeholder naming the namespace, the subtype and the revision, and store
  the payload.
- Treat `0x0100` as MeshCore Open's: show it or ignore it, but do not parse it
  as this envelope.
- Ignore any other `data_type`, or handle it as your own if you own it.
- When sending, use the namespace you own. A new format under `0x0120` takes
  a new subtype from the table above; an incompatible change to a body takes a
  new revision of its subtype.

## Implementations

- **MCO Advanced** (this repository): the files listed at the top. The
  placeholder rules are pinned by
  `test/helpers/channel_binary_data_unknown_test.dart`.
- **South Edition companion firmware** (Luchik's fork of MeshCore):
  `src/helpers/mcmp/MCMPDetect.h`, `src/helpers/mcoimg/MCOImgTransport.h` and
  `src/helpers/mcotxt/MCOtxtTransport.h` each recognise a `0x0120` envelope by
  its subtype nibble and report any other subtype as not theirs, so a subtype
  the node does not know is left to the client untouched;
  `src/helpers/mcotxt/MCOtxtEncoder.h` builds the `0x03` envelope for text the
  node re-encodes on the app's behalf.
