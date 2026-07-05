# Repository Guidelines

## Project Structure & Module Organization
- Core Flutter code is in `lib/`, with BLE protocol definitions in `lib/connector/meshcore_protocol.dart` and BLE transport/state in `lib/connector/meshcore_connector.dart`.
- UI lives in `lib/screens/` and `lib/widgets/`, models in `lib/models/`, tests in `test/`, and platform runners in `android/`, `ios/`, `macos/`, `linux/`, `windows/`, `web/`.

## BLE Frames & Protocol Notes
- Nordic UART Service (NUS) UUIDs: Service `6e400001-b5a3-f393-e0a9-e50e24dcca9e`, RX `6e400002-b5a3-f393-e0a9-e50e24dcca9e`, TX `6e400003-b5a3-f393-e0a9-e50e24dcca9e`.
- Discovery: scans for device names matching known prefixes and filters by `platformName`/`advertisementData.advName`.
- Frames are capped at `maxFrameSize = 172` bytes; byte 0 is the command/response/push code. I/O is `MeshCoreConnector.sendFrame` and `MeshCoreConnector.receivedFrames`.
- Command codes (to device): `cmdAppStart`=1, `cmdSendTxtMsg`=2, `cmdSendChannelTxtMsg`=3, `cmdGetContacts`=4, `cmdGetDeviceTime`=5, `cmdSetDeviceTime`=6, `cmdSendSelfAdvert`=7, `cmdSetAdvertName`=8, `cmdAddUpdateContact`=9, `cmdSyncNextMessage`=10, `cmdSetRadioParams`=11, `cmdSetRadioTxPower`=12, `cmdResetPath`=13, `cmdSetAdvertLatLon`=14, `cmdRemoveContact`=15, `cmdShareContact`=16, `cmdExportContact`=17, `cmdImportContact`=18, `cmdReboot`=19, `cmdSendLogin`=26, `cmdGetChannel`=31, `cmdSetChannel`=32, `cmdGetRadioSettings`=57.
- Response codes (from device): `respCodeOk`=0, `respCodeErr`=1, `respCodeContactsStart`=2, `respCodeContact`=3, `respCodeEndOfContacts`=4, `respCodeSelfInfo`=5, `respCodeSent`=6, `respCodeContactMsgRecv`=7, `respCodeChannelMsgRecv`=8, `respCodeCurrTime`=9, `respCodeNoMoreMessages`=10, `respCodeContactMsgRecvV3`=16, `respCodeChannelMsgRecvV3`=17, `respCodeChannelInfo`=18, `respCodeRadioSettings`=25.
- Push codes (async): `pushCodeAdvert`=0x80, `pushCodePathUpdated`=0x81, `pushCodeSendConfirmed`=0x82, `pushCodeMsgWaiting`=0x83, `pushCodeLoginSuccess`=0x85, `pushCodeLoginFail`=0x86, `pushCodeLogRxData`=0x88, `pushCodeNewAdvert`=0x8A.
- Device info: `cmdAppStart` triggers `respCodeSelfInfo` with tx power, pubkey, lat/lon, telemetry flags, radio params, and node name (see offsets in `lib/connector/meshcore_connector.dart`).
- Radio/time helpers: `cmdGetRadioSettings` → `respCodeRadioSettings`; `cmdGetDeviceTime` → `respCodeCurrTime`; `cmdSetDeviceTime` updates device time.
- Reboot: the UI sends `sendCliCommand('reboot')` (the raw `cmdReboot` code exists but no frame builder is wired in yet).
- Companion radio format: `cmdSendTxtMsg` expects `[cmd][txt_type][attempt][timestamp x4][pub_key_prefix x6][text...]` (no flags/full pubkey). CLI commands use `txtTypeCliData` in the same format, and the app maps `forceFlood` to attempt `3` when sending.
- Group text packets (`PAYLOAD_TYPE_GRP_TXT`): payload is `[channel_hash (1)][MAC (2)][encrypted data...]`. Decrypted data layout is `[timestamp x4][txt_type][text...]` where text is `"sender: message"` (see MeshCore `BaseChatMesh::sendGroupMessage`). Sender identity is not in the payload; use `PUSH_CODE_LOG_RX_DATA` raw packet path bytes for origin hash when available.
- Identity hash: `PATH_HASH_SIZE` is 1 byte; it is the prefix of the public key (see `Identity::copyHashTo`). Flooded packets append this hash to the path as they traverse hops. Self-identification via log data should compare sender name and presence of self pubkey prefix within the path bytes.

## Build, Test, and Development Commands
- `~/flutter/bin/flutter pub get` installs dependencies (or `flutter pub get` if Flutter is on PATH).
- `~/flutter/bin/flutter run` launches the app; `~/flutter/bin/flutter build apk|ios` produces release builds.
- `~/flutter/bin/flutter analyze` and `~/flutter/bin/flutter test` run linting and tests.

## Coding Style & Naming Conventions
- Follow `flutter_lints`, use `lowerCamelCase`/`UpperCamelCase`/`snake_case`, prefer `StatelessWidget` + `Consumer`, and use `const` constructors.
- Material widgets only; keep screens simple, handle disconnects by returning to the scanner, and avoid premature abstractions.

## Testing Guidelines
- Tests use `flutter_test`; add `*_test.dart` under `test/` and run `flutter test` before UI/protocol changes.

## Commit & Pull Request Guidelines
- Keep commit subjects short and action-focused; PRs should describe behavior changes, link issues, include screenshots for UI changes, and call out BLE protocol changes explicitly.

## Memory

Agentmemory hooks are configured for this project/environment.

Use MCP agentmemory manually only when explicitly useful, for example:
- to recall project context before a complex task;
- to save durable decisions, project conventions, user preferences, or unresolved follow-ups.

Do not save secrets, tokens, passwords, API keys, credentials, private personal data, or temporary/debug-only details.

If agentmemory is unavailable, continue the task normally and mention that memory could not be read or saved.