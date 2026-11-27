#!/usr/bin/env bash
# NEXUS Store Linux Mint package-management helper (APT + Flatpak).
# Validates package identifiers strictly, refuses removal of protected base
# packages, and uses Polkit (pkexec) for privileged install/remove/update actions.
set -euo pipefail

DRY_RUN=false

usage() {
  cat <<'USAGE'
Usage: bash linux/mint/nexus-store-cli.sh [OPTIONS] <command> [args...]

Real Linux Mint package backend for NEXUS Store (APT and Flatpak).
Read-only queries run as the current user; mutating commands invoke pkexec so
system authentication is never bypassed.

Options:
  --dry-run       Print exact APT/Flatpak commands without executing mutations
  --help, -h      Show this help message

Commands:
  sources                        Report available package managers (apt, flatpak, mintupdate)
  search <query>                 Search APT and Flatpak metadata (read-only)
  info <apt|flatpak> <pkg>       Show real package metadata and installed state
  installed                      List manually installed APT apps and Flatpak apps
  updates                        Check real upgradable APT and Flatpak updates
  install <apt|flatpak> <pkg>    Install a package via pkexec apt-get or flatpak
  remove <apt|flatpak> <pkg>     Remove a non-protected package via pkexec apt-get or flatpak
USAGE
}

while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --help|-h) usage; exit 0 ;;
    --) shift; break ;;
    -*) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    *) break ;;
  esac
done

[[ $# -ge 1 ]] || { usage >&2; exit 2; }
CMD="$1"
shift

validate_pkg_id() {
  local source="$1" pkg="$2"
  case "$source" in
    apt)
      [[ "$pkg" =~ ^[a-z0-9][a-z0-9+.-]{0,127}$ ]] || {
        printf 'Invalid APT package name: %s\n' "$pkg" >&2
        exit 2
      }
      ;;
    flatpak)
      [[ "$pkg" =~ ^[A-Za-z0-9_.-]{3,128}$ && "$pkg" == *.* ]] || {
        printf 'Invalid Flatpak application ID: %s\n' "$pkg" >&2
        exit 2
      }
      ;;
    *)
      printf 'Unsupported package source: %s (expected apt or flatpak)\n' "$source" >&2
      exit 2
      ;;
  esac
}

is_protected_apt_pkg() {
  local pkg="$1"
  case "$pkg" in
    apt|apt-utils|base-files|base-passwd|bash|coreutils|dash|dpkg|e2fsprogs|findutils|grep|gzip|init|libc6|linux-base|linux-generic|linux-image-*|login|mintsystem|mintupdate|mount|passwd|sed|sudo|systemd|systemd-sysv|tar|ubuntu-minimal|ufw|util-linux|xfce4-session|xfwm4|cinnamon)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

run_mutating() {
  if [[ "$DRY_RUN" == true ]]; then
    printf '[dry-run]'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

case "$CMD" in
  sources)
    apt_ok=false
    flatpak_ok=false
    mintupdate_ok=false
    command -v apt-cache >/dev/null 2>&1 && command -v apt-get >/dev/null 2>&1 && apt_ok=true
    command -v flatpak >/dev/null 2>&1 && flatpak_ok=true
    command -v mintupdate >/dev/null 2>&1 && mintupdate_ok=true
    printf '{"apt":%s,"flatpak":%s,"mintupdate":%s}\n' "$apt_ok" "$flatpak_ok" "$mintupdate_ok"
    ;;

  search)
    [[ $# -ge 1 && -n "$1" ]] || { echo 'search requires a query' >&2; exit 2; }
    query="$1"
    if command -v apt-cache >/dev/null 2>&1; then
      echo '=== APT ==='
      apt-cache search --names-only -- "$query" 2>/dev/null | head -n 40 || true
    else
      echo 'APT unavailable on this host.'
    fi
    if command -v flatpak >/dev/null 2>&1; then
      echo '=== Flatpak ==='
      flatpak search --columns=application,name,version,remotes,description -- "$query" 2>/dev/null | head -n 40 || true
    fi
    ;;

  info)
    [[ $# -eq 2 ]] || { echo 'info requires <apt|flatpak> <pkg>' >&2; exit 2; }
    source="$1"
    pkg="$2"
    validate_pkg_id "$source" "$pkg"
    if [[ "$source" == "apt" ]]; then
      command -v apt-cache >/dev/null 2>&1 || { echo 'apt-cache unavailable on this host.' >&2; exit 1; }
      apt-cache show -- "$pkg"
    else
      command -v flatpak >/dev/null 2>&1 || { echo 'flatpak unavailable on this host.' >&2; exit 1; }
      flatpak info -- "$pkg" 2>/dev/null || flatpak remote-info flathub -- "$pkg"
    fi
    ;;

  installed)
    if command -v dpkg-query >/dev/null 2>&1; then
      echo '=== APT (manually installed) ==='
      if command -v apt-mark >/dev/null 2>&1; then
        apt-mark showmanual | head -n 100
      else
        dpkg-query -W -f='${Package}\t${Version}\n' | head -n 100
      fi
    else
      echo 'dpkg-query unavailable on this host.'
    fi
    if command -v flatpak >/dev/null 2>&1; then
      echo '=== Flatpak ==='
      flatpak list --app --columns=application,name,version,origin
    fi
    ;;

  updates)
    if command -v apt >/dev/null 2>&1; then
      echo '=== APT upgradable ==='
      apt list --upgradable 2>/dev/null || true
    else
      echo 'APT unavailable on this host.'
    fi
    if command -v flatpak >/dev/null 2>&1; then
      echo '=== Flatpak updates ==='
      flatpak remote-ls --updates --columns=application,version,origin 2>/dev/null || true
    fi
    ;;

  install)
    [[ $# -eq 2 ]] || { echo 'install requires <apt|flatpak> <pkg>' >&2; exit 2; }
    source="$1"
    pkg="$2"
    validate_pkg_id "$source" "$pkg"
    if [[ "$source" == "apt" ]]; then
      run_mutating pkexec env DEBIAN_FRONTEND=noninteractive apt-get install -y -- "$pkg"
    else
      run_mutating flatpak install -y -- "$pkg"
    fi
    ;;

  remove)
    [[ $# -eq 2 ]] || { echo 'remove requires <apt|flatpak> <pkg>' >&2; exit 2; }
    source="$1"
    pkg="$2"
    validate_pkg_id "$source" "$pkg"
    if [[ "$source" == "apt" ]]; then
      if is_protected_apt_pkg "$pkg"; then
        printf 'Refusing to remove protected Linux Mint / NEXUS base package: %s\n' "$pkg" >&2
        exit 1
      fi
      run_mutating pkexec env DEBIAN_FRONTEND=noninteractive apt-get remove -y -- "$pkg"
    else
      run_mutating flatpak uninstall -y -- "$pkg"
    fi
    ;;

  *)
    printf 'Unknown command: %s\n' "$CMD" >&2
    usage >&2
    exit 2
    ;;
esac
