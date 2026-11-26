# NEXUS OS Linux Mint Architecture, ISO Build & Validation Guide

## Status

All three NEXUS OS editions (**NEXUS Standard Cinnamon**, **MADOO Xfce**, and **NEXUS Lite**) have been built as GPG/SHA-256-verified Mint 22.3 remastered ISOs, verified free of test infrastructure, graphically booted in QEMU/OVMF, installed onto disposable virtual disks, and verified across 3 ISO-free reboots in GitHub Actions run [`45722286627`](https://github.com/elrenoremembernado2013-blip/Nexus-OS/actions/runs/45722286627) (`efc6c01`). Physical bare-metal qualification remains pending (`Stage: Development / Alpha`).

## NEXUS Linux Architecture

NEXUS OS uses **Linux Mint 22.3** (Ubuntu 24.04 LTS Noble package base, `x86_64`) as its foundation:

- **Kernel & Hardware Drivers:** Inherited from Linux Mint / Ubuntu Noble (`linux-generic` / HWE).
- **Package Management:** Signed Ubuntu/Mint APT repositories (`apt`, `unattended-upgrades`) plus Flatpak (`flatpak`) for desktop applications.
- **Editions:**
  - `cinnamon`: Full NEXUS Standard Cinnamon desktop (`linux/config/cinnamon-packages.list`).
  - `xfce`: MADOO Xfce desktop (`linux/config/mint-packages.list`), tuned for 4 GiB RAM / 32 GiB eMMC targets.
  - `lite`: Ultra-low-RAM Openbox + `tint2` + `zram` desktop (`linux/lite/lite-packages.list`).
- **Offline UEFI Install Readiness:** All three package manifests include `grub2-common`, `grub-efi-amd64-bin`, `efibootmgr`, `parted`, and `dosfstools` under `core:` so `nexus-disk-install` works offline without network access.
- **Boot & Init:** Hybrid BIOS+UEFI ISO (`boot/grub/efi.img` + `OVMF` tested) + GRUB bootloader + `systemd`.
- **Production/Test Separation:** Production ISOs contain **zero** QEMU test agents, **zero** `org.nexus.test.0` units, and **zero** test listeners. During QEMU CI runs, `run-qemu-validation.sh` extracts `/casper/initrd*` into a temporary host-side copy and injects `casper-test-hook.sh` strictly into RAM for the test run; `verify-nexus-iso.sh` unpacks every built ISO's `initrd` (`unmkinitramfs`) and SquashFS manifest (`unsquashfs -l`) and fails the build if any test artifact leaks.
- **Browser Prototype Boundary:** The static web desktop (`index.html`, `app.js`, `apps/*.js`) remains a separate UI reference prototype and is not part of the ISO build or native runtime.

## Build Prerequisites

Run the read-only prerequisite check on a Linux build host:

```sh
bash linux/build/build-nexus-iso.sh --check
```

Required tools on Ubuntu/Debian/Linux Mint:

```sh
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  bash coreutils curl gnupg xorriso squashfs-tools \
  qemu-system-x86 qemu-utils ovmf shellcheck cpio gzip \
  initramfs-tools-core zstd xz-utils
```

Recommended free disk space: at least 12–15 GiB under `build/` (ignored by Git).

## Build & End-to-End Validation Process

1. Acquire and GPG/SHA-256 verify the pinned Linux Mint 22.3 base ISO:

   ```sh
   bash scripts/download-linux-mint.sh --edition xfce      # or cinnamon
   ```

2. Build and verify production/test separation (requires `root` for `unsquashfs`/`chroot`/`mksquashfs`):

   ```sh
   sudo bash linux/build/build-nexus-iso.sh --edition xfce # or cinnamon
   sudo bash linux/lite/build-nexus-lite-iso.sh            # for lite
   bash linux/build/verify-nexus-iso.sh --edition xfce     # checks initrd + squashfs for zero test leaks
   ```

3. Run graphical live + disposable-disk install + 3-reboot installed validation in QEMU/OVMF:

   ```sh
   bash linux/test/run-qemu-validation.sh --edition xfce --ram-matrix "4096" --install-test --reliability
   bash linux/test/run-qemu-validation.sh --edition cinnamon --ram-matrix "2048 4096" --install-test --reliability
   bash linux/test/run-qemu-validation.sh --edition lite --ram-matrix "512 768 1024 2048" --install-test --reliability
   ```

4. Release artifacts under ignored `build/iso/out/`:
   - `nexus-os-22.3-<edition>-amd64.iso`
   - `nexus-os-22.3-<edition>-amd64.iso.sha256`
   - `build-info.json`

## Testing & Verification Limits

- **Verified locally & in CI (`npm test`):** `bash -n`, `shellcheck`, package manifest validation, installer refusal without `--yes-erase-disk`, zero `org.nexus.test.0` leaks in production paths, and prototype/bridge unit tests.
- **Verified in CI QEMU/OVMF (`45722286627`):** ISO build & test-leak verification (3/3 editions), live ISO graphical boots (15/15), Ubiquity GTK UI launch (`>= 1024 MiB`), disposable `/dev/vda` installs (10/10), ISO-free 3-reboot installed boots (21/21), and user config persistence (`7/7` configs).
- **Untested:** Physical bare-metal hardware qualification (`docs/MADOO_CHROMEBOOK_QUALIFICATION.md`), real Wi-Fi/audio/GPU drivers, Secure Boot enforcement, and interactive LUKS+LVM Ubiquity click-throughs.
