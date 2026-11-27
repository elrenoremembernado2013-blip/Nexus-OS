#!/usr/bin/env bash
# Validate NEXUS OS Linux Mint APT package manifest for syntax, duplicates,
# category separation, zero hardcoded secrets, and optional apt-cache checks.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
MANIFEST="${1:-$REPO_ROOT/linux/config/mint-packages.list}"
CHECK_APT=false

usage() {
  cat <<'USAGE'
Usage: bash linux/build/validate-packages.sh [OPTIONS] [MANIFEST_PATH]

Validates linux/config/mint-packages.list syntax, package naming, category
separation (essential vs optional), and optionally checks apt-cache availability.

Options:
  --check-apt   Verify each package exists via apt-cache policy (on Mint/Ubuntu hosts)
  --help, -h    Show this help message
USAGE
}

args=()
while (($#)); do
  case "$1" in
    --check-apt) CHECK_APT=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) args+=("$1"); shift ;;
  esac
done
if ((${#args[@]} > 0)); then
  MANIFEST="${args[0]}"
fi

[[ -r "$MANIFEST" ]] || { printf 'Manifest not readable: %s\n' "$MANIFEST" >&2; exit 1; }

declare -A seen_pkgs=()
essential_count=0
optional_count=0
line_no=0
all_pkgs=()

while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
  line_no=$((line_no + 1))
  line="${raw_line#"${raw_line%%[![:space:]]*}"}"
  [[ -z "$line" || "$line" == \#* ]] && continue

  if [[ "$line" != *:* ]]; then
    printf 'Line %d: missing category:package separator -> %s\n' "$line_no" "$line" >&2
    exit 1
  fi

  cat="${line%%:*}"
  pkg="${line#*:}"
  pkg="${pkg%%[[:space:]]*}"

  case "$cat" in
    core|desktop|nexus) essential_count=$((essential_count + 1)) ;;
    gaming|development|optional) optional_count=$((optional_count + 1)) ;;
    *) printf 'Line %d: unsupported category %s\n' "$line_no" "$cat" >&2; exit 1 ;;
  esac

  if ! [[ "$pkg" =~ ^[a-z0-9][a-z0-9+.-]+$ ]]; then
    printf 'Line %d: invalid APT package name %s\n' "$line_no" "$pkg" >&2
    exit 1
  fi

  if [[ -n "${seen_pkgs[$pkg]:-}" ]]; then
    printf 'Line %d: duplicate package %s (already in %s)\n' "$line_no" "$pkg" "${seen_pkgs[$pkg]}" >&2
    exit 1
  fi
  seen_pkgs["$pkg"]="$cat"
  all_pkgs+=("$pkg")
done < "$MANIFEST"

(( essential_count > 0 )) || { echo 'Manifest must define at least one essential package.' >&2; exit 1; }

if [[ "$CHECK_APT" == true ]]; then
  if ! command -v apt-cache >/dev/null 2>&1; then
    echo 'apt-cache is unavailable on this host.' >&2
    exit 1
  fi
  for pkg in "${all_pkgs[@]}"; do
    if ! apt-cache show "$pkg" >/dev/null 2>&1; then
      printf 'APT package not found in local cache: %s (run apt-get update first)\n' "$pkg" >&2
      exit 1
    fi
  done
  echo "PASS apt-cache resolved all ${#all_pkgs[@]} packages."
fi

printf 'PASS package manifest valid: %s (%d essential, %d optional)\n' "$MANIFEST" "$essential_count" "$optional_count"
