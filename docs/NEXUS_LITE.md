# NEXUS Lite — Ultra-Low-RAM Edition (Phase 11 & Phase 12.2 Validation Guide)

## Why NEXUS Lite Exists

Linux Mint Cinnamon is designed for `>= 2–4 GiB` RAM and uses `~1011 MiB` idle (`4096 MiB` VM) / `~766–942 MiB` (`2048 MiB` VM). **NEXUS Lite** keeps the exact same **Linux Mint 22.3 / Ubuntu 24.04 Noble (`x86_64`)** security, APT signature verification, UFW firewall, `NetworkManager`, and `unattended-upgrades` foundation while replacing Cinnamon/Xfce with **Openbox + `tint2` + `PCManFM` + `LXTerminal` (GNU Bash)**, disabling heavy tray autostart bloat (`warpinator`, `sticky`, `mintupdate`, `evolution-alarm-notify`, `blueman`, `mintwelcome`), and enabling `zstd` `zram-tools` (`50%` RAM).

## Measured 6-Stage RAM & ZRAM Telemetry (GitHub Actions Run `45656960059`, `accel=tcg`)

All measurements below were collected inside live QEMU VMs booted from the built ISOs (`nexus-os-22.3-lite-amd64.iso`, `nexus-os-22.3-cinnamon-amd64.iso`, `nexus-os-22.3-xfce-amd64.iso`) via ephemeral `virtio-serial` (`nexus-guest-test.py` + `guest-mem-probe.sh` + `test-zram-pressure.sh`) and QMP `screendump` PNG verification:

| Edition & Tier | Kernel Total (MiB) | `1_post_login` Used / Avail | `2_idle` Used / Avail (`idle` s) | `3_file_manager` Used | `4_terminal` Used | `5_multi_apps` Used | `6_post_close` Used | Swap Used (`2_idle` -> `6_post_close`) | ZRAM Pressure (`oom_kill`) |
|---|---|---|---|---|---|---|---|---|---|
| **NEXUS Lite `512 MiB`** | `458` | `183 / 275` | `217 / 240` (`300s`) | `222` | `213` | `227` | `209` | `119 -> 138 MiB` | `64 MiB` **PASS** (`0` OOM) |
| **NEXUS Lite `768 MiB`** | `709` | `342 / 367` | `367 / 342` (`30s`) | `374` | `379` | `395` | `390` | `30 -> 41 MiB` | `96 MiB` **PASS** (`0` OOM) |
| **NEXUS Lite `1024 MiB`** | `961` | `367 / 594` | `427 / 533` (`300s`) | `428` | `438` | `459` | `467` | `1 -> 1 MiB` | `96 MiB` **PASS** (`0` OOM) |
| **NEXUS Lite `2048 MiB`** | `1967` | `404 / 1564` | `464 / 1503` (`30s`) | `464` | `470` | `496` | `507` | `1 -> 1 MiB` | `96 MiB` **PASS** (`0` OOM) |
| **NEXUS Lite `4096 MiB`** | `3916` | `517 / 3398` | `572 / 3343` (`300s`) | `575` | `576` | `586` | `596` | `0 -> 0 MiB` | `96 MiB` **PASS** (`0` OOM) |
| **NEXUS Cinnamon `2048 MiB`** | `1967` | `594 / 1373` | `766 / 1201` (`30s`) | `796` | `851` | `938` | `942` | `0 -> 0 MiB` | N/A (`0` OOM) |
| **NEXUS Cinnamon `4096 MiB`** | `3916` | `657 / 3258` | `1011 / 2905` (`300s`) | `1019` | `1040` | `1065` | `1036` | `0 -> 0 MiB` | N/A (`0` OOM) |
| **MADOO Xfce `4096 MiB`** | `3916` | `493 / 3422` | `737 / 3178` (`300s`) | `720` | `721` | `740` | `746` | `0 -> 0 MiB` | N/A (`0` OOM) |

## Evidence-Based Classification & Minimum RAM Recommendations

| RAM Level | Target Configuration | Classification | Notes & Evidence Basis |
|---|---|---|---|
| **512 MB** | NEXUS Lite (`lite-512`) | **Verified Minimal Experimental (CLI / Light GUI + ZRAM)** | Booted UEFI, logged into Openbox + `tint2`, ran 5-minute idle (`217 MiB` used, `119 MiB` zram swap), opened/verified `pcmanfm` + `lxterminal` + `obconf` + `mousepad`, passed `64 MiB` ZRAM pressure (`0` OOM kills). Heavy web browsing remains unsupported at `512 MB`. |
| **768 MB** | NEXUS Lite (`lite-512` / `lite-1g`) | **Verified Lightweight GUI** | Comfortable Openbox + `tint2` desktop (`367–395 MiB` used, `30–41 MiB` swap, `96 MiB` ZRAM pressure PASS). |
| **1 GB (`1024 MiB`)** | NEXUS Lite (`lite-1g`) | **Verified Recommended Minimum for NEXUS Lite** | `427–467 MiB` used (`~500 MiB` free RAM, only `1 MiB` swap), `96 MiB` ZRAM pressure PASS; suitable for graphical Ubiquity installation and light daily desktop tasks. |
| **2 GB (`2048 MiB`)** | NEXUS Lite / NEXUS Standard | **Verified for Lite; Entry Floor for Cinnamon** | Lite uses `464–507 MiB`. Cinnamon boots and launches X11 apps (`766–942 MiB` used), though software LLVMpipe rendering under `tcg` is slow at `30s`. |
| **4 GB (`4096 MiB`)** | NEXUS Standard (Cinnamon) & MADOO Xfce | **Verified Recommended Tier** | Cinnamon (`1011–1065 MiB` used, `96.06%` screen verified) and Xfce (`737–746 MiB` used, `97.87%` screen verified) run smoothly with `~2.85–3.17 GiB` available RAM. |

## Browser, Gaming & Low-Memory Installation Procedure

- **Web Browsers & Gaming:** Excluded by default from `512 MB` (`lite-packages.list` marks `falkon` and `firefox` optional). Steam/Proton remain exclusive to `>= 4 GB` NEXUS Standard systems.
- **Swap & `zram`:** `configure-zram.sh` configures compressed `zstd` RAM swap (`PERCENT=50`, `vm.swappiness=60`). Swap/zram absorbs transient spikes safely and never replaces physical RAM.
- **Exact Installation Procedure (Manual / Target Disk):**
  1. **Verify target disk & preflight:** Boot live ISO, open `LXTerminal` (or terminal), and run `nexus-install-preflight --json` plus `lsblk` to confirm the target disk (e.g. `/dev/vda` or `/dev/nvme0n1`).
  2. **For `>= 1024 MiB` RAM systems (recommended):** Launch the graphical installer via `sudo ubiquity` (or the desktop installer launcher), choose keyboard/locale, select guided partitioning (or manual + LUKS encryption), create the primary user, install GRUB, and reboot after removing the ISO/USB.
  3. **For `512 MiB` systems (`CLI debootstrap` path):** If graphical Ubiquity hits memory limits at `512 MiB`, run `sudo nexus-lite-install --disk /dev/sdX --dry-run` first to inspect partitioning/fstab/GRUB steps, then execute `sudo nexus-lite-install --disk /dev/sdX --hostname nexus-lite --user <username>` (ensure `zramswap` is active via `sudo nexus-configure-zram enable`).

## Reproducible External Build & Graphical QEMU Test Commands

On a Linux host (`Ubuntu 24.04` / `Debian 12+` / `Linux Mint 22.3`) or via `.github/workflows/iso-and-qemu-validation.yml`:

```sh
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  bash coreutils curl gnupg xorriso squashfs-tools \
  qemu-system-x86 qemu-utils ovmf shellcheck cpio gzip \
  initramfs-tools-core zstd xz-utils

# 1. Download & GPG/SHA-256 verify Mint 22.3 base ISOs
bash scripts/download-linux-mint.sh --edition xfce
bash scripts/download-linux-mint.sh --edition cinnamon

# 2. Build & verify all three separated editions
sudo bash linux/lite/build-nexus-lite-iso.sh
bash linux/build/verify-nexus-iso.sh --edition lite

sudo bash linux/build/build-nexus-iso.sh --edition cinnamon
bash linux/build/verify-nexus-iso.sh --edition cinnamon

sudo bash linux/build/build-nexus-iso.sh --edition xfce
bash linux/build/verify-nexus-iso.sh --edition xfce

# 3. Run full graphical QEMU + virtio-serial + QMP screenshot + 6-stage RAM + ZRAM suite
bash linux/test/run-qemu-validation.sh --edition lite --ram-matrix "512 768 1024 2048 4096" --graphical
bash linux/test/run-qemu-validation.sh --edition cinnamon --ram-matrix "2048 4096" --graphical
bash linux/test/run-qemu-validation.sh --edition xfce --ram-matrix "4096" --graphical
```
