#!/usr/bin/env bash
# Select the native application available in the current NEXUS desktop edition.
# Desktop entries call this script directly so they do not depend on shell
# quoting rules inside .desktop Exec values.
set -euo pipefail

STORE_CLI="${NEXUS_STORE_CLI:-/usr/local/bin/nexus-store-cli}"
FIRSTBOOT_CLI="${NEXUS_FIRSTBOOT_CLI:-/usr/local/bin/nexus-firstboot}"

fail() {
  printf 'NEXUS launcher: %s\n' "$1" >&2
  exit 127
}

has() {
  command -v "$1" >/dev/null 2>&1
}

run_in_terminal() {
  local target="$1"
  shift
  for app in qterminal lxterminal; do
    if has "$app"; then exec "$app" -e "$target" "$@"; fi
  done
  if has gnome-terminal; then exec gnome-terminal -- "$target" "$@"; fi
  if has xfce4-terminal; then exec xfce4-terminal -x "$target" "$@"; fi
  if has x-terminal-emulator; then exec x-terminal-emulator -e "$target" "$@"; fi
  return 1
}

case "${1:-}" in
  files)
    shift
    for app in nemo pcmanfm-qt pcmanfm thunar; do
      if has "$app"; then exec "$app" "$@"; fi
    done
    fail "no supported file manager is installed"
    ;;
  browser)
    shift
    for app in firefox chromium chromium-browser falkon x-www-browser; do
      if has "$app"; then exec "$app" "$@"; fi
    done
    fail "no supported web browser is installed (install firefox or falkon via NEXUS Store)"
    ;;
  terminal)
    shift
    for app in qterminal lxterminal gnome-terminal xfce4-terminal x-terminal-emulator; do
      if has "$app"; then exec "$app" "$@"; fi
    done
    fail "no supported terminal emulator is installed"
    ;;
  monitor)
    shift
    for app in gnome-system-monitor qps lxtask xfce4-taskmanager; do
      if has "$app"; then exec "$app" "$@"; fi
    done
    fail "no supported system monitor is installed"
    ;;
  settings)
    shift
    for app in cinnamon-settings xfce4-settings-manager lxqt-config obconf-qt obconf; do
      if has "$app"; then exec "$app" "$@"; fi
    done
    fail "no supported settings manager is installed"
    ;;
  store)
    shift
    if has mintinstall; then exec mintinstall "$@"; fi
    [[ -x "$STORE_CLI" ]] || fail "NEXUS Store CLI is not installed at $STORE_CLI"
    run_in_terminal "$STORE_CLI" --help || fail "no supported terminal emulator is available for NEXUS Store CLI"
    ;;
  firstboot)
    shift
    [[ -x "$FIRSTBOOT_CLI" ]] || fail "NEXUS First-Boot helper is not installed at $FIRSTBOOT_CLI"
    run_in_terminal "$FIRSTBOOT_CLI" "$@" || fail "no supported terminal emulator is available for NEXUS First-Boot"
    ;;
  *)
    printf 'Usage: %s {files|browser|terminal|monitor|settings|store|firstboot}\n' "$0" >&2
    exit 2
    ;;
esac
