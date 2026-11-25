# NEXUS Lite — Ultra-Low-RAM Edition (Phase 11 & Phase 12 Validation Guide)

## Why NEXUS Lite Exists

Linux Mint Cinnamon is designed for `>= 2–4 GiB` RAM and cannot run comfortably inside `512 MB` of physical memory. **NEXUS Lite** keeps the exact same **Linux Mint 22.3 / Ubuntu 24.04 Noble (`x86_64`)** security, APT signature verification, UFW firewall, `NetworkManager`, and `unattended-upgrades` foundation while replacing Cinnamon/Xfce with **Openbox + `tint2` + `PCManFM` + `LXTerminal` (GNU Bash)** and **zero compositor/blur/Steam/default browser**.

## Three Operating Profiles & Edition Separation

| Edition / Profile | Desktop | Config & Manifest | Output ISO | Status |
|---|---|---|---|---|
| **NEXUS Lite — 512 MB Experimental** (`lite-512`) | Openbox + `tint2` (`2` workspaces) | `linux/lite/nexus-lite.conf`, `lite-packages.list` | `nexus-os-22.3-lite-amd64.iso` | **Experimental / Not tested in QEMU** |
| **NEXUS Lite — 1 GB** (`lite-1g`) | Openbox + `tint2` (`4` workspaces + `nm-applet`) | `linux/lite/nexus-lite.conf`, `lite-packages.list` | `nexus-os-22.3-lite-amd64.iso` | **Not tested in QEMU** |
| **NEXUS Standard (Cinnamon)** (`standard-2g`) | Cinnamon + Muffin | `linux/config/nexus-standard-cinnamon.conf`, `cinnamon-packages.list` | `nexus-os-22.3-cinnamon-amd64.iso` | **Development (Not tested in QEMU)** |
| **MADOO Xfce Baseline** (`xfce`) | Xfce 4.18 + Xfwm4 | `linux/config/nexus-system.conf`, `mint-packages.list` | `nexus-os-22.3-xfce-amd64.iso` | **Development (Not tested in QEMU)** |

See `docs/STANDARD_VS_LITE_EDITIONS.md` for why Cinnamon (Standard) and Xfce (MADOO baseline) are both preserved explicitly without overwriting each other.

## Phase 12 Evidence-Based RAM Compatibility Matrix

| RAM Level | Target Configuration | Classification | Notes & Verification Basis |
|---|---|---|---|
| **512 MB** | NEXUS Lite (`lite-512`) | **Experimental (Not tested in QEMU)** | Scripts/manifests optimized (`gvfs-backends` moved optional, `zstd` `zram-tools`, no compositor/browser/Steam), but blocked from QEMU execution in sandbox. |
| **768 MB** | NEXUS Lite (`lite-512` / `lite-1g`) | **Not tested in QEMU** | Pending `linux/test/run-qemu-validation.sh` or `.github/workflows/iso-and-qemu-validation.yml`. |
| **1 GB** | NEXUS Lite (`lite-1g`) | **Not tested in QEMU** | Lowest RAM tier where graphical Ubiquity (`>= 1 GiB`) and optional light browsing are expected to be viable; pending VM verification. |
| **2 GB** | NEXUS Lite & NEXUS Standard | **Not tested in QEMU** | Entry floor for NEXUS Standard (Cinnamon); pending VM verification. |
| **4 GB** | NEXUS Lite & NEXUS Standard | **Not tested in QEMU** | Comfortable Standard (Cinnamon) & MADOO Xfce target (`nexus-system.conf`). |

**Honest Minimum RAM Recommendation (until VM matrix runs complete):**
- Do **not** advertise `512 MB` as verified or general-purpose. Until `run-qemu-validation.sh` passes all 6 guest memory stages (`post_login`, `idle_5min`, `file_manager`, `terminal`, `multi_apps`, `post_close`) with zero OOM kills, **512 MB** remains strictly **Experimental**, **`1 GB` (`1024 MiB`)** is the realistic recommended minimum for a usable **NEXUS Lite** graphical desktop + installer, and **`2 GB` (`2048 MiB`, `4 GB` recommended)** remains the minimum for **NEXUS Standard (Cinnamon)**.

## Browser, Gaming & Installer Limitations

- **Web Browsers:** Excluded by default from `512 MB` (`lite-packages.list` marks `falkon` and `firefox` optional). Modern web apps and HD video require `>= 1–2 GiB` RAM; never compromise browser security updates to save memory.
- **Gaming:** Steam, Proton, and GameMode are excluded from NEXUS Lite and remain exclusive to higher-RAM **NEXUS Standard** systems.
- **Swap & `zram`:** `configure-zram.sh` configures compressed `zstd` (with `lz4`/`lzo` fallback) RAM swap (`PERCENT=50`, `vm.swappiness=60`) and verifies `/proc/swaps` + `/sys/block/zram*/mm_stat`. Swap/zram absorbs transient spikes safely and never replaces physical RAM.
- **Low-Memory Installation:** Graphical Ubiquity generally requires `>= 1024 MiB` RAM; `512 MB` systems require enabling `zram` or CLI `debootstrap` installation (`nexus-lite-install.sh`).

## Reproducible External Build & QEMU Test Commands

On a Linux host (`Ubuntu 24.04` / `Debian 12+` / `Linux Mint 22.3`) or via the manual GitHub Actions workflow **`.github/workflows/iso-and-qemu-validation.yml`**:

```sh
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  bash coreutils curl gnupg xorriso squashfs-tools \
  qemu-system-x86 qemu-utils ovmf shellcheck

# 1. Download & GPG/SHA-256 verify Mint 22.3 base ISOs
bash scripts/download-linux-mint.sh --edition xfce
bash scripts/download-linux-mint.sh --edition cinnamon

# 2. Build & verify both separated editions
sudo bash linux/lite/build-nexus-lite-iso.sh
bash linux/build/verify-nexus-iso.sh --edition lite

sudo bash linux/build/build-nexus-iso.sh --edition cinnamon
bash linux/build/verify-nexus-iso.sh --edition cinnamon

# 3. Boot headless UEFI/OVMF QEMU matrix on disposable qcow2 disks
bash linux/test/run-qemu-validation.sh --edition lite --ram-matrix "512 768 1024 2048 4096"
bash linux/test/run-qemu-validation.sh --edition cinnamon --ram-matrix "2048 4096"
```

Inside a booted guest, capture the 6-stage memory profile and ZRAM pressure test:

```sh
bash linux/test/guest-mem-probe.sh --stage post_login --out /tmp/mem-post-login.json
bash linux/test/test-zram-pressure.sh --pressure-mb 96
```
