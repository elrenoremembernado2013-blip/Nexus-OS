# NEXUS OS Linux Mint Architecture & ISO Build Guide

## Status

**No custom NEXUS OS ISO has been built, booted, or installed yet.**
This document describes the repository-owned build pipeline under `linux/build/` and its current verification limits.

## NEXUS Linux Architecture

NEXUS OS uses **Linux Mint 22.3 Xfce** (Ubuntu 24.04 LTS Noble package base, x86-64) as its foundation:

- **Kernel & Hardware Drivers:** Inherited from Linux Mint / Ubuntu Noble (`linux-generic` / HWE).
- **Package Management:** Signed Ubuntu/Mint APT repositories (`apt`, `unattended-upgrades`) plus Flatpak (`flatpak`) for desktop applications.
- **Session & Display:** X11, Xfce 4.18, and Xfwm4 (`linux/config/nexus-system.conf`), selected to fit 4 GB RAM / 32 GB eMMC targets such as the HP Chromebook x360 14b (MADOO).
- **Boot & Init:** UEFI (OVMF in QEMU) + GRUB bootloader + `systemd`.
- **Browser Prototype Boundary:** The static web desktop (`index.html`, `app.js`, `apps/*.js`) remains a separate UI reference prototype and is not part of the ISO build or native runtime.

## Package Configuration

Package selections are organized by category in `linux/config/mint-packages.list`:

| Category | Purpose | Included by default |
|---|---|---|
| `core` | UFW firewall, unattended security updates, TLS roots, GPG, curl | Yes |
| `desktop` | Xfce GenMon panel plugin, Whisker Menu, Xfce Terminal, GVFS backends | Yes |
| `nexus` | Flatpak integration for future NEXUS Store backend | Yes |
| `gaming` | Vulkan tools, Mesa Vulkan drivers, GameMode, `steam-installer` | Optional (`--with-gaming`) |
| `development` | Git, build-essential, Python 3 | Optional (`--with-dev`) |
| `optional` | LibreOffice Writer, GIMP | Optional (`--with-optional` in guest provisioning) |

## Branding & Customisation

Non-invasive branding lives in `linux/branding/` and `linux/xfce/`:

- `linux/branding/nexus-logo.svg` -> installed to `/usr/local/share/nexus-os/branding/nexus-logo.svg`
- `linux/branding/nexus-firstboot.desktop` -> installed to `/etc/xdg/autostart/nexus-firstboot.desktop` when enabled
- `linux/xfce/nexus-dark.css` -> applied per-user to `~/.config/gtk-3.0/gtk.css` via `linux/mint/apply-nexus-xfce.sh`
- `/etc/os-release` and Mint's APT/GPG configuration are preserved intact; NEXUS writes additive metadata to `/etc/nexus-os-release`.

## Build Prerequisites

Run the read-only prerequisite check on a Linux build host:

```sh
bash linux/build/build-nexus-iso.sh --check
```

Required tools on Ubuntu/Debian/Linux Mint:

```sh
sudo apt update
sudo apt install bash gnupg coreutils xorriso squashfs-tools
```

Recommended free disk space: at least 12 GiB under `build/` (ignored by Git).

## Build Process

1. Acquire and GPG/SHA-256 verify the pinned Linux Mint 22.3 Xfce ISO:

   ```sh
   bash scripts/download-linux-mint.sh
   ```

2. Inspect the exact build plan without root or host changes:

   ```sh
   bash linux/build/build-nexus-iso.sh --dry-run
   ```

3. Build the custom ISO on a Linux host (requires `root` for `unsquashfs`/`chroot`/`mksquashfs`):

   ```sh
   sudo bash linux/build/build-nexus-iso.sh
   ```

   Pass `--with-gaming` and/or `--with-dev` to include optional package groups.

4. Expected outputs under ignored `build/iso/out/`:
   - `nexus-os-22.3-xfce-amd64.iso`
   - `nexus-os-22.3-xfce-amd64.iso.sha256`
   - `build-info.json`

## Testing & Verification Limits

- **Automated in CI (`bash scripts/check-foundation.sh`):**
  - `bash -n` syntax validation and `shellcheck` lint across all `scripts/*.sh`, `linux/mint/*.sh`, and `linux/build/*.sh`
  - Package manifest category validation (`linux/config/mint-packages.list`)
  - Non-privileged `--help`, `--check`, and `--dry-run` runs for `check-build-prereqs.sh`, `build-nexus-iso.sh`, `provision-nexus-guest.sh`, and `nexus-firstboot.sh`
- **Not yet tested:**
  - Full `build-nexus-iso.sh` execution on a Linux build host with `xorriso` and `squashfs-tools`
  - UEFI/OVMF QEMU boot of a generated NEXUS ISO (`build/iso/out/*.iso`)
  - Live-media installation and physical MADOO Chromebook hardware qualification (`docs/MADOO_CHROMEBOOK_QUALIFICATION.md`)
