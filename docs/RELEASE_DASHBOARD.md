# NEXUS OS Release Readiness Dashboard (Phase 10)

**Current Release Stage:** `Development` (ISO build & VM acceptance pending external Linux Mint build host)
**Stable Release Decision:** **HOLD — Not ready for `Stable` release** until external ISO build, UEFI/QEMU live boot, and Ubiquity disk installation pass.

## Subsystem Status Matrix

| Subsystem | Status | Verified Locally / in CI | Pending Live Mint Host / VM Verification |
|---|---|---|---|
| **Linux Mint Foundation** | Ready (Config & Scripts) | `nexus-system.conf`, `mint-packages.list`, `validate-packages.sh`, `provision-nexus-guest.sh --dry-run` | Live `apt update`/`upgrade`, `systemd` service boot |
| **Desktop & Shell** | Prototype + Mint Layers Ready | Browser multi-window shell (`app.js`), `linux/cinnamon/` 5-theme generator + `--revert`, `linux/xfce/` | Live Cinnamon / Xfce session rendering & `gsettings` panel behavior |
| **Core Applications** | Bridge & UI Tested | `nexus-system-bridge.py` (`BASH_OK:5.2.15(1)-release` real PTY, `/proc` telemetry, 15 `check-*.js` suites) | Live GUI launch (`nemo`, `gnome-system-monitor`, `cinnamon-settings`, `firefox`) |
| **NEXUS Store** | CLI & Adapter Tested | `nexus-store-cli.sh` (`apt:true`), protected-package refusal, `check-store-native.js` | Live `pkexec` + `apt-get` + `flatpak` installs |
| **Security & Privacy** | CLI, API & UI Tested | `nexus-security-cli.sh status` + `--dry-run`, `/api/security/status`, `check-security-privacy.js`, zero secrets grep | Live `ufw` toggle, UEFI `efivars` Secure Boot, LUKS disk encryption |
| **Gaming & Proton** | CLI, API & UI Tested | `nexus-gaming-cli.sh status` + `--dry-run`, `/api/gaming/status`, `check-gaming.js` | Physical GPU Vulkan (`vulkaninfo`), Steam launch, Proton, controllers |
| **Personalisation** | Engine & Attribution Tested | 5 themes, 10 attributed photos (zero AI), 6 profiles, `apply-nexus-cinnamon.sh`, `check-personalisation.js` | Live Cinnamon compositor effects & HTTPS wallpaper caching |
| **Installer & First-Boot** | Preflight & Wizard Tested | `nexus-install-preflight.sh`, `nexus-installer-launcher.sh --dry-run`, `apps/welcome.js`, `check-installer.js` | Live ISO Ubiquity partitioning, LUKS, user setup, GRUB install |
| **ISO & Release Pipeline** | Scripts Tested; ISO Blocked Here | `build-nexus-iso.sh --dry-run`, `verify-nexus-iso.sh --dry-run`, `prepare-release.sh` stage gate | Actual ISO build (`xorriso`, `mksquashfs`, Mint base ISO) & QEMU/OVMF boot |

## Blocker Summary Preventing `Stable` Promotion

1. **No ISO generated in sandbox:** `gpg`, `xorriso`, `unsquashfs`, `mksquashfs`, `chroot`, and Mint mirror access are unavailable in this restricted container (`check-build-prereqs.sh`: `NOT READY`).
2. **No VM install completed:** `qemu-system-x86_64` and `qemu-img` are absent here; live boot, Ubiquity disk partitioning, GRUB install, reboot, and post-install smoke tests remain unexecuted.
3. **No physical GPU/controller hardware:** Vulkan 3D acceleration, Steam/Proton game launch, Wi-Fi/Bluetooth/Audio drivers, and USB/Bluetooth controllers require physical or passthrough test hardware.
