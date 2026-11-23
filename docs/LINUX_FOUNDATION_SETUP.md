# NEXUS Linux foundation setup (Milestone 1)

This milestone establishes verified Ubuntu installation media and a local QEMU/UEFI workflow. **It does not build a NEXUS operating-system image.** The ISO is the official Ubuntu 26.04.1 LTS Server installer; installing it in the VM produces a stock Ubuntu guest, not a NEXUS-branded/customized OS. No QEMU boot result is claimed here.

## Target and layout

- Target: x86_64; Ubuntu 26.04.1 LTS Server minimal installation as the initial base.
- Physical reference device: HP Chromebook x360 14b-cb0 (MADOO), Celeron N4500, 4 GB RAM, 32 GB eMMC. Its storage and memory are constraints for the future native image; no NEXUS boot on this device is claimed.
- Guest direction: Wayland, GRUB, systemd; UEFI firmware via OVMF in QEMU.
- `scripts/`: ISO verification, QEMU launch, static checks.
- `linux/config/`: reviewed design defaults; not yet consumed by an image build.
- `nexus-br2-external/`: retained separately for experimental Buildroot work; it is not the primary Ubuntu foundation.
- `build/`: local downloads, VM state, and disk images; ignored by Git.

## Host dependencies

On an Ubuntu/Debian-like x86_64 development host, install:

```sh
sudo apt update
sudo apt install bash coreutils curl gpgv ubuntu-keyring qemu-system-x86 qemu-utils ovmf
```

Roles: `curl` downloads release files over HTTPS; `gpgv` validates the signed checksum manifest; `ubuntu-keyring` supplies the archive trust anchors; `coreutils` supplies `sha256sum`; `qemu-system-x86` runs the guest; `qemu-utils` supplies `qemu-img`; `ovmf` supplies UEFI firmware. `bash` runs scripts. The automated checks use Bash and standard utilities. On macOS, install Homebrew, then run `brew install qemu node`; the project launcher uses QEMU’s Cocoa display backend and the x86-64 EDK II firmware shipped with Homebrew QEMU. Node.js is available for future tooling and is not required by the current foundation scripts. Optional `shellcheck` may be used for additional linting but is not required by the supplied check script.

For accelerated KVM, a Linux host also needs a working `/dev/kvm` and user permissions. TCG is the script default and requires no KVM access, but may be slow; on Apple Silicon, x86-64 guests use TCG emulation. The launcher defaults to Cocoa display on macOS and GTK elsewhere. On macOS, Homebrew QEMU provides the x86-64 UEFI code and variables files. If firmware is installed in a nonstandard location, set both `OVMF_CODE` and `OVMF_VARS` to a matching pair.

## Download and verify official media

From the repository root:

```sh
bash scripts/download-ubuntu.sh
```

By default this downloads `ubuntu-26.04.1-live-server-amd64.iso`, `SHA256SUMS`, and `SHA256SUMS.gpg` from `https://releases.ubuntu.com/26.04/` into ignored `build/downloads/`. The script first verifies the manifest signature with the installed Ubuntu archive keyring (`gpgv`), then compares the ISO digest with the matching entry in that authenticated manifest. It deliberately contains no hardcoded ISO checksum. If the named release artifacts or directory are unavailable, do not substitute a guessed URL or digest; check Ubuntu's official release index and update the version/path only after confirming the published signed files.

Optional overrides:

```sh
NEXUS_DOWNLOAD_DIR="$HOME/nexus-media" \
UBUNTU_ARCHIVE_KEYRING=/usr/share/keyrings/ubuntu-archive-keyring.gpg \
  bash scripts/download-ubuntu.sh
```

The script also supports `--output-dir`, `--base-url` (HTTPS only), `--iso-name`, and `--keyring`. Use official Ubuntu release infrastructure for actual trusted media.

## Create and launch the QEMU VM

```sh
bash scripts/launch-qemu.sh
```

To inspect a VM profile on a host that does not yet have QEMU or OVMF installed:

```sh
bash scripts/launch-qemu.sh --dry-run
```

The dry run validates RAM, CPU, disk, accelerator and boot-media values without
creating a disk, locating firmware or starting a VM.

The current 4 GiB RAM and 40 GiB virtual disk defaults describe a VM on the development host (for example, the Mac used to prepare this project). They are not Chromebook requirements or a profile for running QEMU on the 4 GB reference device. The Mac-side VM checks the generic Ubuntu/QEMU workflow only; it does not validate Chromebook firmware, drivers, performance, or NEXUS bootability.

The script creates an ignored qcow2 disk if needed, keeps writable OVMF variables under `build/qemu/`, and attaches the installer ISO when present. Complete the Ubuntu installer interactively; the script does not automate installation or configure the installed guest. On subsequent launches it boots from the disk if the ISO is not present (if the ISO remains, it boots the installer first).

Configure resources without editing scripts:

```sh
NEXUS_RAM_MB=6144 NEXUS_CPUS=4 NEXUS_DISK_SIZE=48G \
NEXUS_QEMU_ACCEL=kvm bash scripts/launch-qemu.sh
```

Supported disk capacity syntax is a positive integer followed by `M`, `G`, or `T`. The disk capacity is applied only when the virtual disk is first created; changing the variable does not resize an existing disk. To use a non-default media/disk location set `NEXUS_ISO_PATH` and/or `NEXUS_DISK_PATH`. The launch script is interactive and should not be run in unattended CI without a display configuration. On macOS, override the window backend with `NEXUS_QEMU_DISPLAY=BACKEND` if needed (for example, `cocoa`); on headless hosts, consult `qemu-system-x86_64 -display help` before selecting a backend.

## Checks

```sh
bash scripts/check-foundation.sh
```

This checks shell syntax, required tracked files, Git ignore entries, and key safety/wiring patterns. It is not a full shell linter, image build, installer test, checksum verification run, or QEMU boot test. For a syntax-only check use `bash -n scripts/download-ubuntu.sh scripts/launch-qemu.sh scripts/check-foundation.sh` (or run the supplied checker). Record actual download verification and QEMU results separately when performed.

## Reproducibility and security boundaries

- Source media is version-named; its checksum is taken from the downloaded, signature-verified Ubuntu manifest. No digest is asserted in Git.
- Reproducibility here means a repeatable acquisition and local VM procedure, not a reproducible customized OS build. Ubuntu media and packages can have lifecycle/mirror changes; record the exact ISO digest and host/tool versions in a future tested release record.
- Generated downloads, VM disks, firmware variables and state live under ignored `build/`. Never commit guest state, private keys, credentials, or `.env` files.
- OVMF firmware files come from the host distribution package and are not checked into this repository.
- The guest install, partitioning, updates, Wayland session, compositor, GPU/audio setup, and security configuration remain manual/planned work. `linux/config/nexus-system.conf` is currently declarative only.
- Buildroot remains an experimental external tree; this milestone does not add a Buildroot defconfig, kernel config, root filesystem, package set, or bootable Buildroot image.
