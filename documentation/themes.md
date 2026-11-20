# Themes and chat backgrounds

Open **Settings → App Settings → Appearance → Themes** to choose colors, icons,
map markers and chat backgrounds. These settings are stored on the device.

## Choosing a theme

- **MeshCore** uses the saved System, Light or Dark mode. Tapping one of those
  modes in Appearance also returns to the standard theme.
- **Built-in** includes Forest, Ocean, Ember, Grape, High Contrast, Paper, Mint
  and Sky. Use **Customize a copy** to edit a version of a preset.
- **My themes** lists your saved and imported themes. The menu lets you edit,
  copy, export or delete them.
- **Holidays** includes Halloween, Thanksgiving, Christmas and New Year's
  themes. Each includes a palette, icons and a chat background.

The active theme is marked in the list. A custom theme's background determines
whether it uses light or dark surfaces.

## Previewing a theme

The editor has four preview tabs: **Channel chat**, **Direct chat**,
**Channels**, and **Contacts**. They show the same message bubbles, delivery
badges, input field and list cards as the app, with synthetic names, keys and
messages. The chat examples include routing, signal, region and compression
indicators. Channel chat also shows incoming and outgoing quotes, plus both
bordered and simplified mentions together in both message bodies. These examples are
independent of your messaging preferences. Their timestamps are two days
before you opened the editor.
Both chat previews include a new line with `https://localhost` in each message.
Switching tabs preserves your draft. Preview controls do not send messages or
change read state, and the preview does not connect to a radio.

Background, Accent, Chat background, Icons and Map markers start collapsed.
Tap a section heading or its **+** to expand it; tap again (**minus**) to fold
it. Sections open independently and folding preserves your draft.

## Creating and sharing a theme

Tap **Create theme** and enter a name. Choose a background and accent from the
swatches or enter hex colors. The editor previews chat bubbles and controls.
You can choose named icons or pick pictures for the navigation tabs, Send,
Settings, supported node avatars and map markers. A custom theme can tint the
map tiles and change its own-position accent. [Map & Location](map-and-location.md)

**Save and use** applies the theme. **Copy theme code** copies one theme to the
clipboard. **Paste theme code** imports and applies it. **Export to file** and
**Export my themes** create a .jsonl file with one theme per line. **Import from
file** adds the themes to your library and keeps your current selection.

MCOa exports add a `mcoa` section with `"version": 1` to each theme object. This is the
version of the MCOa theme extension, not the app version. Share codes use the
same format. Upstream readers ignore this section; themes without it still
import normally. Optional colors and activation preferences are described below.

## Chat backgrounds

In a direct chat or channel, open **⋮ → Chat background** and pick a color or
a local picture. **Fade** blends it toward the theme's surface color. Select
**None** to clear that conversation's background.

A theme can supply a background for conversations without one. **Use in every
chat** makes the active theme's background take precedence while the theme is
in use. The app keeps your individual chat choices. They follow the contact
or channel if you reconnect with a different radio.

Photos are stored locally as JPEG XL. When you share a theme that uses a
photo from your device, the photo is included.

## MCOa theme settings

The editor's **MCOa settings** block contains four collapsed sections:
**Interface**, **Incoming**, **Outgoing**, and **MCOa settings**. These cards use
compact internal padding without an additional inset around their rows. Color rows open
the same continuous HSV palette (saturation/value square and hue slider) used
for channel widget colors, plus HEX and opacity inputs; **Default** clears that override. Each color swatch
also has a compact editable HEX field below it. A complete RGB or ARGB value
updates the swatch and preview immediately, with or without a leading `#`.
Clearing this field removes the override. Its faint hint and swatch show the
inherited theme color; they do not write that fallback into the theme. Interface colors
cover the status bar, app header and its text. A top-inset overlay also paints
this status-bar color on iOS and edge-to-edge Android without consuming safe-area
padding. Incoming and outgoing messages
have independent border, background, text, badge, quote and mention colors,
plus separate hop-counter borders, backgrounds and text. The general badge
color never changes hop-counter text; unset hop text uses the ordinary hop-chip
color. Simplified mentions always have transparent backgrounds and inherit
the message text color, regardless of the configured mention background or
mention text color. Mention background/text overrides style only bordered mentions.

Interface colors also cover the chat composer background, actions icon, input
border/background/placeholder/text, send button background/icon, and the byte
counter's normal, almost-full and exceeded states. Existing counter thresholds
and message limits are unchanged. These input overrides apply to chat composers;
other byte-counted fields retain their ordinary theme. The repeater CLI command
send button also uses the chat send-button background and icon colors. The preview shows its
zero-byte counter while keeping the placeholder visible.
Each direction also has a link color (including its underline) and a signal
color for SNR/RSSI inside messages. An unset link color uses the standard link
style; an unset signal color uses the normal reception-quality scale. Signal
indicators outside message bubbles retain that scale. Failed-message warning
colors retain their meaning.

DPI accepts 50–200%, sender names accept 25–400%, with up to three digits.
The switch uses the application's simplified mentions setting. **Incoming →
Sender name**, placed before message text, sets the sender-name color in channel
and contact chats. Clearing it restores the application's ordinary sender-name
coloring. Themes no longer change the global monochrome sender names setting;
that obsolete preference in older MCOa theme files is ignored. The preview updates without changing application
preferences. **Save and use**, or selecting the saved theme later, applies these
preferences once. You can change them afterwards in app settings; the active
theme does not force them back, including after restarting the app.

Colors and these activation preferences are saved in the optional `mcoa`
section of both stored themes and shared JSON/JSONL. The upstream theme fields
are unchanged. Legacy themes use the existing defaults; unsupported MCOa
extension versions and unknown fields are ignored.

## Automatic holiday themes

**Switch automatically** is off by default. If enabled, the nearest holiday's
theme appears from 17 days before the holiday through its own day.

| Holiday | Local date | Window opens |
|---|---|---|
| Halloween | October 31 | October 14 |
| Thanksgiving | Fourth Thursday in November | November 5–11 |
| Christmas | December 25 | December 8 |
| New Year's Day | January 1 | December 15 |

When windows overlap, the nearest holiday takes precedence. For example, the
Christmas theme runs through December 25, then the New Year's theme takes over
on December 26. The app checks the schedule when it returns to the foreground
and at the next theme change while it stays visible.

The automatic theme temporarily takes precedence over your saved choice. Picking
another theme or a standard mode during the holiday skips that occurrence.
Turning the switch off restores your saved choice immediately.

## Holiday message animations

**Holiday message animations** in **Themes → Holidays** is a separate option
and is off by default. When enabled, a fresh greeting near the end of the
visible chat can play a short animation. The app recognizes greetings in its
supported languages and plays effects year-round. Existing history stays quiet.

Only one effect plays at a time across chats. Greetings arriving during
an effect or in the five seconds after it stops are skipped.

Touches pass through the effect. It stops when the app or chat loses
visibility and follows the system's reduced-motion setting and the selected
power profile.
