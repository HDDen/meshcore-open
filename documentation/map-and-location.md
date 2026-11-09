# Map & Location

## Overview

The Map feature is a full-featured node-location visualization and radio-planning tool built on OpenStreetMap tiles. It is one of the three primary views accessible from the QuickSwitchBar.

A custom theme can tint map tiles and replace node and own-position markers.
The map retains its status indicators. [Themes](themes.md)

## How to Access

- **QuickSwitchBar tab 2** (rightmost) from Contacts or Channels
- **Deep-link from a chat message**: Tapping a shared location pin in a chat opens the map centered on that pin
- **Settings → Offline Map Cache**: Opens the tile cache management screen

## What the Map Displays

### Self Location (Teal Circle)
With phone-location requests enabled, an available phone fix takes priority
for map display. Otherwise the app uses the node's reported position: its GPS
or fixed coordinates, as selected by the firmware. SELF_INFO carries one node
coordinate pair, without separate GPS/fixed source fields. Setting coordinates
from a map writes to the node; it never changes the phone's location or gives
the chosen point priority over an available phone fix.

### Contact / Node Markers (Color-Coded)
All contacts with known GPS coordinates are plotted:

| Type | Color | Icon |
|---|---|---|
| Chat user | Blue | Person |
| Repeater | Green | Router |
| Room | Purple | Meeting room |
| Sensor | Orange | Sensors |

Node name labels appear automatically at zoom level 14 and above.

Opening a remote contact's **Telemetry** screen also updates its map position
when a received response contains a valid GPS fix. This uses the existing
telemetry request; the map does not start a background location poll. A missing,
zero/zero, non-finite or out-of-range GPS pair leaves the known position intact.

The fix and its receive time are saved locally for the connected node and
survive contact-list refreshes, full synchronizations and application restarts.
A newer advert from the remote node supersedes that fix. Repeated copies of
the same advert keep the fix. Display freshness includes the telemetry receive
time, while contact writes to the radio retain the original advert timestamp.
This does not change the phone-first priority for displaying your own position
and does not write the received GPS coordinates back to the radio.

Select an active Companion or Sensor marker and press **Update location**
to request telemetry once from the map. The request uses that contact's
selected route and flood region. Repeaters and room servers require an
administrator session, so this unauthenticated map action is hidden for them;
use their existing authenticated telemetry screens instead.

While the request is pending, the location action is disabled and its button
shows progress. The app reports whether coordinates arrived, the reply had
no valid position, or the request failed. A successful request moves the
selected marker and centers the map only if that node is still selected.
Leaving/covering the map cancels the wait; connection changes also invalidate
it. An already handed-off radio packet cannot be recalled. There are no
automatic retries or periodic location requests from the map.

### Shared Map Pins (Flag Icons)
Location pins shared in chat messages are displayed as flags:
- **Blue flag**: From a direct message
- **Purple flag**: From a private channel
- **Orange flag**: From a public channel

Tap a pin to see its info. Options to "Hide" (session only) or "Remove" (persistent).

Pins from the same sender in the same chat or channel with the same label (case-insensitive) are treated as one marker: a newer message moves it and keeps the earlier positions as its track. To update a pin you shared before, share again with the same label.

### Predicted / Guessed Locations

Many contacts on the mesh don't have GPS hardware, so the map has no explicit coordinates for them. Instead of leaving these contacts invisible, the app **infers an approximate position** by analyzing the repeater path the contact's messages travel through. These inferred positions are displayed as markers with a `not_listed_location` icon and a muted grey or colored border, visually distinct from confirmed-location markers.

#### Why guessed locations exist

In a mesh network, every message hops through one or more repeaters on its way to the destination. Each repeater in the path is identified by a prefix of its public key whose width is recorded with the path. If any of those repeaters have a known GPS location (because they advertise it), then a contact that routes through those repeaters must be somewhere within radio range of them. By combining the positions of multiple repeaters a contact is known to use, the app can place a rough marker near the anchors. This is a routing heuristic, not measured triangulation or a reliable estimate of physical location.

#### How the algorithm works

1. **Build an anchor index**: The app collects known Repeater and Room contacts that have a valid GPS position and indexes them by the public-key prefixes (1–3 bytes) that paths can use. Only contacts without GPS that were seen within the last 7 days are candidates for a guess.

2. **Walk each path**: For each candidate, the app takes its current path plus recent paths from `PathHistoryService`. Each path is walked hop by hop, starting from your own radio's position, and the last hop that resolves to an anchor is the repeater that heard the contact directly.

3. **Resolve ambiguity**: If several anchors share a hop's prefix (a hash collision), the hop resolves to the candidate nearest the previous hop that is within the maximum link range. Without a self position there is no reference point, so ambiguous prefixes are dropped and only unambiguous matches are kept. The maximum link range is the estimated LoRa range (computed from the current frequency, bandwidth, spreading factor, and TX power using a free-space path loss model), capped at a plausible 150 km.

4. **Vote and filter inconsistencies**: Each observed path contributes one vote for the anchor it ended on. Two anchors more than `2 × max link range` apart cannot both be in range of the same node, so outliers are removed; if no anchors agree, the most-voted anchor wins.

5. **Compute the estimated position**:
   - **Single anchor**: The contact is placed on a small circle (330m radius) around the repeater. The angle on the circle is deterministic — derived from an FNV-1a hash of the contact's public key — so the same contact always appears at the same offset, preventing markers from stacking on top of each other.
   - **Two or more anchors**: The position is the average of the anchor coordinates weighted by their vote counts, with a smaller offset radius (120m for 2 anchors, 80m for 3+) applied for visual separation.

6. **Assign confidence level**:
   - **High confidence** (2+ anchors): The marker border uses the node's type color (brighter border).
   - **Low confidence** (1 anchor): The marker border is rendered in a muted grey.

7. **Cache the result**: The computation runs in a background isolate and is cached using a key derived from the contacts' paths, anchor positions, path-history version, radio parameters, and your own position. The cache is only invalidated when any of these inputs change, avoiding recomputation on every UI rebuild.

#### How to read guessed locations on the map

- **Marker with `not_listed_location` icon**: This is a guessed position, not a confirmed GPS fix.
- **Colored border** (type color): Higher confidence — the contact was seen through 2 or more repeaters with known positions.
- **Grey border**: Lower confidence — based on a single repeater anchor only.
- Coordinates shown in the marker info dialog are prefixed with `~` to indicate they are estimated.
- Guessed locations can be toggled on/off in the map filter dialog (FAB → "Guessed locations" toggle).

## Map Interactions

### Zoom and Pan
Standard pinch-to-zoom (range 2–18). Initial camera position is calculated from the statistical spread of all plotted points.

### Tap on a Node Marker
Opens a dialog showing: type, path (hop chain), coordinates, last-seen time, and public key. Action buttons vary by type:
- **Chat nodes**: "Open Chat"
- **Repeaters**: "Manage Repeater"
- **Rooms**: "Join Room"

### Нижняя карточка выбранного узла

После выбора узла через поиск внизу карты появляется карточка с действиями. Карточка отображается поверх правых кнопок карты: zero-hop discovery, wardrive, фильтра и управления масштабом. В перекрывающейся области нажатия получает карточка; после её закрытия правые кнопки снова доступны на прежних местах. У репитера из карточки можно открыть управление и включить либо скрыть блоки покрытия wardrive.

Удаление контакта с карты ожидает ответ ноды и показывает ошибку при неудаче.
Диалог предупреждает, если авто-добавление на ноде может вернуть контакт после
следующего анонса. Подробнее: [удаление контактов](contacts.md#deleting-a-contact).

### Long-Press on Empty Map Area
Shows a bottom sheet with:
- **Share marker here**: Prompts for a label (default: "Point of interest"), then pick a DM contact or channel to send the location to. Wire format: `m:<lat>,<lon>|<label>|poi`; a `|` in the label is replaced with `/` and line breaks with spaces. The label field shows a live byte counter so the whole pin fits in one message, and a hint that reusing a previous label updates that marker for MeshCore Open recipients. To share your radio's own position, use **Share my location** from the ⊕ menu in chat (see [Chat & Messaging](chat-and-messaging.md#input-bar))
- **Set as my location**: Opens a confirmation showing the selected coordinates. Only after confirmation does the app update the node's advertised location; success requires the node to report matching coordinates.

### Quick Filters and Active Filter Count

The quick-filter row can be collapsed with **Filters**. Its expanded/collapsed
state is remembered when the map is reopened; collapsing it does not reset
active filters. The same type/activity settings remain available in the filter
sheet.

The filter-count badge is temporarily hidden; its implementation is retained.
All existing restrictions, including the default seven-day last-seen limit,
continue to apply. Changing filters never sends a radio command or starts
wardrive/location tracking.

### Filter Dialog (FAB)
Toggle visibility of: chat nodes, repeaters, other nodes, guessed locations, discovery contacts, overlapping markers (stacked markers at similar coordinates), and shared map pins (flag markers).
Additional filters:
- **Key prefix filter**: Show only contacts whose public key starts with a given prefix
- **Last-seen time slider**: Exponential scale from near-zero to 6 months, with "all time" at the top end

### Legend Card (Top-Right)
Shows node count and pin count. Tappable to expand a legend of all marker types.

### In-Map Notifications

Notifications produced by actions on the main map are shown near the bottom of
the screen in a floating overlay. They appear above the bottom navigation and
map controls without taking part in the page layout, so showing a notification
does not move the filter, wardrive, discovery, or other floating buttons.

Only one map notification is visible at a time. A newer notification replaces
the current one; it can also be dismissed by tapping it and otherwise closes
automatically after four seconds. Informational notifications use the regular
surface colour, while failed or unavailable actions retain the error colour.

---

### Setting Node Coordinates from a Path Map

On the channel-message path map or path-trace map, long-press (phone) or
right-click (desktop) a point to open the coordinate confirmation directly.
Cancel sends nothing. After confirmation the app writes to the connected node,
refreshes its information, and waits up to six seconds after that refresh
returns for matching coordinates. Failure uses the error notification colour.

The path's self endpoint follows the normal source priority after the write:
an available phone fix remains first; without it, the updated node position
is used. This action does not request another trace or start GPS tracking.

## Path Trace Map

### How to Access
- From the main map's menu → **Path Trace** (build your own route, see below)
- From Contacts → ⋮ → **Trace by hop hashes** (enter a route without opening the map)
- From a contact's long-press menu → "Path Trace / Ping"
- From a message's path view → radar icon

### Building a Custom Trace on the Map
1. Open the map menu and choose **Path Trace**. A panel appears at the top of the map.
2. Tap nodes on the map in the order the trace should travel. **Remove Last** and **Clear** edit the list.
3. Choose **Round trip** (the trace comes back along the same hops) or **As entered** (the hops are used exactly as listed, so add the return hops yourself).
4. Tap **Run path trace**. Nothing is sent until you press this button.

Returning from the result keeps your hops, mode and the last result (**View last result** reopens it without sending again). **Close** or the back button hides the panel without discarding the hops; reopening **Path Trace** during the same session resumes where you left off. The hops are dropped when you connect to a different radio.

You can also edit the comma-separated hop prefixes directly. The route keeps
its own hash width, even if the current radio mode differs; **Remove Last**
removes an entire hop. Unknown hops can remain in the route without map
coordinates. Region requests retain their separate target-at-the-end behavior
and do not replace the ordinary trace draft.

The draft is kept only in memory for this app session. Changing the route,
mode or radio invalidates the saved result. Replay is labelled as the last
result, preserves previously collected direct-echo observations and neither
subscribes to radio frames nor sends another request. A new explicit run uses
the normal live response validation and timeouts. A temporary reconnect with
no radio identity does not discard the draft; another confirmed identity does.

### Tracing by Hop Hashes

Enter hex hashes separated by commas, spaces or arrows. All hops in the route
must have the same width. Continuous input uses the selected draft's width,
or the radio's configured width when starting a new draft.
For three-byte hashes, each hop needs a unique known relay so the app can use
the fourth byte of its public key in TRACE. The map's builder can prefill the
manual editor with its current route and mode. Each editor keeps its own
draft during the app session.

The app checks the number of hops and the encoded size of the request,
including any return hops. If the route exceeds the radio's limit, shorten
it or select **As entered**. A successful trace shows SNR for each hop.
GPS and map tiles are used only if you open **View map**.

### What the User Sees
A map with a polyline showing the route from your node through repeater hops to the target:
- **Green circles**: Hops with known GPS coordinates
- **Orange circles** (`~HH`): Inferred positions (no GPS but deducible from contacts)
- **Red endpoint**: Target contact with known GPS
- **Magenta endpoint**: Target with guessed position

A bottom panel shows each hop pair with SNR quality icons and total path distance. When multiple observed paths are available, a **Single / Combined** toggle appears at the top of the map. In Combined view, all paths are overlaid; shared segments are highlighted with a white halo and a path count badge appears on shared nodes.

The bottom panel also provides **packet animation controls**:
- **Animation toggle** (on/off)
- **Step back / Play / Step forward / Replay** buttons
- **Follow packet lock** — keeps the map camera centered on the moving packet dot
- **Speed selector** (0.5×, 1×, 2×, 4×)
- A live **"Hop x of y · from → to"** label that tracks the active segment

### How It Works
Sends a trace request frame over the mesh. The repeater network traces the path hop-by-hop and returns per-hop SNR data. For hops without GPS, positions are inferred by averaging GPS coordinates of contacts sharing that last-hop prefix.

---

## Line-of-Sight (LOS) Analysis

### How to Access
From the main map, tap the terrain/antenna icon.

### What the User Sees
A full-screen map with a draggable bottom sheet containing:
- **Elevation profile chart**: Terrain fill (green), LOS beam line (white), radio horizon line (yellow); obstruction points are marked as clickable dots on the chart
- **Status summary**: Clear (green), Marginal (amber, within 5 m of obstruction), or Blocked (red) with distance and clearance/obstruction amount
- **Options section** (collapsible): Node toggles, endpoint dropdowns, antenna height sliders (0–400 ft), Run LOS button

### Key Interactions
- **Long-press the map** to add custom endpoints (pushpin markers, renameable/deleteable)
- **Tap a marker** to select it as Point A or B; LOS runs automatically when both are set
- **Antenna heights** are adjustable for both endpoints
- **Map line** between endpoints is colored green (clear), amber (marginal), or red (blocked)
- Terrain elevation is fetched from the Open-Meteo API (21, 41, or 81 sample points depending on link distance, cached 24 hours)
- K-factor is adjusted per radio frequency from a baseline of 4/3 at 915 MHz

---

## Offline Map Cache

### How to Access
Settings → App Settings → Map Display → Offline Map Cache

### What the User Sees
- Map with a blue polygon overlay showing previously selected cache bounds
- Bounding box coordinates card
- **Cache Area** controls: "Use Current View" and Clear buttons
- **Zoom Range** range slider (3–18, dual-handle for min and max) with estimated tile count
- **Download progress** bar (when downloading)
- **Download Tiles** and **Clear Cache** buttons

На узком экране и при крупном системном тексте подписи кнопок очистки области
и кэша переносятся на несколько строк без сокращения. Очистка области сохраняет
загруженные плитки и диапазон масштаба. Панель управления прокручивается;
во время загрузки очистка недоступна, а кнопка отмены остаётся доступной.

### Key Interactions
1. Pan/zoom the map to the desired area
2. Tap "Use Current View" to capture the viewport as cache bounds
3. Adjust the zoom range slider
4. Tap "Download Tiles" (confirmation dialog shows estimated count)
5. Tiles are downloaded with up to 8 concurrent connections
6. Once cached, tiles are served without internet where supported by the cache backend. Select a Stadia Maps source with a configured API key for bulk offline downloads; OpenStreetMap is for live viewing/already cached tiles. Check the provider’s current terms and quotas.

---

## GPX Export

### How to Access
Settings → Export section

### What It Does
Exports contacts with GPS coordinates to a `.gpx` file via the OS share sheet. Three export options:
- **Export Repeaters**: Repeater and Room contacts with locations
- **Export Contacts**: Chat contacts with locations
- **Export All**: All contacts with locations

Each waypoint includes: name, lat/lon, type label, and public key hex.

---

## Location Data Sources

Координаты нод поступают из mesh. Для локальной позиции на карте и измерений wardrive также может использоваться GPS телефона:

1. **Device self-location**: Read from firmware device-info response. Set manually in Settings → Location, or updated automatically if the device has a GPS module.
2. **Remote node locations**: Extracted from advertisement packets received over the mesh. Encoded as integer lat/lon × 1,000,000.

### GPS телефона и discovery

Поиск соседей из списка контактов не запрашивает GPS телефона. Разовый discovery с карты и определение позиции телефона выполняют ограниченный запрос координат (таймаут 15 секунд); если телефон не предоставил координаты, используется допустимая позиция ноды, когда она доступна. Координаты телефона в этих сценариях не записываются в ноду.

Опция «Непрерывный GPS-location» удерживает постоянную подписку только при запущенном wardrive. Сохранённая включённая опция сама по себе не включает GPS после разового запроса. При остановке wardrive, выключении опции или освобождении сервиса подписка отменяется; запоздалая подготовка не может включить её обратно. Завершение разового запроса сохраняет GPS действующего wardrive.

Ранее начатый разовый запрос может оставаться активным до получения координат или таймаута; это отличается от постоянной подписки. При аппаратной проверке нужно учитывать также активный wardrive и другие функции, запрашивающие геопозицию.

## Regions and offline use

A [message region](regions.md) is a forwarding scope, not a coordinate or GPS boundary. The map does not establish that a sender is physically inside that region. Cached tiles can be used offline; uncached tiles and uncached LOS elevation lookups require internet.

## Heard Repeater Details

Tap either signal indicator, then a row in its repeater list to open details.
The direct-reception indicator retains its ranking; the activity indicator
lists the most recently heard entries first. Both lists preserve multi-byte
routing prefixes and the existing `(?)` indication for ambiguous names.

For a contact the app can resolve, the details show its route, available
coordinates, last advertisement time and full public key. Management or room
login requires a separate action. A contact known only to the app is added to
the radio only after confirmation when an action needs it.

For an unknown prefix, the sheet shows the received prefix, SNR and reception
time. If several contacts share the prefix and the observation has no matching
full key, the suggested name is marked as a guess and contact actions are
unavailable for that entry. Viewing details does not request advertisements,
poll status, start GPS or transmit packets.

The map uses the same details layout and retains its existing repeater action
menu and wardrive coverage controls. Offline details remain readable; radio
actions are blocked.
