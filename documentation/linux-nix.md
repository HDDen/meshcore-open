# Linux builds and profiling with Nix

The Nix shell is optional. Existing Windows, Android and other build workflows
continue to work independently. `flake.lock` pins the historical nixpkgs revision
from upstream commit `4454033f`; it has not been refreshed to a newer release.
All build profiles require Flutter 3.47.9 or later. The current Nix lock
provides Flutter 3.47.4, so put a compatible SDK on `PATH` before entering
the shell. The shell includes the packaged SDK when its version meets the
project minimum.

## Enter and check the environment

From the repository root on a Linux host with Nix flakes enabled:

```bash
clear
nix develop
flutter --version
dart --version
command -v flutter dart clang clang++ cmake ninja pkg-config
pkg-config --exists gtk+-3.0 glib-2.0 gio-2.0 sysprof-capture-4 libsecret-1
```

Flutter supplies its matching Dart SDK. Linux uses wrapped Clang with the Nix
headers and linker environment. CMake, Ninja and pkg-config are native build
tools; Sysprof capture headers and libsecret are included for Linux. The shell
leaves pkg-config discovery and the bundle install prefix to their respective
build tools.

Entering the shell prints Android SDK instructions if the SDK is missing. It
does not execute those instructions, run Flutter commands, change the selected
app profile or alter app data. Nix itself may download the locked development
packages when entering an environment that has not yet been cached. Android
SDK warnings do not prevent Linux builds.

## Profiles and native prerequisites

The selected profile stays active: `pubspec.yaml`, service templates and native
plugins continue to follow [the build profile workflow](../README.md#build-profiles-lite--lite-aeic--full).
The shell supports that workflow without copying a profile automatically.
All public manifests use `packages/mco_service_stub`. An existing local private
override is respected; the shell does not create or remove one.

Private builds may require prepared native artifacts in addition to the public
SDK and system headers. Follow the private module's own build instructions.
The common shell does not build private libraries or install a Go toolchain
implicitly; providing Go alone would not prepare those artifacts. Full builds
also retain their existing LLM native hooks. Availability of the shell does not
prove that every profile and private artifact builds on every architecture.

The existing Linux CMake configuration bundles ONNX Runtime for profiles that
use AEIC, preserving the plugin's runtime lookup and SONAME. The lite profile
has no ONNX plugin. The shell does not force a system ONNX installation.

After choosing the intended profile and preparing any required native artifacts:

```bash
clear
flutter pub get
flutter build linux --debug
flutter build linux --profile
flutter test test/tool/nix_environment_merge_baseline_test.dart test/tool/build_profiles_test.dart
flutter analyze
```

These commands are an owner-run acceptance procedure. Static source-contract
tests cover profiles, shell configuration and Linux bundle rules; they do not
evaluate Nix or compile Linux plugins. Check both builds for each profile you
intend to distribute, and check the resulting bundle on the target Linux host.

## Optional Linux AppImage

Build on Ubuntu 24.04 for the target architecture, x86_64 or ARM64. Use the
desired build profile and the Flutter pin from
[appimage-tools.json](../scripts/appimage-tools.json). The manual
[Linux AppImage workflow](../.github/workflows/appimage.yml) lists the build
and packaging tools and runs a launch check in a clean Ubuntu container.

A regular Flutter build produces the existing bundle. Set the packaging
switch for a Release build to also create an AppImage.

```bash
clear
MESHCORE_BUILD_APPIMAGE=1 flutter build linux --release
```

Find `mco-advanced-x86_64.AppImage` or `mco-advanced-aarch64.AppImage` beside
the `bundle` directory in the release build output. The packager verifies
tool hashes and writes an ELF audit. Build the distributable on a compatible
Ubuntu host when developing in Nix.

When you launch the AppImage, `userdata` is created beside the image file.
The same `--data-dir` override as the plain bundle selects another profile.
Relative paths start from the image's directory. Absolute paths work as given.
For a profile that stays with the image and another stored separately:

```bash
clear
./mco-advanced-x86_64.AppImage --data-dir="profiles/Node 868"
./mco-advanced-x86_64.AppImage --data-dir=/srv/mco/node-433
```

The migration restart relaunches the image with the original arguments.
The packager copies the application binary, libraries and assets. Existing
profile directories stay outside the image.

## Bundle, data and stale caches

Launch the profile bundle from a graphical session; use `arm64` instead of
`x64` for an ARM Linux build:

```bash
clear
build/linux/x64/profile/bundle/mco_advanced
```

This fork uses `mco_advanced`, rather than upstream's `meshcore_open` executable.
Its existing [portable data folder](../README.md#portable-data-folder-windows-and-linux)
policy remains active. Keep production history outside generated `build/`
directories before cleaning or rebuilding those directories. The shell does
not relocate, migrate or remove `userdata`.

After an SDK or compiler change, a stale CMake cache can retain an old compiler
or install prefix. Inspect and remove only the affected generated
`build/linux/<architecture>/<mode>/CMakeCache.txt`, then rebuild. If widget tests
report an undecodable `ink_sparkle.frag` after an SDK change, remove only the
generated `build/unit_test_assets` directory and rerun the tests.

## Sysprof

Launch the profile executable through Sysprof from a graphical session and
stop recording with Ctrl+C. Use a new filename for each recording:

```bash
clear
sysprof-cli meshcore.syscap -- build/linux/x64/profile/bundle/mco_advanced
sysprof meshcore.syscap
```

CPU stack sampling requires kernel perf events and suitable host permissions,
potentially through the Sysprof system service and polkit. The shell supplies
tools and libraries; it does not install host services or change permissions.
If opening perf events fails, ask the host administrator to configure profiling
access. Check recording diagnostics and actual samples: a capture file alone
does not prove that CPU stacks were recorded.

An unprivileged recorder smoke test can omit perf and sysprofd:

```bash
clear
sysprof-cli --no-sysprofd --no-perf smoke.syscap -- build/linux/x64/profile/bundle/mco_advanced
```

This smoke test intentionally excludes CPU stack sampling. Neither the Nix
update nor having Sysprof installed demonstrates reduced application CPU use,
energy consumption or radio latency; those require measurements on a device.

## Updating the package pin

A later `nix flake update nixpkgs` is a separate toolchain update. Review the
lockfile change, repeat the intended profile builds, analysis and tests, and
keep the reviewed lockfile with the shell configuration. Do not refresh the
pin as an incidental part of an upstream feature merge.
