# Themes and chat backgrounds

Open **Settings → App Settings → Appearance → Themes** to choose colors, icons,
map markers and chat backgrounds. These settings are stored on the device.

Новые установки начинают с встроенной темы **MeshCore Liam (dark)**. В списке встроенных тем она находится сразу после стандартной MeshCore. Сохранённый выбор при обновлении не меняется; стандартную тему по-прежнему можно выбрать вручную.

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


At the end of **Interface**, **Accent color (Attention)** and **Accent color
(Warning)** provide independent optional color swatches and editable HEX values.
The swatches default to the existing amber and red settings-action colors.
Attention overrides the channel message spam/filter actions, Support development,
and Reboot device. Warning overrides Delete all paths and the Delete action in channel and direct
message menus (including room and additional-key chats). Without Warning, the
message Delete action has no explicit color override. Settings subtitle text
retains its existing 70% alpha. When an override is cleared, each action returns
to its original color (message filtering uses the ordinary theme primary).
The optional keys are `mcoa.colors.attention` and `mcoa.colors.warning`; storage
and theme sharing remain at MCOa extension version 1.

The **Channels** preview includes the same search field used in the channel list, above the two sample cards. Preview search is inert. In **Chats**, **Search: border**, **Search: background**, **Search: text**, and **Search: placeholder and icons** follow the unread-counter colors; the contacts-only background follows the shared background. These optional colors affect real channel and contact search as well as preview. Border geometry/focus width, search text, clear/filter actions and filtering behavior stay intact; clearing a color restores the current input theme. **Search: background (contacts)** appears after the shared search background and overrides only the contact screen, including its collapsed search box. Clearing it restores the shared search background, then the current input theme if the shared color is also unset. It is stored as `mcoa.colors.chats_search_contacts_background` and does not affect channel search or its preview. The other colors use `chats_search_border`, `chats_search_background`, `chats_search_text` and `chats_search_hint_icons` in `mcoa.colors`.


**Chats** controls the channel and contact list cards, including their previews, room-server and additional-key entries, CompanionCLI and channel groups. Its 20 optional colors are card border/background, chat title, message preview, service icons/text, channel index border/background/text/dot, unread counter background/text, contact public key and prefix border/background/text, plus search border/background/text/placeholder-and-icons. Service ink covers compression/mute/date indicators and the contact route/location/last-seen line. Avatar colors stay independent. Individual channel/group background and foreground colors take priority over the matching theme colors. When an individual color is cleared, that part falls back to the theme, then to the ordinary appearance if the theme slot is also unset. The individual foreground retains its existing scope (title, preview and service indicators); channel-index and unread-counter colors remain independent. These settings use `mcoa.colors.chats_*` keys and are included in storage and exports.

**MCOa settings → Channel indices** is on when indices are shown (it inverses the application's Hide channel indices setting). Like the other preference switches, it applies once on explicit activation/save-and-apply. You can change the application setting afterward without the theme forcing it back, including after restarting the app. The optional preference is stored as `mcoa.preferences.show_channel_indices`; old themes leave the app preference unchanged. Editing this switch only updates the draft and preview until the theme is applied.


**Incoming / Outgoing → Metadata background** sets the separated metadata area's color independently for each direction. The swatch and editable HEX field support the same palette, alpha and reset behavior as other optional theme colors. Clearing the field restores the theme surface color. The metadata background forms one continuous backing beneath the rounded message area. Its upper edge does not form a second pair of rounded corners at the join; the bottom corners remain rounded. This applies to both directions and does not change spacing or bubble width.

**Incoming / Outgoing → Metadata inner padding** adds 0–40 logical pixels at the top inside the metadata area, default 0. Each slider is enabled only while that direction's **Separate metadata** switch is on. The value is retained when separation is switched off. Unlike the message-to-metadata gap, this inset belongs to the metadata background and does not enlarge the rounded message area; existing small gaps within metadata remain. Colors and both padding values are included in theme storage/sharing under `mcoa.colors.incoming_metadata_background`, `mcoa.colors.outgoing_metadata_background`, `mcoa.incoming_metadata_top_padding` and `mcoa.outgoing_metadata_top_padding`.

**Incoming → Separate metadata** is off by default. It gives incoming metadata its own background using its **Metadata background** color (or the current theme surface color when unset), while the message area retains its incoming background and rounded corners. Both halves of the message-to-metadata gap remain in the message area. This works in channel, direct, room and additional-key chats and their previews; **Outgoing → Separate metadata** independently enables the same appearance for outgoing messages and is also off by default. Both directions keep their own message background and badge colors. The extra spacing slider remains an incoming-only setting. The independent switches are stored as `mcoa.separate_incoming_metadata` and `mcoa.separate_outgoing_metadata` and do not change app preferences.


**Incoming → Message-to-metadata spacing** adds 0–40 logical pixels between the message body and its metadata. The default is 0, preserving the current layout. The additional gap consists of two equal empty halves, reserved for separate styling later. It applies to incoming channel, direct and room messages, including the preview; outgoing messages retain their spacing. Existing small gaps between metadata rows remain unchanged. The value is saved and shared in `mcoa.incoming_metadata_spacing`; it does not change application preferences.


The editor's **MCOa settings** block contains five collapsed sections:
**Interface**, **Incoming**, **Outgoing**, **Chats**, and **MCOa settings**. These cards use
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
Sender name** sets the sender-name color in channel and contact chats. The
**Sender name brightness** slider precedes it: its midpoint leaves colored
names unchanged, moving left darkens them, and moving right lightens them while
preserving hue and transparency. It applies only to the application's colored
sender names; monochrome names retain their normal appearance. Setting an
explicit sender-name color resets brightness to the midpoint and disables the
slider. Clearing the color re-enables it at the midpoint, without restoring an
old brightness value. Brightness is stored with the theme and included in exports. Clearing it restores the application's ordinary sender-name
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


Message decorations: neutral incoming MCMP signature icons use incoming message text color, while outgoing MCMP icons use outgoing badge color. Shared-location text/icons use the message text color in both directions. Signature verification success, collision and error indicators retain their semantic colors. The channel header separates its send region and display filter with a small gap instead of a bullet.
