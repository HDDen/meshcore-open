# Routing Paths

MeshCore Open supports flood routing, direct paths, and routing overrides. Chat → Routing lets you choose Auto, Flood, or Manual and inspect recent paths. [Regions](regions.md) control the scope of channel floods; they do not replace direct-contact routing.

## Hash widths and firmware capability

Each hop is represented by a public-key prefix. Current device-info negotiation clamps mode to `0..2`, giving **1–3 bytes per hop**. Some parsing/display helpers accept four-byte widths; that is not a claim that current device negotiation offers a four-byte mode.

| Bytes per hop | Possible prefixes | Hops fitting in 64 path bytes |
|---|---|---|
| 1 | 256 | 63 with the current six-bit packed hop count |
| 2 | 65,536 | 32 |
| 3 | 16,777,216 | 21 |

These are prefix-space sizes, not collision-free network capacities. Longer prefixes reduce collisions and leave less room for hops. Repeaters need compatible firmware to forward multi-byte paths; the UI identifies older-than-v1.14 firmware as incompatible with two- and three-byte IDs.

## Encoded paths and model fields

For packed non-flood contact path metadata:

```dart
final width = ((pathLenRaw & 0xC0) >> 6) + 1;
final hopCount = pathLenRaw & 0x3F;
final byteLength = hopCount * width;
```

`0xFF` is the contact flood/unknown-path sentinel. Handle it before decoding the packed fields.

- Model/storage `pathLength` stores **hop count**, with `-1` representing flood/unknown.
- `pathHashWidth` stores the bytes per hop for that path.
- `pathBytes` (or `Contact.path`) contains concatenated prefixes.
- Use the path’s own width when splitting, reversing, matching, and rendering it; do not substitute the device’s current width for historical metadata.

For example, a three-hop path at width 2 has six bytes: `[A1,A2,B1,B2,C1,C2]`, rendered as `A1A2 → B1B2 → C1C2`, and `pathLength=3`.

For complete observed paths, hop count is `pathBytes.length ~/ width`. Some display helpers round up a partial final group; malformed or incomplete bytes must not be interpreted as a valid complete route. Prefer decoded observed path bytes when frame metadata describes a different route.

## Where paths come from

Contact response frames place packed path metadata at offset **35** and the 64-byte path area at offsets **36–99**, counting the response code as byte 0. See [contact frame layout](ble-protocol.md#contact).

Channel text payloads contain sender text, not an encrypted hop chain. Observed channel paths come from the raw packet header/path associated with `PUSH_CODE_LOG_RX_DATA`. Direct-message frame metadata and path updates likewise need their format-specific decoding.

Short prefixes can match several known nodes. An unresolved or ambiguous hop is not proof of a particular repeater identity. Map positions derived from paths are estimates, not GPS fixes.

## Storage and route selection

Contacts/messages persist hop count, path bytes, and width. Legacy contact records without width infer it from consistent hop and byte counts, falling back to one byte. `PathHistoryService` scores recent routes using delivery observations; automatic route rotation can select another route on retry when no manual override is active. Rotation follows the App Settings **Auto Route Rotation** toggle (`autoRouteRotationEnabled`, on by default).

For message-path actions, trace maps, and retry behavior, see [chat](chat-and-messaging.md), [channels](channels.md), and [map](map-and-location.md).
