# Scanner & Connection

## BLE Scanner (Home Screen)

The BLE Scanner is the app's home screen, displayed immediately on launch.

### How to Access

- Opens automatically when the app starts
- Returns here after a manual disconnect or a non-recoverable USB/TCP connection loss
- Accessible by navigating back from a connected session

### What the User Sees

**App Bar**: Centered title "Scanner".

**Bluetooth-Off Warning Banner** (conditional): Appears when the Bluetooth adapter is off, showing a `bluetooth_disabled` icon, a warning message, and on Android, an "Enable Bluetooth" button.

**Status Bar**: A full-width colored strip reflecting the current connection state:

| State | Text | Color |
|---|---|---|
| Disconnected | "Not connected" | Grey |
| Scanning | "Scanning..." | Blue |
| Connecting | "Connecting..." | Orange |
| Connected | "Connected to \<device name\>" | Green |
| Disconnecting | "Disconnecting..." | Orange |

The TCP cleanup applies to Android, iOS, Windows, Linux and macOS; the shared BLE cleanup applies wherever the BLE backend is supported. For BLE/TCP, a stalled subscription cancellation, BLE platform reply or model release is limited to three seconds per cleanup step; several stalled steps can add up. The app records the failed stage in the debug log and continues disconnecting. TCP socket shutdown also has a three-second limit and force-closes the old socket on exit. A manual disconnect does not enable automatic reconnect. Native USB close and offline review-storage cleanup keep their existing completion rules.

**Device List**: When no devices are found, shows a large Bluetooth icon with a prompt. The prompt text is dynamic: "Searching for devices..." while actively scanning, or "Tap Scan to search" when idle. When devices are found, shows a scrollable list of `DeviceTile` widgets.

**App Bar Actions**: Icon buttons in the top-right corner of the app bar:
- **USB** icon button - Opens USB connection screen (Android, Windows, Linux, macOS, Chrome web only)
- **TCP/IP** icon button - Stops BLE discovery before opening the TCP connection screen (all non-web platforms). Opening the saved TCP transport follows the same rule; the app waits for any BLE scan startup to finish before stopping it.

**Bottom actions**:
- **Offline** - Opens saved history without connecting to a radio
- **BLE Scan** - Toggles BLE scanning on/off; shows a spinner when scanning. **Disabled** (greyed out, not tappable) when Bluetooth is off

### Device Tile

Each discovered device is displayed as a list tile showing:
- **Signal strength icon** (color-coded by RSSI):
  - Green: >= -60 dBm (excellent)
  - Light green: -60 to -70 dBm (good)
  - Amber: -70 to -80 dBm (fair)
  - Orange: -80 to -90 dBm (weak)
  - Red: < -90 dBm (poor)
- **RSSI value** in dBm (e.g., "-72 dBm")
- **Device name** (falls back to "Unknown Device")
- **Device ID** (BLE MAC address on Android; a system-assigned UUID on iOS/macOS)
- **Connect button** (the entire tile row is also tappable — both trigger connection)

Note: The weak (-80 to -90 dBm) and poor (< -90 dBm) tiers share the same icon shape and are only differentiated by color (orange vs. red).

### How Scanning Works

- Filters for devices advertising the Nordic UART Service UUID (so community forks with non-standard names are still found). Known name prefixes used by stock firmware builds for reference: `MeshCore-`, `Whisper-`, `WisCore-`, `Seeed`, `Lilygo`, `HT-`, `LowMesh_MC_`, `NRF52`
- Uses low-latency scan mode on Android
- Scans for 10 seconds then auto-stops
- On iOS/macOS, waits for BLE adapter initialization before starting
- If Bluetooth is turned off during a scan, scanning stops immediately

### Connecting to a Device

Tap a device tile or its Connect button:
1. The connector stops scanning and transitions to "connecting"
2. Connects to the device with a 15-second timeout (6 seconds on Linux)
3. Requests MTU 185 bytes for optimal throughput
4. Discovers BLE services and locates the Nordic UART Service
5. Subscribes to TX notifications for receiving data
6. On success, automatically navigates to the Channels screen
7. On failure, shows a red error snackbar

### Offline History

The Offline button is available on the BLE scanner and on the USB and TCP connection screens. It opens a source picker with:

- **Shared mode** first: combines saved contacts, channels and messages from every known node scope.
- One entry for each previously connected node: opens only that node's locally stored history and UI state.

Offline history is read-only with respect to the radio. Chats, message search, the map, the MCOimg gallery and canvas remain available, but message sending, contact/channel changes, repeater or room login, wardrive, discovery, tracing and live device settings are blocked. The chat composer is disabled. Starting BLE, USB or TCP while offline history is open is rejected until the user leaves that mode.

### Connection Loss and Recovery

- A recoverable BLE loss keeps the current screen open and shows a red reconnecting snackbar. Pending messages remain queued while the connector retries indefinitely; after a successful handshake they resume naturally and a green reconnected snackbar is shown.
- Manual disconnect returns to the selected connection screen.
- При потере USB-соединения приложение возвращается к экрану подключения. BLE и ранее установленный TCP поддерживают автоматическое восстановление; особенности TCP описаны в разделе [Automatic Reconnect](#automatic-reconnect).
- On Android, the foreground-service notification reflects connected/reconnecting state. The service retains the main Flutter engine; it does not contain a second BLE connector.

---

## USB Connection

### How to Access

From the Scanner screen, tap the **USB** icon button in the app bar.

### What the User Sees

- A colored status bar at the top (same color scheme as BLE scanner)
- A list of detected USB serial ports, each showing:
  - Friendly display name
  - Raw port name (subtitle, only shown when it differs from the display name)
  - Chevron trailing icon (the entire tile is tappable to connect)
- Transport switcher buttons (outlined, not FABs) to switch to BLE or TCP (these use `pushReplacement`, so back navigation returns to Scanner, not between USB/TCP)
- An **Offline** button for opening saved history without selecting a serial port

### Key Interactions

- On desktop (Windows, Linux, macOS): ports are polled every 2 seconds for hot-plug detection (polling pauses while connecting/connected)
- On mobile: tap the "Scan" FAB to manually refresh
- Tap a port tile to connect
- On successful connection, navigates to Channels screen
- On connection failure, the port list automatically refreshes
- Platform-specific error messages for common USB failures (permission denied, device missing, device detached, device busy, driver missing, port invalid, timeout, and more)

---

## TCP Connection

### How to Access

From the Scanner screen, tap the **TCP/IP** icon button in the app bar.

### What the User Sees

- A colored status bar at the top
- **Host address** text field
- **Port number** text field
- **Connect** button
- Transport switcher buttons (outlined, not FABs) to switch to USB or BLE
- An **Offline** button for opening saved history without connecting to the configured endpoint

### Key Interactions

- Last-used host and port are pre-populated from saved settings
- Tap Connect to validate inputs and connect
  - Host must not be empty
  - Port must be a number between 1 and 65535
  - Validation errors are shown as red snackbars
- The Connect button shows a spinner and "Connecting..." label while in progress
- The status bar shows the specific host:port being connected to (e.g., "Connecting to 192.168.1.1:5000")
- On success, navigates to Channels screen and saves the host/port to settings
- On connection, the status bar shows the active TCP endpoint (e.g., "Connected to 192.168.1.1:5000")
- Error messages for timeout, unsupported platform, and connection failures

### Automatic Reconnect

- При обрыве ранее установленного TCP без ручного отключения приложение автоматически восстанавливает тот же host и port, используя общий с BLE backoff. Первые шесть пауз — 1/2/4/8/16/30 секунд; затем исходный предел — 30 секунд. Параметр энергосбережения **«Пауза переподключений в фоне»** позволяет увеличить поздние паузы только при неактивном приложении; возврат в приложение пересчитывает ожидание по обычному расписанию. Фоновая служба сохраняет прежние правила работы во время повторов. Подробности — [переподключения в фоне](power-saving.md#переподключения-в-фоне).
- Only a link that completed its handshake is reconnected; a first connection to a wrong address is not retried. A manual disconnect, or connecting over BLE or USB, cancels it.
- The socket uses TCP keepalive (probes after 30 seconds of silence, every 10 seconds, 3 tries), so a dead link is noticed in about a minute instead of the system default of hours.
- USB is not reconnected automatically: losing a USB link usually means the cable was unplugged.


### iOS interface during background operation

When the iOS compatibility guard is active, native application and window-scene activity pauses UI updates while retaining the screen state and typed text. Timers and transport callbacks continue whenever iOS allows the process to run. Returning to the foreground schedules a frame showing the latest data. The debug log marks this version of the guard with `iOSRendering` and `gate=uiPipeline`.

The latest mitigation for missing characters is awaiting device verification. If characters disappear after a background/lock cycle, preserve the `iOSRendering` entries around that cycle and note whether the issue survives navigation and data updates.

### Experimental iOS background TCP receiver

The iOS research branch adds a separate native background receiver. With **Keep TCP-connection alive in background** enabled, the TCP screen accepts a Wi-Fi SSID and saves it with the endpoint and its bookmark. It first tries to read the current SSID; if none is available, a manual connection can ask for it. After a successful foreground connection it saves an `NEAppPushManager` configuration for that SSID and endpoint. Connection diagnostics use the `iOS TCP` log tag.

Background TCP now defaults to enabled, including on Android; a previously saved disabled setting stays disabled. The iOS receiver opens its own connection and can fetch pending messages and show notifications. It does not keep the Flutter interface running or save the fetched messages into the app history. Successful configuration does not prove that the receiver is active or that background delivery works on a particular iPhone.

This feature remains experimental. The merge preserves the earlier research implementation; reliable sharing of the node with the foreground connection, history reconciliation, and disabling an already saved receiver require further work or device verification. Validate the iOS signing/entitlements and the deployment target for the chosen build profile on a Mac before relying on it. The normal BLE peripheral mode for the companion proxy remains in the app's background-mode configuration.
