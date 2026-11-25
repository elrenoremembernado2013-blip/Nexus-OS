#!/usr/bin/env bash
# Check host prerequisites for building a Linux Mint 22.3 Xfce based NEXUS OS ISO.
# Read-only; never installs packages or modifies host configuration.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
DOWNLOAD_DIR="${NEXUS_DOWNLOAD_DIR:-$REPO_ROOT/build/downloads}"
BASE_ISO="${NEXUS_BASE_ISO:-$DOWNLOAD_DIR/linuxmint-22.3-xfce-64bit.iso}"
MIN_FREE_MB=12288

STRICT=false

usage() {
  cat <<'USAGE'
Usage: bash linux/build/check-build-prereqs.sh [OPTIONS]

Reports whether this host has the Linux ISO remastering tools, verified base
Linux Mint 22.3 Xfce ISO, and free disk space needed by build-nexus-iso.sh.

Options:
  --strict    Exit non-zero if any ISO build prerequisite is missing
  --help, -h  Show this help message
USAGE
}

while (($#)); do
  case "$1" in
    --strict) STRICT=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

missing=()
required_tools=(bash gpg sha256sum xorriso unsquashfs mksquashfs chroot mount umount)

echo "NEXUS OS ISO Build Prerequisite Report"
echo "Host OS: $(uname -s) $(uname -m)"

for tool in "${required_tools[@]}"; do
  if command -v "$tool" >/dev/null 2>&1; then
    printf '  [OK]      tool: %s\n' "$tool"
  else
    printf '  [MISSING] tool: %s\n' "$tool"
    missing+=("tool:$tool")
  fi
done

if [[ -r "$BASE_ISO" ]]; then
  printf '  [OK]      base ISO: %s\n' "$BASE_ISO"
else
  printf '  [MISSING] base ISO: %s (run bash scripts/download-linux-mint.sh)\n' "$BASE_ISO"
  missing+=("iso:$BASE_ISO")
fi

free_mb=0
if command -v df >/dev/null 2>&1; then
  free_kb="$(df -Pk "$REPO_ROOT" | awk 'NR==2 {print $4}')"
  free_mb=$(( free_kb / 1024 ))
fi
if (( free_mb >= MIN_FREE_MB )); then
  printf '  [OK]      free disk: %s MiB (>= %s MiB recommended)\n' "$free_mb" "$MIN_FREE_MB"
else
  printf '  [LOW]     free disk: %s MiB (< %s MiB recommended for ISO remastering)\n' "$free_mb" "$MIN_FREE_MB"
  missing+=("disk:${free_mb}MiB")
fi

if ((${#missing[@]} > 0)); then
  printf 'Result: NOT READY (%s missing/insufficient items).\n' "${#missing[@]}"
  if [[ "$STRICT" == true ]]; then
    exit 1
  fi
else
  echo 'Result: READY for Linux Mint ISO build.'
fi
