#!/usr/bin/env bash
set -euo pipefail

project="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$project/scripts/build_appimage.sh"
temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT

assert_fails() {
  if "$@" >"$temporary/error" 2>&1; then
    printf 'Expected failure: %s\n' "$*" >&2
    exit 1
  fi
}

unset MESHCORE_BUILD_APPIMAGE
assert_fails packaging_enabled Release
MESHCORE_BUILD_APPIMAGE=1 assert_fails packaging_enabled Debug
MESHCORE_BUILD_APPIMAGE=1 assert_fails packaging_enabled Profile
MESHCORE_BUILD_APPIMAGE=1 packaging_enabled Release
[[ "$(canonical_arch x64)" == x86_64 ]]
[[ "$(canonical_arch aarch64)" == aarch64 ]]
[[ "$(canonical_arch arm64)" == aarch64 ]]
assert_fails canonical_arch riscv64
MESHCORE_BUILD_APPIMAGE=0 assert_fails packaging_enabled Release
assert_fails check_bundle "$temporary/missing"

mkdir -p "$temporary/bundle/lib" "$temporary/bundle/data/flutter_assets"
printf '#!/usr/bin/env bash\n' > "$temporary/bundle/mco_advanced"
touch "$temporary/bundle/lib/libapp.so" "$temporary/bundle/data/icudtl.dat"
chmod +x "$temporary/bundle/mco_advanced"
check_bundle "$temporary/bundle"
rm "$temporary/bundle/lib/libapp.so"
assert_fails check_bundle "$temporary/bundle"
touch "$temporary/bundle/lib/libapp.so"
MESHCORE_BUILD_APPIMAGE=0 bash "$project/scripts/build_appimage.sh" \
  "$project" /missing "$temporary/output" Release x64
bash "$project/scripts/build_appimage.sh" "$project" /missing "$temporary/output" Release x64
MESHCORE_BUILD_APPIMAGE=1 bash "$project/scripts/build_appimage.sh" \
  "$project" /missing "$temporary/output" Debug x64
[[ ! -d "$temporary/output" ]]
MESHCORE_BUILD_APPIMAGE=1 assert_fails bash "$project/scripts/build_appimage.sh" \
  "$project" /missing "$temporary/output" Release riscv64
# shellcheck disable=SC2218
jq -e '(.flutter.source_revision | test("^[0-9a-f]{40}$")) and
  (.tools.x86_64.linuxdeploy.sha256 | length == 64) and
  (.tools.aarch64.linuxdeploy.sha256 | length == 64) and
  (.tools.aarch64.appimagetool.sha256 | length == 64) and
  (.tools.aarch64.runtime.sha256 | length == 64)' \
  "$project/scripts/appimage-tools.json" >/dev/null

mkdir -p "$temporary/bundle/userdata" "$temporary/bundle/profiles/Second Profile"
touch "$temporary/bundle/userdata/profile.lock" "$temporary/bundle/profiles/Second Profile/profile.lock"
printf 'plugin\n' > "$temporary/bundle/lib/libflutter_onnxruntime_plugin.so"
printf 'runtime\n' > "$temporary/bundle/lib/libonnxruntime.so.1"
printf 'provider\n' > "$temporary/bundle/lib/libonnxruntime_providers_shared.so"
stage_bundle "$project" "$temporary/bundle" "$temporary/AppDir with spaces"
check_bundle "$temporary/AppDir with spaces/usr/bin"
staged_libs="$temporary/AppDir with spaces/usr/bin/lib"
[[ "$(cat "$staged_libs/libflutter_onnxruntime_plugin.so")" == plugin ]]
[[ "$(cat "$staged_libs/libonnxruntime.so.1")" == runtime ]]
[[ "$(cat "$staged_libs/libonnxruntime_providers_shared.so")" == provider ]]
[[ ! -e "$temporary/AppDir with spaces/usr/bin/userdata" &&
   ! -e "$temporary/AppDir with spaces/usr/bin/profiles" ]]
[[ -f "$temporary/bundle/userdata/profile.lock" &&
   -f "$temporary/bundle/profiles/Second Profile/profile.lock" ]]
[[ -x "$temporary/AppDir with spaces/AppRun" ]]
desktop="$temporary/AppDir with spaces/usr/share/applications/com.monitormx.mcoadvanced.desktop"
grep -Fxq 'Exec=mco_advanced' "$desktop"
grep -Fxq 'Icon=com.monitormx.mcoadvanced' "$desktop"

# Simulate an extracted launch from an unrelated working directory. The
# inner runner must see the outer image and its arguments after GTK hooks run.
appdir="$temporary/AppDir with spaces"
outer_image="$temporary/portable/MCO Advanced.AppImage"
working_dir="$temporary/working directory"
mkdir -p "$appdir/apprun-hooks" "$(dirname "$outer_image")" "$working_dir"
touch "$outer_image"
cat > "$appdir/apprun-hooks/10-test.sh" <<'EOF'
for variable in GIO_EXTRA_MODULES GIO_MODULE_DIR GI_TYPELIB_PATH GTK_PATH \
  GTK_MODULES GDK_PIXBUF_MODULE_FILE; do
  if [[ -v "$variable" ]]; then
    printf 'Unexpected host module override: %s\n' "$variable" >&2
    exit 1
  fi
done
[[ "$GSETTINGS_SCHEMA_DIR" == "$APPDIR/usr/share/glib-2.0/schemas" ]] || exit 1
export MCO_TEST_HOOK_DIR="$APPDIR"
export GIO_MODULE_DIR="$APPDIR/usr/lib/gio/modules"
EOF
cat > "$appdir/usr/bin/mco_advanced" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$APPDIR" "$APPIMAGE" "$PWD" "$MCO_TEST_HOOK_DIR" "$GIO_MODULE_DIR" "$#" "$@"
EOF
chmod +x "$appdir/usr/bin/mco_advanced"
for profile in 'profiles/Second Profile' '/srv/mco/Absolute Profile'; do
  argument="--data-dir=$profile"
  mapfile -t forwarded < <(
    cd "$working_dir"
    APPDIR=/invalid APPIMAGE="$outer_image" \
      GIO_EXTRA_MODULES=/host/gio GIO_MODULE_DIR=/host/gio \
      GI_TYPELIB_PATH=/host/girepository GTK_PATH=/host/gtk \
      GTK_MODULES=host-module GDK_PIXBUF_MODULE_FILE=/host/pixbuf.loaders \
      GSETTINGS_SCHEMA_DIR=/host/schemas \
      "$appdir/AppRun" "$argument"
  )
  [[ "${#forwarded[@]}" == 7 ]]
  [[ "${forwarded[0]}" == "$appdir" && "${forwarded[1]}" == "$outer_image" ]]
  [[ "${forwarded[2]}" == "$working_dir" && "${forwarded[3]}" == "$appdir" ]]
  [[ "${forwarded[4]}" == "$appdir/usr/lib/gio/modules" ]]
  [[ "${forwarded[5]}" == 1 && "${forwarded[6]}" == "$argument" ]]
done

printf 'fixture\n' > "$temporary/input"
checksum="$(sha256sum "$temporary/input")"
checksum="${checksum%% *}"
# shellcheck disable=SC2218
download_verified "file://$temporary/input" "$checksum" "$temporary/cache/tool"
# shellcheck disable=SC2218
download_verified 'https://invalid.example/offline' "$checksum" "$temporary/cache/tool"
assert_fails download_verified "file://$temporary/input" \
  '0000000000000000000000000000000000000000000000000000000000000000' "$temporary/cache/invalid"
[[ ! -e "$temporary/cache/invalid" ]]
printf 'corruption\n' >> "$temporary/cache/tool"
assert_fails download_verified "file://$temporary/input" "$checksum" "$temporary/cache/tool"

# shellcheck disable=SC2329
download_verified() {
  printf '%s %s\n' "$1" "$3" >> "$temporary/tool-selection"
  mkdir -p "$(dirname "$3")"
  : > "$3"
}

prepare_tools "$project/scripts/appimage-tools.json" "$temporary/tools-x64" x86_64
prepare_tools "$project/scripts/appimage-tools.json" "$temporary/tools-arm64" aarch64
grep -Fq 'linuxdeploy-x86_64.AppImage' "$temporary/tool-selection"
grep -Fq 'appimagetool-x86_64.AppImage' "$temporary/tool-selection"
grep -Fq 'runtime-x86_64' "$temporary/tool-selection"
grep -Fq 'linuxdeploy-aarch64.AppImage' "$temporary/tool-selection"
grep -Fq 'appimagetool-aarch64.AppImage' "$temporary/tool-selection"
grep -Fq 'runtime-aarch64' "$temporary/tool-selection"
unset -f download_verified

# shellcheck disable=SC2329
readelf() {
  printf '%s\n' "$mock_interpreter"
}

# shellcheck disable=SC2329
getconf() {
  printf 'glibc %s\n' "$mock_glibc"
}

mock_interpreter=/lib64/ld-linux-x86-64.so.2
mock_glibc=2.39
assert_fails bundle_needs_rebuild "$temporary/bundle/mco_advanced" 2.39
mock_glibc=2.43
bundle_needs_rebuild "$temporary/bundle/mco_advanced" 2.39
mock_interpreter=/nix/store/glibc/lib/ld-linux-x86-64.so.2
mock_glibc=2.39
bundle_needs_rebuild "$temporary/bundle/mco_advanced" 2.39
unset -f readelf getconf

# Loader fixtures exercise dependency closure without building a Linux bundle.
audit_appdir="$temporary/audit AppDir"
host_libs="$temporary/host libraries"
fakebin="$temporary/fakebin"
mkdir -p "$audit_appdir/usr/bin/lib" "$audit_appdir/usr/lib" "$host_libs" "$fakebin"
printf 'runner\n' > "$audit_appdir/usr/bin/mco_advanced"
printf 'plugin\n' > "$audit_appdir/usr/bin/lib/libflutter_onnxruntime_plugin.so"
printf 'gpg\n' > "$host_libs/libgpg-error.so.0.37.0"
printf 'extra\n' > "$host_libs/libextra.so.1"
printf 'wayland\n' > "$host_libs/libwayland-client.so.0"

cat > "$fakebin/readelf" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == -d ]] || exit 2
printf '0x0000000000000001 (NEEDED)\n'
EOF
cat > "$fakebin/ldd" <<'EOF'
#!/usr/bin/env bash
set -eu
[[ ! -v LD_PRELOAD && ! -v LD_AUDIT ]] || exit 2
case "${1##*/}" in
  mco_advanced)
    printf 'libwayland-client.so.0 => %s/libwayland-client.so.0 (0x1)\n' "$MCO_TEST_HOST"
    printf 'libGL.so.1 => not found\n'
    if [[ "${MCO_TEST_BAD_VERSION:-0}" == 1 ]]; then
      printf "libc.so.6: version 'GLIBC_2.39' not found\n"
    fi
    ;;
  libflutter_onnxruntime_plugin.so)
    if [[ "${MCO_TEST_MISSING:-0}" == 1 ]]; then
      printf 'libgpg-error.so.0 => not found\n'
    elif [[ -e "$MCO_TEST_APPDIR/usr/lib/libgpg-error.so.0" ]] &&
         { [[ "${MCO_TEST_NEEDS_PATH:-0}" != 1 ]] || [[ -v LD_LIBRARY_PATH ]]; }; then
      printf 'libgpg-error.so.0 => %s/usr/lib/libgpg-error.so.0 (0x1)\n' "$MCO_TEST_APPDIR"
    else
      printf 'libgpg-error.so.0 => %s/libgpg-error.so.0.37.0 (0x1)\n' "$MCO_TEST_HOST"
    fi
    ;;
  libgpg-error.so.0.37.0)
    if [[ -e "$MCO_TEST_APPDIR/usr/lib/libextra.so.1" ]]; then
      printf 'libextra.so.1 => %s/usr/lib/libextra.so.1 (0x1)\n' "$MCO_TEST_APPDIR"
    else
      printf 'libextra.so.1 => %s/libextra.so.1 (0x1)\n' "$MCO_TEST_HOST"
    fi
    ;;
esac
EOF
chmod +x "$fakebin/readelf" "$fakebin/ldd"

check_dependencies() {
  MCO_TEST_APPDIR="$audit_appdir" MCO_TEST_HOST="$host_libs" \
    PATH="$fakebin:$PATH" \
    bash "$project/scripts/appimage/dependencies.sh" "$1" "$audit_appdir" \
    "$temporary/dependencies.log"
}
assert_fails check_dependencies audit
grep -Fq '[unexpected host dependency]' "$temporary/dependencies.log"

check_dependencies bundle
[[ -L "$audit_appdir/usr/lib/libgpg-error.so.0" ]]
[[ -f "$audit_appdir/usr/lib/libgpg-error.so.0.37.0" ]]
[[ -f "$audit_appdir/usr/lib/libextra.so.1" ]]
[[ ! -e "$audit_appdir/usr/lib/libwayland-client.so.0" ]]
check_dependencies audit
grep -Fq 'libextra.so.1 =>' "$temporary/dependencies.log"
grep -Fq '[host interface]' "$temporary/dependencies.log"
grep -Fq 'libGL.so.1 => NOT PRESENT ON AUDIT HOST' "$temporary/dependencies.log"

LD_LIBRARY_PATH=/host/invalid MCO_TEST_NEEDS_PATH=1 assert_fails check_dependencies audit
grep -Fq '[unexpected host dependency]' "$temporary/dependencies.log"
MCO_TEST_MISSING=1 assert_fails check_dependencies audit
grep -Fq 'libgpg-error.so.0 => NOT FOUND' "$temporary/dependencies.log"
MCO_TEST_BAD_VERSION=1 assert_fails check_dependencies audit
grep -Fq "version 'GLIBC_2.39' not found" "$temporary/error"

printf 'AppImage packaging contract tests passed\n'
