#!/usr/bin/env bash
# Select the native application available in the current NEXUS desktop edition.
# Desktop entries call this script directly so they do not depend on shell
# quoting rules inside .desktop Exec values.
set -euo pipefail

STORE_CLI="${NEXUS_STORE_CLI:-/usr/local/bin/nexus-store-cli}"

fail() {
  printf 'NEXUS launcher: %s\n' "$1" >&2
  exit 127
}

has() {
  command -v "$1" >/dev/null 2>&1
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
    for app in qterminal lxterminal; do
      if has "$app"; then exec "$app" -e "$STORE_CLI" --help; fi
    done
    if has gnome-terminal; then exec gnome-terminal -- "$STORE_CLI" --help; fi
    if has xfce4-terminal; then exec xfce4-terminal -x "$STORE_CLI" --help; fi
    if has x-terminal-emulator; then exec x-terminal-emulator -e "$STORE_CLI" --help; fi
    fail "NEXUS Store CLI or a supported terminal emulator is unavailable"
    ;;
  *)
    printf 'Usage: %s {files|terminal|monitor|settings|store}\n' "$0" >&2
    exit 2
    ;;
esac
