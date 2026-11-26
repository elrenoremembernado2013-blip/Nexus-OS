# NEXUS Lite — Ultra-Low-RAM Edition (Phase 11–12.3 Validation Guide)

## Why NEXUS Lite Exists

Linux Mint Cinnamon is designed for `>= 2–4 GiB` RAM and uses `~1103 MiB` idle when installed (`4096 MiB` VM). **NEXUS Lite** keeps the exact same **Linux Mint 22.3 / Ubuntu 24.04 Noble (`x86_64`)** security, APT signature verification, UFW firewall, `NetworkManager`, and `unattended-upgrades` foundation while replacing Cinnamon/Xfce with **Openbox + `tint2` + `PCManFM` + `LXTerminal` (GNU Bash)**, disabling heavy tray autostart bloat (`warpinator`, `sticky`, `mintupdate`, `evolution-alarm-notify`, `blueman`, `mintwelcome`), and enabling `zstd` `zram-tools` (`50%` RAM).

## Measured Post-Install 7-Stage RAM & ZRAM Telemetry (Run `45722286627`, Commit `efc6c01`, `accel=tcg`)

All measurements below were captured **after full disk installation onto disposable `/dev/vda` and booting without the live ISO** across 3 reboots (`Boot 1`, warm `Boot 2`, cold `Boot 3`) via `guest-mem-probe.sh` and `test-zram-pressure.sh`:

| Edition & Tier (Installed Boot 1 / Boot 3) | `1_post_login` Used / Avail | `2_post_session_init` Used | `3_idle` Used | `4_file_manager` Used | `5_terminal` Used | `6_multi_apps` Used | `7_post_close` Used | Swap Used (`3_idle` -> `7_post_close`) | ZRAM Ratio / Pressure (`oom_kill`) |
|---|---|---|---|---|---|---|---|---|---|
| **NEXUS Lite `512 MiB` (Boot 1)** | `233 / 217` | `260` | `282` | `290` | `300` | `270` | `257` | `101 -> 175 MiB` | `4.81–5.95x` / `64 MiB` **PASS** (`0` OOM) |
| **NEXUS Lite `512 MiB` (Boot 3 Cold)** | `260 / 191` | `296` | `233` | `245` | `254` | `254` | `237` | `81 -> 100 MiB` | `5.39–6.05x` / `64 MiB` **PASS** (`0` OOM) |
| **NEXUS Lite `768 MiB` (Boot 1)** | `334 / 368` | `394` | `416` | `418` | `412` | `431` | `417` | `23 -> 66 MiB` | `5.34–6.02x` / `96 MiB` **PASS** (`0` OOM) |
| **NEXUS Lite `1024 MiB` (Boot 1)** | `386 / 568` | `466` | `446` | `448` | `465` | `483` | `465` | `0 -> 0 MiB` | `96 MiB` **PASS** (`0` OOM) |
| **NEXUS Lite `1024 MiB` (Boot 3 Cold)** | `389 / 565` | `467` | `475` | `474` | `483` | `498` | `490` | `0 -> 0 MiB` | `96 MiB` **PASS** (`0` OOM) |
| **NEXUS Lite `2048 MiB` (Boot 1)** | `389 / 1571` | `504` | `502` | `501` | `516` | `561` | `530` | `0 -> 0 MiB` | `96 MiB` **PASS** (`0` OOM) |
| **NEXUS Cinnamon `4096 MiB` (Boot 1)** | `511 / 3398` | `727` | `1103` | `1110` | `1128` | `1190` | `1079` | `0 -> 0 MiB` | N/A (`0` OOM) |
| **MADOO Xfce `4096 MiB` (Boot 1)** | `505 / 3404` | `538` | `907` | `905` | `928` | `958` | `889` | `0 -> 0 MiB` | N/A (`0` OOM) |
| **MADOO Xfce `4096 MiB` (Boot 3 Cold)** | `470 / 3439` | `602` | `858` | `870` | `872` | `900` | `884` | `0 -> 0 MiB` | N/A (`0` OOM) |

*(Live ISO 6-stage measurements from Phase 12.2 run `45656960059` also passed `0` OOM across all tiers; see `docs/RELEASE_DASHBOARD.md` for per-tier Phase 12.3 install durations and reboot metrics.)*

## Evidence-Based Classification & Minimum RAM Recommendations

| RAM Level | Target Configuration | Classification | Notes & Evidence Basis |
|---|---|---|---|
| **512 MB** | NEXUS Lite (`lite-512`) | **Experimental (Verified QEMU Install + 3-Reboot + ZRAM)** | Installed `2/2` via `nexus-disk-install` (`840.4s`), booted `3/3` without ISO (`233–300 MiB` used, `81–175 MiB` zram swap at `4.81–6.06x` ratio, `0` OOM, `persist=true`, `64 MiB` pressure PASS). Remains **Experimental** because heavy web browsing/Electron apps are unsupported in 512 MiB and `Boot 3` logged `28` `journalctl -p err` messages (`0` failed systemd units). |
| **768 MB** | NEXUS Lite (`lite-512` / `lite-1g`) | **Verified Lightweight GUI (QEMU)** | Installed `1/1` (`832.5s`), booted `3/3` (`416–431 MiB` used, `0–66 MiB` swap, `0` err, `0` failed units, `96 MiB` ZRAM PASS). |
| **1 GB (`1024 MiB`)** | NEXUS Lite (`lite-1g`) | **Verified Recommended Minimum for NEXUS Lite (QEMU)** | Live `3/3` (`ubiquity` GTK UI verified `99.98%`), installed `1/1` (`836.6s`), booted `3/3` (`446–516 MiB` used, `0` swap, `~460–500 MiB` free RAM, `96 MiB` ZRAM PASS). |
| **2 GB (`2048 MiB`)** | NEXUS Lite / NEXUS Standard | **Verified for Lite; Entry Floor (Development) for Cinnamon** | Lite installed `1/1` & booted `3/3` (`502–561 MiB` used, `0` swap). Cinnamon installed `1/1` & booted `3/3`, but software LLVMpipe (`tcg`) causes >30s initial render delay at `-vga std` (`96.65%` once settled under `-vga virtio`). |
| **4 GB (`4096 MiB`)** | NEXUS Standard (Cinnamon) & MADOO Xfce | **Verified Recommended Tier (QEMU)** | Both installed `2/2` and booted `3/3` (`0` err, `0` failed units, `0` OOM, `persist=true`). |

## Browser, Gaming & Low-Memory Installation Procedure

- **Web Browsers & Gaming:** Excluded by default from `512 MB` (`lite-packages.list` marks `falkon` and `firefox` optional). Steam/Proton remain exclusive to `>= 4 GB` NEXUS Standard systems.
- **Swap & `zram`:** `configure-zram.sh` configures compressed `zstd` RAM swap (`PERCENT=50`, `vm.swappiness=60`). Swap/zram absorbs transient spikes safely and never replaces physical RAM.
- **Exact Installation Procedure (Target Disk):**
  1. **Verify target disk & preflight:** Boot live ISO, open `LXTerminal`, and run `nexus-install-preflight --json` plus `lsblk` to confirm the target disk (e.g. `/dev/vda` or `/dev/nvme0n1`).
  2. **For `>= 1024 MiB` RAM systems (Ubiquity GUI or deterministic CLI):** Launch the graphical installer via `sudo ubiquity` (or the desktop installer launcher) for interactive guided/manual/LUKS partitioning, or run `sudo nexus-disk-install --disk /dev/sdX --user <username> --autologin --edition lite --yes-erase-disk` (prompts interactively for password if `--password-file` is not supplied).
  3. **For `512 MiB` systems (`CLI` path):** Graphical `ubiquity` is skipped below `850 MiB`; run `sudo nexus-lite-install --disk /dev/sdX --dry-run` to inspect GPT ESP (`512 MiB` FAT32) + ext4 root + UEFI GRUB steps, then execute `sudo nexus-lite-install --disk /dev/sdX --hostname nexus-lite --user <username> --yes-erase-disk`.

## Reproducible External Build, Install & 3-Reboot QEMU Test Commands

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

# 2. Build & verify all three separated editions (including unmkinitramfs + unsquashfs test-leak checks)
sudo bash linux/lite/build-nexus-lite-iso.sh
bash linux/build/verify-nexus-iso.sh --edition lite

sudo bash linux/build/build-nexus-iso.sh --edition cinnamon
bash linux/build/verify-nexus-iso.sh --edition cinnamon

sudo bash linux/build/build-nexus-iso.sh --edition xfce
bash linux/build/verify-nexus-iso.sh --edition xfce

# 3. Run full graphical QEMU + disposable-disk install + 3-reboot ISO-free validation
bash linux/test/run-qemu-validation.sh --edition lite --ram-matrix "512 768 1024 2048" --install-test --reliability
bash linux/test/run-qemu-validation.sh --edition cinnamon --ram-matrix "2048 4096" --install-test --reliability
bash linux/test/run-qemu-validation.sh --edition xfce --ram-matrix "4096" --install-test --reliability
```
