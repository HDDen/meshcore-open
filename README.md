# MeshCore Open Advanced (MCOa)

Open-source Flutter client for MeshCore LoRa mesh networking devices — an extended fork of
[MeshCore Open](https://github.com/zjs81/meshcore-open).

## Overview

MeshCore Open Advanced (short: **MCOa**) is a fork of cross-platform client for MeshCore LoRa mesh
network devices. It connects to a companion radio over **BLE, USB serial or TCP** and provides
direct and channel chat, contact and channel management, on-map node tracking and repeater
administration.

The fork started as a small experiment: adding **cyr2lat**, an alternative way of packing text,
in which two-byte Cyrillic characters are replaced with visually similar single-byte Latin ones,
saving around 20–30% of the packet payload. That single feature grew into a separate fork with a
whole set of additions — about throughput, about what you can actually say over the mesh, and
about bringing useful functionality together in one app:

1. **Compression via mesh-compressor** (credits [dimapanov](https://github.com/dimapanov/mesh-compressor/)), and — starting with the v3 format — signing of channel
   messages, so authorship can be established reliably.
2. **Self-contained images** that fit entirely into a single LoRa packet, with a bundled smileys
   pack and an image gallery.
3. **Built-in wardrive** — building a coverage map of the network.
4. **DPI-adjusting** — allows you to scale the elements of the application interface.
5. **Channel grouping**, delayed message sending with the option to cancel, and quick answers.
6. **Multi-byte path hashes and regions** — these have recently appeared in the original
   MeshCore Open as well.
7. **Windows/iOS builds** — ready-to-install packages are available not only for Android and Linux, 
but also for Windows and iOS (as .ipa files)

- **Repository:** <https://github.com/HDDen/meshcore-open>
- **Telegram group:** <https://t.me/mcoadvanced>

## What MCOa adds - detailed

### Text compression — two additional selectable schemes

Compression is chosen per contact and per channel:

- **cyr2lat** — not real compression: two-byte Cyrillic characters are replaced with visually
  similar single-byte Latin ones, which saves around 20–30% of the packet payload. What makes the
  method notable is that it is fully backwards compatible with every MeshCore application, since
  it needs no decompression on the receiving side; the caveat is that it only applies to
  non-English messages (Cyrillic, for example).
- **MCMP** — the [mesh-compressor](https://dimapanov.github.io/mesh-compressor/) algorithm by
  dimapanov: an arithmetic coder driven by a bundled statistical 9-gram language model. 
  On typical chat text it reaches up to ~70% compression, so
  a message roughly three times longer than usual still fits into a single packet.

### Signed messages (MCMP v3, Ed25519)

MCMPv3 messages can carry an Ed25519 signature. Signing is performed by the node itself
(`CMD_SIGN_START/DATA/FINISH`): the app assembles a canonical byte string — a domain separator,
a context tag (channel or room), a binding value that ties the signature to that exact
conversation (an HMAC of the channel PSK, or the room server's public key), the sender name, the
message timestamp, the container flags, the reply anchor for replies, and the message text — and
hands it to the node. The node signs that data with its own private key and returns only the
resulting signature, without ever revealing the private key. The signature is placed inside the
message and sent over the mesh; pairing it with text compression means those extra 64 bytes do
not have to be paid for out of the text the user actually writes.

**Verification happens entirely inside the app** against the public keys of known contacts — the
firmware never verifies anything. The result is shown as a
signature badge next to the message, and sender-name collisions are resolved by the verified key
rather than by the displayed name.

### Precise replies (MCMP v3)

You can now see exactly which message a participant is replying to, as long as they use MCMP v3.
The packet carries a reply anchor: the name of the author of the quoted message and that
message's timestamp. On the receiving side the anchor is matched against the local history — the
author must be the same and the timestamp must match exactly, either the outer packet timestamp
or the MCMP body timestamp — and the quoted message is then shown above the reply.

If the original message never reached us, there is nothing to quote, so the reply degrades
gracefully into a plain **@mention** of the quoted author — the same thing older clients show,
and no worse than the classic "@name" convention that has no way of telling apart several
messages from the same person.

### Exact quotes — precise replies without MCMP

A reply that travels as ordinary text carries only `@[sender]`, which the receiving app resolves
to that sender's most recent message — wrong whenever the answer targets an older one. With the
option enabled (it is, by default), such a reply also carries a short excerpt of the quoted
message on a line of its own:

```
@[Anon] >Всем привет
да, и тебе доброго утра
```

The excerpt is budgeted in **wire bytes** — up to 15, counted *after* cyr2lat transliteration when
the channel uses it, so a Cyrillic quote buys as many characters as a Latin one. It is cut on
character boundaries, stripped of trailing spaces and punctuation (a question mark is kept — it
identifies the message too well to lose), and marked with an ellipsis when it is shorter than the
message it came from. If the quoted message itself began with a quote or a mention of somebody
else, that scaffolding is skipped so the excerpt starts at what the author actually wrote.

Nothing is spent when the answer targets the sender's **newest** message: a bare mention already
resolves to it, and the network is not asked to carry what it can infer. The same goes for MCMP v3
messages, which already have an exact anchor of their own.

On the receiving side the history is walked backwards for a message from that author whose text
starts with the excerpt, retried through every known cyr2lat table when the reply itself arrived
transliterated. A hit makes the quote tappable and scrolls to the original; a miss still displays
the excerpt, so the reader sees what was answered even when the original never reached them.

The quote line adds at most 20 bytes — the marker, up to 15 bytes of text, the ellipsis and the
line break — and needs no support on the other end: the excerpt is plain text, so clients that
know nothing about the convention simply show it as written.

### Text formatting

Messages carry the inline markup the big messengers taught everyone, and it costs nothing but
the marker characters themselves:

| Syntax | Result |
|---|---|
| `**bold**` | **bold** |
| `__italic__` | *italic* |
| `_underline_` | underlined |
| `~~strikethrough~~` | ~~strikethrough~~ |
| <code>&#96;&#96;&#96;mono&#96;&#96;&#96;</code> | <code>monospace</code> |

A span may cover several lines, and spans nest — `**bold with __italic__ inside**` works. The
parser is deliberately forgiving: a marker only opens a span when a matching closer appears
later, so a lone asterisk stays an asterisk, and markers made of underscores never trigger
inside a word, which keeps snake_case names and URLs intact. Inside a monospace block nothing
else is interpreted.

In a message the markers are hidden and only the formatting shows. In the composer they stay
visible but dimmed, with the run between them already styled — so you can see what will be sent,
and deleting one marker visibly strips the formatting from that run, which is how you undo it by
editing. Selecting text also offers the five styles straight from the selection toolbar.

Clients that do not know the convention show the markers as written, the same way they would in
any other messenger.

### MCOimg — small images over LoRa, in one packet payload

A purpose-built lossless raster format that squeezes a very small but recognisable picture 
(mainly pixel art) into a LoRa-sized (~160 bytes) payload:
quantisation to fixed or dynamic palettes (up to 512 colours) and a brute-force search across
many encoders, keeping whichever output is smallest. A typical image size is 30x30 px with 
6 different colours, or up to around 40x40 px with a monochrome palette

Around it:

- a built-in **canvas editor** for drawing and sending a picture directly from the app;
- an on-device **gallery** with installable `.mcoimg.pack` image sets;
- **original-quality playback**: when a received image's identity hash matches an installed pack,
  the app shows the original file instead of the degraded transmitted copy.

The format is documented in [docs/mcoimg_v3_reference.md](docs/mcoimg_v3_reference.md)
(Russian version: [docs/mcoimg_v3_reference_RU.md](docs/mcoimg_v3_reference_RU.md)), with a
reference JavaScript decoder in [docs/mcoimg-js](docs/mcoimg-js) so other clients can display
MCOa images too.

### Built-in wardriving / coverage mapping

Ported from [Meshcore-Wardrive-Android](https://github.com/mintylinux/Meshcore-Wardrive-Android). Turns the phone plus radio into a mesh coverage scanner, with no extra hardware or software. On
each cycle (25 s by default, 5–300 s configurable) the app takes a GPS fix, sends 
a zero-hop discovery request, then listens for responses; every responder becomes a
GPS-tagged sample with SNR, RSSI, node key and response time, and cycles with no answer are
recorded as "dead zone" samples. Samples can be uploaded to a configurable coverage map service
(de-duplicated per endpoint), and on Android an optional foreground service keeps sampling
running with the screen off.

### DPI-adjusting

The app carries its own interface scale, independent of the system one. A slider in the mod
settings sets a factor from **50% to 200%** in 5% steps, which is multiplied on top of the
system text scale — so the OS accessibility setting is still honoured, and the app can be made
denser or larger than the system allows. A separate switch decides whether icons scale along
with the text. On top of that, text inside chats has its own persistent scale (0.8×–1.8×) that
is remembered between sessions.

### Region / flood-scope routing

Channels can be tagged with a named region, which is hashed into a flood scope and pushed to the
node. This keeps regional channel traffic inside its own scope instead of flooding the whole
mesh. Regions are managed in a dedicated screen and stored per channel. The same goes for
multi-byte path hashes (a configurable 1–4 byte per-hop hash width). Both have recently appeared
in the original MeshCore Open as well.

### Smaller additions

- **Channel groups** and custom channel ordering, plus contact groups
- **Sending delay** — schedule, review and cancel a queued outgoing message per conversation
- **Quick answers** — canned replies available straight from the composer
- **Per-conversation settings** — compression, signing, delay, quick answers and channel colour
- Numerous smaller layout, readability and navigation corrections throughout the app

## Downloads

Ready-made builds are published in the
[Releases](https://github.com/HDDen/meshcore-open/releases) section — not only for Android:

- **Android** — APKs split per CPU architecture (`arm64-v8a`, `armeabi-v7a`, `x86_64`) so the
  download stays small
- **iOS** — `.ipa` packages
- **Windows** — desktop build
- **Linux** — desktop build

## Platform support

| Feature            | Android (API 21+) | iOS (12+) | Linux | Windows |
|--------------------|:-----------------:|:---------:|:-----:|:-------:|
| BLE companion      | ✅                | ✅        | ✅   | ✅      |
| USB companion      | ✅                | 🚧        | ✅   | ✅      |
| TCP companion      | ✅                | 🚧        | ✅   | ✅      |

## Building from source

Requires the Flutter SDK (3.38.5 or later) and a MeshCore-compatible LoRa device.

Two branches matter:

- [`rename-mco-advanced`](https://github.com/HDDen/meshcore-open/tree/rename-mco-advanced) — the
  main stable branch, this is what released builds are made from
- [`rename-mco-advanced-alfa-build`](https://github.com/HDDen/meshcore-open/tree/rename-mco-advanced-alfa-build)
  — the main testing branch, carrying the latest changes

```bash
git clone https://github.com/HDDen/meshcore-open.git
cd meshcore-open
git checkout rename-mco-advanced
flutter pub get
flutter run
```

Release builds:

```bash
flutter build apk --release --split-per-abi
flutter build ios --release
flutter build windows --release
flutter build linux --release
```

### Build profiles: lite / lite-aeic / full

The app can be built in three profiles:

- **lite** — no LLM translation or AEIC neural images; smallest binary
- **lite-aeic** — lite plus AEIC image support (`flutter_onnxruntime`)
- **full** — includes both on-device LLM translation (`llamadart`) and AEIC

```bash
flutter clean
dart run tool/use_translation_profile.dart lite   # or: lite-aeic / full
flutter pub get
...
flutter build apk --release --split-per-abi --dart-define=MESHCORE_ENABLE_TRANSLATION=false # adds «MESHCORE_ENABLE_TRANSLATION»-flag; Android apk for example
```

The tool copies the selected `pubspec.<profile>.yaml` over `pubspec.yaml` and swaps both the
translation service and AEIC backend to their matching implementations. The selected profile is
sticky: it stays active for every subsequent build until you switch again. When changing shared
dependencies, update every profile manifest so a later switch does not overwrite the change.

## Contact and support

Questions, bug reports, feature requests and ideas for the modification are all welcome:

- **GitHub** — open an [issue](https://github.com/HDDen/meshcore-open/issues) or send a pull
  request to <https://github.com/HDDen/meshcore-open> (see
  [CONTRIBUTING.md](CONTRIBUTING.md))
- **Telegram** — the official group of the fork: <https://t.me/mcoadvanced>

Issues that concern the base client rather than the modification are better reported upstream at
<https://github.com/zjs81/meshcore-open/issues>.

## Acknowledgments

- A big thank you to **[zjs81](https://github.com/zjs81)**, the author of the original
  [MeshCore Open](https://github.com/zjs81/meshcore-open) client. MCOa exists only because there
  was an excellent, well-structured open client to build on — everything listed above was added
  on top of that foundation.
- **[dimapanov](https://github.com/dimapanov)** for the
  [mesh-compressor](https://dimapanov.github.io/mesh-compressor/) algorithm behind MCMP
- Built with [Flutter](https://flutter.dev/)
- Map tiles from [OpenStreetMap](https://www.openstreetmap.org/)
