#!/usr/bin/env bash
# Provision a booted Linux Mint 22.3 Xfce guest with NEXUS OS baseline security,
# curated packages, branding assets, and user-space helper scripts.
# Does not build an ISO or touch Chromebook firmware.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
SYSTEM_CONF="$REPO_ROOT/linux/config/nexus-system.conf"
PKG_MANIFEST="$REPO_ROOT/linux/config/mint-packages.list"

DRY_RUN=false
WITH_GAMING=false
WITH_DEV=false
WITH_OPTIONAL=false
SKIP_UFW=false
AUTOSTART_FIRSTBOOT=false
FORCE_DISTRO=false
PREFIX_DIR="/usr/local"

usage() {
  cat <<'USAGE'
Usage: sudo bash linux/mint/provision-nexus-guest.sh [OPTIONS]

Provisions an installed Linux Mint 22.3 Xfce (Ubuntu Noble) system with NEXUS OS
security defaults (UFW firewall, unattended-upgrades), curated packages, branding
assets, and helper scripts under /usr/local. Keeps Mint's /etc/os-release and
signed APT repositories intact.

Options:
  --dry-run              Print planned steps without modifying the system
  --with-gaming          Include optional Vulkan/GameMode/steam-installer packages
  --with-dev             Include optional development packages (git, build-essential, python3)
  --with-optional        Include optional desktop applications
  --skip-ufw             Do not alter UFW firewall state
  --autostart-firstboot  Install /etc/xdg/autostart/nexus-firstboot.desktop
  --force                Skip Linux Mint / Ubuntu Noble OS verification check
  --help, -h             Show this help message
USAGE
}

while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --with-gaming) WITH_GAMING=true; shift ;;
    --with-dev) WITH_DEV=true; shift ;;
    --with-optional) WITH_OPTIONAL=true; shift ;;
    --skip-ufw) SKIP_UFW=true; shift ;;
    --autostart-firstboot) AUTOSTART_FIRSTBOOT=true; shift ;;
    --force) FORCE_DISTRO=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -r "$SYSTEM_CONF" ]] || { printf 'Missing config: %s\n' "$SYSTEM_CONF" >&2; exit 1; }
[[ -r "$PKG_MANIFEST" ]] || { printf 'Missing package manifest: %s\n' "$PKG_MANIFEST" >&2; exit 1; }

run_cmd() {
  if [[ "$DRY_RUN" == true ]]; then
    printf '[dry-run]'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

if [[ "$DRY_RUN" == false && "$(id -u)" -ne 0 ]]; then
  echo 'Run provision-nexus-guest.sh as root (via sudo) or pass --dry-run to preview.' >&2
  exit 1
fi

os_id="unknown"
os_codename="unknown"
if [[ -r /etc/os-release ]]; then
  while IFS='=' read -r key val; do
    val="${val%\"}"
    val="${val#\"}"
    case "$key" in
      ID) os_id="$val" ;;
      UBUNTU_CODENAME|VERSION_CODENAME)
        if [[ "$os_codename" == "unknown" ]]; then
          os_codename="$val"
        fi
        ;;
    esac
  done < /etc/os-release
fi

if [[ "$DRY_RUN" == false && "$FORCE_DISTRO" == false ]]; then
  if [[ "$os_id" != "linuxmint" && "$os_id" != "ubuntu" ]]; then
    printf 'Unsupported host OS (%s). Expected Linux Mint 22.3 / Ubuntu Noble; pass --force to override.\n' "$os_id" >&2
    exit 1
  fi
fi

packages=()
while IFS=':' read -r section pkg; do
  [[ -z "${section:-}" || "$section" == \#* ]] && continue
  pkg="${pkg%%[[:space:]]*}"
  [[ -n "$pkg" ]] || continue
  case "$section" in
    core|desktop|nexus) packages+=("$pkg") ;;
    gaming)
      if [[ "$WITH_GAMING" == true ]]; then
        packages+=("$pkg")
      fi
      ;;
    development)
      if [[ "$WITH_DEV" == true ]]; then
        packages+=("$pkg")
      fi
      ;;
    optional)
      if [[ "$WITH_OPTIONAL" == true ]]; then
        packages+=("$pkg")
      fi
      ;;
    *)
      printf 'Unknown package category in %s: %s\n' "$PKG_MANIFEST" "$section" >&2
      exit 1
      ;;
  esac
done < "$PKG_MANIFEST"

if ((${#packages[@]} == 0)); then
  echo 'No packages selected from manifest.' >&2
  exit 1
fi

echo "Provisioning NEXUS OS Mint baseline (host=$os_id, codename=$os_codename, gaming=$WITH_GAMING, dev=$WITH_DEV)"

run_cmd env DEBIAN_FRONTEND=noninteractive apt-get update
run_cmd env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${packages[@]}"

if [[ "$SKIP_UFW" == false ]]; then
  run_cmd ufw default deny incoming
  run_cmd ufw default allow outgoing
  run_cmd ufw --force enable
fi

share_dir="$PREFIX_DIR/share/nexus-os"
bin_dir="$PREFIX_DIR/bin"

run_cmd install -d -m 0755 "$share_dir" "$share_dir/xfce" "$share_dir/config" "$share_dir/branding" "$bin_dir"
run_cmd install -m 0644 "$REPO_ROOT/linux/xfce/nexus-dark.css" "$share_dir/xfce/nexus-dark.css"
run_cmd install -m 0644 "$REPO_ROOT/linux/branding/nexus-logo.svg" "$share_dir/branding/nexus-logo.svg"
run_cmd install -m 0644 "$SYSTEM_CONF" "$share_dir/config/nexus-system.conf"
run_cmd install -m 0755 "$REPO_ROOT/linux/mint/apply-nexus-xfce.sh" "$bin_dir/nexus-apply-xfce"
run_cmd install -m 0755 "$REPO_ROOT/linux/mint/measure-footprint.sh" "$bin_dir/nexus-measure-footprint"
run_cmd install -m 0755 "$REPO_ROOT/linux/mint/nexus-panel-status.sh" "$bin_dir/nexus-panel-status"
run_cmd install -m 0755 "$REPO_ROOT/linux/mint/madoo-qualify-report.sh" "$bin_dir/nexus-qualify-report"
run_cmd install -m 0755 "$REPO_ROOT/linux/mint/nexus-firstboot.sh" "$bin_dir/nexus-firstboot"

if [[ "$DRY_RUN" == true ]]; then
  printf '[dry-run] Write /etc/nexus-os-release (preserving /etc/os-release)\n'
else
  cat > /etc/nexus-os-release <<META
NEXUS_NAME="NEXUS OS"
NEXUS_BASE_DISTRO="$os_id"
NEXUS_BASE_CODENAME="$os_codename"
NEXUS_DESKTOP="xfce"
NEXUS_GAMING_PROVISIONED="$WITH_GAMING"
NEXUS_DEV_PROVISIONED="$WITH_DEV"
META
  chmod 0644 /etc/nexus-os-release
fi

if [[ "$AUTOSTART_FIRSTBOOT" == true ]]; then
  run_cmd install -d -m 0755 /etc/xdg/autostart
  run_cmd install -m 0644 "$REPO_ROOT/linux/branding/nexus-firstboot.desktop" /etc/xdg/autostart/nexus-firstboot.desktop
fi

echo 'NEXUS guest provisioning complete. Run nexus-firstboot as your regular desktop user.'
