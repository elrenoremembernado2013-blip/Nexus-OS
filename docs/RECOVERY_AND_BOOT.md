# NEXUS OS Recovery, Boot Troubleshooting & Repair Guide

> **Always back up personal data before attempting repairs.** Never format drives, repartition disks, or modify firmware/BIOS/UEFI settings without verifying your target device (`lsblk -f`) and saving personal files to external storage.

---

## 1. Quick Read-Only Diagnosis (`nexus-recovery`)

NEXUS OS ships a strictly read-only-by-default diagnostic tool across all four editions (`cinnamon`, `xfce`, `lite`, `lite-lxqt`):

```bash
nexus-recovery --diagnose
nexus-recovery --diagnose --json --redacted
nexus-recovery --guide
```

What `--diagnose` checks safely without modifying disks:
- Live session vs. installed system mode and active NEXUS edition (`/etc/nexus-os-release`).
- UEFI vs. Legacy BIOS firmware mode and Secure Boot state.
- Presence of signed UEFI bootloaders (`/boot/efi/EFI/BOOT/BOOTX64.EFI`, `/boot/efi/EFI/ubuntu/{shimx64.efi,grubx64.efi,grub.cfg}`, `/boot/efi/EFI/nexus/`).
- `/etc/fstab` and `/etc/crypttab` syntax and `UUID=` consistency against `blkid`.
- Failed systemd units (`systemctl --failed`) and installer log paths (`/var/log/nexus-install.log`, `/var/log/installer/syslog`).

---

## 2. Step 1: Safe Read-Only Data Backup (Before Any Repair)

1. Boot a **NEXUS OS live ISO / USB** (choose *"Try NEXUS OS"*).
2. Identify your drives and partitions without modifying anything:
   ```bash
   lsblk -f
   ```
3. Mount your root or home partition **read-only** first:
   ```bash
   sudo mkdir -p /mnt/backup-ro
   sudo mount -o ro /dev/sdXY /mnt/backup-ro
   ```
   If your root partition is **LUKS2 encrypted**:
   ```bash
   sudo cryptsetup luksOpen --readonly /dev/sdXY nexus_ro
   sudo mount -o ro /dev/mapper/nexus_ro /mnt/backup-ro
   ```
4. Copy personal directories (`/mnt/backup-ro/home/<user>/`) to an external USB drive before running any filesystem or bootloader repair.

---

## 3. Boot & UEFI GRUB Recovery

If an installed NEXUS OS system fails to boot or drops to a `grub>` prompt:

1. Boot the **NEXUS OS live ISO** in **UEFI mode** (confirm `ls /sys/firmware/efi` exists).
2. Identify the FAT32 EFI System Partition (`sdX1`, ~512 MiB) and root partition (`sdX2`, or `/dev/mapper/nexus_crypt` + separate `/boot` `sdX2` for LUKS2).
3. Mount the installed target and virtual filesystems:
   ```bash
   sudo mount /dev/sdX2 /mnt
   # If separate /boot (LUKS2 layout), mount it before /boot/efi:
   # sudo mount /dev/sdX2 /mnt/boot
   sudo mount /dev/sdX1 /mnt/boot/efi
   for d in dev dev/pts proc sys run; do sudo mount --bind "/$d" "/mnt/$d"; done
   ```
4. Reinstall UEFI GRUB and refresh the signed Secure Boot chain and menu:
   ```bash
   sudo chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=nexus --recheck
   sudo chroot /mnt update-grub
   ```
5. Verify `/mnt/boot/efi/EFI/ubuntu/grub.cfg` and `/mnt/boot/efi/EFI/BOOT/BOOTX64.EFI` exist (Mint/Ubuntu signed `grubx64.efi` reads `/EFI/ubuntu/grub.cfg`), then cleanly unmount (`sudo umount -R /mnt`) and reboot with the live USB removed.

---

## 4. Filesystem Checking Guidance (`fsck`)

- **Never run write-mode `fsck` / `e2fsck` on a mounted filesystem.**
- **First, inspect read-only (`-n`):**
  ```bash
  sudo nexus-recovery --fsck-dry-run --partition /dev/sdXY --confirm
  # Equivalent direct read-only command:
  sudo fsck -n /dev/sdXY
  ```
- **Only after backing up personal files and confirming the partition is unmounted**, run repair on the unmounted partition:
  ```bash
  sudo e2fsck -f -p /dev/sdXY    # ext4 root or /boot
  sudo dosfsck -v /dev/sdX1      # FAT32 EFI System Partition
  ```

---

## 5. LUKS2 Full-Disk Encryption Recovery

- NEXUS `nexus-disk-install --luks` configures:
  - Partition 1: 512 MiB FAT32 EFI System Partition (`/boot/efi`)
  - Partition 2: 1024 MiB ext4 unencrypted `/boot`
  - Partition 3: LUKS2 (`aes-xts-plain64`, 512-bit key, `sha256`, `argon2id` 64 MiB memory bound) unlocked via `/etc/crypttab` + `cryptsetup-initramfs`.
- **Inspect LUKS2 header & key slots safely (never exposes passphrases):**
  ```bash
  sudo cryptsetup luksDump /dev/sdX3
  ```
- **Back up your LUKS2 header offline right after install (recommended):**
  ```bash
  sudo cryptsetup luksHeaderBackup /dev/sdX3 --header-backup-file nexus-luks-header.img
  ```
- **Add a secondary recovery passphrase in an unused slot:**
  ```bash
  sudo cryptsetup luksAddKey /dev/sdX3
  ```
- **Rebuild encrypted initramfs from a live session if boot fails after a kernel update:**
  Unlock `/dev/sdX3` to `nexus_crypt`, mount `/`, `/boot`, `/boot/efi`, bind `/dev /proc /sys /run`, verify `/etc/cryptsetup-initramfs/conf-hook` contains `CRYPTSETUP=y`, and run:
## 6. Driver, Network, Desktop Environment, Low Storage & Recovery Mode

Use `nexus-recovery --guide <topic>` for quick terminal instructions or follow these safe steps:

- **Driver problems (`--guide drivers`)**: Boot with `nomodeset` from GRUB if display fails, inspect `dmesg | grep -Ei "drm|amdgpu|i915|nvidia|firmware"`, check `ubuntu-drivers devices`, and run `nexus-hw-inventory --markdown` for missing Wi-Fi/SOF firmware.
- **Network problems (`--guide network`)**: Check `rfkill list`, `nmcli general status`, and `resolvectl status`. Unblock Wi-Fi with `rfkill unblock wifi` and restart `NetworkManager` if needed.
- **Desktop environment failures (`--guide desktop`)**: Switch to TTY3 (`Ctrl+Alt+F3`), inspect `systemctl status lightdm` and `journalctl --user -p err -n 25`, and revert NEXUS per-user theming safely via `nexus-apply-xfce --revert` (or `nexus-apply-lite --revert` / `nexus-apply-lite-lxqt --revert`).
- **Low storage (`--guide storage`)**: Check `df -h / /boot /home` and `df -ih /`. Run `sudo apt-get clean`, preview `sudo apt-get autoremove --dry-run`, and trim logs safely with `sudo journalctl --vacuum-size=200M`.
- **Broken updates (`--guide packages`)**: Run `sudo dpkg --configure -a && sudo apt-get update && sudo apt-get install -f`.
- **GRUB Recovery Mode (`--guide recovery`)**: Hold Shift (BIOS) or tap Esc (UEFI) at boot -> **Advanced options for NEXUS OS** -> **(recovery mode)**. Always run `fsck -n` read-only first and remount `/` read-write (`mount -o remount,rw /`) only after confirming backups.

---

## 6. Package & Interrupted Update Repair

If an update or package installation was interrupted:

```bash
sudo dpkg --configure -a
sudo apt-get update
sudo apt-get install -f
sudo apt-get check
```

NEXUS OS preserves upstream Linux Mint / Ubuntu signed APT repositories (`Acquire::AllowInsecureRepositories` is never enabled).

---

## 7. Dual-Boot Preservation Notes

- **Never format a shared EFI System Partition** used by Windows or another Linux distribution.
- In CLI mode (`nexus-disk-install`), always pass `--keep-efi --efi-part <ESP> --root-part <TARGET_PART>`.
- In Ubiquity GUI mode (*"Something else"*), select the existing ESP as `/boot/efi` with **Format unchecked** and assign your separate Linux partition as `/`.
- **Unsupported / Out-of-Scope Configurations:**
  - Legacy BIOS / MBR installations via `nexus-disk-install` (UEFI GPT is required).
  - Intel RST / RAID-on SATA controllers (switch storage mode only after backing up and understanding host OS boot impact — never alter firmware settings on primary machines casually).
  - BitLocker-encrypted Windows partitions without recovery keys backed up first.
  - Physical dual-boot testing on personal hardware remains **`NOT TESTED`** (only disposable QEMU simulated dual-boot `--keep-efi` has been tested).

---

## 8. Interrupted-Install Recovery

If `nexus-disk-install` exits early or is interrupted:
- It automatically runs `cleanup()` on `EXIT` to unmount `/mnt/nexus-install-target` and close `/dev/mapper/nexus_crypt`.
- On a subsequent run inside the same live session, it detects and detaches stale mounts/mappers before continuing.
- Inspect `/var/log/nexus-install.log` and `lsblk -f` before retrying, and verify you are targeting the intended disposable or dedicated disk.
