# NEXUS Linux foundation setup (Milestone 1)

This milestone establishes verified Linux Mint 22.3 Xfce installation media and a local QEMU/UEFI workflow. **It does not build a NEXUS operating-system image.** Installing the ISO in a VM produces a stock Mint guest, not a NEXUS-branded or customized OS. No Chromebook boot result is claimed.

## Target and layout

- Base candidate: Linux Mint 22.3 Xfce, built on Ubuntu 24.04 LTS (Noble).
- Physical reference device: HP Chromebook x360 14b-cb0 (MADOO), Intel Celeron N4500, 4 GB RAM, 32 GB eMMC.
- Mint lists 4 GB RAM as recommended and 20 GB disk as the minimum. The target has limited storage headroom; measure free space after installation and updates.
- Ubuntu 26.04 Desktop lists 6 GB RAM and 25 GB free storage for a comfortable experience. This is why Mint Xfce is the current desktop choice. The exact complete NEXUS memory and storage use still needs testing.
- Guest direction: X11, Xfce, Xfwm4, GRUB, systemd; UEFI firmware via OVMF in QEMU.
- `scripts/`: media verification, QEMU launch, and static checks.
- `linux/config/`: declarative design defaults (`NEXUS_TARGET_RAM_MB` is read as the fallback default by `scripts/launch-qemu.sh`) and the curated Linux Mint package manifest (`mint-packages.list`).
- `linux/xfce/` and `linux/mint/`: user-session GTK3/Xfce theme & low-resource defaults (`apply-nexus-xfce.sh`), guest provisioning baseline (`provision-nexus-guest.sh`, dry-run checked locally; requires a booted Mint guest for live execution), per-user first-boot setup (`nexus-firstboot.sh`), a focused `xfce4-genmon-plugin` panel status helper (`nexus-panel-status.sh`), a read-only RAM/disk footprint reporter (`measure-footprint.sh`), and a read-only MADOO live-media qualification reporter (`madoo-qualify-report.sh`).
- `nexus-br2-external/`: retained separately for experimental Buildroot work; it is not the primary desktop.
- `build/`: local downloads, VM state, and disk images; ignored by Git.

## Host dependencies

On Ubuntu, Debian, or Linux Mint, install:

```sh
sudo apt update
sudo apt install bash coreutils curl gnupg qemu-system-x86 qemu-utils ovmf
```

The Mint downloader needs `curl`, `gpg`, and either `sha256sum` or macOS `shasum`. QEMU uses `qemu-img` and an OVMF UEFI firmware pair.

On macOS with Homebrew:

```sh
brew install qemu gnupg
```

Homebrew QEMU on Apple Silicon provides the Cocoa display backend, x86-64 EDK II firmware, and TCG emulation. x86-64 guest emulation can be slow. Node.js is available for future tooling but is not required by this foundation workflow.

For accelerated KVM on Linux, the host needs a working `/dev/kvm` and user permissions. The launch script defaults to TCG for portability. It defaults to Cocoa display on macOS and GTK elsewhere; set `NEXUS_QEMU_DISPLAY` to override the backend.

## Download and verify Linux Mint media

From the repository root:

```sh
bash scripts/download-linux-mint.sh
```

The script downloads the pinned `linuxmint-22.3-xfce-64bit.iso` and its `sha256sum.txt` and `sha256sum.txt.gpg` files from the Linux Mint stable 22.3 mirror into ignored `build/downloads/`. It imports the Linux Mint ISO signing key into a temporary GnuPG home, checks the full published fingerprint `27DEB15644C6B3CF3BD7D291300F846BA25BAE09`, verifies the signed manifest, and compares the ISO digest with the matching manifest entry. The key fingerprint and verification steps follow the [Linux Mint ISO verification guide](https://linuxmint.com/verify.php).

Optional output directory:

```sh
NEXUS_DOWNLOAD_DIR="$HOME/nexus-media" bash scripts/download-linux-mint.sh
```

The Ubuntu media script remains available for an explicit Ubuntu alternative, but it is not the default foundation path.

## Create and launch the QEMU VM

```sh
bash scripts/launch-qemu.sh --profile minimum --edition lite-lxqt
# or recommended profile (4 vCPUs, 8192 MiB RAM, 50G disposable disk):
bash scripts/launch-qemu.sh --profile recommended --edition xfce
# after installation, boot directly from the installed disk without ISO media:
bash scripts/launch-qemu.sh --profile minimum --edition lite-lxqt --disk-only
```

To inspect any profile without creating a disk, locating firmware, or starting a VM:

```sh
bash scripts/launch-qemu.sh --dry-run
bash scripts/launch-qemu.sh --profile minimum --edition lite-lxqt --dry-run
bash scripts/launch-qemu.sh --profile recommended --edition xfce --dry-run
```

The default 4 GiB guest RAM and 40 GiB virtual disk are for a VM on the development host. They are not a profile for running QEMU on the Chromebook's 4 GB/32 GB hardware. A sparse 40 GiB virtual disk also does not mean the Chromebook has 40 GiB available.

On macOS, the QEMU launch script uses Homebrew's x86-64 UEFI firmware and Cocoa display backend. It runs the x86-64 VM under TCG on Apple Silicon. A successful Mac VM test checks only the generic installer/QEMU workflow; it does not validate MADOO firmware, Chromebook hardware drivers, NEXUS bootability, or performance on the physical device.

The script creates a qcow2 virtual disk if needed, keeps writable UEFI variables under ignored `build/qemu/`, and attaches the Mint installer ISO when present. Complete the installer interactively in the VM. The script does not automate installation or configure NEXUS. When the ISO remains present, the VM boots the installer first; move or rename it to boot from an installed guest.

Configure VM resources without editing scripts:

```sh
NEXUS_RAM_MB=4096 NEXUS_CPUS=2 NEXUS_DISK_SIZE=32G \
NEXUS_QEMU_ACCEL=tcg bash scripts/launch-qemu.sh
```

Change the VM disk capacity only when creating a new disk; changing the variable does not resize an existing one. For headless hosts, inspect `qemu-system-x86_64 -display help` and set `NEXUS_QEMU_DISPLAY` to a supported backend.

## Checks

```sh
bash scripts/check-foundation.sh
```

This checks shell syntax, required tracked files, Git ignore entries, key media-verification and QEMU wiring, and the browser prototype checks. It is not a NEXUS image build, installer test, Chromebook hardware test, benchmark, or QEMU boot acceptance result. Record actual media verification and VM results separately.

## Reproducibility and security boundaries

- The Mint media version and edition are pinned; the ISO digest comes from its signed manifest. No checksum is guessed or embedded.
- This is repeatable media acquisition and a local VM procedure, not a reproducible customized NEXUS image build.
- Generated downloads, VM disks, firmware variables, and guest state live under ignored `build/`. Never commit credentials, private keys, personal data, or guest state.
- OVMF firmware comes from the host distribution or Homebrew QEMU and is not checked into this repository.
- The native session, partitioning, device drivers, suspend/resume, security configuration, and Chromebook firmware changes remain planned work. `linux/config/nexus-system.conf` is declarative only.
- Buildroot remains experimental; this milestone does not add a Buildroot defconfig, kernel config, root filesystem, package set, or bootable image.
