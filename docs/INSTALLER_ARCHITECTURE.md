# NEXUS OS Installation Architecture, Dual-Boot, Recovery & Secure Boot Qualification (Phase 13.0)

## Installer Components

NEXUS OS ships two complementary installation paths across Standard (`cinnamon`, `xfce`) and Lite (`lite`, `lite-lxqt`) ISOs:

1. **Interactive Graphical Ubiquity Installer (`ubiquity` + `ubiquity-frontend-gtk` + `partman-auto-crypto` + `cryptsetup`)** — recommended for interactive guided, dual-boot, manual ("Something else"), and LUKS+LVM full-disk encryption installs on `>= 1024 MiB` systems:
   - `linux/installer/nexus-install-preflight.sh` performs read-only hardware, firmware (`UEFI` vs `BIOS/Legacy`), Secure Boot chain (`shimx64.efi`, `grub-efi-amd64-signed`, `grub-pc`), dual-boot/NTFS/ESP partition detection (`os-prober`, `ntfs-3g`), tier-aware RAM checks, `installer_modes` classification, and `encryption_ux` readiness.
   - `linux/installer/nexus-installer-launcher.sh` runs preflight, logs non-secret launch timestamps to `~/.local/state/nexus-os/installer.log`, and launches `pkexec ubiquity gtk_ui` inside live sessions.
2. **Safety-Guarded Deterministic Disk Installer (`linux/installer/nexus-disk-install.sh`, `/usr/local/bin/nexus-disk-install`)** — supports:
   - **Guided Unencrypted GPT+UEFI** (`512 MiB` FAT32 ESP + `ext4` root).
   - **Manual Pre-Partitioned & Dual-Boot ESP Preservation** (`--efi-part PART --root-part PART [--keep-efi]`): preserves existing GPT tables, unrelated data/Windows NTFS partitions, and existing EFI loaders (`/EFI/Microsoft/Boot/bootmgfw.efi`), enables `GRUB_DISABLE_OS_PROBER=false` when `--keep-efi` is set, and guarantees signed `shimx64.efi` (`BOOTX64.EFI`) + `grubx64.efi` + `mmx64.efi` + `fbx64.efi` across `EFI/BOOT`, `EFI/nexus`, and `EFI/ubuntu`.
   - **Interrupted / Failed-Install Recovery** (refuses execution without `--yes-erase-disk`; automatically detaches stale `/mnt/nexus-install-target` mounts and closes stale `/dev/mapper/nexus_crypt` before formatting).
   - **Guided LUKS2 Full-Disk Encryption** (`--luks --luks-passphrase-file FILE`, `aes-xts-plain64` 512-bit, `sha256`, `argon2id --pbkdf-memory 65536`, unencrypted `1 GiB` `/boot` + `512 MiB` ESP + encrypted root `/dev/mapper/nexus_crypt`, `/etc/crypttab`, `cryptsetup-initramfs`, and non-secret `/usr/local/share/nexus-os/luks-recovery-guide.txt`).
   - **Strict Secret & Test Hygiene:** Strips `\r\n` from passphrase files, unlinks ephemeral password files, never logs passphrases, and never installs `nexus-test-agent.service` or `org.nexus.test.0`.

## Phase 12.5 Verified QEMU/OVMF Baseline (`45876350800`, `b4879cb`, `accel=tcg`)

| Mode | Install Result | Key Safety & Recovery Checks | Installed UEFI Boot (No ISO) | Result |
|---|---|---|---|---|
| **Guided Unencrypted (`lite`, `lite-lxqt`, `cinnamon`, `xfce`)** | **PASS** across all 4 editions (`1063–1823s`) | `BOOTX64.EFI`, `grub.cfg`, `vmlinuz`, `initrd.img`, `nexus-installed.json` verified | `3/3` boots per tier (`persist=true`, `0` `journalctl -p err`, `0` failed units) | **PASS (QEMU)** |
| **Manual Partitioning (`--efi-part /dev/vda1 --root-part /dev/vda2`)** | **PASS** (`1700.1s`) | Pre-created `/dev/vda3` (`nexus_data`) preserved during & after install (`extra_partition_preserved_after_boot: true`) | `1/1` boot from `/dev/vda2`, `live_iso_absent: true`, `0` failed units | **PASS (QEMU)** |
| **Interrupted-Install Recovery** | **PASS** (`1674.4s`) | Unconfirmed run refused (`refused_without_confirm: true`); stale mounted `/mnt/nexus-install-target` recovered | `1/1` boot from `/dev/vda2`, `live_iso_absent: true`, `0` failed units | **PASS (QEMU)** |
| **Separate LUKS2 Cold-Boot Unlock (`lite-lxqt`)** | **PASS** (`1728.9s`) | `crypto_luks_blkid: true`, `crypttab_ok: true`, `luks_recovery_guide_ok: true`; wrong passphrase rejected (`prompts_count: 3`) | `boot1_from_luks: true`, `boot2_from_luks: true`, `boot2_persistence_verified: true` | **PASS (QEMU)** |

## Phase 13.0 Automated Disposable-QEMU Extensions (`linux/test/run-phase130-tests.sh`)

- **Simulated Dual-Boot / NTFS / `--keep-efi` Preservation (`--dualboot-test`):** Creates a disposable GPT virtual disk (`vda1` ESP with `/EFI/Microsoft/Boot/bootmgfw.efi`, `vda2` NTFS `Windows/System32/winload.efi`, `vda3` target root), verifies `nexus-install-preflight` detects ESP+NTFS dual-boot candidates, installs with `--keep-efi`, and verifies both Windows EFI and NTFS partitions survive after installed boot. *(Awaiting Phase 13.0 CI QEMU run — currently `NOT TESTED` in CI until `iso-and-qemu-validation.yml` completes.)*
- **Enforced OVMF Secure Boot Signed Chain (`--secure-boot-test`):** Packaged `core:shim-signed`, `core:grub-efi-amd64-signed`, `core:mokutil`, `core:ntfs-3g`, and `core:os-prober` into all 5 edition manifests (`mint`, `cinnamon`, `lite`, `lite-openbox`, `lite-lxqt`), and added an enforced OVMF Secure Boot test (`OVMF_CODE_4M.secboot.fd` + `OVMF_VARS_4M.ms.fd`, `smm=on`) to `run-phase130-tests.sh`. *(Awaiting Phase 13.0 CI QEMU run — currently `NOT TESTED` until CI completes.)*

## What Remains `NOT TESTED`

- Interactive **Ubiquity GUI click-through** partitioning, dual-boot NTFS/ESP resizing, and Ubiquity's own `partman-auto-crypto` GUI dialogs (manual checklist documented in `docs/HARDWARE_TESTING_GUIDE.md`; only Ubiquity GTK window launch was verified).
- **Legacy BIOS (CSM / MBR)** non-UEFI installed boot (`nexus-disk-install.sh` requires UEFI `x86_64-efi` and does not install `grub-pc` MBR bootloaders).
- **Physical NVMe, SATA, eMMC**, and **physical OEM UEFI Secure Boot** hardware installations.
