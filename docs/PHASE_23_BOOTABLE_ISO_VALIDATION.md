# Phase 23: Bootable ISO, Installation & Real-World Validation

This document specifies the reproducible distribution architecture, ISO build pipeline, QEMU validation procedures, safety boundaries, and strictly audited verification status for **NEXUS OS** across all four editions (**Standard Cinnamon**, **XFCE**, **Lite LXQt**, and **Lite Openbox**).

All results strictly separate **PASS**, **FAIL**, **BLOCKED**, **NOT TESTED**, and **ESTIMATED** statuses. **128 MB RAM is NOT claimed or supported** (512 MiB is the minimum experimental Lite floor with zstd zram; 1024 MiB is recommended for Lite, 2048 MiB minimum / 4096 MiB recommended for XFCE and Standard Cinnamon).

---

## 1. Real Operating System Foundation

NEXUS OS builds a real bootable `x86_64` Linux distribution—not a web-page wrapper—by remastering a GPG- and SHA-256-verified **Linux Mint 22.3 ("Zena", based on Ubuntu 24.04 LTS "Noble Numbat")** base ISO:

- **Base OS & Signed Repositories:**
  - `NEXUS_BASE_DISTRO=linuxmint`
  - `NEXUS_BASE_VERSION=22.3`
  - `NEXUS_BASE_UBUNTU_CODENAME=noble` (Ubuntu 24.04 LTS signed APT + Linux Mint 22.3 signed APT)
  - Target architecture: `x86_64` (`amd64`)
  - Init & display stack: `systemd` + X11 (`LightDM` display manager) + `GRUB` (UEFI + Legacy BIOS)
- **NEXUS Desktop & Native Runtime:**
  - Provisioned inside the squashfs rootfs via edition-specific provisioners (`linux/mint/provision-nexus-guest.sh`, `linux/lite/provision-nexus-lite.sh`, `linux/lite/scripts/provision-nexus-lite-lxqt.sh`).
  - Installs `nexus-system-bridge.service` (loopback `127.0.0.1` + `0600` ephemeral `X-Nexus-Token` runtime authentication), native CLI helpers (`nexus-store-cli`, `nexus-security-cli`, `nexus-gaming-cli`, `nexus-performance-cli`, `nexus-compat-cli`, `nexus-wallpaper`, `nexus-control-centre`, `nexus-hw-inventory`, `nexus-hw-diagnostics`, `nexus-install-preflight`, `nexus-disk-install`, `nexus-recovery`), 15 `.desktop` launchers (`linux/branding/applications/*.desktop`), and offline desktop shell assets at `/usr/local/share/nexus-os/ui/`.
  - Strictly excludes test harnesses/agents (`nexus-test-agent`, `nexus-guest-test`, `casper-test-hook`, `99nexus_test_harness`) from released ISOs, verified by `linux/build/verify-nexus-iso.sh`.

---

## 2. Four Editions

| Edition | Config | Desktop & Panel | Default File Manager & Terminal | Heavyweight Apps Policy | Target RAM |
|---|---|---|---|---|---|
| **Standard (Cinnamon)** | `linux/config/nexus-standard-cinnamon.conf` | Cinnamon (`muffin`) | `nemo`, `gnome-terminal` | Full Mint desktop; Steam/Wine/Waydroid optional on demand | 2048 MiB min / 4096 MiB rec |
| **XFCE** | `linux/config/nexus-system.conf` | XFCE (`xfwm4`) | `thunar`, `xfce4-terminal` | Mint XFCE desktop; Steam/Wine/Waydroid optional on demand | 2048 MiB min / 4096 MiB rec |
| **Lite LXQt** | `linux/lite/nexus-lite-lxqt.conf` | LXQt + Openbox (`lxqt-panel`, no compositor) | `pcmanfm-qt`, `qterminal` | Zero preinstalled Cinnamon/Steam/Wine/Waydroid/browser bloat; zstd zram 50% | 512 MiB exp / 1024 MiB rec |
| **Lite Openbox** | `linux/lite/nexus-lite.conf` | Openbox + `tint2` (no compositor) | `pcmanfm`, `lxterminal` | Zero preinstalled Cinnamon/Steam/Wine/Waydroid/browser bloat; zstd zram 50% | 512 MiB exp / 1024 MiB rec |

---

## 3. Host Requirements & Reproducible ISO Build

### 3.1 Host Build Prerequisites
Building an ISO locally requires an `x86_64` Linux host with root privileges (`sudo`), at least **12 GiB free disk space**, internet access to official Linux Mint mirrors, and:

```sh
sudo apt-get update && sudo apt-get install -y \
  bash coreutils curl gnupg xorriso squashfs-tools \
  qemu-system-x86 qemu-utils ovmf shellcheck cpio gzip \
  initramfs-tools-core zstd xz-utils desktop-file-utils nodejs
```

Verify readiness (exits non-zero cleanly when tools or base ISO are absent; never emits placeholder ISOs):

```sh
bash linux/build/check-build-prereqs.sh --edition lite-lxqt --strict
```

### 3.2 Downloading & Building ISOs

1. Download and GPG + SHA-256 verify the Linux Mint 22.3 base ISO:
   ```sh
   bash scripts/download-linux-mint.sh --edition xfce      # for xfce, lite, lite-lxqt
   bash scripts/download-linux-mint.sh --edition cinnamon  # for cinnamon
   ```
2. Build any of the four editions:
   ```sh
   sudo bash linux/build/build-nexus-iso.sh --edition cinnamon
   sudo bash linux/build/build-nexus-iso.sh --edition xfce
   sudo bash linux/lite/scripts/build-nexus-lite-lxqt-iso.sh
   sudo bash linux/lite/build-nexus-lite-iso.sh
   ```
   Each build outputs:
   - `build/iso/out/nexus-os-22.3-<edition>-amd64.iso`
   - `build/iso/out/nexus-os-22.3-<edition>-amd64.iso.sha256`
   - `build/iso/out/nexus-os-22.3-<edition>-amd64.iso.build-info.json` (recording `source_commit`, `source_branch`, `source_dirty`, `base_distro`, `base_version`, `ubuntu_codename`, `package_repositories`, `build_environment`, and checksums)

3. Verify integrity, checksum, BIOS + UEFI boot catalog, and production/test separation:
   ```sh
   bash linux/build/verify-nexus-iso.sh --edition lite-lxqt
   (cd build/iso/out && sha256sum -c nexus-os-22.3-lite-lxqt-amd64.iso.sha256)
   ```

---

## 4. Booting & Validating in QEMU (UEFI + Legacy BIOS + Disposable Disk)

`linux/test/run-qemu-validation.sh` strictly creates disposable `qcow2` images under `build/qemu-test/` and **never touches physical host disks**.

```sh
bash linux/test/run-qemu-validation.sh \
  --edition lite-lxqt \
  --ram-matrix "1024 2048" \
  --install-ram-matrix "1024" \
  --graphical \
  --install-test \
  --bios-check
```

Stages executed:
1. **UEFI (`OVMF`) ISO boot check** + screendump (`uefi_boot.png`).
2. **Legacy BIOS (`SeaBIOS`) ISO boot check** (`--bios-check`) + screendump (`bios_boot.png`).
3. **Graphical live ISO validation** via `virtio-serial` + `QMP` (`nexus-guest-test.py`): LightDM login, WM/panel readiness, app launches, NetworkManager connectivity, `zram` pressure check, and loopback `nexus-system-bridge.service` API checks.
4. **Disposable-disk install** via `nexus-disk-install.sh` (requires `--yes-erase-disk`, GPT ESP + ext4 or LUKS2 root, UUID `/etc/fstab`, initramfs, UEFI GRUB).
5. **3-reboot installed-system verification (ISO detached)**: Boot 1 -> Warm Reboot -> Boot 2 -> Poweroff -> Cold Boot 3, confirming `/dev/vda` root, absence of live ISO (`/rofs`), `persistence_verified` (`persist-marker.json`, `personalisation.json`, `Documents/nexus-reboot-check.txt`), and zero failed systemd units.

Additional safety and compatibility test suites:
- Manual partitioning, interrupted-install recovery, LUKS2 wrong-passphrase rejection, and browser RAM benchmarks: `bash linux/test/run-phase125-tests.sh`
- Dual-boot NTFS/ESP preservation and OVMF Secure Boot enrolled boot chain: `bash linux/test/run-phase130-tests.sh`

---

## 5. Security, Native Services & Application Boundaries

### 5.1 Real Native Services vs Prototype / Browser Previews
Inside a booted NEXUS OS Linux guest, `apps/native-services.js` connects to `nexus-system-bridge.py` on `http://127.0.0.1:<ephemeral-port>` using the `0600`-protected token in `$XDG_RUNTIME_DIR/nexus-os/system-bridge.json`:

- **Real native Linux integrations (when bridge active):**
  - **Terminal:** Real GNU Bash PTY session (`/api/terminal/*`)
  - **Performance Centre / System Monitor:** Real `/proc` + `/sys` CPU, RAM, swap/zram, disk, boot diagnostics, low-resource mode, confirmed-only cache cleanup (`/api/telemetry`, `/api/performance/*`)
  - **File Manager:** Real `$HOME`-jailed file browsing, preview, mkdir, touch, rename, delete (`/api/files/*`, `403` outside `$HOME` or on `~/.ssh`/`~/.gnupg`)
  - **Control Centre & Settings:** Real DND/notifications state, theme/wallpaper persistence (`nexus-wallpaper-cli`, `nexus-control-centre-cli`), native desktop tool launching (`/api/tools/launch`)
  - **NEXUS Store:** Real `apt` / `flatpak` / `mintupdate` sources, search, installed list, and `pkexec`-confirmed install/remove (`nexus-store-cli.sh`)
  - **Security & Privacy:** Real UFW status, PolicyKit `pkexec` escalation, Flatpak permission inspection/revocation, honest `mokutil`/`efivars` Secure Boot detection (`nexus-security-cli.sh`)
  - **Gaming Hub:** Real GPU/Vulkan/Steam/GameMode capability detection (`nexus-gaming-cli.sh`)
  - **Hardware Compatibility Centre:** Real privacy-redacted hardware inventory and diagnostics (`nexus-hw-inventory.sh`, `nexus-hw-diagnostics.sh`)
  - **NEXUS Compatibility Centre:** Real `$HOME`-jailed file classifier (`PE`/`ELF`/`AppImage`/`APK`) and explicit-confirmation Wine/Waydroid/Flatpak/AppImage manager (`nexus-compat-cli.sh`)
  - **Quantum:** Real local JSON notes persistence (`/api/quantum/notes`) + local learning labs
- **Browser-prototype-only / simulated when opened outside Linux guest without bridge:**
  - Brightness slider overlay in Control Centre (desktop preview only; physical backlight requires hardware sysfs)
  - Quantum Studio offline curriculum, single-qubit simulator, Calculator, Calendar (self-contained local client logic; not a remote AI service)
  - Browser File System Access fallback when running over HTTP without `nexus-system-bridge`

---

## 6. Observed Verification Status (Strictly Audited)

### 6.1 Local Sandbox Environment (Observed on this Host)
- **PASS:** `npm run check:prototype`, `npm test` (`scripts/check-foundation.sh`), `scripts/check-phase23-validation.js`, `scripts/check-native-launchers.sh`, `linux/test/test-installer-safety.sh`, `linux/security/nexus-security-audit.sh --repo-only --repo . --strict`, Python `py_compile` & bridge tests (`check-linux-bridge.py`, `check-native-services-reliability.py`), ShellCheck lint (`shellcheck-py`).
- **BLOCKED (Local Sandbox Only):** Building real ISOs (`build-nexus-iso.sh`) and booting QEMU VMs (`run-qemu-validation.sh`) on this container because `qemu-system-x86_64`, `xorriso`, `mksquashfs`, `unsquashfs`, `ovmf`, `/dev/kvm`, and external Mint mirrors are absent locally. Real ISO builds and QEMU execution run in GitHub Actions (`iso-and-qemu-validation.yml`).

### 6.2 GitHub Actions Real ISO + QEMU CI Evidence (Run `46087428882`, Linux Mint 22.3 / Ubuntu 24.04 Noble)
- **PASS (ISO Build & SHA-256 Verification):**
  - `nexus-os-22.3-cinnamon-amd64.iso` (`3,089,281,024` bytes, `sha256:72d1f8c79bf4a63cf54958241cbd91baace52558ccc78a84df5085ae3c12d82d`)
  - `nexus-os-22.3-xfce-amd64.iso` (`3,030,503,424` bytes, `sha256:ebf931657b4a0ee3f6c5b9c7e267411bbf6f4f22806952d0d5bad4390b1ac17b`)
  - `nexus-os-22.3-lite-lxqt-amd64.iso` (`2,874,503,168` bytes, `sha256:9acf4683bde356e0ab7a4255fead084ff4e973cc96311e49c543ea901bfead80` in `phase130`)
  - `nexus-os-22.3-lite-amd64.iso` (Openbox Lite ISO built and verified in `lite-openbox-compare`)
- **PASS (QEMU UEFI Live + Install + 3-Reboot Matrix in `46087428882`):**
  - **Standard Cinnamon (4096 MiB):** UEFI live `3/3`, install `2/2` (`1802.3s`), installed boots `3/3` (`/dev/vda`, no ISO, `persist=true`, `0` failed units, `0` journal errors; `969 MiB` live idle).
  - **XFCE (4096 MiB):** UEFI live `3/3`, install `2/2` (`1204.4s`), installed boots `3/3` (`persist=true`, `0` failed units, `0` journal errors; `793 MiB` live idle).
  - **Lite Openbox (512–4096 MiB):** Live `3/3` at `512 MiB` (`234 MiB` idle, zstd zram `4.34x`, `0` OOM); `1024 MiB` live `3/3`, install `1/1` (`858.6s`), installed boots `3/3` (`persist=true`, `459 MiB` live idle / `492 MiB` installed idle).
  - **Lite LXQt (512–4096 MiB):** `512 MiB` (`268 MiB` idle, install `2/2`, boots `3/3`), `768 MiB` (`402 MiB` idle, install `1/1`, boots `3/3`), `1024 MiB` (`544 MiB` idle, install `1/1`, boots `3/3`, `persist=true`), `2048 MiB` (`571 MiB` idle, install `1/1`, installed boots `2/3`—one of the 3 installed-boot cycles did not report complete in that run).
- **PASS (Phase 12.5 & 13.0 QEMU Qualification on Lite LXQt in `46087428882`):**
  - Manual 3-partition GPT install preserving `/dev/vda3`, interrupted-install recovery & unconfirmed guard refusal, LUKS2 encrypted install + wrong-passphrase rejection + 2-boot unlock & persistence, dual-boot NTFS/EFI preservation, and OVMF Secure Boot enrolled chain (`secure_boot_state=enabled`, `shimx64.efi`, `grubx64.efi`, signed kernel).
- **NOT TESTED (Pending New Phase 23 CI Run & Physical Hardware):**
  - **Legacy BIOS (`SeaBIOS`) boot check** (`--bios-check` added in Phase 23) and **expanded Phase 23 in-guest bridge checks** (`files_jailed_ok`, `compat_ok`, `perf_ok`, `hw_ok`, `quantum_ok`, `control_centre_ok`, `ui_bundle_present`, `personalisation_ok`) are queued for the new Phase 23 CI workflow run upon push.
  - **Physical Bare-Metal Hardware** (real Intel/AMD/NVIDIA GPU acceleration, Wi-Fi, Bluetooth, onboard audio codecs, touchpad gestures, S3 suspend/resume, thermal/battery behaviour): **NOT TESTED** in QEMU (`bochs-drm` + `llvmpipe` software rendering, virtual `virtio` storage/NIC).

---

## 7. Known Hardware Limitations & Remaining Work Before Public Beta

1. **Physical Hardware Qualification Still Required:** QEMU validates virtual `virtio_blk`, `virtio-net-pci`, and `bochs-drm`/`llvmpipe` only. Bare-metal Wi-Fi firmware, Bluetooth, audio codecs, GPU acceleration, touchpad, and suspend/resume must be validated on target hardware (`docs/HARDWARE_TESTING_GUIDE.md`, `docs/MADOO_CHROMEBOOK_QUALIFICATION.md`).
2. **Lite LXQt 2048 MiB Installed-Boot Stability:** `2/3` installed boots completed in `46087428882` at `2048 MiB`; the Phase 23 CI run should confirm consistent `3/3` stability.
3. **Not Yet Publicly Released:** NEXUS OS remains in alpha/pre-beta engineering validation. Do not publish ISOs as production-ready releases until Phase 23 CI (including BIOS+UEFI and expanded in-guest checks) and initial bare-metal hardware qualification complete cleanly.
