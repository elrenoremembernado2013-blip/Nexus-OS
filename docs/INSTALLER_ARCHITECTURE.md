# NEXUS OS Installation Architecture & LUKS Readiness Review (Phase 12.4)

## Installer Components

NEXUS OS ships two complementary installation paths across Standard (Cinnamon / Xfce) and Lite (Openbox / LXQt) ISOs:

1. **Interactive Graphical Ubiquity Installer (`ubiquity` + `ubiquity-frontend-gtk` + `partman-auto-crypto` + `cryptsetup`)** — recommended for interactive guided, dual-boot, manual ("Something else"), and **LUKS+LVM full-disk encryption** installs on `>= 1024 MiB` systems:
   - `linux/installer/nexus-install-preflight.sh` performs read-only hardware, firmware (`UEFI` vs `BIOS/Legacy`), tier-aware RAM checks (`512 MiB` Lite experimental CLI floor, `1024 MiB` Lite min, `2048 MiB` Standard floor, `4096 MiB` Standard recommended), block disks (`lsblk -J`, non-removable count), `ubiquity` availability, and `encryption_ux` readiness (`cryptsetup`, `lvm2`, `dm_crypt` kernel support).
   - `linux/installer/nexus-installer-launcher.sh` runs preflight, writes non-secret launch timestamps to `~/.local/state/nexus-os/installer.log`, and launches `pkexec ubiquity gtk_ui` only inside a live session.
2. **Safety-Guarded Deterministic Disk Installer (`linux/installer/nexus-disk-install.sh`, `/usr/local/bin/nexus-disk-install`)** — used for automated QEMU/OVMF validation and low-RAM (`512–768 MiB`) CLI installs via `nexus-lite-install --disk`:
   - Enforces `root`, verifies target is a whole block disk (`TYPE=disk`), refuses to touch the live/booted host root disk, requires explicit `--yes-erase-disk`, and supports `--dry-run`.
   - Creates GPT `512 MiB` FAT32 EFI System Partition + `ext4` root, writes UUID-based `/etc/fstab`, creates user accounts without hardcoded passwords (`openssl passwd -6` via TTY or `chmod 0600` `--password-file`), strips `casper` live artifacts, regenerates `initramfs`, and installs UEFI GRUB (`--no-nvram`) into `EFI/nexus/`, `EFI/ubuntu/` (for Mint/Ubuntu signed `grubx64.efi`), and `EFI/BOOT/BOOTX64.EFI`.
   - **Never** embeds or installs `nexus-test-agent.service` or `org.nexus.test.0`.

## LUKS / Full-Disk Encryption Review (Honest Scope)

- **What is verified:** `cryptsetup`, `lvm2`, and `dm_crypt` presence checks in `nexus-install-preflight.sh` (`encryption_ux`), Ubiquity GTK UI launch on `1024 / 2048 / 4096 MiB` across `lite`, `lite-lxqt`, `cinnamon`, and `xfce`, and unencrypted GPT+UEFI automated disk installation (`nexus-disk-install.sh`).
- **What is NOT automated or claimed:** `nexus-disk-install.sh` performs **unencrypted** `GPT + ext4` installs for deterministic CI testing; interactive **LUKS passphrase entry, recovery-key guidance, and cold-boot `cryptsetup` unlock** rely on Ubiquity `partman-auto-crypto` and **have NOT been end-to-end tested in headless CI** (explicitly documented as untested rather than fabricated).

## Verification Status (Phase 12.3 `45722286627` + Phase 12.4 `45808626482`)

- **Verified in CI & QEMU/OVMF (`accel=tcg`) on disposable `20 GiB` `qcow2` disks:**
  - `lite-lxqt` (`512`, `768`, `1024`, `2048 MiB`): `5/5` `/dev/vda` installs (`1154.0–1229.4s`) and `12/12` ISO-free UEFI boots (`2x` warm + `1x` cold per tier, `0` `journalctl -p err`, `0` failed units, `persist=true`).
  - `lite` Openbox (`1024 MiB` Phase 12.4 + `512/768/1024/2048 MiB` Phase 12.3): `6/6` installs and `15/15` ISO-free UEFI boots (`persist=true`).
  - `cinnamon` (`2048/4096 MiB`) & `xfce` (`4096 MiB`): `5/5` installs and `9/9` ISO-free UEFI boots (Phase 12.3).
- **Untested:** Interactive Ubiquity GUI click-through partitioning, dual-boot NTFS/ESP resizing, LUKS+LVM unlock prompts, Legacy BIOS non-UEFI installed boot, and physical NVMe/eMMC/Secure Boot hardware.
