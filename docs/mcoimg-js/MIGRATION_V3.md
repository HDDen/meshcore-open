# Migrating MCOimg v1/v2 clients to v3

MCOimg v3 is the current format. It is intentionally isolated from the legacy
v1/v2 codec so applications can keep old messages readable while moving all new
encoding to the official MCO Advanced namespace.

## Transport identifiers

| Layer | v1/v2 | v3 |
| --- | --- | --- |
| Chat text prefix | `im:` | `im3:` |
| MeshCore `data_type` | `0xFFF0` legacy/developer route | `0x0120` official MCO Advanced route |
| App subtype | implicit in the legacy route | `0x01` (`MCOimg`) |
| Content version | encoded by the legacy body | `0x03` |
| Packed subtype/version byte | n/a | `0x13` |
| Packet nonce | legacy format dependent | first byte of the v3 body |

The canonical v3 binary file/app payload is:

```text
0x13 | v3 body
```

The v3 body itself starts with the one-byte packet nonce. Do not prepend the
legacy `0xFFF0` data type to a raw `.bin` file and do not remove `0x13` before
passing canonical binary to the version-neutral browser helpers.

The official channel envelope carried under `data_type = 0x0120` is:

```text
senderNameLength(varuint) | senderName(UTF-8) | 0x13 | v3 body
```

## JavaScript file split

Load all compatibility helpers in this order:

```html
<script src="mcoimg-codec.global.js"></script>
<script src="mcoimg-v3-codec.global.js"></script>
<script src="mcoimg-browser.global.js"></script>
```

- `MCOImg` owns v1/v2 only.
- `MCOImgV3` owns v3 only.
- `MCOImgBrowser` detects and routes `im:`, `im3:`, legacy binary, and canonical
  v3 binary.
- `mcoimg-v3-worker.global.js` is loaded by Worker instances; it does not need a
  normal page `<script>` tag.

The low-level v3 codec can be loaded without the v1/v2 file when canvas/PNG and
version-neutral browser helpers are not required:

```js
const codec = new MCOImgV3.MCOImageV3Codec();
```

## Encoding new images

Switch new outbound images to `formatVersion: 3`:

```js
const text = await MCOImgBrowser.encodeCanvas(canvas, {
  formatVersion: 3,
  compressionLevel: 'high',
  paletteProfile: MCOImgV3.PaletteProfile.master8,
  output: 'text',
});
```

Available outputs are `text`, `binary`, `png`, `image`, and `encoded`.
`binary` means canonical `0x13 | body`, not the bare body.

For Extreme, workers are selected automatically when the browser provides the
Worker API. High uses workers only when explicitly requested:

```js
const encoded = await MCOImgBrowser.encodeImage(image, {
  formatVersion: 3,
  compressionLevel: 'extreme',
  workerCount: 4,
  output: 'encoded',
});
```

Serve the demo and scripts over HTTP(S). Browsers commonly restrict Worker
loading from `file://` pages.

## Reading old and new messages together

No manual prefix branching is needed for ordinary text/binary conversion:

```js
const image = MCOImgBrowser.decodePayload(payload);
const metadata = MCOImgBrowser.inspectPayload(payload);
const png = await MCOImgBrowser.convertPayload(payload, { output: 'png' });
```

Detection rules:

- `im:` routes to v1/v2;
- `im3:` routes to v3;
- canonical binary beginning with `0x13` routes to v3;
- other binary routes to the legacy inspector unless `formatVersion` is
  supplied explicitly.

Raw v3 bodies without the leading `0x13` are intentionally a low-level format.
Use `MCOImgV3.MCOImageV3Codec.decodeBody()` or pass them to `decodeBytes()` with
care; store/exchange canonical app payloads wherever possible.

## Channel packet inspection

```js
const packet = MCOImgBrowser.inspectMcoImageChannelPacket(bytes, {
  formatVersion: 3,
  layout: 'auto',
});

console.log(packet.dataType);       // 0x0120
console.log(packet.subtypeVersion); // 0x13
console.log(packet.payload);        // 0x13 | body
console.log(packet.body);           // nonce-prefixed v3 body
```

`layout` can be `auto`, `channelData`, `outgoingCommand`, `envelope`, or
`rawMcoImage`. Both little- and big-endian `data_type` inspection are supported
when `byteOrder: 'auto'` is used.

## Nonce-only refresh

The v3 packet nonce is outside the compressed bitstream, so it can be replaced
without rerunning the encoder:

```js
const newBody = MCOImgV3.MCOImageV3Codec.refreshPacketNonce(oldBody);
const newText = MCOImgV3.MCOImageV3Codec.textFromBody(newBody);
```

To refresh a canonical binary app payload, refresh `payload.slice(1)` and prepend
`0x13` again, or keep the original encoded image and encode a new packet nonce.

## Suggested rollout

1. Ship a decoder update that understands both `im:` and `im3:` and both data
   types.
2. Keep v1/v2 rendering enabled for stored/history messages.
3. Switch new outbound encoding to v3 and `0x0120`.
4. Monitor old-client population before hiding v1/v2 encoding controls.
5. Remove the legacy encoder only after no supported client needs to create
   `im:` payloads. Keep the legacy decoder for message history as long as old
   messages remain accessible.

## Compatibility boundaries

- v1/v2 code never imports or mutates the v3 namespace.
- v3 code never mutates `MCOImg`.
- Worker completion order cannot change the selected payload.
- v3 rejects non-canonical dimension encodings, non-zero padding, trailing
  bytes, invalid palette references, and illegal container/algorithm
  combinations.
- The codec is lossless for an already prepared palette-index array. PNG import
  performs palette mapping before lossless MCOimg encoding.
