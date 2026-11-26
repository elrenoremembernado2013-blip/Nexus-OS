# NEXUS OS Installation Architecture (Phase 12.3)

## Installer Components

NEXUS OS ships two complementary installation paths on the remastered Linux Mint 22.3 (`noble`) live ISOs:

1. **Interactive Graphical Ubiquity Installer (`ubiquity` + `ubiquity-frontend-gtk` + `partman` + `cryptsetup`)** — recommended for interactive guided, dual-boot, manual ("Something else"), and LUKS+LVM full-disk encryption installs on `>= 1024 MiB` systems:
   - `linux/installer/nexus-install-preflight.sh` performs read-only hardware, firmware (`UEFI` vs `BIOS/Legacy`), RAM, block disk (`lsblk -J`), GPU, network, audio, battery, display, and `ubiquity` availability checks.
   - `linux/installer/nexus-installer-launcher.sh` runs preflight, writes non-secret launch timestamps to `~/.local/state/nexus-os/installer.log`, and launches `pkexec ubiquity gtk_ui` only inside a live session.
   - `apps/welcome.js` provides the **NEXUS Welcome & Installer Guide** UI for both the live pre-install orientation and the 7-step First-Boot Experience (`nexus-firstboot.sh`).
2. **Safety-Guarded Deterministic Disk Installer (`linux/installer/nexus-disk-install.sh`, installed as `/usr/local/bin/nexus-disk-install`)** — used for automated QEMU/OVMF validation and low-RAM (`512–768 MiB`) CLI installation via `nexus-lite-install --disk`:
   - Enforces `root`, verifies target is a whole block disk (`TYPE=disk`), refuses to touch the live/booted host root disk, requires explicit `--yes-erase-disk`, and supports `--dry-run`.
   - Creates GPT `512 MiB` FAT32 EFI System Partition + `ext4` root, writes UUID-based `/etc/fstab`, creates user accounts without hardcoded passwords (prompting via TTY or reading `--password-file` with `chmod 0600`), strips `casper` live artifacts, regenerates `initramfs`, and installs UEFI GRUB (`--no-nvram`) into `EFI/nexus/`, `EFI/ubuntu/` (required by Ubuntu/Mint's signed `grubx64.efi`), and `EFI/BOOT/BOOTX64.EFI`.
   - **Never** embeds or installs any test agent (`nexus-test-agent.service` or `org.nexus.test.0`).

## Minimum & Recommended Hardware

- **Architecture:** `x86_64` (`amd64`)
- **NEXUS Lite:** `512 MiB` experimental (`CLI` install), `1024 MiB` recommended minimum (`20 GiB` storage)
- **NEXUS Standard (Cinnamon) & MADOO Xfce:** `2048 MiB` minimum (`Cinnamon` entry floor), `4096 MiB` recommended (`20–32 GiB` storage)
- **Firmware:** 64-bit UEFI (or Legacy BIOS)

## Verification Status (Phase 12.3, Run `45722286627`)

- **Verified locally & in CI:** `nexus-install-preflight.sh`, `nexus-installer-launcher.sh --check` / `--dry-run`, `nexus-disk-install.sh` refusal without `--yes-erase-disk`, `shellcheck`, and `npm test`.
- **Verified in QEMU/OVMF (`accel=tcg`) on disposable `20 GiB` `qcow2` disks:**
  - Ubiquity GTK UI launch & window rendering (`96.63–99.98%` non-black) on `lite 1024/2048 MiB`, `cinnamon 2048/4096 MiB`, and `xfce 4096 MiB`.
  - End-to-end `/dev/vda` disk installation (`10/10` attempts across all 3 editions, `832.5–1188.8s`) + `21/21` ISO-free UEFI boots (`2x` warm reboot + `1x` cold boot per tier) + user/file persistence across reboots (`persist=true`).
- **Untested (requires manual / bare-metal runs):** interactive Ubiquity GUI click-through partitioning, dual-boot resizing, LUKS+LVM passphrase entry, Legacy BIOS (non-UEFI) installed boot, and physical NVMe/eMMC/Secure Boot hardware.
