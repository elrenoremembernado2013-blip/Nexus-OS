# NEXUS OS Recovery, Logs & Boot Troubleshooting

## Installer & System Logs

- **Live launcher log:** `~/.local/state/nexus-os/installer.log`
- **Ubiquity installation logs (inside live/installed system):**
  - `/var/log/installer/syslog`
  - `/var/log/installer/partman`
  - `/var/log/installer/debug`
- **First-boot marker:** `~/.config/nexus-os/firstboot-done`

## Safe Failure Handling

- If Ubiquity aborts before writing partitions, target disks remain untouched.
- If installation fails mid-copy, inspect `/var/log/installer/syslog` and `/var/log/installer/partman` from the live environment before retrying on a clean partition layout. Never run destructive `dd` or `mkfs` commands blindly against personal disks.

## Full-Disk Encryption (LUKS) Recovery Guidance

- Write down and store your LUKS passphrase safely offline. If the LUKS passphrase is forgotten and no secondary key slot was added, encrypted data **cannot** be recovered.
- To inspect encrypted volumes from a live USB without modifying them: `sudo lsblk -f` and `sudo cryptsetup luksDump /dev/<partition>`.

## Boot Troubleshooting (UEFI & GRUB)

1. Boot the NEXUS OS / Linux Mint live USB or QEMU OVMF environment (`scripts/launch-qemu.sh`).
2. Verify EFI System Partition (`vfat` FAT32, `/boot/efi`) and root partition UUIDs with `sudo lsblk -f` and `efibootmgr -v`.
3. Use Linux Mint's built-in **Boot Repair** (`boot-repair` in the live Mint session) or chroot + `grub-install` + `update-grub` to restore the signed Ubuntu/Mint shim and GRUB menu.
