# NEXUS OS Release Engineering & Verification Gates (Phase 9)

## Release Stages

1. **`development`**: Automated CI checks pass, ISO build script succeeds locally, or changes are staged on feature branches. Not VM-verified.
2. **`testing`**: ISO built with `sudo bash linux/build/build-nexus-iso.sh`, verified with `bash linux/build/verify-nexus-iso.sh` (size, `.sha256`, `build-info.json`, `xorriso` live/boot tree), ready for QEMU/OVMF and hardware testers.
3. **`stable`**: **Strictly gated** (`prepare-release.sh --stage stable --vm-verified`). Only promoted after live VM boot, Ubiquity partitioning on a disposable disk, GRUB bootloader installation, reboot, network/audio, and first-boot checks pass.

## Preparing Installation Media (After Verification)

Verify the SHA-256 checksum before flashing any USB drive:

```sh
cd build/iso/out
sha256sum -c nexus-os-22.3-xfce-amd64.iso.sha256
```

Write to a USB drive using Linux Mint's **USB Image Writer** (`mintstick -m iso`) or carefully with `dd` after confirming the target block device with `lsblk`:

```sh
sudo dd if=nexus-os-22.3-xfce-amd64.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

## Supported Hardware & Reporting Issues

- **Target architecture:** `x86_64` (`amd64`), minimum `2 GiB` RAM (`4 GiB` recommended), `20 GiB` storage (`32 GiB` recommended), UEFI or Legacy BIOS.
- **Issue reporting:** Include `build-info.json`, `nexus-install-preflight.sh` JSON output, `/var/log/installer/syslog` (for Ubiquity failures), and QEMU flags if tested in a VM (`https://github.com/elrenoremembernado2013-blip/Nexus-OS/issues`).
