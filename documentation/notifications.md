# Notifications

## Overview

MeshCore Open provides both **system notifications** (push-style OS alerts) and **in-app unread badges** to inform users of new activity.

On Android, message and service notifications use a monochrome icon in the
status bar. The conversation's thumbnail and reply actions remain part of
the expanded notification.

## Notification Types

### 1. Direct Message Notifications
- **Triggered when**: A new incoming message arrives from a Chat or Room contact
- **Title**: Contact's name
- **Body**: Message text, with localized summaries for structured messages (see below)
- **Priority**: High
- **Android channel**: `messages`
- **Android style**: conversation (MessagingStyle) showing the last few messages, with **Reply** and a hidden **Mark as read** action. When URL images are enabled, an image preview appears as the notification's thumbnail

### 2. Channel Message Notifications
- **Triggered when**: An incoming message is allowed by the channel notification mode
- **Title**: Channel name (or "Channel N" if unnamed)
- **Body**: `"<senderName>: <message text>"`
- **Priority**: High
- **Android channel**: `channel_messages`
- **Android style**: group conversation with each sender shown by name, with **Reply**, **Mute channel**, and a hidden **Mark as read** action

### Message Summaries

Direct and channel notifications summarize structured messages in the app's
language, rather than displaying their encoded contents:

- Reactions show the emoji, for example "Reacted 👍".
- Compact GIF messages and supported Giphy links show "Sent a GIF".
- AEIC image references show "Sent an image", including while the image is
  not decoded. Generating the summary does not start the image decoder.
- Shared map markers show "Shared a location", followed by the marker's label
  when present. The notification does not show the encoded coordinates.
- MCOimg retains its `MCOimg` label and existing picture attachment support.

Channel notifications retain the sender's name before the summary. The
original message stays unchanged in chat history and in the database.
Formatting these summaries does not fetch media or load image files. Existing
URL-image preview settings still control separate thumbnail loading.

### 3. Advertisement Notifications
- **Triggered when**: A new node is discovered on the mesh for the first time
- **Title**: "New [type] discovered" (e.g., "New Chat discovered")
- **Body**: Contact's name
- **Priority**: Default
- **Android channel**: `adverts`

### 4. Background Service Notification (Android Only)
- A persistent low-priority notification describing the current connection state
- Required by Android while the app retains its process and main Flutter engine for background BLE (or optional background TCP/wardrive work)
- Tap to re-launch the app
- **Does not auto-start on reboot** — the user must re-open the app manually after a phone restart
- The main engine sends an in-process heartbeat every 5 seconds. If a surviving or restarted foreground task receives no heartbeat for 20 seconds, the notification changes to the localized `app_connectionLostBreaked` text
- The foreground task does not own BLE and cannot recreate `MeshCoreConnector` after Android kills the entire process

Notification text states:

- **Connected**: the normal static background-service text
- **Reconnecting**: `app_connectionLostReconnect`, retained while BLE automatic reconnect continues
- **Engine/process unavailable**: `app_connectionLostBreaked`

### 5. Connected Radio Low-Battery Alerts

Open **Mod Settings → Battery → Notify on low battery**. The switch is enabled
by default. Select any of **5%, 10%, 15%, 20%, 25%, 30%**; the initial selection
is **10% and 25%**. An empty selection produces no battery alerts. The general
**Enable Notifications** switch and OS notification permission must also allow
notifications. Power-saving profiles are now reached from the same Battery section.

Each selected threshold needs two consecutive valid readings at or below it.
If several levels are confirmed together, only the lowest alert is shown.
The body names the radio and its estimated charge. Changing options preserves
the chosen levels; disabling alerts or deselecting a level cancels its existing
notification and suppresses queued notifications for that level.

Rising measured voltage suppresses alerts. Equal readings after a rise remain
suppressed until a decline is observed. The protocol provides voltage, not a
charger-connected flag: this is trend-based suppression, not charger detection.

The percentage uses the same per-radio chemistry or custom voltage range as
the battery indicator. A zero reading or, for ordinary profiles, a reading below
2 V does not trigger an alert and breaks the confirmation sequence. An explicit
custom/additional profile whose minimum is below 2 V remains supported. The
raw voltage and battery indicator are not changed by this notification filter.

A threshold alerts once per connection session until charge rises strictly
above it by five percentage points (for example, above **30%** for a **25%** alert).
Recharging past that boundary clears the corresponding notification and allows
another alert after two new low readings. Disconnecting, resetting the
connection handshake or changing radio identity clears the previous radio's
alert state. These alerts use existing battery responses; they add no polling
requests or timers, so power-saving battery intervals still apply.

Android uses a separate high-priority `low_battery` notification channel.
Other supported native platforms use their existing notification backend.
Battery show/cancel operations run in order, independently of message alerts;
a delayed show is followed by its cleanup if the radio disconnects meanwhile.

### Replying from Notifications, Watches, and Android Auto (Android)

Message notifications can be answered without opening the app, from the notification shade, a paired Wear OS or Galaxy watch, or Android Auto (which reads messages aloud and takes voice replies).

- **Reply** sends through the connected radio exactly like the chat screen: same length limits, SMAZ and Cyr2Lat handling, and retries. Your reply is then added to the notification.
- **Replies over the message limit** are split at word boundaries into up to 3 messages. Longer replies are not sent; a "Reply not sent" notification asks you to open the app.
- **Mark as read** clears the unread count on the phone only. MeshCore has no read receipts, so nothing is sent over the mesh.
- **Mute channel** (phone and watch) selects Mentions only, retaining the fork's existing mention exception. The chat bell also offers Fully muted.
- If the radio is disconnected, the conversation is no longer on the radio, the radio reports a send error, or the app isn't running, a "Reply not sent" notification explains why. The reply is not queued. If a split reply fails partway, earlier parts may already have been sent.
- Replies are sent as typed; composer translation is not applied.

iOS notifications do not have reply actions yet.

### Android Auto

MeshCore Open works in Android Auto as a notification-based messaging app. There is no MeshCore screen in the car; Android Auto provides the interface.

Android Auto support is **enabled by default** in this fork, in all three build
profiles. To omit it from a build, pass the `androidAuto=false` Gradle property:

```bash
flutter build apk --release --android-project-arg=androidAuto=false
```

Omit the property or pass `androidAuto=true` to include support. Only `true` and
`false` are accepted; another value fails the build configuration.

When enabled, the build merges `android/app/src/androidAuto/` (the car manifest
metadata and `automotive_app_desc.xml`). With `false`, those entries/resources
are absent and Android Auto does not list the app. Phone/watch notification
replies and the app's common services remain available in either variant.
The property is a build option, not an in-app switch. Upstream uses default-off
to separate builds distributed for Android Auto through Google Play; this fork
retains its existing default-on behavior.

- New direct and channel messages appear on the car display and can be read aloud.
- Reply by voice or with a suggested reply; replies follow the rules above (splitting, failure notifications, no translation).
- Android Auto shows **Reply** and **Mark as read**. **Mute channel** is marked as a mute action, but Android Auto only documents reply and mark-as-read for messaging apps, so mute may not appear in the car; use the phone, a watch, or the bell icon.
- Setup: none beyond allowing MeshCore Open notifications. The app must be running with the radio connected, as for any notification.

Limitations:

- Only messages that arrive during the Android Auto session are shown; there is no conversation list or message history in the car.
- You can reply to a received message, but you cannot start a new message by voice (for example, "send a MeshCore message to Public"). Android Auto does not currently offer this to third-party messaging apps.
- Sideloaded or debug builds only appear in Android Auto when its developer setting **Unknown sources** is on.

Testing with the Desktop Head Unit (DHU): enable Android Auto developer mode (tap **Version** about 10 times in Android Auto settings), turn on **Unknown sources**, choose **Start head unit server**, run `adb forward tcp:5277 tcp:5277`, then start `desktop-head-unit` from the SDK's `extras/google/auto` package. Use DHU 2.1 or newer; version 2.0 disconnects from current Android Auto releases.

### Checking Android Auto build variants

After generating the merged manifests for a default build, `androidAuto=true`
and `androidAuto=false`, save each XML under a different name and compare them:

```sh
python -B tool/check_android_auto_manifests.py --default default.xml --enabled enabled.xml --disabled disabled.xml
```

Use Gradle's actual `processDebugMainManifest` outputs, not the source manifests.
The checker requires default and true to match, and false to differ only by the
car metadata. It also checks that the notification action receiver and backup
references remain common. It does not build APKs, validate packaged resources,
or test an Android Auto head unit; both build variants still need Android
build/device verification. For the current AGP, the debug XML is under
`build/app/intermediates/merged_manifest/debug/processDebugMainManifest/AndroidManifest.xml`.

### Notification Tap Behavior

Tapping a direct-message or channel notification restores/focuses the app and navigates to the corresponding contact chat or channel when that destination exists in the loaded session. Advertisement and batch-summary payloads currently only restore the app because they have no dedicated destination route.

## In-App Unread Badges

Red numeric badges appear throughout the UI:
- **Contacts list**: Each contact row shows a red pill badge (e.g., "3") for unread messages
- **Channels list**: Each channel row shows an unread badge
- **Chat screen subtitle**: Shows unread count inline
- Badges cap at "9999+" for display

### App Icon Badge (iOS and macOS)

The app icon (iOS) or dock icon (macOS) badge shows the total unread count. It is set directly by the app, so it clears when you read your messages, and it is re-synced to the real unread total whenever the app returns to the foreground. On Android the launcher badge comes from the active notifications instead.

### How Unread Counts Work

- Stored per contact (by public key) and per channel, **scoped to the connected device's identity** (first 10 hex characters of its public key). Switching between different radios gives each its own independent unread state
- **Suppressed when viewing**: Opening a chat resets the count to 0 and cancels the OS notification
- **Ignored for**: Outgoing messages, CLI messages, and repeater contacts
- Debounced writes (500ms) to avoid excessive storage I/O during message bursts

## Notification Settings

Access via **App Settings → Notifications**:

| Setting | Default | Description |
|---|---|---|
| Enable Notifications | On | Master toggle; requests OS permission when turned on |
| Message Notifications | On | DM alerts (greyed out if master is off) |
| Channel Message Notifications | On | Channel alerts (greyed out if master is off) |
| Advertisement Notifications | On | New node alerts (greyed out if master is off) |

### Per-Channel Muting

Choose All messages, Mentions only or Fully muted from the channel controls. Existing muted channels retain their mentions exception.

The mode picker scrolls when a short screen, large system text or the keyboard
leaves too little room for all three choices. Scroll to a choice and tap it;
the selected mode is still marked when you reopen the picker.

- The bell icon in the channel chat app bar
- Long-press a channel in the channels list → "Notification settings"
- **Mute channel** on a channel notification (Android)

There is no per-contact muting.

## Rate Limiting

The notification system prevents notification storms:
- **Minimum interval**: 3 seconds between alerts
- **Messages**: the first update to a conversation posts immediately. Further messages in the same 800 ms window update that card together. The Android conversation card keeps the latest six messages and its reply actions.
- **Sound**: Android, iOS and macOS update silently within the three-second interval and allow at most one audible conversation alert per radio queue drain.
- **Advertisements batch window**: If multiple advertisement notifications arrive within 5 seconds, they are combined into a single summary notification on a fourth Android channel (`batch_summary`). The title is "MeshCore Activity" and the body lists the count (e.g., "3 new nodes"). Batch summaries are Android-only; queued notifications that overflow the batch window are silently dropped on other platforms

## Notification Clearing

- **Opening a contact chat**: Cancels the OS notification and resets unread count
- **Opening a channel**: Cancels the channel notification and resets unread count
- **Switching radios or replacing a channel in a slot**: Clears stale cards and pending updates. After an app restart, clearing old cards depends on which active notifications the platform exposes.
- **Opening Contacts screen**: Cancels all advertisement notifications

## Translation and image references

Automatic incoming translation can also translate notification text when enabled with a ready local model. GIF and URL-image retrieval still need internet; receiving a notification does not make those references available offline. For image packet progress and reconstruction states, use [channel image chat](image-messages.md).

## Platform Support

| Platform | Message Notifs | Reply / Mute Actions | Android Auto | Badge | Background Service |
|---|---|---|---|---|---|
| Android | Yes | Yes (incl. watches) | Yes | Via notification number | Yes (foreground service) |
| iOS | Yes | No | — | Yes (app badge) | No |
| macOS | Yes | No | — | Yes (dock badge) | No |
| Windows | Yes | No | — | No | No |
| Linux | Yes (if D-Bus available) | No | — | No | No |


## Per-channel notification modes (Advanced mod)

The bell in a channel chat and the notification entry in the channel's context
menu open a three-choice picker:

- **All messages**: notify for incoming channel messages allowed by the global settings.
- **Mentions only**: notify for `@[name]` or plain `@name`, matching either the
  node's name or its configured sender name in this channel. Matching ignores
  case; bracketed mentions retain support for spaces inside the brackets.
  Plain mentions require the full name and word boundaries.
- **Fully muted**: suppress channel notifications, including mentions.

Existing muted channels keep their prior **Mentions only** behavior. Full
silence is an explicit new choice. The modes affect notifications; incoming
messages remain in history and keep the existing unread behavior. Blocked
senders remain suppressed, and received translations do not create mentions.
Settings follow linked previous names when a channel is renamed. Selecting
All clears inherited restrictions under those linked names too. The existing
Mute action in a system notification retains the mentions exception.

The modification setting that hides the chat's bell still applies. The channel
list shows different icons for mentions-only and fully muted channels.
