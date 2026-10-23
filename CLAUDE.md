# MeshCore Open - Flutter Client (Advanced mod)

Document private/premium module internals only inside the private module; do not describe them in this public guide.

Open-source Flutter client for MeshCore LoRa mesh networking devices. Connects to MeshCore-compatible radios over **BLE, TCP, or USB serial** and provides direct/channel chat, contact and channel management, on-map node tracking, and repeater administration.

This checkout is the **"Advanced mod"** fork (app title `MeshCore Open (Advanced mod)`). On top of a vanilla MeshCore client it adds: selectable text compression (MCMP arithmetic coder / SMAZ / cyr2lat), app-side Ed25519 verification of MCMP v3 signatures, emoji reactions, tiny image/GIF-over-LoRa (MCO image codec), wardriving/coverage mapping with cloud upload, and region/flood-scope routing. See **Advanced mod features** below.

> On-device LLM translation is **scaffolded but disabled in this build** — `TranslationService` is a no-op stub (`downloadModel()` throws `StateError('LLM translation is disabled in this build.')`) and the `llamadart` / `flutter_langdetect` dependencies have been removed. The translate UI still lets users pick a target language for settings, but no translation is performed.

## Build Commands

```bash
# Install dependencies
~/flutter/bin/flutter pub get

# Run in debug mode
~/flutter/bin/flutter run

# Build Android APK
~/flutter/bin/flutter build apk

# Build iOS
~/flutter/bin/flutter build ios

# Build versioned web release (uses build_pipe)
~/flutter/bin/dart run build_pipe

# Run static analysis
~/flutter/bin/flutter analyze

# Run tests
~/flutter/bin/flutter test

# Run on Windows with a data folder outside build/, which flutter clean deletes
~/flutter/bin/flutter run -d windows --dart-entrypoint-args=--data-dir=<absolute path>
```

## Project Structure

```
lib/
├── main.dart        # Entry point: MultiProvider wiring, locale + theme, initial route
├── connector/       # Unified BLE/TCP/USB transport layer
│   ├── meshcore_connector.dart       # Central state holder + ChangeNotifier (all transports)
│   ├── meshcore_connector_tcp.dart   # TCP transport helper
│   ├── meshcore_connector_usb.dart   # USB serial transport helper
│   ├── meshcore_protocol.dart        # Frame size + version constants
│   └── meshcore_uuids.dart           # Nordic UART UUIDs + scan name prefixes
├── models/          # Plain data classes (Contact, Channel, Message, Community, …)
├── services/        # ChangeNotifier services + IO services (retry, wardrive, ML, …)
├── storage/         # Per-device-key stores (SharedPreferences; message history in SQLite)
├── helpers/         # Pure utilities (MCMP/Smaz/cyr2lat compression, MCMP/MCOtxt app containers, MCO image codec, GIF parsing, path hop resolution)
├── MCOtxt/          # MCOtxt v1 text codec: bit codec, frame primitive, static language models (generated)
├── utils/           # Platform / IO / UX utilities (logger, GPX export, dialogs)
├── theme/           # MeshTheme — warm-dark MeshPalette, wired in main.dart
├── l10n/            # ARB localization for 18 locales
├── icons/           # Custom icon widgets
├── widgets/         # Reusable widgets (AppBar, BatteryUi, QR, jump-to-bottom, …)
└── screens/         # ~30 screens — see Screens section below
```

## Screens

All screens are fully implemented (no remaining placeholders).

### Connection / Scanning
| Screen | Purpose |
|---|---|
| `scanner_screen.dart` | BLE device scan and connect — main entry point |
| `tcp_screen.dart` | Connect to a MeshCore device over TCP/IP |
| `usb_screen.dart` | Connect to a MeshCore device over USB serial |
| `discovery_screen.dart` | Browse discovered mesh nodes not yet in contacts; a discovery request sent from the screen lists the nodes that answer it above a rule, a contact the node holds among them dimmed and without actions, and leaves the list as it was below; its menu exports the list to a JSON file and imports one |
| `chrome_required_screen.dart` | Web gate for non-Chrome browsers (BLE unavailable) |

### Chat / Messaging
| Screen | Purpose |
|---|---|
| `chat_screen.dart` | Direct (private) messaging with a contact |
| `channel_chat_screen.dart` | Group messaging inside a named channel |
| `channels_screen.dart` | List and manage channels (add/edit/delete) |
| `channel_message_path_screen.dart` | Hop-by-hop route a channel message took, with map overlay; for a direct message or room post also the route its delivery was confirmed along |

### Contacts / Neighbors
| Screen | Purpose |
|---|---|
| `contacts_screen.dart` | Full contacts list with previews and management |
| `neighbors_screen.dart` | Nodes directly heard by the connected radio (one-hop) |

### Repeater Management
| Screen | Purpose |
|---|---|
| `repeater_hub_screen.dart` | Top-level repeater hub; navigates to sub-screens |
| `repeater_status_screen.dart` | Live status of a managed repeater node |
| `repeater_cli_screen.dart` | Raw command-line interface to a repeater |
| `repeater_settings_screen.dart` | Full radio/node settings editor for a repeater |

### Map / Location
| Screen | Purpose |
|---|---|
| `map_screen.dart` | Main map view of contacts/nodes with live GPS positions |
| `line_of_sight_map_screen.dart` | Terrain LOS analysis between configurable endpoints |
| `path_trace_map.dart` | Animates the hop path a direct message traveled |
| `map_cache_screen.dart` | Download/clear offline map tile cache |
| `community_qr_scanner_screen.dart` | Scan QR to join a mesh community/channel |

### Settings / Debug / Diagnostics
| Screen | Purpose |
|---|---|
| `settings_screen.dart` | Connected device settings: radio params, identity, GPS |
| `app_settings_screen.dart` | App preferences: theme, units, map source, notifications |
| `mod_settings_screen.dart` | Advanced-mod preferences: compression, reactions, wardrive, images |
| `region_management_screen.dart` | Manage named regions / flood scopes for channel routing |
| `message_history_database_screen.dart` | Message-history database: statistics, migration quarantine, exports, vacuum |
| `app_debug_log_screen.dart` | In-app log viewer (app-layer messages) |
| `ble_debug_log_screen.dart` | In-app log viewer (raw BLE frame traffic) |
| `companion_radio_stats_screen.dart` | RF stats (RSSI, SNR, packet counts) for paired radio |
| `telemetry_screen.dart` | Battery / sensor / environmental telemetry for a contact |

### Images (Advanced mod)
| Screen | Purpose |
|---|---|
| `canvas_editor_screen.dart` | Draw/compose a tiny image and send it over the mesh (MCO image codec) |
| `mco_image_gallery_screen.dart` | On-device gallery of MCO images + bundled `.mcoimg.pack` sets |

## Architecture

### State Management

`Provider` with `ChangeNotifier`. `main.dart` wires a `MultiProvider` with the following:

| Provider | Role |
|---|---|
| `MeshCoreConnector` | Active transport (BLE/TCP/USB), connection state, frame I/O; opaque `activeTcpConnectionIdentity` fences work across reconnects, including the same endpoint |
| `MessageRetryService` | ACK tracking and retry scheduling with backoff |
| `PathHistoryService` | Per-contact routing history (LRU cache, `maxCachedContacts` = 1000), per node: `setDevicePublicKey` rebinds it at every SELF_INFO |
| `AppSettingsService` | App preferences (theme, units, locale, notifications) |
| `BleDebugLogService` | Raw BLE frame log buffer |
| `AppDebugLogService` | Structured app log buffer |
| `ChatTextScaleService` | Pinch-to-zoom text scale for chat screens |
| `TranslationService` | On-device LLM translation — **disabled stub** in this build (see intro) |
| `UiViewStateService` | Contacts/channels sort/filter/search state |
| `SettingsSectionsService` | Public stub/private-module bridge for optional settings sections and device capabilities |
| `TimeoutPredictionService` | ML linear regression for ACK timeout prediction |
| `StorageService` | Path history + delivery observation persistence (`Provider`, not `ChangeNotifier`) |
| `MapTileCacheService` | Raster map tile cache and offline-region downloads |
| `WardriveService` | Coverage-mapping scanner: GPS-tagged SNR/RSSI samples + cloud upload (Advanced mod) |
| `ImageCodecService` | Optional AEIC encoder/decoder backend and model lifecycle |
| `ReceivedImageStore` | Persistent AEIC receive/send state, lazy image bytes and decode queue |

Non-provider singletons wired in `main()`: `NotificationService`, `BackgroundService` (Android foreground-process/Flutter-engine retention for BLE, optional TCP and wardrive keep-alive reasons), `MeshCompressor` (MCMP model init), `MCOImageGalleryStore` (installs bundled image packs). `BackgroundService` does not own BLE or parse frames: the retained engine keeps the existing `MeshCoreConnector` alive.

Screens consume these via `Consumer<T>` (or `context.watch<T>()` / `context.read<T>()`) for reactive UI.

### Data folder (Windows and Linux)

On Windows and Linux everything the app writes lives in one folder of its own, so that several copies, or several profiles of one copy, run side by side, connected to different nodes, without sharing a preferences file or a database, and so that a portable copy leaves nothing behind in the system. The folder is `userdata` beside the executable unless `--data-dir=<path>` names another, absolute or relative to the executable's folder rather than the working directory, so a shortcut and a terminal open the same one. The last `--data-dir` wins, quotes are dropped from it on Windows (`--data-dir="C:\My Data\"` arrives as `C:\My Data"`, the closing backslash read as escaping the quote), and `--data-dir` with no path stops the start on an error screen rather than guessing. macOS, Android, iOS and the web keep the system directories (`DataRootMode.system`), and macOS does not read the argument.

`prepareDataRoot` (`storage/data_root_io.dart`; the rules in the pure `data_root_core.dart`, a web stub behind `data_root.dart`) runs first in `main()`, at stage `MCO-STARTUP-110`. It replaces `PathProviderPlatform.instance` with a subclass of the platform's own provider whose four directories are folders of the data folder, made when first asked for, and hands the same provider to the Windows and Linux preference stores, which keep a `pathProvider` field of their own, marked for tests yet the only way to give them a folder, and would otherwise go on writing to the system folder. The stores and services needed no change: `getApplicationSupportDirectory()` and its siblings simply answer differently. Downloads and the save dialogs stay the system's.

```
<data folder>/
  profile.lock      the lock, held while the app runs
  window_state.txt  the window size, kept by the Windows runner
  migration.json    the state of the copy of an earlier installation's data
  support/          preferences, both databases, received images, MCOimg packs
  cache/            the GIF cache
  temp/             map tile files (offline regions included), link previews, notification pictures
  documents/        image codec and translation models
```

`temp/` is not scratch: it holds the tiles of downloaded offline regions, and nothing empties it but the app. Nothing may ask path_provider for a directory before `offerDataTransfer` has returned: the provider makes the folder it answers, and anything in the data folder besides `profile.lock` and `window_state.txt` makes it used, so the offer below would never come. The startup error handler therefore reads `DataRoot.path` on Windows and Linux instead of asking a provider, and the platform's own provider is asked only to look up the old documents folder, which it does not create.

**The lock.** `lockDataRoot` takes an exclusive lock on byte 4096 of `profile.lock`, past the process id written at its start, which stays readable while another copy holds the lock. A start on a folder in use retries for two seconds, which covers the restart after the history migration, and then shows `DataFolderProblemApp` (`screens/data_folder_problem_screen.dart`) instead of the app; a folder that cannot be created or written, one under Program Files for instance, gets the same screen with the error, and the app never falls back to a system folder. A lock this process already holds counts as taken: a hot restart leaves the previous isolate's handle open, and on Windows a lock belongs to the handle. macOS takes the same lock in its application support folder, its only data folder.

**Copying an earlier installation's data.** A new data folder, missing or holding nothing but `profile.lock` and `window_state.txt`, is offered at stage `MCO-STARTUP-111` the data that a build from before the data folder left in the system folders (`offerDataTransfer` in `screens/data_transfer_screen.dart`, the work in `storage/data_transfer_io.dart`). Every new folder is asked, the default one and every `--data-dir` profile, as long as the old support folder holds data. On Windows that is `%APPDATA%\com.meshcore\meshcore_open (Advanced mod)`, with the same names under `%LOCALAPPDATA%` for the cache, the system temporary folder for the tiles and the documents folder for the models; on Linux the application id under `$XDG_DATA_HOME` (else `~/.local/share`), or the executable's name where only that folder exists, and under `$XDG_CACHE_HOME` (else `~/.cache`). The names are those of `Runner.rc` and `linux/CMakeLists.txt`, and a test keeps `LegacyData` equal to them. The question lists the old folders, their size, counted in a background isolate while it is on screen, and the copies made before; closing the window on it decides nothing, and "Start with empty data" starts the app on the empty folder, which its first writes make used.

The copy runs in a background isolate and counts bytes. The two databases go as consistent snapshots, sqlite3's `Database.backup` over a read-only connection, since an older build may still have them open and be writing; of the tile files only those the old tile database names (all of them where it has none), flutter_cache_manager before 3.4.2 having left files no record named; everything else file by file, except `libCachedImageData.json`, the index of flutter_cache_manager's default cache, whose files lie among every other Flutter app's in the system temporary folder and are not copied either (link previews are fetched again). Each folder fills under a `.partial` name and is renamed into place at the end, `support` last, while `migration.json` says `copying`, so a copy cut short by a closed window or a crash is cleared at the next start and offered again; a failed copy leaves the data folder with its housekeeping files, the failure screen up and the offer for the next start. It copies and never moves: the old data stay for an older build, and only a line in `COPIED_TO_PORTABLE.txt` in the old support folder, written best effort, records when and where to, for later offers to list.

**Deleting the old data.** At a start later than the copy, never the same one, `offerDataCleanup` (stage `MCO-STARTUP-112`) asks whether the old folders may go: a screen before the app rather than a dialog over it, because the connection to the last node starts with the app and moves its screens over any dialog. The folders named after the app go whole, with an empty `com.meshcore` parent on Windows; from the folders others share, the temporary one with the tiles and the documents with the models, only the files that have a copy in the data folder go, with the folders that leaves empty. A recorded support or cache folder is deleted only under one of the app's own names, so a damaged `migration.json` cannot point the deletion anywhere else. Deleting everything settles the question (`cleanup: done`), and so do old data already gone, without asking; "Keep" settles it as well (`declined`); a file another running copy holds open stays, the folders still holding something are listed, and the question comes again at the next start (`pending`). To be asked again, set `cleanup` back to `pending`; never set `state` to `copying` by hand, which clears the data folder at the next start.

**The window size** is read by the Windows runner before Dart starts, so `windows/runner/main.cpp` finds the data folder itself: its `DataFolder` repeats `selectDataRoot` rule for rule, and a change to one goes into the other. The runner keeps the logical size in `window_state.txt` and never writes the registry. The size an earlier build kept under `HKCU\Software\com.meshcore\meshcore_open\WindowState` is read while the file has none, and the first write to the file deletes those two registry values and the keys they leave empty; `com.meshcore\meshcore_open` is the vanilla app's name as well, so nothing else under it is touched. The runner makes no folder, so nothing is kept until Dart has made the data folder, and it writes the file directly, since a temporary file left by a crash would make a new folder look used. It does without `std::filesystem`: the runner builds with `/W4 /WX` and `_HAS_EXCEPTIONS=0`, and no plugin compiles `<filesystem>` under those flags.

**Notifications.** The Windows notification plugin registers the app in the registry at every start (`HKCU\Software\Classes\AppUserModelId\<id>` with the display name and the activator's `CustomActivator`, and `...\PushNotifications\Backup\<id>`) and registers a COM class object for the activator GUID in the process. A click on a toast is a `CoCreateInstance` of that GUID, and with every copy registering the same one COM handed the click to whichever process it found first, so a notification of one copy opened another. The identity therefore comes from the data folder (`helpers/windows_notification_identity.dart`): the GUID is the v5 UUID of the lowercased normalized path in the namespace of the old fixed GUID, the app user model id is `org.meshcore.open.app.` plus the GUID's first sixteen hex digits, and the display name carries the folder (`MeshCore Open (node-868)`; the app folder's name for a default `userdata`), which is also how Windows tells the copies apart in its notification settings. Two registry keys per data folder stay behind, which the owner accepted. The two keys of the fixed identity earlier builds wrote go once no such build is running (`helpers/legacy_notification_registry.dart`, from `NotificationService.initialize`, on a background isolate so that a hung old copy cannot hold the start): an older build writes them again at every start and shows its toasts under them, so deleting them under a running one would leave it without toasts until its restart. Whether one runs is COM's to answer: `CoGetClassObject` for the old activator GUID with `CLSCTX_LOCAL_SERVER` finds the class object a running copy registered, from any process, and answers `REGDB_E_CLASSNOTREG` when nobody serves it; it starts nothing, since the plugin registers no `LocalServer32`, which is also why no toast launches a closed copy. The registry is read first, so the usual start, with nothing left to remove, asks COM nothing; any other answer from COM or the registry keeps the keys for the next start. The `Settings` key Windows itself writes under `...\Notifications\Settings\<id>` when the user changes an app's notification settings is not the app's and is left. On Linux the plugin keeps its id map in `$XDG_RUNTIME_DIR/mco_advanced/notification_plugin_cache.json`, one file for every copy, read once at initialization, so a copy started while another's notifications are still up may answer clicks on those as well; that needs a change in the plugin and is accepted. The Linux runner is `G_APPLICATION_NON_UNIQUE`, Flutter's default, and keeps no window state.

**Developing.** `flutter run` starts the executable inside `build`, so its `userdata` lives there and `flutter clean` deletes it; a profile that lasts takes a `--data-dir` outside the tree: `flutter run -d windows --dart-entrypoint-args=--data-dir=<absolute path>`, `-d linux` the same way. A test that calls `prepareDataRoot` passes an explicit `--data-dir`, or the folder is made beside the test runner's executable. `--loading-timing` appends the length of every startup step, and the time from the process start to `main`, to `loading_timing.txt` beside the executable (`utils/startup_timing.dart`; the steps are the `_setStartupStage` codes and the `StartupTiming.mark` calls in `main.dart`); it is how the AEIC sidecar rewrite was found.

### Storage / Persistence

The stores in `lib/storage/` **scope their data by the first 10 hex chars of the connected device's public key**, so per-radio data is isolated. What is written on traffic lives in SQLite (see the next section): the message history, the node's contacts and channels, the path histories and the delivery observations, each one row per item, and the small per-node collections as one JSON row each in `node_state`. Settings stay in `PrefsManager` (a `SharedPreferences` singleton initialized in `main()`): `app_settings`, the per-channel and per-contact setting keys, marker styles, unread counts, blocked senders, the MCOimg gallery index and single flags. On Windows and Linux the plugin rewrites the whole preferences file on every `set` and `remove`, absent keys included, which is why the heavy collections left it and why a load never writes there (`ChannelRegionStore.loadRegion` reads only, the legacy-key removals check `containsKey` first, `NodeIdentityStore.saveName` writes only a changed name). Every store keeps its preference form for the web build and for a process without the database, such as a unit test (`MessageHistoryStorage.hasDatabase` false).

| Store | Persists |
|---|---|
| `message_store`, `channel_message_store` | Direct + channel messages (SQLite-backed, see below) |
| `contact_store`, `contact_discovery_store` | Known contacts, one `node_contacts` row each; discovered contacts, app-wide, in `discovered_contacts` (see below) |
| `channel_store`, `channel_order_store`, `channel_settings_store`, `channel_group_store` | Channels (`node_channels` rows), display order and channel groups (`node_state` rows), per-channel compression/sign toggles and sender name (preferences) |
| `channel_region_store`, `region_store` | Per-channel region tag + known regions / flood scopes (Advanced mod) |
| `contact_region_store` | Per-contact flood region, a `contact_settings` row in the message-history database rather than a preference (Advanced mod) |
| `community_store` | Communities (32-byte shared secrets), a `node_state` row |
| `contact_group_store`, `contact_settings_store` | Groups (a `node_state` row); per-contact compression (MCMP/MCOtxt/Smaz/cyr2lat), sign, sending-delay, quick-answer, widget-color settings (preferences) |
| `node_identity_store` | The node's own name, a `node_state` row read through a startup cache |
| `connection_transport_preference_store` | Last-used transport (BLE/USB/TCP) per device |
| `mco_image_gallery_store` | On-device MCO image gallery + bundled `.mcoimg.pack` index (Advanced mod) |
| `unread_store` | Per-contact unread counts (debounced writes) |

Wardrive samples, sessions and the record of what was uploaded where live in the message-history database (the `wardrive_*` auxiliary tables, see the next section) behind `wardrive_sample_store`; only the ignore list (`wardrive_ignore_store`), the upload sites and the auto-upload flag stay in SharedPreferences. The disabled translation subsystem still exposes a `translation_file_store` file path for model removal only.

`services/storage_service.dart` keeps the path histories (`contact_path_history`, one row per node and contact, plus a shared row under the empty node key for the histories written before the keys carried a node, which every node reads until it saves its own), the delivery observations of the timeout prediction (`delivery_observations`, the capped list replaced whole, two seconds after a change at most) and the app-wide maps (repeater passwords, the auto clock sync flags) as `node_state` rows under the empty node key. `storage/node_state.dart` is the one helper behind the small collections: a value per node and name in the database, or the preference key it always had.

`PrefsManager.prepareDesktopPreferencesFile` runs before the plugin opens `shared_preferences.json` on Windows and Linux, where the plugin rewrites the file whole and not atomically: a file that decodes is copied to `.bak` through a temporary file, a file that does not is set aside as `.corrupt-<time>` and the copy restored when it decodes, so a write cut short costs the changes of one session rather than everything (`test/storage/prefs_manager_desktop_file_test.dart`).

A few states are deliberately **unscoped by node** because they describe this phone rather than any radio's data. The blocked-sender table is managed through `BlockedSenderStore`, the map's node-filter chip row writes its collapsed or expanded state directly under `map_node_filters_expanded_v1`, and whether the battery-optimization exemption has ever been asked for is recorded under `background_battery_exemption_asked_v1` (see the Android section). The discovered-contacts list (`contact_discovery_store`, the `discovered_contacts` table described in the next section) is one for the whole app too: those nodes are stored on no radio and only the app knows them, whichever radio it heard them through. Upstream scopes that list per node, moving the global one to the first node that loads it; the scoping was left out of the merge on purpose, so keep it out when an upstream change to that store offers it again. Anything holding per-radio data belongs in a scoped store instead.

### Application database

The database started as the message history and still carries that name in its file (`message_history.sqlite`), its classes (`MessageHistoryDatabase`, `MessageHistoryStorage`) and the l10n keys of its maintenance screen, but it holds the node collections and the wardrive data as well: it is the application's database. A rename is deferred on purpose (153 references, the generated `.g.dart`, 46 l10n keys in 18 locales) and, if ever done, is its own commit, never mixed with a data move.

Message history moved out of `SharedPreferences` into SQLite via **drift** (`message_history.sqlite` in `getApplicationSupportDirectory()`, the data folder's `support/` on Windows and Linux). Three decisions shape everything else, and all three exist to keep the change to a storage backend rather than a rewrite:

- **One table for both kinds.** `HistoryMessages` carries a `kind` discriminator (`0` = direct, `1` = channel) instead of two parallel tables, which would have doubled every query for nothing.
- **The key space is unchanged.** `storageKey` *is* the former preferences key (`messages_<10hex><contactKey>`, `channel_messages_<10hex>name_<…>`), so `MessageStore` / `ChannelMessageStore` still speak the same strings and all the legacy-key handling — scoped vs unscoped, name-keyed channels — keeps working untouched.
- **The message stays JSON.** `messageJson` holds the whole serialized message; the other columns are denormalized projections of it, added only for the queries that actually run. `MessageHistoryStorage` hands callers back a JSON array string, so `_messageToJson` / `decodeStoredMessage` never had to change.

`MessageHistoryStorage` is the only door to the database. Every method has a `kIsWeb` branch that falls back to `SharedPreferences`, because the web build never creates the database at all — `initializeAndMigrate` returns before constructing it, which is why `web/` carries no `sqlite3.wasm` or `drift_worker.js` despite the `DriftWebOptions` in the constructor.

**The file is in WAL mode with `synchronous = FULL`** (`MessageHistoryDatabase.setupConnection`, run in the database isolate at every open through `DriftNativeOptions.setup`, and what the tests hand `NativeDatabase` to open a file the same way). Before, the database ran with the rollback journal, so every commit, one per received message, per copy of one and per contact write, wrote the journal, the file and an fsync of each: 11 to 15 ms measured, which `_addChannelMessage` waited out before notifying and the queue drain before its next `SYNC_NEXT`, and reads queued behind writes on the one connection. A commit now appends to the write-ahead log, 3.5 ms with FULL, and reads no longer wait for writes. FULL rather than NORMAL is the owner's decision: the tile cache runs NORMAL because a tile can be fetched again, a message cannot, so every commit is on disk before the write returns, a power cut included. A database from before the change switches over at its next open. The log is reused after a checkpoint but never shrunk by itself, and the app never closes this database, so `journal_size_limit` (4 MB) cuts it back after a checkpoint, `initializeAndMigrate` runs `truncateWriteAheadLog` (`PRAGMA wal_checkpoint(TRUNCATE)`) at every launch after the one-time moves, each of which is one transaction the size of what it moves, and `fullVacuum` runs it after the `VACUUM`, which writes the whole rebuilt file into the log. The multi-row writes of the auxiliary tables (the node collections, the discovered contacts, the delivery observations, the wardrive imports and deletions) go through `batch()`, one round trip to the database isolate per batch instead of one per row, with the same statements in the same order in one transaction; `importWardriveSamples` counts its rows before and after the batch, since a batch reports no change counts (`test/storage/message_history_journal_test.dart`, `message_history_wal_test.dart`).

**Indexes** (`schemaVersion = 2`, `auto_vacuum = INCREMENTAL` set in `onCreate` *before* `createAll()` — the only moment that pragma takes effect):

| Index | Serves |
|---|---|
| `history_message_timeline` (kind, storageKey, timelineAtMs, messageId) | cursor pagination |
| `history_message_identity` (kind, storageKey, messageId) UNIQUE | upsert by message id, and the upsert's conflict target |
| `history_message_summary` (kind, storageKey, isCli, timelineAtMs, messageId) | contact-list previews, covers the `ORDER BY` too |
| `history_message_marker` (kind, storageKey, containsMarker) | the map's marker sweep |
| `legacy_rejected_location` (kind, storageKey, messageIndex) | quarantine listing |

**Auxiliary tables** stay out of the drift table list, so adding one needs no regenerated `.g.dart` and no schema bump: `_ensureAuxiliaryTables` runs `CREATE TABLE IF NOT EXISTS` for `legacy_rejected_messages`, `contact_location_cache`, `heard_packets`, `contact_settings`, `discovered_contacts`, `wardrive_samples`, `wardrive_sessions`, `wardrive_uploads`, `node_contacts`, `node_channels`, `contact_path_history`, `delivery_observations` and `node_state` from `onCreate`, `onUpgrade` and `beforeOpen`, which is what gives a database that predates one of them the table on its next open, and they are read and written through `customSelect` / `customInsert` / `customUpdate`. `contact_settings` (`node_key`, `contact_key`, `name`, `value`, one primary key over the first three) holds per-contact settings of a node as text. The contact flood region (`ContactRegionStore`, name `flood_region`) is its first tenant; a setting moving out of preferences later takes a new `name`, not a new table.

`discovered_contacts` (`public_key_hex` primary key, `contact_json`) holds the app-wide list of discovered nodes, one row per node in the JSON `ContactDiscoveryStore` has always written, read back in rowid order, which is the list's own since an update keeps its row. The connector saves that whole list on every advert it hears, so the store writes only the contacts that are not the very objects it last loaded or wrote (an update always replaces a contact through `copyWith`), runs its writes one after another, copies the list it is handed before its turn comes (the connector hands in its live list, and a disconnect clears it), and deletes only against a list it has loaded. `initializeAndMigrate` moves the former preference key (`discovered_contacts`, one JSON array) into the table once: rows already there win, the key goes only after the commit, and a failure leaves the key for the next launch rather than stopping the app over a cache. The web build, and a process that never opened the database such as a unit test (`MessageHistoryStorage.hasDatabase` false), keep the list in that preference.

The wardrive data follows the same pattern, in three tables. `wardrive_samples` (`id` primary key, `timestamp_ms`, `public_key_hex`, `ping_success` nullable, `sample_json`) holds one sample per row, the JSON being what `WardriveSample.toStorageJson` writes and the columns what the queries order and filter by; `wardrive_sessions` (`start_time_ms` primary key, `session_json`); `wardrive_uploads` (`sample_id`, `endpoint_url`, `uploaded_at_ms`, primary key over the first two) records which sample reached which upload site. `WardriveSampleStore` (`services/wardrive_sample_store.dart`, every method asynchronous) is the one reader and writer; where the database does not exist it keeps the three preference keys it always used (`wardrive_samples_v1`, `wardrive_sessions_v1`, `wardrive_uploaded_samples_v1`). Samples are ordered newest first by their own timestamp and capped at `MessageHistoryStorage.wardriveSampleLimit` (6000, the oldest going as new ones arrive; the preference form kept 3000 for the size of the file), sessions at 200. An upload record dies with its sample: a trim, a removal from the map and a clear drop the records of what they remove, since a sample that is gone cannot be uploaded again. The upload service asks the store for the newest samples that carry a reading and have no record for the site (`pendingUpload`, one query with a limit, the ignore list applied in Dart) instead of decoding every stored sample on every upload, and marks a posted batch through `markUploaded`. `WardriveService` keeps the samples in memory for the map (`recentSamples`, a filtered view built once per change) and reads them from the store asynchronously at construction, at `start()` and after an import or a removal. `initializeAndMigrate` moves the three keys once, in one transaction, samples and sessions already there winning and an upload record taken only for a sample that made it, and removes the keys after the commit; a failure leaves them for the next launch. Tests open the database over an in-memory or temporary-file executor (`MessageHistoryDatabase.withExecutor`, `initializeAndMigrate(databaseFactory:)`, `resetForTesting`) and skip themselves when the host has no native sqlite3.

The node collections follow the same pattern once more. `node_contacts` (`node_key`, `contact_key`, `contact_json`) and `node_channels` (`node_key`, `channel_index`, `channel_json`) hold one row per item. `ContactStore` and `ChannelStore` are handed the connector's whole live list on every advert, sync and message, so they keep, per node, what the database holds as last loaded or written and write only the difference: contacts by identity (a `Contact` is immutable and an update replaces it), channels by content (`unreadCount` changes in place), deleting only against a list a load had seen, one write after another, with the node taken when the save is called, since the node may change before the write runs. `contact_path_history` holds a contact's whole history JSON per node, the shared row under the empty node key being the pre-scoping fallback; `delivery_observations` holds the capped list; `node_state` (`node_key`, `name`, `value`) holds the channel order, the channel groups with their UI state, the contact groups, the communities and the node's name, which `MessageHistoryStorage` reads into a cache at startup because the connector reads it synchronously. `_moveNodeCollections` moves every preference form into these tables once, in one transaction, the keys removed after the commit, rows already there winning, damaged elements skipped, a blob that is not JSON left in place, and the bare keys of the time before scoping (`contacts`, `channels`, `channel_order_`, `contact_groups`, `communities_v1`) untouched, since only the preference form of the stores reads them. On the first machine the move took a 2.4 MB preferences file down to its settings.

**`timelineAtMs` repeats the domain rules rather than inventing its own.** It is `receivedAt ?? timestamp` for channel rows and for room messages (detected by a non-empty `fourByteRoomContactKey`), and plain `timestamp` for ordinary direct messages — so SQL order matches `ChannelMessageTimelineHelper.compare` / `RoomMessageTimelineHelper.compare` instead of drifting from them. Contact-list summaries sort by the same column, which is why a room contact's `lastMessageAt` is its local receive time and not the timestamp the room server stamped.

**Reads are windowed and cursor-paginated.** Opening a conversation asks for `_initialContactHistorySize` / `_initialChannelHistorySize` (300 each); offline shared mode merges up to `_offlineSharedHistoryWindowSize` (1000) per scope. Older pages come from `loadMessagesBefore` / `loadChannelMessagesBefore`, anchored on the pair `(timelineAtMs, messageId)` — the second half of the key is what keeps ordering stable when several messages share a millisecond. `loadNewerMessages` / `loadNewerChannelMessages` are the forward half of the same cursor and are implemented but not yet called by any screen.

**Writes are per row.** Receiving a message upserts one row (`saveMessage` / `saveChannelMessage`); before, every incoming message re-serialized the whole conversation and rewrote the entire preferences file. `saveMessages` / `saveChannelMessages` still exist but their meaning changed from *replace* to *upsert*, so the four remaining call sites are all blocked-sender sweeps that genuinely touch several rows. Deleting is `deleteMessage`, clearing a conversation is `clearMessages` / `clearChannelMessages` — passing a shortened list no longer removes anything. The upsert names the identity index's columns as its conflict target on purpose: drift's default target is the autoincrement primary key, which an insert never collides on, so a repeated save of one message used to trip the unique index and fail — status promotions, merged paths and translations never reached the disk, and any reload from storage (the channel sheet's `setChannel` re-sync, a restart) showed the first insert again.

**Two in-memory caches** are filled by one `SELECT DISTINCT` each at startup and maintained on write: the set of known `storageKey`s per kind, and the keys whose history contains a marker. The marker cache is deliberately **add-only** on point upserts — a stale positive costs one wasted history read, while `replaceString` and `deleteMessage` recompute it exactly. That asymmetry is intentional and commented in place; it keeps `mayContainMarker` synchronous, which the map's sweep over every contact depends on.

**Corrupt records never take the whole read down.** `_messagesFromJson` / `_channelMessagesFromJson` decode element by element and skip a bad one with a log line instead of returning an empty list, so one unreadable message costs one message rather than the entire conversation.

### Migrating the legacy history

The move from preferences is **one-way, one-time and irreversible**, and it will meet years of accumulated real data on every device exactly once. Everything below exists because of that.

`MessageHistoryStorage.initializeAndMigrate()` runs from `main()` before any service exists. It finds legacy keys with strict regexes, imports them, and only then removes them from preferences. The import, the skip counters and the `legacy_migration_complete` flag all commit **in one transaction, before cleanup**, so an interrupted cleanup resumes on the next launch without importing anything twice.

The import walks one `storageKey` at a time in chunks of 200, yielding to the event loop between chunks, and reports through `migrationProgress` — a `ValueListenable` the `MessageHistoryMigrationApp` screen renders as "conversation N of M". Without the chunking the indicator would freeze, because `_companionsFor` runs `MessageTextCodec.tryDecodeKnownCompression` on legacy rows that predate `rawText`, and that is the MCMP arithmetic decoder. On desktop the app restarts itself afterwards (`restartAfterMigration`), releasing the data folder's lock first and handing the new process the arguments it was started with, so a `--data-dir` profile restarts in its own folder.

**Damage is skipped at two levels.** A container that will not `jsonDecode` costs that conversation; a single element that is not an object, or whose field has the wrong type, costs that message. The `catch` deliberately takes everything except `OutOfMemoryError` and `StackOverflowError` — a `TypeError` from `as int?` on a JSON double is the common case and is not an `Exception` — but it is drawn tightly around the pure conversion, with `batch()` outside it, so a database failure can never be mistaken for bad data.

**Validation runs the real parser.** `main()` passes `MessageStore.decodeStoredMessage` / `ChannelMessageStore.decodeStoredMessage` as `validateMessage`, so a message is only imported if the code that will later read it can read it. Checking only the ten fields `_companionsFor` touches would let a broken value ride along inside `messageJson` and fail at display time instead.

### Migration quarantine

Whatever the import skips is written to `LegacyRejectedMessages` **in the same transaction** — which is what makes it safe to wipe the preferences afterwards. A rejected element is stored as itself; a rejected container is stored whole, since there is nothing smaller to keep. Rows carry `rawValue`, `errorType`, `errorText` (capped at 1000 chars) and `messageIndex`; the write is kept deliberately primitive so the safety net cannot itself fail the migration.

`retryLegacyRejected` re-runs the quarantine through the current parser. A container is re-split, and whatever still fails comes back as *per-element* rows with an index — so every attempt makes the quarantine finer rather than repeating itself. `resolvedMessageId` is preserved so a recovered message lands under the id it would have had originally. This is the path that matters when the defect was in *our* parser rather than in the data: a later build simply recovers what an earlier one rejected.

Two exports, deliberately separate:

- **diagnostic** — schema version, error *types*, indexes and SHA-256 hashes of `storageKey`. No message text: `errorText` is excluded because `FormatException` from `jsonDecode` quotes the source around the failure, which would put conversation text into a file meant to be safe to send.
- **recovery** — the rejected entries with their original content, behind a confirmation that says so.

Both go through `file_selector.getSaveLocation` on desktop and `SharePlus` on mobile (falling back to share if the save dialog fails), because `getApplicationSupportDirectory()` is unreachable for a user on Android and iOS. The three outcomes are distinguished: a path means saved, an empty string means handed to the share sheet, `null` means the user cancelled — and a cancelled export must not be followed by the "delete the quarantine now?" prompt.

Counters live in `HistoryMetadata` (`legacy_migration_skipped_histories`, `…_skipped_messages`, `…_warning_pending`) and drive a one-time dialog shown from a post-frame callback after normal startup, with a button into the management screen. Migration logging uses `developer.log` rather than `appLogger` on purpose: `appLogger.initialize` happens far later in `main()` than the migration does.

`message_history_database_screen.dart` (UI) and `message_history_maintenance.dart` (statistics, exports, quarantine, vacuum) hold all of this, keeping `mod_settings_screen.dart` down to one section and a route. `PRAGMA incremental_vacuum` only works when `auto_vacuum = 2`, so the screen disables that action and swaps its description when `autoVacuumMode` says otherwise — databases created before the pragma was added need a full `VACUUM` first, which also switches the mode over. The size the screen shows is `MessageHistoryMaintenance.bytesOnDisk`: the file with the write-ahead log and its shared index beside it, since the log holds commits the file does not yet.

### Offline history mode

The BLE, USB and TCP connection screens expose the same `OfflineHistoryButton`. A user can open one saved node scope or choose the shared mode, which merges every known node scope without connecting to a radio. `MeshCoreConnector.enterOfflineHistory()` binds stores to the selected synthetic scope and uses read-only loading paths with legacy migration disabled; `exitOfflineHistory()` clears the offline state before a real connection begins. Shared offline mode builds a merged contact/channel/message view up front, while single-node mode keeps that node's settings, order and unread data.

Offline mode is deliberately read-only for radio/device state: chat composers and send buttons are disabled, contact/channel management, repeater/room login, wardrive, discovery, tracing and device/app-setting routes that require a live session are blocked. Local-only viewing tools remain available, including the map, message search, MCOimg gallery and canvas. `connect`, `connectUsb` and `connectTcp` reject calls while the offline session is active so incoming frames can never be written under the synthetic scope.

### Stored-message search

`widgets/message_search_sheet.dart` is shared by contacts, channels and individual chat screens. It searches decoded human-readable text across the requested channel/contact/room scope, includes the configured shared-history scopes, debounces input for 1500 ms and processes bounded batches through `helpers/message_search_worker.dart` so parsing does not block the UI isolate. Results are ordered newest first, deduplicated across node scopes using the same content identity used by shared channel history, and retain enough source/message identity to open the conversation and materialize/scroll to the stored message. Desktop chat/list screens expose the same action through Ctrl+F.

### Deleting a shared-history message

Shared history is read out of the *other* node scopes in the same database and merged into the open chat on the fly (`_sharedChannelSecondaryMessages` / `_sharedContactSecondaryMessages`), so deleting one of those messages has to reach the store it actually lives in. `deleteChannelMessage` / `deleteMessage` drop it from the merged-in list and then `SharedMessageHistoryHelper.deleteSecondary*Message` rewrites the other scope without it; dropping it in memory alone would bring it back on the next merge. Matching is by `messageId` (persisted in both stores), which also removes the copy the merge hid when the same message exists in two scopes — otherwise deleting the local one just uncovers the shared duplicate. `deleteChannelMessage` takes the `Channel` rather than reading `message.channelIndex`, because a shared message carries the *other* node's channel index.

Clearing a whole conversation deliberately works the other way: `clearMessagesForContact` / `clearMessagesForChannel` only hide the shared scope for the session (`_hiddenSharedContactKeys` / `_hiddenSharedChannelIdentityKeys`) and leave the other node's data alone.

### Contact keys and lookups

`Contact.publicKeyHex` is computed once per instance (`late final`), not on every access. The key drives `==`, `hashCode` and every sort and lookup of contacts, and rebuilding the 64-character string each time used to be the main cost of the contacts screen. The cache is safe only because nothing writes into a contact's `publicKey` bytes; keep it that way.

The connector's `_contacts` is a `KeyIndexedList` (`helpers/key_indexed_list.dart`), a list whose `byKey` answers in O(1) with `firstWhere` semantics. Call sites need no bookkeeping: any mutation, through any `List` method, marks the index stale and the next lookup rebuilds it, so the two dozen places that change `_contacts` stay plain list code. `_shouldTrackUnreadForContactKey` uses it. The unread counts reach that check once per contact on every rebuild of the contacts list, and its old linear scan made the rebuild quadratic: about 55 ms at 300 contacts on a desktop, 0.2 ms now. A new per-contact lookup on a hot path belongs on `byKey`, not on another `firstWhere`.

Caches of per-contact data key on two connector revisions rather than on `uiRevision`, which moves on every notification, radio traffic and battery readings included. `contactsRevision` is the list's own version. `contactUnreadRevision` comes from the unread map, a `VersionedMap` (`helpers/versioned_map.dart`), for the same reason the list indexes itself: no write site, including one arriving in an upstream merge, has to remember to bump anything; it reads -1 while the unread state is not loaded. The contacts screen keys its derived rows on both, plus the view state, the locale and a minute bucket for the "last seen" labels. Its recent-messages sort also reads message timestamps, which change without either revision when a message is deleted or history loads, so in that mode the key adds a fingerprint of each contact's last direct-message time.

### Contacts the node keeps

The node owns its contact table and says what it did with each advert. `PUSH_CODE_NEW_ADVERT` comes only for a node it did not store (`BaseChatMesh::onAdvertRecv`), so `_handleNewAdvert` feeds the discovery list and nothing else, while `PUSH_CODE_ADVERT` names a stored contact, which `getContactByKey` re-reads. `PUSH_CODE_CONTACT_DELETED` (0x8F) reports a contact dropped to make room under overwrite-oldest auto-add: `_handleContactDeleted` takes it off the list and, unlike a removal by hand, leaves its history alone. `PUSH_CODE_CONTACTS_FULL` (0x90) sets `contactsStorageFull` and emits on `contactsFullEvents`; removing a contact clears the flag. The answer to a GET_CONTACT_BY_KEY is a CONTACT frame like those of a sync, so the reply pairing tells it apart (`completeReply`, then `countTowardSync` in `_handleContact`) and it neither counts towards a running sync nor re-arms its idle timeout. `getContacts` does not start a second sync while one younger than a minute is running: the firmware refuses it with ERR_BAD_STATE, and the list clearing it does would lose what the first had delivered.

**The contact list is the node's.** Every sync keeps the list on screen while it runs (`preserveExisting`), so a full one, without `since`, is what prunes it: `CONTACTS_START` notes the keys listed before it (`_contactsUnconfirmedBySync`), every CONTACT frame, a sync's or a GET_CONTACT_BY_KEY answer, strikes its key, and at `END_OF_CONTACTS` `_dropContactsMissingFromNode` removes what is left, a contact the node no longer holds or never did. Its conversation stays in the database and its unread count goes, nothing on screen being left to clear it. A sync filtered by lastmod lists only what changed and a sync that ended in the idle timeout proves nothing, so neither drops anything. Discovered entries never become contacts: `isActive` in the discovered list only mirrors membership (`updateKnownDiscovered`). `_loadDiscoveredContactCache` used to merge every entry flagged active, favourite or with messages into the list, and with NEW_ADVERT still routed through `_handleContact`, which recorded each node as an active discovered entry before the auto-add filter, every node a node with auto-add off declined came back as a contact at the next connection: contacts the node did not hold, which the official app did not show, which returned after deletion and failed a batch deletion. `removeContact` therefore takes the node's ERR_CODE_NOT_FOUND (`CommandFailedException.errCode == errCodeNotFound`) as a finished removal, so such an entry can still be deleted.

**Repeaters only the app knows.** The contact list also shows the repeaters the app has heard whose adverts the node did not keep (`MeshCoreConnector.localRepeaters`: discovered entries of type repeater with no counterpart in `_contacts`), after the node's own contacts and with `contacts_notInNodeMemory` as the last line of the card; `_discoveredContacts` is a `KeyIndexedList` too, and the screen keys its snapshot and its derived rows on `discoveredRevision` as well. They stay in the app-wide discovered list, never in `_contacts`, up to
`maxDiscoveredContacts` (1000, the stalest evicted), or
`evictingDiscoveredContactsCap` (350) while the *evict discovered contacts*
toggle of the auto-add dialog is on, an app setting
(`evictDiscoveredContactsEnabled`, off by default) that trims the list the
moment it is switched on. A ping reaches them as they are, a trace needing no contact on the node. A login, a status or region request, a favourite or a share needs the node to hold the contact (the firmware answers ERR_CODE_NOT_FOUND otherwise, and a region request on a route writes the contact through `setContactPath`), so these go through `runWithContactOnNode` (`widgets/node_memory_prompt.dart`), which asks before `importDiscoveredContact` writes it and tells a full table (ERR_CODE_TABLE_FULL) apart from other failures. The map's actions on discovered nodes, opening a chat and joining a room included, ask the same way; they used to import silently. `deleteContact` removes a contact from the node when the node holds it and from the discovered list otherwise, so deleting such a repeater sends the node no removal it cannot perform; its next advert brings it back.

### Contact message summaries and channel-screen visibility

`Contact.hasMessages` means that an actual direct-message history exists for the contact in either the current node's store or an enabled shared-history scope. Channel posts, adverts, and discovery activity must not set this flag. Missing `hasMessages` values in legacy `contact_store` / `contact_discovery_store` records are treated as `false`; `_refreshContactMessageSummaries()` rebuilds the flag from real local/shared message summaries and clears stale values. When summaries are merged, `lastMessageAt` remains monotonic and keeps the newest known timestamp.

Incoming channel activity may still advance a known contact's `lastMessageAt` for activity sorting, but `_updateContactLastMessageAtByName()` calls `_setContactLastMessageAt(..., markHasMessages: false)`, so this never makes an empty direct conversation appear on the channels screen. Channel-author attribution follows this order:

1. A valid MCMP v3 signature uses the verified full public key for an exact contact match.
2. Otherwise, the sender name is used only when it matches exactly one chat contact.
3. With no name match, the packet path may be used only when the negotiated path-hash width is at least two bytes and exactly one contact matches.

`verifiedSenderKeyHex` is populated only when the signature is valid. Callers must still require
`mcmpSignatureStatus == McmpSignatureStatus.valid` whenever they use it as authenticated identity;
the badge follows the same rule and never shows a fingerprint for invalid or unverifiable results.

### Theming
- Material 3 design (`useMaterial3: true`)
- Light/dark selected via `AppSettings.themeMode` (`system` / `light` / `dark`)
- `lib/theme/mesh_theme.dart` defines the warm-dark `MeshPalette` (phosphor-green accents) and **is wired** in `main.dart` via `MeshTheme.light()` / `MeshTheme.dark()`
- Global UI scale (`AppSettings.uiScale`, optionally applied to icons) is layered on top of the system text scaler in the `MaterialApp.builder`
- Bundled `Inter` and `JetBrains Mono` fonts (see `pubspec.yaml`)
- Совместимость рендеринга iOS реализована в `lib/helpers/ios_presentation_guard.dart`, `ios/Runner/IosPresentationMonitor.swift` и отдельном `ios/Runner/IosPresentationGpuGuard.swift`. Native application/scene-события откладывают `drawFrame` до widget build/layout/paint; при возврате обычный кадр отображает актуальные данные с сохранённым состоянием виджетов. При активной совместимости и подписке presentation native helper дополнительно устанавливает публичный `FlutterEngine.isGpuDisabled` до уведомления Dart, не переключая его lifecycle и не останавливая таймеры/транспорты. Engine получается через registrar и проверяется по messenger; до появления viewController получение повторяется при watch/событиях и одном отложенном вызове. Запрет проверяется даже при неизменном active: Flutter может включить GPU на `willEnterForeground`; один повтор в очереди main thread учитывает порядок обработчиков, устаревший повтор после resume/отписки отменяется. Снимается только собственный запрет при полной активности; известная неактивная сцена блокирует преждевременное разрешение. Независимый `mco_advanced/ios_activity` сохраняет отдельную подписку. `MCO_IOS_RENDER_GUARD=false` отключает оба слоя; без совместимости native helper не меняет GPU. В `iOSRendering` сохраняется `gate=uiPipeline`, добавлены `nativeGpuGuard` и `gpuDisabled`; false/null для недоступного engine означает отсутствие native-слоя. `sendFramesToEngine` сохраняет first-frame deferral Flutter. Это не синхронный GPU drain, не непрерывная блокировка между конкурирующими обработчиками и не восстановление уже повреждённых ресурсов; результат требует проверки на iPhone. Native baseline/регрессии в `ios/RunnerTests/RunnerTests.swift` используют изолированный NotificationCenter; проверки engine API не запускают отдельный Dart isolate.

### Localization

18 locales supported via Flutter's standard ARB pipeline (`lib/l10n/`): en, de, es, fr, it, pt, ru, uk, bg, hu, ja, ko, nl, pl, sk, sl, sv, zh. Language override comes from `AppSettingsService.settings.languageOverride`. Use the `context.l10n` extension (`lib/l10n/l10n.dart`) for translated strings; contact-type names live in `contact_localization.dart`.

Every non-template locale carries ~37 keys that `app_en.arb` no longer has — the whole `path_*` / `chat_path*` group (`chat_pathManagement`, `path_currentPath`, `path_setPath`, `path_routeWeight`, `chat_score`, …), `settings_bleDebugLog` and its subtitle, plus a few per-locale leftovers (`repeater_refreshLocationSettings` and the malformed `neighbors_heardA ago` in ru/uk, the `settings_preset*Mhz` radio presets in zh). None of them are referenced from Dart and `gen-l10n` ignores anything absent from the template, so they are harmless. **Do not delete them**: merges from the upstream `meshcore_open` dev branch reintroduce the same keys, so a cleanup only produces churn.

`untranslated.json` is a snapshot written by the last `gen-l10n` run, not a live view — check missing keys against `app_en.arb` directly before concluding a locale is incomplete.

## Advanced mod features

Everything below is fork-specific and lives on top of the vanilla protocol. Most is threaded through `MeshCoreConnector` on the send/receive paths; toggles are per-contact / per-channel in `contact_settings_store` / `channel_settings_store` and edited in `mod_settings_screen.dart`.

### Text compression (4 selectable schemes)
`MessageCompressionType { mcmp, smaz, cyr2lat, mcotxt }` (`models/message_compression.dart`). Applied outbound in `MeshCoreConnector.prepareContactOutboundText()` / `prepareChannelOutboundText()`; decoded inbound via `helpers/message_text_codec.dart` by prefix (`mcmp2:`, `mcmp3:`, `mct:`, SMAZ).
- **MCMP** (`helpers/mesh_compressor.dart`) — context-mixing + arithmetic coder driven by the bundled `assets/models/model-en-ru.json` (EN/RU), Base91 output, prefix `mcmp2:` (legacy `mcmp:` gated off). A v3 signed/metadata container is handled by `helpers/mcmp_app_codec.dart`.
- **SMAZ** (`helpers/smaz.dart`) — classic short-string dictionary coder.
- **cyr2lat** (`helpers/cyr2lat.dart`) — not real compression; maps look-alike Cyrillic letters to ASCII so Cyrillic text fits the cheaper wire encoding. Whatever sits inside square brackets stays as typed: a mention's name, the reply mention above all, which the receiver matches against the sender's name, and any bracketed word; a colour tag keeps only its key, the text it encloses lying outside both tags. The one exception is a reply's quote line (`@[name] >fragment`), transliterated whole, brackets included, because receivers of every version match it against their own full transliteration of the quoted message; a bracketed name kept there would leave the quote unlinked on them. The reply mention ends at its first closing bracket, as `ChannelMessage.parseReplyMention` reads it; it used to run to the last `] ` in the message and left everything before it in Cyrillic (`test/helpers/cyr2lat_test.dart`). The South Edition node's own cyr2lat (`transliterateChannelText`, applied to the app's plain channel text when the node has it on) maps every character, brackets and the reply mention included.
- **MCOtxt** (`lib/MCOtxt/`, container in `helpers/mcotxt_app_codec.dart`) — static TOP-4 letter-prediction codec with per-language tables, text prefix `mct:`, channel app subtype byte `0x31`. See **MCOtxt v1** below.
MCMP v2 and SMAZ use their `encodeIfSmaller` paths. MCMP v3 and MCOtxt always use their metadata container
when selected for an eligible message, whether signed or unsigned; structured payloads that have
their own format stay outside the normal text-compression path.

MCOtxt has one exception: the per-channel / per-contact **"plain when smaller"** rule, default on,
shown under the MCOtxt toggle in `channel_edit_sheet.dart`, `chat_screen.dart` and
`contacts_screen.dart` and stored under `*_mcotxt_plain_when_smaller_` keys in the two settings
stores. Before an MCOtxt send the connector costs both packets as the firmware builds them
(`BaseChatMesh::sendGroupMessage` / `sendGroupData`): GRP_TXT is `timestamp(4) + type(1) +
"Name: text"`, GRP_DATA is `data_type(2) + length(1) + envelope`, and the encryption around them
is the same; for a contact or room both forms are the text of one packet, so their UTF-8 lengths
decide. Plain text goes out when it is not larger. The plain candidate of a channel reply gets
its exact-quote fragment back (`_channelPlainAlternative`), because the composer leaves the
fragment out whenever `channelReplyCarriesContainerAnchor` promises a container anchor; a plain
candidate that would not fit `maxChannelMessageBytes` keeps MCOtxt. The channel composer counter
asks the same question through `channelPlainIfSmallerThanMCOtxt`, and `prepareContactOutboundText`
applies the rule itself, so the contact composer follows for free. The plain alternative of a reply
reads the conversation's history only while `exactQuote` is on: the merge costs milliseconds per
call and a disabled quote spends no fragment. `MCOtxtCodec.encode` remembers its last eight results
by text, explicit options and the default pair, handing back a copy of the bytes each time: the
composer's limiter, its counter, the plain-when-smaller comparison and the send each encode the same
text once more, and the planner, which is the wire format and is untouched, runs once for all of them
(`MCOtxtCodec.debugPlannedEncodings` counts its runs for tests).

The MCMP version and the sign flag are per channel and per contact (`channel_settings_store` /
`contact_settings_store`, each mirrored by a `MeshCoreConnector` getter for the window before the
stored value is read back). **The defaults are v3, unsigned**, and each of the two lives in four
places at once — two stores, two getters — so keep them in step. There is deliberately no migration:
a default reaches every channel and contact whose value was never written, not only new ones, and
only entries set by hand stay where they were put.

Unsigned is the deliberate half of that. The v3 container is taken for its structure — timestamp,
precise reply anchor, compression — while a signature costs 64 body bytes plus a `CMD_SIGN_*` round
trip, which firmware without those commands answers only by timing out (`_signAttempts` ×
`_signAttemptTimeout`, 5 × 3 s per message, before the send falls back to unsigned). Signing is
opted into per conversation instead.

Two consequences worth knowing. A plain chat contact never signs whatever the flag says —
`contactMcmpUseSign` is read only inside `contact.type == advTypeRoom` branches, a direct message
being authenticated by its own transport. And shared map markers on a channel travel as **plain
text** under this default: `allowMarkerPayload` is fed from the same flag, and an unsigned envelope
would cost bytes while proving nothing. A channel whose pins matter has to turn signing on, which is
what makes a `del:` command attributable.

### MCOtxt v1 (static-model text codec)
Fork-only text codec specified in [`docs/MCOTXT_V1_PROTOCOL.md`](docs/MCOTXT_V1_PROTOCOL.md)
(Russian: `docs/MCOTXT_V1_PROTOCOL_RU.md`); keep that document in step with the code, it is
written for other implementations. Where MCMP runs an arithmetic coder over a large n-gram
model, MCOtxt predicts the next letter from a static per-language TOP-4 table and spends a
variable-length token per character — a whole model is a few hundred bytes, so the same tables
are exported as C headers for microcontroller ports. Four layers, each in its own place:

- **Stream** — `lib/MCOtxt/mcotxt_codec.dart`: a header of four 3-bit fields — codec version
  (`1`), model-set generation (`0`), language A, language B — where version and generation escape
  through `7` + 8 bits (range 0–262, one encoding per value) and language `7` means none /
  extended header; then tokens. TOP4 ranks cost 2/3/4/4 bits, primary literals 7,
  punctuation 8, extension literals 9, SHIFT 5, TOGGLE_LANGUAGE 6, extended controls 9+
  (SWITCH_OTHER_LANGUAGE, RESET_CONTEXT, UTF8_RUN up to 32 bytes, TOGGLE_CASE_MODE). Three
  prediction contexts: START, AFTER_PUNCT, SYMBOL(prev). A whole message that is smaller as
  UTF-8 goes out in RAW_UTF8 mode (16-bit header). Case is planned by a separate two-state DP.
  The stream is **not self-terminating**: padding bits decode as TOP4 tokens, so every embedding
  carries the bit count. `encodeToBitLimit` fits text into a bit budget. The languages are not
  searched for: `main.dart` sets `MCOtxtCodec.defaultLanguagePair` from the resolved UI locale
  (`MCOtxtLanguagePair.forLocale` — that language and EN, or EN and RU for English; a UI language
  with no model becomes RU if Cyrillic, else EN), and the encoder plans once with that pair.
  Trying every available pair, the reference behaviour, runs only while the default is null,
  which is how the tests see the codec; explicit `MCOtxtEncodeOptions` languages win over both.
- **Frame** — `lib/MCOtxt/mcotxt_frame.dart`, `MCOtxtFrame`: `varuint(bitLength)` + bytes. The
  one agreed way to put a stream into a byte container; the app container uses it for every
  string, and a new byte container should call it rather than frame the stream its own way. A
  bit-packed host (MCOimg v4) keeps only the rule: bit count ahead of the bits.
- **Models** — `lib/MCOtxt/models/`: `MCOtxtLanguageModel` (primary ≤ 32 with SPACE at index 0,
  extension ≤ 32, `startTop4`, `punctStartTop4`, one TOP-4 row per symbol, uppercase map) and
  the shared 32-entry punctuation page. Seven language ids (en ru fr de it uk be), each with a
  generated table; a build lacking one would carry an `MCOtxtLanguageModel.unavailable`
  placeholder, which the decoder rejects with `modelUnavailable`. **Symbol order is wire format** (it defines literal ids), so
  tables are generated, never edited: `tools/MCOtxt/MCOtxt_model_trainer_with_diagnostics.py`
  writes `models/generated/v1/model_<lang>.dart`, a C header and a report, and records a SHA-256
  wire hash in `tools/MCOtxt/generated/model_manifest.json`; `verify_runtime_models.py` checks
  Dart, C and manifest agree; `freeze_model_manifest.py` froze the set as generation 0 on
  2026-09-04 (`"frozen": true`, all seven tables), so a table can now change only as a new
  generation. Tables
  live in `MCOtxtModelSet`s keyed by generation (`MCOtxtModelRegistry.latest` / `setFor`): a
  regenerated existing table is a new generation, a table added to a reserved language is not,
  and a header generation this build lacks decodes as `unsupportedModelGeneration` — except in
  RAW_UTF8, which needs no tables. Generations are numbered within a codec version; the manifest
  records the current one as `modelGeneration`.
- **Container and transports** — `lib/helpers/mcotxt_app_codec.dart`: flags (`0x01` reply,
  `0x02` embedded sender name, `0x04` timestamp inherited from the packet), optional u32
  timestamp, optional name, optional reply anchor, then the text; every string is a mode byte
  (`0` MCOtxt frame, `1` UTF-8) — names take the shorter, text is always `0`. Text transport is
  `mct:` + Base91 of `0x31` + body; binary channel transport is the `0x0120` envelope with an
  **empty** outer name and subtype byte `0x31`, the name travelling inside the body. A revision
  other than `1` is shown as a placeholder text rather than dropped.

The app names itself `MeshCoreOpen;cap=mctxt,mcmp,mcimg,aeic` in `CMD_APP_START`
(`buildMeshCoreOpenAppName`, with `frmfrg1` added to the comma-separated `cap=` list when framed packets are on). A South
Edition node reads those capabilities: without `mctxt`, and with its **MCOtxt conversion** setting on, the
node hands incoming MCOtxt to the app already decoded, in numbered `[i/n]` parts when long. The
app decodes for itself, so `mctxt` is always sent. `mcmp` signals generic MCMP support
without pinning the capability to a specific MCMP version. `aeic` signals AEIC image support.
The reverse also happens: a node whose
**MCOtxt coding** covers the channel (or `mcotxt.contacts` for a contact) re-encodes plain text
the app sends when that packet is smaller, as the same binary `0x0120` envelope this app uses in
channels and as `mct:` to contacts. The app is not told, and does not need to be: the node's echo
map puts the app's own plain GRP_TXT packet into `PUSH_CODE_LOG_RX_DATA`, payload type included,
so `ChannelEchoRecovery` and repeat counting keep matching what the app wrote.

Two rules that are easy to break. `DecodedMCOtxtAppMessage.senderName` is set **only** from a
name embedded in the body, as `DecodedMcmpAppMessage.senderName` is; the outer `Name: text`
layer is the message's `senderName`, never container metadata. And the container fills the same
`container*` model fields as MCMP v3 (see the signatures section), so anything that consumes a
reply anchor or timestamp works for both codecs without asking which one filled them.

### Unknown channel data packets from known namespaces

A GROUP_DATA `data_type` is a registered application namespace (MeshCore's
`docs/number_allocations.md`): `0x0120` is MCO Advanced, `0x0100` is MeshCore
Open. A packet from either that this build cannot read is kept rather than
dropped. After `tryDecodeInbound` and `tryDecodeAppData` both return null,
`ChannelBinaryDataHelper.tryDescribeUnknownAppData` describes the packet when
its data type is in `knownNamespaceOwners`: for `0x0120` it reads the outer
sender name, the subtype id and the version when the envelope parses (a
subtype this build does not know, an MCMP wire version it does not know, or a
payload that is not an envelope at all, which keeps only the namespace); for
`0x0100` it reads nothing, that layout belongs to MeshCore Open. The
connector's `_addUnknownAppDataMessage` then stores an ordinary channel message
whose text is the sentinel `mcoapp-unknown:0x0120:<subtype>.<version>` (or
`mcoapp-unknown:0x0100` with nothing to add) and whose `rawPayload` is the
whole payload, so a later build that knows the format has the bytes to decode
from history. The screens never print the sentinel:
`unknownAppDataPlaceholderText` (`widgets/unknown_app_data_placeholder.dart`)
turns it into a localized line naming the namespace with its owner
(`0x0120 MCO Advanced`) and, when known, subtype and version, in the bubble,
the reply quote, the reply banner and the channels list preview, in the italic
style the MCOimg unsupported-version placeholder uses (`_buildPlaceholderText`).
No notification is raised for it, the unread count is enough, and the RX-log
copy of such a packet is still ignored: the node hands every foreign packet
over as a frame as well, so nothing is lost there. MCOimg and MCOtxt report
their own unsupported versions before this point and keep their own texts;
the message search still shows the sentinel, since it runs in an isolate
without localization. Any other data type stays ignored, as before.

The transport, the namespace registry, the `0x0120` envelope grammar and the
receiver rules other implementations are expected to follow are specified in
[`docs/CHANNEL_APP_DATA.md`](docs/CHANNEL_APP_DATA.md) (Russian:
`docs/CHANNEL_APP_DATA_RU.md`). It is the common document of every binary
channel format: the MCMP, MCOtxt and MCOimg documents cover their own bodies
only and point there, so a change to the envelope or to the placeholder rules
goes into the common document, not into a codec's.

### MCMP v3 signatures (Ed25519, verified app-side)
The node signs canonical message bytes via `CMD_SIGN_START/DATA/FINISH` (single global sign buffer
→ serialize sessions). The canonical data contains the v3 signing domain, channel/room context,
the destination binding (HMAC-SHA256 derived from the channel PSK, or the room's full public key),
sender name, MCMP timestamp, wire flags, optional reply author/timestamp, and decoded message text.
The 64-byte Ed25519 signature is stored inside the MCMP body.

**Verification is done entirely in the app** (`helpers/mcmp_signature_verifier.dart`,
`cryptography` package) against known contacts; firmware never verifies. A normal channel body
keeps its sender name in the outer GROUP_TEXT or GROUP_DATA envelope, and an embedded channel name
is accepted only when it matches that displayed name. A room body embeds the signed name and the
room post supplies the original author's four-byte public-key prefix; verification resolves that
prefix to full contact keys and also requires the signed name to match the contact. Direct-contact
MCMP v3 messages are not Ed25519-signed and use the authenticated contact transport status.
The South Edition companion firmware reads the v3 header — flags, timestamp, embedded sender,
signature presence, reply anchor — without decompressing or verifying, to show a placeholder
with the sender on the node's display; the header must therefore stay parseable on its own,
ahead of the compressed text.

`McmpSignatureStatus`, the verbatim container metadata, the MCMP-only signature fields
(`mcmpIsSigned`, `mcmpSignature`), the verified full key and the name-collision flag are persisted
on `Message` / `ChannelMessage`. The container metadata is the four `container*` fields —
`containerTimestamp`, `containerSenderName`, `containerReplyAuthorName`,
`containerReplyTimestamp` — and they are deliberately shared by MCMP v3 and MCOtxt v1: both
codecs carry a timestamp, an optional embedded sender name and a reply anchor, and everything
that consumes an anchor (reply resolution, exact quotes, the clock-mismatch warning) reads these
fields without asking which codec filled them; `compressionType` already says that.
`containerSenderName` holds only a name embedded in the body (room posts, the binary channel
envelope): the channel text transport leaves the name in the outer `Name: text` layer, so both
codecs report `null` there. The stores write the `container*` JSON keys and still read the legacy
`mcmp*` keys, so history written before the rename needs no migration. The badge shows a
fingerprint only for `valid` results.
Incoming messages also compare the container timestamp with `message.timestamp` through
`helpers/mcmp_timestamp_warning.dart`: a difference greater than
`mcmpTimestampWarningThreshold` (30 minutes) adds the red clock indicator, while the details screen
shows the distinct container timestamp whenever the two second values differ. That helper detects a
clock mismatch and nothing more — it neither establishes freshness nor proves that a replay
occurred — and signature status and timestamp comparison stay separate UI fields.

The wire format itself — body layout, flags, both transports, the canonical signing bytes, the
destination bindings and the `CMD_SIGN_*` exchange — is specified in
[`docs/MCMP_V3_PROTOCOL.md`](docs/MCMP_V3_PROTOCOL.md) (Russian: `docs/MCMP_V3_PROTOCOL_RU.md`).
That document is written for other implementations, so keep it in step with the codec whenever the
container changes.

### Reactions
Emoji reactions ride the normal text channel as a compact `r:<4hex-targetHash>:<2hex-emojiIndex>` string (`helpers/reaction_helper.dart`) — no protocol extension. Target hash = `computeReactionHash(timestampSecs, senderName?, textPrefix)`; sender name omitted for 1:1. Processed in the connector's reactions region.

MeshCore One's reactions are read too (`HashType.mc1`, from upstream): `@[sender]emoji`, a newline and an eight-character Crockford base32 hash in a channel, the emoji, a newline and the hash in a direct chat, an older form putting the emoji before the name. The hash is the first five bytes of SHA-256 over the target's UTF-8 text and its timestamp as u32 LE, and the sender name is compared on its own. A reaction whose target is not found is dropped in our format and shown as an ordinary message in MeshCore One's; a channel reaction we send goes out as a reaction only when its target is found, as plain text otherwise. `parseReaction` sees every message, so it tries the `r:` fast path first and runs the two MC1 expressions only on text that ends in a newline and eight characters. The connector keeps its per-row saves (`saveMessage` / `saveChannelMessage` of the one message a reaction changed) where upstream rewrites the whole conversation.

### Channel message timeline

`ChannelMessage` deliberately carries three clocks. `timestamp` is the time shown in message
bubbles: incoming GROUP_TEXT takes it from the outer packet, while incoming MCMP GROUP_DATA uses
the MCMP body timestamp because that transport has no independent packet timestamp. Outgoing rows
are aligned to the first transmission attempt. `receivedAt` is the app-local timeline used by
history ordering, pagination, shared-history insertion and channel-list previews.
`sentByRadioAt` is the first outgoing transmission-attempt anchor. Central rules live in
`helpers/channel_message_timeline_helper.dart`; connector receive/dedup paths and
`ChannelMessageStore` must use that helper rather than sorting channel messages by `timestamp`.

Live incoming messages are stamped before asynchronous verification. Repeated incoming copies keep
the earliest physical receipt, which also repairs reversed async completion; self echoes preserve the
outgoing message's first `receivedAt` and `sentByRadioAt`. Outgoing time is assigned after the send
delay and radio-quiet wait, immediately before the transport write, and retries do not move it. This
is intentionally the first attempt time: a transport exception does not cause a later replay to
rewrite history.

The companion backlog frame has only the sender's packet timestamp. Firmware replays the queue FIFO,
so the initial post-connect drain assigns local monotonic `receivedAt` values in frame order (`now`,
or previous + one millisecond when the local clock did not advance). Legacy stored rows without
`receivedAt` fall back to `timestamp` because their real receive time cannot be reconstructed. When
shared history has the same packet in current and secondary scopes, the current-scope copy wins.

Room-server conversations use the same separation of clocks: `timestamp`, assigned by the room
server when it stores the post, is displayed in the bubble, while `receivedAt` controls stored order.
Initial queued room posts receive monotonic local
positions in companion FIFO order with a one-millisecond minimum step, and outgoing room posts are
positioned at their first transmission. Legacy rows without `receivedAt` fall back to `timestamp`.
The rules live in `helpers/room_message_timeline_helper.dart`.

### Direct and room message de-duplication

The node replays its offline queue on connect and can hand the same direct or room post over more
than once, so `_handleIncomingMessage` drops an incoming message that already sits in the
conversation. Identity is the packet timestamp in milliseconds plus the exact text, and the scan
covers the whole loaded conversation rather than only its last entry — a duplicate need not arrive
adjacent to its twin, since other senders' posts can be interleaved between the two copies.

For a room server that pair is not enough: two participants can post identical text in the same
second, and collapsing them would delete somebody's message. When the contact is `advTypeRoom` the
comparison therefore also requires an equal `fourByteRoomContactKey`, the author prefix the room
server stamps on every post. Only incoming messages are considered, and the check runs before the
message is stored, so nothing has to be undone afterwards.

### Notifications and the node's queue

`CMD_SYNC_NEXT_MESSAGE` is destructive: the node drops the message it hands
over, so `_processPotentialQueuedMessage` sends the next request only after
the delivered message is parsed, verified and written to the history. That
order is the iOS sync fix (`806c51fe`): iOS kept the BLE link while the
process was not really running, and the app had advanced the queue before
the write. The notification for the message is enqueued in the same place
and shown in the background (`_showNotificationInBackground`). The `await`
on the plugin came from upstream's translated notifications, when the queue
still advanced first; after the fix it held the queue for `_ensureCanNotify`,
the MCOimg render with its file, the URL-image download under its
five-second ceiling and the plugin's `show`, up to five seconds per live
message with a picture. The call still runs up to its first await before the
next request goes out, so the service's rate limiter sees the messages in
order, and the gates (the settings, a blocked sender, a muted channel, the
initial-drain summary) are decided on the receive path as before; only the
showing moved. An error from the plugin is logged, where an error inside
`process()` stops the queue sync. The MCOimg picture of a notification is a
file only where something reads one: Apple's attachment, which the system
moves into its own store when the notification is scheduled, and the Windows
toast; Android and Linux take the bytes. The next MCOimg notification
deletes the files older than `_notificationImageLifetime` (24 hours), since a
toast can be shown again from the action centre well after `show`
(`test/connector/queued_message_notifications_test.dart`).

### Channel messages under our own name

An incoming channel message whose sender is this node's own name is **not**
filtered. Upstream drops one whose frame carries no path bytes
(`_shouldDropSelfChannelMessage`, written to catch our own echo heard directly),
but companion firmware never puts path bytes into a channel frame, so the rule
dropped every message under our name: a reply from a node-side TerminalCLI, a
message typed on the node's own keyboard, a second node carrying the same name.
The duplicate it was written for is handled elsewhere, `_isChannelRepeat` merging
an incoming copy of our own text into the outgoing message as a repeat, so the
rule is gone from all three receive paths: channel frames, channel-data frames
and the raw RX log, where the packet does carry its path and the rule could only
hide a same-named node heard directly. The
`doNotFilterMessagesOnChannels` setting keeps its key and its per-channel list
but now means one thing only: messages to the listed channels skip the
acknowledgement wait and the retries. A V3 frame's raw path byte `0xFF` is read
as `pathLength == -1`, no path, as the v1 frame and the channel-data frame
already read it; unpacked as hash width and hop count it claimed 63 hops. The
channel-data frame carries the same packed byte, and
`parseChannelDataReceivedFrame` unpacks it the same way into `pathLength` and
`pathHashWidth`; stored raw, as it once was, a five-hop packet under two-byte
hashes read as 69 hops whenever no RX-log route arrived to override it.

This is also what lets a message typed on a South Edition node's own keyboard
reach this app: the node puts a copy into the app queue under its own name with
path byte `0xFF`, exactly the shape the rule dropped. When merging from the
upstream `meshcore_open` branch, expect `_shouldDropSelfChannelMessage` and its
call sites to come back in the conflict and drop them again; the removal is
deliberate, not an oversight.

### Channel sender name

A channel can send under a name of its own instead of the node's: the
*Sender* line of the channel header (`widgets/channel_sender_name_line.dart`,
the dialog in `channel_sender_name_dialog.dart`, since 2026-10-14), tappable
on its own text while the rest of the header keeps opening the region dialog,
*default* for the node's name. The setting lives in `channel_settings_store`
(`channel_sender_name_`, `loadSenderName` / `saveSenderName`), keyed by name
and inherited from the owner's other nodes like every channel setting, with
one twist: a cleared name is stored as the empty string, never removed,
because a missing value reads through to the other nodes and a name cleared
here has to shadow theirs. The connector mirrors it in `_channelSenderNames`;
`channelSenderName` is the stored alias, `channelSenderNameInEffect` the one
a send takes, `channelSendName` what a message goes out under, and outgoing
messages store that name in `senderName`, which is what the self-echo rule of
`_isChannelRepeat`, reactions to our message, replies naming us, the
heard-packet record and the "own node" quote styling read; `_channelMessageMentionsSelf`
and `isChannelSenderNameOurs` match the alias beside the node name.

Three locks, in `helpers/channel_sender_name.dart` (`resolveChannelSenderNameLock`),
each shown as a snackbar when the line is tapped. **Signed MCMP** (MCMP on,
v3, sign): receivers verify the signature against the contact bearing the
sender name, so switching signing on drops the alias for good
(`_dropChannelSenderNameForSigning`, from the three MCMP setters; the edit
sheet warns under the sign dropdown), and the owner's decision is that the
alias and a signature never coexist. **Firmware**: a plain packet under the
alias needs `CMD_SEND_RAW_PACKET`, guaranteed from version code 13
(`supportsRawPacketSend`; it arrived at 12, on 2026-05-13, so 12 is not
trusted). **A private `$` region** as the channel's effective scope: its key
is on the repeater, so the app cannot compute the transport code. In this app
a channel cannot be given such a region (the region screen allows
`[a-z0-9-]`, fetched lists and links drop `$` names); only the node's default
scope, set outside the app, can be one. Nothing falls back at send time: a
stored alias under a lock is simply not in effect and the line says *default*.

**The wire.** The node's command carries only the text and the companion
puts `_prefs.node_name` in front of it (`BaseChatMesh::sendGroupMessage`),
so under an alias the app builds the GRP_TXT packet itself
(`helpers/channel_raw_packet.dart`, `ChannelRawPacket`; the connector's
`_channelTextFrame` decides between the two at the five text sends: the
message, its resends, the ack-and-retry bypass, the deferred send and
reactions) and sends it through `CMD_SEND_RAW_PACKET`, exactly as the
firmware would have built it: the flood header, the transport code of the
region, the node's default scope included, computed in the app
(`regionTransportCode`, now the one implementation behind
`_computeRegionTransportCode`), the path byte with the node's hash width, the
channel hash byte and the MAC and ciphertext of `timestamp + type +
"Name: text"` (`ChannelEchoRecovery.groupTextPlaintext` /
`encryptedPayloadFor`). The binary envelopes (MCMP v3 unsigned, MCOtxt,
MCOimg) carry the name in the body the app writes, so there the alias is
only substituted. `_handleOk` and `_handleErrorFrame` take the OK or ERR of
a raw packet with a queue id as a channel send's. Three things the firmware
does for its own packets the app does here: the echo registry is fed with
the plaintext directly (`_sendFrameDirect` reads only the node's command),
the heard-packet record keys on the message's own name, and the dedupe mark
is missing altogether: `Mesh::sendFlood` marks, the `CMD_SEND_RAW_PACKET`
handler calls `sendPacket` straight, so the first relayed copy comes back
from the node as an incoming message under the alias (and on a node with a
display shows there as one) and is folded into our own message as any copy
of it is. The raw frame has its own header to fit into the 176-byte
companion frame, so it carries 160 bytes of plaintext where the node's
command carries 165: `maxChannelTextBytes` takes five bytes off the channel's
text budget while an alias is in effect (`ChannelRawPacket.maxGroupTextBytes`,
155 bytes of `"Name: text"`), and the composer limiter, the send-path length
guards, the plain-when-smaller costing, the notification reply split and the
map's marker label budget (the tightest over the channels a pin may go to)
read it. The node's own transforms of plain text (the South Edition's cyr2lat
and MCOtxt re-encoding) never see a raw packet
(`test/helpers/channel_raw_packet_test.dart`, `channel_sender_name_test.dart`,
`test/widgets/channel_sender_name_line_test.dart`,
`channel_sender_name_dialog_test.dart`,
`test/storage/channel_settings_inheritance_test.dart`).

The *(radio default)* suffix of the region line went from the channel header
and the channels list the same day: the line reads *Region: name* whether the
region is the channel's own or the node's default scope.

### Blocked senders

A sender muted from a message's long-press menu keeps arriving — nothing is dropped on receipt or
removed from history — but their messages are neither shown nor acted on. It covers **channel
posts and room-server posts**; a one-to-one conversation has nothing to mute, being the contact
itself, which is deleted instead. The behaviour lives in two files:
`storage/blocked_sender_store.dart` (rules and JSON) and `helpers/blocked_senders.dart`
(`BlockedSenders.instance`, a singleton rather than a provider because the connector consults it
while parsing a frame). Two widgets carry the UI — `blocked_message_body.dart` for the
placeholder and `blocked_senders_sheet.dart` for the list.

**The table** is one app-wide JSON blob, **not** scoped by node public key like most stores here:
a sender worth muting is worth muting from every radio this phone connects to. A row's key is the
identity the mute is aimed at — a channel sender's name, or a room author's 4-byte public-key
prefix as uppercase hex. Rooms are keyed by the prefix because it is the stronger identity of the
two: a channel post carries whatever name its author typed, while the prefix is stamped on every
post by the room server itself, so a participant cannot wear somebody else's. The two key spaces
share one map and could in principle collide, on a channel sender literally named `AB12CD34`;
blocking one would then block the other, and that is the whole cost of not keeping a second
table.

A row carries three things.

- **`keyHex`** — the full public key behind a verified MCMP v3 signature, and an *exemption, not
  a requirement*. The row mutes the identity it is keyed by, and the only message it lets through
  is one that provably verified to a **different** key. That is the reasoning blocking itself
  follows — an unsigned message proves nothing about who sent it — applied to the arriving side.
  Requiring the key instead would let a muted sender walk out of the rule by not signing and,
  worse, by being deleted from contacts: with nobody left bearing that name a signature verifies
  as `unverifiable`, which reports no key at all, and muting somebody then removing them from
  contacts is the natural pair of actions. Never read `verifiedSenderKeyHex` without
  `mcmpSignatureStatus == valid` — `verifiedKeyOf` and `verifiedRoomKeyOf` are the only places
  that pairing is made.
- **`channels`** — always `["*"]` today; it exists so a per-channel block can be added later
  without migrating stored rules. Note that names are matched as the caller spells them, so the
  day a row stops being a wildcard, callers have to agree on what an unnamed channel is called;
  `MeshCoreConnector.channelDisplayName` is that one answer.
- **`blockedAt`** — where the rule starts, and it only ever travels backwards.

**The moment a rule starts at** is the message it was ordered from, not the tap: by the time
somebody long-presses a post, that sender has usually put several more on the screen above it,
and those are what the user is reacting to. It is clamped to now because `receivedAt` is our own
clock: live channel messages are stamped on first physical receipt, while the post-connect
backlog receives local monotonic times in the firmware's FIFO replay order. The sender-controlled
packet `timestamp` is stored separately and cannot push the boundary into the future. Blocking an
identity again takes the **earlier** of the stored moment and the new anchor (`_blockedAtFor`):
pointing further back strengthens the rule, pointing forward must not weaken it. A row written
before blocks carried a moment is stamped with the load time and written straight back, so the
stamp is decided once instead of drifting with every launch; the epoch would be the wrong default
there, since the date arm would then reach over the whole conversation and hide everything that
sender ever wrote.

Re-blocking never narrows the identity either: a second, different key under one row widens it to
the bare identity, the most a single-key record can express, and a row that already has no key
stays that way. Narrowing is a deliberate act, done by deleting the row and blocking again.
Because a re-block can still move `blockedAt` backwards, `block` bails out only when neither the
key nor the moment would change.

**Two questions, and the difference is only which clock the moment is compared against.**

- `isSenderBlocked` / `isRoomAuthorBlocked` — *is this sender muted right now?* — is the
  receive-time question, asked by `_addChannelMessage` and `_handleIncomingMessage`, and it
  compares no dates at all. A row that exists was created in the past, so a message arriving now
  is always after it; comparing our clock with our clock would add nothing and would misfire if
  the device clock stepped backwards. The answer is stamped onto the message as `wasBlocked`, and
  that flag keeps the receive-time decision independent from packet time. The backlog drain is
  covered too: its
  `receivedAt` is assigned locally before the message reaches this check, and its wire timestamp
  remains metadata only.
- `hidesStoredMessage` — *should this stored message be hidden?* — is the display-time question,
  and it does compare: `ChannelMessage.receivedAt` at or after `blockedAt`. It exists for messages
  the receive path never stamped, above all copies merged in from another node's shared history,
  which that node stored without ever seeing our rules. The packet's own `timestamp` is never
  consulted — the sender chooses it, and the moment of blocking is known only to us.

Everything that draws or interprets a channel message asks both and hides on either. Room posts
use the stamped `wasBlocked` flag; their `receivedAt` is the local conversation position rather
than sender-controlled packet metadata.

**Reaching the history already on screen.** `markChannelMessageBlocked` and
`markContactMessageBlocked` walk the loaded conversation from the newest message backwards and
stop at the one the block was ordered from, flagging what they pass. That costs only what the
user actually saw, never the whole conversation, and everything older than the anchor is left
alone — a block does not rewrite history the reader had already gone past. The anchor itself is
flagged whatever the rule says, since the user pointed at it; the messages above it only if the
rule really covers them, so a namesake exempted by a verified key stays visible. Both write to
the node's own store and to any shared scope holding the same message id, for the same reason
`_deleteSharedChannelMessage` does — flagging only the local copy lets the next merge uncover the
unflagged twin.

`applyBlockedSenderRules` is the other writer: it stamps the flag onto every loaded channel
message the date arm hides and saves the channels that changed. It runs on every change to the
table and once after a channel's history is read from storage, which is what makes that answer
permanent — lifting the block does not bring those messages, or the commands they carry, back.
Only this node's own store is swept; a copy merged in from another node is hidden by the
display-time check instead of being rewritten, since the flag it wants is the answer *our* rules
give, which is exactly what the check computes on the fly.

**Outgoing messages are never blocked.** `ruleFor` and `roomRuleFor` refuse them on their first
line, and the menu entry exists only for incoming messages. Without that, somebody adopting the
user's own callsign — which a channel post allows, the name being whatever its author typed —
could get him to mute himself. Any new display site must go through the helper rather than
inlining a lookup of its own, or it loses the guard.

**What the flag reaches.** Both chat screens compute `bodyText` once — the message text, or an
empty string when hidden — and every parser below reads that, so a hidden body produces no pin,
image, shared contact, coordinate link or quote. The placeholder takes the whole body and a tap
reveals the stored text, but revealing is a display choice: `bodyText` stays empty, so a revealed
marker still puts nothing on the map, and the revealed set is dropped whenever the table changes.
`_collectSharedMarkers` skips hidden messages **before** `SharedMarkerDeletions.absorb`, in the
contact loop as well as the channel one, or a muted troll's `del:` commands would still erase
everyone else's pins. The channels list shows the placeholder instead of the last-message
preview. Notifications and unread counts are gated on the rule directly at receive time: a
notification would put the hidden text straight back on screen, and a badge fed by a muted
flooder never stops climbing and reaches the OS app icon through `getTotalUnreadCount`. Reactions
are decided by the rule too and dropped in `_addChannelMessage` — a reaction has no body to hide,
lands in a `Map<emoji,count>` carrying no author, and is never stored, so there would be nothing
to re-evaluate later.

`wasBlocked` is persisted by `channel_message_store` and `message_store` and defaults to `false`
for older records. Repeats merge through `existing.copyWith(...)` without touching it, so the
first arrival decides. It also rides in `markerSignature`, next to `BlockedSenders.revision`:
flagging a message changes nothing else about it, and the map's marker cache would otherwise keep
drawing its pin. Revealing or hiding a body changes bubble heights, and without a guard the
post-frame snap that follows every list rebuild drags a reader sitting near the bottom down to the
newest message. Two guards cover that, for the two shapes the change takes. `_toggleBlockedBody`
is synchronous and sets `_channelSkipNextBottomSnap`, which the next snap consumes and clears.
`_toggleSenderBlock` and `_toggleRoomAuthorBlock` are not: blocking rewrites stored history and
the connector notifies more than once along the way, so both run their work inside
`ChatBottomSnapGuard.run` (`helpers/chat_scroll_controller.dart`), which holds the suppression
until the end of the frame that applies the final heights. Its generation counter is what keeps a
second toggle started mid-flight from letting the first one lift the guard early.

**Redrawing.** `BlockedSenders` is a `ChangeNotifier` and bumps `revision` on every write; the
connector re-emits that signal, so the chat, the channels list and the map redraw from the one
hook all three already watch. `revision` is a value rather than a bare notification because the
map's pin list is cached against a signature — a redraw alone would serve the cache.

**Unblocking** removes the row and clears no flags, the anchor's included. What arrived during a
block stays hidden for good; what arrives after the row is gone is shown and acted on as normal.

**The list.** `BlockedSendersSheet` opens from two overflow menus — inside a channel, below
`channels_editChannel`, and on the channels screen, below `chat_searchMessages`. It reads and
writes `BlockedSenders.instance` straight, since the table is app-wide and synchronous — nothing
is passed in and nothing handed back, which is what makes a second entry point free. Neither is
gated on offline mode, the list being local data. The channels screen hangs its handlers off
`PopupMenuItem.onTap`, which runs after the menu route has popped, so the sheet is opened from
the screen's context and `menuContext` is only used for the label.

Its **Add** dialog takes a name and nothing else, so `blockName` writes the widest row a name can
carry — no key, `["*"]` — which replaces a keyed row and, having no message to point at, cannot
move an existing moment backwards either. The dialog's controller is a `State` field because
`showDialog` completes on pop, while the dialog is still animating out and still reading it.

**Quotes of a hidden message.** A reply carries a snapshot of what it answers, taken when the
reply arrived, so a muted sender's words used to come back on screen through somebody else's quote.
`hidesQuotedMessage` is the question that keeps them off it, asked by `_buildReplyPreview`, the
one place a channel draws a quote. A room chat draws its quotes with `ReplyQuoteBox` and can ask
less: a room block is keyed by the author's key prefix, which a quote does not carry, so there a
quote is hidden only while its original is loaded and flagged `wasBlocked`. The original is taken
from the list the transcript itself is built from, `MeshCoreConnector.getChannelMergedMessages`:
the timeline cache's unfiltered merge of own and shared history, a new object only when the
timeline is rebuilt, which `ReplyTargetIndex` (`helpers/reply_target_index.dart`) indexes by id
once per object. Before, every reply bubble merged own and shared history anew
(`getChannelMessages`) on every rebuild of the transcript, 0.5 to 4 ms a bubble with a large
shared history, on every relay heard while typing. A quote of our own message skips the lookup,
since the rule refuses it on its first line.

It answers from the original message when that is still in the loaded conversation, so the quote
mirrors the bubble a few rows up: nothing is hidden here that stays readable there, and nothing
stays readable here that was hidden there. With the original out of memory only the name is left,
and a name under a rule is hidden — a quote is text arriving now, not history the reader already
scrolled past, so the `blockedAt` boundary that spares old messages does not apply to it. Our own
name is refused on the first line, as `ruleFor` refuses outgoing messages.

Hiding runs through the same funnel as a bubble body: the local `replyText` becomes empty, so the
gif, marker and AEIC parsers below it see nothing and a hidden quote can no more draw an image or
a pin than a hidden message can. The author line stays — the block hides what was said, not that a
reply happened — and so does the tap, which scrolls to the quoted message as before.
`BlockedQuoteBody` (`widgets/blocked_message_body.dart`) draws the placeholder without
`BlockedMessageBody`'s reveal-on-tap, because that tap belongs to the preview.

**Not covered, deliberately**: one-to-one conversations, where the contact is deleted rather than
muted; the message search, which runs in a real isolate the table cannot be reached from; and
AEIC images, which never become a message object and carry no author name at all.

### Mentions
`@[name]` is the wire form for naming someone — replies have always used it, and it is typed directly too. Both ends live outside the screens: `helpers/mention_autocomplete.dart` for composing, `MentionText.split` (same file) for rendering.

**Composing.** `queryAt` reads the mention under the caret: it walks back to an `@`, bailing on whitespace or a bracket, and requires the `@` to open a word. `suggestionsFor` then matches the typed fragment against `MeshCoreConnector.allContacts` — the node's own contacts plus the app's discovery cache, so somebody heard advertising can be addressed before being added to the radio — and sorts alphabetically. Wired into the channel composer and — via a `type == advTypeRoom` check — the room-server one; a one-to-one chat has nobody to disambiguate. Picking inserts `@[name]` followed by a space and leaves the caret past it, ready for the next word; the space is skipped when the text already continues with whitespace, so a mention picked mid-sentence does not leave a double one, and either way the caret ends up after exactly one whitespace character. That also closes the panel — `queryAt` walks back from the caret and stops at whitespace — as the closing bracket alone already did.

The search is debounced by `MentionSearchDebounce` (750 ms, same file): it runs from a bare `TextEditingController` listener, which fires on every value change — selection included, so an Android selection drag notifies continuously — and it walks a discovery cache of up to 500 entries. **Only the search waits, and only while a name is being typed.** `schedule` sends an empty filter — the bare `@`, with nothing filtered yet — straight through, so the trigger character brings the full list up at once; the delay starts with the first letter after it. `_mentionQuery`, the range a pick replaces, is assigned before anything else and tracks the caret on every keystroke, and an ended mention cancels the timer and clears the list on the spot: a panel lingering after the user typed a space, or a replacement range pointing at text already moved past, would be wrong rather than merely late. While the timer runs the previous list stays on screen, and picking from it still replaces the current range, which is what makes a stale row harmless. Picking also closes the panel immediately — the inserted `@[name]` ends in a bracket, so `queryAt` returns null on the very next notification.

Two filters shape that list, and both matter more than they look. A name is offered **once**: the two sets overlap, a mention carries nothing but a name, and duplicate rows would be visually identical with nothing to choose between them. The first occurrence wins, which keeps a real contact ahead of a discovery entry and — because the screens compare suggestion lists by public key — keeps the surviving row the same one on every rebuild; an unstable pick would rebuild the picker under the user's finger. `excludeKeyHex` then drops this node itself, which `allContacts` filters out of the discovery half but not out of the node's own contacts. Names are compared trimmed and case-insensitively, which also leaves the sort with no ties to break.

Two non-obvious bits in `widgets/mention_suggestions_panel.dart` and its callers. Rows fire on `onPointerDown`, not `onTap`: touching the panel pulls focus out of the composer, the focus listener hides the panel, and a pending tap would be cancelled with it. And the `MentionQuery` is kept in screen state rather than recomputed on selection — by the time a row is picked the caret may already be gone.

**Rendering.** `MentionText.split` cuts message text into plain and mention runs; `widgets/mention_chip.dart` draws the chip in either the bordered or the plain look, per `AppSettings.simplifiedMentions`. This happens for every `@[name]` in the body, regardless of that setting and of `incomingQuoteAsMentions` — those two only govern the *reply* chip. Tapping an inline mention opens the contacts list filtered by that name (`ContactsScreen.openWithSearch`), while the reply chip scrolls to the quoted message: same look, deliberately different destinations.

### Exact quotes (plain-text replies)
Plain-text replies carry only `@[sender]`, which the receiver resolves to that sender's *newest* message. `helpers/exact_quote_helper.dart` adds a quote fragment so the reply anchors to the message it was actually written for. Wire form is `@[sender] >fragment\ntext`; the whole mechanism (both directions) lives in that one file, exposed as `formatReply` / `resolveReply` — everything else is call sites.

**Outbound** (`_applyReplyMention` → `_formatReply` in `channel_chat_screen.dart`; direct and room chats have their own, see below). Budget is `AppSettings.exactQuoteLimit` (3–100, default 30) counted in **wire bytes**: the fragment is cut from the readable original, but each character is weighed after cyr2lat substitution, using the table `MeshCoreConnector.channelCyr2LatCharMap()` returns for that channel. Trailing `[\s.+,-]` is trimmed (a question mark is deliberately kept) and an ellipsis is appended only when the fragment is shorter than its source. No fragment is spent when the toggle is off, or when `MeshCoreConnector.channelReplyCarriesContainerAnchor()` is true — MCMP v3 and MCOtxt v1 already ship an exact author+timestamp anchor. A reply to the sender's newest message spends one under `AppSettings.exactQuoteLatest` (the second toggle under the first, default on since 2026-10-08): a bare mention resolves to the newest message the *receiver* holds from that author, which is the sender's only while nobody posted in between and nothing was missed, and the owner preferred the bytes to the guess. With it off the helper reads the history to tell the newest message apart, so the four callers hand it the history only then (`fragmentForLatest` on `ExactQuoteHelper.formatReply` / `formatReplyWith`); on, the history is not merged at all (`test/helpers/exact_quote_helper_test.dart`, `exact_quote_history_test.dart`).

**Trimming the quote by hand.** The composer puts the reply's mention and quote line into the text field itself (`_plainReplyComposerPrefix`), so a quote can be shortened there to save payload. The reply banner stays above the composer in that case too (since 2026-10-13), for its close button and the region chip, so the quote shows twice, in the banner's preview and in the field. `ExactQuoteHelper.composerReply` decides what an edit leaves: a quote line that still quotes the start of the message, whatever was deleted from its end, keeps the reply: the send passes its fragment to `formatReply` as `quoteFragment` instead of cutting a new one, while the byte counter puts the `wirePrefix` `composerReply` returns in front of the draft and reads no history, because `getChannelMessages` and `getMessages` merge shared history anew on every call and the counter runs on every keystroke. For the same reason the screens' `_formatReply` reads history only when a fragment can be due, which a channel with a container anchor never has. Touching the mention or rewriting the line drops the reply, as any edit once did. Both chat screens compared the text with the inserted prefix byte for byte, so trimming a single character sent the edited line as plain text with no reply behind it. The fragment goes out canonical (`_canonicalFragment`): a partly deleted ellipsis and trailing punctuation come off and a whole ellipsis goes back on while the fragment stops short of the message, because receivers strip only a whole one before matching. A manual retry of a direct message cuts the budget's fragment again, the trimmed one not being stored.

**Inbound** (`_addChannelMessage`). Three predicates in the helper own the policy, so the connector and the chat screen cannot drift apart on it. `parsesFragment` refuses outright when `containerReplyTimestamp != null`: an MCMP or MCOtxt body never carries a fragment — it has an author+timestamp anchor and needs none — so a leading `>` line there is the author's own writing and stays in the message as ordinary text. Otherwise the fragment is parsed, except when replies are drawn as mentions *and* `AppSettings.exactQuote` is off. It is then cut off the body and matched backwards through history against messages from that author: prefix match first, then the candidate re-encoded through `extendedCharMap` → `defaultCharMap` → `transliterationCharMap` → the user's own cyr2lat profiles. Encoding the candidate rather than decoding the fragment is deliberate — several Cyrillic letters share one Latin look-alike, so the reverse is ambiguous. `stripsFragment` decides whether the line actually leaves the stored body, and it only does when something will display it back: with no bubble in front of the message and nothing matched, removing it would swallow the only excerpt the sender paid payload for.

**Quote or mention** (`rendersAsQuote`, read by `channel_chat_screen.dart`). `AppSettings.incomingQuoteAsMentions` draws an incoming reply as a plain mention chip instead of a quote bubble, because a bare `@[sender]` resolves to that sender's *newest* message and a bubble around a guess claims more than the message actually says. A reply that named its target keeps the bubble. Two anchors qualify and both require a message that was really found: a container anchor (MCMP v3 or MCOtxt v1) — `containerReplyTimestamp` together with the `replyToMessageId` it resolved to — and `ChannelMessage.replyIsExact`, set on receipt when the text fragment matched. An anchor that resolved to nothing falls back to the mention, since there is no message to show inside the bubble and none to scroll to. The two are governed separately: a container anchor rides inside the compressed body, costs no payload and is never something the author typed, so it always counts, while the fragment is the feature `exactQuote` switches on and off — consulted once at receipt rather than a second time at display.

`replyIsExact` is persisted by `channel_message_store` and defaults to `false` for older records, which leaves them rendering the way they already did. It exists because a resolved fragment and the `_findMessageBySender` guess both leave a non-null `replyToMessageId`, so nothing else tells them apart afterwards. A container anchor needs no flag of its own — `containerReplyTimestamp` already says which kind of anchor the message carries — which is also why the places that attach an MCMP or MCOtxt anchor to a channel message were left untouched.

Both sides normalise identically before cutting or comparing: leading scaffolding (a quote line or a mention the quoted message itself began with) is stripped, whitespace collapsed, ends trimmed. A miss stores the received fragment as `replyToText` with no `replyToMessageId`, so the quote stays visible but untappable; `_findReplyFallbackMessageId` in the screen may still resolve it later by substring after older messages load. Parsing happens once on receipt and the processed text is what gets persisted — toggling the settings does not replay old messages.

**Quoting our own messages.** A reply may target one of our own channel messages exactly as it targets anyone else's: the long-press menu always offered it, and on mobile the reply swipe now takes our own bubbles too (`_SwipeReplyBubble` keeps them at the inset they had without it, and their hint shows the icon alone, the only part the sliding bubble uncovers). Nothing downstream tells the two apart. The mention names us, under the name the message went out with, the fragment follows `exactQuote`, and MCMP v3 or MCOtxt carry their author-and-timestamp anchor instead. Two details keep that anchor equal to what the receivers hold. Our message learns its packet time only as it goes on the air (`_updateChannelMessagePacketTimestamp`), so `_sendMessage` reads the target back from the connector (`_currentCopyOf`) rather than from the snapshot the reply started with, which a quick answer can predate. And an MCOtxt text packet carries no timestamp of its own, its receivers giving the container the packet's, so the same alignment writes the packet time into our copy's `containerTimestamp` as well (`MCOtxtAppCodec.inheritsPacketTimestamp`). That field used to keep the moment the send began, up to a radio-quiet wait earlier, and an anchor taken from it missed on every receiver whenever the two fell in different seconds; messages stored before the fix keep the old value.

### Replies in direct and room chats

A direct or room message can be answered as a channel message can, under the same four settings
(`exactQuote`, `exactQuoteLatest`, `exactQuoteLimit`, `incomingQuoteAsMentions`) and in the same wire form:
`@[author]`, then a quote line while `exactQuote` is on and no container anchor carries the reply,
and MCMP v3 or MCOtxt send their anchor, with an empty author in a direct chat, which resolves by
timestamp alone as `docs/MCOTXT_V1_PROTOCOL.md` specifies, and the author's name in a room.
Upstream has no replies there, so the pieces are the fork's own:
`widgets/swipe_reply_bubble.dart`, a copy of the channel screen's private `_SwipeReplyBubble`
that came from upstream, and `widgets/reply_quote_box.dart`, holding the quote in the bubble, the
banner above the composer and the reply drawn as a mention.

These messages carry no author, so `MeshCoreConnector.contactMessageAuthorName` names one for
both ends of the mechanism: the name a room post embeds in its container, us for our own
messages, the node a room post's key prefix points at, saved or only discovered, and the contact
itself in a direct chat.
`ExactQuoteHelper.formatReplyWith` / `resolveReplyWith` take that as an accessor, and the channel
entry points are wrappers over them. A room post whose author is unknown cannot be answered, there
being no name to mention: the menu offers no reply and the swipe lets it go.

On the way out the screen writes the reply as the channel composer does, the quote line shown in
the composer or the banner above it, and `_composerEncoder` counts the mention, quote line or
anchor. `sendMessage` and `scheduleContactMessage` take the reply reference, and
`prepareContactOutboundText(Async)` puts the anchor into the container; its MCOtxt "plain when
smaller" candidate gets the quote line back (`_contactPlainAlternative`), as a channel's does.
The stored message keeps only the body (`_contactReplyBody`): the wire text stays in `rawText` and
in the retry service's prepared text, which is what goes out and what the ACK hash covers. A
manual retry writes the mention and the quote line anew from the stored reference. `sendMessage`
also reads the message's time once, before the MCOtxt meta, so an inherited container timestamp
equals the packet's and an anchor on our own MCOtxt message does not miss by a second.

On the way in `_resolveContactTextReply` follows `_resolveContactReplyReference`, which resolved
any container anchor, and does what `_addChannelMessage` does for a channel: the mention comes off
the body, a quote line goes through the same `parsesFragment` / `stripsFragment` rules, a bare
mention falls back to the author's newest message, and an anchor that resolved to nothing stays a
name. A direct chat has two ends, so there only a mention of one of them is a reply; a message
that starts with anybody else's mention is left as it came. `Message.replyIsExact` is persisted
by `message_store` and defaults to `false`.

### Inline text markup
Chat-style formatting parsed by `helpers/message_markup.dart`: `**bold**`, `__italic__`, `_underline_`, `~~strike~~`, a monospace block fenced by triple backticks, and colour tags like `[r]red[/r]`. `parse()` returns styled runs and drops the markers; `parse(keepMarkers: true)` keeps them as their own segments, which the composer needs so caret offsets still line up with the raw text.

Colour is the second axis: ten tags — `[r]` `[g]` `[b]` `[y]` `[o]` `[lb]` `[p]` `[w]` `[bk]` `[gr]` — each closed by `[/key]`. Note `[b]` is **blue** and black is `[bk]` — the original spec used `[b]` for both, and blue won because it came first. Keys live in `MessageMarkup.colorKeys` (longest first, so `[b]` cannot shadow `[bk]`) while the pigments live in `MarkupPalette` (`theme/mesh_theme.dart`) — parser owns the syntax, theme owns the colour. `MarkupStyles.color` carries the innermost key, so nesting replaces rather than blends.

Rules that matter when touching it: a span only opens when its closer exists later (so a lone `*` or an unclosed `[r]` stays literal), markers built from `_` refuse to open inside a word (snake_case, URLs), a monospace block is literal all the way to its closer, and spans may cross line breaks. Only the ten known colour keys are markup, which is what keeps `@[name]` mentions out of the parser's way. `has()` short-circuits on a codeunit scan for `*_~[` and backtick before parsing, because message lists render mostly plain text.

Three call sites. **Rendering**: `widgets/formatted_message_text.dart` treats markup as the outer layer and resolves mentions and links inside each run, so a bold sentence keeps its mention chip and tappable URL; that widget is reached from `TranslatedMessageContent`, which falls back to plain `Linkify` when neither markup nor a mention is present. **Composing**: `widgets/markup_text_editing_controller.dart` overrides `buildTextSpan` to dim the markers and style the run between them — characters are never hidden, since a Flutter field cannot hide them without the caret drifting, and that visibility is what makes deleting a marker an obvious way to strip formatting. **Toolbar and keyboard**: `ByteCountedTextField.contextMenuBuilder` appends five wrap actions plus a **Text colour** entry (`chat_format*` keys) that opens `showMarkupColorPicker` (`widgets/markup_color_picker.dart`) — ten swatches are too many for the toolbar itself. `_formattingShortcuts` binds the same wraps to Ctrl/⌘ combos on desktop only; macOS swaps in `⌘⇧U` for underline and `⌘⇧K` for monospace, and has no clear-formatting combo. Colours have no shortcuts.

The edits themselves are pure transforms in `helpers/markup_editing.dart` (`wrap`, `stripFormatting`), shared by all three entry points so they cannot drift apart; each caller applies the UTF-8 limiter afterwards, so a tag can never push a message past the payload budget. Wrapping an empty selection leaves the caret between a fresh pair. `stripFormatting` removes markers inside the selection or, failing that, the pair immediately around it — colour tags included, via `_surroundingPairs`.

A reader can switch one message back to the text as typed: the bubble's action menu offers **Show without Markdown** for any message `MessageMarkup.has` (after the copy-path entries in a channel, after Copy in a direct or room chat), and **Show with Markdown** on a message already switched. Both chat screens keep the choice in a session set of message ids (`_rawMarkupMessageIds`, toggled by `_toggleMessageMarkup`) and hand it down as `markupEnabled` on `TranslatedMessageContent` and `FormattedMessageText`, which then renders the whole body as one unstyled run while still resolving mentions, links and coordinates. Nothing is stored: leaving the chat restores the formatted view. The flag is part of the span cache key, or the toggle would not redraw.

### Last-hop signal in the hop list

The tracing row of a channel bubble ends its hop list with the SNR and RSSI our own radio measured
for that reception, and the packet-path screen repeats them under every route it lists.

Three frames can report a reading and only one reports both. `PUSH_CODE_LOG_RX_DATA` (0x88)
carries `[snr*4 int8][rssi int8]` in its header — `_handleLogRxData` reads those three bytes
instead of skipping them — while `CHANNEL_MSG_RECV_V3` (byte 1) and `CHANNEL_DATA_RECV`
(`ChannelDataReceivedFrame.snr`) carry SNR alone. A missing RSSI is therefore normal, not a fault.

A reading describes **one** reception, so it belongs to the route it was heard on rather than to
the message. `ChannelMessage.pathObservations` is a list of `ChannelPathObservation`
(`helpers/channel_path_signal_helper.dart`) — path bytes plus an optional SNR and RSSI — and
`channel_message_store` persists it with each path base64-encoded. The constructor still takes bare
`snr` / `rssi` arguments and folds them into that list under the message's own `pathBytes`, so a
receive path only has to hand over what its frame reported and never builds an observation itself.
`snr` and `rssi` are getters that look up `pathBytes`, the route the bubble is currently showing.

`ChannelPathSignalHelper` owns every rule about the list. `includeReading` matches by exact path
bytes and fills only the gaps of the entry it finds, so the same packet arriving twice — once as a
channel message carrying SNR alone, once through the RX log carrying both — completes one
observation instead of creating two. `merge`, which `_addChannelMessage`'s repeat merge calls,
folds an incoming list into a stored one the same way. A copy that travelled a different route adds
its own entry and never lends its numbers to another: mixing an SNR from one reception with an RSSI
from another would describe a link nobody heard. Nothing is overwritten either, so a route keeps
the first real reading it got.

Rendering lives in `helpers/signal_reading_text.dart` (`signalReadingSpans`, plus the RSSI colour
scale) rather than in `channel_chat_screen.dart`, which is a merge hot spot. The spans are appended
to the hop list's own `Text` instead of becoming another chip in the meta row's `Wrap`, so they
inherit its font and only colour sets them apart — the same five-step scale the app-bar SNR
indicator paints, SNR against the current spreading factor through `snrUiFromSNR`, RSSI against its
own dBm thresholds. Each reading is glued on with a non-breaking space: a plain space is a break
opportunity, and a reading must never be stranded on a line without the hop it belongs to. With no
hop list in front of them the first reading takes no glue, or it would sit a space further from the
route chip than every other row does.

A message heard with no repeater in between has no hop list but still has a reading, so the row
appears for it too and the route chip reads `DIRECT`. `channel_message_path_screen.dart` asks
`ChannelPathSignalHelper.find` for each path variant it draws, so a packet heard over several
routes shows what each one measured, and a variant with no observation simply shows none. All of it
is gated on `AppSettings.showLastHopSignal` (default on, in mod settings) on top of the existing
tracing and `showHops` gates.

### Overhearing our own packets

Two features read the same thing out of `PUSH_CODE_LOG_RX_DATA` (0x88): a repeater within our
radio range retransmits a packet we sent, our radio logs that retransmission, and the packet
itself says how far it has already travelled. Both are **passive** — nothing extra is
transmitted, and neither delays the send it is watching. Both live in their own helper, because
the parsing is fiddly and the matching rules are what break first.

**Live path tracing** (`helpers/path_trace_progress_helper.dart`, driven from
`path_trace_map.dart`). `PathTraceProgressTracker.parse` accepts a frame only after proving it
belongs to *this* request: the four-byte trace tag matches, the flags encode the same hash width
we asked for, and the route bytes are byte-for-byte ours. Everything else — a TRACE from another
app, our own earlier trace, a packet on a different route — is rejected. It also insists the path
entry width is 1, because TRACE stores exactly one signed SNR byte per completed stage, and that
is what the accumulated readings are read from.

A `PathTraceObservation` deliberately carries **two unrelated measurements**, and the UI must
keep them apart: `routeSnr` is what the relay recorded when it received the packet from the
previous hop — the number the trace exists to collect — while `localSnr`/`localRssi` describe a
different link entirely, namely how *our* radio heard that relay's retransmission. Collapsing
them into one number would describe a hop nobody measured.

Observations are appended as they arrive, so the hop list fills in before any reply comes back.
`_failTrace` does not clear them, and the observation list renders on `completed > 0` rather than
on the success flag — which is what makes a timed-out trace still show how far the packet got.
They are cleared only when a new trace starts. A stage with no observation is drawn with a hollow
check and the `pathTrace_hopConfirmedNoDirectEchoTooltip`: confirmed by the reply, never heard
directly, because that hop is out of our range.

The trace map names the hops of the reply in route order, walking out from our own position
(`_nameHops` over `PathHopResolver`: the nearest node with each prefix after the one before it,
the most recently seen when none has a location). A target that forwards traces went into the
path as its last outbound hop (`buildPath`), so that hop is pinned to the target itself. With
one-byte hashes the prefix of a pinged repeater is usually shared by other nodes, and the scan
this replaced, which gave each hop to the last matching contact in list order, drew the ping to
one of them. Routes from the target's path history are drawn only beside a traced route that
could be drawn: shown alone, a route the trace never took reads as its result.

**Direct-message delivery progress** (`helpers/direct_message_progress_helper.dart`, driven from
`MessageRetryService.handleRxLogFrame`). The echo of a `TXTMSG` carries the *remaining* route, so
completed hops follow from `hopCount - remainingHopCount`, and the progress bar under an outgoing
bubble advances as the message moves away.

Matching here is stricter than it looks, and the strictness is the feature: the packet only
carries **one-byte** source and destination hashes, so several conversations collide on them
routinely. A candidate has to agree on both hashes, on the hash width and on the exact remaining
route suffix — and if more than one pending message still matches, the echo is **discarded**
rather than credited to a guess (`if (matches.length != 1) return;`). Once an echo is accepted the
tracker binds to that packet's exact payload, and a retry's tracker is armed with the previous
attempt's payload in `rejectedPayloads`, so the echo of an older attempt can never be counted as
progress of the current one. Any new call site must go through `matchingStage` rather than
comparing hashes itself, or it loses all of this.

`deliveryProgressTotalSteps` is `pathLength + 1` — the hops plus the final leg to the recipient —
and is reset together with `deliveryProgressCompletedSteps` on every attempt, so a retry starts
the bar over instead of continuing a stale one. A flood-routed message carries `-1` as its path
length, so it gets `0` total steps and shows no bar at all — there is no known route to measure
against, and `_armProgressTracker` refuses to arm for it on the same test.
Delivery fills the bar to `totalSteps`, and `chat_screen.dart` hides it once the status reaches
`delivered`. Both fields are persisted by `message_store` and default to `0` for older records.

### Recovering a cut echo of our own channel packet

The RX log is the only place our own echo is visible: `sendFlood` marks the packet as seen, so
the companion drops the repeat on dedupe before it could become a channel message. But
`logRxRaw` refuses a raw packet longer than 173 bytes (`len + 3 <= MAX_FRAME_SIZE`), and an
ESP32 companion sets its BLE MTU to `MAX_FRAME_SIZE` itself, so a 174–176-byte frame arrives cut
to 173. A cut copy fails the MAC and used to be dropped, and the repeat of a long message went
uncounted.

`helpers/channel_echo_recovery.dart` closes that ESP32 band. The payload of a channel packet is
predictable — AES-128-ECB with zero padding over `timestamp + type + "Name: text"` (or
`data_type + length + data`), the first two HMAC-SHA256 bytes in front, all under the channel
PSK and a timestamp the app chose itself — so `_sendFrameDirect` registers the expected MAC and
ciphertext of every `CMD_SEND_CHANNEL_TXT_MSG` / `CMD_SEND_CHANNEL_DATA` it writes, whatever
built the frame: text, MCMP/MCOtxt envelopes, images, markers, scheduled commits and retries all
pass that one point. When `_handleLogRxData` fails to decrypt a group packet it asks the registry
for an entry the received bytes are a strict prefix of and decodes the full packet in place of
the cut one, so path, SNR/RSSI and repeat counting run through the ordinary code. A match needs
the MAC and one whole block: AES under one key is a permutation, so a shared block means the
same plaintext under the same key, which is our own packet; a copy as long as the packet is not
a cut one and is never "recovered". Entries live ten minutes, the self-echo window of
`_isChannelRepeat`. `AppSettings.recoverLongPacketEchoes` (default on, mod settings) gates both
registration and matching, and the channel composer's counter: while it is on, a message whose
packet would be too long even for a cut copy shows `160 (-5) / 165`, the bytes to drop for the
first repeater's echo to fit (`ChannelEchoRecovery.plaintextBytesOverEchoLimit`: one hop at
the node's `pathHashByteWidth`, the region scope's transport codes counted, and for a binary
payload the firmware's three-byte `data_type + length` header added, because the binary counters
report only the bytes handed to `CMD_SEND_CHANNEL_DATA`, so the budget there is 157 data bytes
rather than 160 of plaintext). The counter and that budget read one memoised encoding
per keystroke (`_composerEncoding`), so the compressor does not run twice. A packet longer than 173 bytes on the wire produces no frame at all
and nothing here can help it; direct messages are out of reach too, their ciphertext needs the
node's private key.

### Copies of a channel packet

The companion logs every packet its radio hears before it processes it
(`Dispatcher::checkRecv`), so a channel packet the node delivers as
`CHANNEL_MSG_RECV` reaches the app twice, as the RX-log copy first and as the
frame after it, and every repeater in range adds one more RX-log copy. Every
copy used to go through the whole receive path, decryption, MCMP or MCOtxt
decoding, the reply anchor, the Ed25519 check, the contact's last-message
write, the reaction parse, the quote resolution against the history, the
repeat scan, the history sort and the awaited history write, and was
recognised as a repeat only at the end, by the processed text.
`helpers/heard_channel_packets.dart` keeps the packets heard in the last ten
minutes by the identity every copy of one packet shares, which is what can be
read without decoding: the channel, the packet timestamp, the sender name and
the text as it travelled for a text packet, the hash the connector already
computes over channel, data type and payload for a data packet. The four
receive paths (the channel text and data frames, the RX-log text and data
branches of `_handleLogRxData`) look a packet up right after decryption, or
after `fromFrame`, and a known copy is folded into its message by
`_foldHeardChannelCopy`: the route, the reading, the region and one more
repeat through `_mergeChannelRepeat`, the merge the whole path uses as well,
then the row is saved and the connector notifies; a copy of an applied
reaction is dropped. A packet not in the map is claimed and processed as
before, and `_addChannelMessage` settles the claim with the message the packet
was stored as or merged into, or as a reaction, or abandons it when nothing
was stored, so a copy arriving during that processing waits for the outcome
(five seconds at most) instead of processing the packet again; the wait is
also what keeps two copies of one reaction, inside one history write, from
being applied twice. Our own sends are recorded when the packet timestamp is
known (`_recordOwnChannelPacket`), so the first echo is a copy too.

What the map does not do. It merges nothing the old rule would not merge:
the key is the packet itself, and `_isChannelRepeat` takes a same-text message of the sender under the
same packet second, an exact copy at any time while the message is loaded;
its thirty-second window went on 2026-10-13, since another sender's copies
all carry the packet's own second and the window merged a bot answering a
ping twice with one text (`channel_packet_copies_test`). A copy the map misses, a message
trimmed from memory, a packet the node re-encoded, a copy after ten minutes,
takes the old path and its rules. A reaction that matched nothing is not
recorded, so a later copy can still find a target that arrived in between.
The channels listed in `doNotFilterMessagesOnChannels` never use it: their
packets take the whole path every time, since a technical channel such as a
node's TerminalCLI sends what a copy cannot predict. A copy no longer touches
the contact's `lastMessageAt`, which the first receipt sets.
`heardChannelCopiesMerged` and `heardChannelReactionCopiesDropped` count the
short path for the tests (`test/connector/channel_packet_copies_test.dart`).

The hash width of a merged route belongs to the route (`_mergeChannelRepeat`,
since 2026-10-14): a message without one yet, our own send or a message
echoed into the history with a path byte that says no hops, takes the first
copy's width, and a route taken from a copy brings its own along. The
message's width used to win, so a two-byte route merged into a message that
claimed one-byte hashes was drawn as twice the hops.

### Direct echo recovery (experimental, off by default)

The same RX log shows a direct message *to us* before it arrives: the
companion logs every packet its radio hears and only then checks whether it
is the next hop of a direct-routed packet, dropping it otherwise. A TXT_MSG
addressed to our one-byte hash can therefore be heard from a repeater near us
while it still has hops to travel, and the copy is the very packet that will
reach the node later, minus the hops it has already shed. With the node's
private key the app can decrypt it as the node would. `AppSettings.
directEchoRecovery` (mod settings, **off** by default, under the long-echo
toggle) turns that on, and the toggle's subtitle says why it is a decision:
the key is exported into the app's memory.

**The key lives in RAM and nowhere else.** After each SELF_INFO handshake the
connector sends `CMD_EXPORT_PRIVATE_KEY` (23) and keeps only the X25519
scalar — the first 32 of the 64 bytes — in `DirectEchoKeyStore`
(`helpers/direct_echo_recovery.dart`), together with the shared secrets
derived from it, one per sender. `RESP_CODE_DISABLED` (15, firmware built
without `ENABLE_PRIVATE_KEY_EXPORT`), a short frame or no answer leave the
option quietly inert. `_clearDirectEchoKey` zero-fills everything on
disconnect, at the start of every new session, on a node change, when the
option is switched off and in `dispose`. `BleDebugLogService.logFrame`
withholds the payload of `RESP_CODE_PRIVATE_KEY` (14), since that log is
exportable; the app log only ever records that the export succeeded, was
refused or timed out.

Энергопараметр `deferBleLogDescriptions` меняет только момент форматирования
новых записей этого журнала. Маскирование ответа с ключом и копирование данных
остаются немедленными. Отложенная запись получает readonly view собственной копии;
static-фабрика `_recordEntry` передаёт callback только безопасный snapshot,
направление и уже очищенную note, без исходного ответа и ссылки на service.
`helpers/deferred_log_description.dart` кэширует первое описание и освобождает
callback после успеха. Обычный конструктор `BleDebugLogEntry(description: ...)`
сохранён, публичное чтение `description` работает в обоих режимах.

**The crypto repeats the firmware's.** `helpers/direct_echo_crypto.dart` is
pure Dart so it can be checked outside the Flutter test runner: the shared
secret is `ed25519_key_exchange` — the clamped scalar against the peer's
Edwards y turned into Montgomery u = (1 + y) / (1 − y) — run through
`DartX25519`, and the six ACK bytes are `BaseChatMesh::onPeerDataRecv`'s
(SHA-256 over timestamp, flags and text plus the sender's key, truncated to
four, then the extended attempt byte after the text's NUL, then one random
byte). MAC-then-decrypt is the connector's existing `_decryptPayload`, which
is already `Utils::MACThenDecrypt` for channels; the shared secret is simply
the key. Verified against libsodium with the firmware's own test client
keypair.

**One branch in the receive path, not a second one.** `_handleLogRxData`
hands a TXT_MSG frame to `_recoverDirectEcho`, which accepts only a direct-
routed copy addressed to our hash with hops still ahead (a copy with none
left is the one the node delivers itself), tries every contact whose key
starts with the source hash — the firmware's `searchPeersByHash` loop — and
accepts only `TXT_TYPE_PLAIN` (CLI replies and room posts stay the node's
business). The plaintext is then rebuilt as the `CONTACT_MSG_RECV_V3` frame
the node would have queued and fed to `_processIncomingMessage` with a
`DirectEchoContext`, so decoding, verification, storage, unread counting,
notification and translation are the ordinary ones. Only three things differ
there: the duplicate check now finds the message instead of merely noticing
it and calls `_mergeDirectEcho`; a new message from an echo is stamped by
`DirectEchoRecovery.stampFirstEcho`; and after it is stored the ACK goes out.

**Our own packets.** A contact whose key starts with the byte ours starts
with makes our packets to them look, to us, like theirs: the destination
hash is ours, the source hash is theirs, and the shared secret is the same
both ways. The node drops the copy a repeater relays as a packet it has
already seen (`Mesh::sendDirect` and `sendFlood` mark it), but the RX log
carries it, and the echo branch decoded our own message as one from them,
showed it with the route bar and acknowledged it (reported from the field
on 2026-10-09). `_processIncomingMessage` therefore asks
`DirectEchoRecovery.isOwnMessage` before an incoming message from such a
contact is verified, counted, stored or acknowledged: the packet time and
the text, decoded or as it went out, of a message we sent them name it as
ours and it is dropped, the node's ordinary delivery included, in case the
node forgot a packet it sent. Any other contact is never checked
(`test/connector/own_message_echo_test.dart`).

**Identity and progress.** The duplicate key is the one the receive path
already uses — sender, packet timestamp in milliseconds, decoded text — so
every later copy, a repeater's retransmission or the node's own delivery at
the end of the route, merges into the message the echo created. The bar
under the bubble reuses `deliveryProgressTotalSteps` /
`deliveryProgressCompletedSteps`: the first echo sizes it to the hops still
ahead plus the final leg (`remaining + 1`, none done), a later copy heard
from further along advances it, a copy with more hops left than the bar was
sized for widens it and keeps what was done — it never moves backwards —
and the ordinary delivery fills it (`completeOnDelivery`), which is what
hides it, since `chat_screen.dart` shows it for an incoming message while
`completed < total`. A message the node delivered before any echo was heard
keeps its bar off and only records the route. Every distinct route heard is
kept as a `DirectEchoObservation` (`models/direct_echo_observation.dart`:
remaining path in travel order, hash width, SNR, RSSI) on
`Message.directEchoObservations`, persisted by `message_store`.

**Incomplete paths.** The path screen opened from a direct chat receives
those observations as `incompletePaths` and lists them under a section of
that name ahead of *Other observed paths*, one card each in the order heard,
hops sender-side first with the signal reading. A line under the header
(`channelPath_incompletePathsNote`, en and ru) says why they are
incomplete: a direct packet carries only the hops still ahead of it, each
repeater removing itself from the remaining path, so the full route the
sender set is heard only in the sender's own transmission, and the node's
own delivery carries none. The map button opens the
route through `ChannelMessagePathMapScreen`, handing it the *inverted* path,
because that screen draws a direct message's stored route from our end and
reverses it for display. The copy button puts the inverted route on the
clipboard as hop hex joined by commas — the form `PathEditorSheet`'s hex
field parses — since read from our end it is the known tail of a route back
to the sender.

**The ACK is real, and only when the firmware can.** `CMD_SEND_RAW_PACKET`
(65, stock MeshCore since May 2026) sends any parsed packet, so
`_sendDirectEchoAck` builds a `PAYLOAD_TYPE_ACK` packet as
`BaseChatMesh::sendAckTo` would route it — direct along
`resolvePathSelection(contact)`, else a flood, scoped through
`_computeRegionTransportCode` with the contact's own region or else the node's
default one, when there is one — with the path byte packed as the firmware
packs it. It is sent once, for the copy that
created the message; repeats and the delivery send none. Only
`ERR_CODE_UNSUPPORTED_CMD`, or an ERR carrying no code, means the firmware
predates the command (`DirectEchoRecovery.meansRawPacketUnsupported`); that
sets `_directEchoAckUnsupported`, logged once, until the link goes (see
Connection State). Any other refusal costs that one ACK, above all
`ERR_CODE_TABLE_FULL` from a busy node with no packet to spare, which drops
its own ACK in the same case; a timeout is logged and not held against the
node either. What the app cannot suppress is the node's own ACK when the
packet finally arrives: two ACKs go on air, and the sender's node confirms
the delivery once, since the first clears its expected-ACK entry and the
second finds nothing. With the option off nothing here runs: no
command is sent, `_handleLogRxData` returns on a TXT_MSG as it did before,
and the duplicate check is the same predicate returning through a new name.

### Flood retransmissions of direct messages

A direct message that travels by flood shows the relay counter channel messages have: the repeat icon and a number in the bubble's meta row, which message tracing gates as it does in channels, and the Repeats row of its path screen. `Message.repeatCount` holds it, persisted by `message_store` and 0 for older records. An outgoing message counts every relayed copy our radio hears, since our own transmission never reaches the RX log; an incoming one counts the copies after the one the node delivered.

`helpers/direct_flood_repeats.dart` does the counting. A flood copy keeps its payload byte for byte at every hop, so once a message is tied to a payload, each further copy with that payload is one more relay. The tie is the hard part, the payload being encrypted:

- **With direct echo recovery on**, `_directFloodIdentity` decrypts every flood TXT_MSG copy that involves our hash with the key the option keeps in RAM. The shared secret works both ways, so our own copies decrypt as well as copies addressed to us. A decrypted copy is named by the other party's key and the sender timestamp and binds only to the message with that identity.
- **Without the key**, an outgoing message binds the first unclaimed copy from our one-byte hash to its recipient's once `RESP_CODE_SENT` said flood. `_handleMessageSent` reads that `is_flood` byte, and `MessageRetryService.sentMessageForAck` names the message it matched. Two different messages waiting on one pair of hashes are refused, while the attempts of one message count as one. An incoming message binds, at delivery, the earliest unclaimed copy from its sender's hash to ours that took the hop count the CONTACT_MSG_RECV frame reports, since the node hands messages over in the order it heard them.

Heard packets are remembered for ten minutes and a flood send waits two for its first copy; all of it is dropped with the session. `_processIncomingMessage` reads the frame's path byte for the binding, and a sender's retry, being a packet of its own, binds to the message it repeats. The retry service writes back its own stale copy of a pending message, so `_updateMessage` keeps the stored count when that one is ahead: the count only grows within an attempt.

The count belongs to the latest attempt, from the moment that attempt is planned. Every attempt is a packet of its own: the retry service bumps `retryCount` and writes the message back as soon as it schedules a retry, before the backoff, the radio-quiet wait and the send, and `_updateMessage` reads that change of attempt number as the start of a new count, taking the copy's zero instead of keeping the stored count, and telling the helper (`planAttempt`) so that the earlier attempt's copies stop counting at once rather than at `RESP_CODE_SENT`. The helper tags each bound packet with its attempt (`expectOutgoing(attempt:)`, the retry service's `retryCount`; for an incoming message the binding order, so the sender's delivered retry becomes the latest and restarts the count too) and marks every other packet of the message superseded for good, so a restart at the same number cannot revive them. A copy of an earlier attempt heard later still adds its route, but `DirectFloodHit.currentAttempt` is false and it neither counts nor writes its region onto the message. The region line keeps the attempt that last went out: the planning write-back restarts the count but leaves the region, because an acknowledgement of the earlier attempt can still arrive during the backoff and cancel the retry, and the delivered message used to read *unknown*. The retry itself reads the contact's choice as it is at that moment (`_sendMessageDirect` looks it up per attempt), and `_stampDirectFloodSend` replaces the line at the retry's `RESP_CODE_SENT` with that same choice, unless a copy of the retry was already heard while the default scope loaded (`DirectFloodRepeats.heardCopyOf`), so a region changed between attempts still reaches both the packet and the bubble. With the echo-recovery key the attempt is read out of the plaintext (`_directFloodAttemptOf`: the low two bits of the flags byte, or the byte the firmware appends after the text's terminator past three), so a decrypted copy binds only to the expectation of its own attempt; without the key a new attempt takes the place of the older expectations of the same message, since copies of a send arrive within seconds of it or not at all.

The same message shows the region line channel bubbles have, `Region: …` on its own line above the time under `showMessageRegion`, but only when it travelled by flood: `Message.sentByFlood`, set from the `is_flood` byte of `RESP_CODE_SENT` for an outgoing message and from the CONTACT_MSG_RECV path byte for an incoming one, since a message on a known route carries no scope at all. The three region fields mirror `ChannelMessage`'s (`packetRegion`, `packetRegionInfoAvailable`, `packetRegionNotMatched`), persisted by `message_store`, and the bubble words them as the channel bubble does: the name, *no matches* for a transport code no known region produces, *unset* for a plain flood, *unknown* while nothing was read. The exact answer comes from a heard copy of the packet: the helper keeps each copy's first transport code with its payload and hands both back on binding, and `_withDirectFloodCopy` resolves them through `_resolveTransportCodeRegion`, which tries the node's default scope after the known regions, because a flood direct message goes out under that scope and the region screen does not add it to the list (a channel packet heard under it is named the same way now). An outgoing message shows the contact's own region, else the node's default scope, as soon as the node confirms the flood send (`_stampDirectFloodSend`), and a relayed copy replaces that assumption with what the packet carried. An incoming one shows the region of the copy the node delivered, which the RX log carries as well, or *unknown* when no copy was heard, such as a packet too long for the log. `_updateMessage` keeps the stored flag and region when the retry service writes back a copy without them, as it keeps the count.

Each heard copy also leaves its route. `Message.floodPathObservations` holds one `ChannelPathObservation` per distinct route with the SNR and RSSI of that reception, written sender first as the RX log gives it, and `floodPathHashWidth` the hash width they are written in; `message_store` puts them into the message JSON, which lives in the SQLite row like everything else on a message. With message tracing and `showHops` on, the bubble draws the longest of those routes above the region and time lines as a channel bubble draws its hop list (`RouteChip`, `channels_via`, the copy's reading under `showLastHopSignal`), `ChannelPathSignalHelper.longest` picking it as the path screen picks its primary route; a message that took a known route draws none, its route being the contact's. The helper keeps every copy of a packet it has not tied to a message yet, so an incoming message receives the routes heard before its delivery when it binds, the delivered copy's included; later copies, and every copy of an outgoing message, go straight onto the message. `_openMessagePath` hands them to the path screen as `pathVariants` and `pathObservations`, turned around hop by hop for an incoming message (`ChannelPathSignalHelper.reverseHops`) because that screen reads a direct message's routes from our end, and the screen takes the longest route as the primary one, as it does for a channel message. `_updateMessage` keeps the longer stored list, for the same reason it keeps the count.

### The path of an incoming direct message

An incoming direct message or room post keeps the path of its own packet,
as the node reports it in the CONTACT_MSG_RECV frame's path byte: `0xFF` for
a packet routed to us, which the repeaters stripped of its route on the way,
stored as `pathLength` 0 with no hop bytes, the path screen's *Direct* with
no hop list; otherwise the hop count of a flood, with the hash width in the
top two bits, stored as `pathLength` with no bytes either, the routes
themselves coming from the RX-log copies (`floodPathObservations`). Until
2026-10-09 the connector wrote the contact's route onto every incoming
message, so a message received directly showed, as its repeater hops, the
route the node held for the contact, a pinned one included; only a message
another client sent through us still takes the contact's route, as our own
sends do (`test/connector/incoming_message_path_test.dart`). Messages stored
before keep the route they were given.

### Direct send failures

Each attempt of a direct or room message waits under the command lock for its own `RESP_CODE_SENT`, paired by `PendingCommandReplies` (see **Frame I/O**). The node's ERR (unknown contact, packet pool full, text too long for the attempt) is thrown out of `_sendMessageDirect`, and the retry service's `_attemptSendOrFail` fails the message at once and frees its slot; before, the attempt returned null and the message was retried every two seconds until the limit. A missing SENT leaves the message to the retry timer, and a scope command the node left unanswered sends nothing, the attempt returning null for a retry two seconds later. `_failMessage` keeps a message whose earlier attempt did go out matchable for `_lateAckGracePeriod`, as the last attempt is, because the node reports a delivery once; one that never left is dropped from the service at once, where it used to stay tracked, failed, with its stop row, for the rest of the session.

A lost link is not a failure. The connector pauses sending (`pausePendingOutgoingMessages`) before anything can throw, `_attemptSendOrFail` leaves a message alone while sending is paused, and the reconnect resumes it; upstream's `failAllPending`, which fails every pending message on a disconnect, was deliberately not taken.

From the fifth attempt on the firmware appends the attempt number after the text and refuses text over 158 bytes (`BaseChatMesh::composeMsgPacket`), so `_textFitsAttempt` ends the retries of a longer message after the fourth, and the direct composer shows `chat_longMessageRetryNote` next to its counter (`softLimitBytes` / `softLimitNote` of `ByteCountedTextField`) once the text passes that size.

### Stopping a direct send

An outgoing direct or room message the retry service is still working on, attempts ahead or an acknowledgement awaited (`isSendInProgress`), carries a *stop sending* row at the bottom of its bubble: `widgets/stop_sending_bar.dart`, laid out as the scheduled send's cancel bar, divider included but without an icon, wrapped in the same `IntrinsicWidth`, and placed under the delivery progress bar, which joins the column while the row is shown instead of lying on the bubble's edge. It exists for the message that was read long ago while its ACK never came back: the app would otherwise retry it to the limit and hold the contact's queue meanwhile. `stopSending` hands the message to `MessageRetryService.untrack`, which cancels the timer, drops the message and frees the in-flight slot and the contact's queue; the message keeps what its attempts earned, `sent` once the node had taken it, `failed` when nothing had gone out; and when the contact has a flood choice the node's scope is cleared once more under the command lock, after any window an attempt still holds, so nothing of a cut-short window lingers. The ACK hashes the attempts waited for are remembered for the session (`_stoppedSendAcks`), so a confirmation that arrives after all still marks the message delivered from the `PUSH_CODE_SEND_CONFIRMED` handler, once the retry service has declined it.

### Map raster sources

Sources live in `MapRasterSourceCatalog` (`services/map_tile_cache_service.dart`) and are picked in app settings. Two carry an API key: Stadia (`mapTileApiKey`, with a shared demo key as fallback) and **Yandex** (`mapYandexApiKey`, no demo — the map silently falls back to OpenStreetMap until the user pastes their own key from the Yandex developer dashboard).

Tile resolution is user-picked: `mapYandexTileScale` (1.0 by default, options in `AppSettings.mapYandexTileScaleOptions`) becomes the `scale` parameter, so a value above 1.0 fetches the same tile at a multiple of 256 px for dense screens. It is part of the cache key, so changing it orphans previously downloaded tiles.

Yandex ships as two sources, `yandex` and `yandex_dark`, differing only by `theme=dark` on the request. They are separate catalog entries rather than one entry with a flag, because the theme travels in the URL and therefore in the cache key: light and dark are different files on disk and have to be counted, downloaded and cleared apart. That also means `_parseCachedTile` cannot attribute a cached Yandex tile by host alone — both share `tiles.api-maps.yandex.ru` — so it reads `theme` back out of the key, which survives because `tileCacheKey()` strips only `apikey` and `signature`. Get that wrong and the dark source reports the light one's tiles as its own. Everything else follows automatically: the API-key field, the signing secret, the tile scale and the terms link are all gated on `isYandex`, and the picker walks `MapRasterSourcePreset.values`.

Yandex needs `projection=web_mercator` on every request. Its default is elliptical Mercator (EPSG:3395), which flutter_map does not model — it ships `Epsg3857`, `Epsg4326` and `Proj4Crs` only — and rendering those tiles on the 3857 grid would put every node marker kilometres off. Tile coordinates ride in the query string rather than the path, so `_parseCachedTile` reads `x`/`y`/`z` from `queryParameters` for that host, and `tileCacheKey()` strips `apikey` from the cache key: reissuing a key must not orphan an already-downloaded offline region.

Requests are signed when a signing secret is set (`mapYandexSigningSecret`, entered in settings next to the key). `signYandexUrl()` implements the *simple signature*: `HMAC-SHA256` over the path and query with the host stripped, keyed with the Base64UrlSafe-decoded secret, digest appended Base64UrlSafe as the last `signature` parameter. Because the signature covers the finished URL, it can only be computed per tile — hence `CachedNetworkTileProvider.urlSigner`, applied after flutter_map substitutes the coordinates, and the same call in `downloadRegion`. `tileCacheKey()` strips `apikey` **and** `signature`, so a tile survives a reissued key, a rotated secret, and signing being switched on or off. It is one function for every source, `MapTileCacheService.tileCacheKey`, and also drops Stadia's `api_key`, so a Stadia tile survives a new key too; Stadia tiles cached before that were keyed with the key in them and are fetched once more. An undecodable secret yields an unsigned URL rather than a broken one, which the console's "optional" signature mode still accepts.

Two deliberate departures from the provider's terms, decided by the project owner:

- **Cache lifetime.** Yandex permits caching for at most 30 days; the shared cache keeps tiles for `MapTileCacheService.cacheLifetime` (365 days). `PinnedFreshnessFileService` also overrides the `Cache-Control` Yandex sends, pinning freshness to that same period — otherwise stored tiles re-validate, which spends rate-limit slots on files already on disk and lets an offline region expire far from any network. The app is meant for mountains and emergencies where there may be no network for far longer than a month, no commercial harm is done to the provider, and a permission request has been sent to Yandex. Do not "fix" this back to 30 days without asking.
- **Bulk pre-download** stays enabled for Yandex, capped at `yandexMaxRequestsPerSecond` (25) against the published 30 rps limit. Pacing lives in `RateLimitedTileCacheManager` so rendering and pre-download share one counter; it claims a slot *before* awaiting, because tile requests arrive in parallel and reserving afterwards lets a zoom or fast pan fire them all in one burst.

Their terms also ask for two attribution elements. The **About dialog link** is in place: `settings_screen.dart` shows `settings_aboutYandexMapsTerms` — pointing at <https://yandex.ru/legal/maps_termsofuse/> — but only while a Yandex source is selected, since the requirement applies to apps actually using the tiles. The **logo overlay on the map itself is not implemented yet** and is tracked as separate work; until then the on-screen attribution is the `© Яндекс` in the source description shown when picking the source.

`buildTileLayer` sets `evictErrorTileStrategy: EvictErrorTileStrategy.notVisible`. The flutter_map default is `none`, and since Flutter caches failed image loads as well as successful ones, a tile lost to a rate limit or a dropped connection stayed a grey square for the whole session. Evicting error tiles once they leave the viewport is what makes returning to the area re-request them.

Tile requests carry a per-host `User-Agent` (`headersForUrl`): `MCO (+…)` everywhere, since the OpenStreetMap tile policy blocks library defaults like `flutter_map (…)`, and a desktop-browser string for Yandex, whose tile endpoint is built for web clients. The provider is seeded with the app agent so `TileLayer`'s `putIfAbsent` cannot overwrite it.

Removing a cached tile used to leave its file on disk. flutter_cache_manager before 3.4.2 deleted a file by its bare name against the working directory of the process, so the map cache screen's clear, the removal of a tile that fails to decode and the package's own eviction (over 200000 tiles, or untouched for a year) all dropped the record and kept the tile: a cleared cache read 0 bytes while the directory kept its size. The dependency is `^3.4.5` now, which also brings 3.4.3's atomic writes of the JSON record file used on Windows and Linux. What the old versions left behind goes when the inventory is first read in a session: `sweepOrphanedCacheFilesOnce` (`services/cache_manager_orphans.dart`) deletes, in a background isolate, every file in the cache directory that no record names and that has not changed for an hour, since a tile being downloaded exists before its record does. The same leak hit the default cache behind URL image previews and notification pictures; the upgrade stops it there as well, but nothing sweeps what it already left.

On Windows and Linux the tile records live in `map_tile_cache.sqlite` (`storage/map_tile_cache_database.dart`: drift over a `GeneratedDatabase` with no generated code, one `CREATE TABLE IF NOT EXISTS` and `customSelect` / `customStatement` throughout) rather than in the JSON file flutter_cache_manager keeps there by default, which it decoded whole before the first frame and rewrote whole on every change, a viewed tile's touch time included: 30 MB and 370 ms a write at 66 thousand records. Android, iOS and macOS keep the package's sqflite repository, which is indexed already. `MapTileCacheRepository` implements the package's `CacheInfoRepository` over that database and gives the sqflite repository's answers (a hundred old or over-capacity records at a time, the latter only when untouched for a day), and the database is a file of its own rather than a table in the message-history database, so the churn of a cache never grows the history or its vacuum. It runs in WAL mode with `synchronous = NORMAL`, set through `DriftNativeOptions.setup`: `CacheStore` writes a record's touch time as a transaction of its own at every first access of a tile in a session, and with the rollback journal each of those cost an fsync, 15 ms measured, against 0.2 ms in the log. The log is reused after a checkpoint but never shrunk by itself, and the app never closes this database, so a session leaves its log behind at the size of the largest transaction it held; the one-time move below is one transaction the size of the index and left a 39 MB log beside a 39 MB database on the first machine. `journal_size_limit` (4 MB) cuts the log back after any checkpoint, the move ends in a `wal_checkpoint(TRUNCATE)`, and `openForThisPlatform` runs the same checkpoint at every launch, before the map reads anything. A deletion that removes more records than it leaves, the cache screen's clear above all, is followed by a `VACUUM` and the same checkpoint (`_rebuildAfterDeleting`): SQLite keeps the pages of deleted rows for its own reuse and never shrinks the file by itself, and the first cleared cache stayed at 38 MB with nothing in it; the eviction of a hundred records from a full cache leaves the file alone, its pages going to the tiles that come next. `MapTileCacheRepository.openForThisPlatform` runs from `main()` before any service exists and moves the JSON index into the table once: decoded in a background isolate, every record in one transaction, a key already in the table keeping its row, ids not carried over, the file deleted after the commit, behind a `StartupNoticeApp` notice while it takes. A file that will not decode is renamed `.corrupt-<time>` and nothing is imported, where the package read such a file as empty and overwrote it at the first write. Any failure returns null, and the service then takes the package's JSON repository with the index file untouched, as before. The orphan sweep stays off for the session that moved the index (`sweepOrphanedFiles`), in case the move missed a record. The cache manager and the tile provider are `late final` and created on first use rather than in `main()`, so a launch that never opens a map opens no repository.

### Opening the map on a node

`widgets/contact_map_button.dart` is the icon button that jumps to the map centred on a
contact's own position — used from the repeater login dialog. It renders nothing at all when
`Contact.hasLocation` is false (an advert carries 0,0 until its node has a fix), so a caller
drops it into a row unconditionally. It opens at zoom 15 because the map draws node labels only
from `_labelZoomThreshold` (14.0) up, and reading the name is the point of going there.

`MapScreen.highlightPosition` does two jobs — it centres the map *and* draws the red highlight
pin — so `showHighlightPin` (default true, every existing call site unchanged) turns the pin off
for a position that only names something the map already draws itself.

### Map notifications

Notifications initiated by `MapScreen` use its local `_showMapSnackBar` overlay rather than
`ScaffoldMessenger`, `showDismissibleSnackBar`, or a snackbar placed in the map's layout. The
`OverlayEntry` is positioned 20 px from either side and 72 px above the bottom safe area, so it
overlays the map without shifting the filter, wardrive, zero-hop, or other floating controls.
Only one entry is kept: a new notification replaces the previous one, tapping dismisses it, and
the four-second timer removes it automatically. Pass `colorScheme.error` as `backgroundColor`
for failures; informational messages use `surfaceContainerHigh`. `_removeMapSnackBarOverlay`
must remain in `dispose`, and future notifications owned by the main map should use this helper.
The path-trace cancellation notice and offline-action rejection follow the same path.

### Estimated node positions

The map can estimate where a node without coordinates is (the repeater
search behind `locateUnknownRepeatersEnabled`) and keeps the guesses in
`contact_location_cache` through `ContactLocationEstimateStore`
(`storage/contact_location_estimate_store.dart`): one row per node, with its
real position when it has one and its estimate when it has none, plus the
prefix-only repeaters nobody has named. The map draws a stored estimate only
for a node that still has no coordinates, so a guess left behind for a node
that reported its position is invisible, but it would come back the day the
node loses its coordinates again, and it would keep the map from
recalculating (`missingKeys`). The connector therefore drops a node's
estimate when the node becomes located: `_persistContacts` and
`_persistDiscoveredContacts` hand `clearEstimatesForKeys` the keys that have
coordinates now and did not at the previous save, remembered per list in
`_contactEstimatesCleared` and `_discoveredEstimatesCleared`; a key that
drops out of the list leaves the set (an advert without coordinates keeps
the known ones, so a node loses them only by leaving the list), a node that
comes back without them is cleared again when it reports them, and the
first save of a session clears every located key once.
Before, every save cleared every located contact, a rewrite of up to a
thousand rows with nothing in them, 12 ms per advert or message on the
database isolate. The UPDATE itself touches only rows that hold an estimate
(`AND estimated_latitude IS NOT NULL`), so a clear of keys already empty
writes nothing and moves no `updated_at_ms`
(`test/storage/contact_location_estimate_store_test.dart`,
`test/connector/contact_location_estimates_test.dart`).

### Map builds

The map screen (`map_screen.dart`) rebuilds on every notification of the connector, up to twenty a second under live radio, and on those of the path history, the settings and the wardrive service, and each build derives everything from scratch: signatures, filters, guessed positions, markers, coverage. Two things cut that down without touching what is drawn. Under another page (a chat, the settings) the build hands back the tree it built last (`_lastBuiltBody`) and computes nothing, since nobody sees the map; `didPopNext` calls `setState`, so the return builds anew once with everything that changed meanwhile. A dialog or a bottom sheet over the map is no page to `appRouteObserver`, which is typed on `PageRoute`, so the map under one keeps updating live. And the caches key on less. The node marker cache (`_NodeMarkersCacheKey`, its inputs listed above the class) no longer includes a signature of every contact, so an advert from a node off the map leaves the markers as they are, and it includes the node's hash width, which the overlap prefixes are cut at. The guessed-position key is a hash of the same inputs it used to join into a string of a hundred kilobytes per build. `allContacts` is built once per build and handed to the snapshot, and the repeater search candidates are built only while that search is on. The wardrive derivations (the selected coverage samples, the coverage polygons, the repeater coverage samples and polygons, the sample points) go through `LastValueMemo` (`helpers/last_value_memo.dart`), keyed on the samples list itself, which `WardriveService` replaces whole at every change, plus the settings each reads, so a build that changes nothing about the samples reuses the polygons; the samples themselves are collected and kept exactly as before. The search field waits `_searchDelay` (300 ms) for the typing to pause before it sets `_searchQuery`, which rebuilds the whole map. Every marker carries a key (`node:`, `label:`, `cluster:`, `guess:` or `shared:` and the identity), so the marker layer moves subtrees instead of recreating them when the list changes order. Left as it was, on purpose: the centre and zoom of all nodes are computed every build because the centre-map button uses them live; clustering of guessed markers, cheaper marker shadows and the dark-theme tile filter change the look and wait for a decision; the marker signature still hashes every loaded marker message, which is exact, and a connector-side messages revision would be a change of its own (`test/screens/map_screen_state_test.dart`, `test/helpers/last_value_memo_test.dart`).

### Shared markers on the map

A marker shared into a chat is the text `m:<lat>,<lon>|<label>|<flags>`, parsed by
`parseMarkerText`. `_collectSharedMarkers` in `map_screen.dart` turns every such message into a
pin, grouping repeats of the same marker so the older positions become its history trail.
`parseMarkerText` refuses a latitude or longitude out of range, which `LatLng` would assert on.

**Where markers come from.** `getLoadedChannelMessagesWithShared` /
`getLoadedMessagesWithShared` merge in shared history, so pins from another node appear too.
Those getters never start a load, so the map warms both sides from `build`:
`ensureSharedChannelHistoryLoaded()` for channels, `ensureContactHistoryLoaded()` for contacts.
The contact one exists because a conversation, unlike a channel's messages, is read from storage
only when something asks for it — without it a contact's pins appeared on the map only after that
chat had been opened. It skips repeaters, whose history is CLI traffic. Contact pins are never
filtered by the channel picker: that gate is `_channelMarkerStyles.isVisible(marker.channelName)`,
and a contact marker has no channel name.

`ensureContactHistoryLoaded` cannot simply warm everything in one go: a conversation is stored as
a single JSON blob, so doing them back to back decodes the whole message store inside one frame,
which is plainly visible as a stall — and at a few hundred contacts with shared history on, three
separate costs pile up. The sweep answers each one:

- **Decoding.** Most conversations are never decoded. `MessageStore.mayContainMarker` reads the
  raw string and rejects it with a substring scan, and `secondaryMayContainMarker` does the same
  across every other node's copy, so the cost stops depending on how much history exists. That
  peek deliberately avoids `_loadMessagesJson`, whose legacy-key migration would fire a
  preferences *write* per contact, and it is synchronous so a sweep pays no async hop per look.
- **Scope discovery.** `SharedMessageHistoryHelper.knownScopes()` walks every preferences key
  with three regexes, so it is read once for the whole sweep and passed down. Asking it per
  contact was the single largest cost.
- **Frame time.** The sweep runs in the background under `_warmingContactHistory` and yields to
  the event loop after anything it decodes, and every 25 contacts regardless.

A conversation the peek rejects is left *unloaded* rather than marked loaded, so opening its chat
still reads it as before; a marker arriving later loads the conversation on the receive path
anyway. `_markerScannedContactKeys` records that a contact was examined at all, so a later sweep
skips it in one lookup — that set, not the loaded one, is what keeps the steady state cheap, and
it is cleared wherever `_loadedConversationKeys` is.

The pass only calls `notifyListeners` when it actually opened something — otherwise the notify
would drive a rebuild that starts another pass. It reports that itself rather than trusting the
loaders, because an empty conversation is stored and loaded without notifying at all.

The same getters feed `_MapConnectorSnapshot.markerSignature` — the marker list is cached
against that signature, so anything that should change the pins has to be visible to it.

**Per-channel styling.** Each channel decides whether its markers show at all, in what colour
and with which icon — the map's overflow menu → `map_showMarksFromChannels`. The feature is kept
out of `map_screen.dart` on purpose: it is fork-only and the map screen is a merge hot spot.
Four files own it — `models/channel_marker_style.dart` (style and palette),
`storage/channel_marker_style_store.dart` (persistence), `helpers/channel_marker_styles.dart`
(load/lookup/update, channel ordering) and `widgets/channel_marker_settings_sheet.dart` (all
UI). The map screen keeps one field, `syncTo` and `trackChannels` in `build`, `isVisible` in the
marker filter, `styleFor` in the marker builder, one menu entry and `channelName` on
`_SharedMarker`.

Styles are one JSON blob per node, **keyed by channel name**: indexes shift when channels are
added or removed, and the name is what shared history matches across nodes. Reads are
synchronous because a style is looked up while building every marker. Colours and icons are
stored as keys into `ChannelMarkerPalette`, never as an ARGB int and a code point — building
`IconData` from a stored code point at runtime defeats the icon tree-shaker and pulls the whole
Material font into the build.

Untouched channels store nothing: `ChannelMarkerStyle.defaultsFor(order)` derives their look
from the channel's place in the picker, walking the palette in order and wrapping around. Public
sorts first and so keeps green; the default icon is `place`. Anything the user edits is written
out and from then on wins. The visibility toggle filters in `build`, next to the hidden/removed
marker sets, rather than inside `_collectSharedMarkers` — that one is cached against a signature
which knows nothing about style changes.

**"Remove for everyone".** `helpers/shared_marker_deletions.dart` (no imports of its own) holds
the convention: the command is the marker's own text behind a `del:` prefix, sent back where the
pin came from — its channel, or the contact or room server that shared it — so a client that does
not know the convention just shows the line as text. `_SharedMarker` carries `channelIndex` or
`contactKeyHex`, exactly one of the two, and `_sendMarkerDeletion` picks the route from that.
Nothing is stored — `_collectSharedMarkers` reads the commands back out of the conversation,
which gives two rules for free: a command only hides markers **older than itself**, so re-sharing
the pin later brings it back, and deleting the command from the chat undoes it. `del:` lines
therefore have to count towards `markerSignature`, in the contact loop as well as the channel
one. In the chat the command renders as the POI badge with `chat_poiRemoved` and a struck-through
pin icon — in both chat screens, since `parseMarkerText` is unanchored and matches `del:m:...` as
readily as `m:...`. That same unanchored match is why the contact loop has to `absorb` before it
parses: without it a `del:` line drew a second pin of its own.

A command of ours hides nothing until the mesh confirms it, on the same evidence the spinner
uses: `absorb(..., pending: ...)` files it under `_pendingByTarget` instead of
`_confirmedByTarget`, so `hides` stays false while `pendingHides` turns true and fades the pin to
0.4 opacity. Dropping the pin outright would claim a removal nobody else has seen, and the send
may still fail. A command that is never confirmed leaves the pin faded, which is the truth;
deleting the command message undoes it. The two maps are independent, so a second command that
*is* confirmed removes the pin without waiting on the first.

**Wire form — the part that is easy to break.** A command must repeat the marker's label byte
for byte, or it matches nothing. Hence:

- `SharedMarkerDeletion.isMarkerPayload` (marker *or* command) keeps both out of MCMP and SMAZ
  in `prepareChannelOutboundText` / `prepareContactOutboundText`, which are also the
  normalisation and byte-estimation path — those must hand back a readable marker, not a
  container. On the **contact** side that is the whole story: neither `prepareContactOutboundText`
  nor `prepareContactOutboundTextAsync` will wrap a marker in anything, v3, v2 or SMAZ, and
  contacts have no binary transport to slip into either. Only the **channel** send path has an
  exception, the signed envelope described below.
- `SharedMarkerDeletion.isMarker` (marker only) gates cyr2lat, applied through
  `encodeLabel` to the **label alone**: coordinates and flags are structure, and a profile
  reaching them would make the message unparseable.
- A `del:` command takes **no** transform at all. Whoever sends it may not be the marker's
  author, and a different cyr2lat profile — or one that also maps Latin letters — would rewrite
  an already-transliterated label.
- Both chat screens transliterate composer text themselves before handing it to the connector;
  markers and commands are excluded there too, or a hand-typed `del:m:...|ттт|poi` would be
  rewritten whole.
- `sendMessage` / `sendChannelMessage` and both `schedule*Message` normalise a marker **before
  storing it**, not only before transmitting — otherwise the sender sees the typed Cyrillic
  label while receivers see the transliterated one, and a queued message would change shape when
  it finally goes out. Normalisation runs only for a first send (`pendingMessageId == null`):
  committing a queued or retried message re-uses text that was already normalised, and running
  the profile over it twice is exactly the rewrite described above.

**The signed envelope.** On a channel with MCMP v3 *and* signing on, a marker and its `del:`
command travel inside the v3 container instead of as plain text. Compression is incidental; the
signature is the point, since a channel post carries nothing but a display name and a plain
`del:` there lets anyone erase anyone's pin. `_isMcmpSignableText` takes `allowMarkerPayload`,
set from `channelMcmpUseSign`, and `ChannelBinaryDataHelper.tryEncodeOutbound` takes the same
flag — its default `false` also keeps a `del:` out of the *unsigned* binary MCMP
path it used to slip into, since its structured-payload guard only knew the bare `m:` prefix.

Two fallbacks keep it safe, both landing on plain text, which every client reads, and both live
in `sendChannelMessage`. A node that refuses to sign sends the marker plain rather than wrapping
it unsigned: an unsigned envelope costs bytes and proves nothing, while hiding the payload from
clients that cannot decode MCMP. And a wrapped marker that no longer fits its frame — Base91
gives back most of what the compressor won, and the signature costs 64 bytes on top — also goes
plain, instead of being refused by the length guard further down. `mcmpV3Sent` (not
`mcmpV3Applies`) is therefore what the stored message's MCMP metadata is keyed on, so a marker
that fell back cannot claim an envelope it lost.

The pin's info dialog repeats that provenance: `_MarkerSignature` carries the source message's
status onto `_SharedMarker`, `_buildInfoRow` gained a trailing slot, and the same
`McmpSignatureBadge` the bubble draws sits next to the author. It is keyed on the message rather
than on the marker, so a plain-text pin shows nothing at all, and `mcmpSignatureStatus` rides in
`markerSignature` so a manual re-check reaches the cached pin.

Contacts are excluded on purpose, both kinds. A direct message is authenticated by its ECDH
transport, and a room post carries the author's 4-byte key prefix (`fourByteRoomContactKey`,
attached by the server itself and shown beside the name in the chat), so an envelope there would
cost bytes and prove nothing the reader does not already have — only a channel post arrives with
nothing but a display name behind it. `allowMarkerPayload` therefore has exactly two call sites,
both in `sendChannelMessage`. Queued previews
(`schedule*Message`) are excluded too — they sign nothing, and a preview should not promise a
badge that only materialises at commit time.

**Waiting for the mesh.** `_SharedMarker.pendingDelivery` marks a pin of ours the mesh has not
confirmed, and draws an indeterminate `CircularProgressIndicator` around the circle. The evidence
differs by route and that is the only difference: a channel post waits for a repeat
(`repeatCount == 0`), a direct message or room post waits for its delivery receipt
(`status != MessageStatus.delivered`), because nobody acknowledges a broadcast. `failedDelivery`
is the third state and looks different rather than merely stopping — a send that gave up is
struck through with a rotated bar in `MapPalette.markerOutline`, the one shade already picked to
read against every colour in the pin palette. `repeatCount` and both `status` fields ride in
`markerSignature`: a repeat, a receipt and giving up change nothing else about a message, so
without them the cached pins would keep spinning.

Neither overlay may cost the pin any layout. Both are `Positioned` inside a
`Stack(clipBehavior: Clip.none)` whose only sizing child is the 36×36 circle — `Positioned`
never contributes to a `Stack`'s size — so the marker keeps exactly the footprint it had, and
the ring is free to reach 6px outside it. Painting outside the marker's own box is safe:
flutter_map puts each marker in a `Positioned` inside one viewport-wide `Stack`, which clips at
the viewport rather than per marker. Growing `Marker.height` or wrapping the circle in a larger
box instead is what broke marker rendering once already — the pin's own box is the thing to
leave alone.

**Hidden and removed locally.** `_hiddenMarkerIds` (session) and `_removedMarkerIds` (persisted
by `MapMarkerService`) are `Map<String, DateTime>`, not sets, and `_isLocallyDropped` compares
that moment against the marker's own. The reason is the same one that makes markers group into a
trail: `buildSharedMarkerKey` carries no position, so the same caption shared to the same place
later is the same id. As plain sets, removing one pin captioned `map_pointOfInterest` — the
default the share dialog offers — silently swallowed every future pin under that caption, with
no way back, since an invisible marker cannot be tapped to restore it. Bounding by time is the
rule `del:` commands already follow. Stored entries are `"<millis>|<id>"`; a bare id from before
this is **dropped** on load. Those were written under the old meaning — "hide this caption for
good" — and nothing records which pin was actually meant, so guessing a time would keep hiding
pins the user never chose to remove. Dropping them brings everything back, and removing one again
now behaves properly.

**Label budget.** `_maxMarkerLabelBytes` limits the pin caption at entry time: the channel
budget for this node (which already accounts for `"<name>: "`), capped by the user's outgoing
byte limit (which counts that prefix, so it is subtracted), less the marker scaffold, less
`SharedMarkerDeletion.prefix.length` — those four bytes are reserved so the author can later
send the same text back as a delete command without overflowing.

### Coordinates in message text

A message that is *only* `lat,lon` is still handled by `parseCoordinateText` (in `map_screen.dart`), which turns the whole bubble into one link. A pair written inside a sentence — "I'm at 45.0,38.9, see you" — is found by `helpers/coordinate_text.dart` instead and linked on its own, leaving the rest of the text alone. `CoordinateText.split` runs inside `widgets/formatted_message_text.dart`, on plain runs only, so a pair sitting in a URL query stays part of that link; `TranslatedMessageContent` routes text to that widget when `CoordinateText.has` is true, the same way it already does for mentions and markup.

The pattern is deliberately stricter than the whole-message one: both halves must carry a decimal point, or "1,5" written as a price and "steps 1,2" would read as coordinates. Out-of-range values are dropped after parsing, not by the pattern.

### Composer rebuilds
Anything in a chat composer that reacts to the text controller must go through `widgets/composer_text_builder.dart`, never a bare `ValueListenableBuilder`. A `TextEditingController` notifies on every value change, **selection included**, and dragging an Android selection handle changes the selection continuously — rebuilding the text field underneath the gesture makes the handle stutter badly enough to be unusable. `ComposerTextBuilder` rebuilds only when the text actually changes; `ByteCountedTextField` keeps its own listener with the same guard, plus a byte-count cache, because its encoder runs full MCMP compression over the message and that is far too expensive to repeat per pointer move. The count itself is taken `ByteCountedTextField.counterDelay` (250 ms, `countDelay` per field) after the last change of the text or of the encoder, every change restarting the wait and the last number staying on screen meanwhile: the screens create the encoder closure in `build` and the connector rebuilds them on every notification, so the field used to encode the same draft again per notification. The first count is immediate, so a restored draft never shows zero. A count that lags can neither cut nor pass a message wrongly, since the limiter encodes on every edit itself and the send path encodes on its own. `MarkupTextEditingController` caches its span tree for the same reason — `buildTextSpan` fires on every repaint, not just on rebuilds.

`Utf8LengthLimitingTextInputFormatter` (`helpers/utf8_length_limiter.dart`) is the input formatter behind every composer and name field: it measures the draft on the encoder's output when there is one and, when an edit does not fit, keeps the unchanged head and tail of the draft and as many whole graphemes of the insertion as fit. It finds that count by binary search, about log2(n) encodings for a paste of n graphemes plus the two that decide whether the edit fits at all; the walk grapheme by grapheme it replaced encoded the whole draft once per grapheme, 475 times and most of a second on a desktop for 260 Russian characters pasted into an MCOtxt channel. The search keeps only counts it has encoded and found fitting, so the result fits whatever the encoder does; for an encoder whose output can shrink as the text grows it may keep fewer graphemes than a longer fitting prefix would have, which is accepted. Flutter calls the formatter synchronously inside the edit, so it cannot be deferred; the counter under the field is a separate cost, memoised per text change.

### Bubble box

Both chats draw a bubble's box with `ChatBubbleBox` (`widgets/chat_bubble_box.dart`), not `AnimatedContainer`. A bubble's maximum width is a share of the window, and `AnimatedContainer` animates every property that changes, so each step of a window resize restarted a one-second width animation in every visible bubble and laid their text out again on every frame of it. `ChatBubbleBox` takes the same parameters and builds the same layout, but the width limit and the padding apply at once; only the decoration fades, which is all the search highlight and the failed-status colours need. An upstream merge that brings `AnimatedContainer` back into a bubble should keep the swap.

### Right-click on a message

On a desktop both chats open a message's action menu from the bubble's `onSecondaryTapUp`, and only there, with one exception. A plain body is a `SelectableText` (`LinkHandler.buildLinkifyText`, `SelectableLinkify`), which wins the right-click in the gesture arena, so the bubble never hears it; that body is handed the menu as `onSecondaryTap` and answers from a `Listener`. A formatted body (`FormattedMessageText`: markup, a mention, coordinates, or a reply drawn as a mention through `ReplyMentionText`) is a `Text.rich` that does not compete for the click, so the bubble's handler runs. It used to answer from a `Listener` of its own as well, and every such message opened two menus at once, most often seen on an outgoing message with a mention; `FormattedMessageText` and `ReplyMentionText` take no `onSecondaryTap` since (`test/widgets/message_right_click_test.dart`).

### List rows move by key

The contacts list and both chat transcripts put each row's key on the widget the item builder returns and pass `findChildIndexCallback`, backed by a key-to-index map built with the rows. Without the callback a sliver list matches rows by index only, so anything that shifts indices, a new message at the bottom of a reversed transcript, a deleted one, a re-sort of the contacts, made every visible row either take its neighbour's subtree through the message `GlobalKey` or be recreated from scratch, replaying the contacts' entrance animation. Keys stay unique: a repeated message id or contact key gets a numbered key. A key moved back inside the row, or a builder that loses the callback, brings the old cost back.

### Following the newest message

Both chats show their messages in a reversed list, pixel 0 being the newest,
and a rebuild used to end in `scrollToBottomIfAtBottom`
(`helpers/chat_scroll_controller.dart`): within 100 px of the bottom, an
`animateTo(0)`. Every rebuild did it, a relay heard, a reading, a reaction,
in the direct chat every notification of the connector, and `animateTo`
begins a new scroll activity, which disposes the drag under the reader's
finger or the fling they gave the list
(`ScrollPositionWithSingleContext.beginActivity`); at the bottom exactly
Flutter turns it into a `jumpTo`, which does the same. So a reader near the
bottom of a busy channel could not scroll away. Two rules now.
`followNewMessage(newest)` is what the screens call, with the id of the last
row: it snaps only when that id changed, a new message at the bottom, and
keeps the id whether or not it snapped, so a rebuild after the reader's own
scrolling snaps nothing (the channel screen passes `reversedRows.first.id`
from its post-frame callback, the direct chat
`reversedMessages.first.messageId` through `_scheduleAutoScrollIfNeeded`,
which still schedules once per `uiRevision`). And `scrollToBottomIfAtBottom`
never moves the list while `position.userScrollDirection` is not idle: a
drag or a wheel tick sets it and a fling keeps it, while the controller's own
animation never sets it, so a second new message during the first's
animation still lands at the bottom, where `isScrollingNotifier` would have
blocked it. A wheel tick is idle again at once, which is why the first rule,
not the second, is what lets a desktop reader scroll up through a stream of
relays (`test/helpers/chat_scroll_controller_test.dart`).

### Screens that read a little of the connector

Three screens used to watch the whole connector for a few of its values and
rebuild on every notification, up to twenty a second under live radio. The
discovery screen still watches it, its list changing with every advert, but
derives its rows once per change of their inputs: `discoveryRows`
(`helpers/discovery_list.dart`, the filtering and sorting the screen did
inline) goes through `LastValueMemo`, keyed on `discoveredRevision`,
`contactsRevision` (every change of the known keys comes with one of the
contact list, the two being changed together), the node's key, the query,
the filters and the set of nodes that answered the last discovery request,
by identity and size, since that set is a live view that grows while the
request runs, and the keys of the discovered list as that request went out.
A request sent from the screen splits the list in two (`discoverySections`):
above, the nodes that answered the latest one, a contact the node holds
among them, dimmed, since the request reached it; a rule labelled
`discoveredContacts_previouslyHeard` (en and ru); below, the list as it was
before the request, which never lists a contact the node holds and leaves
out a node first heard through its answer, so a node listed before that
answered again stands in both parts and one heard only through its answer
above alone. The rule shows only with something under it, and the split
stays until the screen is left. An answered card carries, under the key, how
the node heard our request (its SNR, the answer's second byte, behind an up
arrow) and how our radio heard its answer (SNR and RSSI off the companion's
push frame, behind a down arrow): `ZeroHopDeviceDiscovery.responderReadings`,
the first copy's, drawn by `signalReadingSpans` on the colour scale of a
channel bubble's hop list. The line-of-sight map rebuilt
its map, its terrain profile and
its panels for a banner showing the battery and the last SNR; it selects
those two, and the quick-switch bar's two unread counts, with
`context.select`, so it rebuilds when one of them changes. The neighbours
screen selects the repeater's name and routing and the spreading factor its
readings are scaled by, the fields rather than the contact, since
`Contact ==` compares keys alone and would miss a new route
(`test/helpers/discovery_list_test.dart`,
`test/screens/discovery_screen_test.dart`,
`test/screens/line_of_sight_banner_test.dart`).

### Keys cut in the middle

`MiddleEllipsisText` (`widgets/middle_ellipsis_text.dart`) shows public keys in the contacts and discovery lists and needs a monospace style. It computes the cut from the width of one character cell instead of laying out candidate strings. The cell is measured once per effective style and text scaler and shared by every instance; the text scaler is where the app's DPI setting (`uiScale`) lands, on top of the system font size. Measuring without it, as the widget once did, under-measures whenever either is above 100%, and the key then loses its tail instead of its middle.

### MCO image codec (image/GIF over LoRa)
Bespoke ultra-compressed raster format so tiny images fit LoRa text/binary messages. `helpers/mcoimg_codec.dart` (v1/v2, text prefix `im:`) and `helpers/mcoimg_v3_codec.dart` (binary container) quantize to fixed/dynamic palettes (`mcoimg_palette.dart`, `mcoimg_dynamic_palettes.dart`, up to 512 colors) and brute-force many encoders, keeping the smallest. Because the transmitted image is degraded, `services/mco_image_pack_originals.dart` keeps a hash→ordered-candidate index of installed `.mcoimg.pack` sets and renders a matching high-quality original in priority order: `.lottie.json`, `.lottie`, `.webp`, `.png`, `.gif`, `.jpg`, `.jpeg`. Invalid candidates fall through to the next format and finally to decoded MCOimg. Lottie and animated raster originals pause outside the viewport. Compose/send in `canvas_editor_screen.dart`; manage in `mco_image_gallery_screen.dart`. Channel image payloads go through `helpers/channel_binary_data_helper.dart` (`ChannelBinaryDataKind { mcoImage, mcoImageV3, mcoImageV4, mcmp, mcotxt }`). A direct or room chat has no binary transport, so an image travels there as text (`im:`, `im3:` or `im4:` plus Base91) under the text budget, and the editor offers every version it can encode, v4 included, wherever it is opened.

A v4 figure can also be **text** (`MCOImageV4Text`, extended sub-opcode `15` used as a second escape, command `0`). The glyphs are not transmitted: the string travels as an MCOtxt v1 stream embedded bit by bit after its bit count, and only the anchor, the area width in cells and the em height in cells are normative — rendering is up to the client, so the app pins its own through `MCOImageV4TextRendering` in `widgets/mco_image_v4_view.dart`. Alignment and font size are sticky across text figures the way style is, the area width is per figure and its default (anchor to the right canvas edge) costs no bits. In the editor that width is a cell count pinned to the layer: the slider runs in cells over the whole canvas width, moving a layer never changes it, and a default-width layer has its width pinned on its first horizontal move so the text does not re-wrap; crops and resizes clamp text widths and em heights to what the codec accepts. The editor tool lays an ordinary `TextField` over the canvas, scaled from canvas cells so it breaks lines exactly where the painter will, keeps the layer in the document while typing so the payload counter counts it, and hides that one layer from the painter meanwhile. Wire format in [`docs/mcoimg_v4_reference.md`](docs/mcoimg_v4_reference.md), fixed at tag `9.5.1-mod-1.9.0`; the JavaScript and C++ ports, and the steps that have to come first, are planned in [`docs/mcoimg_v4_porting_plan.md`](docs/mcoimg_v4_porting_plan.md).

### AEIC image store: pictures are paged in lazily

`ReceivedImageStore.load()` deliberately restores sizes, not bytes — reattaching a few hundred
images must not read tens of MB of PNG on the startup path — so an entry comes back with
`pngStored` / `receiverPreviewStored` re-derived from the files actually on disk and both byte
slots null. `ensurePng` and `ensureReceiverPreview` read them back on demand. It writes a
sidecar back only when that repair changed the record: rewriting every one, each a flushed
write and a rename, held a Windows launch about half a second an image where an antivirus
watched the writes of a new executable (`test/services/received_image_store_test.dart`).

An outgoing entry has **two** pictures: the sender's own 512×512 crop in the PNG slot (written
by `registerOutgoing`; it is the backdrop of the placeholder and what a tap on the
reconstruction opens) and its own decode in `receiverPreviewPng`. It stays in `reassembled`
rather than `decoded` — `decoded` would name the wrong picture — and the renderer keys off the
preview's presence.

**Never write back a snapshot taken before an await.** `_storeSync` replaces the record whole
rather than merging fields, so a `copyWith` built on a pre-await snapshot silently reverts
whatever landed while it was on disk. The bubble asks for both pictures at once and awaits
neither, so the two loaders overlap on every restart: whichever finished second used to reset
the other's bytes to null, which showed up either as a tap opening the reconstruction instead of
the original or as a bubble stuck on the decoding spinner. Both loaders — and the outgoing
decode branch, around its own preview write — re-read `_entries[streamId]` after the await and
build the update from that. A test in `test/services/received_image_store_test.dart` pins it.

`registerOutgoing` takes the `aspectCode` the send path already computes for the wire. Without
it our own entry defaults to 1:1 and the sender is the one person seeing their own photo
squashed into a square: the stored crop is the stretched square every recipient also gets, so
the bubble has to undo the stretch exactly the way theirs does.

It also takes the region label the send was scoped with (`region` / `regionInfoAvailable`,
resolved by `MeshCoreConnector.outgoingChannelRegionLabel` — the channel's region, else the
node's default scope — exactly as a text message's label is), so an image bubble can carry the
same region line under `showMessageRegion`. An incoming image cannot: its `CHANNEL_DATA_RECV`
chunk frames hold neither a path nor a scope, so it reads as unknown rather than borrowing the
channel's region. The scope on the wire is applied for images identically to text —
`sendImageChunks` wraps the whole burst in `_runScopedChannelSend`, so every chunk of one image
goes out under one scope and no other channel send can slip in between them.

The chunk layout follows the parity toggle in the send preview (`imageChunkDataSizes`). With
parity every chunk but the last is full: a contract with every shipped receiver, whose parity
recovery refuses to rebuild a short chunk that is not the last one. Without parity the same
number of chunks shares the bytes evenly, so a two-chunk image's packets both stay short enough
for the companion's RX log to carry the repeater's echo. Reassembly concatenates by index, so old
receivers take either layout; only the parity path cares.

An image is not stored inside the message it arrived with — the message holds only a sentinel — so
clearing a conversation has to reach this store separately, or the bytes stay on disk with nothing
left pointing at them. An entry belongs to a channel by `channelId`, the `Channel.storageId` of the
slot it arrived on (`ImageStreamReassembler` resolves it through `channelIdForSlot`) or was sent to
(`registerOutgoing`), not by the slot: another app may move a channel, and another channel may take
the slot. The chat lists `entriesForChannelIds` for the IDs of the channel's identity group (see
**Channel identity**), plus the unstamped entries of its slot, those written before the IDs existed;
a completed channel sync stamps such entries once with the ID of the channel their slot holds now
(`stampLegacyChannelIds`; the store is app-wide, so the first node synced claims them), and a sync
that finds another PSK in a slot drops its in-progress streams (`ImageReassembler.clearChannel`,
`forgetChannelSlot`). The connector holds three callbacks wired in `main()`, null when the build has
no image codec: `_deleteImagesForChannel(slot, channelIds)`, called from both places a channel's
history ends, deleting the channel and clearing its messages, which main answers with
`deleteImagesForChannelIds` and the unstamped-only `deleteImagesForChannel(slot)`;
`_stampImageChannelIds`; `_forgetImageSlot`. Single-message deletion
does not currently invoke AEIC cleanup: `deleteImageForSentinel` can parse the stream id back out of
the message text, but that helper is not wired into the connector's individual-message delete path.

### Wardriving (coverage mapping)
Turns the app into a mesh coverage scanner (`services/wardrive_service.dart`, driven from `map_screen.dart` / `widgets/wardrive_status_panel.dart`). Each cycle (default 25 s, 5–300 s configurable) takes a GPS fix, sends a zero-hop discovery request, and listens ~10 s for `DiscoverResp` frames; each responder → a GPS-tagged `WardriveSample` (SNR/RSSI/node key/response time), plus `pingSuccess=false` "dead zone" samples when nobody answers. `wardrive_upload_service.dart` POSTs sample batches as JSON to configurable sites (default `https://meshwar-map.pages.dev/api/samples`), de-duping per endpoint. `wardrive_foreground_service.dart` runs an Android **location** foreground service (MethodChannel `mco_advanced/wardrive_foreground`), gated in Dart so ordinary BLE users don't inherit location FGS.

Background wardriving (`map_wardriveInBackground`, Android only) needs five things the phone may refuse: the notification permission, location services on, location allowed all the time, background activity not restricted, and the battery optimization exemption (`WardriveBackgroundRequirement`, `helpers/wardrive_background_requirements.dart`; on Android 13 and newer the last two are one three-way battery setting, unrestricted, optimized or restricted, and `ActivityManager.isBackgroundRestricted` is checked beside `PowerManager.isIgnoringBatteryOptimizations` for the 9 to 12 phones that keep them as two switches, the restriction opening the app's own settings page). Turning the option on checks them and, with one missing, asks for that one alone: the runtime prompt where Android has one, else its system screen, waited out until the app comes back (`WardriveForegroundService.requestAndroidRequirement`); the option stays off while anything is missing, a snackbar names what (`map_wardriveBackgroundNeeds`), and the next tap asks for the next missing requirement in order, round the end, so a screen the user backed out of is not the only one offered (`nextWardriveBackgroundRequirement`). No system screen opens by itself; the loop that walked every screen in turn (`ensureAndroidRequirements`, until 2026-10-09) is gone. A session started with the option on checks the requirements without asking, and a permission revoked meanwhile turns the option off, the session running in the foreground and the panel naming the requirement (`backgroundRequirementMissing`, `map_wardriveBackgroundOff`) (`test/helpers/wardrive_background_requirements_test.dart`).

### Region / flood-scope routing
Channels can be tagged with a named region; `cmdSetFloodScope` (54) / `cmdSetDefaultFloodScope` (63) hash `#<name>` (SHA-256, first 16 bytes) into a scope. Managed in `region_management_screen.dart`; persisted in `region_store` / `channel_region_store`.

A channel can also be set to *no region*: `kUnscopedRegion` (`'!unscoped'`, `region_store.dart`, upstream's marker) stored in the channel's region slot, which `getChannelRegion` answers `''` for, so a share link, a label or `outgoingChannelRegionLabel` never treat it as a region, while `isChannelExplicitlyUnscoped` tells it apart. Its floods go out under no scope at all, the node's default scope included: `_runScopedChannelSend` sends CMD_SET_FLOOD_SCOPE sub-command 1 for it through `_sendFloodUnscopedFrame`, the same probe the contact's flood choice uses (the first refusal sets `_unscopedSendUnsupported` for the connection, and the send falls back to the bare clear, which puts the default scope back). The picker's row (`_RegionSelectDialog`, the first row of its list, worded and drawn like the region rows and like the contact picker's since 2026-10-14) shows on firmware 12+ only (`supportsExplicitUnscopedFlood`), and the channels list and the chat's app bar label the channel *no region* while the firmware takes the flag, else with the node's default scope, read through `channelUsesRadioDefaultScope` (the `channels_regionRadioDefaultSuffix` that followed it went on 2026-10-14; the key stays for the other locales). The contact's own choice keeps its `*` marker (`ContactRegionStore.unscoped`), a different store.

A channel send carries no region in its command: `_runScopedChannelSend` sets the scope override (54 with the key, or 54 without one for an unscoped channel, so nothing another client left behind leaks into the packet), sends, waits for the node's `RESP_CODE_OK`, which it writes only after building the packet with the scope's transport code (`Mesh::sendFlood`), and clears the override; all of it under `_runChannelCommandLocked`, the scope being one field on the node. A channel send is never answered with `RESP_CODE_SENT`, in stock firmware or the South Edition, and meshcore_py waits for OK as well. Channel text and reactions once waited for SENT, a leftover of an upstream branch, and so held the lock and the scope for the full five-second timeout on every message, while direct messages and repeater commands queued behind them. The same belief had `_handleMessageSent` give an unclaimed SENT to the oldest pending channel message; it answers a login, a request or a CLI command (whose SENT carries a zero hash), so the message was marked sent before it went out and left out of the replay after a reconnect. An unclaimed SENT is now ignored, as upstream does too.

A contact can carry a flood choice of its own (`ContactRegionStore`, `getContactRegion` / `setContactRegion`): a region, or `ContactRegionStore.unscoped` (`*`), no scope at all. It is chosen from the line the direct chat's app bar shows under the route line whenever a send would go by flood, forced or automatic with no route; the picker (`widgets/contact_region_dialog.dart`) lists *no region* first, then the known regions, and its clear action drops the contact's choice so the node's default scope applies again. Every attempt the retry service makes goes through `_sendMessageDirect` under the same lock, so a direct send never falls inside a channel's scoped window nor a channel send inside a direct one. A flood attempt to a contact with a choice opens a window of its own (`_sendScopedContactFrame`): 54 with the region's key, or 54 sub-command 1 for unscoped (`buildSetFloodUnscopedFrame`, firmware 12+; older firmware answers `ERR_CODE_UNSUPPORTED_CMD`, which is logged once and sends every unscoped attempt under the default scope until the connection ends, while any other failure fails the attempt as a region's scope command does), then the frame, `RESP_CODE_SENT`, and 54 sub-command 0, which clears the key and the unscoped flag alike. Without a choice the app sends nothing extra and the node stamps its default scope. A room login, a repeater login, a status, telemetry or neighbour request and every CLI command to a repeater (the settings and console screens, the settings' danger zone, the clock sync after a login) take the same road through `sendContactFrame(contact, frame, useFlood:)`, with the routing their screen prepared through `preparePathForContactSend`; the firmware floods them exactly as it floods a text message (`sendLogin` / `sendRequest` / `sendCommandData` end in `sendFloodScoped(recipient)`) and answers them with `RESP_CODE_SENT` too, so the line shows for a room server as well. The CLI commands and the telemetry and neighbour requests used to go out through a bare `sendFrame`: by flood they took the node's default scope while the login before them took the contact's region, and one written while a channel's window stood open took that channel's. Under the lock a command now waits for a channel send in progress, its radio-quiet wait included. `sendContactFrame` rethrows a failure as `sendFrame` does, so a screen reports a send that did not happen instead of waiting out a reply; only the telemetry request to the node itself stays on `sendFrame`, since it never leaves the node. Room posts flood like any other direct message: the retry service's `_roomPostPathWithoutFlood` guard of 2026-09-18, which turned a flood choice for a room into the known route or a zero-hop direct send, was removed on 2026-09-26 once posts could carry a region. What it spared is accepted now: the firmware floods only a contact with no route, so a flood attempt erases the node's route to the room, and until the room's next path return the node acknowledges the room's pushes by flood (`sendAckTo`). The node's own ACKs and path returns for what it receives from that contact still go under its default scope, out of the app's reach. The picker paints a tile's colour through its own `Material` inside a `ClipRect`: `tileColor` is ink on the nearest Material, which a scrolled-away tile otherwise keeps showing under the bar.

### DirectRepeater last-hop path selection
`DirectRepeater` (top of `meshcore_connector.dart`) tracks the ≤5 best last-hop repeaters ranked by SNR + recency (stale after 30 min), built from advert path tails and repeater-ACK trip-times (fed to `PathHistoryService`). It feeds the app bar's signal readout (`widgets/snr_indicator.dart`) and the quality labels of the routing sheet. Related: **path-hash mode** (`cmdSetPathHashMode`, modes 0–2 for 1–3 bytes per hop; the firmware refuses 3, so `setPathHashMode` and the DEVICE_INFO parse clamp to that range).

Both repeater lists (`directRepeaters` from adverts, `activeRepeaters` from every relayed packet in the RX log) change on every copy of everything the radio hears, so they publish through `repeaterActivity`, a `ValueNotifier<int>` bumped by `_recordRepeaterActivity` and `_updateDirectRepeater`, not through `notifyListeners()`: the two SNR indicators and the routing sheet listen to it themselves, and a relay no longer rebuilds every listener of the connector for a signal-strength number. A copy of an advert that changes nothing about a stored contact (name, position, `lastSeen`) neither replaces it nor bumps `contactsRevision`; the same rule in `_handleDiscovery` keeps an identical copy from rewriting the discovered entry and its store. A real change still replaces the contact and notifies. The per-packet scans compare bytes (`helpers/key_prefix_match.dart`: `keyStartsWith` on public keys, `hexStartsWith` on stored hex keys, both case-insensitive where hex is involved) and walk `_contacts` and `_discoveredContacts` in place instead of building `allContacts`, and `selfPublicKeyHex` is computed once when the key is set (`_setSelfPublicKey`), never per candidate.

**Path histories load lazily, and the map never loads from `build`.** `PathHistoryService.getRecentPaths` reads the cache and, on a miss, loads the history and reports through `notifyListeners()` once a history read for the first time in the node's session turns out non-empty, so a send attempt or the routing sheet that read too early sees it on the next look; a history evicted and read again is not reported (`_loadedOnce`). `version` moves on every change, `routesVersion` only when the set of routes changes: a route added, removed or cleared, a first load, a node switch, not the statistics an advert copy or a delivery refreshes. The map's guessed positions (`_computeGuessedLocations`) read `peekRecentPaths`, which never loads and returns null for a history not cached, key their cache on `routesVersion`, and hand the missing histories to `ensureLoaded` after the frame, one batch that reports at most once. Before, the read from `build` started a load per candidate and every load reported, and with more candidates than the cache held (50) the LRU evicted and reloaded histories on every frame, forever. The cache holds `maxCachedContacts` (1000) now, and a candidate set larger than that settles as well, with the evicted histories missing from that pass.

**A route the user pinned outranks every automatic decision.** `Contact.pathOverride` (null = auto, `-1` = force flood, `>= 0` = manual hop count, with `pathOverrideBytes`) is checked by all three places that can change a path on their own: `resolvePathSelection` returns it before it looks at anything else, including `forceFlood`; `MessageRetryService._plannedRoute` takes it before any automatic choice; and the `clearPathOnMaxRetry` cleanup in `_handleTimeout` skips too, because it would otherwise send `CMD_RESET_PATH` (`0x0D`) to the node and drop a hand-picked route to flood behind the user's back. Forcing flood counts as a choice as much as picking hops does, so any non-null override stops all three — none of them distinguish `-1`.

The override survives everything the node says about the contact. `_handleContact` and `_handleContactAdvert` both carry it across when a contact is re-read from the radio, and `clearContactPath` wipes only the device path. That matters because the node changes routes on its own and announces it with `PUSH_CODE_PATH_UPDATED` (`0x81`); `_handlePathUpdated` answers by re-reading that one contact, so `contact.path` follows the node while `pathOverride` stays the user's. A hand-picked path is written to the node when it is chosen, a forced flood only at the next send, and every send writes the override again — between sends the node runs on whatever it decided. Only two paths drop an override, both explicit: `setPathOverride(pathLen: null)` (the "auto" choice) and `deleteAllPaths()` behind its confirm dialog.

**Without an override the route is the node's.** `contact.path` and `pathLength` mirror the route the node keeps for the contact, and they change only when the node reports the contact or the app writes a route itself. An overheard advert is neither: the node never changes a route on one (`BaseChatMesh::onAdvertRecv`), while the RX log hands over every copy of it, relayed or heard directly. `_handlePayloadAdvertReceived` used to write each copy's path into the contact, so the last copy heard became the route the contact was shown with, a copy with no path turned a direct route into a flood, and the next send put that route on the node. It now updates the name, the position and the last-seen time, feeds `DirectRepeater`, and offers the advert's path to the path history, where the routing sheet lists it and a direct message may rotate to it. In that list a record with no bytes and no hops is the direct route, pinned like any other as a manual override of 0 hops; it used to be greyed out with every record lacking bytes, although only one with hops and no bytes, an older record that never stored its route, has nothing to set.

**Each contact keeps its own hash width.** `Contact.pathHashWidth` is the width its route was learned in, read from the packed path byte of the contact frame, persisted by `contact_store` and `contact_discovery_store`, and inferred as bytes ÷ hops where only a path is at hand (`Contact.inferPathHashWidth`). A route written back to the node is packed by `_encodePathLenForWidth` in that width, not in the node's current mode, which may have changed since; the chat header's hop split and the map's repeater guesses read it too. The same `CMD_ADD_UPDATE_CONTACT` carries `last_advert`, which the firmware keeps as the contact's replay guard and eviction order: `buildUpdateContactPathFrame` sends the contact's own advert time (`_deviceLastAdvert`, 0 when unknown) where it used to send the phone's clock, which made every genuine advert of the contact look replayed while the phone ran ahead of its sender, and every route write is one of those. Whatever puts a contact into memory without an advert keeps the rule: `addOrUpdateSharedContact` stores the advert time it sent, not `DateTime.now()`, since the next path write reads it back.

Rotation stays with direct messages (see **Routing the attempts of a direct message**). `preparePathForContactSend` prepares a login (repeater and room), a status, telemetry or neighbour request and every CLI command, the repeater settings screen's included, and takes the override, else the node's route, which is the route the login dialog shows as "use saved path". With rotation it had put a path from the history on the node for each of those requests, the next path each time and never a direct one, since `_getRankedPaths` drops empty paths: a repeater shown as direct was logged into over a stale hop, and each command of a settings refresh went its own way. The repeater hub reads the contact back from the connector (`getContactByPubKeyHex`) rather than keeping the copy it was opened with, so its header shows the route as it is now and not as it was when the login dialog opened.

A retry sees the choice as it is at that moment, not as it was when the message was queued: `_attemptSend` re-reads the contact through `RetryServiceConfig.findContact` (the connector's `getContactByPubKeyHex`) before resolving the attempt's path, so a route pinned, changed or cleared between attempts, flood to a route or one route to another, is what the retry takes. The queued `Contact` was a snapshot, and resolving from it also wrote its stale flags and name back to the node with the path update.

Both sides log to `AppDebugLogService` (through `appLogger`, tag `Connector`), because a path that simply vanished says nothing about who dropped it: `clearContactPath` announces the reset the app sends, `_handlePathUpdated` announces the one the node reports, and the `Refreshing contact …` line that follows carries the new device path. Keep the pair symmetric — a reset logged on one side only is worse than neither, since silence then reads as evidence.

### Routing the attempts of a direct message

Every attempt of a direct message or a room post takes its route when it starts (`MessageRetryService._plannedRoute`), from the contact as the connector holds it at that moment. The user's choice comes first and works as it always did: a forced flood floods every attempt and clears the node's route before each, since the recipient's answer to the previous one left a route there, and a pinned route goes out on every attempt, the last included, written to the node before each. Without a choice the route is the node's own:

- **No route**, which the chat header shows as *Flood (авто)* and «Забыть маршрут» in the routing sheet leads to: every attempt floods, with no `CMD_RESET_PATH`, there being nothing to clear, and with no route from the history, whatever it holds, until the recipient's answer gives the node a route. The next attempt takes that one.
- **A route**: the first attempt goes by it. Once it went unanswered, `autoRouteRotationEnabled` (the «Автоматическое переключение маршрутов» switch) moves the next attempts to the path history, each written to the node before its attempt: `PathHistoryService.selectPathForAttempt` offers the best ranked route not taken in the last two attempts, and the best one again when none is left. With the switch off the attempts stay on the node's route. The switch is off by default since 2026-09-29, where it used to be on; a stored value wins, and the settings JSON holds every field once any setting was saved, so only an install that never saved its settings follows the new default. The number of attempts («Максимальное количество повторных попыток», `maxMessageRetries`) sits above the switch in app settings rather than among its sub-options, every mode making that many attempts; the route weights stay under the switch, serving the history's ranking.
- **The last attempt**, the last that will be made (the fourth for a text over 158 bytes, see **Direct send failures**), is an auto-flood: the node's route is cleared and the attempt floods, so the recipient's answer brings a fresh route.

The node's own route is never written back before an attempt. The node sends by it anyway, every `CMD_ADD_UPDATE_CONTACT` makes the node save its whole contact table five seconds later (`dirty_contacts_expiry`), and a write could put back a route the node had just replaced with the one the recipient returned. The writes left are the pin, a route from the history and the clears. Before, the rotation started on the first attempt, where the node's route counted for no more than any other, the *Flood (авто)* state went to the history from the second attempt once the history had loaded, and the flood came only as the fifth attempt, which a long text never reaches. The pick waits for the history now (`_selectAutoPathForAttempt` awaits `ensureLoaded`), because `getRecentPaths` answers a history not read yet with an empty list.

A route the recipient returns is credited in the history as having just worked: `_handlePathUpdated` re-reads the contact through `_fetchContactSnapshotFromDevice` and hands its route to `_recordPathResult` as a success, the answer having come along the route our packet took. The node pushes PATH_UPDATED and, right after it, SEND_CONFIRMED for the acknowledgement the answer carried, and the re-read returns after both, so the flood attribution `_recordPathResult` gives at the acknowledgement always found the contact still without the route. Moving a pin to the route the recipient returned was considered and left out: the node keeps the last good route itself, and the app would be steering it (`test/services/direct_route_attempts_test.dart`, `test/connector/returned_route_test.dart`).

### The route a direct message was delivered along

An outgoing direct message or room post keeps the route its delivery was
confirmed along (`Message.deliveryPathBytes`, hops of
`deliveryPathHashWidth` bytes from our end; empty for a delivery without
repeaters, null while no acknowledgement named one; persisted by
`message_store`), apart from `pathBytes`, which follow the latest attempt.
The two differ whenever the acknowledged attempt is not the latest one:
attempt k went by route A and its acknowledgement came after attempt k+1 had
gone out by route B. Every attempt has an ACK hash of its own, the firmware
hashing the timestamp, the attempt byte and the text, and the retry service
keeps the route of each attempt under its hash from the moment the attempt
is made (`_expectedAttempts`, then `AckHashMapping` once RESP_CODE_SENT
confirmed the hash, the node's `is_flood` byte overriding the plan), so
`handleAckReceived` reports which attempt a PUSH_CODE_SEND_CONFIRMED answered
(`AcknowledgedAttempt`) and the connector's `_recordDeliveryRoute` writes the
route. Which route depends on the acknowledgement's carrier. A flood is
answered with a path return, the path our packet took with the ACK inside
it: the node stores the path, pushes PUSH_CODE_PATH_UPDATED and, in the next
frame, PUSH_CODE_SEND_CONFIRMED (`onContactPathRecv`), and the app learns the
path from the contact re-read the push starts. `_handlePathUpdated` keeps
that re-read with the frame's number (`_lastReturnedRoute`,
`_companionFrameSequence`), and an acknowledgement in the frame right after
it takes the route the re-read brings back. A bare acknowledgement answers
an attempt sent along a route, and the route recorded is that attempt's,
never the contact's current one, which may be a later attempt's. A send
stopped by hand keeps its attempts' routes in `_stoppedSendAcks` for the
same purpose, and `_updateMessage` keeps a stored route the retry service's
copy lacks. When nothing can be read, the message keeps no route rather than
a guess. The firmware hashes only the two low bits of the attempt number, so
attempts k and k+4 share a hash, and the retry service keeps every attempt
sent under a hash, newest first. The carrier tells the usual pair apart, the
first attempt from the auto-flood last one. Two routed attempts four apart,
which rotation can produce from the sixth attempt on, are told apart by the
acknowledgement packet itself: a bare ACK travels in the clear, six bytes,
the hash and then the attempt number the recipient copied from behind the
text of our packet, where the firmware writes it from the fifth attempt on
(before that the byte is padding), and the node logs the packet
(PUSH_CODE_LOG_RX_DATA) in the frame right before PUSH_CODE_SEND_CONFIRMED.
`_handleLogRxData` keeps that byte for one frame (`_lastHeardAck`), and
`MessageRetryService.acknowledgedAttemptIndex` picks the attempt: a byte of
four or more names it, a smaller one means one of the first four, and no
byte, or one naming no attempt sent, leaves the newest. An acknowledgement
inside a path return is encrypted, but a flood needs no attempt. A South
Edition node that sends a direct message transformed (`cyr2lat.contacts`,
`mcotxt.send.dm`) reports in RESP_CODE_SENT and PUSH_CODE_SEND_CONFIRMED the
hash of the text the app handed over, since the app computes that one
itself, while the acknowledgement on the air names the text that went out;
the two then differ, the RX-log acknowledgement is not paired, and the newest
attempt is taken (firmware `helpers/TextMessageAck`, 2026-10-09; before
that fix no delivery of a transformed message was ever confirmed in the app)
(`test/services/direct_route_attempts_test.dart`,
`test/connector/delivery_route_test.dart`).

The path screen shows the route for an outgoing message under a header of
its own right after the message details (`showDeliveryPath`,
`deliveryPathBytes` and `deliveryPathHashWidth` on `ChannelMessagePathScreen`,
handed over by the direct chat's `_openMessagePath`): the hops as the
repeater-hops section draws them, with a map button in the header that opens
the map on that route alone; a line for a delivery without repeaters; and a
placeholder while no acknowledgement named a route, which also covers a
delivery whose route could not be read. The repeater-hops section below it
keeps showing the message's own path, the latest attempt's. An incoming
message and a channel message get no section
(`test/screens/channel_message_path_screen_test.dart`).

### Air activity dot

Энергосбережение выбирается в настройках приложения через `PowerSavingSettingsTile`
и `PowerSavingScreen`. `models/power_saving_settings.dart` хранит профиль и отдельные
пользовательские параметры в JSON `power_saving`. «Выключено» — фиксированный
исходный профиль для сравнения, выбранный по умолчанию. Каждый новый параметр
обязан сохранять в нём поведение до работ по энергосбережению; свои значения
и готовые энергопрофили не меняют его. Исходные свои настройки также сохраняют
прежнее поведение. Слайдер скрытого экрана радиостатистики:
1–60 с, запросы готовых профилей 15/30/60 с. `helpers/radio_stats_screen_polling.dart`
координирует интервалы экранов по маршруту, Flutter lifecycle и существующему
нативному сигналу iOS из `ios_presentation_guard.dart`. Видимый экран использует
1 с; незавершённая отправка сохраняет этот интервал, пока экран смонтирован.
Другие владельцы учитываются через read-only `radioStatsPollingOwners`.
Отдельный флаг `pauseHiddenRadioIndicator` управляет приостановкой опроса
невидимого индикатора: настройки скрытия, маршрут, TickerMode, активность приложения,
подключение и поддержка статистики учитываются в `helpers/radio_stats_indicator_polling.dart`.
В готовых энергопрофилях флаг включён, в исходных своих настройках выключен.
При его включении `helpers/radio_stats_send_polling.dart` удерживает опрос в коннекторе
независимо от виджетов: подготовка/подпись, отложенные отправки, повторы, очередь
канального ответа и hop-проверки. Входы `sendMessage`/`sendChannelMessage` обёрнуты
счётчиком операций с освобождением в finally; `markNotifyDirty` обновляет удержание
до отложенного UI notify. Read-only `MessageRetryService.pendingMessageCount`
сообщает о добавлении/очистке повторов, включая истечение окна позднего ACK;
очистка канального ответа также синхронизирует удержание. Без экрана статистики
сохраняется обычный интервал 30 с. При отключённом флаге дополнительного владельца нет.
Смена профиля не затирает свои значения; слайдер сохраняется после отпускания.
Отдельные слайдеры `batteryIntervalSeconds` (120–600 с) и `gpsIntervalSeconds`
(60–600 с) имеют шаг 60 с и действуют на экране и в фоне. Минимумы и исходные
значения равны прежним периодам 120/60 с. Готовые профили задают 180/120,
300/300 и 600/600 с; это стартовые значения, не результаты измерений.
`helpers/device_polling_intervals.dart` связывает порог watchdog с периодом
батареи: два периода плюс прежние 60 с проверки. `_syncPowerSavingSettings`
перезапускает только соответствующий активный таймер, не запускает выключенный
GPS и начинает новое окно тишины при изменении периода батареи. Чужие настройки
не сдвигают расписание. Ручные/начальные запросы, запрет APP_START при загрузке
контактов, защита watchdog после сна и предел восстановлений сохранены.
Четыре числовых параметра используют `widgets/power_saving_interval_card.dart`
с локальным состоянием перетаскивания и единственным сохранением после отпускания.
JSON новых периодов нормализуется к допустимым минутным шагам; старые настройки
получают минимумы. Форматы пакетов, сроки ACK/повторов и фоновые транспорты не меняются.
Нативная активность имеет Flutter fallback и не меняет защиту вывода кадров.
Флаг `pauseIdleImageCleanup` отключает пустой таймер очистки изображений;
в готовых энергопрофилях включён, в Off и исходных своих настройках выключен.
`helpers/image_reassembly_maintenance.dart` содержит `MaintainedImageReassembler`
и привязку `ImageReassemblyMaintenance` к настройкам/жизни app state в main.dart.
Сборщик приложения наследует этот helper, а формат и алгоритм сборки остаются
в `services/image_chunk_transport.dart`. Таймер нужен при pendingCount > 0 ИЛИ
completedCount > 0; во время работы сохраняет период 5 с. TTL остаётся 60 с
от первого чанка для сборки и от завершения для кэша поздних дубликатов.
Вложенные вызовы addChunk/evictExpired и callbacks ошибок сверяются после всей
операции; новый поток из callback не теряет обслуживание. Очистка канала/сессии
обновляет таймер; посторонняя настройка не сбрасывает его фазу. При уничтожении
app state снимается listener и останавливается таймер, поздние чанки его не запускают.
Управление не зависит от lifecycle/видимости UI; исполнение при suspension определяет ОС.
Отдельный `pauseHiddenGifs` управляет показом GIF-ссылок через `helpers/gif_playback.dart`;
ручная пауза сохраняется независимо от видимости. Подробности — в разделе GIF cache ниже.
Слайдер `uiNotificationIntervalMilliseconds` задаёт окно общих уведомлений
50–1000 мс с шагом 50 мс; Off/исходные свои — 50, готовые профили — 100/250/500 мс.
`helpers/ui_notification_batcher.dart` объединяет события от первого mark,
не переносит deadline при непрерывном потоке и не держит таймер в простое.
Снимок состояния подключения в коннекторе включает state/transport, публичные
`isConnected`/`supportsCompanionRadioStats`, ручной разрыв,
восстановление, restart, offline, идентичность ноды и готовность сессии: изменения
сохраняют срок до 50 мс или уже более ранний обычный deadline. Оба одноразовых
таймера снимаются при flush/dispose, reentrant mark начинает следующее окно.
Уменьшение интервала выдаёт накопленное асинхронно без нового ожидания;
увеличение относится к следующему окну, посторонние настройки не сдвигают его.
`uiRevision` увеличивается при фактическом общем notify. Поток кадров,
radio/repeater notifiers и синхронизация владельца отправки не ждут UI-окна.
Общий слайдер умеет подписи секунд и миллисекунд; сохраняет значение после отпускания.
Восьмой параметр `deferBleLogDescriptions` / JSON `defer_ble_log_descriptions`
выключен в Off/исходных своих/старом JSON и включён в трёх готовых энергопрофилях.
`helpers/ble_log_power_settings.dart` применяет выбранное значение к общему
BleDebugLogService при создании app state и изменении настроек; dispose снимает
только свою подписку. Накопленные записи не перестраиваются и не теряются.
Уведомления, timestamp, оба лимита 500 и формат текста сохраняются; нового таймера нет.
Девятый параметр `reduceBlePluginLogs` / JSON `reduce_ble_plugin_logs` —
отдельный false по умолчанию в Off/своих/старом JSON, true в готовых энергопрофилях.
`helpers/ble_plugin_log_power_settings.dart` живёт в app state и на Android/iOS/macOS
запрашивает `FlutterBluePlus.setLogLevel(warning)` при true, `debug` при false.
Исходный Off с уже установленным debug не вызывает API. Windows native setter —
заглушка, Linux setter инициализирует BlueZ; там и в web привязка не вызывает API.
На iOS поиск использует плагин, подключение/обмен — собственный native BLE central;
новый флаг не управляет логами последнего и не обещает уменьшить каждый iOS RX.
Helper сериализует применения, объединяет промежуточные изменения до последнего,
не повторяет одинаковый режим на посторонних настройках. После исключения кэш
применения сбрасывается: Dart getter плагина меняется ещё до await и не доказывает
успех. Публичный Future<void> также скрывает платформенный bool false; успешных
нативных применений привязка не объявляет. Ошибка передаётся AppDebugLogService
как warning без содержимого исключения; новая попытка — после изменения режима,
автоматического retry-таймера нет. Dispose снимает listener и запрещает новые вызовы,
но не отменяет начатый нативный запрос. Предупреждения/ошибки плагина и наш журнал
кадров сохраняются; транспорт и очереди не меняются. ARB дополняются только ru/en.
Десятый и одиннадцатый параметры `pauseHiddenStatusAnimations` /
`pause_hidden_status_animations` и `disableContinuousStatusAnimations` /
`disable_continuous_status_animations` независимы; оба false в Off/исходных своих/старом JSON.
Balanced включает только паузу скрытых, economical/maximum — оба флага.
`helpers/status_animation_playback.dart` управляет контроллерами MessageStatusIcon/PulseDot.
При паузе лениво используется существующий GifPlaybackVisibility (сам код GIF не меняется):
viewport/route/TickerMode/Flutter lifecycle/native iOS activity. Невостребованный,
ошибочный pending или статичный индикатор не удерживает наблюдатель; Off его не создаёт.
Статичный режим останавливает контроллер, оставляя три равномерно непрозрачные точки
и PulseDot без дополнительного fade; подписи и счётчики продолжают обновляться. Пауза сохраняет
текущую фазу, завершение статуса сбрасывает её. Dispose снимает наблюдатель до контроллера;
нового таймера нет. Отсутствующий settings provider сохраняет прежнее поведение.
Радиоточка с 400-мс таймером, Material progress, входные анимации и оригиналы изображений
этими двумя флагами не меняются. Состояния доставки/ACK/повторы и транспорты не затрагиваются.
Двенадцатый параметр `cacheChannelKeyHashes` / JSON `cache_channel_key_hashes`
выключен в Off/исходных своих/старом JSON, включён в трёх энергопрофилях.
`helpers/channel_key_hash_cache.dart` — чистый Dart helper с Expando по identity PSK
и побайтовым snapshot: изменяемый Uint8List и alias не дают устаревший хеш.
Общий `_computeChannelHash` использует его в RX-log и proxy-фильтре, сохраняя SHA256(psk)[0].
Off вычисляет каждый раз; новый объект ключа даёт miss. Кэш живёт только в памяти,
не удерживает исходный ключ от GC, очищается при выключении флага, начале сессии,
disconnect, смене ноды и dispose; посторонние настройки его не вымывают.
Коллизии однобайтового хеша по-прежнему требуют проверки MAC; AES, wire, de-dup,
запись истории и ACK не меняются. `tool/benchmark_channel_key_hash.dart` сравнивает
рабочий helper с прежней формулой на том же синтетическом корпусе; это не замер энергии.
Тринадцатый параметр `skipIdleDirectProgressParsing` /
`skip_idle_direct_progress_parsing` — false в Off/исходных своих/старом JSON,
true в трёх энергопрофилях. Чистый Dart `helpers/direct_progress_rx_parser.dart`
проверяет наличие direct-трекеров до вызова прежнего DirectMessageEcho.tryParse.
MessageRetryService хранит выбранный флаг через listener настроек; на каждом RX
передаёт актуальное `_progressTrackers.isNotEmpty`, не читая весь профиль заново.
initialize заменяет подписку, dispose её снимает, отсутствующий settings provider
сохраняет Off. Pending до SENT и flood могут не иметь direct-трекера;
hasPendingMessages для этого условия не используется. При активном трекере парсер,
привязка payload, сопоставление маршрута/ширины/неоднозначности и ACK не меняются.
Остальные RX-потребители, сообщения, история, повторы и транспорт сохраняются.
`tool/benchmark_rx_progress.dart` использует рабочий helper со сверяемым снимком
парсера на прежнем корпусе; он не измеряет matcher, весь сервис или энергию.
Четырнадцатый параметр `backgroundReconnectIntervalSeconds` /
`background_reconnect_interval_seconds` — слайдер 30–600 с, шаг 30;
Off/исходные свои/старый JSON — 30, профили — 60/180/600 с.
Чистый Dart `helpers/reconnect_backoff.dart` сохраняет первые шесть пауз
1/2/4/8/16/30 с, начиная с индекса 6 увеличивает паузу только в фоне.
`helpers/reconnect_power_settings.dart` наблюдает Flutter lifecycle и существующий
native activity iOS; скрытый маршрут сам по себе не включает фон. Observer
создаётся только при выбранной паузе >30 с, освобождается при Off/минимуме/dispose.
`ReconnectWait` пересчитывает оставшееся ожидание от монотонного начала паузы
при смене активности/профиля, не расходуя новую попытку. Возврат к foreground
сокращает длинную паузу; просроченное ожидание завершается асинхронно.
Общий scheduler BLE/TCP сохраняет coalescing, transport guard, запрет параллельного
connect, manual cancellation и прежние сбросы счётчика. USB/review не добавлены.
`tool/simulate_reconnect_backoff.dart` сравнивает рабочую функцию со старым
снимком на прежних сценариях; число стартов не является измерением батареи.
См. `documentation/power-saving.md`; проверка устройства отложена владельцем
до добавления всех параметров. Экономия энергии пока не измерена.

Общий `helpers/background_work_tracker.dart` учитывает независимые удержания
незавершённых операций: `run` освобождает их в `finally`, снимки неизменяемы,
`close` запрещает новую работу без сброса активной. Через `helpers/frame_background_work.dart`
он подключён к низкоуровневому writer коннектора и командам с ожидающим completer.
`transportWrite` живёт до завершения исходного I/O Future даже после внешнего timeout,
`commandReply` — до завершения логической команды, включая запись и ожидание ACK.
Tombstone и ответы без ожидания не создают `commandReply`; прежние 5/5 с сохранены.
Снимок доступен как `backgroundWorkSnapshot`, без notify/timers; это частичный
наблюдательный учёт при любом профиле. Dispose закрывает реестр, сохраняя активные
leases; поздние вызовы после close выполняются прежним кодом без новых удержаний.
Служба/CPU lock ещё не подключены; пустота и закрытый snapshot не разрешают сон.
Set причин `BackgroundService` и 14 энергопараметров сохраняются.
Контракт и границы учёта: `documentation/background-activity.md`.
Через `helpers/message_processing_background_work.dart` подключён `messageSync`
на время общего пути `_processPotentialQueuedMessage`: обработка полученного
кадра, ожидаемая ею история и продолжение SYNC_NEXT. Contact/channel сообщения,
channel data и локальные источники учитываются, когда проходят этим путём.
Принятый `test/connector/queued_message_processing_baseline_test.dart` сохранён,
счётчики проверяет отдельный `queued_message_work_tracking_test.dart`.
`helpers/queued_message_request_background_work.dart` добавляет отдельный
`queuedMessageRequest` до отправки SYNC_NEXT и до ответа/прежнего таймаута,
остановки очереди или сброса sync/transport-состояния. Обычный полученный кадр
передаёт удержание обработке; незавершённый writer учитывается независимо.
Новых таймеров нет, сроки очереди и wire/ACK сохранены. Закрытие tracker не
сбрасывает pending wait; поздние запросы после close проходят прежним кодом
без регистрации. Deferred replay/direct echo, другие RX и не ожидаемые
обработчиком записи/уведомления/сборки изображений ещё требуют подключения;
реестр остаётся частичным, CPU lock и параметры профилей не менялись.
Принятый `test/connector/queued_message_request_baseline_test.dart` сохранён:
сроки, ранний пустой ответ, ошибки/поздняя запись и сброс проверяются настоящим
алгоритмом; отдельные регрессии счётчиков — `queued_message_request_work_tracking_test.dart`.
Перед подключением контактов/каналов принят владельцем
`test/connector/contact_channel_sync_baseline_test.dart`: ожидание END/idle timeout,
поканальные retry/restart и async-финализация перед запуском очереди сообщений.
Fixture с mock preferences и пустыми слотами проверяет lifecycle без native
handshake/SQLite. Через `helpers/sync_background_work.dart` подключены
`contactSync`/`channelSync`: логическое ожидание ответов отдельно от реальных
async-участков подготовки контактов, обработки каналов, restart и финализации.
Reset снимает ожидания, сохраняя удержания незавершённых Future. END/idle timeout,
retry, ERR_NOT_FOUND и queued handoff сохраняют прежний порядок и сроки.
Старый токен не снимает новый; счётчик одного kind может включать несколько
удержаний. Принятый baseline неизменен, новые счётчики проверяет отдельный
`contact_channel_sync_work_tracking_test.dart`. Не ожидаемые записи/replay
остаются вне этого участка; CPU/Wi-Fi/heartbeat и 14 параметров прежние.
Для участка подготовки direct/channel отправок принят владельцем
`test/connector/radio_send_preparation_baseline_test.dart`: существующая активность
polling до записи, ошибки/timeout/dispose и канальная последовательность scope/ACK.
Это изолированный lifecycle baseline без node scope/SQLite и реальной подписи;
через `helpers/radio_send_background_work.dart` подключён общий `radioSend`
вместе с прежним `RadioStatsSendPolling.run` в двух send entrypoints. Удержание
начинается до callback подготовки и заканчивается с исходным send-Future;
включает прежние ожидаемые scope/text ACK/reset. Параллельные вызовы независимы,
caller timeout/dispose не объявляют исходную операцию завершённой. После write
timeout незавершённый writer сохраняет свой отдельный `transportWrite`;
после close late calls выполняются прежним кодом без новых leases.
Принятый baseline неизменен, отдельные регрессии — `radio_send_work_tracking_test.dart`.
Unawaited/дальнейшие retry и scheduled/deferred операции требуют своего учёта;
CPU/Wi-Fi/heartbeat и параметры профилей прежние. Команды — `documentation/background-activity.md`.
Перед подключением direct ACK/retry подготовлен
`test/services/retry_lifecycle_baseline_test.dart`: per-contact/global очередь,
SENT/ACK/backoff, pause/resume, failed grace, отмена/незавершённый radio-Future.
`pendingMessageCount` включает пассивные failed-записи позднего ACK и не является
общим busy. Fixture без connector/native/БД; принятый владельцем baseline сохранён.
Через `helpers/retry_background_work.dart` и необязательный
`RetryServiceConfig.backgroundWorkTracker` коннектор передаёт общий реестр.
Kind `retry` считает отдельно логические queue/SENT/ACK/backoff ожидания и actual
`_attemptSend`, поэтому count может превышать число сообщений. Pause снимает
ожидания, resume восстанавливает только неразрешённые; failed grace не busy.
Cancel/dispose/rebind не освобождают незавершённый radio/path Future, сервис не
закрывает общий tracker. Без tracker/после close callbacks сохраняют прежний путь.
Таймеры, ACK/очереди/grace, pendingMessageCount и polling остаются прежними;
канальные повторы/scheduled/deferred и unawaited cleanup требуют своего охвата.
Регрессии — `retry_work_tracking_test.dart`, `retry_work_binding_test.dart`;
команды и границы — `documentation/background-activity.md`.
Принят владельцем baseline `test/connector/outgoing_queue_lifecycle_baseline_test.dart`:
канальные hop-loop/deadline и pending resend, scheduled commit/resume/cancel,
deferred flush после END с сохранением порядка и защитой от повторного запуска.
Фикстура без реальной ноды/SQLite, writer и готовность сессии синтетические.
`OutgoingQueueBackgroundWork` учитывает исходный hop-loop как `retry`,
commit/resume/deferred/replay Future как `radioSend`, включая подготовку scope.
Вложенные этапы имеют отдельные удержания; passive scheduled wait и очереди
до триггера не busy. Dispose/cancel не освобождают незавершённый Future;
после закрытия реестра callbacks идут прежним путём без новых leases.
Таймеры, guard/order/ACK и старый polling сохранены. Новые регрессии —
`outgoing_queue_work_tracking_test.dart`; пакет принят владельцем.
Непокрытые ошибки/reconnect replay и прочие владельцы остаются по карте;
снимок пока не разрешает отпускать CPU. Команды — в том же руководстве.
Принят baseline `image_send_lifecycle_baseline_test.dart`: настоящий
`sendImageChunks`, общий scope lock, pacing/progress/ACK, ошибки, disconnect,
caller timeout и dispose. `ImageTransferBackgroundWork` теперь оборачивает
исходный `sendImageChunks` целиком как `imageTransfer`, от ожидания scope lock
до reset, включая паузы. Параллельные вызовы независимы; caller timeout/dispose
не снимают actual lease, closed пропускает callback без новой регистрации.
После прежнего write timeout физический writer может оставаться отдельным
`transportWrite`. Тело метода, wire/кодеки/ACK/pacing и старые false/exception
ветви сохранены. Пакет `image_send_work_tracking_test.dart` и helper-тестов
принят владельцем. Capability/writer синтетические; очередь
ImageChunkTransport, encoding/decoding/RX reassembly и диск этим шагом не покрыты.
Принят baseline `test/storage/history_persistence_lifecycle_baseline_test.dart`:
ожидание реальной записи, ошибки/внешний timeout/parallel/detached writes,
обновление caches только после БД и model-store entrypoints. SQLite в памяти,
gates перед настоящими DB-методами; SQL/режим сохранения не менялись.
`PersistenceBackgroundWork` теперь оборачивает setString/replaceString/
deleteMessage/remove до завершения исходного callback и caches как persistence.
Storage общий: constructor коннектора прикрепляет наблюдателя с принятием уже
начатых записей, dispose открепляет будущие регистрации, сохраняя active holds
до окончания записи. Несколько наблюдателей видят одну общую работу независимо;
reattach не удваивает один lease. Test reset снимает подписки без обнуления
начатых операций. Принятые baseline не переписаны; новый persistenceWorkTests
принят владельцем. Без SQLite storage-сценарии пропускаются, такой skip их не проверяет.
Другие DB-операции, миграции, чтения, web и disk durability требуют своего охвата;
CPU/Wi-Fi/service/heartbeat и режим сохранения этот учёт не меняет.
Принят baseline `notification_lifecycle_baseline_test.dart`: разные границы
public Future и native show, advert batch/rate limit/suppression, caught errors,
cancel и reply. Для детерминированных сроков добавлен setRateLimitClockForTest;
по умолчанию и после reset используются DateTime.now, изменены только два
обращения rate limiter к часам. Native plugin подменён MethodChannel.
`NotificationBackgroundWork` учитывает подготовку/show, summary, own/failed reply
и cancel/clear до завершения исходного callback как notification. Detached show
direct/channel учитывается независимо от раннего возврата public Future.
Пассивное ожидание advert batch не удерживает реестр; фактический show после
таймера удерживает. Constructor коннектора принимает текущие операции singleton,
dispose снимает будущие регистрации без завершения active holds; новый коннектор
принимает незавершённые операции. Reset тестов снимает bindings, сохраняя holds.
Тела девяти методов, RX, rate limit и особенности suppression/cancelAll сохранены.
Пакет notificationWorkTests принят владельцем 23.10.2026. Отдельные badge,
другие show entrypoints, background action isolate и завершение underlying image
I/O после существующего timeout требуют отдельного охвата; CPU-политика прежняя.
Принят baseline `image_receive_lifecycle_baseline_test.dart`: запись
принятого bitstream/sidecar и отдельная очередь декодирования ReceivedImageStore.
ImageStreamReassembler передаёт outcomes без ожидания; intake может завершиться
раньше decode, тогда как requestDecode/settle ждут текущую работу. Неполные
чанки, фон и busy encoder оставляют пассивное ожидание; isDecoding может быть
true без активного decoder Future. Запрос отмены не завершает native Future;
dispose очищает очередь, но текущую декодировку не отменяет.
`ImageReceiveBackgroundWork` считает handleOutcome/handleFailure, active
_decodeOne (включая подготовку/сохранение/eviction) и запись decoderUnavailable
из очереди как receiveAssembly. Passive pending chunks/background/busy очередь
не удерживаются. Intake/decode могут иметь два независимых lease одного
изображения; count не равен числу изображений. Store ведёт операции независимо
от наблюдателей: bindImageReceiveBackgroundWork принимает pending, смена store
и dispose коннектора сохраняют начатые holds; closed не принимает новые.
Main передаёт store через initialize при доступной image feature.
Принятые baseline не переписаны; подготовлены 21 service-регрессия и 10
helper-тестов; пакет imageReceiveWorkTests принят владельцем. Startup/load/paging/delete,
outgoing registration, отдельные записи manual/memory-pressure/repeat metadata,
encoding/backend и FR01 требуют охвата. CPU-политика и 14 параметров прежние.
Принят baseline `handshake_lifecycle_baseline_test.dart`: общий запрос
устройства, refresh, ожидание SELF_INFO, retry 3500 мс и location waiters.
Его 22 сценария используют @visibleForTesting adapters. Writer синтетический,
SELF_INFO использует fixture cached-path без привязки stores/первой загрузки БД.
Проверки transport labels BLE/TCP/USB относятся к общей non-web ветви таймера,
не к реальному открытию соединения. Native connect, cold initial sync и Web
handshake требуют отдельного охвата.
Теперь существующий SyncBackgroundWork считает общий handshake как
transportSetup: логическое ожидание принадлежит прежнему awaiting-флагу,
четыре actual Future (request/refresh/location/wait) учитываются независимо.
Reset/SELF_INFO снимают только логическую фазу; local timeout/известный ключ
не снимают ещё установленный awaiting-флаг. Retry при потере связи и dispose
снимают logical hold, сохраняя actual запросы/waiters и отдельный transportWrite.
Значение флага, команды, deadlines/retry и прежние error/early-response quirks
сохранены; после close новые leases не создаются. Подготовлены 23 отдельные
connector-регрессии; handshakeWorkTests принят владельцем.
Native connect/cold load/полный initial sync и Web требуют своего охвата;
CPU-политика, таймеры и 14 параметров энергосбережения прежние.
Принят baseline `tcp_connect_lifecycle_baseline_test.dart`: полный
connectTcp от ожидания teardown/stopScan/dial до SELF_INFO и syncTime, cancel
и late completion. Конструктор принимает optional TCP manager; default по-прежнему
создаёт MeshCoreTcpConnector. Подготовлены 20 сценариев с synthetic manager,
cached SELF_INFO, frame writer seam и настоящим teardown при пустом USB/BLE.
Реальные сокеты/overlay, native lifetime и cold load не проверяются новой
фикстурой; stopScan/default scope изолированы. Теперь прежний SyncBackgroundWork
учитывает весь connectTcp как transportSetup до завершения исходного Future,
включая ожидаемый cleanup; тело алгоритма сохранено. Отмена/reset/dispose и
внешний timeout не снимают удержание незавершённого connect. Общий handshake
и фактический writer учитываются независимо; после write timeout writer может
оставаться активным уже после завершения connect. Unawaited default-region
refresh и полный initial sync этим удержанием не охватываются.
Пакет tcpConnectWorkTests с 22 отдельными сценариями принят владельцем;
CPU-политика и 14 параметров прежние.
Принят baseline `usb_connect_lifecycle_baseline_test.dart`: подготовлены
20 сценариев полного connectUsb с fake manager, без создания UsbSerialService
и flserial. Конструктор принимает optional usbManager с прежним default.
Проверяются open/200 мс/SELF_INFO/time sync, ошибки/guards/teardown и ожидание
USB close без внешнего deadline; native FFI join не менялся. Теперь весь
connectUsb выполняется через прежний SyncBackgroundWork как transportSetup
до завершения исходного Future с ожидаемым cleanup; тело алгоритма сохранено.
Reset/отмена/caller timeout/dispose не снимают незавершённый connect; writer и
logical SELF_INFO независимы. Пакет usbConnectWorkTests с 22 отдельными
регрессиями принят владельцем.
Unawaited region refresh и последующий disconnect после уже завершённого
connect не входят в эту обёртку. Реальный native USB/Web/cold load и позднее
открытие после отмены требуют отдельного охвата. CPU-политика прежняя.
Принят baseline `disconnect_lifecycle_baseline_test.dart`: 20 сценариев
настоящего disconnect с synthetic close/release, без изменения коннектора.
Фиксируются coalescing, приоритет ручного отключения, порядок USB/TCP/models,
ошибки manager close и отдельные трёхсекундные deadlines release моделей.
Позднее завершение timeout-операции не должно продолжать старый teardown.
Native FFI, review/offline storage и настоящие модели фикстура не открывает.
Теперь ConnectionTeardownBackgroundWork считает весь _disconnectInternal
как transportTeardown; параллельные callers не создают дубликат outer hold.
ConnectionCleanup получил optional runAction: отдельный actual hold создаётся
до action и живёт ниже timeout, до фактического результата/ошибки. Null и
синхронные ошибки сохраняют прежнее выполнение; late completion освобождает
только своё удержание. CPU-политика и правила закрытия прежние.
Пакет disconnectWorkTests с 16 connector-регрессиями и восемью helper-тестами
принят владельцем. Baseline не переписан. В двух TCP/USB tracking-тестах
общая сумма теперь учитывает новый kind, setup/write assertions сохранены.
Пустой snapshot сон не разрешает; underlying native I/O вне Futures manager
и неохваченные владельцы ещё требуют отдельной проверки.
Следующий baseline — `ble_connect_lifecycle_baseline_test.dart`: 20 сценариев
Windows-ветви плагина, другие платформы явно skipped. Device/GATT/bond ответ
синтетические; настоящие connect/disconnect/handshake сохранены. Проверяются
scan/open/discovery/CCCD, Windows-пауза 750 мс и CCCD retries 1/2 с, ошибки,
guards/cancel/caller timeout и time sync. После двух missing SELF_INFO окон
BLE connect-Future по прежнему коду может завершиться без ошибки, сохраняя
незавершённый handshake; это baseline, не новый критерий готовности сессии.
Native iOS/Linux pairing/Web/Android MTU, cold sync и аппаратный BLE требуют
своего охвата. BleConnectBaselineTests принят владельцем после исправления
фикстуры; outer hold полного BLE connect пока не добавлен. Коннектор
не менялся на этапе этого baseline.
Потоки фикстуры имеют управляемые Stream/Subscription: cancel завершается
в зоне widget-теста. Это устраняет ожидание root-Zone Future._nullFuture
от broadcast.cancel внутри FakeAsync; проверки и таймауты сценариев сохранены.

`AirActivityDot` (`widgets/radio_stats_entry.dart`) blinks while the last
radio-stats frame showed the node's airtime growing
(`radioStatsAirActivityPulse`), which the stats poll (`_pollingInterval`,
30 s by default) refreshes: it says the air was busy in the last poll window
and cannot be more current than the poll, which is left alone on purpose, a
poll every two seconds costing both radios more than the frames it would
save. The blink is a 400 ms `Timer.periodic` toggling the half, run only
while the dot is active and `TickerMode.getValuesNotifier(context)` allows frames,
not an `AnimationController`: a repeating controller ticks the whole frame
pipeline sixty times a second for a dot that changes 2.5 times a second, and
a DevTools profile of the app sitting idle after a send (2026-10-08) put 95%
of the UI isolate's samples into that ticker, several percent of CPU for
every poll window the dot blinked, while the connector did not appear at
all. The timer's own problem, which the ticker had been chosen for, is
answered by the same signal that muted the ticker: a timer ticked on under
a route that is not on top, one frame every 400 ms for the app bar of every
route in the stack, so the timer stops when the notifier says frames are
off, keeps its phase, and starts again when it says on, without rebuilding
from the notifier's callback, which fires during another widget's build
(`test/widgets/air_activity_dot_test.dart`).

Every screen has its own app bar and its own dot, and the quick switch
replaces one screen with another, so the flag has to be the connector's
answer for the whole window rather than something a widget keeps.
`radioStatsAirActivityPulse` returns `_airtimeGrewInLastPoll`: the last stats
frame of the polling run found the airtime grown over the frame before it,
held until the next frame. It used to be true for two seconds after the
frame, and only the dot on screen at that moment blinked for the window,
its widget holding the answer it got; a dot built on a screen opened a few
seconds later asked afresh and stayed dark. The first frame of a polling run
lights nothing, its totals counting from the node's boot, and stopping the
poll (`_stopRadioStatsPolling`, at a disconnect or when the last dot goes)
starts the next run afresh. `_airtimeBumpStopwatch`, which the send path's
radio-quiet wait reads, is left as it was
(`test/connector/radio_air_activity_test.dart`).

### Answers to neighbour and telemetry requests

The neighbours and telemetry screens learn their request's tag from the `RESP_CODE_SENT` the node gives for it, and the repeater's answer (`PUSH_CODE_BINARY_RESPONSE`) repeats that tag. The node answers every command in turn, so a direct message, a room post or another request written meanwhile brings its own SENT, before the request's or after it. Both screens used to keep the tag of the last SENT and dropped the answer whenever another send fell in between; the telemetry screen also armed its timeout on every SENT, a request pending or not, so a message sent while it was open ended in a false timeout. `RequestSentTags` (`helpers/request_sent_tags.dart`, tested in `test/helpers/request_sent_tags_test.dart`) keeps every tag seen while the request waits, which cannot mix answers up, because the companion passes on the answer to its latest binary request only (`pending_req`). The estimates those SENTs carry set the timeout: the first replaces the fallback, a later one can only push the deadline back. The 10-second fallback is armed once the request is out, not before, so waiting for the command lock does not use it up; the telemetry screen had none and without a SENT waited for good. A new request drops the tags while its route is being prepared, so nothing that arrives before it goes out counts, while an answer arriving after a timeout is still taken.

The telemetry screen also shows a separate **Calculated power (V × I)** row
when voltage and current are finite numbers in the same channel of the current
response (`helpers/telemetry_power.dart`). It preserves the sign and all
transmitted values; LPP power (128) remains whole watts, and the original power
row is kept. No values are borrowed from other channels or earlier responses.
`helpers/telemetry_diagnostics.dart` supplies structured parser diagnostics and
debug logs tagged `Telemetry`: unknown types, malformed fields, incomplete
headers and truncated polylines include a payload-relative offset, channel,
type and payload length. The screen logs decoded field names by channel.
Unknown types still stop parsing safely and retain the valid prefix. Pressure
(115) remains a decoded sensor field; its absence in the reported BMP280+AHT20
case is not yet attributed to a device-confirmed cause. Baseline and regression
coverage lives in `test/helpers/cayenne_lpp_telemetry_test.dart`,
`test/helpers/telemetry_power_test.dart`,
`test/helpers/telemetry_diagnostics_test.dart` and
`test/screens/telemetry_screen_test.dart` (2026-10-21).

### Room servers on the channels screen
Three mod settings decide how much of the contact list the channels screen borrows. `roomServerShowNotemptyOnChatscreen` adds room servers (`advTypeRoom`) and `roomServerShowNotemptyContactsOnChatscreen` adds ordinary chat contacts (`advTypeChat`) — both only where `Contact.hasMessages` is true, so an advert alone never puts a node there. `roomServerDisableRoomAndContactsSorting` (default **on**; the other two default off) keeps them out of the channel sort order, and while it is on `_visibleRoomServers()` returns nothing at all. `widgets/message_search_sheet.dart` reads the same two visibility flags, so search covers exactly what the screen shows.

### Channel identity: names, keys and aliases

Per-channel data (messages, settings, region, marker styles, mutes) is keyed
by the channel's **name** in the node's scope (`ChannelNameKeyedStore`,
`channel_messages_<node>name_<base64url(name)>`), never by the radio slot: a
slot is reused for other channels, and the same channel sits in different
slots on different nodes. One channel name on several nodes of one owner is
one channel, which is what the shared history, the search and the marker
styles rest on. What the name keying lost was a rename: a channel renamed
under the same PSK started over, its history, settings and region staying
under the old name.

`channel_identities` (`storage/channel_identity_store.dart`,
`ChannelIdentities.instance`, an app-wide auxiliary table of the application
database, `(group_id, psk_id, name)`, the preference key
`channel_identities_v1` where there is no database) records every (PSK,
name) pair a channel went through: a group is one logical channel, its rows
the aliases, a pair with no row a group of itself; `psk_id` is
`Channel.storageId`. A link is recorded only when exactly one of the two
parameters changed: by `setChannel` (the edit sheet and the link and QR
import's "update the channel of this name" go through it, the slot's old
channel known), and by the channel sync, which compares the node's list
before the sync (the last saved list at the first sync of a session) with
the list it read, as sets of pairs (`helpers/channel_identity_reconciler.dart`):
a pair that vanished links to the pair that appeared with its key, else, when
its key vanished altogether, to the one that appeared with its name; both
changed is a new channel, a slot move is nothing. A slot whose channel gained
names is read again at the end of the sync.

The reads follow the group. `channelStorageKeys` gives the key of every name
of the channel, its own first, and the message store reads over them
(`storage_key IN`, `MessageHistoryStorage.getLatestStringForKeys` and its
siblings, the lists merged in timeline order on the web), writes under the
current name and drops a re-saved message from the former names' keys
(`_dropFromFormerNames`), so a read over several keys never lists one message
twice (`_withoutRepeatedIds` covers the window between the two). Settings and
the region are not copied on a rename: `channelInheritedKeys` reads the value
from the channel's other names in this scope and then from the same names in
every other node's scope, after the node's own value and the one-time move
from the slot key, so a node that never set anything for a channel takes what
another node keeps for it, and a value set here wins from then on. Marker
styles (`ChannelMarkerStyles.styleFor`) and mutes
(`_isChannelMutedUnderAnyName`) read the former names the same way. The
shared history finds another node's copy by the group when the matcher fails
(`SharedMessageHistoryHelper.matchingChannelIndex`), and
`_sharedChannelIdentityKey` carries the table's revision, so a channel that
gains a name fetches its shared copy anew.

A manual deletion (`deleteChannel`) and a clearing
(`clearMessagesForChannel`) take `allNodes`. With the shared channel history
on, the dialog (`widgets/channel_data_scope_dialog.dart`) asks whether the
channel's data goes for this node or in the merged history of every node:
this node clears its own scope under every name of the group and keeps the
group while another node's cached channel list holds a channel of it, all
nodes clears every scope and forgets the group. A slot emptied by another
app clears nothing, as before. Contact history is keyed by the full public
key and loses nothing on a rename; linking a contact's new key to an old
history is its own, manual change
(`test/storage/channel_identities_test.dart`,
`test/helpers/channel_identity_reconciler_test.dart`,
`test/storage/channel_message_store_identity_test.dart`,
`test/storage/channel_settings_inheritance_test.dart`).

### Contact identity: attaching an old key's history

A contact's history is keyed by its full public key (`messages_<node><key>`),
so a rename loses nothing, while a node re-flashed with a new identity under
the same name is a new contact with an empty chat, its history staying under
the old key. `contact_identities` (`storage/contact_identity_store.dart`,
`ContactIdentities.instance`, an app-wide auxiliary table `(group_id,
public_key_hex)`, the preference key `contact_identities_v1` where there is
no database) records the keys the user linked as one person; a key with no
row is a group of itself. **Links are made by hand only**: a name proves
nothing, two people, or one person's phone and base, carry the same one.
When a chat opens, `MeshCoreConnector.contactHistoryCandidates` looks for
chat contacts of the same name (trimmed, case-insensitive) under another
key that have a history (`helpers/contact_history_candidates.dart`), on this
node's list and, with the shared contact history on, on the other nodes'
cached lists, and the chat shows `ContactHistoryLinkBanner`
(`widgets/contact_history_link_banner.dart`) until one is attached or the
banner is dismissed for the session. Attaching goes through a dialog that
names the contact and the key and says the user must be sure it is the same
person, not a namesake; `linkContactHistory` then links the keys, gives the
contact the settings and the region of the other key where it has none
(`ContactSettingsStore.copySettings`, `ContactRegionStore.copyRegion`), drops
the in-memory settings and conversation of the key and reads the chat again.
`MessageStore` reads a conversation over the keys of the group
(`_storageKeys`, the contact's own first), writes under the contact's own and
drops a re-saved message from the linked keys (`_dropFromLinkedKeys`), merges
the summaries of the keys for the contacts list, and clears every key of the
group; the shared history, the search and the marker sweep follow, since
they read through the store. Deleting the contact without keeping its
history clears the group's keys in this node's scope and forgets the group
unless another node's list still holds one of its keys
(`test/storage/contact_identities_test.dart`,
`test/helpers/contact_history_candidates_test.dart`,
`test/storage/message_store_identity_test.dart`).

### Channel QR codes: scanning and sharing (fork-only, removable)

The add-channel sheet has a **Scan a QR Code** option ahead of the community one. It reads the link format the MeshCore mobile app uses for channels, documented in MeshCore's `docs/qr_codes.md`: `meshcore://channel/add?name=<url-encoded>&secret=<32 hex>` with an optional `region_scope`. A hashtag channel is the same link with a `#` name; a hashtag link that carries no secret is accepted too, its key derived from the whole name. An over-long name is shortened on a character boundary to the 31 bytes the node stores, since the secret is what identifies a channel and the name is only a label.

What a scanned link does to the node is decided by `ChannelQrLink.importInto`, a pure function the tests cover. A key the node already holds under another name is never written a second time, the secret being the channel. A **name** the node already holds is not given a second slot either: a small-print dialog (`channels_qrUpdateExisting`, Cancel / OK) offers to update that channel, and OK replaces its key and makes its region what the link says — set when the link carries a `region_scope`, **cleared** when it carries none, because the link is taken as the whole description of the channel. The channel keeps its own name, since history and per-channel settings are keyed by it. Names are compared the way `ChannelIdentityMatcher` compares them, trimmed and without case. The same name with the same key and the same region is nothing to change and reads as already added, as does the case where the key sits in a *different* slot than the name — updating there would leave one key in two slots.

A region from a link is kept the way the region screen keeps them, without the leading `#` the scope hash adds back by itself, and is added to `RegionStore` when the app has not met it: `setChannelRegion` stores the channel's region only, and the region picker finds the selected one by looking it up in that list. The same happens for a newly added channel. Writing the channel's own region has an order to it: regions are stored under the channel's **name**, and the connector learns which name a slot holds only when the node reports the slot back, some time after `setChannel` has returned — so for a new channel `setChannelRegion` finds no name and silently stores nothing, and the sync that follows reloads an empty region. The scanner therefore writes the region first, through a `ChannelRegionStore` of its own bound to the name the slot is about to get, and the sync `setChannel` starts reads it from there; `setChannelRegion` is still called afterwards, which is what makes an updated channel change at once. A link whose `region_scope` the app could not use — longer than 30 bytes, a private `$` region whose key lives on a repeater, or characters outside the byte rule regions fetched from a repeater are held to — is refused whole rather than imported without it, since "no region" is an order to clear one. The share screen's region field therefore types under the region screen's own rule (`[a-z0-9-]`, 30 characters), so the app never shows a QR code its own scanner would refuse.

Upstream may ship its own version, so the feature is kept in one piece that can be lifted out: the parser `helpers/channel_qr_link.dart` (pure Dart, tested in `test/helpers/channel_qr_link_test.dart`), the screen `screens/channel_qr_scanner_screen.dart` with its `scanAndAdd` helper (the camera through the shared `QrScannerWidget`; a picture from the gallery, since 2026-10-14, through `helpers/qr_gallery_scan.dart`, the gallery logic of upstream's contact scanner with the kind of code to accept as a parameter and the picker and the reader injectable for its test, under the contact scanner's own `contacts_qrFromGallery`, `contacts_noQrCodeFound` and `contacts_qrGalleryFailed` strings; the contact scanner's gallery button goes through it as well. mobile_scanner reads the picture where it has an implementation for that, Android, iOS and macOS; elsewhere, and whenever it read nothing, `helpers/qr_picture_decoder.dart` reads it in pure Dart with `zxing2`, the ZXing port: the engine decodes the picture (`dart:ui`, scaled to 1600 px on its longer side) and a background isolate runs ZXing's two binarizers over it as it is and inverted, with the try-harder hint. On Windows and Linux, where mobile_scanner has no implementation at all and a camera widget answers every call with a MissingPluginException, the shared `QrScannerWidget` shows its unsupported-camera message instead of starting the camera (`QrScannerWidget.isSupported`) with the gallery button under it (`onPickPicture`, which both scanners pass), so a QR code in a downloaded picture scans there too), the import itself in `widgets/channel_link_import.dart` (`ChannelLinkImport`: the dialogs, the region stores and `setChannel`, shared by the scanner, links in messages and the clipboard), and four insertions in `channels_screen.dart` marked `channel-qr-scan` (two imports, option card `6`, its `case 6`). `ChannelQrLink.enabled` hides the option without touching anything else.

The other direction is the **Share** entry that follows **Edit channel** in both channel menus, the long-press sheet of `channels_screen.dart` and the overflow menu of `channel_chat_screen.dart`. It opens `screens/channel_share_screen.dart`: the QR code of `ChannelQrLink.toLink()`, the secret key with a copy button, a region field and a button that copies the link. The region starts as the channel's own (`getChannelRegion`) and only goes into the link, `region_scope` being written when the field is not empty; editing it never touches the channel. An unnamed channel is shared under its display name, because a link with an empty name does not parse. The entry is not gated on offline mode: everything it shows is local. Its insertions are marked `channel-qr-share`, and `channel_chat_screen.dart` has mixed line endings, so they were made byte-safe. The copy button reads `channels_shareCopyLink` (en and ru only); it used to borrow the contact screen's `discoveredContacts_copyContact`, «Copy Contact to clipboard» (`test/screens/channel_share_screen_test.dart`).

**Links in messages and on the clipboard.** A copied link sent into a channel, a direct chat or a room is a link of its own. `helpers/mesh_link_linkifier.dart` (`MeshLinkLinkifier`) runs ahead of the URL linkifier in both places message text is linkified, `LinkHandler.buildLinkifyText` and `FormattedMessageText`, because `linkify`'s `UrlLinkifier` knows only http, https and www; a body without `meshcore://`, which is nearly all of them, costs it one substring search and no pattern. Only what `ChannelQrLink.tryParse` or `ContactLink.tryParse` reads becomes a link, and punctuation closing the sentence around one stays text; a link the app writes never ends in punctuation, the secret, the region, the hex or the type coming last. `LinkHandler.handleLinkTap` hands a channel link to `ChannelLinkImport.confirmAndAdd` and a contact link to `ContactLinkImport.confirmAndAdd` instead of the open-in-browser dialog, and the contacts screen's import from the clipboard does the same when the clipboard holds a channel link or the MeshCore app's contact link rather than a contact's advert: all three start with `meshcore://`, and the first two used to read there as a bad advert. `confirmAndAdd` refuses in the offline history (`app_offline_unableToMessage`) and without a connection (`scanner_notConnected`), then follows `importInto` as a scan does, with two differences: a new channel is asked about first (`channels_addChannel` over the name and `channels_regionSetTo` or `channels_regionNotSet`), the link being somebody else's suggestion, and it takes the first free slot, `channels_noFreeSlots` when there is none, where a scan takes the slot the add sheet picked. Reply quotes, the channels list preview and the message search draw text without links, so a channel link stays text there. The link is shown as written; a card like a shared contact's may come later. A Cyrillic name is percent-encoded to three times its bytes, so a link to a channel with a long one may not fit one message (`test/helpers/mesh_link_linkifier_test.dart`, `test/widgets/channel_link_in_messages_test.dart`; `test/widgets/message_links_test.dart` holds web links to the browser dialog).

**Contact links** (`helpers/contact_link.dart`, 2026-10-09) come in two forms. `meshcore://<hex>` is the contact's advert packet, header and path included: what the contacts and discovery screens copy to the clipboard, and what the node imports and verifies itself through `CMD_IMPORT_CONTACT`; `ContactAdvertLink` reads the key, the type and the name off it for the question and refuses anything that is not an advert packet of a plausible size, so a stray hex string stays text. `meshcore://contact/add?name=…&public_key=…&type=…` is the MeshCore app's link (MeshCore `docs/qr_codes.md`: 1 companion, 2 repeater, 3 room server, 4 sensor; a missing type reads as 1); `ContactAddLink` carries the name, the key and the type, and the app writes the contact itself through `addOrUpdateSharedContact`, unsigned, as the shared contact card (`<hex:type:name>`) does. `ContactLinkImport.confirmAndAdd` (`widgets/contact_link_import.dart`) refuses offline and without a connection, answers our own key with `chat_contactIsYou`, asks under `chat_addContact` with the name, the type and the key, adding `chat_sureToReplaceContact` when the node holds the key, and reports `contacts_contactImported` or `contacts_contactImportFailed`; the chat screens' own `_addSharedContact` still serves the card (`test/helpers/contact_link_test.dart`, `test/helpers/mesh_link_linkifier_test.dart`, `test/widgets/contact_link_in_messages_test.dart`).

A tap on the QR code of that screen hands it over as a picture, for pasting into a messenger. Flutter's `Clipboard` carries text only, and the plugins that carry pictures (`pasteboard`, `super_clipboard`) each bring a native build step and a content provider in the Android manifest, so there is deliberately no new dependency. `helpers/image_clipboard.dart` puts the picture on the clipboard on **Windows only**, through `dart:ffi`: the registered `PNG` format first, then a bottom-up 32-bit `CF_DIB`, from which the system derives `CF_BITMAP` and `CF_DIBV5` by itself. Everywhere else `ImageClipboard.isSupported` is false and the tap goes through `MCOImageFileSaver.savePngBytes` — the save dialog on a desktop, the share sheet on a phone, which is the shorter way into a messenger there anyway. The hint under the QR code and its tooltip say which of the two will happen.

Three things in that helper are deliberate. The clipboard is opened with no owner window, which the Win32 documentation warns about but which only rules out delayed rendering, and the data here is handed over whole. It is opened, filled and closed in one synchronous run, with no `await` in between, because an open clipboard belongs to the thread that opened it and is closed to every other application meanwhile; a busy clipboard, normal right after any change while clipboard viewers look at it, is retried for a third of a second instead. And the fourth byte of every `CF_DIB` pixel is written as `0xFF` whatever the source says: readers disagree on what it means in a `BI_RGB` bitmap, and a zero there turns the picture invisible in those that take it for alpha.

The picture comes from `helpers/qr_bitmap.dart`, which builds pixels straight from the module matrix of the same `QrCode` that `QrImageView` draws — a whole number of pixels per module, the four-module quiet zone, opaque white behind — rather than from `QrPainter`, whose output is transparent, has no quiet zone and sizes a module in half pixels. Both helpers are generic and tested (`test/helpers/qr_bitmap_test.dart`, `test/helpers/image_clipboard_test.dart`), but the share screen is their only caller today.

To remove the whole feature, delete `helpers/channel_qr_link.dart`, `widgets/channel_link_import.dart`, both screens and their tests (`channel_qr_link_test.dart`, `channel_link_in_messages_test.dart`, `channel_share_screen_test.dart`), drop the channel branch of `MeshLinkLinkifier` (`helpers/mesh_link_linkifier.dart`) with the channel cases of its test, drop the lines marked `channel-qr-scan`, `channel-qr-share`, `channel-qr-chat` and `channel-qr-paste` together with the branches under the last two markers' comments in `LinkHandler.handleLinkTap` and the contacts screen's `_contactImport`, and remove the ARB keys `channels_scanQrInstructions`, `channels_invalidQrCode`, `channels_qrAlreadyAdded`, `channels_qrUpdateExisting` (en and ru only), `channels_shareQrHint`, `channels_shareSecretKey`, `channels_shareRegionScope`, `channels_shareKeyCopied`, `channels_shareLinkCopied`, `channels_shareQrTapToCopy`, `channels_shareQrTapToShare`, `channels_shareQrImageCopied`, `channels_shareQrImageFailed` and `channels_shareCopyLink` (en and ru only); `channels_scanQrCode`, `channels_addChannel`, `channels_regionSetTo`, `channels_regionNotSet`, `channels_noFreeSlots`, `scanner_notConnected`, `app_offline_unableToMessage`, `community_join` and `common_share` were there before and stay. `test/widgets/message_links_test.dart` stays too: it holds web links, not channel ones. `helpers/qr_bitmap.dart` and the three `helpers/image_clipboard*.dart` files go with it, tests included, unless something else has started to use them by then; the `suggestedName` parameter of `MCOImageFileSaver.savePngBytes` is harmless and can stay. `helpers/qr_gallery_scan.dart` and `helpers/qr_picture_decoder.dart`, their tests and the `zxing2` dependency stay as long as the contact scanner's gallery button goes through them.

### Radio settings and device config

`setRadioParams` sends SET_RADIO_PARAMS and waits for the node's OK, returning false on ERR or timeout, and the settings screen then shows `settings_radioSettingsNotApplied`. The coding rate travels as the node's own 5–8 (the app once sent 1–4), frequencies start at 150 MHz and TX power at −9 dBm, as the firmware accepts. The client-repeat check uses the frequency ranges the node allows (`allowedRepeatFreqRanges`, firmware version code 9+, falling back to 433, 869.495 and 918 MHz), and writing the auto-add settings keeps the node's max-hops value (`autoAddMaxHops`, 8+); `_maybeRequestDeviceConfig` asks for both once DEVICE_INFO and SELF_INFO are in. The path-hash mode is offered from version code 10. Sending an AEIC picture needs version code 11 (`supportsChannelData`, checked by `sendImageChunks` and the channel screen's `_sendImage`), where it used to wait for 13: `CMD_SEND_CHANNEL_DATA` arrived while the code was 10 (2026-03-05) and took its final framing on 03-18 and 03-23, so 11 (04-15) is the first code that guarantees it, while 13 (06-01) brought requests to non-contacts and nothing for channel data. The other binary channel sends, the MCMP and MCOtxt envelopes and MCOimg, check no version at all: a node without the command answers ERR and the message fails. Airtime estimates (`calculateLoRaAirtime`) use the firmware's preamble, 32 symbols up to SF8 and 16 above, and RadioLib's LDRO rule (symbol time over 16 ms), so timeouts and retry spacing came out longer than before.

### URL image previews

An image link in an ordinary text message can be shown as a picture (`helpers/message_url_image_helper.dart`, from upstream): direct `.png` / `.jpg` / `.webp` links, `pyx.li`, `ibb.co` share pages and IPFS paths or CIDs, share pages being resolved over HTTP and every image checked before it is drawn. It is off by default and switched per contact (the contact settings dialog in `chat_screen.dart`) and per channel (`widgets/channel_edit_sheet.dart`), stored by `contact_settings_store` / `channel_settings_store` (`loadUrlImagesEnabled` / `saveUrlImagesEnabled`, the channel flag keyed by name like the other channel settings). With the flag off a bubble with such a link shows the `urlImage_possible` hint instead. Both bubbles read `bodyText`, so a blocked sender's message never fetches anything, and notifications attach the picture only where the flag is on, waiting at most five seconds for it. This is apart from the images sent over the mesh (MCOimg, AEIC), which never touch the network.

### GIF cache

Флаг энергосбережения `pauseHiddenGifs` (JSON `pause_hidden_gifs`) управляет
приостановкой `GifMessage`: исходные custom/Off выключены, готовые профили включены.
`helpers/gif_playback.dart` содержит `GifPlaybackVisibility` и `GifImageSubscription`.
При включённом флаге учитываются маршрут, TickerMode, геометрическая видимость
из уже используемого visibility_detector, Flutter lifecycle и существующий
`iosAppPresentationActive`. Подписка на кадры снимается в фоне/вне видимости;
новый скрытый GIF ждёт видимости перед resolve. Последний кадр и ручная пауза сохраняются.
Handle completer удерживается только на паузе и освобождается при возобновлении,
смене URL или dispose: вытеснение из image cache не ломает возврат. Ручная пауза
независима от автоматической; старые callbacks проверяются по ревизии потока и mounted.
При выключенном флаге нет visibility detector и подписок на lifecycle/native activity.
Подготовленные widget-регрессии находятся в `test/widgets/gif_message_power_baseline_test.dart`,
исходные восемь сценариев Off сохранены. См. `documentation/power-saving.md`.

A GIF in a message travels as its Giphy id (`g:<id>`, `helpers/gif_helper.dart`), and `GifMessage` draws it from `https://media.giphy.com/media/<id>/giphy.gif` wherever a GIF message appears: bubbles, reply quotes and the composer preview. `services/gif_disk_cache.dart` keeps the bytes on disk, so a GIF seen once shows again after a restart and without a network: `gif_cache/` under the application cache directory, one file per URL named by the SHA-256 of that URL, 200 MB at most, and a file not shown for 365 days is deleted. The file system is the whole index. A file's size is what counts against the limit and its modification time is the moment it was last shown, since every hit moves it forward, so past the limit the files shown longest ago go first. A trim follows every write, and one runs before the first read of a session, so the lifetime holds even when nothing new is downloaded. Nothing is kept in the database or in preferences, so no record can drift from the files, and the operations run one after another, so a trim never deletes a file being read or written.

`GifMessage` takes its provider from `gifImageProvider` (`services/gif_image_provider.dart`, a conditional export). Wherever `dart:io` exists that is `CachedGifImage`, which reads the disk first, goes to the network only on a miss and stores a download only once it has decoded, so an error page never takes a place in the cache, and a cached file that stops decoding is dropped and fetched again. The web build keeps `NetworkImage`, the browser's HTTP cache being the only one there. The directory comes from `getApplicationCacheDirectory` (Android `cacheDir`, `Caches` on iOS and macOS, the data folder's `cache/` on Windows and Linux): the system may empty it when storage runs short and keeps it out of backups, while a system temporary directory, where the map tiles lived before the data folder, is cleared at boot on many Linux systems and by Windows clean-up tools; in the data folder nothing empties either of them but the app. `flutter_cache_manager` was left out on purpose: it limits a cache by count, not by bytes, and the 3.4.1 in use when this cache was written left every evicted file on disk (see Map raster sources).

A failed load stays in Flutter's image cache as a completer that only repeats its error, and resolving the same provider again returns that completer. `GifMessage._retryLoad` therefore evicts the provider before the retry; before, a GIF that failed once kept failing for the rest of the session. The GIF picker's previews are not cached: they are search results, and a year of them would crowd out the GIFs that were actually sent.

### Repeater clock sync and region load

`RepeaterCommandService.sendCommand` turns `clock sync` into `time <epoch>` with the phone's clock (`normalizeRepeaterClockSyncCommand`), as meshcore-cli does: companion firmware since 2025-12-30 stamps a CLI frame with the node's own RTC, so a plain `clock sync` set the repeater to the node's time. The CLI screen knows the repeater's `region load` mode, in which the firmware takes every line before prefix stripping and answers none: lines go out verbatim through `sendUnansweredLine`, and a blank line commits the load, the only line of the mode that gets an answer. Like every CLI command they take `sendContactFrame`, so they carry the contact's region as the `region load` before them did.

### Other UX
Per-conversation **sending delay** (schedule/commit/cancel a queued send), **quick answers** (canned composer replies, `helpers/quick_answers_helper.dart`), per-channel **widget color**, a **sender name size** (`AppSettings.senderNameScalePercent`, mod settings under the monochrome names switch: 25, 50 and 100 to 400 by 25, default 100, a stored value snapped to the nearest; the channel and room bubbles multiply their sender-name font size by it and by the chat zoom, and the gap under the name with it and, above 100%, by a third more (`senderNameGapScale`), while the DPI setting reaches it through the global text scaler like every other text), and a **translate UI shell** (`widgets/message_translation_button.dart`) that only writes the target-language setting (translation itself is disabled).

## Upstream dev merges

The fork merges `zjs81/meshcore-open` dev in steps along its first-parent
history, one `git merge --no-commit <tip>` per step, so that each step is
tested on its own. The rules that hold across the steps: the ARB files keep
the fork's translations where both sides changed a value and take upstream's
new keys; the generated `app_localizations*.dart` are taken as ours and
regenerated with `gen-l10n`; the merge hot spots (`chat_screen.dart`,
`channel_chat_screen.dart`, `contacts_screen.dart`, `map_screen.dart`, the
connector) stay the fork's and upstream's functional changes are ported into
them by hand; the storage stays the fork's SQLite; `pubspec.yaml` changes go
into the three profiles; this file stays the fork's. A file the fork deleted
on purpose (the eleven widgets of step 4, the dropped tests) merges silently
while upstream leaves it alone; when upstream changes it, git reports a
modify/delete conflict, and the answer is `git rm` again, not a restore.

**Step 1 (2026-10-12, dev up to 9334d556, upstream's 2026-09-27 batch).**
Taken: notification replies, mark-as-read and mute actions with Android
Auto support (`services/notification_reply.dart`, the connector's
`handleNotificationReply`, MessagingStyle notifications that still carry the
fork's MCOimg pictures as the large icon and Apple attachment); the channel
mute bell in the channel chat, one `Channel.muteKey` for named and unnamed
channels (the mod setting `hideChannelMuteButton`, off by default, takes the
bell out of the app bar since 2026-10-13); resending a channel message until it is heard through N repeaters
(`channelMinHops*` settings, `_resendUntilMinHops`, the resend reusing the
first send's packet timestamp so it stays one packet; the status icon of a
channel bubble reports the progress, and `ChannelMessage.resendCount` keeps the
repeated transmissions: the bubble's meta row shows the attempt count for
every outgoing message while the setting is on, a spinner in place of the
replay icon from the radio transmission until the loop ends (the hop
check is registered as the frame goes to the radio, the delay counted
from that moment and the loop woken by every echo, and the transcript's
selector rebuilds on
`channelResendRevision`, since the loop changes nothing in the message
list), the sent check mark left out under the setting, the badge saying
the message went out, and the path screen a *Send attempts* row; the wait before each resend is `channelMinHopsDelaySeconds` (10 to
120 s, default 30) under the hop count; `helpers/channel_resend_coverage.dart`
also accepts enough distinct first-hop repeaters as an alternative to the hop
target when `channelMinHopsCountRepeaters` is on. Its independent target is
`channelMinHopsRepeaterCount` (2–10, default 2), shown below the toggle by
`widgets/channel_resend_repeater_settings.dart`; the toggle subtitle uses this
target too. Both nearby-repeater controls are read live by the resend loop.
Older JSON without the new field inherits `channelMinHops`, clamped to 2–10;
subsequent changes to either target leave the other unchanged (2026-10-21).
Согласование покрытия и предупреждения (2026-10-22):
`helpers/channel_resend_warning.dart` сохраняет обычный no-echo guard и допускает
warning при `repeatCount > 0`, если завершённая серия имеет `_channelHopShortfalls`.
`_mergeChannelRepeat` сохраняет поле предупреждения и ожидающий warning-таймер
при позднем недостаточном эхо; достаточный маршрут или distinct first-hop target
снимает shortfall, увеличивает `channelResendRevision` и отменяет warning.
Повторы одного префикса не становятся разными nearby-репитерами; resend loop
после завершения не запускается заново. `widgets/channel_resend_shortfall_indicator.dart`
добавляет warning в tracing-строку, пока общее предупреждение ещё не выделило
сообщение. Mod-опция и таймаут 5–15 с от последней отправки сохраняются;
packet timestamp, счётчики и статус передачи в радио не меняют смысла.
Цели/shortfall остаются только в сессии; сохранённое сообщение содержит прежнее
поле warning, но не восстановление цели старой серии после новой сессии.
Экран пути по-прежнему использует snapshot при открытии. Подробности —
`documentation/channels.md#channel-auto-resend`.
The no-retransmission warning of
the mod settings is held back while the resends run, counts from the last
attempt, and its line under a resent message names the resends
(`settings_modSettingsNoRetraInfoResends`) rather than seconds that would
count from that attempt only (all 2026-10-13/14)); the contact QR scanner screen
(`screens/contact_qr_scanner_screen.dart`, `utils/contact_qr*.dart`, beside
the fork's own link parser); day separators in both chats
(`widgets/chat_day_separator.dart`); "keep chat history" on contact
deletion (`removeContact(keepMessages:)`); the contacts-full banner; the map's
node clustering toggle (`mapClusterNodes`); the USB serial close off the UI
isolate with the teardown serialised against reconnects
(`_activeDisconnect`, `_disposed`); the self-node telemetry tile; the
repeater settings "load all" with fields disabled until read (its refresh
on opening the screen, taken in step 4, went again on 2026-10-14: the
fields are read by hand, one or all at once, as the fork always had it, so
that a visit to the screen sends nothing over the air by itself); upstream's
image send preview with its own reconstruction preview (replacing the fork's
"as received" one, the parity default kept off); the hash-width fix when a
repeat's path bytes are merged. Left out: upstream's app-side default region
(the fork uses the node's default flood scope), the `region` field on
`ChannelMessage` (the fork has `packetRegion`, and "reply to the same
region" was ported onto it: the reply banner's region chip, shown for a
message with a known region and off until tapped, sends the reply under that region
through `sendChannelMessage(region:)`, the scheduled and the deferred sends
carrying it along), upstream's `_isChannelRepeat` rewrite and reply-target
resolution (the fork's exact quotes and heard-packet map cover them), the
discovery screen's add icon and the region screen's empty state,
`test/models/channel_message_reply_test.dart` (tests an upstream-only
constructor parameter).

**Step 2 (2026-10-12, dev up to a64a33d0, upstream build 18).** Taken: review
mode, a simulated radio for store reviewers (`lib/review_mode/`,
`MeshCoreTransportType.review`, `connectReview`, the session cleanup at
startup in `main.dart`, the banner above the channel and contact lists, the
long-press on the scanner title), but kept unreachable: `reviewModeAvailable`
in `review_mode_entry.dart` is `false`, because the simulated radio's
contacts, channels and messages would go into the application database
while `clearReviewModeData` clears preferences only; enabling it means
clearing the fake scope's rows there too. Its three connector-level tests
assumed the preference storage and were dropped;
`test/review_mode/review_radio_test.dart` stays. Edge-to-edge on Android
(`SystemUiMode.edgeToEdge`, transparent system bars with contrast
enforcement, light icons over the image viewer and the QR scanner); the copy
snackbar skipped on Android, where the system shows its own chip; the
package bumps in all four pubspecs. Left out then: the discovered-contact
eviction toggle (`evictDiscoveredContactsEnabled`, cap 500), since the fork
keeps its eviction always on at `maxDiscoveredContacts` (1000); taken on
2026-10-13 as the same toggle in the auto-add dialog with a cap of 350, off
by default, its ARB keys having come along in this step. Upstream's re-indent of `channels_screen.dart` made the
auto-merge turn the search clear button's `setChannelsSearchText('')` into
`(value)`: a hot screen's `git diff HEAD` is read even when its conflicts
were taken as ours.

**Step 3 (2026-10-12, dev up to 9609a823).** Taken: the contact-sync fixes
(CMD_APP_START stops the firmware's contact iterator, so `_sendAppStart`
holds it back while a sync runs and `_continueAfterContactSync` sends it at
the end; a message from a sender the app does not know yet is held in
`_unknownSenderMessageFrames` and replayed when its CONTACT frame arrives or
the sync ends, where it used to be re-parsed after a refresh that had
delivered nothing, the firmware having already dropped it from its queue);
the channel sync ending at the first ERR_NOT_FOUND
(`_handleChannelSyncNotFound`) and `_unconfirmedChannelSlots` behind the
free-slot choice of the channels and community screens; a later SELF_INFO
of the same radio in one link session (`refreshDeviceInfo` after a settings
change) no longer reloads every store (`_persistedStateLoadedKey`), and
another radio answering after a dropped BLE link drops the previous radio's
in-memory history (`_messageStateOwnerKey`, `_clearSessionMessageState`);
reply tombstones in `PendingCommandReplies`, so a late OK or ERR of a
timed-out command cannot complete the next one; 176-byte RX frames
(`maxRxFrameSize`, the USB codec); TCP keepalive probes in
`tcp_transport_service_native.dart`; the discovered list's export and
import (`exportDiscoveredContactsJson` / `importDiscoveredContactsJson`, the
discovery screen's menu, onto the app-wide list and the fork's cap, public
now as `maxDiscoveredContacts`); the repeater command service's late-reply
handling, merged with the fork's `sendContactFrame`; the image store's
atomic writes, dead worker and delete-during-decode fixes merged into
`received_image_store.dart`; the future-timestamp indicator next to a
message time, computed on the fork's `receivedAt` (nullable on `Message`);
`_isSendingText` in both chats, with the draft kept when it changed during
an outgoing translation; `MarkerLabelDialog` on the map, fed the fork's own
`_maxMarkerLabelBytes` budget; the system text scale as the default of
`LinkHandler.buildLinkifyText` (the chats pass their own scaler); the app
badge on iOS and macOS; UTF-8 name limits; `channelMinHopsCountRepeaters`;
`regionOnHopsLine`, taken as a setting (the channel bubble puts the region
into the hop row instead of upstream's `_RouteRegionChips`); and a channel's
explicit *no region*, added on top of the fork's scope handling (see
**Region / flood-scope routing**). Left out: upstream's TCP auto-reconnect
(the fork reconnects every transport through `_scheduleReconnect`), the
preference archive window (`setArchived`; the fork pages SQLite), the
stalled-sync watchdog (the fork's `_contactSyncIdleTimeout` ends such a
sync), upstream's app default region and its radio-default dropdown on the
region screen (the fork has its own default-scope section over
`getDefaultRegionScope`), the node scan sheet (#570), share-my-location
from the chat composer (the fork's actions sheet inserts the coordinates,
the map shares pins), `Contact.wasPulled` (removed upstream; the map's
contact signature dropped it). Dropped tests: `received_at_test` (the
archive, a non-null `Message.receivedAt`), `default_flood_scope_test`
(upstream's app default), `scoped_store_fixes_test` (preference-key
scoping). Auto-merge damage fixed: the closing `}` of
`_handleDisconnection`, a stray `return;` in the unknown-sender branch, a
duplicate `case respCodeDefaultFloodScope`, the discovery screen's lost
delete handler, a `showDismissibleSnackBar` call without its import, and,
found on 2026-10-14, the `Row` around the routing label and its menu in
the repeater login dialog, whose `Spacer` then sat straight in a column
and kept upstream's collapsible *Advanced* section from opening. That
section went the same day: the fork's layout is back, the routing row
with its menu, the route label and the manage-paths button under a
divider, in the dialog itself, where the route is what the user looks
for before logging in.

**Step 4 (2026-10-12, dev up to d30744aa, upstream's UI refresh).** The
refresh rebuilt most screens around new widgets, and the fork's UI stays.
Upstream's screens were taken whole only where the fork had changed little
(`map_cache_screen.dart`, `repeater_settings_screen.dart`,
`repeater_status_screen.dart`, `repeater_cli_screen.dart`,
`line_of_sight_map_screen.dart`), the fork's own lines put back by hand: the
bulk-download gate behind `SettingsSectionsService`, `sendContactFrame` for
the status request, `recv_errors`, the `clearNeighbors` quick command, the
console's desktop scrollbar, `MapSessionZoom`, the `context.select` reads
of the line-of-sight banner. Eleven widgets the refresh introduced were
dropped as unused by the fork's screens (`chat_composer`,
`chat_send_pipeline`, `message_bubble_frame`, `reaction_chips`,
`contact_visuals`, `cyr2lat_profile_dialog`, `language_picker_sheet`,
`mesh_nav_tile`, `node_scan_sheet`, `radio_settings_dialog`,
`translation_settings_section`); `confirm_clear_dialog.dart`,
`radio_disconnected_banner.dart`, `map_poi_cluster.dart` and
`path_map_scaffold.dart` stayed (the last with its test; the fork's trace
screens keep their own panels and read only its zoom constants). Ported by
hand into the fork's screens: the confirmation before clearing a chat or a
debug log; a contact's telemetry flags written as each is toggled; the
keyboard opening on a reply; the channel chat's communities reloaded when a
covering route pops, and its transcript order memoised (`_TranscriptOrder`,
a stable sort by arrival computed once per change of the message list or
the image store instead of on every rebuild); the contacts screen's advert
failure snackbar and a ten-second timeout on its pending import, export and
share commands, which took the next OK or ERR of anything before; the
channels list's relative times and slot chip through l10n; on the map, a
timer that ages the markers once a minute without traffic, the removal of
a pin with an undo and the restore of every removed pin from the filter
sheet, a confirmation before "set my location" that waits for the
SELF_INFO carrying the new position, and the clustering of shared pins with
the "You" marker under the node clustering toggle
(`_buildPoiAndSelfMarkers`, off while overlaps or a path trace are shown);
the TCP screen's field errors; the USB screen's hot-plug timer paused in
the background and its web port picker; the neighbours screen opening the
repeater hub; the telemetry screen failing fast on ERR; the settings
screen's guard for commands sent while disconnected, the hints on the copy
and battery rows, the confirmation of saved contact settings and empty
location fields clearing the node's location; the API key field's
show/hide toggle; the path trace reporting a refused send; the region
screen's guards on fetching with no repeater and on blank names, the
repeater's route restored in a `finally`. Left out: share-my-location from
the composer, the lazy camera and the parallel path loads of the trace
screens (the fork has no such loop), the semantics labels, the back-button
change, and the widget extractions themselves. Fixed afterwards: the
'both' resolution of the `MapBulkDownloadNotAllowed` /
`MapTileDownloadCancelToken` conflict dropped the exception class's closing
brace, nesting every later class of the tile cache service (435 analyzer
errors from one line); and the fork's `PathAnimationControls` overflowed
the 288 px that upstream's panel test lays them out in, so the controls
wrap now, the hop label under them, and a legend label is `Flexible`, as
upstream's refresh had done, the fork's compact sizes and theming kept.

**Step 5 (2026-10-13, dev up to 86ec8b4e, upstream's channel storage by
PSK-derived ID).** Upstream re-keyed every per-channel store (messages,
settings, region, order, images) by `Channel.storageId`, the first 8 bytes
of SHA-256 over `meshcore-channel:` and the PSK, with a slot-to-ID map
diffed at every channel sync, channel frames held until the map is
confirmed, a one-shot preference migration and a deletion that clears
everything. The fork keeps its name-keyed storage (`ChannelNameKeyedStore`,
see **Storage / Persistence**): one channel name on several nodes of one
owner is one channel, which the shared history, the search and the marker
styles are built on. Taken: the `storageId` helper on `Channel`;
`ImageReassembler.clearChannel`, called from `_applySyncedChannel` when a
sync finds another PSK in a slot, so an image begun under the previous
channel is never finished with the new one's chunks; the image store's
`channelId`, stamped on outgoing entries (`registerOutgoing`) and inbound
ones (`ImageStreamReassembler` resolves the slot through
`MeshCoreConnector.channelIdForSlot`), with `deleteImagesForChannelId`
beside the fork's deletion by slot (the chat moved to the IDs with the
channel identity work, see **AEIC image store**); the paragraph of
`documentation/channels.md`, written for the name rule. Left out: the slot map and the frames held for it,
`channel_storage_migration.dart`, the channel order by ID, upstream's
`getChannels` completer (the fork restarts a running sync through
`_pendingChannelSyncRestart`), the two tests of the ID scheme
(`channel_slot_map_test`, `channel_storage_by_id_test`) and the modified
`received_at_test` and `message_store_archive_test`, both deleted in step
3. What the name keying still loses, a rename under the same PSK, is the
subject of the channel identity table that follows this step as its own
change.

**Step 6 (2026-10-13, dev up to 3bee159c, upstream's network map).** Taken
whole but unreachable: upstream's opt-in upload of header-only packet
records to map.meshcoreopen.org and its online repeater layer
(`lib/services/network_map/*`, `lib/utils/location_grid.dart`,
`lib/connector/raw_packet.dart`, the four `network_map_*` widgets,
`get_node_banner.dart`, `mesh_nav_tile.dart` restored for the settings
section, the settings fields `networkMapUploadEnabled` and
`networkMapPromptShown`, `UiViewStateService.mapSource`, the tests and
`documentation/network-map.md`). `networkMapAvailable` in
`lib/services/network_map/network_map_availability.dart` is `false`, as
`reviewModeAvailable` is: `main.dart` creates no `NetworkMapUploadService`
and registers no provider for it, the channels screen never asks the opt-in
question, the app settings show no network-map section, and the map's
`mapSource` is `local` without reading `UiViewStateService`, so the
Local / Online / Both switch, the online layers, the hint and the
`NetworkMapOnlineController` (a `late final` the disabled build never
touches) stay out of the build. The connector reads the path byte through
`raw_packet.dart`'s public `decodePathByteLen` / `decodePathHashWidth`
where it had private copies. The decision is the fork's: what its users'
packet records should feed, if anything, is not settled, and an upload
nobody can switch on would still cost a listener on every connector
notification. The node-purchase banner of the connect screen is gated the
same way (`getNodeBannerAvailable` in `get_node_banner.dart`; it would sit
above the offline-history row, not replace the bottom bar as upstream's
does) and kept so the fork can point it at a project of its own. Left out:
the version bump (ours stays as **Dependencies** says), the `BETA` suffix on
the settings screen's version, the README link to the map and the
privacy-policy paragraphs about uploads and the affiliate link, since
neither exists in this build; `docs/PRIVACY_POLICY.md` is upstream's text
of 2026-09-27 until the flag flips. ARB: upstream's 40 keys appended to en
and ru, the ru strings reworded to the fork's terms («радио» for the radio,
«репитер», «анонс», «нода»), the other locales auto-merged.

## Transports

`MeshCoreConnector` unifies all three transports under one `ChangeNotifier`. There is **no shared base class** — selection is via the `MeshCoreTransportType { bluetooth, usb, tcp }` enum, and BLE/TCP/USB share the same connection-state enum, send/receive API, and frame protocol.

Opening TCP from the scanner uses `helpers/scanner_tcp_navigation.dart` for both the toolbar action and the saved transport. It joins any scanner-owned BLE startup before awaiting `stopScan()`, so delayed adapter setup cannot restart discovery after the switch. Navigation checks that the scanner is still mounted and current after the waits, preventing late or duplicate pushes. The TCP button keeps its existing shared-state guards.

### Connection State
```dart
enum MeshCoreConnectionState {
  disconnected,
  scanning,
  connecting,
  connected,
  disconnecting,
}
```

Recoverable BLE loss does not navigate away from the current chat/canvas. The connector shows the reconnecting state, queues pending sends and retries indefinitely with capped exponential delay; successful `SELF_INFO` restores the ready session. Manual disconnects and non-recoverable USB/TCP loss return to their connection flow.

BLE/TCP teardown uses `helpers/connection_cleanup.dart`: subscription cancellation, BLE platform replies and queued model release have a three-second limit per step, log the failed stage, and let the remaining cleanup run. Captured old subscriptions are detached before awaiting cancellation. `helpers/tcp_socket_cleanup.dart` closes the captured socket concurrently with read cancellation and always destroys it, including after a timeout; the TCP service shares in-flight teardown, fences callbacks and queued writes by connection generation, and resets the write queue for the next socket. New connects join this bounded teardown. These are per-step deadlines, not a three-second total, and do not cancel the original Futures. Model services serialize old releases before later loads; native USB close and review-storage cleanup retain their existing joins for resource/storage safety.

The firmware refusals remembered for a connection, `_directEchoAckUnsupported` and `_unscopedSendUnsupported`, are cleared whenever the link goes: in `disconnect()`, which manual disconnects, USB and TCP loss and every failed reconnect attempt pass through, and in `_handleDisconnection()`, the unexpected BLE drop, after which a successful reconnect never calls `disconnect()`. `_resetConnectionHandshakeState` runs only at USB and TCP connects and at a BLE connect on the web, so a flag cleared there alone outlives native BLE reconnections, a change of node or a firmware update included, until the app restarts, as both of these once did. Both are set only by `ERR_CODE_UNSUPPORTED_CMD` (or an ERR with no code), never by a lost link or a full packet pool.

A **transport restart** (`_restartActiveTransport`, handed to the optional module behind `SettingsSectionsService`, which asks for one a moment after the node accepts a command of one of that module's own clients that changes the node's session, and when a client of its own that cannot read framed packets connects while the node sends them, the node negotiating framing with this app and not with each client; the app's own commands never cause one since 2026-10-14, the app refreshing its own session after a name or radio change, and a restart in the middle of its command sequence used to drop the frames still queued behind the accepted one, the TX power behind the radio parameters) tears the link down as a manual disconnect and brings the same transport straight back. It is a manual disconnect in the connector's terms only, and both readers of that state keep their routes, as they do for a recovering link, instead of popping to the scanner as for the user's own disconnect: the app shell reads `isRestartingTransport` first in `_handleConnectionStateChanged`, and so does `DisconnectNavigationMixin` (`utils/disconnect_navigation_mixin.dart`), which the channels, contacts and map screens run in their build and which pops the whole stack from there the moment a teardown begins; it knew only the recovering link and popped on every restart whatever the shell did, which is what left the app on the scanner, with the radio connected, when a client connected to the proxy (2026-10-14, `test/utils/disconnect_navigation_mixin_test.dart`). The restart logs its request to the app log ahead of the disconnect and connect lines it produces, and one that ends with the link down clears the flag and notifies once more, so the shell and the screens see the plain disconnect; one that ends connected has nothing to add. The scanner covers the race that stays: a TCP reconnect can be up before the shell's post-frame pop runs, so the scanner's listener saw `connected` under another route and the next notification might be a while; `didPopNext` therefore pushes the channels when the radio is connected and the screen has not shown them for this connection (`_changedNavigation`, reset by a disconnect only, so a user who backed out of the channels keeps the scanner).
### Frame I/O (all transports)
- **Send**: `MeshCoreConnector.sendFrame(Uint8List data, {String? channelSendQueueId, bool expectsGenericAck, bool waitForGenericAck})`
- **Receive**: `Stream<Uint8List> get receivedFrames`
- **Protocol constants** (`meshcore_protocol.dart`): `maxFrameSize = 176`, `maxTextPayloadBytes = 160`, `maxChannelDataLength = 165`, `appProtocolVersion = 4`. Command codes are top-level `cmd*` consts (app→device, 1…65), responses `respCode*` (with v3 variants `…RecvV3`), async pushes `pushCode*` (`0x80`…`0x90`), mesh-layer `payloadType*`. Frames are built/parsed with `BufferWriter` / `BufferReader` and `build*Frame` / `parse*` helpers.
- **Reply pairing**: `PendingCommandReplies` (`connector/pending_command_replies.dart`, from upstream) enrols every command whose reply is known in `_sendFrameDirect`, before the write: `replyCodeForCommand` names OK, SENT or the specific response, a GET_CONTACT_BY_KEY being matched by key. `_handleCompanionFrame` hands every frame of the node to `completeReply` ahead of the switch (a frame another client wrote through us is skipped), `_handleOk` takes the oldest entry waiting for OK and `_handleErrorFrame` the oldest of any kind, and entries older than ten seconds are pruned before either, so a reply that never came cannot take a later one. `waitForGenericAck` and `_sendFrameAndWaitForCommandAck` wait up to five seconds for the command's own reply and throw its ERR as a `CommandFailedException` carrying the firmware's error code; before, a waiting send took the first OK or ERR of any command. The fork's own commands are in the table (the three `CMD_SIGN_*`, the default flood scope pair, `CMD_SEND_RAW_PACKET`), so that a signing session's OK cannot complete a channel send; the signing session still reads its replies from `receivedFrames` itself. `CMD_EXPORT_PRIVATE_KEY` stays out on purpose: a node built without the export answers `RESP_CODE_DISABLED`, which no entry pairs, and the entry left behind would take the next ERR. Frames the settings-sections bridge writes straight to the transport are not enrolled.

### BLE — Nordic UART Service (NUS)
- **Service UUID**: `6e400001-b5a3-f393-e0a9-e50e24dcca9e`
- **RX Characteristic** (write to device): `6e400002-b5a3-f393-e0a9-e50e24dcca9e`
- **TX Characteristic** (notify from device): `6e400003-b5a3-f393-e0a9-e50e24dcca9e`
- **Discovery**: filters on the **NUS service UUID** (not the device name) so community forks with custom names are still found. `MeshCoreUuids.deviceNamePrefixes` (`MeshCore-`, `Whisper-`, `WisCore-`, `Seeed`, `Lilygo`, `HT-`, `LowMesh_MC_`, `NRF52`) is kept only for reference/display heuristics.
- **Linux**: `linux_ble_pairing_service.dart` falls back to `bluetoothctl` when BlueZ agent prompts fail

### TCP
- Manual host/port entry, persisted via `AppSettingsService` (`tcpServerAddress`, `tcpServerPort`)
- UI hint: `192.168.40.10` / port `5000`
- Disabled on web (`PlatformInfo.isWeb`)
- API: `MeshCoreConnector.connectTcp(host: ..., port: ...)`
- Optional TCP transports are selected through `helpers/companion_tcp_dialer.dart`; ordinary endpoints use `Socket.connect`.

### USB Serial (flserial)
- Default baud rate: `115200`
- Port enumeration: `MeshCoreConnector.listUsbPorts()`
- Marker-and-length framed packets via `usb_serial_frame_codec.dart`: `0x3C`
  for host-to-device, `0x3E` for device-to-host, then a two-byte little-endian
  payload length
- macOS device-name resolution via `ioreg` (`utils/macos_usb_device_names.dart`)
- API: `MeshCoreConnector.connectUsb(portName: ..., baudRate: 115200)`

## Dependencies

App version: `9.5.0-mcoa.1.12.0+46` — Dart SDK constraint: `^3.9.2`. The base
is upstream's version (9.5.0 since its build 13), the fork's own release
number follows `-mcoa.`, the build number counts the fork's builds; the base
was 9.5.1 from 2026-08-20 to 2026-10-13 with no upstream 9.5.1 behind it.

`pubspec.yaml` is never edited on its own: it is a copy of the active build profile. `tool/use_translation_profile.dart` overwrites it from `pubspec.full.yaml`, `pubspec.lite.yaml` or `pubspec.lite-aeic.yaml`, and `lib/services/translation_service.dart` and `lib/services/image_codec_backend.dart` from their templates under `tool/translation_profiles/` and `tool/image_codec_profiles/`. The committed default is **lite-aeic**, so `pubspec.yaml` stays byte-identical to `pubspec.lite-aeic.yaml` and each live service file to its active template. The profiles differ only in their own blocks: lite drops `flutter_onnxruntime`, full adds `llamadart`, `flutter_langdetect` and the llamadart `hooks`. A dependency, a version bump or a git ref therefore goes into all three profiles in the same commit, and a change to either service file into its template. `test/tool/build_profiles_test.dart` holds all of that: the live files equal the lite-aeic templates, the three profiles differ only in their own packages and the llamadart `hooks`, and the two templates of each service declare the same public API; it was added after the onnx template missed upstream's `releaseDecoderSession` fix in step 3 of the 2026-10 merge and a profile switch put the stale copy back into the working tree. Upstream merges touch only `pubspec.yaml`: the flserial ref of upstream `82ec1feb` and `base32` for MeshCore One reactions lived there alone until 2026-09-27, and any profile switch dropped both. The `tool/use_translation_*.ps1` scripts copy the same files but leave the iOS deployment target alone, so a switch meant for a Mac build goes through the Dart tool.

**Connectivity**

| Package | Version | Purpose |
|---------|---------|---------|
| flutter_blue_plus | ^2.1.0 | BLE scanning, connecting, and UART data transfer |
| flutter_blue_plus_platform_interface | ^9.0.2 | Platform-interface layer required by flutter_blue_plus |
| flserial | git (MeshEnvy fork) | USB serial transport for wired device connections (TODO: upstream pending) |

**State / Storage**

| Package | Version | Purpose |
|---------|---------|---------|
| provider | ^6.1.5+1 | ChangeNotifier-based state management across screens |
| shared_preferences | ^2.2.2 | Persistent key-value storage for user settings |
| drift | ^2.34.3 | SQLite layer for the message-history database |
| drift_flutter | ^0.3.1 | Platform wiring for drift (native background isolate, file location) |
| path_provider | ^2.1.5 | Locates platform-appropriate directories for file I/O |
| path_provider_platform_interface | ^2.1.2 | `PathProviderPlatform.instance`, replaced on Windows and Linux to answer with folders of the data folder |
| path_provider_windows | ^2.3.0 | Base of the data folder's provider on Windows |
| path_provider_linux | ^2.2.1 | Base of the data folder's provider on Linux |
| shared_preferences_platform_interface | ^2.4.2 | The preference store instances that are handed the data folder's provider |
| shared_preferences_windows | ^2.4.1 | Its stores take the data folder's provider on Windows |
| shared_preferences_linux | ^2.4.1 | Its stores take the data folder's provider on Linux |
| sqlite3 | ^3.5.2 | `Database.backup` snapshots of the databases when an earlier installation's data are copied into a data folder |
| path | ^1.9.1 | Path rules of the data folder and of the old system folders |

**Crypto**

| Package | Version | Purpose |
|---------|---------|---------|
| crypto | ^3.0.3 | SHA/HMAC hashing used in message authentication + flood-scope hashing |
| pointycastle | ^4.0.0 | AES encryption/decryption for channel and direct messages |
| cryptography | ^2.9.0 | Ed25519 verification of MCMP v3 message signatures (signing happens on the node via CMD_SIGN_*) |
| cryptography_flutter | ^2.3.4 | Native crypto acceleration for the `cryptography` package |
| base32 | ^2.2.0 | Crockford base32 of MeshCore One reaction hashes |
| convert | ^3.1.2 | Hex/base codec helpers used across protocol + image codecs |
| uuid | ^4.3.3 | Generates UUIDs for message and contact identity |

**Maps & Location**

| Package | Version | Purpose |
|---------|---------|---------|
| flutter_map | ^8.2.2 | Interactive tile map for node positions and path traces |
| latlong2 | ^0.9.1 | LatLng coordinate type used throughout map and GPS code |
| geolocator | ^13.0.2 | Phone GPS fixes for own-position advert and wardrive sampling |
| gpx | ^2.3.0 | Export node paths as GPX track files |

**UI**

| Package | Version | Purpose |
|---------|---------|---------|
| material_symbols_icons | ^4.2928.1 | Extended Material Symbols icon set (line-of-sight, etc.) |
| flutter_svg | ^2.0.10+1 | Renders SVG assets (custom icons such as LoS indicator) |
| cached_network_image | ^3.4.1 | Caches map tile images downloaded over the network |
| flutter_cache_manager | ^3.4.5 | Map tile cache and the cache behind cached_network_image; 3.4.2 is the first release that deletes evicted files |
| flutter_linkify | ^6.0.0 | Auto-detects and makes URLs tappable in chat messages |
| mobile_scanner | ^7.1.4 | QR/barcode scanning for contact and channel import |
| qr_flutter | ^4.1.0 | Generates QR codes for sharing contacts and channels |
| zxing2 | ^0.2.4 | Pure-Dart ZXing port: reads the QR code in a picked picture where mobile_scanner cannot (Windows, Linux, web) or read nothing |
| cupertino_icons | ^1.0.8 | iOS-style icon font (bundled for completeness) |
| characters | ^1.4.0 | Unicode-aware string operations for message text handling |

**Notifications / Background**

| Package | Version | Purpose |
|---------|---------|---------|
| flutter_local_notifications | ^22.0.0 | Shows local push notifications for incoming messages |
| flutter_foreground_task | ^9.2.0 | Keeps the app alive in background to maintain BLE/USB connection |

**ML**

| Package | Version | Purpose |
|---------|---------|---------|
| ml_algo | ^16.0.0 | OLS regression used in `timeout_prediction_service.dart` to predict message ACK timeouts |
| ml_dataframe | ^1.0.0 | DataFrame input format required by ml_algo |

> `llamadart` and `flutter_langdetect` (on-device LLM translation) have been **removed** — translation is disabled in this build.

**Misc**

| Package | Version | Purpose |
|---------|---------|---------|
| http | ^1.2.0 | Fetches tile URLs, remote API calls, and wardrive sample uploads |
| url_launcher | ^6.3.0 | Opens URLs in the system browser from linkified chat text |
| share_plus | ^13.1.0 | Shares files (e.g. exported GPX tracks) via the system share sheet |
| file_selector | ^1.0.3 | Native open/save dialogs for image packs and GPX/exported files |
| archive | ^4.0.9 | Reads/writes `.mcoimg.pack` image-pack archives |
| wakelock_plus | ^1.5.2 | Keeps the screen awake during scanning / wardriving |
| package_info_plus | ^10.1.0 | Reads app version/build number displayed in settings |
| web | ^1.1.1 | Web-platform APIs for USB serial and browser detection on Flutter Web |
| intl | any | Internationalization and locale formatting (required by flutter_localizations) |
| build_pipe | ^0.3.1 | CI/CD build pipeline configuration (web release builds with versioned assets) |

## Platform Configuration

### Android (`android/app/src/main/AndroidManifest.xml`)
- `INTERNET` (map tiles, wardrive sample uploads)
- `BLUETOOTH`, `BLUETOOTH_ADMIN` (API ≤ 30)
- `BLUETOOTH_SCAN` (with `neverForLocation`), `BLUETOOTH_CONNECT`, `BLUETOOTH_ADVERTISE` (API 31+)
- `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION` (BLE scanning on API ≤ 30)
- `ACCESS_BACKGROUND_LOCATION`, `FOREGROUND_SERVICE_LOCATION` (optional wardrive background sampling — gated in Dart so ordinary BLE users don't inherit them)
- `POST_NOTIFICATIONS` (API 33+)
- `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_CONNECTED_DEVICE` (foreground process/engine retention for BLE and optional background TCP)
- `WAKE_LOCK`
- `CAMERA` (QR scanning, declared as optional feature)
- USB host hardware feature (optional)

`BackgroundService.ensureBatteryOptimizationExemption` checks Android's battery-optimization whitelist, which is what lets the foreground service — and with it the BLE or TCP link — survive Doze. It has nothing to do with wardriving, which runs its own location service. The **check** runs on every launch and on the first explicit BLE connection; the **prompt** is spent once per install and recorded in `background_battery_exemption_asked_v1`, because it throws the user out to a system screen and repeating that every launch reads as nagging for something already declined. The record is written before the prompt, so backing out of that screen still counts as the one ask. Settings → Debug has an Android-only tile that asks again on purpose, through `force: true`, which steps past both that record and the once-per-reason guard held for the current run.

`flutter_foreground_task` registers a connected-device `ForegroundService` (`foregroundServiceType="connectedDevice"`, `stopWithTask="false"`); a separate wardrive `location` foreground service is declared and enabled only via the Android-only wardrive path. `MainActivity` caches the main Flutter engine while the service has an active keep-alive reason. The engine sends an in-process heartbeat every 5 seconds; after 20 seconds without one, a surviving/restarted foreground task changes its notification to `app_connectionLostBreaked`. This heartbeat is not a BLE or LoRa packet. While the link stays down every failed reconnect attempt goes through `disconnect(manual: false)` and reports the loss again, seconds apart, so `BackgroundService.setConnectionLost` posts the `app_connectionLostReconnect` text once per outage (`_connectionLostPosted`) and leaves it in the notification until the link is back; a restored connection re-arms it, so the next loss is always announced. If Android kills the whole process, the service cannot reconstruct BLE because it has no connector of its own.

**Build config (`android/app/build.gradle.kts`)**: `applicationId = com.meshcore.mcoadvanced`, NDK `29.0.14206865`, Java/Kotlin 17 with core-library desugaring (`desugar_jdk_libs:2.1.4`), release signing via `key.properties` (debug fallback).

### iOS (`ios/Runner/Info.plist`)
Deployment target is owned by the build profile, not edited by hand: `tool/use_translation_profile.dart` writes it into `ios/Podfile` and all three `IPHONEOS_DEPLOYMENT_TARGET` entries in `project.pbxproj` — 13.0 for **lite**, 16.0 for **lite-aeic** and **full**, where `flutter_onnxruntime` forces it. The two files must agree: CocoaPods fails the build outright when the Podfile platform is lower than a plugin needs. Switching a profile requires dropping `ios/Pods` and `ios/Podfile.lock` before `pod install`. The Podfile also declares `onnxruntime-objc` with `:modular_headers => true`, guarded by a check for `flutter_onnxruntime` in `.flutter-plugins-dependencies`: that pod ships no module map, so CocoaPods refuses to link the Swift plugin statically without one, and the guard keeps the lite profile from pulling a runtime it does not use.
- Display name `MCO Advanced`
- `NSBluetoothAlwaysUsageDescription`, `NSBluetoothPeripheralUsageDescription`
- `NSCameraUsageDescription` (QR scanning to join communities)
- `NSLocationWhenInUseUsageDescription` (tag wardrive discovery requests + update own node position)
- Background modes: `bluetooth-central` (no location background mode — iOS wardriving is foreground-only)
- `LSApplicationQueriesSchemes`: `http`, `https`

**Experimental iOS background TCP (merged from `feature/ios-background-tcp`).** The TCP screen stores a Wi-Fi SSID in the last endpoint and in each bookmark, tries the current SSID through `IosWifiSsidService`, and configures `NEAppPushManager` through `IosBackgroundTcpService` after a successful connection when background TCP is enabled. The incoming branch changes `backgroundTcpEnabled` to true by default (Android included); an explicit saved false is retained. The separate `MeshCoreBackgroundTcpExtension` uses its own TCP connection, drains the node queue and posts local notifications; it does not run the Flutter connector or persist those messages to the app database. `AppDelegate` registers the added native channels on both the launch path and the implicit engine, while retaining the BLE adapters and badge channel. `Info.plist` keeps `bluetooth-peripheral` alongside the incoming fetch/processing/voip modes. This is a merge of an experiment, not a device-validated background-delivery guarantee. Signing/entitlements, shared-node socket behaviour, queue ownership, re-delivery to Flutter, disable/disconnect handling, and deployment targets after switching profiles still need checking on the affected iOS build; the profile tool rewrites every `IPHONEOS_DEPLOYMENT_TARGET`, now including the extension. See `documentation/scanner-and-connection.md`.

### Web (`web/`)
PWA scaffold present but boilerplate (`manifest.json` and `index.html` are unmodified Flutter defaults). BLE is unsupported in browsers; TCP and Web Serial USB may work in Chrome only. `ChromeRequiredScreen` gates non-Chrome web users. Versioned releases are produced via `build_pipe` (`?v=<pubspec version>` cache busting, no service worker).

### Desktop
`linux/` is a Flutter scaffold with no app-specific native config. The Windows runner adds three things: the window size, kept in the data folder (`windows/runner/main.cpp`, see **Data folder**); a first-frame watchdog (`flutter_window.cpp`), a message box with `MCO-WIN-STARTUP-001` when Flutter has drawn nothing 15 seconds after the window was created; and the `meshcore_open/window_activation` channel, whose `restoreAndFocus` brings the window back to the front (`services/window_activation_service.dart`). `macos/` is configured: both entitlement files grant Bluetooth, USB plus the `/dev/cu.*` / `/dev/tty.*` serial paths, network client, camera and user-selected files (AEIC image picking); `Info.plist` carries the Bluetooth, camera and photo-library usage strings; the deployment target is 14.0 and the Release configuration is ad-hoc signed (`CODE_SIGN_IDENTITY = "-"`), so the built `meshcore_open.app` runs where it was built and needs right-click → Open (or the quarantine attribute removed) elsewhere. BLE and USB on desktop have not been validated at runtime.

## Coding Conventions

### Code Philosophy
- **Minimal**: Only write code that is necessary. Avoid over-engineering.
- **Organized**: Keep related code together. One responsibility per file.
- **Maintainable**: Favor readability over cleverness. Simple is better.

### Style
- Use `StatelessWidget` with `Consumer` for state-dependent UI
- Use `const` constructors where possible
- Prefix private methods/fields with `_`
- Center app bar titles (`centerTitle: true`)
- **Material widgets only** - no Cupertino or custom widgets
- Handle disconnection gracefully (auto-navigate back to scanner)

### Avoid
- Premature abstractions - don't create helpers until needed in 3+ places
- Unnecessary comments - code should be self-explanatory
- Feature flags or backwards-compatibility shims
- Over-engineered error handling for impossible scenarios

## Key Files

| File | Purpose |
|------|---------|
| `lib/main.dart` | App configuration, MultiProvider setup, theme, locale, initial route |
| `lib/connector/meshcore_connector.dart` | Unified BLE/TCP/USB transport state holder |
| `lib/connector/meshcore_protocol.dart` | Frame size limits and protocol version |
| `lib/connector/meshcore_uuids.dart` | NUS UUIDs and BLE scan name prefixes |
| `lib/services/app_settings_service.dart` | App-wide settings (`AppSettings` JSON in SharedPreferences) |
| `lib/services/storage_service.dart` | Path histories, delivery observations and the app-wide maps, in the database or in preferences |
| `lib/storage/node_state.dart` | One JSON value per node and name: the `node_state` row, or the preference key where there is no database |
| `lib/services/message_retry_service.dart` | ACK tracking + retry scheduling |
| `lib/services/translation_service.dart` | On-device LLM translation — **disabled stub** in this build |
| `lib/services/wardrive_service.dart` | Coverage-mapping scanner (Advanced mod) |
| `lib/helpers/mesh_compressor.dart` | MCMP arithmetic-coder text compression (`mcmp2:`) |
| `lib/MCOtxt/mcotxt_codec.dart` | MCOtxt v1 bit codec: header, token tree, planner, decoder |
| `lib/MCOtxt/mcotxt_frame.dart` | Length-prefixed MCOtxt frame for byte containers |
| `lib/helpers/mcotxt_app_codec.dart` | MCOtxt app container (flags, timestamp, name, reply) and the `mct:` transport |
| `lib/helpers/message_text_codec.dart` | Inbound decode across MCMP/MCOtxt/Smaz prefixes |
| `lib/helpers/mcmp_signature_verifier.dart` | App-side Ed25519 verification of MCMP v3 signatures |
| `lib/helpers/exact_quote_helper.dart` | Quote fragments that pin plain-text replies to the message they answer |
| `lib/helpers/message_markup.dart` | Inline `**bold**` / `__italic__` / `~~strike~~` / mono markup parser |
| `lib/helpers/mention_autocomplete.dart` | `@[name]` parsing for the composer and for message rendering |
| `lib/helpers/mcoimg_v3_codec.dart` | MCO image-over-LoRa codec (v3 binary container) |
| `lib/helpers/path_trace_progress_helper.dart` | Matches overheard TRACE retransmissions to the running trace |
| `lib/helpers/direct_message_progress_helper.dart` | Matches overheard message retransmissions to a pending direct message |
| `lib/helpers/direct_echo_recovery.dart` | Decrypts a direct message to us from its RX-log echo before the route completes (opt-in); key store, merge rules, ACK packet |
| `lib/helpers/direct_echo_crypto.dart` | Pure-Dart X25519 shared secret and ACK hash, as the firmware computes them |
| `lib/storage/prefs_manager.dart` | SharedPreferences singleton initialized in `main()`; on Windows and Linux backs up and repairs the preferences file first |
| `lib/storage/message_history_database.dart` | drift schema, queries, legacy import and quarantine (`.g.dart` is committed, see `.gitignore`) |
| `lib/storage/message_history_storage.dart` | The only door to that database; holds the web fallback and the key caches |
| `lib/storage/message_history_maintenance.dart` | Statistics, diagnostic/recovery export, quarantine retry, vacuum |
| `lib/storage/map_tile_cache_database.dart` | The map tile records on Windows and Linux: their database, the move of the JSON index into it, the repository the cache manager drives |
| `lib/storage/data_root_io.dart` | The data folder on Windows and Linux: choosing it (rules in `data_root_core.dart`), sending path_provider and the preference stores into it, its lock |
| `lib/storage/data_transfer_io.dart` | Copying an earlier installation's data into a new data folder, and deleting the old data at a later start |
| `windows/runner/main.cpp` | Windows runner: finds the data folder by the same rules and keeps the window size in it |
| `lib/screens/scanner_screen.dart` | Home screen — BLE scan and connect |
| `lib/screens/mod_settings_screen.dart` | Advanced-mod feature toggles |
| `pubspec.yaml` | Dependencies and project metadata; the `## Dependencies` section above quotes the same version |
