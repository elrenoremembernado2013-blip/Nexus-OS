# NEXUS Lite — Openbox vs. LXQt Evaluation, RAM Matrix & Browser Benchmarks (Phase 12.5–13.0)

## Overview & Dual-Profile Architecture

NEXUS OS maintains two lightweight editions built on **Linux Mint 22.3 / Ubuntu 24.04 Noble (`x86_64`)** with signed APT repos, UFW, `NetworkManager`, `unattended-upgrades`, `cryptsetup` + `cryptsetup-initramfs`, `shim-signed` + `grub-efi-amd64-signed` + `mokutil`, `ntfs-3g` + `os-prober`, and `zstd` ZRAM (`50%`, `vm.swappiness=60`):

1. **NEXUS Lite Openbox (`--edition lite`, `linux/lite/`)** — Ultra-minimalist `Openbox + tint2 + PCManFM + LXTerminal (GNU Bash)` (`nexus-os-22.3-lite-amd64.iso`, `2.84 GB`, SHA-256 `6417381b5a9bc8aa027b112df7ee63482a2460fd34fef81f78ddd46a21a14fab`).
2. **NEXUS Lite LXQt (`--edition lite-lxqt`, `linux/lite/lxqt/`, `linux/lite/manifests/lite-lxqt-packages.list`)** — Curated **LXQt + Openbox WM** (`lxqt-panel` with Dark Glass QSS styling, `pcmanfm-qt`, `qterminal`, `featherpad`, `qps`, `lxqt-archiver`, `screengrab`, `lxqt-config`, `lxqt-policykit`, `lxqt-powermanagement`, `LightDM`, `Xorg`, `NetworkManager`, without `sddm`/`connman`/`snapd`/`libreoffice`) (`nexus-os-22.3-lite-lxqt-amd64.iso`, `2.87 GB`, `+30.8 MB`, SHA-256 `05970e975a37d3141ad786b46e8d22dffd82aab124de7e90028fc904934daa89`).

## Head-to-Head QEMU/OVMF Comparison (`512 MB` – `4 GB`, Run `45919673389`, `b5594a2`, `accel=tcg`)

| RAM Tier | Openbox Live (`3_idle` / `6_multi` / `7_close`, Swap) | LXQt Live (`3_idle` / `6_multi` / `7_close`, Swap) | Idle Delta (`LXQt - OB`) | Openbox Live/Inst/Boot | LXQt Live/Inst/Boot | LXQt Installed `idle -> close` (Boot 1) | ZRAM Pressure / `oom_kill` |
|---|---|---|---|---|---|---|---|
| **`512 MiB`** | `237 / 259 / 232 MiB` (`104->116` sw) | `241 / 263 / 233 MiB` (`174->187` sw) | **`+4 MiB` (`+70` sw)** | `3/3` live (`2/2` inst, `3/3` boot in `12.3`) | `3/3` live, `2/2` inst (`1153.2s`), `3/3` boot | `281 -> 273 MiB` (`0` err) | Both **PASS** (`4.24–4.40x`, `0` OOM) |
| **`768 MiB`** | `364 / 377 / 354 MiB` (`75->87` sw) | `402 / 425 / 400 MiB` (`108->107` sw) | **`+38 MiB` (`+33` sw)** | `1/1` live (`1/1` inst, `3/3` boot in `12.3`) | `1/1` live, `1/1` inst (`917.5s`), `3/3` boot | `484 -> 449 MiB` (`0` err) | Both **PASS** (`3.85–4.07x`, `0` OOM) |
| **`1024 MiB`** | `437 / 464 / 480 MiB` (`2` sw) | `508 / 525 / 501 MiB` (`11->52` sw) | **`+71 MiB`** | `3/3` live, `1/1` inst (`1213.7s`), `3/3` boot | `3/3` live, `1/1` inst (`1765.6s`), `3/3` boot | `562 -> 582 MiB` vs OB `478 -> 513` (`0` err) | Both **PASS** (`3.10–4.84x`, `0` OOM) |
| **`2048 MiB`** | `461 / 495 / 512 MiB` (`1` sw) | `542 / 574 / 550 MiB` (`1` sw) | **`+81 MiB`** | `1/1` live (`1/1` inst, `3/3` boot in `12.3`) | `1/1` live, `1/1` inst (`1692.9s`), `3/3` boot | `574 -> 598 MiB` (`0` err) | Both **PASS** (`2.79–2.80x`, `0` OOM) |
| **`4096 MiB`** | `571 / 592 / 587 MiB` (`0` sw) | `628 / 658 / 644 MiB` (`0` sw) | **`+57 MiB`** | `1/1` live (`ub_ui: true`) | `1/1` live (`ub_ui: true`) | N/A (live comparison) | Both **PASS** (`0` OOM) |

## Browser Performance Benchmarks: QEMU TCG (`llvmpipe`) vs. Physical GPU Procedure

Measured inside cold-booted **installed** disposable QEMU/OVMF VMs (`linux/test/nexus-browser-bench.py`, `bochs-drm` + `llvmpipe`, run `45919673389`) across `1, 2, 4, 6` tabs on both **`lite-lxqt`** and **`lite` Openbox**:

| Edition & RAM Tier | Falkon (`start_s` / `tabs_ok` / `1->6T RSS` / `Swap` / `OOM` / `Post-Close RSS`) | Firefox (`start_s` / `tabs_ok` / `1->6T RSS` / `Swap` / `OOM` / `Post-Close RSS`) | Measured Winner (QEMU TCG) |
|---|---|---|---|
| **Lite LXQt `1024 MiB`** (`954 MiB` avail) | `1.35s` / **`4/6`** (`32.8s` at 4T) / `491.0 -> 762.7 MiB` / `349.2 MiB` sw / `0` / `0.0 MiB` (`402.8` used) | `1.32s` / **`6/6`** (`1.73–6.64s` load) / `223.2 -> 961.0 MiB` / `235.2 MiB` sw / `0` / `0.0 MiB` (`378.2` used) | **Firefox** (completed `6/6` tabs cleanly) |
| **Lite LXQt `2048 MiB`** (`1960.5 MiB`) | `1.28s` / **`2/6`** (`24.0s` at 2T) / `507.6 -> 1291.1 MiB` / `0` sw / `0` / `0.0 MiB` (`574.7` used) | `1.27s` / **`6/6`** (`2.27–10.10s` load) / `339.3 -> 952.7 MiB` / `0` sw / `0` / `0.0 MiB` (`590.3` used) | **Firefox** (`-338.4 MiB` RSS at 6 tabs, `6/6` tabs) |
| **Lite LXQt `4096 MiB`** (`3908.8 MiB`) | `1.26s` / **`2/6`** (`22.8s` at 2T) / `507.0 -> 1294.6 MiB` / `0` sw / `0` / `0.0 MiB` (`654.3` used) | `1.29s` / **`6/6`** (`1.98–10.69s` load) / `341.9 -> 942.5 MiB` / `0` sw / `0` / `0.0 MiB` (`657.7` used) | **Firefox** (`-352.1 MiB` RSS at 6 tabs, `6/6` tabs) |
| **Lite Openbox `1024 MiB`** (`954 MiB`) | `1.34s` / **`1/6`** / `484.3 -> 799.3 MiB` / `239.4 MiB` sw / `0` / `0.0 MiB` (`359.4` used) | `1.38s` / **`6/6`** (`2.13–7.89s` load) / `228.7 -> 823.4 MiB` / `166.0 MiB` sw / `0` / `0.0 MiB` (`373.5` used) | **Firefox** (`6/6` tabs vs `1/6`, faster loads) |
| **Lite Openbox `2048 MiB`** (`1960.5 MiB`) | `1.33s` / **`4/6`** (`27.6s` at 4T) / `499.9 -> 1260.2 MiB` / `0` sw / `0` / `0.0 MiB` (`498.1` used) | `1.37s` / **`6/6`** (`3.13–13.86s` load) / `403.9 -> 937.6 MiB` / `0` sw / `0` / `0.0 MiB` (`500.3` used) | **Firefox** (`-322.6 MiB` RSS at 6 tabs, `6/6` tabs) |
| **Lite Openbox `4096 MiB`** (`3908.8 MiB`) | `1.31s` / **`4/6`** (`27.4s` at 4T) / `498.4 -> 1250.7 MiB` / `0` sw / `0` / `0.0 MiB` (`590.7` used) | `1.34s` / **`6/6`** (`2.33–14.87s` load) / `362.0 -> 946.3 MiB` / `0` sw / `0` / `0.0 MiB` (`596.4` used) | **Firefox** (`-304.4 MiB` RSS at 6 tabs, `6/6` tabs) |

### Phase 13.0 Physical-GPU Browser Qualification Status (`NOT TESTED`)

- **Physical-GPU Browser Runs (`cinnamon`, `xfce`, `lite`, `lite-lxqt`):** **`NOT TESTED`**. `nexus-browser-bench.py --standalone` and `/usr/local/bin/nexus-browser-qualify` now capture active PCI GPU driver, `glx_renderer`, `acceleration_mode` (`hardware_gpu` vs `software_llvmpipe_or_virtual`), WebGL (`webgl2`/`webgl1` + `WEBGL_debug_renderer_info` + FPS), and HTML5 video codec support (`H.264`, `VP9`, `VP8`, `AV1`).
- **Conservative Decision:** Keep both `firefox` and `falkon` `optional` in Lite ISOs until bare-metal GPU-accelerated tests are completed (`512–768 MiB` remains unsuitable for heavy multi-tab web browsing).

## Option B Architectural Decision & ZRAM Tier Policy

- **Option B retained:** `lite-lxqt` is primary for `>= 1 GiB` RAM (`Alpha` at `1024 / 2048 / 4096 MiB`); `lite` Openbox is retained for `512–768 MiB` (`Experimental` at `512 MiB`, `Development` at `768 MiB`). Neither edition is promoted to `Beta` or `Stable` without physical bare-metal qualification.
