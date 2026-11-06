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

## Upstream idle-loop fix included in U16

Upstream `bb7a15f43611803484c45bca0f62b6738016786a` (merge `5eaddcb1`)
adds `setTimeout(10, 10, 0, 0, 0)` before opening a Linux/macOS port, in both
`src/flserial.cpp` and `macos/Classes/flserial.cpp`. Previously a zero POSIX
read timeout made SerialThread continuously poll an empty port. The new
bounded read permits select to sleep. Windows keeps its previous timeout;
the exported ABI, FIFO handling and U01 Linux callback/lifecycle guards remain.

Readiness wakes select immediately, but a short read can continue collecting
bytes until its 10 ms total read deadline. Notification of short RX bursts,
queued TX and idle close can therefore wait approximately one read interval,
plus host scheduling. This is not a guaranteed physical USB latency bound.
Write timeout settings are unchanged. U16 does not fix the pre-existing macOS
early-callback initialization race; native macOS acceptance is separate.
A native rebuild is required; hot reload cannot replace this C++ change.

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
bidirectional binary I/O, several baud rates, close after idle, and RX/TX after
idle. The post-change idle-cpu case also measures one second of quiet process
CPU, requiring less than 10% of one core, then verifies RX/TX. Run this on a
quiet host; a heavily throttled or overloaded machine can distort a CPU ratio.
Each case runs in a separate process with a timeout so a native crash or
hang is reported. It does not replace a real USB-radio test, hot restart, or
testing other architectures.

Before and after changing the native timeout, measure the actual built library
with the same script and options on a quiet Linux host:

```sh
clear
python3 -B tool/benchmark_flserial_idle.py \
  --library build/linux/x64/release/bundle/lib/libflserial.so
```

Use the same build profile, compiler and machine, retaining the old library
outside generated build directories if needed for comparison. The script prints
the library SHA256, process idle CPU (100% means one core), wall/CPU times and
post-idle RX/TX/close timings. It verifies binary RX/TX too. Each sample runs in
a child process with a timeout. An optional `--max-idle-core-percent` limit can
be used as a post-change regression check on a controlled host; no CPU threshold
is applied by default, so the same command also measures the old busy loop.
These measurements do not establish app energy savings or real radio latency.
The post-change Linux/macOS acceptance remains separate from passing Flutter
tests with fake USB transports. In the test runner, idle-cpu is expected to fail
against the old busy-loop library. For before/after measurement without that
assertion, use the benchmark command above.
