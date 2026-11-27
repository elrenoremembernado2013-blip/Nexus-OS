# NEXUS OS Installation Architecture, Recovery, Dual-Boot & Secure Boot Qualification (Phase 13.2)

## Installer Components

NEXUS OS ships two complementary installation paths plus a dedicated read-only-by-default recovery tool across all four editions (`cinnamon`, `xfce`, `lite`, `lite-lxqt`):

1. **Read-Only Preflight & Live Launcher (`nexus-install-preflight.sh`, `nexus-installer-launcher.sh`, `nexus-lite-install.sh`)**:
   - `linux/installer/nexus-install-preflight.sh` performs strictly read-only checks for CPU architecture, total & available RAM, VM vs. bare-metal environment (`environment.is_virtual_machine`), active NEXUS edition (`--edition` or `/etc/nexus-os-release`), UEFI vs. BIOS firmware, Secure Boot chain (`shimx64.efi`, `grub-efi-amd64-signed`, `grub-pc`), disk sizes/types (`nvme_ssd`, `sata_or_usb_ssd`, `hdd_rotational`, `virtio_virtual_disk`), dual-boot/NTFS/ESP partition detection (`os-prober`, `ntfs-3g`), required CLI/GUI tools, network state (confirming offline squashfs installation works), and `structured_warnings` (each stating `problem`, `why_it_matters`, `can_continue`, and `recommended_action`).
   - `linux/installer/nexus-installer-launcher.sh` refuses to bypass hard hardware blockers (`arch != x86_64`, `< 512 MiB` RAM, no eligible disk `>= 10 GiB`), refuses Ubiquity GTK below `850 MiB` unless `--force-low-ram` is explicitly passed (recommending `nexus-lite-install`), logs non-secret timestamps to `~/.local/state/nexus-os/installer.log`, and records non-zero exit recovery instructions.
   - `linux/lite/nexus-lite-install.sh` detects the active Lite edition (`lite` vs. `lite-lxqt`) from `/etc/nexus-os-release` (respecting `--edition` overrides) instead of hardcoding `lite`.
2. **Interactive Graphical Ubiquity Installer (`ubiquity` + `ubiquity-frontend-gtk` + `partman-auto-crypto` + `cryptsetup`)** — recommended for interactive guided, dual-boot, manual ("Something else"), and LUKS+LVM full-disk encryption installs on `>= 1024 MiB` systems.
   - `apps/welcome.js` surfaces edition-aware RAM floors, Secure Boot state, dual-boot detection, structured preflight warnings, destructive confirmation gating, and `nexus-recovery` references.
3. **Safety-Guarded Deterministic Disk Installer (`linux/installer/nexus-disk-install.sh`, `/usr/local/bin/nexus-disk-install`)** — supports:
   - **Language, Keyboard, Timezone & Configuration Validation:** `--locale` (default `en_US.UTF-8` → `/etc/default/locale`), `--keymap` (default `us` → `/etc/default/keyboard` + `/etc/vconsole.conf`), `--timezone` (default `UTC` → `/etc/localtime` + `/etc/timezone`), `--validate-only`, and real 8-stage progress reporting (`[STAGE 1/8]`..`[STAGE 8/8]` plus optional JSON `--status-file PATH`).
   - **Guided Unencrypted GPT+UEFI** (`512 MiB` FAT32 ESP + `ext4` root).
   - **Manual Pre-Partitioned & Dual-Boot ESP Preservation** (`--efi-part PART --root-part PART [--keep-efi]`): validates both partitions belong to `--disk`, are unmounted, `--root-part >= 8 GiB`, and `--efi-part` is `vfat` when `--keep-efi` is passed; preserves existing GPT tables, unrelated data/Windows NTFS partitions, and existing EFI loaders (`/EFI/Microsoft/Boot/bootmgfw.efi`), enables `GRUB_DISABLE_OS_PROBER=false` when `--keep-efi` is set, and installs signed `shimx64.efi` (`BOOTX64.EFI`) + `grubx64.efi` + `mmx64.efi` + `fbx64.efi` across `EFI/BOOT`, `EFI/nexus`, and `EFI/ubuntu`.
   - **Failure-Stage Reporting & Interrupted-Install Recovery**: tracks `CURRENT_STAGE` and `DISK_MODIFIED`, cleans up temporary mounts and LUKS mappers via `EXIT`/`ERR` traps, prints exact recovery instructions (`nexus-recovery --diagnose`, `lsblk -f`, `/var/log/nexus-install.log`), and on retry detaches stale `/mnt/nexus-install-target` mounts and `/dev/mapper/nexus_crypt` before formatting.
   - **Guided LUKS2 Full-Disk Encryption** (`--luks --luks-passphrase-file FILE`, `aes-xts-plain64` 512-bit, `sha256`, `argon2id --pbkdf-memory 65536`, unencrypted `1 GiB` `/boot` + `512 MiB` ESP + encrypted root `/dev/mapper/nexus_crypt`, `/etc/crypttab`, `cryptsetup-initramfs`, and non-secret `/usr/local/share/nexus-os/luks-recovery-guide.txt`).
   - **Strict Secret & Test Hygiene:** Strips `\r\n` and rejects blank/whitespace passphrase files, never logs passphrases, and never installs `nexus-test-agent.service` or `org.nexus.test.0`.
4. **Read-Only-by-Default Recovery Tool (`linux/installer/nexus-recovery.sh`, `/usr/local/bin/nexus-recovery`, `docs/RECOVERY_AND_BOOT.md`)**:
   - Packaged in all 4 editions (`cinnamon`, `xfce`, `lite`, `lite-lxqt`) with `nexus-recovery.desktop`.
   - `--diagnose` inspects firmware, Secure Boot, `/boot/efi/EFI/*`, `/etc/fstab` & `/etc/crypttab` consistency, failed systemd units, and installer logs without modifying disks (`--redacted` strips UUIDs).
   - `--guide` prints step-by-step backup-first, UEFI GRUB, `fsck -n` / `e2fsck`, LUKS2 header/slot recovery, `dpkg`/`apt` repair, and dual-boot guidance; `--fsck-dry-run` explains the read-only `fsck -n` action and requires `--confirm`.

## Ubiquity GUI Qualification Tiers (Strictly Separated)

| Qualification Tier | Automated Status | Notes |
|---|---|---|
| **1. Installer Launch Verified** | **PASS (`45919673389`, QEMU)** | `ubiquity gtk_ui` window launch verified via X11 + QMP screenshot across `lite` (`1G+`), `lite-lxqt` (`1G+`), `cinnamon`, and `xfce`. |
| **2. Individual Screens Navigated & Verified** | **Implemented (`nexus-guest-test.py` + `qemu-graphical-runner.py`), awaiting CI run** | QMP `send-key` + `/var/log/installer/debug` step inspection (`01_language` -> `02_keyboard` -> `03_prepare` -> `04_partman`) added in Phase 13.1. |
| **3. Complete GUI Install Verified** | **`NOT TESTED`** | Full click-through Ubiquity installation to completion & reboot remains untested (automated installs use `nexus-disk-install.sh`). |
| **4. Installed-System Boot Verified** | **PASS (`45919673389`, QEMU CLI installs)** | `3/3` ISO-free UEFI boots per edition/tier after `nexus-disk-install.sh` (unencrypted, manual, recovery, LUKS2, dual-boot `--keep-efi`, OVMF Secure Boot). |

## Phase 12.5–13.1 Verified Baseline (`45919673389` QEMU + Local Safety Suite)

| Mode | Result | Key Safety & Recovery Checks | Installed UEFI Boot (No ISO) |
|---|---|---|---|
| **Preflight, Failure Refusal, Edition Isolation & Recovery Suite (`test-installer-safety.sh`)** | **PASS (Local)** | Refuses missing `--yes-erase-disk`, bad `--edition`, mismatched manual partitions, `--keep-efi` without parts, `--luks` + `--efi-part`, blank LUKS passphrase, unconfirmed `--fsck-dry-run`; `lite-lxqt` preserved in `nexus-lite-install`; UUIDs redacted. | N/A (non-destructive safety suite) |
| **Guided Unencrypted (`lite`, `lite-lxqt`, `cinnamon`, `xfce`)** | **PASS (`45919673389`, QEMU)** | `BOOTX64.EFI`, `grub.cfg`, `vmlinuz`, `initrd.img`, `nexus-installed.json` verified (`1213–1766s`). | `3/3` boots per tier (`persist=true`, `0` `journalctl -p err`, `0` failed units) |
| **Manual Partitioning (`--efi-part /dev/vda1 --root-part /dev/vda2`)** | **PASS (`45919673389`, QEMU)** | Pre-created `/dev/vda3` preserved during & after install (`extra_partition_preserved_after_boot: true`). | `1/1` boot from `/dev/vda2`, `live_iso_absent: true`, `0` failed units |
| **Interrupted-Install Recovery** | **PASS (`45919673389`, QEMU)** | Unconfirmed run refused; stale mounted `/mnt/nexus-install-target` cleanly recovered. | `1/1` boot from `/dev/vda2`, `live_iso_absent: true`, `0` failed units |
| **Separate LUKS2 Cold-Boot Unlock (`lite-lxqt`)** | **PASS (`45919673389`, QEMU)** | `crypto_luks_blkid: true`, `crypttab_ok: true`, `luks_recovery_guide_ok: true`; wrong passphrase rejected (`prompts_count: 3`). | `boot1_from_luks: true`, `boot2_from_luks: true`, `boot2_persistence_verified: true` |
| **Simulated Dual-Boot / NTFS / `--keep-efi` (`lite-lxqt`)** | **PASS (`45919673389`, QEMU)** | `dualboot_preflight_detected: true`, `dualboot_efi_preserved_install: true`, `dualboot_os_part_preserved_install: true`. | `1/1` boot from `/dev/vda3`, Windows EFI & NTFS markers preserved (`0` failed units) |
| **Enforced OVMF Secure Boot Signed Chain (`lite-lxqt`)** | **PASS (`45919673389`, QEMU)** | Booted under `OVMF_CODE_4M.secboot.fd` + `OVMF_VARS_4M.ms.fd` (`smm=on`), `secure_boot_state: "enabled"`, `efi_boot_ok: true`. | `1/1` boot, `0` failed units |

## What Remains `NOT TESTED` or `Unsupported`

- **Complete interactive Ubiquity GUI installation** (wizard click-through from Language to Reboot, Ubiquity `partman-auto-crypto` GUI, and Ubiquity NTFS resize) (`NOT TESTED`).
- **Legacy BIOS (CSM / MBR)** non-UEFI installed boot (`Unsupported` in `nexus-disk-install.sh`, which enforces UEFI `x86_64-efi`).
- **Physical NVMe, SATA, eMMC**, **physical Windows BitLocker/Fast-Startup dual-boot**, and **physical OEM UEFI Secure Boot** hardware installations (`NOT TESTED`).
