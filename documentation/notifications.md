# Notifications

## Overview

MeshCore Open provides both **system notifications** (push-style OS alerts) and **in-app unread badges** to inform users of new activity.

## Notification Types

### 1. Direct Message Notifications
- **Triggered when**: A new incoming message arrives from a Chat or Room contact
- **Title**: Contact's name
- **Body**: Message text (reactions show "Reacted [emoji]", GIFs show "Sent a GIF")
- **Priority**: High
- **Android channel**: `messages`

### 2. Channel Message Notifications
- **Triggered when**: A new message arrives on a non-muted channel
- **Title**: Channel name (or "Channel N" if unnamed)
- **Body**: `"<senderName>: <message text>"`
- **Priority**: High
- **Android channel**: `channel_messages`

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

### Notification Tap Behavior

Tapping a direct-message or channel notification restores/focuses the app and navigates to the corresponding contact chat or channel when that destination exists in the loaded session. Advertisement and batch-summary payloads currently only restore the app because they have no dedicated destination route.

## In-App Unread Badges

Red numeric badges appear throughout the UI:
- **Contacts list**: Each contact row shows a red pill badge (e.g., "3") for unread messages
- **Channels list**: Each channel row shows an unread badge
- **Chat screen subtitle**: Shows unread count inline
- Badges cap at "9999+" for display

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

Long-press a channel in the channels list → "Mute channel" / "Unmute channel". Muted channels do not generate OS notifications.

There is no per-contact muting.

## Rate Limiting

The notification system prevents notification storms:
- **Minimum interval**: 3 seconds between individual notifications
- **Batch window**: If multiple notifications arrive within 5 seconds, they are combined into a single summary notification on a fourth Android channel (`batch_summary`). The title is "MeshCore Activity" and the body lists the grouped counts (e.g., "2 messages, 1 channel message, 3 new nodes"). Batch summaries are Android-only; queued notifications that overflow the batch window are silently dropped on other platforms

## Notification Clearing

- **Opening a contact chat**: Cancels the OS notification and resets unread count
- **Opening a channel**: Cancels the channel notification and resets unread count
- **Opening Contacts screen**: Cancels all advertisement notifications

## Platform Support

| Platform | Message Notifs | Badge | Background Service |
|---|---|---|---|
| Android | Yes | Via notification number | Yes (foreground service) |
| iOS | Yes | Yes (app badge) | No |
| macOS | Yes | Yes | No |
| Windows | Yes | No | No |
| Linux | Yes (if D-Bus available) | No | No |
