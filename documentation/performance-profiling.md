# Performance and memory profiling

Use `flutter run --profile` to measure frame times and memory after repeating
the same actions. Debug builds also retain Dart source, JIT code and debugger
objects, so their process memory is not a release-build baseline.

## HTTP recording retains response bodies

Dart's HTTP timeline logging defaults to off. The app does not enable it.
Developer tools can enable it through the VM service, independently of the
app's debug-log settings. When enabled, Dart retains HTTP request records and
response bodies until those captures are cleared. Map browsing and downloads
can therefore increase profiling memory even after the app stops displaying
the downloaded images. Stopping recording does not clear earlier captures.

For a memory baseline, stop HTTP recording and clear its captures in DevTools'
Network view. Close or disconnect tools that turn recording back on. If the
Network controls are unavailable, run this command from the repository root
with the Dart VM service URI printed by `flutter run`:

```sh
dart run scripts/reset_http_profile.dart http://127.0.0.1:PORT/TOKEN=/
```

This explicitly stops HTTP recording and clears the retained Dart HTTP profile
in the running app's main isolate. Save any captures you need first. It does
not delete downloaded map tiles, change app settings, stop network requests or
change CPU/timeline profiling. You can enable HTTP recording again in DevTools
when investigating network requests. Other HTTP profiling providers may keep
their own records; the command reports any requests that remain.

After clearing, use DevTools' memory view to collect garbage and compare live
heap snapshots at the same point in the workflow. Process RSS can remain high
because the runtime and native libraries can keep reusable allocations; a
larger RSS alone does not establish a leak. Keep frame measurements collected
before heap inspection separate from collection pauses caused by diagnostics.

## Local history storage

This fork retains its existing Drift/SQLite message-history database and
profile store. It does not create upstream's `history_v1.db` or install a
second history backend. See [message history storage](message-history-storage.md)
for migration, quarantine, recovery, and backup instructions.

Direct and channel history use cursor pagination; concurrent requests for the
same boundary share a read. A page belonging to a replaced radio/channel or a
cleared history is discarded, and messages arriving during a read remain in the
live conversation. Map unread badges update separately from its layers. The
fork retains session-only camera memory rather than persisting upstream's
`map_last_camera` preference.
