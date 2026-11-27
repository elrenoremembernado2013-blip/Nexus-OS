# NEXUS OS Linux Mint Architecture, ISO Build & Virtual Qualification Guide (Phase 13.2)

## Status

All four NEXUS OS editions (**NEXUS Standard Cinnamon**, **MADOO Xfce**, **NEXUS Lite Openbox**, and **NEXUS Lite LXQt**) have been built as GPG/SHA-256-verified Mint 22.3 remastered ISOs, verified free of test infrastructure, graphically booted in QEMU/OVMF, installed onto disposable virtual disks, and verified across 3 ISO-free reboots in GitHub Actions run [`45919673389`](https://github.com/elrenoremembernado2013-blip/Nexus-OS/actions/runs/45919673389) (`b5594a2`). Phase 13.2 adds `--locale`/`--keymap`/`--timezone`/`--validate-only`/`--status-file` to `nexus-disk-install.sh`, reproducible `minimum` (`2C/4G/30G`) and `recommended` (`4C/8G/50G`) QEMU profiles in `scripts/launch-qemu.sh`, and unified `PASS`/`FAIL`/`BLOCKED`/`NOT TESTED` virtual qualification reporting (`linux/test/run-virtual-qualification.sh`). Physical bare-metal qualification remains `NOT TESTED` (`Stage: Development / Alpha`).

## NEXUS Linux Architecture

NEXUS OS uses **Linux Mint 22.3** (Ubuntu 24.04 LTS Noble package base, `x86_64`) as its foundation:

- **Kernel & Hardware Drivers:** Inherited from Linux Mint / Ubuntu Noble (`linux-generic` / HWE).
- **Package Management:** Signed Ubuntu/Mint APT repositories (`apt`, `unattended-upgrades`) plus Flatpak (`flatpak`) for desktop applications.
- **Editions:**
  - `cinnamon`: Full NEXUS Standard Cinnamon desktop (`linux/config/cinnamon-packages.list`).
  - `xfce`: MADOO Xfce desktop (`linux/config/mint-packages.list`), tuned for 4 GiB RAM / 32 GiB eMMC targets.
  - `lite`: Ultra-low-RAM Openbox + `tint2` + `zram` desktop (`linux/lite/lite-packages.list` / `linux/lite/manifests/lite-openbox-packages.list`).
  - `lite-lxqt`: Curated Lubuntu/Ubuntu Noble LXQt + Openbox + `zram` desktop (`linux/lite/manifests/lite-lxqt-packages.list`).
- **Offline UEFI Install Readiness:** All four package manifests include `grub2-common`, `grub-efi-amd64-bin`, `grub-efi-amd64-signed`, `shim-signed`, `mokutil`, `efibootmgr`, `parted`, and `dosfstools` under `core:` so `nexus-disk-install` works offline without network access.
- **Boot & Init:** Hybrid BIOS+UEFI ISO (`boot/grub/efi.img` + `OVMF` tested) + GRUB bootloader + `systemd`.
- **Production/Test Separation:** Production ISOs contain **zero** QEMU test agents, **zero** `org.nexus.test.0` units, and **zero** test listeners. During QEMU CI runs, `run-qemu-validation.sh` extracts `/casper/initrd*` into a temporary host-side copy and injects `casper-test-hook.sh` strictly into RAM for the test run; `verify-nexus-iso.sh` unpacks every built ISO's `initrd` (`unmkinitramfs`) and SquashFS manifest (`unsquashfs -l`) and fails the build if any test artifact leaks.
- **Browser Prototype Boundary:** The static web desktop (`index.html`, `app.js`, `apps/*.js`) remains a separate UI reference prototype and is not part of the ISO build or native runtime.

## Build Prerequisites

Run the read-only prerequisite check on a Linux build host:

```sh
bash linux/build/check-build-prereqs.sh --edition lite-lxqt --strict
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

## How to Build & Verify the ISO

1. Acquire and GPG/SHA-256 verify the pinned Linux Mint 22.3 base ISO:

   ```sh
   bash scripts/download-linux-mint.sh --edition xfce      # or cinnamon
   ```

2. Build and verify production/test separation (requires `root` for `unsquashfs`/`chroot`/`mksquashfs`):

   ```sh
   sudo bash linux/build/build-nexus-iso.sh --edition xfce # or cinnamon
   sudo bash linux/lite/build-nexus-lite-iso.sh            # for lite
   sudo bash linux/lite/scripts/build-nexus-lite-lxqt-iso.sh # for lite-lxqt
   bash linux/build/verify-nexus-iso.sh --edition lite-lxqt
   ```

3. Release artifacts under ignored `build/iso/out/`:
   - `nexus-os-22.3-<edition>-amd64.iso`
   - `nexus-os-22.3-<edition>-amd64.iso.sha256`
   - `nexus-os-22.3-<edition>-amd64.iso.build-info.json`

## How to Launch the Installer & Test First Boot in QEMU

Reproducible disposable VM profiles in `scripts/launch-qemu.sh` (all qcow2 disks stay under ignored `build/images/`, never host disks):

- **Minimum profile (`--profile minimum`):** `2` vCPUs, `4096 MiB` RAM, `30G` disposable qcow2 disk
- **Recommended profile (`--profile recommended`):** `4` vCPUs, `8192 MiB` RAM, `50G` disposable qcow2 disk

```sh
# 1. Inspect resolved profile safely
bash scripts/launch-qemu.sh --profile minimum --edition lite-lxqt --dry-run

# 2. Boot the built ISO in UEFI/OVMF QEMU and run the installer inside the VM
bash scripts/launch-qemu.sh --profile minimum --edition lite-lxqt
# Inside the booted live VM:
#   - GUI installer: nexus-installer-launcher --launch
#   - Deterministic CLI installer (e.g. disposable /dev/vda):
#       sudo nexus-disk-install --disk /dev/vda --edition lite-lxqt \
#         --locale en_US.UTF-8 --keymap us --timezone UTC --yes-erase-disk

# 3. Detach ISO and test first boot directly from the installed virtual disk
bash scripts/launch-qemu.sh --profile minimum --edition lite-lxqt --disk-only
```

## Automated Virtual Qualification & Reports

Run the automated qualification harness (`linux/test/run-virtual-qualification.sh`), which strictly distinguishes `PASS`, `FAIL`, `BLOCKED`, and `NOT TESTED` and writes `build/reports/virtual-qualification-<edition>.{json,md}`:

```sh
# Local installer/manifest/security/profile checks + honest BLOCKED/NOT TESTED status when QEMU/ISO absent:
bash linux/test/run-virtual-qualification.sh --edition lite-lxqt --profile minimum

# Full automated QEMU/OVMF matrix + disposable install + 3-reboot persistence test:
bash linux/test/run-qemu-validation.sh --edition lite-lxqt --ram-matrix "1024 2048 4096" --install-ram-matrix "1024 2048" --graphical --install-test --reliability

# Or attempt local VM qualification directly via run-virtual-qualification.sh (exits 3 if BLOCKED by missing tools/ISO):
bash linux/test/run-virtual-qualification.sh --edition lite-lxqt --profile minimum --run-vm
```

## Troubleshooting & Known Limitations

- **QEMU TCG slowness / timeouts:** Software emulation (`NEXUS_QEMU_ACCEL=tcg`) is portable but slow; use KVM (`NEXUS_QEMU_ACCEL=kvm`) when `/dev/kvm` is available.
- **Missing local QEMU / OVMF / ISO:** Without `qemu-system-x86_64`, `ovmf`, and a built ISO under `build/iso/out/`, `run-virtual-qualification.sh --run-vm` marks VM checks `BLOCKED` and exits `3` rather than faking results.
- **Legacy BIOS / MBR:** `nexus-disk-install.sh` enforces UEFI GPT + FAT32 ESP (`x86_64-efi`); Legacy BIOS/MBR remains unsupported in the CLI path (`NOT TESTED`).
- **Complete Ubiquity GUI install & physical bare-metal hardware:** Full click-through Ubiquity GUI installation and bare-metal GPU/Wi-Fi/audio/NVMe/OEM Secure Boot tests remain `NOT TESTED` (`docs/HARDWARE_TESTING_GUIDE.md`, `docs/RECOVERY_AND_BOOT.md`).
