#!/usr/bin/env bash
# Exercise native launcher selection across Cinnamon, Xfce, Lite Openbox, and Lite LXQt with harmless stubs.
set -euo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
LAUNCHER="$ROOT_DIR/linux/branding/nexus-launch-app.sh"
APP_DIR="$ROOT_DIR/linux/branding/applications"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
STUB_DIR="$TMP_DIR/bin"
LOG="$TMP_DIR/launch.log"
mkdir -p "$STUB_DIR"
export NEXUS_TEST_LOG="$LOG"

make_stub() {
  local name="$1"
  cat > "$STUB_DIR/$name" <<'STUB'
#!/bin/sh
printf '%s %s\n' "${0##*/}" "$*" >> "$NEXUS_TEST_LOG"
STUB
  chmod 0755 "$STUB_DIR/$name"
}

clear_stubs() {
  rm -f "$STUB_DIR"/*
}

run_case() {
  local expected="$1"
  shift
  : > "$LOG"
  PATH="$STUB_DIR" NEXUS_STORE_CLI="$STUB_DIR/nexus-store-cli" /bin/bash "$LAUNCHER" "$@"
  grep -Fq "$expected" "$LOG" || {
    printf 'Expected launcher output containing %s, got: ' "$expected" >&2
    cat "$LOG" >&2
    exit 1
  }
}

expect_fail() {
  if PATH="$STUB_DIR" NEXUS_STORE_CLI="$STUB_DIR/nexus-store-cli" /bin/bash "$LAUNCHER" "$@" >/dev/null 2>&1; then
    printf 'Expected launcher failure for args: %s\n' "$*" >&2
    exit 1
  fi
}

# 1. Lite LXQt edition utilities
make_stub pcmanfm-qt
run_case "pcmanfm-qt " files
make_stub qterminal
run_case "qterminal " terminal
make_stub qps
run_case "qps " monitor
make_stub lxqt-config
run_case "lxqt-config " settings
make_stub nexus-store-cli
run_case "qterminal -e $STUB_DIR/nexus-store-cli --help" store
clear_stubs

# 2. Lite Openbox edition utilities
make_stub pcmanfm
run_case "pcmanfm " files
make_stub lxterminal
run_case "lxterminal " terminal
make_stub lxtask
run_case "lxtask " monitor
make_stub obconf
run_case "obconf " settings
make_stub nexus-store-cli
run_case "lxterminal -e $STUB_DIR/nexus-store-cli --help" store
clear_stubs

# 3. Xfce edition utilities
make_stub thunar
run_case "thunar " files
make_stub xfce4-terminal
run_case "xfce4-terminal " terminal
make_stub xfce4-taskmanager
run_case "xfce4-taskmanager " monitor
make_stub xfce4-settings-manager
run_case "xfce4-settings-manager " settings
make_stub nexus-store-cli
run_case "xfce4-terminal -x $STUB_DIR/nexus-store-cli --help" store
clear_stubs

# 4. Cinnamon edition utilities
make_stub nemo
run_case "nemo " files
make_stub gnome-terminal
run_case "gnome-terminal " terminal
make_stub gnome-system-monitor
run_case "gnome-system-monitor " monitor
make_stub cinnamon-settings
run_case "cinnamon-settings " settings
make_stub mintinstall
run_case "mintinstall " store
make_stub firefox
run_case "firefox https://example.org" browser https://example.org
clear_stubs

# 4b. Lightweight browser fallback (falkon)
make_stub falkon
run_case "falkon https://example.org" browser https://example.org
clear_stubs

# 5. Missing utility & missing Store CLI failure paths
expect_fail files
expect_fail browser
expect_fail terminal
expect_fail monitor
expect_fail settings
make_stub qterminal
expect_fail store
clear_stubs
expect_fail unknown-target

for pair in \
  "nexus-browser.desktop:browser %u" \
  "nexus-files.desktop:files" \
  "nexus-terminal.desktop:terminal" \
  "nexus-system-monitor.desktop:monitor" \
  "nexus-settings.desktop:settings" \
  "nexus-store.desktop:store"; do
  file="${pair%%:*}"
  target="${pair#*:}"
  grep -Fqx "Exec=/usr/local/bin/nexus-launch-app $target" "$APP_DIR/$file" || {
    echo "Unexpected Exec target in $file" >&2
    exit 1
  }
done

if command -v desktop-file-validate >/dev/null 2>&1; then
  desktop-file-validate "$APP_DIR"/nexus-*.desktop "$ROOT_DIR/linux/branding/nexus-firstboot.desktop"
  echo "PASS desktop-file-validate on all desktop launchers"
fi

echo "PASS native launcher selection across Cinnamon/Xfce/Lite Openbox/Lite LXQt, Store fallback, and missing-tool failure paths"
