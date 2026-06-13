# Repeater Management

## Overview

Repeater Management provides tools for administering MeshCore repeater and room server nodes. It includes device status monitoring, CLI access, telemetry reading, neighbor discovery, and remote configuration.

## How to Access

From the Contacts screen:
1. Long-press a **Repeater** or **Room** contact
2. Select "Manage Repeater" or "Room Management"
3. Enter the admin password in the login dialog
4. Navigate to the Repeater Hub Screen

### Login Dialog

- Password field with show/hide toggle
- "Save password" checkbox (persists for future logins). If a saved password exists, it is pre-filled and the checkbox is pre-checked, making login one-tap
- Routing mode selector and "Manage Paths" link are available directly in the dialog (configure routing before login)
- Auto-retries up to 5 times on timeout, showing progress ("Attempt 2 of 5"). A wrong password (explicit failure response) stops immediately — only timeouts trigger retries
- If auto-clock-sync is enabled for this repeater (configured in Repeater Settings), a `clock sync` command is sent automatically on successful login

---

## Repeater Hub Screen

The central management screen showing:

- **Header card**: Repeater name, short public key, path label, GPS coordinates (if known)
- **Battery chemistry selector**: NMC / LiFePO4 / LiPo (saved per repeater)
- **Management tool cards** (full-width cards with chevron arrows, not a grid). Title dynamically shows "Repeater Management" or "Room Management" (admin) or "Repeater Guest" / "Room Guest" (guest) based on contact type and login result:

| Card | Destination | Visibility |
|---|---|---|
| Status | Repeater Status Screen | All users |
| Telemetry | Telemetry Screen | All users |
| Neighbors | Neighbors Screen | All users |
| CLI | Repeater CLI Screen | Admin only |
| Settings | Repeater Settings Screen | Admin only |

The battery chemistry selector and CLI/Settings cards are hidden from guest users.

---

## Repeater Status

### What the User Sees

Three information cards:

**System Information**:
- Battery percentage and voltage (e.g. "85% / 3.95V"), using the battery chemistry set in the hub screen
- Clock at login time
- Uptime (days/hours/minutes/seconds)
- Queue length
- Debug flags (error event count)

**Radio Statistics**:
- Last RSSI and SNR
- Noise floor
- TX airtime and RX airtime

**Packet Statistics**:
- Packets sent and received, each broken down by flood vs. direct
- Duplicates, broken down by flood vs. direct
- Channel utilization (% of uptime used by TX + RX)

### Key Interactions
- Auto-queries the repeater on open; shows a loading spinner until data arrives
- On timeout: red snackbar error. On success: data appears in-place (no extra snackbar)
- Pull-to-refresh or refresh button in the app bar to re-query
- Routing mode popup and path management dialog in app bar (these controls appear on **all** management sub-screens, not just Status)
- Accepts both binary `RESP_CODE_STATUS_RESPONSE` frames and legacy JSON text responses

---

## Repeater CLI

A terminal-style interface for sending commands directly to the repeater.

### What the User Sees

- **Quick-command bar** (horizontal scroll): Shortcut buttons for 9 common commands (advert, get name, get radio, get tx, discover.neighbors, neighbors, ver, clock, clock sync)
- **Command history list**: Sent commands in primary color, responses in secondary color
- **Input bar**: Up/down history arrows, monospace text field with `> ` prefix, send button

### Key Interactions

- Type a command and press send (or Enter on desktop)
- Up/down arrows navigate through command history
- Quick-command buttons populate and send common commands
- Overflow menu (three-dot icon): "Debug next command" option shows raw frame debug info for the next typed command (shows error snackbar if input field is empty)
- Help icon: Opens a scrollable reference of all known CLI commands. Tapping any command populates the input field immediately
- Clear icon: Wipes the command/response history
- Failed/timed-out commands are automatically retried once

### Available CLI Commands

The in-app help reference (help icon) documents all known commands. Categories:

**General**: `advert`, `advert.zerohop`, `reboot`, `clock`, `clock sync`, `password`, `ver`, `clear stats`, `erase`, `poweroff`, `shutdown`, `clkreboot`, `start ota`, `time`, `board`, `discover.neighbors`, `powersaving`, `stats-packets`, `stats-radio`, `stats-core`

**Get**: `get name`, `get role`, `get public.key`, `get prv.key`, `get repeat`, `get tx`, `get freq`, `get radio`, `get radio.rxgain`, `get af`, `get dutycycle`, `get int.thresh`, `get agc.reset.interval`, `get multi.acks`, `get allow.read.only`, `get advert.interval`, `get flood.advert.interval`, `get guest.password`, `get lat`, `get lon`, `get rxdelay`, `get txdelay`, `get direct.txdelay`, `get flood.max`, `get owner.info`, `get path.hash.mode`, `get loop.detect`, `get acl`, `get bridge.*`, `get adc.multiplier`, `get bootloader.ver`

**Set**: `set name`, `set af`, `set tx`, `set repeat`, `set allow.read.only`, `set flood.max`, `set int.thresh`, `set agc.reset.interval`, `set multi.acks`, `set advert.interval`, `set flood.advert.interval`, `set guest.password`, `set lat`, `set lon`, `set freq`, `set radio`, `set rxdelay`, `set txdelay`, `set direct.txdelay`, `set radio.rxgain`, `set dutycycle`, `set loop.detect`, `set path.hash.mode`, `set owner.info`, `set prv.key`, `set bridge.*`, `set adc.multiplier`, `tempradio`, `setperm`

**Bridge**: `get bridge.type`

**Logging**: `log start`, `log stop`, `log erase`

**Neighbors**: `neighbors`, `neighbor.remove`

**Power Management**: `get pwrmgt.support`, `get pwrmgt.source`, `get pwrmgt.bootreason`, `get pwrmgt.bootmv`

**Sensors**: `sensor get {key}`, `sensor set {key} {value}`, `sensor list [start]`

**GPS Management**: `gps`, `gps {on|off}`, `gps sync`, `gps setloc`, `gps advert`, `gps advert {none|share|prefs}`

**Region Management**: `region`, `region load`, `region get`, `region put`, `region remove`, `region allowf`, `region denyf`, `region home`, `region save`, `region default`, `region list allowed`, `region list denied`

---

## Telemetry

### What the User Sees

A list of Cayenne LPP sensor channel cards:

- **Channel 1** (special): Battery voltage (shown as percentage or raw mV) and MCU temperature
- **Other channels**: Raw sensor values with appropriate labels

Shows "No data" until a response arrives from the repeater.

### Key Interactions
- Auto-queries on open
- Pull-to-refresh
- Temperature respects metric/imperial setting
- Battery readings are stored for the repeater's battery snapshot

---

## Neighbors

### What the User Sees

A card titled "Repeater's Neighbors - N" listing each neighbor as:
- Repeater name (or hex key prefix if unknown)
- Time since last heard
- SNR quality icon with color coding and label

### Key Interactions
- Auto-queries up to 15 neighbors on open
- Matches public key prefixes against known contacts to show names
- Pull-to-refresh

---

## Repeater Settings

### What the User Sees

Nine configuration cards, each with its own per-field refresh button(s):

**1. Basic Settings**
- Name field
- Admin password field (write-only; always sent when non-empty)
- Guest password field (write-only; always sent when non-empty)

**2. Radio Settings**
- Frequency (MHz)
- TX Power (dBm) — has its own independent refresh button
- Bandwidth dropdown (kHz)
- Spreading Factor (SF5–SF12)
- Coding Rate (4/5–4/8)
- RX Gain boost toggle

**3. Location Settings**
- Latitude and longitude fields, each with an independent refresh button

**4. Features**
- Packet forwarding toggle (`set repeat`)
- Guest access toggle (`set allow.read.only`)
- Multi-ACKs toggle (`set multi.acks`)
- Auto clock sync after login toggle (local app setting only, not sent to repeater)

**5. Network Health**
- Loop detection dropdown (off / minimal / moderate / strict; `set loop.detect`)
- Duty cycle slider (1–100%; `set dutycycle`)

**6. Advertisement Settings**
- Local advert interval slider (60–240 minutes) with enable/disable toggle
- Flood advert interval slider (3–168 hours) with enable/disable toggle
- Flood max hops slider (0–64; `set flood.max`)

**7. Owner Info**
- Multi-line text field for operator contact info (`set owner.info`); newlines sent as `|`

**8. Actions** (one-tap, no save needed)
- Send Advertisement (`advert`)
- Send Zero-Hop Advertisement (`advert.zerohop`)
- Clock Sync (`clock sync`)

**9. Advanced** (collapsed by default)
- Path hash mode dropdown (0–2; `set path.hash.mode`)
- TX delay field (`set txdelay`)
- Direct TX delay field (`set direct.txdelay`)
- Interference threshold field (`set int.thresh`)
- AGC reset interval slider (0–240s in multiples of 4; `set agc.reset.interval`)

**Danger Zone** (red-styled card)
- Reboot repeater (sends `reboot` with confirmation dialog)
- Erase filesystem (serial-only; shows a confirmation dialog, then an informational snackbar — no command is sent over the air)

### Key Interactions
- **Settings are NOT auto-fetched on open**. Name is pre-filled from cached contact data. Each section has its own refresh button to fetch live values from the repeater
- TX Power, RX Gain, latitude, longitude, and advanced fields each have independent inline refresh buttons
- Save button in app bar appears when any change is detected; failed commands keep those fields dirty for retry
- Settings are sent sequentially with 200ms delays between commands; firmware responses are checked and partial failures are reported in a snackbar
- Some changes (e.g. radio frequency) require a reboot; the firmware response triggers an orange "reboot needed" snackbar
- Advertisement interval sliders reset to defaults when re-enabled (local: 60 min, flood: 3 hours)
- **Erase Filesystem** does NOT send any command over the air — tapping it only shows a snackbar explaining the operation requires physical serial access
