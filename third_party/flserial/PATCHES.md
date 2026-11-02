# Vendored flserial

Base: MeshEnvy/flserial `e1864de9b65cda9656dba804329bdd2890dd5a92`,
version 0.3.5. Imported through MeshCore Open upstream commit
`2474389099238cd044f81632d66a830c36a0cdc1` (merge `caee4d5c`).
Keep this package's MIT license and the licenses under `native_libs/src/`.

## Upstream fixes included in U01

- `src/flserial.cpp`: initialize callback/handle state, create FIFO mutexes
  before starting `SerialThread`, and wait for `fl_set_callback` before
  notifying Dart about bytes received immediately after opening a port.
  Closing the port also releases that wait.
- `src/native_libs/src/impl/unix.cpp`: bind the x86-64 glibc baud setters to
  `GLIBC_2.2.5` and translate newer numeric baud constants to the legacy
  termios values. This avoids introducing a `GLIBC_2.42` dependency for
  these two functions when building on a recent glibc.
- The existing Dart FFI API and exported C declarations are retained. The
  macOS source tree is upstream's separate implementation; it did not
  receive the Linux callback changes in this commit.

## Fork adaptation

The `GLIBC_2.2.5` symbol binding and legacy conversion are restricted to
Linux/glibc **x86-64**. The upstream guard selected every glibc architecture,
although symbol version baselines differ. ARM and other architectures keep
their previous libc calls; this patch does not establish their minimum glibc.

All three build profiles and the active `pubspec.yaml` use
`path: third_party/flserial`. Run `flutter pub get` after switching from
the previous Git dependency so the native build selects this copy.

The later upstream idle-loop fix `bb7a15f4` is **not included in U01**;
it is a separate step in the merge plan.

## Verification

The app's USB baseline tests exercise framing, handshake, lifecycle and work
tracking without opening a native port. They do not reproduce a C++ crash.

On Linux, after building the app, run the native PTY regression against the
actual library, for example from the project root:

```sh
python3 -B tool/test_linux_usb_native.py \
  --library build/linux/x64/release/bundle/lib/libflserial.so
```

This checks early RX before callback installation, close before callback,
bidirectional binary I/O and several baud rates. Each case runs in a separate
process with a timeout so a native crash or hang is reported. It does not
replace a real USB-radio test, hot restart, or testing other architectures.
