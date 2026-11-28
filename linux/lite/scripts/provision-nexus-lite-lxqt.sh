#!/usr/bin/env bash
# Provision a Linux Mint 22.3 / Ubuntu 24.04 Noble guest or chroot with the
# NEXUS Lite LXQt Candidate (Ubuntu/Lubuntu LXQt + Openbox + PCManFM-Qt + QTerminal + ZRAM).
# Preserves ufw, unattended-upgrades, NetworkManager, APT signatures, and /etc/os-release.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"
MANIFEST="$REPO_ROOT/linux/lite/manifests/lite-lxqt-packages.list"
LXQT_DIR="$REPO_ROOT/linux/lite/lxqt"

DRY_RUN=false
WITH_BROWSER=false
WITH_FLATPAK=false
SKIP_UFW=false
PURGE_BLOAT=false
FORCE=false

usage() {
  cat <<'USAGE'
Usage: sudo bash linux/lite/scripts/provision-nexus-lite-lxqt.sh [OPTIONS]

Provisions a genuine Ubuntu/Noble-based guest or chroot for the NEXUS Lite LXQt
candidate using curated Lubuntu/LXQt components + Openbox + zram-tools.

Options:
  --dry-run       Preview provisioning commands without changing the system
  --with-browser  Include optional lightweight browser (falkon)
  --with-flatpak  Include optional Flatpak integration
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
    --with-flatpak) WITH_FLATPAK=true; shift ;;
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
  echo 'Run provision-nexus-lite-lxqt.sh as root (sudo) or pass --dry-run.' >&2
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
    optional)
      [[ "$WITH_BROWSER" == true && "$pkg" == "falkon" ]] && packages+=("$pkg")
      [[ "$WITH_FLATPAK" == true && "$pkg" == "flatpak" ]] && packages+=("$pkg")
      ;;
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

# Install shared NEXUS Lite, Installer, Hardware, and Security tools + LXQt assets
run_cmd install -d -m 0755 \
  /usr/local/share/nexus-os/lite \
  /usr/local/share/nexus-os/lite-lxqt \
  /usr/local/share/nexus-os/branding \
  /usr/local/share/nexus-os/hardware \
  /usr/local/share/nexus-os/docs \
  /usr/local/share/lxqt/themes/nexus-dark \
  /usr/local/share/applications \
  /usr/local/bin \
  /etc/lightdm/lightdm.conf.d \
  /etc/systemd/user \
  /etc/systemd/user/default.target.wants

run_cmd install -m 0755 "$SCRIPT_DIR/apply-nexus-lite-lxqt.sh" /usr/local/bin/nexus-apply-lite-lxqt
run_cmd install -m 0755 "$REPO_ROOT/linux/lite/configure-zram.sh" /usr/local/bin/nexus-configure-zram
run_cmd install -m 0755 "$REPO_ROOT/linux/lite/memory-audit.sh" /usr/local/bin/nexus-memory-audit
run_cmd install -m 0755 "$REPO_ROOT/linux/lite/nexus-lite-install.sh" /usr/local/bin/nexus-lite-install
run_cmd install -m 0755 "$REPO_ROOT/linux/installer/nexus-install-preflight.sh" /usr/local/bin/nexus-install-preflight
run_cmd install -m 0755 "$REPO_ROOT/linux/installer/nexus-installer-launcher.sh" /usr/local/bin/nexus-installer-launcher
run_cmd install -m 0755 "$REPO_ROOT/linux/installer/nexus-disk-install.sh" /usr/local/bin/nexus-disk-install
run_cmd install -m 0755 "$REPO_ROOT/linux/installer/nexus-recovery.sh" /usr/local/bin/nexus-recovery
run_cmd install -m 0644 "$REPO_ROOT/docs/RECOVERY_AND_BOOT.md" /usr/local/share/nexus-os/docs/RECOVERY_AND_BOOT.md
run_cmd install -m 0755 "$REPO_ROOT/linux/hardware/nexus-hw-inventory.sh" /usr/local/bin/nexus-hw-inventory
run_cmd install -m 0755 "$REPO_ROOT/linux/hardware/nexus-hw-diagnostics.sh" /usr/local/bin/nexus-hw-diagnostics
run_cmd install -m 0755 "$REPO_ROOT/linux/hardware/nexus-hw-qualify.sh" /usr/local/bin/nexus-hw-qualify
run_cmd install -m 0755 "$REPO_ROOT/linux/hardware/nexus-browser-qualify.sh" /usr/local/bin/nexus-browser-qualify
run_cmd install -m 0755 "$REPO_ROOT/linux/security/nexus-security-audit.sh" /usr/local/bin/nexus-security-audit
run_cmd install -m 0755 "$REPO_ROOT/linux/branding/nexus-launch-app.sh" /usr/local/bin/nexus-launch-app
run_cmd install -m 0755 "$REPO_ROOT/linux/mint/nexus-firstboot.sh" /usr/local/bin/nexus-firstboot
run_cmd install -m 0755 "$REPO_ROOT/linux/mint/nexus-store-cli.sh" /usr/local/bin/nexus-store-cli
run_cmd install -m 0755 "$REPO_ROOT/linux/mint/nexus-security-cli.sh" /usr/local/bin/nexus-security-cli
run_cmd install -m 0755 "$REPO_ROOT/linux/mint/nexus-gaming-cli.sh" /usr/local/bin/nexus-gaming-cli
run_cmd install -m 0755 "$REPO_ROOT/linux/mint/nexus-performance-cli.sh" /usr/local/bin/nexus-performance-cli
run_cmd install -m 0755 "$REPO_ROOT/linux/mint/nexus-compat-cli.sh" /usr/local/bin/nexus-compat-cli
run_cmd install -m 0755 "$REPO_ROOT/linux/mint/nexus-control-centre-cli.sh" /usr/local/bin/nexus-control-centre
run_cmd install -m 0755 "$REPO_ROOT/linux/mint/nexus-wallpaper-cli.sh" /usr/local/bin/nexus-wallpaper
run_cmd install -m 0755 "$REPO_ROOT/linux/mint/nexus-system-bridge.py" /usr/local/bin/nexus-system-bridge
run_cmd install -m 0644 "$REPO_ROOT/linux/mint/nexus-system-bridge.service" /etc/systemd/user/nexus-system-bridge.service
run_cmd ln -sf ../nexus-system-bridge.service /etc/systemd/user/default.target.wants/nexus-system-bridge.service
run_cmd install -m 0644 "$REPO_ROOT/linux/hardware/hw-compatibility-db.json" /usr/local/share/nexus-os/hardware/hw-compatibility-db.json
run_cmd install -m 0644 "$REPO_ROOT/linux/test/nexus-browser-bench.py" /usr/local/share/nexus-os/hardware/nexus-browser-bench.py
run_cmd install -m 0644 "$REPO_ROOT/linux/branding/nexus-logo.svg" /usr/local/share/nexus-os/branding/nexus-logo.svg
run_cmd install -m 0644 "$REPO_ROOT/linux/config/wallpapers.json" /usr/local/share/nexus-os/wallpapers.json
run_cmd install -m 0644 "$LXQT_DIR/wallpaper-nexus-obsidian.png" /usr/local/share/nexus-os/lite/wallpaper-nexus-obsidian.png
run_cmd install -m 0644 "$LXQT_DIR/wallpaper-nexus-obsidian.svg" /usr/local/share/nexus-os/lite/wallpaper-nexus-obsidian.svg
run_cmd install -m 0644 "$LXQT_DIR/theme/nexus-dark/lxqt-panel.qss" /usr/local/share/lxqt/themes/nexus-dark/lxqt-panel.qss
run_cmd cp -a "$LXQT_DIR" /usr/local/share/nexus-os/lite-lxqt/
run_cmd install -d -m 0755 /usr/local/share/nexus-os/ui
run_cmd install -m 0644 "$REPO_ROOT/index.html" /usr/local/share/nexus-os/ui/index.html
run_cmd install -m 0644 "$REPO_ROOT/app.js" /usr/local/share/nexus-os/ui/app.js
run_cmd install -m 0644 "$REPO_ROOT/styles.css" /usr/local/share/nexus-os/ui/styles.css
run_cmd cp -a "$REPO_ROOT/apps" /usr/local/share/nexus-os/ui/
run_cmd cp -a "$REPO_ROOT/assets" /usr/local/share/nexus-os/ui/

run_cmd install -d -m 0755 /etc/xdg/autostart
run_cmd install -m 0644 "$REPO_ROOT/linux/branding/nexus-firstboot.desktop" /etc/xdg/autostart/nexus-firstboot.desktop

for desktop_file in "$REPO_ROOT"/linux/branding/applications/*.desktop; do
  [[ -f "$desktop_file" ]] || continue
  run_cmd install -m 0644 "$desktop_file" "/usr/local/share/applications/${desktop_file##*/}"
done

run_cmd install -d -m 0755 \
  /etc/skel/.config/lxqt \
  /etc/skel/.config/openbox \
  /etc/skel/.config/pcmanfm-qt/lxqt \
  /etc/skel/.config/qterminal.org \
  /etc/skel/.config/autostart \
  /etc/skel/.config/nexus-os \
  /etc/xdg/lxqt \
  /etc/xdg/openbox \
  /etc/xdg/pcmanfm-qt/lxqt

for cfg_root in /etc/skel/.config /etc/xdg; do
  run_cmd install -m 0644 "$LXQT_DIR/lxqt.conf" "$cfg_root/lxqt/lxqt.conf"
  run_cmd install -m 0644 "$LXQT_DIR/panel.conf" "$cfg_root/lxqt/panel.conf"
  run_cmd install -m 0644 "$LXQT_DIR/session.conf" "$cfg_root/lxqt/session.conf"
  run_cmd install -m 0644 "$LXQT_DIR/openbox-rc.xml" "$cfg_root/openbox/lxqt-openbox-rc.xml"
  run_cmd install -m 0644 "$LXQT_DIR/openbox-rc.xml" "$cfg_root/openbox/rc.xml"
  run_cmd install -m 0644 "$LXQT_DIR/pcmanfm-qt/settings.conf" "$cfg_root/pcmanfm-qt/lxqt/settings.conf"
done
run_cmd install -m 0644 "$LXQT_DIR/qterminal.ini" /etc/skel/.config/qterminal.org/qterminal.ini

if [[ "$DRY_RUN" == true ]]; then
  echo '[dry-run] Disable identical heavy XDG tray autostart bloat in /etc/skel/.config/autostart/'
  echo '[dry-run] Write /etc/skel/.config/nexus-os/lite-profile, /etc/lightdm/lightdm.conf.d/90-nexus-lite-lxqt.conf, /etc/nexus-os-release'
  if [[ "$SKIP_UFW" == false ]]; then
    echo '[dry-run] Configure zram swap + UFW default deny incoming'
  else
    echo '[dry-run] Configure /etc/default/zramswap (skipping ufw enable inside chroot)'
  fi
else
  # Symmetrical autostart bloat disabling with Openbox Lite for fair comparison
  for bloat_desktop in warpinator-autostart.desktop sticky.desktop mintupdate.desktop org.gnome.Evolution-alarm-notify.desktop blueman.desktop print-applet.desktop mintwelcome.desktop xapp-sn-watcher.desktop; do
    printf '[Desktop Entry]\nHidden=true\n' > "/etc/skel/.config/autostart/${bloat_desktop}"
    chmod 0644 "/etc/skel/.config/autostart/${bloat_desktop}"
  done
  printf 'profile=lite-1g\ndesktop=lxqt\n' > /etc/skel/.config/nexus-os/lite-profile
  chmod 0644 /etc/skel/.config/nexus-os/lite-profile

  rm -f -- /etc/lightdm/lightdm.conf.d/90-nexus-lite.conf /etc/lightdm/lightdm.conf.d/50-nexus-lite.conf
  cat > /etc/lightdm/lightdm.conf.d/90-nexus-lite-lxqt.conf <<'DM'
[Seat:*]
user-session=lxqt
autologin-session=lxqt
DM
  chmod 0644 /etc/lightdm/lightdm.conf.d/90-nexus-lite-lxqt.conf

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
    bash "$REPO_ROOT/linux/lite/configure-zram.sh" enable
    if command -v ufw >/dev/null 2>&1; then
      ufw default deny incoming || true
      ufw default allow outgoing || true
      ufw --force enable || true
    fi
  fi

  cat > /etc/nexus-os-release <<'META'
NEXUS_NAME="NEXUS OS Lite (LXQt Candidate)"
NEXUS_EDITION="lite-lxqt"
NEXUS_BASE_DISTRO="linuxmint"
NEXUS_BASE_CODENAME="noble"
NEXUS_DESKTOP="lxqt"
NEXUS_WINDOW_MANAGER="openbox"
META
  chmod 0644 /etc/nexus-os-release
fi

echo 'NEXUS Lite LXQt provisioning complete.'
