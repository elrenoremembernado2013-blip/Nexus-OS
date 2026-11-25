# NEXUS OS Installation Architecture (Phase 8)

## Installer Technology Choice

NEXUS OS uses **Linux Mint's Ubiquity installer** (`ubiquity` + `ubiquity-frontend-gtk` + `partman` + `cryptsetup` + `grub-efi`/`grub-pc`), built into the Linux Mint 22.3 (Ubuntu 24.04 Noble) live ISO remastered by `linux/build/build-nexus-iso.sh`.

We explicitly **do not** replace `partman` or `grub-install` with a custom low-level disk formatter. Instead:
- `linux/installer/nexus-install-preflight.sh` performs read-only hardware, firmware (`UEFI` vs `BIOS/Legacy`), RAM, block disk (`lsblk -J`), GPU, network, audio, battery, display, and `ubiquity` availability checks.
- `linux/installer/nexus-installer-launcher.sh` runs preflight, writes non-secret launch timestamps to `~/.local/state/nexus-os/installer.log`, and launches `pkexec ubiquity gtk_ui` only inside a live session.
- `apps/welcome.js` provides the **NEXUS Welcome & Installer Guide** UI for both the live pre-install orientation and the 7-step First-Boot Experience (`nexus-firstboot.sh`).

## Supported Installation & Security Options (via Ubiquity)

1. **Install alongside another operating system** (when free space or resizable partitions exist and are supported by `partman`).
2. **Erase disk and install NEXUS OS** (explicit destructive confirmation dialog inside Ubiquity; never silently formatted).
3. **Manual partitioning ("Something else")** for custom `/`, `/boot/efi`, `swap`, or `/home` layouts.
4. **Full-Disk Encryption (LUKS + LVM)** via Ubiquity's `partman-auto-crypto` option. Passphrases are entered interactively in Ubiquity and never logged or stored in plaintext. Hardware/firmware without EFI or with Secure Boot restrictions should review `docs/RECOVERY_AND_BOOT.md`.
5. **User Account Creation**: username, display name, password, hostname, automatic login toggle, and `sudo` admin group membership via Ubiquity's standard `user-setup`.

## Minimum & Recommended Hardware

- **Architecture:** `x86_64` (`amd64`)
- **RAM:** `2 GiB` minimum (`4 GiB` recommended)
- **Storage:** `20 GiB` minimum (`32 GiB` recommended)
- **Firmware:** 64-bit UEFI (recommended; Secure Boot compatible with Ubuntu/Mint signed shim) or Legacy BIOS

## Verification Status

- **Verified locally & in CI:** `nexus-install-preflight.sh`, `nexus-installer-launcher.sh --check` / `--dry-run`, `build-nexus-iso.sh --dry-run`, `GET /api/installer/preflight` on `nexus-system-bridge.py`, and `scripts/check-installer.js`.
- **Not yet tested (requires external ISO build + QEMU/VM run):** booting the remastered ISO live environment, running Ubiquity partitioning on a disposable virtual disk, installing GRUB, and completing live first-boot. NEXUS OS must **not** be claimed as installable until that end-to-end VM installation passes.
