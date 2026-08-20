# MeshCore BLE Protocol Documentation

## Overview

The MeshCore BLE protocol implements a binary frame-based communication system using Nordic UART Service (NUS) for low-level transport. The protocol supports mesh networking operations including contact management, text messaging, channel communication, and device configuration.

## BLE Transport Layer

### Nordic UART Service (NUS)

**Service UUID**: `6e400001-b5a3-f393-e0a9-e50e24dcca9e`

**Characteristics**:
- **RX Characteristic** (Write): `6e400002-b5a3-f393-e0a9-e50e24dcca9e`
  - Used for sending commands/data TO the device
  - Supports write with/without response

- **TX Characteristic** (Notify): `6e400003-b5a3-f393-e0a9-e50e24dcca9e`
  - Used for receiving responses/data FROM the device
  - Notifications enabled during connection

### Connection Flow

1. **Scan** for devices with known name prefixes (defined in `MeshCoreUuids.deviceNamePrefixes`):
    - `MeshCore-`
    - `Whisper-`
    - `WisCore-`
    - `HT-`
    - `LowMesh_MC_`
2. **Connect** with 15-second timeout
3. **Request MTU** of 185 bytes (falls back to default if unsupported)
4. **Discover services** and locate NUS characteristics
5. **Enable notifications** on TX characteristic (with 3 retry attempts)
6. **Initialize device** by sending:
   - `CMD_DEVICE_QUERY` - Get device capabilities
   - `CMD_APP_START` - Register app with device
   - `CMD_GET_BATT_AND_STORAGE` - Request battery status

## Frame Structure

### Command Frames (App → Device)

All command frames start with a single-byte command code followed by command-specific data.

**Format**: `[command_code][parameters...]`

**Maximum Frame Size**: 176 bytes (`maxFrameSize`)

### Response Frames (Device → App)

Response frames start with a response code, followed by response-specific data.

**Format**: `[response_code][data...]`

### Push Frames (Device → App, Asynchronous)

Push frames are unsolicited notifications from the device, using codes ≥ 0x80.

**Format**: `[push_code][data...]`

## Command Codes (0x01-0x40)

Commands implemented by the Flutter connector in this checkout:

| Code | Name | Description |
|------|------|-------------|
| 0x01 | `CMD_APP_START` | Register application with device |
| 0x02 | `CMD_SEND_TXT_MSG` | Send direct text message to contact |
| 0x03 | `CMD_SEND_CHANNEL_TXT_MSG` | Send text message to channel |
| 0x04 | `CMD_GET_CONTACTS` | Request contact list |
| 0x05 | `CMD_GET_DEVICE_TIME` | Get device's current time |
| 0x06 | `CMD_SET_DEVICE_TIME` | Sync device time |
| 0x07 | `CMD_SEND_SELF_ADVERT` | Broadcast self advertisement |
| 0x08 | `CMD_SET_ADVERT_NAME` | Set node display name |
| 0x09 | `CMD_ADD_UPDATE_CONTACT` | Add/update contact with custom path |
| 0x0A | `CMD_SYNC_NEXT_MESSAGE` | Request next queued message |
| 0x0B | `CMD_SET_RADIO_PARAMS` | Configure LoRa radio settings |
| 0x0C | `CMD_SET_RADIO_TX_POWER` | Set transmit power |
| 0x0D | `CMD_RESET_PATH` | Clear contact's routing path |
| 0x0E | `CMD_SET_ADVERT_LATLON` | Set node GPS coordinates |
| 0x0F | `CMD_REMOVE_CONTACT` | Delete contact from device |
| 0x10 | `CMD_SHARE_CONTACT` | Share contact via mesh |
| 0x11 | `CMD_EXPORT_CONTACT` | Export contact data |
| 0x12 | `CMD_IMPORT_CONTACT` | Import contact data |
| 0x13 | `CMD_REBOOT` | Reboot device |
| 0x14 | `CMD_GET_BATT_AND_STORAGE` | Request battery and storage info |
| 0x16 | `CMD_DEVICE_QUERY` | Query device capabilities |
| 0x1A | `CMD_SEND_LOGIN` | Authenticate to repeater |
| 0x1B | `CMD_SEND_STATUS_REQ` | Request status from repeater |
| 0x1E | `CMD_GET_CONTACT_BY_KEY` | Get specific contact by public key |
| 0x1F | `CMD_GET_CHANNEL` | Get channel configuration |
| 0x20 | `CMD_SET_CHANNEL` | Configure channel |
| 0x21 | `CMD_SIGN_START` | Start signing operation |
| 0x22 | `CMD_SIGN_DATA` | Add data to be signed |
| 0x23 | `CMD_SIGN_FINISH` | Finish signing and get signature |
| 0x24 | `CMD_SEND_TRACE_PATH` | Send path trace request |
| 0x26 | `CMD_SET_OTHER_PARAMS` | Set miscellaneous parameters |
| 0x27 | `CMD_SEND_TELEMETRY_REQ` | Request telemetry data (deprecated) |
| 0x28 | `CMD_GET_CUSTOM_VARS` | Get custom variables |
| 0x29 | `CMD_SET_CUSTOM_VAR` | Set custom variable |
| 0x32 | `CMD_SEND_BINARY_REQ` | Send binary request to contact |
| 0x36 | `CMD_SET_FLOOD_SCOPE` | Set flood routing scope (v8+) |
| 0x37 | `CMD_SEND_CONTROL_DATA` | Send control data (v8+) |
| 0x38 | `CMD_GET_STATS` | Get statistics (v8+, sub-types: core/radio/packets) |
| 0x39 | `CMD_SEND_ANON_REQ` | Send an anonymous request |
| 0x3A | `CMD_SET_AUTO_ADD_CONFIG` | Set auto-add configuration |
| 0x3B | `CMD_GET_AUTO_ADD_CONFIG` | Get auto-add configuration |
| 0x3D | `CMD_SET_PATH_HASH_MODE` | Set path hash width |
| 0x3E | `CMD_SEND_CHANNEL_DATA` | Send typed channel data |
| 0x3F | `CMD_SET_DEFAULT_FLOOD_SCOPE` | Set default flood scope |
| 0x40 | `CMD_GET_DEFAULT_FLOOD_SCOPE` | Query default flood scope |

### Firmware-Only and Legacy Command Mappings

The following commands are retained because they are documented by older or
firmware-specific MeshCore implementations, even though the Flutter connector
in this checkout does not expose them. Their availability and numeric mapping
must be verified against the exact firmware and protocol version in use.

| Code | Name | Description |
|------|------|-------------|
| 0x15 | `CMD_SET_TUNING_PARAMS` | Set device tuning parameters |
| 0x17 | `CMD_EXPORT_PRIVATE_KEY` | Export device private key (security-sensitive) |
| 0x18 | `CMD_IMPORT_PRIVATE_KEY` | Import device private key (security-sensitive) |
| 0x19 | `CMD_SEND_RAW_DATA` | Send raw data to contact |
| 0x1C | `CMD_HAS_CONNECTION` | Check whether a connection exists to a contact |
| 0x1D | `CMD_LOGOUT` | Disconnect from repeater |
| 0x25 | `CMD_SET_DEVICE_PIN` | Set device PIN for pairing |
| 0x2A | `CMD_GET_ADVERT_PATH` | Get advertisement path for contact |
| 0x2B | `CMD_GET_TUNING_PARAMS` | Get device tuning parameters |
| 0x33 | `CMD_FACTORY_RESET` | Factory reset device |
| 0x34 | `CMD_SEND_PATH_DISCOVERY_REQ` | Request path discovery |
| 0x39 | `CMD_GET_RADIO_SETTINGS` | Legacy mapping; conflicts with current `CMD_SEND_ANON_REQ` |

## Response Codes (0x00-0x1C)

Responses handled by the Flutter connector in this checkout:

| Code | Name | Description |
|------|------|-------------|
| 0x00 | `RESP_CODE_OK` | Generic success |
| 0x01 | `RESP_CODE_ERR` | Generic error |
| 0x02 | `RESP_CODE_CONTACTS_START` | Beginning of contact list |
| 0x03 | `RESP_CODE_CONTACT` | Contact entry |
| 0x04 | `RESP_CODE_END_OF_CONTACTS` | End of contact list |
| 0x05 | `RESP_CODE_SELF_INFO` | Device identity and settings |
| 0x06 | `RESP_CODE_SENT` | Message sent (includes ACK hash) |
| 0x07 | `RESP_CODE_CONTACT_MSG_RECV` | Received direct message (v1/v2) |
| 0x08 | `RESP_CODE_CHANNEL_MSG_RECV` | Received channel message (v1/v2) |
| 0x09 | `RESP_CODE_CURR_TIME` | Current device time |
| 0x0A | `RESP_CODE_NO_MORE_MESSAGES` | Queue empty |
| 0x0B | `RESP_CODE_EXPORT_CONTACT` | Exported contact data |
| 0x0C | `RESP_CODE_BATT_AND_STORAGE` | Battery and storage status |
| 0x0D | `RESP_CODE_DEVICE_INFO` | Device capabilities |
| 0x10 | `RESP_CODE_CONTACT_MSG_RECV_V3` | Received direct message (v3) |
| 0x11 | `RESP_CODE_CHANNEL_MSG_RECV_V3` | Received channel message (v3) |
| 0x12 | `RESP_CODE_CHANNEL_INFO` | Channel configuration |
| 0x13 | `RESP_CODE_SIGN_START` | Signing operation started |
| 0x14 | `RESP_CODE_SIGNATURE` | Digital signature result |
| 0x15 | `RESP_CODE_CUSTOM_VARS` | Custom variables data |
| 0x18 | `RESP_CODE_STATS` | Statistics data (v8+) |
| 0x19 | `RESP_CODE_AUTO_ADD_CONFIG` | Auto-add configuration |
| 0x1B | `RESP_CODE_CHANNEL_DATA_RECV` | Incoming typed channel data |
| 0x1C | `RESP_CODE_DEFAULT_FLOOD_SCOPE` | Current default flood scope |

### Firmware-Only and Legacy Response Mappings

| Code | Name | Description |
|------|------|-------------|
| 0x0E | `RESP_CODE_PRIVATE_KEY` | Exported private key |
| 0x0F | `RESP_CODE_DISABLED` | Feature disabled |
| 0x16 | `RESP_CODE_ADVERT_PATH` | Advertisement path data |
| 0x17 | `RESP_CODE_TUNING_PARAMS` | Tuning parameters |
| 0x19 | `RESP_CODE_RADIO_SETTINGS` | Legacy mapping; conflicts with current `RESP_CODE_AUTO_ADD_CONFIG` |

## Push Codes (0x80-0x8E)

Asynchronous notifications from device:

| Code | Name | Description |
|------|------|-------------|
| 0x80 | `PUSH_CODE_ADVERT` | Advertisement received |
| 0x81 | `PUSH_CODE_PATH_UPDATED` | Contact path changed |
| 0x82 | `PUSH_CODE_SEND_CONFIRMED` | Message ACK received |
| 0x83 | `PUSH_CODE_MSG_WAITING` | New messages in queue |
| 0x84 | `PUSH_CODE_RAW_DATA` | Raw data received from contact |
| 0x85 | `PUSH_CODE_LOGIN_SUCCESS` | Repeater login succeeded |
| 0x86 | `PUSH_CODE_LOGIN_FAIL` | Repeater login failed |
| 0x87 | `PUSH_CODE_STATUS_RESPONSE` | Repeater status response |
| 0x88 | `PUSH_CODE_LOG_RX_DATA` | Raw LoRa packet log |
| 0x89 | `PUSH_CODE_TRACE_DATA` | Path trace response |
| 0x8A | `PUSH_CODE_NEW_ADVERT` | New contact advertisement |
| 0x8B | `PUSH_CODE_TELEMETRY_RESPONSE` | Telemetry data response |
| 0x8C | `PUSH_CODE_BINARY_RESPONSE` | Binary request response |
| 0x8D | `PUSH_CODE_PATH_DISCOVERY_RESPONSE` | Path discovery response (firmware-only/legacy) |
| 0x8E | `PUSH_CODE_CONTROL_DATA` | Control data received (v8+) |

## Key Frame Formats

### CMD_APP_START (0x01)

Registers the application with the device.

**Format**:
```
[0x01][app_ver][reserved x6][app_name...]\0
```

**Fields**:
- `app_ver` (1 byte): Application version number
- `reserved` (6 bytes): Reserved for future use (zeros)
- `app_name` (variable): Null-terminated UTF-8 app name

**Example**:
```dart
buildAppStartFrame(appName: 'MeshCoreOpen', appVersion: 1)
// [0x01][0x01][0x00 x6]["MeshCoreOpen"][0x00]
```

### CMD_SEND_TXT_MSG (0x02)

Sends a direct message to a contact.

**Format**:
```
[0x02][txt_type][attempt][timestamp x4][pub_key_prefix x6][text...]\0
```

**Fields**:
- `txt_type` (1 byte): Message type (0=plain, 1=CLI data)
- `attempt` (1 byte): Retry attempt number (0-3)
- `timestamp` (4 bytes LE): Unix timestamp in seconds
- `pub_key_prefix` (6 bytes): First 6 bytes of recipient's public key
- `text` (variable): UTF-8 message text, null-terminated

**Max text length**: 160 bytes after overhead (matching firmware `MAX_TEXT_LEN`)

**Example**:
```dart
buildSendTextMsgFrame(recipientPubKey, "Hello mesh!", attempt: 0)
```

### CMD_SEND_CHANNEL_TXT_MSG (0x03)

Sends a message to a channel (broadcast group).

**Format**:
```
[0x03][txt_type][channel_idx][timestamp x4][text...]\0
```

**Fields**:
- `txt_type` (1 byte): Message type (0=plain)
- `channel_idx` (1 byte): Channel index (0-7 typically)
- `timestamp` (4 bytes LE): Unix timestamp in seconds
- `text` (variable): UTF-8 message text, null-terminated

**Max text length**: Depends on sender name prefix (see `maxChannelMessageBytes()`)

### CMD_GET_CONTACTS (0x04)

Requests contact list from device.

**Format**:
```
[0x04]                     # Get all contacts
[0x04][since x4]          # Get contacts modified after timestamp
```

**Fields**:
- `since` (4 bytes LE, optional): Unix timestamp filter

**Response**:
- `RESP_CODE_CONTACTS_START` (0x02)
- Multiple `RESP_CODE_CONTACT` (0x03) frames
- `RESP_CODE_END_OF_CONTACTS` (0x04)

### CMD_GET_CONTACT_BY_KEY (0x1E)

Fetches a specific contact by their public key.

**Format**:
```
[0x1E][pub_key x32]
```

**Fields**:
- `pub_key` (32 bytes): Contact's Ed25519 public key

**Response**:
- `RESP_CODE_CONTACT` (0x03) if found
- `RESP_CODE_ERR` (0x01) with `ERR_CODE_NOT_FOUND` (2) if not found

**Use case**: Efficiently check if a specific contact exists without fetching entire contact list.

**Example**:
```dart
// Fetch specific contact
final pubKey = hexToPubKey('a1b2c3d4...');
await connector.getContactByKey(pubKey);

// Response handled in _handleContact() as usual
```

### CMD_SET_DEVICE_TIME (0x06)

Synchronizes device clock with app.

**Format**:
```
[0x06][timestamp x4]
```

**Fields**:
- `timestamp` (4 bytes LE): Current Unix timestamp in seconds

### CMD_SET_ADVERT_NAME (0x08)

Sets the device's display name for advertisements.

**Format**:
```
[0x08][name...]
```

**Fields**:
- `name` (variable): UTF-8 name, max 31 bytes (truncated if longer)

### CMD_SET_ADVERT_LATLON (0x0E)

Sets the device's GPS coordinates.

**Format**:
```
[0x0E][lat x4][lon x4]
```

**Fields**:
- `lat` (4 bytes LE): Latitude × 1,000,000 (signed int32)
- `lon` (4 bytes LE): Longitude × 1,000,000 (signed int32)

**Example**:
```dart
// 37.7749° N, -122.4194° W (San Francisco)
buildSetAdvertLatLonFrame(37.7749, -122.4194)
// lat_int = 37774900, lon_int = -122419400
```

### CMD_ADD_UPDATE_CONTACT (0x09)

Adds a new contact or updates an existing contact's routing path.

**Format**:
```
[0x09][pub_key x32][type][flags][path_len][path x64][name x32][timestamp x4]
```

**Fields**:
- `pub_key` (32 bytes): Contact's public key
- `type` (1 byte): Advertisement type (1=chat, 2=repeater, 3=room, 4=sensor)
- `flags` (1 byte): Contact flags
- `path_len` (1 byte): Number of path bytes used
- `path` (64 bytes): Custom routing path (padded with zeros)
- `name` (32 bytes): Contact name, null-padded UTF-8
- `timestamp` (4 bytes LE): Unix timestamp

**Total size**: 136 bytes

### CMD_RESET_PATH (0x0D)

Clears a contact's custom path, reverting to flood mode.

**Format**:
```
[0x0D][pub_key x32]
```

**Fields**:
- `pub_key` (32 bytes): Contact's public key

### CMD_SET_RADIO_PARAMS (0x0B)

Configures LoRa radio parameters.

**Format**:
```
[0x0B][freq x4][bw x4][sf][cr]
```

**Fields**:
- `freq` (4 bytes LE): Frequency in Hz (300,000 - 2,500,000)
- `bw` (4 bytes LE): Bandwidth in Hz (7,000 - 500,000)
- `sf` (1 byte): Spreading factor (5-12)
- `cr` (1 byte): Coding rate (5-8)

**Example**:
```dart
// 915 MHz, 125 kHz BW, SF7, CR 4/5
buildSetRadioParamsFrame(915000000, 125000, 7, 5)
```

### CMD_SET_CHANNEL (0x20)

Creates or updates a channel configuration.

**Format**:
```
[0x20][idx][name x32][psk x16]
```

**Fields**:
- `idx` (1 byte): Channel index (0-7)
- `name` (32 bytes): Channel name, null-padded UTF-8
- `psk` (16 bytes): Pre-shared key for encryption

**To delete a channel**: Send empty name and zero PSK

### RESP_CODE_SELF_INFO (0x05)

Device identity and current settings.

**Format**:
```
[0x05][adv_type][tx_pwr][max_pwr][pub_key x32][lat x4][lon x4][multi_acks]
[adv_loc_policy][telemetry][manual_add][freq x4][bw x4][sf][cr][name...]
```

**Fields**:
- `adv_type` (1 byte): Advertisement type (1=chat, 2=repeater)
- `tx_pwr` (1 byte): Current TX power in dBm
- `max_pwr` (1 byte): Maximum TX power in dBm
- `pub_key` (32 bytes): Device's public key
- `lat` (4 bytes LE): Latitude × 1,000,000
- `lon` (4 bytes LE): Longitude × 1,000,000
- `multi_acks` (1 byte): Multi-ACK mode flag
- `adv_loc_policy` (1 byte): Location advertisement policy
- `telemetry` (1 byte): Telemetry mode flags
- `manual_add` (1 byte): Manual contact addition mode
- `freq` (4 bytes LE): Radio frequency in Hz
- `bw` (4 bytes LE): Radio bandwidth in Hz
- `sf` (1 byte): Spreading factor
- `cr` (1 byte): Coding rate
- `name` (variable): Node name, null-terminated UTF-8

**Minimum size**: 58 bytes (without name)

### RESP_CODE_CONTACT (0x03)

Contact entry from device.

**Format**:
```
[0x03][pub_key x32][type][flags][path_len][path x64][name x32][timestamp x4]
[lat x4][lon x4][lastmod x4]
```

**Fields**:
- `pub_key` (32 bytes): Contact's public key
- `type` (1 byte): Contact type (1=chat, 2=repeater, 3=room, 4=sensor)
- `flags` (1 byte): Contact flags
- `path_len` (1 byte): Path length (0xFF = flood mode)
- `path` (64 bytes): Routing path data
- `name` (32 bytes): Contact name, null-terminated UTF-8
- `timestamp` (4 bytes LE): Last seen timestamp
- `lat` (4 bytes LE): Latitude × 1,000,000
- `lon` (4 bytes LE): Longitude × 1,000,000
- `lastmod` (4 bytes LE): Last modification timestamp

**Total size**: 148 bytes

**Path length interpretation**:
- `-1` (0xFF): Flood mode (no direct path)
- `≥0`: Direct path with N hops

### RESP_CODE_CONTACT_MSG_RECV_V3 (0x10)

Received direct message (protocol version 3).

**Format**:
```
[0x10][snr][res x2][prefix x6][path_len][txt_type][timestamp x4][extra? x4][text...]
```

**Fields**:
- `snr` (1 byte): Signal-to-noise ratio
- `res` (2 bytes): Reserved
- `prefix` (6 bytes): Sender's public key prefix
- `path_len` (1 byte): Path length (0xFF = direct)
- `txt_type` (1 byte): Text type (bits 7-2: type, bits 1-0: flags)
  - Type 0: Plain text
  - Type 1: CLI data
- `timestamp` (4 bytes LE): Message timestamp (Unix seconds)
- `extra` (4 bytes, optional): Extra data for signed/plain variants
- `text` (variable): Message text, null-terminated

**Text decoding**:
1. Try reading at base offset (timestamp + 4)
2. If empty and room for extra bytes, try offset + 4
3. Check for SMAZ compression prefix
4. Decode as UTF-8

### RESP_CODE_CHANNEL_MSG_RECV_V3 (0x11)

Received channel message (protocol version 3).

**Format**:
```
[0x11][snr][res x2][channel_idx][path_len][txt_type][timestamp x4][sender_name...]: [text...]
```

**Fields**:
- `snr` (1 byte): Signal-to-noise ratio
- `res` (2 bytes): Reserved
- `channel_idx` (1 byte): Channel index
- `path_len` (1 byte): Path length
- `txt_type` (1 byte): Text type
- `timestamp` (4 bytes LE): Message timestamp
- Combined text format: `"[sender_name]: [message_text]"`

### RESP_CODE_SENT (0x06)

Confirmation that message was transmitted to LoRa radio.

**Format**:
```
[0x06][is_flood][ack_hash x4][timeout_ms x4]
```

**Fields**:
- `is_flood` (1 byte): 1 if flood mode, 0 if direct path
- `ack_hash` (4 bytes): Hash for matching future ACK
- `timeout_ms` (4 bytes LE): Expected ACK timeout in milliseconds

### PUSH_CODE_SEND_CONFIRMED (0x82)

ACK received for a sent message.

**Format**:
```
[0x82][ack_hash x4][trip_time_ms x4]
```

**Fields**:
- `ack_hash` (4 bytes): Hash matching RESP_CODE_SENT
- `trip_time_ms` (4 bytes LE): Round-trip time in milliseconds

### PUSH_CODE_PATH_UPDATED (0x81)

Notification that a contact's path has been updated by the device.

**Format**:
```
[0x81][pub_key x32]
```

**Fields**:
- `pub_key` (32 bytes): Contact whose path changed

**Handler action**: Request updated contact list

### RESP_CODE_BATT_AND_STORAGE (0x0C)

Battery and storage status.

**Format**:
```
[0x0C][battery_mv x2][storage_used_kb x4][storage_total_kb x4]
```

**Fields**:
- `battery_mv` (2 bytes LE): Battery voltage in millivolts
- `storage_used_kb` (4 bytes LE): Used storage in kilobytes
- `storage_total_kb` (4 bytes LE): Total storage in kilobytes

**Battery percentage calculation**:
```dart
// Chemistry-specific voltage ranges:
// LiFePO4: 2600-3650 mV
// LiPo/NMC: 3000-4200 mV
int percent = ((mv - minMv) * 100) / (maxMv - minMv);
```

### RESP_CODE_DEVICE_INFO (0x0D)

Device capabilities and limits.

**Format**:
```
[0x0D][protocol_ver][max_contacts_div2][max_channels]
```

**Fields**:
- `protocol_ver` (1 byte): Protocol version
- `max_contacts_div2` (1 byte): Max contacts ÷ 2 (actual = value × 2)
- `max_channels` (1 byte): Max supported channels

**Example**: `[0x0D][0x03][0x10][0x08]` = v3, 32 contacts, 8 channels

### RESP_CODE_AUTO_ADD_CONFIG (0x19)

Returns the current automatic-contact-addition flags.

### RESP_CODE_RADIO_SETTINGS (0x19, legacy/firmware-specific)

In firmware variants where response code `0x19` is assigned to radio settings,
the response contains the current LoRa parameters. This mapping conflicts with
`RESP_CODE_AUTO_ADD_CONFIG` in the current Flutter protocol, so the expected
layout must be selected from the negotiated protocol version and target
firmware, not from the numeric code alone.

**Legacy format**:
```
[0x19][freq x4][bw x4][sf][cr]
```

**Fields**:
- `freq` (4 bytes LE): Frequency in Hz
- `bw` (4 bytes LE): Bandwidth in Hz
- `sf` (1 byte): Spreading factor (5-12)
- `cr` (1 byte): Coding rate (5-8, subtract 4 for actual CR)

### RESP_CODE_CHANNEL_DATA_RECV (0x1B)

Carries an incoming typed channel `GROUP_DATA` payload.

### RESP_CODE_DEFAULT_FLOOD_SCOPE (0x1C)

Returns the node's current default flood scope.

## Additional and Firmware-Specific Commands

Some commands below are implemented by particular firmware versions but are
not exposed by the Flutter connector in this checkout. Verify them against the
target firmware before use, especially where the tables above document a code
collision.

### CMD_GET_ADVERT_PATH (0x2A)

Get the recently heard advertisement path for a contact.

**Purpose**: Retrieves the inbound path that was used when the contact's
advertisement was last received. Useful for discovering optimal paths.

**Format**:
```
[0x2A][pub_key_prefix x6]
```

**Response**: `RESP_CODE_ADVERT_PATH` (0x16) with path data

### CMD_GET_STATS (0x38)

Get device statistics (protocol version 8+).

**Format**:
```
[0x38][stats_type]
```

**Stats types**:
- `0x00`: Core stats (packet counts, air time)
- `0x01`: Radio stats (RSSI, SNR, noise floor)
- `0x02`: Packet stats (detailed packet analysis)

**Response**: `RESP_CODE_STATS` (0x18) with statistics data

### CMD_SEND_TELEMETRY_REQ (0x27)

Request telemetry data from a contact (deprecated in favor of binary requests).

**Purpose**: Request sensor data, battery status, or environmental data from remote nodes.

**Response**: `PUSH_CODE_TELEMETRY_RESPONSE` (0x8B)

### CMD_SEND_PATH_DISCOVERY_REQ (0x34)

Request path discovery to a contact.

**Purpose**: Actively discover available paths to a contact by broadcasting a
discovery request.

**Response**: `PUSH_CODE_PATH_DISCOVERY_RESPONSE` (0x8D) with discovered paths

### CMD_SET_FLOOD_SCOPE (0x36)

Set flood routing scope (v8+).

**Purpose**: Configure geographic or logical boundaries for flood routing to reduce mesh congestion.

**Format**:
```
[0x36][scope_data...]
```

### CMD_FACTORY_RESET (0x33)

Factory reset the device.

**Purpose**: Erase all stored data (contacts, keys, settings) and return to
factory defaults.

**Format**:
```
[0x33]
```

**Response**: `RESP_CODE_OK` or `RESP_CODE_ERR`

**WARNING**: This erases the device's identity. Use with caution.

### CMD_EXPORT_PRIVATE_KEY (0x17) / CMD_IMPORT_PRIVATE_KEY (0x18)

Export or import the device's Ed25519 private key on firmware variants that
support these commands.

**Security**: These commands should be protected by device PIN or other
authentication and are not exposed by the current Flutter connector.

**Export format**:
```
[0x17]
```

**Import format**:
```
[0x18][private_key x32]
```

**Response**: `RESP_CODE_PRIVATE_KEY` (0x0E) or `RESP_CODE_OK`

### CMD_GET_CUSTOM_VARS (0x28) / CMD_SET_CUSTOM_VAR (0x29)

Get or set custom device variables for application-specific configuration.

**Get format**:
```
[0x28]
```

**Set format**:
```
[0x29][var_id][value...]
```

**Response**: `RESP_CODE_CUSTOM_VARS` (0x15)

### CMD_SET_OTHER_PARAMS (0x26)

Set miscellaneous device parameters (battery chemistry, telemetry mode, etc.).

**Format**:
```
[0x26][param_data...]
```

### CMD_SIGN_START/DATA/FINISH (0x21-0x23)

Multi-step digital signing operation.

**Purpose**: Sign arbitrary data using the device's private key.

**Flow**:
1. `CMD_SIGN_START` - Initialize signing session
2. `CMD_SIGN_DATA` (multiple) - Add data chunks (max 8KB total)
3. `CMD_SIGN_FINISH` - Get Ed25519 signature

**Response**: `RESP_CODE_SIGNATURE` (0x14) with 64-byte signature

### PUSH_CODE_LOG_RX_DATA (0x88)

Raw LoRa packet for debugging/decryption.

**Format**:
```
[0x88][flags][snr][raw_packet...]
```

**Used for**: Decrypting channel messages when device doesn't have the channel key.

**Raw packet structure**:
```
[header][transport_id? x4][path_len][path...][payload...]
```

**Channel message decryption flow**:
1. Parse header to get route type
2. Extract path and payload
3. For group text payload (type 0x05):
   - First payload byte is channel hash
   - Verify hash against known channels
   - Decrypt payload using channel PSK
   - Parse decrypted data as channel message

## Message Features

### Text Compression (SMAZ)

The protocol supports optional SMAZ compression for text messages:

**Encoding**:
```dart
// Only compress if it saves space
String outbound = Smaz.encodeIfSmaller(text);
```

**Decoding**:
```dart
// Detect and decode SMAZ prefix
String decoded = Smaz.tryDecodePrefixed(received) ?? received;
```

**Enable per-contact/channel**:
- Contact: Stored in `ContactSettingsStore`
- Channel: Stored in `ChannelSettingsStore`

**Exclusions**: Structured payloads starting with `g:`, `m:`, or `V1|` are never compressed.

### Message Reactions

**Format**: `"m:[message_id]:[emoji]"`

**Example**: `"m:abc123:👍"`

**Processing**:
1. Parse reaction from incoming message
2. Find target message by `messageId`
3. Increment emoji counter in target message's `reactions` map
4. Don't display reaction as a separate message

### Message Replies

**Format**: `"@[node_name] [actual_message]"`

**Example**: `"@Alice Hello there!"`

**Processing**:
1. Parse reply mention from message text
2. Find most recent message from mentioned sender
3. Attach reply metadata to new message:
   - `replyToMessageId`
   - `replyToSenderName`
   - `replyToText`

### Message Retry and ACK Tracking

The app implements automatic retry for failed messages:

**Flow**:
1. Send message → Receive `RESP_CODE_SENT` with `ack_hash` and `timeout_ms`
2. Start timeout timer
3. On timeout: Retry with incremented attempt counter
4. On `PUSH_CODE_SEND_CONFIRMED`: Mark delivered, record trip time

**Retry strategy**: Exponential backoff with path rotation (if auto-rotation enabled).

## LoRa Timing Calculations

### Airtime Calculation

Based on Semtech SX127x datasheet formula:

```dart
double symbolDuration = (1 << sf) / (bw / 1000.0); // ms
double preambleTime = (preambleSymbols + 4.25) * symbolDuration;

int numerator = 8*payloadBytes - 4*sf + 28 + 16*crc - headerBytes;
int denominator = 4*(sf - 2*de);
int payloadSymbols = 8 + ceil(numerator/denominator) * (cr + 4);

double payloadTime = payloadSymbols * symbolDuration;
int airtime = ceil(preambleTime + payloadTime);
```

**Variables**:
- `sf`: Spreading factor (5-12)
- `bw`: Bandwidth in Hz
- `cr`: Coding rate (5-8)
- `de`: Low data rate optimization (1 if sf≥11, else 0)
- `crc`: CRC enabled (always 1)

### Message Timeout Calculation

**Flood mode** (path_len = -1):
```
timeout = 500 + (16 × airtime) ms
```

**Direct path** (path_len ≥ 0):
```
timeout = 500 + ((airtime×6 + 250) × (hops+1)) ms
```

**Example** (SF7, BW125, 100 bytes, 2 hops):
```
airtime ≈ 50 ms
timeout = 500 + ((50×6 + 250) × 3) = 500 + (550 × 3) = 2150 ms
```

## Path Routing

### Path Format

Paths are sequences of 1-byte public key prefixes:

**Example path** (3 hops):
```
[0xAB][0xCD][0xEF]  // Route through nodes AB... → CD... → EF...
```

**Max path size**: 64 bytes = 64 hops maximum

### Path Modes

**Flood mode** (`path_len = -1`):
- Message floods through all nodes
- Higher latency, more reliable
- Used when no direct path known

**Direct mode** (`path_len ≥ 0`):
- Message follows specific path
- Lower latency, less reliable
- Requires path discovery/maintenance

### Auto Path Rotation

When enabled, the app cycles through known paths:

**Implementation**:
1. `PathHistoryService` tracks success/failure per path
2. On message send, select next path variant
3. Record attempt and outcome
4. Rotate to next path on retry
5. Update contact's path in-memory via `CMD_ADD_UPDATE_CONTACT`

## Channel Encryption

Channels use symmetric encryption with pre-shared keys (PSK).

### Encryption Scheme

**MAC**: HMAC-SHA256 (first 2 bytes)
**Cipher**: AES-128-ECB

**Process**:
1. Compute channel hash: `sha256(psk)[0]`
2. Encrypt payload with AES-128-ECB using first 16 bytes of PSK
3. Compute HMAC-SHA256 of ciphertext using 32-byte padded PSK
4. Prepend 2-byte MAC to ciphertext
5. Prepend channel hash byte

**Format**:
```
[channel_hash][mac x2][ciphertext...]
```

### Decryption (from PUSH_CODE_LOG_RX_DATA)

1. Extract channel hash from payload
2. Try each known channel's PSK
3. Verify 2-byte HMAC prefix
4. Decrypt with AES-128-ECB
5. Parse decrypted payload as channel message

## Data Types

### Binary Encoding

**Little-endian** for all multi-byte integers:

```dart
// Read uint32
int val = data[offset] | (data[offset+1] << 8) |
          (data[offset+2] << 16) | (data[offset+3] << 24);

// Write uint32
data[offset] = val & 0xFF;
data[offset+1] = (val >> 8) & 0xFF;
data[offset+2] = (val >> 16) & 0xFF;
data[offset+3] = (val >> 24) & 0xFF;
```

### String Encoding

**Format**: Null-terminated UTF-8

```dart
// Read C-string
String readCString(Uint8List data, int offset, int maxLen) {
  int end = offset;
  while (end < offset + maxLen && end < data.length && data[end] != 0) {
    end++;
  }
  return utf8.decode(data.sublist(offset, end), allowMalformed: true);
}
```

**Fallback**: If UTF-8 decoding fails, use Latin-1 (byte-to-char mapping).

### Public Keys

**Format**: 32-byte Ed25519 public keys

**Hex representation**:
```dart
String hex = pubKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
// Example: "a1b2c3d4e5f6..."
```

**Prefix matching**: First 6 bytes used for message routing.

## Connection Management

### Connection States

```dart
enum MeshCoreConnectionState {
  disconnected,  // Not connected
  scanning,      // BLE scan in progress
  connecting,    // Connection attempt in progress
  connected,     // Fully connected and initialized
  disconnecting, // Disconnect in progress
}
```

### Auto-Reconnection

When connection is lost (not manual disconnect):

**Strategy**: Exponential backoff
```dart
int delayMs = 1000 * (1 << attempt);  // 1s, 2s, 4s, 8s, 16s, 32s
delayMs = min(delayMs, 30000);         // Cap at 30 seconds
```

**Attempts**: Unlimited until manual disconnect or successful reconnect.

### Message Queue Syncing

On connect, the app syncs queued messages:

**Flow**:
1. Wait for `RESP_CODE_SELF_INFO` (device ready)
2. Wait for `RESP_CODE_END_OF_CONTACTS` (contacts loaded)
3. Send `CMD_SYNC_NEXT_MESSAGE`
4. Process each message/response
5. Send next `CMD_SYNC_NEXT_MESSAGE`
6. Continue until `RESP_CODE_NO_MORE_MESSAGES`

**Trigger**: Also triggered by `PUSH_CODE_MSG_WAITING` notification.

## Error Handling

### Frame Validation

All frame handlers validate:
1. Minimum frame length
2. Expected data offsets
3. Null-termination of strings
4. Public key prefix matching (for messages)

**Invalid frames**: Silently ignored, logged to debug.

### Send Failures

**Exceptions**:
- Not connected: `throw Exception("Not connected to a MeshCore device")`
- No write support: `throw Exception("RX characteristic does not support write")`

**Retries**: Write operations use platform-level retries (BLE stack).

### Disconnection Recovery

**Actions on disconnect**:
1. Cancel all subscriptions
2. Clear device references (but preserve ID/name for reconnection)
3. Clear in-memory contacts and conversations
4. Reset sync state flags
5. Schedule reconnection (if not manual)

## CLI Commands

The device supports text-based CLI commands for advanced configuration:

**Format**:
```
[0x01][command_string...][0x00]
```

**Examples**:
```dart
sendCliCommand('set privacy on')
sendCliCommand('radio sf 7')
sendCliCommand('channel add "TestChannel"')
```

**Note**: CLI commands don't use the frame-based protocol and are sent as UTF-8 text with 0x01 prefix.

## Protocol Constants

```dart
const int pubKeySize = 32;         // Ed25519 public key
const int maxPathSize = 64;        // Max routing path
const int pathHashSize = 1;        // Path prefix size
const int maxNameSize = 32;        // Max name length
const int maxFrameSize = 176;      // app command/response frame limit
const int maxTextPayloadBytes = 160; // Firmware limit (10 cipher blocks)
const int appProtocolVersion = 4;  // Current protocol version
```

## Implementation Notes

### Thread Safety

`MeshCoreConnector` uses Flutter's `ChangeNotifier`:
- All state changes trigger `notifyListeners()`
- BLE callbacks run on main isolate
- No explicit locking required (single-threaded)

### Storage

Persistent storage uses separate stores:
- `ContactStore`: Contact list cache
- `MessageStore`: Per-contact message history
- `ChannelMessageStore`: Per-channel message history
- `ContactSettingsStore`: Per-contact settings (SMAZ, etc.)
- `ChannelSettingsStore`: Per-channel settings
- `UnreadStore`: Unread message tracking

**Windowing**: Only most recent 200 messages kept in memory per conversation.

### Deduplication

**Contact messages**: Compare timestamp + text in last 10 messages.

**Channel messages**:
- Same text + timestamp within 5 seconds = duplicate
- Self-messages: Match sender name + path contains own public key prefix

### Notifications

The app shows system notifications for:
- New advertisements (if enabled)
- New direct messages (if enabled)
- New channel messages (if enabled)

**Filtering**: No notifications for outgoing messages or CLI data.

## Firmware Implementation Details

### C++ Firmware Side (companion_radio)

The firmware implements the protocol through the `MyMesh` class which extends `BaseChatMesh`. Key implementation notes:

#### Frame Constants

```cpp
#define MAX_TEXT_LEN (10*CIPHER_BLOCK_SIZE)  // 160 bytes
```

The client-side command/response limit is the 176-byte `maxFrameSize` documented
above. Keep firmware constants tied to the exact firmware checkout being built;
they are not duplicated here because that source tree is versioned separately.

#### Timeout Calculations

**Base constants**:
```cpp
#define SEND_TIMEOUT_BASE_MILLIS        500
#define FLOOD_SEND_TIMEOUT_FACTOR       16.0f
#define DIRECT_SEND_PERHOP_FACTOR       6.0f
#define DIRECT_SEND_PERHOP_EXTRA_MILLIS 250
```

**Flood timeout**: `500 + (airtime × 16) ms`

**Direct timeout**: `500 + ((airtime × 6 + 250) × (hops + 1)) ms`

These match the Dart implementation.

#### Offline Message Queue

The firmware maintains an offline queue for when the BLE client is disconnected:

```cpp
#define OFFLINE_QUEUE_SIZE 16
Frame offline_queue[OFFLINE_QUEUE_SIZE];
```

**Features**:
- Queues messages when app not connected
- On connection, sends `PUSH_CODE_MSG_WAITING` to trigger sync
- Channel messages can be evicted if queue full (oldest first)
- Contact messages are preserved over channel messages

**Sync flow**:
1. App sends `CMD_SYNC_NEXT_MESSAGE`
2. Firmware sends oldest queued frame
3. App sends another `CMD_SYNC_NEXT_MESSAGE`
4. Repeat until firmware sends `RESP_CODE_NO_MORE_MESSAGES`

#### Contact Storage

**Lazy write strategy**:
```cpp
#define LAZY_CONTACTS_WRITE_DELAY 5000  // 5 seconds
```

Contact list changes trigger a delayed write (5s after last change) to reduce wear on flash storage.

#### Advertisement Path Cache

Firmware variants that implement `CMD_GET_ADVERT_PATH` cache recently heard
advertisement paths in volatile memory. A documented implementation uses this
shape:

```cpp
#define ADVERT_PATH_TABLE_SIZE 16
struct AdvertPath {
  uint8_t pubkey_prefix[6];
  char name[32];
  uint32_t recv_timestamp;
  uint8_t path_len;
  uint8_t path[MAX_PATH_SIZE];
};
```

**Purpose**: Allows `CMD_GET_ADVERT_PATH` to retrieve inbound paths for
discovered nodes. The exact table size and structure are firmware-specific and
should be checked against the target firmware source.

#### Expected ACK Table

```cpp
#define EXPECTED_ACK_TABLE_SIZE 8
struct {
  uint32_t ack;            // Expected ACK hash
  uint32_t msg_sent;       // Timestamp when sent
  ContactInfo* contact;    // Recipient contact
} expected_ack_table[EXPECTED_ACK_TABLE_SIZE];
```

When message is sent, firmware:
1. Computes `expected_ack` hash from message
2. Stores in table with send timestamp
3. On ACK receipt, computes trip time
4. Sends `PUSH_CODE_SEND_CONFIRMED` to app

#### Protocol Version Negotiation

```cpp
uint8_t app_target_ver = 0;  // Set by CMD_APP_START
```

The firmware adapts response formats based on app version:
- Version < 3: Uses `RESP_CODE_CONTACT_MSG_RECV` (no SNR)
- Version ≥ 3: Uses `RESP_CODE_CONTACT_MSG_RECV_V3` (includes SNR + reserved bytes)

#### Error Codes

```cpp
#define ERR_CODE_UNSUPPORTED_CMD    1
#define ERR_CODE_NOT_FOUND          2
#define ERR_CODE_TABLE_FULL         3
#define ERR_CODE_BAD_STATE          4
#define ERR_CODE_FILE_IO_ERROR      5
#define ERR_CODE_ILLEGAL_ARG        6
```

Returned in `RESP_CODE_ERR` frames: `[0x01][err_code]`

### Flutter Implementation Details

#### Message Windowing

```dart
static const int _messageWindowSize = 200;
```

Only most recent 200 messages per contact/channel kept in memory. Older messages stored on disk but must be explicitly loaded via `loadOlderMessages()`.

#### Frame Processing

All received frames processed in `_handleFrame()`:
```dart
void _handleFrame(List<int> data) {
  final frame = Uint8List.fromList(data);
  final code = frame[0];
  switch (code) {
    case respCodeSelfInfo: _handleSelfInfo(frame);
    case respCodeContact: _handleContact(frame);
    // ... etc
  }
}
```

**Validations**:
- Minimum frame length checks
- Null-termination validation for strings
- Public key prefix matching for messages
- Contact existence checks before processing messages

#### Auto-Reconnection

```dart
int _nextReconnectDelayMs() {
  final attempt = _reconnectAttempts.clamp(0, 6);
  final delayMs = 1000 * (1 << attempt);  // Exponential backoff
  return delayMs > 30000 ? 30000 : delayMs;
}
```

**Strategy**: 1s, 2s, 4s, 8s, 16s, 32s, then capped at 30s.

#### Self-Info Retry

```dart
Timer.periodic(const Duration(milliseconds: 3500), (timer) {
  if (!_awaitingSelfInfo) timer.cancel();
  sendFrame(buildAppStartFrame());
});
```

On connect, if `RESP_CODE_SELF_INFO` not received within 3s, retry `CMD_APP_START` every 3.5s until received.

#### Message Deduplication

**Contact messages**: Compare last 10 messages for same timestamp + text.

**Channel messages**:
- Same text within 5 seconds = duplicate
- Self-message detection: Match sender name with self name + path contains own public key prefix

#### Reaction Processing

```dart
final reactionInfo = Message.parseReaction(message.text);
if (reactionInfo != null) {
  _processContactReaction(messages, reactionInfo);
  return; // Don't add as visible message
}
```

Reactions are parsed, processed to update target message's reaction counts, but never displayed as standalone messages.

## References

- **Firmware Repository**: https://github.com/nonik0/meshcore
- **LoRa Airtime Calculator**: Based on Semtech AN1200.22
- **SMAZ Compression**: https://github.com/antirez/smaz
- **Ed25519**: https://ed25519.cr.yp.to/
- **AES-128-ECB**: FIPS 197
- **Nordic UART Service (NUS)**: Nordic Semiconductor BLE UART specification
