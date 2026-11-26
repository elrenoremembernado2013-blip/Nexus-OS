# NEXUS Lite — Openbox vs. Lubuntu/LXQt Evaluation & RAM Matrix (Phase 12.4)

## Overview & Dual-Profile Architecture

NEXUS OS evaluates two lightweight editions built on the **Linux Mint 22.3 / Ubuntu 24.04 Noble (`x86_64`)** security, APT signature, UFW, `NetworkManager`, `unattended-upgrades`, and `zstd` ZRAM (`50%`, `vm.swappiness=60`) foundation:

1. **NEXUS Lite Openbox (`--edition lite`, `linux/lite/`)** — Ultra-minimalist `Openbox + tint2 + PCManFM + LXTerminal (GNU Bash)` (`nexus-os-22.3-lite-amd64.iso`, `2.84 GB`, SHA-256 `ea38cdc9f3ab2dd2c9a14ac6b4123f46a64727d37cc637fb665db7474758dbce`).
2. **NEXUS Lite LXQt Candidate (`--edition lite-lxqt`, `linux/lite/lxqt/`, `linux/lite/manifests/lite-lxqt-packages.list`)** — Curated Ubuntu/Lubuntu **LXQt + Openbox WM** (`lxqt-panel` with Dark Glass QSS styling, `pcmanfm-qt`, `qterminal` + GNU Bash, `featherpad`, `qps`, `lxqt-archiver`, `screengrab`, `lxqt-config`, `lxqt-policykit`, `lxqt-powermanagement`, `LightDM`, `Xorg`, `NetworkManager`, without `sddm`/`connman`/`snapd`/`libreoffice`) (`nexus-os-22.3-lite-lxqt-amd64.iso`, `2.87 GB`, `+30.8 MB`, SHA-256 `e1be78e6044243cb6daabbc27fd225656d7fabe446fd96e2274c5978ba3c9906`).

## Head-to-Head QEMU/OVMF Comparison (`512 MB` – `4 GB`, Run `45808626482`, `d537b2c`, `accel=tcg`)

Both editions were tested under identical QEMU (`q35`, OVMF UEFI, `-vga std`, `300s` idle on primary tiers, `30s` idle on secondary tiers, identical `guest-mem-probe.sh` & `test-zram-pressure.sh` workloads) and aggregated by `linux/lite/scripts/nexus-lite-compare.py`:

| RAM Tier | Openbox Live (`3_idle` / `6_multi` / `7_close`, Swap) | LXQt Live (`3_idle` / `6_multi` / `7_close`, Swap) | Idle Delta (`LXQt - OB`) | Openbox Live/Inst/Boot | LXQt Live/Inst/Boot | LXQt Installed `idle -> close` (Boot 1–3) | ZRAM Pressure / `oom_kill` |
|---|---|---|---|---|---|---|---|
| **`512 MiB`** | `240 / 255 / 237 MiB` (`103->113` sw) | `251 / 255 / 233 MiB` (`160->189` sw) | **`+11 MiB` (`+57` sw)** | `2/3` live (`2/2` inst, `3/3` boot in `12.3`) | `3/3` live, `2/2` inst (`1210.8s`), `3/3` boot | `275–287 -> 266–280 MiB` (`0` err) | Both **PASS** (`4.32–4.48x`, `0` OOM) |
| **`768 MiB`** | `366 / 384 / 377 MiB` (`39->50` sw) | `405 / 434 / 418 MiB` (`93->93` sw) | **`+39 MiB` (`+54` sw)** | `1/1` live (`1/1` inst, `3/3` boot in `12.3`) | `1/1` live, `1/1` inst (`1229.4s`), `3/3` boot | `466–476 -> 403–448 MiB` (`0` err) | Both **PASS** (`3.94–4.82x`, `0` OOM) |
| **`1024 MiB`** | `459 / 486 / 495 MiB` (`1->1` sw) | `521 / 522 / 504 MiB` (`10->43` sw) | **`+62 MiB`** | `3/3` live, `1/1` inst (`1554.5s`), `3/3` boot | `3/3` live, `1/1` inst (`1154.0s`), `3/3` boot | `549–564 -> 559–572 MiB` vs OB `474–485` (`0` err) | Both **PASS** (`3.10–4.86x`, `0` OOM) |
| **`2048 MiB`** | `457 / 484 / 500 MiB` (`2->2` sw) | `540 / 571 / 552 MiB` (`1->1` sw) | **`+83 MiB`** | `1/1` live (`1/1` inst, `3/3` boot in `12.3`) | `1/1` live, `1/1` inst (`1189.3s`), `3/3` boot | `558–578 -> 580–617 MiB` (`0` err) | Both **PASS** (`2.79x`, `0` OOM) |
| **`4096 MiB`** | `568 / 575 / 583 MiB` (`0` sw) | `639 / 671 / 666 MiB` (`0` sw) | **`+71 MiB`** | `1/1` live (`ub_ui: true`) | `1/1` live (`ub_ui: true`) | N/A (live comparison) | Both **PASS** (`0` OOM) |

### Startup Time, Panel RSS & Stability Notes

- **Installed Startup (`1024 MiB`, Boots 1–3):** Openbox WM `15.6–17.8s` / `tint2` `28.4–30.6s`; LXQt Openbox WM `14.6–20.8s` / `lxqt-panel` `25.9–32.0s` — **effectively tied once installed**.
- **Panel Memory (`1024–4096 MiB`):** `tint2` uses `24.95–25.69 MiB` RSS vs `lxqt-panel` `35.30–36.62 MiB` (`~+10 MiB`). Under `512 MiB` ZRAM paging, `tint2` compresses down to `3.84 MiB` RSS vs `lxqt-panel` `22.84 MiB`.
- **Errors & Persistence:** All `12` installed LXQt boots across `512 / 768 / 1024 / 2048 MiB` logged **`0` `journalctl -p err` messages, `0` failed systemd units, `persist: true`, and `NetworkManager: connected`**.

## Option A / B / C Architectural Recommendation

- **Selected Strategy: Option B — Dual-Tier Lite Architecture**
  - **Promote `NEXUS Lite LXQt` (`lite-lxqt`) as the primary UX-forward Lite desktop for `>= 1 GiB` RAM systems (`1024 MiB` practical minimum, `2048 MiB` comfortable):** Adds only `~62–83 MiB` idle RAM and `+30.8 MB` ISO size while gaining a full Qt/LXQt settings center (`lxqt-config`), integrated power management, Polkit agent, cohesive Dark Glass panel/theming, `PCManFM-Qt`, `QTerminal`, `FeatherPad`, `Qps`, `lxqt-archiver`, and `ScreenGrab`.
  - **Retain `NEXUS Lite Openbox` (`lite`) for ultra-low `512–768 MiB` systems:** Saves `~39–62 MiB` RAM and `~54–57 MiB` active ZRAM swap pressure under tight `512–768 MiB` limits (`512 MiB` remains **Experimental** on both editions; heavy web browsers and Electron apps remain unsupported at `512 MiB`).

## ZRAM & Tier Policy (`linux/lite/profiles/lite-*.conf`)

| Profile | RAM Floor | ZRAM Policy (`configure-zram.sh`) | Browser & Apps Policy | Classification |
|---|---|---|---|---|
| `lite-512` | `512 MiB` | `zstd`, `PERCENT=50`, `swappiness=60`, `cache_pressure=100` | Excluded by default; CLI install (`nexus-lite-install`) | **Experimental** |
| `lite-768` | `768 MiB` | `zstd`, `PERCENT=50`, `swappiness=60` | Light single-tab only; CLI install | **Experimental / Development** |
| `lite-1g` | `1024 MiB` | `zstd`, `PERCENT=50`, `swappiness=60` | Optional lightweight browser (`falkon`), Ubiquity GUI OK | **Alpha (Minimum Practical Target)** |
| `lite-2g` | `2048 MiB` | `zstd`, `PERCENT=50`, `swappiness=40` | Full desktop + standard browser | **Alpha (Comfortable Lite Tier)** |
| `lite-4g` | `4096 MiB` | `zstd`, `PERCENT=25`, `swappiness=20` | Full Lite productivity or Standard Cinnamon/Xfce | **Alpha** |

## Reproducible Build & Side-by-Side QEMU Commands

```sh
# Build isolated Openbox Lite and LXQt Lite ISOs
sudo bash linux/lite/build-nexus-lite-iso.sh
bash linux/build/verify-nexus-iso.sh --edition lite

sudo bash linux/lite/scripts/build-nexus-lite-lxqt-iso.sh
bash linux/build/verify-nexus-iso.sh --edition lite-lxqt

# Run parallel QEMU verification & generate comparison report
bash linux/test/run-qemu-validation.sh --edition lite --ram-matrix "512 768 1024 2048 4096" --install-ram-matrix "1024" --primary-idle 300 --install-test --reliability
bash linux/test/run-qemu-validation.sh --edition lite-lxqt --ram-matrix "512 768 1024 2048 4096" --install-ram-matrix "512 768 1024 2048" --primary-idle 300 --install-test --reliability
python3 linux/lite/scripts/nexus-lite-compare.py --openbox-json build/qemu-test/qemu-results-lite.json --lxqt-json build/qemu-test/qemu-results-lite-lxqt.json --out-json build/lite-comparison.json --out-md build/lite-comparison.md
```
