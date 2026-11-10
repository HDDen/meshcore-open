# Routing Paths

Open **Chat → Routing** to choose **Auto**, **Flood**, **Direct**, or
**Manual** and inspect recent paths. **Direct** pins a zero-hop route for
every send and retry. The routing sheet confirms it when the node reports
zero hops. You can use the same sheet from repeater and room-server login.
Channel floods have their own scope settings. [Regions](regions.md)

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

Contacts and messages persist hop count, path bytes, and width. Legacy contact
records infer width from consistent hop and byte counts, falling back to one byte.
`PathHistoryService` scores recent routes using delivery observations.
**Auto Route Rotation** in App Settings starts off. Enable it to try other
paths from history on retries when no manual override is active.

**Experimental route selection** is a separate switch under Auto Route
Rotation. It starts off. When enabled, Thompson sampling chooses a path for
intermediate retries from recent delivery results and passively heard
neighbors. It can try a known zero-hop route. Delivery evidence loses half
its weight each day and is stored with the contact's route history on the
current node. The first attempt follows the node's route. The final attempt
uses the usual Flood policy, and pinned routes take precedence.

A timed-out route loses weight only when an unambiguous delivery
acknowledgement for another attempt shows that the contact was reachable.
A late acknowledgement credits the attempt it confirms. When every
attempt goes unanswered, route weights stay as they were. Flood attempts
keep their own delivery and timeout counts.

A contact's path history retains up to 100 routes. Once full, a new route
replaces the existing route with the lowest selection score, using the same
reliability, latency, freshness and route-weight factors as automatic selection.
Updating a known route preserves the other entries and its learned statistics.
The complete hop bytes are retained for one-, two- and three-byte prefixes.
This history replacement does not edit the contact's manual routing override.

For message-path actions, trace maps, and retry behavior, see [chat](chat-and-messaging.md), [channels](channels.md), and [map](map-and-location.md).


## Path hash size in radio settings

On companions with protocol version code 10 or newer (firmware v1.14+),
use the separate **Settings → Path hash size** item to select 1, 2 or 3 bytes
per hop. The duplicate selector inside **Radio settings** is temporarily hidden;
its upstream implementation is retained. Saving radio parameters or choosing
a radio preset does not send a path-width command or overwrite the current width.

The separate path hash size dialog scrolls on short screens or with large
text. Long option labels wrap onto multiple lines without shortening the
text or changing their values. Full path details in the routing sheet also
scroll, preserving the complete selectable path and repeater names above the
trace/close buttons.
