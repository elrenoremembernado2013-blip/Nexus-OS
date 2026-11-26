#!/usr/bin/env bash
# NEXUS OS Phase 13.0 Physical-GPU Browser Qualification Helper (Falkon vs Firefox).
# Measures startup, page load, WebGL, HTML5 video capability, RAM/RSS, CPU, ZRAM/swap,
# multi-tab stability (1/2/4/6), crashes, OOMs, and post-close memory recovery.
# Strictly separates genuine hardware GPU acceleration from QEMU/llvmpipe software rendering.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
BENCH_PY="$REPO_ROOT/linux/test/nexus-browser-bench.py"
[[ -r "$BENCH_PY" ]] || BENCH_PY="/usr/local/share/nexus-os/hardware/nexus-browser-bench.py"

EDITION="auto"
BROWSERS="falkon,firefox"
OUT_JSON=""
DRY_RUN=false
CONFIRMED=false

usage() {
  cat <<'USAGE'
Usage: bash linux/hardware/nexus-browser-qualify.sh [OPTIONS]

Runs repeatable browser qualification (Firefox vs Falkon) inside a booted
X11 desktop session on NEXUS Standard (Cinnamon), MADOO (Xfce), NEXUS Lite
(Openbox), or NEXUS Lite LXQt.

Options:
  --edition NAME      Edition label (auto, cinnamon, xfce, lite, lite-lxqt)
  --browsers LIST     Comma-separated browsers (default: falkon,firefox)
  --out PATH          Save redacted JSON result to PATH
  --confirm           Confirm running standalone browser benchmark
  --dry-run           Print planned benchmark procedure without launching browsers
  --help, -h          Show this help message
USAGE
}

while (($#)); do
  case "$1" in
    --edition) [[ $# -ge 2 ]] || { echo '--edition requires a value' >&2; exit 2; }; EDITION="$2"; shift 2 ;;
    --browsers) [[ $# -ge 2 ]] || { echo '--browsers requires a value' >&2; exit 2; }; BROWSERS="$2"; shift 2 ;;
    --out) [[ $# -ge 2 ]] || { echo '--out requires a path' >&2; exit 2; }; OUT_JSON="$2"; shift 2 ;;
    --confirm) CONFIRMED=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ "$EDITION" == "auto" && -r /etc/nexus-os-release ]]; then
  while IFS='=' read -r k v; do
    v="${v%\"}"
    v="${v#\"}"
    if [[ "$k" == "NEXUS_EDITION" || "$k" == "NEXUS_DESKTOP" ]]; then
      [[ -n "$v" ]] && EDITION="$v"
    fi
  done < /etc/nexus-os-release
fi

echo "=== NEXUS OS Browser & GPU Qualification Plan ==="
echo "  Edition:   $EDITION"
echo "  Browsers:  $BROWSERS"
echo "  Metrics:   startup, page load, WebGL/renderer, HTML5 video codecs, RSS/RAM, CPU, ZRAM/swap, 1/2/4/6 tabs, OOM/crashes, post-close recovery"
echo "  Notice:    Falkon and Firefox remain optional on Lite editions; QEMU llvmpipe results do NOT qualify physical GPUs."

if [[ "$DRY_RUN" == true ]]; then
  echo "[dry-run] Would invoke: python3 $BENCH_PY --standalone --edition $EDITION --browsers $BROWSERS${OUT_JSON:+ --out $OUT_JSON}"
  exit 0
fi

if [[ "$CONFIRMED" != true ]]; then
  echo "Refusing to launch browsers without --confirm (use --dry-run to preview)." >&2
  exit 3
fi

[[ -r "$BENCH_PY" ]] || { printf 'Missing benchmark runner: %s\n' "$BENCH_PY" >&2; exit 1; }
[[ -n "${DISPLAY:-}" ]] || { echo 'Error: active X11 DISPLAY required to benchmark GUI browsers.' >&2; exit 2; }

cmd=(python3 "$BENCH_PY" --standalone --edition "$EDITION" --browsers "$BROWSERS")
[[ -z "$OUT_JSON" ]] || cmd+=(--out "$OUT_JSON")
exec "${cmd[@]}"
