#!/usr/bin/env bash
# Provision a Linux Mint 22.3 (Ubuntu Noble) guest or chroot with NEXUS Lite (Openbox + tint2).
# Preserves ufw, unattended-upgrades, NetworkManager, APT signatures, and /etc/os-release.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
MANIFEST="$SCRIPT_DIR/lite-packages.list"

DRY_RUN=false
WITH_BROWSER=false
SKIP_UFW=false
PURGE_BLOAT=false
FORCE=false

usage() {
  cat <<'USAGE'
Usage: sudo bash linux/lite/provision-nexus-lite.sh [OPTIONS]

Provisions a Linux Mint 22.3 (Ubuntu Noble) guest or chroot for NEXUS Lite
(512 MB Experimental / 1 GB) using Openbox, tint2, PCManFM, LXTerminal, and zram-tools.

Options:
  --dry-run       Preview provisioning commands without changing the system
  --with-browser  Include optional lightweight browser (falkon)
  --skip-ufw      Do not invoke ufw enable (recommended inside chroot ISO builds)
  --purge-bloat   Remove heavy Mint desktop apps (Firefox/LibreOffice/Thunderbird/Xfce) during ISO remastering
  --force         Skip OS check
  --help, -h      Show this help message
USAGE
}

while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --with-browser) WITH_BROWSER=true; shift ;;
    --skip-ufw) SKIP_UFW=true; shift ;;
    --purge-bloat) PURGE_BLOAT=true; shift ;;
    --force) FORCE=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

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
  echo 'Run provision-nexus-lite.sh as root (sudo) or pass --dry-run.' >&2
  exit 1
fi

if [[ "$DRY_RUN" == false && "$FORCE" == false && -r /etc/os-release ]]; then
  if ! grep -Eq '^ID=(linuxmint|ubuntu)$' /etc/os-release; then
    echo 'Expected Linux Mint / Ubuntu host; pass --force to override.' >&2
    exit 1
  fi
fi

packages=()
while IFS=':' read -r cat pkg; do
  [[ -z "${cat:-}" || "$cat" == \#* ]] && continue
  pkg="${pkg%%[[:space:]]*}"
  case "$cat" in
    core|desktop|nexus) packages+=("$pkg") ;;
    optional) [[ "$WITH_BROWSER" == true && "$pkg" == "falkon" ]] && packages+=("$pkg") ;;
  esac
done < "$MANIFEST"

run_cmd env DEBIAN_FRONTEND=noninteractive apt-get update
run_cmd env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${packages[@]}"

if [[ "$PURGE_BLOAT" == true ]]; then
  bloat_pkgs=(firefox thunderbird rhythmbox celluloid hexchat transmission-gtk timeshift xfwm4 xfdesktop4 xfce4-panel xfce4-session)
  if [[ "$DRY_RUN" == true ]]; then
    printf '[dry-run] Purge heavy Mint desktop bloat (if installed): %s && apt-get autoremove -y\n' "${bloat_pkgs[*]}"
  else
    installed_bloat=()
    for bpkg in "${bloat_pkgs[@]}"; do
      if dpkg-query -W -f='${Status}' "$bpkg" 2>/dev/null | grep -q 'install ok installed'; then
        installed_bloat+=("$bpkg")
      fi
    done
    if ((${#installed_bloat[@]} > 0)); then
      env DEBIAN_FRONTEND=noninteractive apt-get purge -y "${installed_bloat[@]}" || true
      env DEBIAN_FRONTEND=noninteractive apt-get autoremove -y --purge || true
    fi
  fi
fi

run_cmd install -d -m 0755 /usr/local/share/nexus-os/lite /usr/local/share/nexus-os/branding /usr/local/share/nexus-os/hardware /usr/local/share/applications /usr/local/bin /etc/lightdm/lightdm.conf.d
run_cmd install -m 0755 "$SCRIPT_DIR/apply-nexus-lite.sh" /usr/local/bin/nexus-apply-lite
run_cmd install -m 0755 "$SCRIPT_DIR/configure-zram.sh" /usr/local/bin/nexus-configure-zram
run_cmd install -m 0755 "$SCRIPT_DIR/memory-audit.sh" /usr/local/bin/nexus-memory-audit
run_cmd install -m 0755 "$SCRIPT_DIR/nexus-lite-install.sh" /usr/local/bin/nexus-lite-install
run_cmd install -m 0755 "$REPO_ROOT/linux/installer/nexus-install-preflight.sh" /usr/local/bin/nexus-install-preflight
run_cmd install -m 0755 "$REPO_ROOT/linux/installer/nexus-installer-launcher.sh" /usr/local/bin/nexus-installer-launcher
run_cmd install -m 0755 "$REPO_ROOT/linux/installer/nexus-disk-install.sh" /usr/local/bin/nexus-disk-install
run_cmd install -m 0755 "$REPO_ROOT/linux/hardware/nexus-hw-inventory.sh" /usr/local/bin/nexus-hw-inventory
run_cmd install -m 0755 "$REPO_ROOT/linux/hardware/nexus-hw-diagnostics.sh" /usr/local/bin/nexus-hw-diagnostics
run_cmd install -m 0755 "$REPO_ROOT/linux/hardware/nexus-hw-qualify.sh" /usr/local/bin/nexus-hw-qualify
run_cmd install -m 0755 "$REPO_ROOT/linux/hardware/nexus-browser-qualify.sh" /usr/local/bin/nexus-browser-qualify
run_cmd install -m 0755 "$REPO_ROOT/linux/security/nexus-security-audit.sh" /usr/local/bin/nexus-security-audit
run_cmd install -m 0644 "$REPO_ROOT/linux/hardware/hw-compatibility-db.json" /usr/local/share/nexus-os/hardware/hw-compatibility-db.json
run_cmd install -m 0644 "$REPO_ROOT/linux/test/nexus-browser-bench.py" /usr/local/share/nexus-os/hardware/nexus-browser-bench.py
run_cmd install -m 0644 "$REPO_ROOT/linux/branding/nexus-logo.svg" /usr/local/share/nexus-os/branding/nexus-logo.svg
run_cmd cp -a "$SCRIPT_DIR/openbox" /usr/local/share/nexus-os/lite/

for desktop_file in nexus-files.desktop nexus-terminal.desktop nexus-system-monitor.desktop nexus-settings.desktop nexus-installer.desktop nexus-hw-diagnostics.desktop nexus-security-audit.desktop; do
  if [[ -f "$REPO_ROOT/linux/branding/applications/$desktop_file" ]]; then
    run_cmd install -m 0644 "$REPO_ROOT/linux/branding/applications/$desktop_file" "/usr/local/share/applications/$desktop_file"
  fi
done

run_cmd install -d -m 0755 /etc/skel/.config/openbox /etc/skel/.config/tint2 /etc/skel/.config/autostart /etc/skel/.config/nexus-os /etc/xdg/openbox /etc/xdg/tint2
run_cmd install -m 0644 "$SCRIPT_DIR/openbox/rc.xml" /etc/skel/.config/openbox/rc.xml
run_cmd install -m 0644 "$SCRIPT_DIR/openbox/menu.xml" /etc/skel/.config/openbox/menu.xml
run_cmd install -m 0755 "$SCRIPT_DIR/openbox/autostart" /etc/skel/.config/openbox/autostart
run_cmd install -m 0644 "$SCRIPT_DIR/openbox/tint2rc" /etc/skel/.config/tint2/tint2rc
run_cmd install -m 0644 "$SCRIPT_DIR/openbox/rc.xml" /etc/xdg/openbox/rc.xml
run_cmd install -m 0644 "$SCRIPT_DIR/openbox/menu.xml" /etc/xdg/openbox/menu.xml
run_cmd install -m 0755 "$SCRIPT_DIR/openbox/autostart" /etc/xdg/openbox/autostart
run_cmd install -m 0644 "$SCRIPT_DIR/openbox/tint2rc" /etc/xdg/tint2/tint2rc

if [[ "$DRY_RUN" == true ]]; then
  echo '[dry-run] Disable heavy XDG tray autostart bloat in /etc/skel/.config/autostart/'
  echo '[dry-run] Write /etc/skel/.config/nexus-os/lite-profile, /etc/lightdm/lightdm.conf.d/90-nexus-lite.conf, /etc/nexus-os-release'
  if [[ "$SKIP_UFW" == false ]]; then
    echo '[dry-run] Configure zram swap + UFW default deny incoming'
  else
    echo '[dry-run] Configure /etc/default/zramswap (skipping ufw enable inside chroot)'
  fi
else
  for bloat_desktop in warpinator-autostart.desktop sticky.desktop mintupdate.desktop org.gnome.Evolution-alarm-notify.desktop blueman.desktop print-applet.desktop mintwelcome.desktop xapp-sn-watcher.desktop; do
    printf '[Desktop Entry]\nHidden=true\n' > "/etc/skel/.config/autostart/${bloat_desktop}"
    chmod 0644 "/etc/skel/.config/autostart/${bloat_desktop}"
  done
  printf 'profile=lite-512\n' > /etc/skel/.config/nexus-os/lite-profile
  chmod 0644 /etc/skel/.config/nexus-os/lite-profile
  rm -f -- /etc/lightdm/lightdm.conf.d/50-nexus-lite.conf
  cat > /etc/lightdm/lightdm.conf.d/90-nexus-lite.conf <<'DM'
[Seat:*]
user-session=openbox
autologin-session=openbox
DM
  chmod 0644 /etc/lightdm/lightdm.conf.d/90-nexus-lite.conf

  if [[ "$SKIP_UFW" == true ]]; then
    cat > /etc/default/zramswap <<'CFG'
ALGO=zstd
PERCENT=50
PRIORITY=100
CFG
    if command -v systemctl >/dev/null 2>&1; then
      systemctl enable zramswap.service >/dev/null 2>&1 || true
    fi
  else
    bash "$SCRIPT_DIR/configure-zram.sh" enable
    if command -v ufw >/dev/null 2>&1; then
      ufw default deny incoming || true
      ufw default allow outgoing || true
      ufw --force enable || true
    fi
  fi
  cat > /etc/nexus-os-release <<'META'
NEXUS_NAME="NEXUS OS Lite"
NEXUS_EDITION="lite"
NEXUS_BASE_DISTRO="linuxmint"
NEXUS_BASE_CODENAME="noble"
NEXUS_DESKTOP="openbox"
META
  chmod 0644 /etc/nexus-os-release
fi

echo 'NEXUS Lite provisioning complete.'
