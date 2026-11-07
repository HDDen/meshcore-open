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
touch "$temporary/bundle/mco_advanced" "$temporary/bundle/lib/libapp.so" \
  "$temporary/bundle/data/icudtl.dat"
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
stage_bundle "$project" "$temporary/bundle" "$temporary/AppDir with spaces"
check_bundle "$temporary/AppDir with spaces/usr/bin"
[[ ! -e "$temporary/AppDir with spaces/usr/bin/userdata" &&
   ! -e "$temporary/AppDir with spaces/usr/bin/profiles" ]]
[[ -f "$temporary/bundle/userdata/profile.lock" &&
   -f "$temporary/bundle/profiles/Second Profile/profile.lock" ]]
[[ -x "$temporary/AppDir with spaces/AppRun" ]]
desktop="$temporary/AppDir with spaces/usr/share/applications/com.monitormx.mcoadvanced.desktop"
grep -Fxq 'Exec=mco_advanced' "$desktop"
grep -Fxq 'Icon=com.monitormx.mcoadvanced' "$desktop"

# Verify that AppRun forwards the profile argument as one argument.
cat > "$temporary/AppDir with spaces/usr/bin/mco_advanced" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$#:$1"
EOF
chmod +x "$temporary/AppDir with spaces/usr/bin/mco_advanced"
forwarded="$("$temporary/AppDir with spaces/AppRun" '--data-dir=profiles/Second Profile')"
[[ "$forwarded" == '1:--data-dir=profiles/Second Profile' ]]
forwarded="$("$temporary/AppDir with spaces/AppRun" '--data-dir=/srv/mco/Absolute Profile')"
[[ "$forwarded" == '1:--data-dir=/srv/mco/Absolute Profile' ]]

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

printf 'AppImage packaging contract tests passed\n'
