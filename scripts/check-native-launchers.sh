#!/usr/bin/env bash
# Exercise native launcher selection with harmless stub applications.
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

make_stub pcmanfm-qt
run_case "pcmanfm-qt " files
rm "$STUB_DIR/pcmanfm-qt"

make_stub qterminal
run_case "qterminal " terminal
rm "$STUB_DIR/qterminal"

make_stub qps
run_case "qps " monitor
rm "$STUB_DIR/qps"

make_stub lxqt-config
run_case "lxqt-config " settings
rm "$STUB_DIR/lxqt-config"

make_stub nexus-store-cli
run_case "qterminal -e $STUB_DIR/nexus-store-cli --help" store

make_stub mintinstall
run_case "mintinstall " store

for pair in \
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
  desktop-file-validate "$APP_DIR"/nexus-*.desktop
fi

echo "PASS native launcher selection, Store fallback, and desktop Exec targets"
