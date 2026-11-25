#!/usr/bin/env bash
# Focused Xfce panel status integration (for xfce4-genmon-plugin) and CLI reporter.
# Read-only; runs as the desktop user with zero privileged calls or daemons.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
SYSTEM_CONF="$REPO_ROOT/linux/config/nexus-system.conf"

MODE="genmon"

usage() {
  cat <<'USAGE'
Usage: bash linux/mint/nexus-panel-status.sh [OPTIONS]

Read-only status output for the NEXUS Xfce panel integration
(xfce4-genmon-plugin) on Linux Mint 22.3 Xfce.

Options:
  --genmon    Print xfce4-genmon-plugin XML (<txt>/<tool>) (default)
  --plain     Print a single-line plain text summary
  --json      Print status fields as JSON
  --help, -h  Show this help message
USAGE
}

while (($#)); do
  case "$1" in
    --genmon) MODE="genmon"; shift ;;
    --plain) MODE="plain"; shift ;;
    --json) MODE="json"; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

escape_xml() {
  local s="$1"
  s="${s//&/&amp;}"
  s="${s//</&lt;}"
  s="${s//>/&gt;}"
  printf '%s' "$s"
}

escape_json() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  printf '%s' "$s"
}

mem_total_kb=0
mem_avail_kb=0
if [[ -r /proc/meminfo ]]; then
  while read -r key val _; do
    case "$key" in
      MemTotal:) mem_total_kb="$val" ;;
      MemAvailable:) mem_avail_kb="$val" ;;
    esac
  done < /proc/meminfo
fi

mem_used_kb=$(( mem_total_kb > mem_avail_kb ? mem_total_kb - mem_avail_kb : 0 ))
mem_used_gib="$(awk -v kb="$mem_used_kb" 'BEGIN { printf "%.1f", kb / 1048576 }')"
mem_total_gib="$(awk -v kb="$mem_total_kb" 'BEGIN { printf "%.1f", kb / 1048576 }')"
mem_avail_mib=$(( mem_avail_kb / 1024 ))

load_1m="unknown"
if [[ -r /proc/loadavg ]]; then
  read -r load_1m _ < /proc/loadavg
fi

battery_label=""
battery_pct=""
battery_state=""
for bat in /sys/class/power_supply/BAT*; do
  [[ -d "$bat" ]] || continue
  if [[ -r "$bat/capacity" ]]; then
    battery_pct="$(cat "$bat/capacity")"
    battery_state="unknown"
    if [[ -r "$bat/status" ]]; then
      battery_state="$(cat "$bat/status")"
    fi
    battery_label="${battery_pct}%"
    break
  fi
done

compositor_state="unknown"
if command -v xfconf-query >/dev/null 2>&1 && [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
  if comp_raw="$(xfconf-query -c xfwm4 -p /general/use_compositing 2>/dev/null)"; then
    if [[ "$comp_raw" == "true" ]]; then
      compositor_state="on"
    elif [[ "$comp_raw" == "false" ]]; then
      compositor_state="off"
    fi
  fi
fi

base_label="Linux Mint 22.3 Xfce"
if [[ -r "$SYSTEM_CONF" ]]; then
  conf_distro=""
  conf_version=""
  conf_edition=""
  while IFS='=' read -r k v; do
    case "$k" in
      NEXUS_BASE_DISTRO) conf_distro="$v" ;;
      NEXUS_BASE_VERSION) conf_version="$v" ;;
      NEXUS_BASE_EDITION) conf_edition="$v" ;;
    esac
  done < "$SYSTEM_CONF"
  if [[ "$conf_distro" == "linuxmint" ]]; then
    conf_distro="Linux Mint"
  fi
  if [[ "$conf_edition" == "xfce" ]]; then
    conf_edition="Xfce"
  fi
  if [[ -n "$conf_distro" && -n "$conf_version" ]]; then
    base_label="${conf_distro} ${conf_version}${conf_edition:+ ${conf_edition}}"
  fi
fi

summary="NEXUS · ${mem_used_gib}/${mem_total_gib}G · load ${load_1m}"
if [[ -n "$battery_label" ]]; then
  summary="${summary} · bat ${battery_label}"
fi

case "$MODE" in
  plain)
    printf '%s\n' "$summary"
    ;;
  genmon)
    nl=$'\n'
    tooltip="NEXUS Panel Status${nl}Base: ${base_label}${nl}RAM used: ${mem_used_gib} / ${mem_total_gib} GiB (${mem_avail_mib} MiB available)${nl}Load (1m): ${load_1m}${nl}Xfwm4 compositor: ${compositor_state}"
    if [[ -n "$battery_label" ]]; then
      tooltip="${tooltip}${nl}Battery: ${battery_label} (${battery_state})"
    fi
    printf '<txt>%s</txt>\n<tool>%s</tool>\n' "$(escape_xml "$summary")" "$(escape_xml "$tooltip")"
    ;;
  json)
    printf '{"summary":"%s","base":"%s","mem_used_gib":"%s","mem_total_gib":"%s","mem_avail_mib":%s,"load_1m":"%s","compositor":"%s","battery_pct":"%s","battery_state":"%s"}\n' \
      "$(escape_json "$summary")" \
      "$(escape_json "$base_label")" \
      "$(escape_json "$mem_used_gib")" \
      "$(escape_json "$mem_total_gib")" \
      "$mem_avail_mib" \
      "$(escape_json "$load_1m")" \
      "$(escape_json "$compositor_state")" \
      "$(escape_json "${battery_pct:-none}")" \
      "$(escape_json "${battery_state:-none}")"
    ;;
esac
