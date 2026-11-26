# NEXUS OS Installation Architecture, Manual/Recovery & LUKS2 Qualification (Phase 12.5)

## Installer Components

NEXUS OS ships two complementary installation paths across Standard (`cinnamon`, `xfce`) and Lite (`lite`, `lite-lxqt`) ISOs:

1. **Interactive Graphical Ubiquity Installer (`ubiquity` + `ubiquity-frontend-gtk` + `partman-auto-crypto` + `cryptsetup`)** — recommended for interactive guided, dual-boot, manual ("Something else"), and LUKS+LVM full-disk encryption installs on `>= 1024 MiB` systems:
   - `linux/installer/nexus-install-preflight.sh` performs read-only hardware, firmware (`UEFI` vs `BIOS/Legacy`), tier-aware RAM checks, block disk detection, `ubiquity` availability, and `encryption_ux` readiness (`cryptsetup`, `lvm2`, `dm_crypt` kernel support).
   - `linux/installer/nexus-installer-launcher.sh` runs preflight, logs non-secret launch timestamps to `~/.local/state/nexus-os/installer.log`, and launches `pkexec ubiquity gtk_ui` inside live sessions.
2. **Safety-Guarded Deterministic Disk Installer (`linux/installer/nexus-disk-install.sh`, `/usr/local/bin/nexus-disk-install`)** — supports:
   - **Guided Unencrypted GPT+UEFI** (`512 MiB` FAT32 ESP + `ext4` root).
   - **Manual Pre-Partitioned GPT+UEFI** (`--efi-part PART --root-part PART [--keep-efi]`) preserving existing partition tables and unrelated data partitions.
   - **Interrupted / Failed-Install Recovery** (refuses execution without `--yes-erase-disk`; automatically detaches stale `/mnt/nexus-install-target` mounts and closes stale `/dev/mapper/nexus_crypt` before formatting).
   - **Guided LUKS2 Full-Disk Encryption** (`--luks --luks-passphrase-file FILE`, `aes-xts-plain64` 512-bit, `sha256`, `argon2id --pbkdf-memory 65536` tuned for low-RAM reliability, unencrypted `1 GiB` `/boot` + `512 MiB` ESP + encrypted root `/dev/mapper/nexus_crypt`, `/etc/crypttab`, `cryptsetup-initramfs` (`CRYPTSETUP=y`), and non-secret `/usr/local/share/nexus-os/luks-recovery-guide.txt`).
   - **Strict Secret & Test Hygiene:** Strips `\r\n` from passphrase files, unlinks ephemeral password files, never logs passphrases, and never installs `nexus-test-agent.service` or `org.nexus.test.0`.

## Phase 12.5 Separated Verification Results (Run `45876350800`, Commit `b4879cb`, QEMU/OVMF `accel=tcg`)

Unencrypted and LUKS2-encrypted installations were tested in **separate disposable QEMU/OVMF runs** on `NEXUS Lite LXQt` (`lite-lxqt`):

### 1. Unencrypted Installer Qualification (QEMU/OVMF `2048 MiB`)

| Mode | Install Result | Key Safety & Recovery Checks | Installed UEFI Boot (No ISO) | Result |
|---|---|---|---|---|
| **Guided Unencrypted (`lite`, `lite-lxqt`, `cinnamon`, `xfce`)** | **PASS** across all 4 editions (`1063–1823s`) | `BOOTX64.EFI`, `grub.cfg`, `vmlinuz`, `initrd.img`, `nexus-installed.json` verified | `3/3` boots per tier (`persist=true`, `0` `journalctl -p err`, `0` failed units) | **PASS (QEMU)** |
| **Manual Partitioning (`--efi-part /dev/vda1 --root-part /dev/vda2`)** | **PASS** (`1700.1s`) | Pre-created `/dev/vda3` (`nexus_data`) preserved during & after install (`extra_partition_preserved_after_boot: true`) | `1/1` boot from `/dev/vda2`, `live_iso_absent: true`, `0` failed systemd units | **PASS (QEMU)** |
| **Interrupted-Install Recovery** | **PASS** (`1674.4s`) | Unconfirmed run refused (`refused_without_confirm: true`); stale mounted `/mnt/nexus-install-target` cleanly recovered | `1/1` boot from `/dev/vda2`, `live_iso_absent: true`, `0` failed systemd units | **PASS (QEMU)** |

### 2. Separate LUKS2 Encrypted Qualification (`--luks` on `lite-lxqt`, QEMU/OVMF `2048 MiB`)

| Check | Measured Result (`NEXUS-125-LUKS-lite-lxqt-installer-luks`) | Notes |
|---|---|---|
| **LUKS2 Install & Metadata** | **PASS** (`1728.9s`) | `crypto_luks_blkid: true`, `crypttab_ok: true`, `luks_recovery_guide_ok: true`, `cryptsetup` + `cryptsetup-initramfs` embedded in Lite manifests |
| **Cold-Boot Serial Unlock (`ttyS0`)** | **PASS** (`prompts_count: 3`) | `prompt_seen: true`; intentionally wrong passphrase sent & rejected (`wrong_passphrase_rejected: true`); valid ephemeral passphrase unlocked `nexus_crypt` (`unlocked_confirmed: true`) with zero passphrase logging |
| **Encrypted Boot 1 (No ISO)** | **PASS** | `boot1_from_luks: true` (`/dev/mapper/nexus_crypt` root), `boot1_recovery_guide_present: true` |
| **Encrypted Reboot 2 & Persistence** | **PASS** (`boot_cycles_completed: 2`) | Re-prompted & unlocked cleanly on reboot; `boot2_from_luks: true`, `boot2_persistence_verified: true` |

## What Remains `NOT TESTED`

- Interactive **Ubiquity GUI click-through** partitioning, dual-boot NTFS/ESP resizing, and Ubiquity's own `partman-auto-crypto` GUI dialogs (only Ubiquity GTK window launch was verified).
- **Legacy BIOS (CSM / MBR)** non-UEFI installed boot.
- **Physical NVMe, SATA, eMMC**, and **physical UEFI Secure Boot** hardware installations.
