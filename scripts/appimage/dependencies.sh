#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'AppImage dependencies: %s\n' "$*" >&2
  return 1
}

is_host_interface() {
  case "$1" in
    linux-vdso.so.*|ld-linux*.so.*|ld64.so.*|libc.so.*|libm.so.*|libpthread.so.*|\
      libdl.so.*|librt.so.*|libresolv.so.*|libutil.so.*|libanl.so.*|\
      libBrokenLocale.so.*|libnss_*.so.*|libGL.so.*|libGLX.so.*|libEGL.so.*|\
      libGLES*.so.*|libOpenGL.so.*|libglapi.so.*|libvulkan.so.*|libdrm*.so.*|libgbm.so.*|\
      libX*.so.*|libxcb*.so.*|libwayland*.so.*|libxkbcommon.so.*)
      return 0
      ;;
    *) return 1 ;;
  esac
}

is_inside_appdir() {
  [[ "$1" == "$2/"* ]]
}

copy_dependency() {
  local appdir="$1" soname="$2" source="$3" source_real real_name library_dir target existing_real
  source_real="$(realpath -e -- "$source")" || {
    fail "Cannot resolve dependency $soname from $source"
    return 1
  }
  [[ -f "$source_real" ]] || { fail "Dependency is not a regular file: $source_real"; return 1; }
  real_name="${source_real##*/}"
  library_dir="$appdir/usr/lib"
  target="$library_dir/$real_name"
  mkdir -p "$library_dir" || return 1
  if [[ -e "$target" || -L "$target" ]]; then
    existing_real="$(realpath -e -- "$target")" || {
      fail "Broken bundled library path: $target"
      return 1
    }
    if ! is_inside_appdir "$existing_real" "$appdir" ||
       { [[ "$existing_real" != "$source_real" ]] && ! cmp -s -- "$existing_real" "$source_real"; }; then
      fail "Conflicting libraries map to $target"
      return 1
    fi
  else
    cp -p -- "$source_real" "$target" || return 1
  fi
  if [[ "$soname" != "$real_name" ]]; then
    if [[ -e "$library_dir/$soname" || -L "$library_dir/$soname" ]]; then
      existing_real="$(realpath -e -- "$library_dir/$soname")" || {
        fail "Broken bundled SONAME link: $library_dir/$soname"
        return 1
      }
      if ! is_inside_appdir "$existing_real" "$appdir" ||
         { [[ "$existing_real" != "$source_real" ]] && ! cmp -s -- "$existing_real" "$source_real"; }; then
        fail "Conflicting libraries provide SONAME $soname"
        return 1
      fi
    else
      ln -s -- "$real_name" "$library_dir/$soname" || return 1
    fi
  fi
}

scan_appdir() {
  local appdir="$1" report="$2" mode="$3" changed_name="$4"
  local elf dynamic output status line soname resolution resolved resolved_real
  local failed=0 copied_any=0
  local -a elf_files=()
  local -a loader_env=(env -u LD_LIBRARY_PATH -u LD_PRELOAD -u LD_AUDIT LC_ALL=C)
  if [[ "$mode" == bundle ]]; then
    # During staging the final RPATH has not been installed yet.
    loader_env+=(LD_LIBRARY_PATH="$appdir/usr/bin/lib:$appdir/usr/lib")
  fi
  : > "$report" || return 1
  # Flutter puts native assets in lib. Skip its data and asset tree.
  # An empty final entry confirms that find completed successfully.
  mapfile -d '' -t elf_files < <(
    find "$appdir/usr/bin" "$appdir/usr/lib" \
      -path "$appdir/usr/bin/data" -prune -o -type f -print0 && printf '\0'
  )
  if ((${#elf_files[@]} == 0)) || [[ -n "${elf_files[-1]}" ]]; then
    fail "Cannot list AppDir files: $appdir"
    return 1
  fi
  unset 'elf_files[-1]'
  for elf in "${elf_files[@]}"; do
    # Ignore scripts, resources and static ELF files. Inspect each real
    # dynamic object once even when several SONAMEs link to it.
    dynamic="$(LC_ALL=C readelf -d "$elf" 2>/dev/null)" || continue
    [[ "$dynamic" == *'(NEEDED)'* ]] || continue
    printf '%s\n' "${elf#"$appdir/"}" >> "$report"
    if output="$("${loader_env[@]}" ldd "$elf" 2>&1)"; then
      status=0
    else
      status=$?
    fi
    while IFS= read -r line; do
      soname=''
      resolution=''
      if [[ "$line" =~ ^[[:space:]]*([^[:space:]]+)[[:space:]]*=\>[[:space:]]*(.*)$ ]]; then
        soname="${BASH_REMATCH[1]}"
        resolution="${BASH_REMATCH[2]}"
      elif [[ "$line" =~ ^[[:space:]]*(/[^[:space:]]+) ]]; then
        resolution="${BASH_REMATCH[1]}"
        soname="${resolution##*/}"
      else
        continue
      fi
      soname="${soname##*/}"
      if [[ "$resolution" == 'not found'* ]]; then
        if is_host_interface "$soname"; then
          printf '  %s => NOT PRESENT ON AUDIT HOST [host interface]\n' "$soname" >> "$report"
        else
          printf '  %s => NOT FOUND\n' "$soname" >> "$report"
          printf 'AppImage dependencies: %s needs missing %s\n' "$elf" "$soname" >&2
          failed=1
        fi
        continue
      fi
      resolved="$resolution"
      if [[ "$resolved" =~ ^(.*[^[:space:]])[[:space:]]+\(0x[[:xdigit:]]+\)$ ]]; then
        resolved="${BASH_REMATCH[1]}"
      fi
      [[ "$resolved" == /* ]] || continue
      if ! resolved_real="$(realpath -e -- "$resolved" 2>/dev/null)"; then
        if is_host_interface "$soname"; then
          printf '  %s => NOT PRESENT ON AUDIT HOST (%s) [host interface]\n' \
            "$soname" "$resolved" >> "$report"
        else
          printf '  %s => UNRESOLVED (%s)\n' "$soname" "$resolved" >> "$report"
          printf 'AppImage dependencies: %s resolves %s to missing path %s\n' \
            "$elf" "$soname" "$resolved" >&2
          failed=1
        fi
        continue
      fi
      if is_inside_appdir "$resolved_real" "$appdir"; then
        printf '  %s => %s [bundled]\n' "$soname" "$resolved_real" >> "$report"
      elif is_host_interface "$soname"; then
        printf '  %s => %s [host interface]\n' "$soname" "$resolved_real" >> "$report"
      elif [[ "$mode" == bundle ]]; then
        printf '  %s => %s [bundling]\n' "$soname" "$resolved_real" >> "$report"
        copy_dependency "$appdir" "$soname" "$resolved_real" || return 1
        copied_any=1
      else
        printf '  %s => %s [unexpected host dependency]\n' "$soname" "$resolved_real" >> "$report"
        printf 'AppImage dependencies: %s resolves non-allowlisted %s from %s\n' \
          "$elf" "$soname" "$resolved_real" >&2
        failed=1
      fi
    done <<< "$output"
    if ((status != 0)) || [[ "$output" =~ version[[:space:]].*not[[:space:]]found ]]; then
      printf 'AppImage dependencies: ldd dependency check failed for %s (exit %s): %s\n' \
        "$elf" "$status" "$output" >&2
      failed=1
    fi
  done
  printf -v "$changed_name" '%s' "$copied_any"
  ((failed == 0))
}

bundle_appdir_dependencies() {
  local appdir="$1" report="$2" pass changed
  for ((pass = 1; pass <= 32; pass++)); do
    scan_appdir "$appdir" "$report" bundle changed || return 1
    ((changed == 1)) || break
  done
  ((pass <= 32)) || { fail 'Dependency closure did not converge after 32 passes'; return 1; }
}

audit_appdir_dependencies() {
  local appdir="$1" report="$2" changed=0
  scan_appdir "$appdir" "$report" audit changed
}

main() {
  [[ $# == 3 ]] || { fail 'Usage: dependencies.sh bundle|audit APPDIR REPORT'; return 1; }
  local mode="$1" appdir report="$3"
  appdir="$(realpath -e -- "$2")" || return 1
  [[ -d "$appdir/usr/bin" && -d "$appdir/usr/lib" ]] || {
    fail "Invalid AppDir: $appdir"
    return 1
  }
  command -v readelf >/dev/null || { fail 'Missing readelf'; return 1; }
  command -v ldd >/dev/null || { fail 'Missing ldd'; return 1; }
  case "$mode" in
    bundle) bundle_appdir_dependencies "$appdir" "$report" ;;
    audit) audit_appdir_dependencies "$appdir" "$report" ;;
    *) fail "Unknown mode: $mode"; return 1 ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
