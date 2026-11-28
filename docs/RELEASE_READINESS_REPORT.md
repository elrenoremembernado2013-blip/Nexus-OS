# NEXUS OS — Release Readiness Report (Phase 18)

Date: 2026-11-28  
Branch: `arena/f18c36a4-nexus-os` (`main` untouched)  
Base Linux Foundation: Linux Mint 22.3 (`linuxmint`) / Ubuntu 24.04 Noble (`ubuntu-noble`) package ecosystem

---

## 1. Executive Assessment

**Status: Beta / Release-Candidate Ready for Guided Testing — Not Yet Hardware-Certified for Broad Public GA.**

The full software architecture across the web/host shell (`app.js`, `apps/*`), authenticated loopback system bridge (`linux/mint/nexus-system-bridge.py`), per-edition desktop configurators (`cinnamon`, `xfce`, `lite-lxqt`, `lite`), installer safety & recovery tooling (`linux/installer/*`), and CI validation (`check-foundation.sh`, `check-prototype.sh`, `nexus-security-audit.sh`) is integrated, reproducible, and verified in repository/sandbox checks.

True bare-metal hardware qualification, live ISO booting across physical UEFI/Secure Boot firmware, and multi-GPU/Bluetooth/audio/Wayland/X11 integration require a real Linux Mint / QEMU KVM host and are explicitly separated from static repository checks below.

---

## 2. Verified Features (Code & Automated Checks)

| Area | Verified Capabilities | Evidence |
|---|---|---|
| **Desktop Shell & Window Manager** | 12 preinstalled apps, independent instances, resize clamping, keyboard shortcuts, corrupted-storage recovery, fault isolation | `scripts/check-desktop-integration.js`, `scripts/check-window-manager.js`, `scripts/check-app-registry.js` |
| **Native Bridge & Auth** | Loopback `127.0.0.1` HTTP server, per-session CSPRNG token (`X-Nexus-Token`), systemd user unit (`nexus-system-bridge.service`), allowlisted GUI tool launcher, all 16 `NexusNativeServices` endpoints | `apps/native-services.js`, `linux/mint/nexus-system-bridge.py`, `scripts/check-phase18-integration.js` |
| **Control Centre** | Real `nmcli`, `bluetoothctl`, `wpctl`/`pactl`, `brightnessctl`, `dunst`/`xfconf-query` DND, battery/updates/UFW status strip, debounced sliders, honest preview/unavailable states | `linux/mint/nexus-control-centre-cli.sh`, `app.js` |
| **NEXUS Store** | APT & Flatpak search/info/installed/updates, dependency inspection (`packages.info`), PolicyKit (`pkexec`) auth, protected-package guardrails, cancellation & failure messages | `apps/software-centre.js`, `linux/mint/nexus-store-cli.sh`, `scripts/check-store-native.js` |
| **Gaming Hub** | GPU/kernel driver, Vulkan (`vulkaninfo`), llvmpipe warning, Wine/Proton/Steam manifest scanning, Lutris/Heroic/GameMode/MangoHud checks, Gaming Mode toggle | `apps/gaming.js`, `linux/mint/nexus-gaming-cli.sh`, `scripts/check-gaming.js` |
| **Security & Privacy** | UFW firewall status & `pkexec` toggle, listening ports (`ss`), LUKS/Secure Boot/update checks, autostart list, Flatpak permission inspect/revoke/reset, strict repo security audit | `apps/settings-sections.js`, `linux/mint/nexus-security-cli.sh`, `scripts/check-security-privacy.js`, `linux/security/nexus-security-audit.sh` |
| **Personalisation & Themes** | 5 theme presets (`Midnight`, `Nebula`, `Arctic`, `Emerald`, `Solar`), Dark/Light appearance, 18 verified photographic wallpapers across 7 categories with attribution, safe download caching (`nexus-wallpaper-cli.sh`) | `apps/personalisation-catalog.js`, `linux/mint/nexus-wallpaper-cli.sh`, `scripts/check-personalisation.js` |
| **First-Boot & Installer** | Interactive/CLI first-boot (`nexus-firstboot.sh`) forwarding `--theme` and `--appearance` across all 4 editions; Ubiquity preflight, dual-boot (`--keep-efi`), LUKS2, and recovery CLI (`nexus-recovery.sh`) | `apps/welcome.js`, `linux/mint/nexus-firstboot.sh`, `linux/test/test-installer-safety.sh` |
| **4-Edition Parity & Lite Power** | `cinnamon`, `xfce`, `lite-lxqt`, `lite` (Openbox with Logout/Reboot/Shut Down menu), ZRAM tiers (`lite-512`..`lite-4g`), reduced motion & `:focus-visible` accessibility | `scripts/check-native-launchers.sh`, `scripts/check-phase18-integration.js`, `styles.css` |

---

## 3. Incomplete / Host-Dependent Features & Known Limitations

1. **Real-Hardware Execution vs. Sandbox Preview**:
   - In the standalone browser prototype (without `nexus-system-bridge.py`), native OS operations (Wi-Fi, Bluetooth, audio hardware, UFW, APT/Flatpak, Steam/Proton, Ubiquity partitioning) remain intentionally disconnected and report honest `Preview Only` / `Unavailable` states.
2. **Offline / Live ISO Wallpapers**:
   - Wallpaper downloads in `nexus-wallpaper-cli.sh` validate HTTPS URLs against verified Unsplash photo hosts and cache locally under `~/.local/share/nexus-os/wallpapers/`. Without internet access, built-in SVG/CSS wallpaper fallbacks apply (`wallpaper-nexus-obsidian.svg`).
3. **Edition Differences**:
   - **Cinnamon & XFCE**: Full desktop visual styling, compositor effects, and native settings integration.
   - **Lite LXQt & Lite Openbox**: Intentionally omit heavy desktop animations (`animation-duration=0`, `animateIconify=no`), Picom transparency overhead, and heavy background services to support 512 MiB–1 GiB RAM hardware.
   - **Cinnamon** uses `Mint-Y`/`Cinnamon` theme overrides (`apply-nexus-cinnamon.sh`) rather than `--appearance` light/dark flags used by Xfce/LXQt/Openbox helpers.
4. **Audio / Brightness Hardware Boundaries**:
   - Hardware backlight control requires `/sys/class/backlight/*` (unavailable in VMs or desktop monitors lacking DDC/sysfs backlight); the UI dims CSS brightness only as a preview and explicitly guards native backlight calls behind `dataset.nativeBacklight === "true"`.
   - Desktop environments without PipeWire (`wpctl`) or PulseAudio (`pactl`) report audio controls as unavailable.
5. **Security Boundaries**:
   - Traditional APT packages run unsandboxed under the user account; only Flatpak applications enforce portal sandboxing and permission overrides.
   - Privileged actions (`ufw`, `apt-get`) require interactive PolicyKit (`pkexec`) authentication and cannot execute headless without polkit agent authorization.

---

## 4. Performance & Accessibility Summary

- **Lite Openbox & Lite LXQt**: Configured with ZRAM swap tiers (`linux/lite/profiles/lite-512.conf` through `lite-4g.conf`), zero panel animation delay, no desktop icon daemon bloat, and optional bloat purging (`--purge-bloat`).
- **Web / Desktop Shell UI**:
  - Added 120 ms debouncing on volume and brightness slider native calls to prevent subprocess storms during drag gestures.
  - Added global `:focus-visible` keyboard focus rings (`2px solid var(--accent)`) across buttons, inputs, tiles, and dock icons.
  - Improved Light Mode (`theme-light`) muted text contrast (`#4e484e` on warm `#f1efed` glass) and preserved `prefers-reduced-motion` / `body.reduced-motion` rules.

---

## 5. Remaining Release Blockers Before General Availability (GA)

1. **Full ISO Build + QEMU Validation Sign-Off**:
   - `iso-and-qemu-validation.yml` validates ISO assembly, boot, memory profiles, LUKS/manual install, dual-boot, and Secure Boot across editions; final GA requires all matrix jobs green on the release commit.
2. **Bare-Metal Hardware Qualification (Stage B/C)**:
   - Run `linux/hardware/nexus-hw-qualify.sh` on target physical laptops/desktops (Intel, AMD, NVIDIA Optimus, Realtek/Intel Wi-Fi, UEFI Secure Boot, S3/S0ix suspend/resume) since sandbox/CI runners do not cover physical firmware/GPU variance.
3. **Signed Release Artifacts**:
   - Sign final `.iso` checksums (`SHA256SUMS.gpg`) with the release maintainer GPG key before public distribution (`linux/build/prepare-release.sh`).
