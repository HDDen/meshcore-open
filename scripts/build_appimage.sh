#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'AppImage: %s\n' "$*" >&2
  return 1
}

packaging_enabled() {
  [[ "${MESHCORE_BUILD_APPIMAGE:-0}" == 1 && "$1" == Release ]]
}

canonical_arch() {
  case "$1" in
    x64|x86_64) printf 'x86_64\n' ;;
    arm64|aarch64) printf 'aarch64\n' ;;
    *) fail "Unsupported AppImage architecture: $1"; return 1 ;;
  esac
}

check_bundle() {
  local bundle="$1"
  [[ -x "$bundle/mco_advanced" && -f "$bundle/lib/libapp.so" && \
    -f "$bundle/data/icudtl.dat" && -d "$bundle/data/flutter_assets" ]] || \
    fail "Incomplete release bundle: $bundle"
}

download_verified() {
  local url="$1" checksum="$2" destination="$3" temporary
  mkdir -p "$(dirname "$destination")"
  if [[ -f "$destination" ]]; then
    if printf '%s  %s\n' "$checksum" "$destination" | sha256sum --check --status; then
      return
    fi
    fail "Cached tool checksum mismatch: $destination; remove it and retry"
    return 1
  fi
  temporary="$(mktemp "$destination.download.XXXXXX")"
  if ! curl --fail --location --retry 3 --connect-timeout 20 --max-time 600 \
    --output "$temporary" "$url"; then
    rm -f "$temporary"
    fail "Cannot download $url; populate the verified cache or disable packaging with MESHCORE_BUILD_APPIMAGE=0"
    return 1
  fi
  if ! printf '%s  %s\n' "$checksum" "$temporary" | sha256sum --check --status; then
    rm -f "$temporary"
    fail "Downloaded tool checksum mismatch: $url"
    return 1
  fi
  mv "$temporary" "$destination"
}

require_tools() {
  local tool
  for tool in "$@"; do
    command -v "$tool" >/dev/null || {
      fail "Missing $tool; see README Linux AppImage prerequisites or set MESHCORE_BUILD_APPIMAGE=0"
      return 1
    }
  done
}

prepare_tools() {
  local manifest="$1" cache="$2" architecture="$3" tool url checksum
  mkdir -p "$cache"
  exec {cache_lock}>"$cache/tools.lock"
  flock "$cache_lock"
  for tool in linuxdeploy appimagetool gtk runtime; do
    if [[ "$tool" == gtk ]]; then
      url="$(jq -er '.tools.gtk.url' "$manifest")"
      checksum="$(jq -er '.tools.gtk.sha256' "$manifest")"
    else
      url="$(jq -er --arg arch "$architecture" --arg tool "$tool" '.tools[$arch][$tool].url' "$manifest")"
      checksum="$(jq -er --arg arch "$architecture" --arg tool "$tool" '.tools[$arch][$tool].sha256' "$manifest")"
    fi
    download_verified "$url" "$checksum" "$cache/$tool"
    chmod +x "$cache/$tool"
  done
  flock -u "$cache_lock"
  exec {cache_lock}>&-
}

extract_tool() {
  local tool="$1" destination="$2"
  mkdir -p "$destination"
  cp "$tool" "$destination/extractor"
  printf '\0\0\0' | dd of="$destination/extractor" bs=1 seek=8 count=3 conv=notrunc status=none
  (cd "$destination" && ./extractor --appimage-extract >/dev/null)
}

stage_bundle() {
  local project="$1" bundle="$2" appdir="$3" identity=com.monitormx.mcoadvanced
  mkdir -p "$appdir/usr/bin" "$appdir/usr/share/applications" \
    "$appdir/usr/share/icons/hicolor/256x256/apps"
  # Only stage the installed application. The bundle directory may also
  # contain userdata or named profiles from a developer's local runs.
  cp -a "$bundle/mco_advanced" "$bundle/lib" "$bundle/data" "$appdir/usr/bin/"
  install -m 644 "$project/scripts/appimage/$identity.desktop" "$appdir/usr/share/applications/"
  install -m 644 "$project/mesh-icon.png" "$appdir/usr/share/icons/hicolor/256x256/apps/$identity.png"
  install -m 755 "$project/scripts/appimage/AppRun" "$appdir/AppRun"
}

audit_appdir() {
  local appdir="$1" report="$2" library rpath interpreter needed
  : > "$report"
  while IFS= read -r -d '' library; do
    readelf -h "$library" >/dev/null 2>&1 || continue
    rpath="$(patchelf --print-rpath "$library")"
    interpreter="$(patchelf --print-interpreter "$library" 2>/dev/null || true)"
    needed="$(patchelf --print-needed "$library")"
    if [[ "$rpath$interpreter$needed" == *'/nix/store/'* || \
      "$rpath" == *"$appdir"* ]]; then
      fail "Non-relocatable ELF: $library"
      return 1
    fi
    printf '%s\n  interpreter: %s\n  rpath: %s\n%s\n' \
      "${library#"$appdir/"}" "$interpreter" "$rpath" "$needed" >> "$report"
  done < <(find "$appdir" -type f -print0)
}

package_direct() {
  local project="$1" bundle="$2" output="$3" manifest="$4" cache="$5" architecture="$6"
  local work appdir library relative linuxdeploy appimagetool appimage_name plugins
  local rpath_flags=()
  local dependencies=()
  require_tools curl jq sha256sum flock file readelf patchelf pkg-config \
    desktop-file-validate glib-compile-schemas gdk-pixbuf-thumbnailer xdg-user-dir
  pkg-config --exists gtk+-3.0 librsvg-2.0 gobject-introspection-1.0 || \
    { fail 'Missing GTK, librsvg or GObject introspection development files'; return 1; }
  prepare_tools "$manifest" "$cache" "$architecture"
  appimage_name="mco-advanced-$architecture.AppImage"
  work="$(mktemp -d "$output/appimage.XXXXXX")"
  # shellcheck disable=SC2064
  trap "rm -rf -- $(printf '%q' "$work")" EXIT
  appdir="$work/AppDir"
  extract_tool "$cache/linuxdeploy" "$work/linuxdeploy"
  extract_tool "$cache/appimagetool" "$work/appimagetool"
  linuxdeploy="$work/linuxdeploy/squashfs-root/AppRun"
  appimagetool="$work/appimagetool/squashfs-root/AppRun"
  install -m 755 "$cache/gtk" "$work/linuxdeploy/squashfs-root/linuxdeploy-plugin-gtk.sh"
  export PATH="$work/linuxdeploy/squashfs-root:$PATH"
  stage_bundle "$project" "$bundle" "$appdir"
  install -m 755 "$(command -v xdg-user-dir)" "$appdir/usr/bin/xdg-user-dir"
  gdk-pixbuf-thumbnailer --size 256 "$project/mesh-icon.png" \
    "$appdir/usr/share/icons/hicolor/256x256/apps/com.monitormx.mcoadvanced.png"
  desktop-file-validate "$appdir/usr/share/applications/com.monitormx.mcoadvanced.desktop"
  export DEPLOY_GTK_VERSION=3 NO_STRIP=1
  "$linuxdeploy" --appdir "$appdir" --executable "$appdir/usr/bin/mco_advanced" \
    --library "$(pkg-config --variable=libdir harfbuzz)/libharfbuzz.so.0" \
    --library "$(pkg-config --variable=libdir freetype2)/libfreetype.so.6" \
    --library "$(pkg-config --variable=libdir fontconfig)/libfontconfig.so.1" \
    --library "$(pkg-config --variable=libdir fribidi)/libfribidi.so.0" \
    --desktop-file "$appdir/usr/share/applications/com.monitormx.mcoadvanced.desktop" \
    --icon-file "$appdir/usr/share/icons/hicolor/256x256/apps/com.monitormx.mcoadvanced.png" \
    --plugin gtk
  while IFS= read -r -d '' library; do
    readelf -h "$library" >/dev/null 2>&1 || continue
    dependencies+=(--deploy-deps-only "$library")
  done < <(find "$appdir/usr/bin/lib" -type f -print0)
  "$linuxdeploy" --appdir "$appdir" "${dependencies[@]}"
  while IFS= read -r -d '' library; do
    readelf -h "$library" >/dev/null 2>&1 || continue
    relative="$(realpath --relative-to="$(dirname "$library")" "$appdir/usr/lib")"
    # Keep DT_RPATH for the runner's indirect ONNX dependencies.
    rpath_flags=()
    if [[ "$library" == "$appdir/usr/bin/mco_advanced" ||
          "$(readelf -d "$library")" == *'(RPATH)'* ]]; then
      rpath_flags+=(--force-rpath)
    fi
    patchelf "${rpath_flags[@]}" --set-rpath "\$ORIGIN:\$ORIGIN/lib:\$ORIGIN/$relative" "$library"
  done < <(find "$appdir" -type f -print0)
  install -m 755 "$project/scripts/appimage/AppRun" "$appdir/AppRun"
  mkdir -p "$appdir/usr/share/doc/mco-advanced"
  cp "$project/LICENSE" "$appdir/usr/share/doc/mco-advanced/"
  while IFS= read -r -d '' library; do
    relative="${library#/usr/share/doc/}"
    mkdir -p "$appdir/usr/share/doc/mco-advanced/$(dirname "$relative")"
    cp -L "$library" "$appdir/usr/share/doc/mco-advanced/$relative"
  done < <(find -L /usr/share/doc -name copyright -type f -print0)
  plugins="$(dirname "$bundle")/plugins"
  if [[ -d "$plugins" ]]; then
    while IFS= read -r -d '' library; do
      relative="${library#"$plugins/"}"
      mkdir -p "$appdir/usr/share/doc/mco-advanced/build-notices/$(dirname "$relative")"
      cp -L "$library" "$appdir/usr/share/doc/mco-advanced/build-notices/$relative"
    done < <(find "$plugins" -type f \
      \( -iname LICENSE -o -iname NOTICE -o -name ThirdPartyNotices.txt \) -print0)
  fi
  if [[ -n "${PUB_CACHE:-}" && -d "$PUB_CACHE/hosted" ]]; then
    while IFS= read -r -d '' library; do
      relative="${library#"$PUB_CACHE/"}"
      mkdir -p "$appdir/usr/share/doc/mco-advanced/packages/$(dirname "$relative")"
      cp -L "$library" "$appdir/usr/share/doc/mco-advanced/packages/$relative"
    done < <(find "$PUB_CACHE/hosted" -maxdepth 4 -type f \
      \( -iname LICENSE -o -iname NOTICE \) -print0)
  fi
  if [[ -n "${MESHCORE_APPIMAGE_FLUTTER_ROOT:-}" &&
        -f "$MESHCORE_APPIMAGE_FLUTTER_ROOT/LICENSE" ]]; then
    cp "$MESHCORE_APPIMAGE_FLUTTER_ROOT/LICENSE" "$appdir/usr/share/doc/mco-advanced/Flutter-LICENSE"
  fi
  audit_appdir "$appdir" "$work/audit.txt"
  ARCH="$architecture" "$appimagetool" --runtime-file "$cache/runtime" --no-appstream \
    "$appdir" "$work/$appimage_name"
  chmod +x "$work/$appimage_name"
  mv "$work/$appimage_name" "$output/$appimage_name"
  mv "$work/audit.txt" "$output/appimage-audit.txt"
  cp "$manifest" "$output/appimage-tools.json"
  rm -rf "$work"
  trap - EXIT
}

bundle_needs_rebuild() {
  local executable="$1" baseline="$2" host_glibc host_major host_minor baseline_major baseline_minor
  if [[ "$(readelf -l "$executable")" == *'/nix/store/'* ]]; then
    return 0
  fi
  host_glibc="$(getconf GNU_LIBC_VERSION)" || return 0
  host_glibc="${host_glibc#glibc }"
  host_major="${host_glibc%%.*}"
  host_minor="${host_glibc#*.}"
  host_minor="${host_minor%%.*}"
  baseline_major="${baseline%%.*}"
  baseline_minor="${baseline#*.}"
  [[ "$host_major" =~ ^[0-9]+$ && "$host_minor" =~ ^[0-9]+$ ]] || return 0
  (( host_major > baseline_major || (host_major == baseline_major && host_minor > baseline_minor) ))
}

main() {
  [[ $# == 5 ]] || { fail 'Expected: project bundle output configuration architecture'; return 1; }
  local project="$1" bundle="$2" output="$3" configuration="$4" architecture="$5"
  packaging_enabled "$configuration" || return 0
  architecture="$(canonical_arch "$architecture")" || return 1
  check_bundle "$bundle"
  require_tools jq readelf sha256sum flock getconf
  mkdir -p "$output"
  output="$(realpath "$output")"
  exec {output_lock}>"$output/appimage.lock"
  flock "$output_lock"
  local manifest="$project/scripts/appimage-tools.json" pin cache
  pin="$(sha256sum "$manifest")"
  pin="${pin%% *}"
  cache="${XDG_CACHE_HOME:-$HOME/.cache}/mco-advanced/appimage/$pin/$architecture"
  if bundle_needs_rebuild "$bundle/mco_advanced" "$(jq -er '.glibc' "$manifest")"; then
    fail 'Build the Linux bundle on Ubuntu 24.04 (glibc 2.39) before packaging.'
    return 1
  fi
  local host_arch
  host_arch="$(canonical_arch "$(uname -m)")" || return 1
  if [[ "$host_arch" != "$architecture" ]]; then
    fail "AppImage packaging must run on $architecture (found $host_arch)"
    return 1
  fi
  package_direct "$project" "$bundle" "$output" "$manifest" "$cache" "$architecture"
  printf 'AppImage created: %s/mco-advanced-%s.AppImage\n' "$output" "$architecture"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
