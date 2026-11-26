# NEXUS Lite — Openbox vs. LXQt Evaluation, RAM Matrix & Browser Benchmarks (Phase 12.5)

## Overview & Dual-Profile Architecture

NEXUS OS maintains two lightweight editions built on **Linux Mint 22.3 / Ubuntu 24.04 Noble (`x86_64`)** with signed APT repos, UFW, `NetworkManager`, `unattended-upgrades`, `cryptsetup` + `cryptsetup-initramfs`, and `zstd` ZRAM (`50%`, `vm.swappiness=60`):

1. **NEXUS Lite Openbox (`--edition lite`, `linux/lite/`)** — Ultra-minimalist `Openbox + tint2 + PCManFM + LXTerminal (GNU Bash)` (`nexus-os-22.3-lite-amd64.iso`, `2.84 GB`, SHA-256 `49a948a1d159d60948d8e50831db48cb56d291e6e01852e7357c5fc8afa71eb4`).
2. **NEXUS Lite LXQt (`--edition lite-lxqt`, `linux/lite/lxqt/`, `linux/lite/manifests/lite-lxqt-packages.list`)** — Curated **LXQt + Openbox WM** (`lxqt-panel` with Dark Glass QSS styling, `pcmanfm-qt`, `qterminal`, `featherpad`, `qps`, `lxqt-archiver`, `screengrab`, `lxqt-config`, `lxqt-policykit`, `lxqt-powermanagement`, `LightDM`, `Xorg`, `NetworkManager`, without `sddm`/`connman`/`snapd`/`libreoffice`) (`nexus-os-22.3-lite-lxqt-amd64.iso`, `2.87 GB`, `+30.7 MB`, SHA-256 `0543e98359481124948784ee98252c79a47c85f20d43d3c556c270abd1d04862`).

## Head-to-Head QEMU/OVMF Comparison (`512 MB` – `4 GB`, Run `45876350800`, `b4879cb`, `accel=tcg`)

| RAM Tier | Openbox Live (`3_idle` / `6_multi` / `7_close`, Swap) | LXQt Live (`3_idle` / `6_multi` / `7_close`, Swap) | Idle Delta (`LXQt - OB`) | Openbox Live/Inst/Boot | LXQt Live/Inst/Boot | LXQt Installed `idle -> close` (Boot 1) | ZRAM Pressure / `oom_kill` |
|---|---|---|---|---|---|---|---|
| **`512 MiB`** | `226 / 238 / 214 MiB` (`117->135` sw) | `266 / 266 / 239 MiB` (`142->177` sw) | **`+40 MiB` (`+25` sw)** | `3/3` live (`2/2` inst, `3/3` boot in `12.3`) | `2/3` live, `2/2` inst (`1823.4s`), `3/3` boot | `294 -> 285 MiB` (`0` err) | Both **PASS** (`4.25–4.41x`, `0` OOM) |
| **`768 MiB`** | `366 / 394 / 372 MiB` (`32->65` sw) | `407 / 433 / 407 MiB` (`103->106` sw) | **`+41 MiB` (`+71` sw)** | `1/1` live (`1/1` inst, `3/3` boot in `12.3`) | `1/1` live, `1/1` inst (`1642.3s`), `3/3` boot | `470 -> 434 MiB` (`0` err) | Both **PASS** (`3.93–4.62x`, `0` OOM) |
| **`1024 MiB`** | `445 / 468 / 470 MiB` (`1->1` sw) | `509 / 512 / 504 MiB` (`11->50` sw) | **`+64 MiB`** | `3/3` live, `1/1` inst (`1111.1s`), `3/3` boot | `3/3` live, `1/1` inst (`1165.7s`), `3/3` boot | `564 -> 556 MiB` vs OB `481 -> 516` (`0` err) | Both **PASS** (`2.81–4.85x`, `0` OOM) |
| **`2048 MiB`** | `465 / 488 / 503 MiB` (`2->2` sw) | `555 / 577 / 567 MiB` (`1->1` sw) | **`+90 MiB`** | `1/1` live (`1/1` inst, `3/3` boot in `12.3`) | `1/1` live, `1/1` inst (`1158.5s`), `3/3` boot | `583 -> 600 MiB` (`0` err) | Both **PASS** (`2.79x`, `0` OOM) |
| **`4096 MiB`** | `557 / 577 / 577 MiB` (`0` sw) | `643 / 666 / 652 MiB` (`0` sw) | **`+86 MiB`** | `1/1` live (`ub_ui: true`) | `1/1` live (`ub_ui: true`) | N/A (live comparison) | Both **PASS** (`0` OOM) |

## Phase 12.5 Browser Performance Benchmarks: Firefox vs. Falkon (Run `45876350800`, `b4879cb`)

Measured inside cold-booted **installed** disposable QEMU/OVMF VMs (`linux/test/nexus-browser-bench.py`) using a controlled local HTTP fixture server (DOM grid, article reflow, JS compute table, SVG+Canvas rendering, `/beacon` load timing) across `1, 2, 4, 6` tabs on both **`lite-lxqt`** and **`lite` Openbox**:

| Edition & RAM Tier | Falkon (`start_s` / `tabs_ok` / `1->6T RSS` / `Swap` / `OOM` / `Post-Close RSS`) | Firefox (`start_s` / `tabs_ok` / `1->6T RSS` / `Swap` / `OOM` / `Post-Close RSS`) | Measured Winner (QEMU TCG) |
|---|---|---|---|
| **Lite LXQt `1024 MiB`** (`954 MiB` avail) | `3.87s` / **`1/6`** / `482.4 -> 805.2 MiB` / `274.0 MiB` sw / `0` / `0.0 MiB` (`387.6` used) | `1.36s` / **`6/6`** (`2.29–7.76s` load) / `207.0 -> 775.2 MiB` / `278.1 MiB` sw / `0` / `0.0 MiB` (`400.9` used) | **Firefox** (completed `6/6` tabs, lower peak RSS) |
| **Lite LXQt `2048 MiB`** (`1960.5 MiB`) | `1.35s` / **`1/6`** / `490.7 -> 1260.2 MiB` / `0` sw / `0` / `0.0 MiB` (`567.0` used) | `1.38s` / **`6/6`** (`2.56–6.48s` load) / `339.5 -> 897.9 MiB` / `0` sw / `0` / `0.0 MiB` (`576.3` used) | **Firefox** (`-362.3 MiB` RSS at 6 tabs, `6/6` tabs) |
| **Lite LXQt `4096 MiB`** (`3908.8 MiB`) | `1.32s` / **`1/6`** / `494.6 -> 1242.0 MiB` / `0` sw / `0` / `0.0 MiB` (`651.1` used) | `1.35s` / **`6/6`** (`2.57–11.14s` load) / `343.4 -> 845.7 MiB` / `0` sw / `0` / `0.0 MiB` (`653.9` used) | **Firefox** (`-396.3 MiB` RSS at 6 tabs, `6/6` tabs) |
| **Lite Openbox `1024 MiB`** (`954 MiB`) | `1.22s` / **`2/6`** (`19.2s` at 2T) / `489.5 -> 810.7 MiB` / `236.2 MiB` sw / `0` / `0.0 MiB` (`371.7` used) | `1.27s` / **`6/6`** (`2.42–7.36s` load) / `326.5 -> 760.0 MiB` / `232.1 MiB` sw / `0` / `0.0 MiB` (`365.8` used) | **Firefox** (`6/6` tabs vs `2/6`, lower RSS) |
| **Lite Openbox `2048 MiB`** (`1960.5 MiB`) | `1.23s` / **`2/6`** (`17.2s` at 2T) / `512.2 -> 1287.1 MiB` / `0` sw / `0` / `0.0 MiB` (`490.8` used) | `1.26s` / **`6/6`** (`1.93–9.51s` load) / `456.0 -> 848.7 MiB` / `0` sw / `0` / `0.0 MiB` (`494.4` used) | **Firefox** (`-438.4 MiB` RSS at 6 tabs, `6/6` tabs) |
| **Lite Openbox `4096 MiB`** (`3908.8 MiB`) | `1.23s` / **`2/6`** (`16.4s` at 2T) / `515.0 -> 1291.2 MiB` / `0` sw / `0` / `0.0 MiB` (`582.7` used) | `1.28s` / **`6/6`** (`1.75–9.58s` load) / `455.7 -> 850.7 MiB` / `0` sw / `0` / `0.0 MiB` (`592.6` used) | **Firefox** (`-440.5 MiB` RSS at 6 tabs, `6/6` tabs) |

### Browser Findings & Honest Default-Browser Decision

- **Why Falkon struggled in QEMU:** Under QEMU TCG without GPU acceleration (`bochs-drm` + `llvmpipe`), QtWebEngine/Chromium (`falkon`) sustained `83–92%` CPU and failed to deliver `/beacon` page-load completions within `30s` past 1–2 tabs (`load_ms: null` at 4 and 6 tabs), while allocating `~1.24–1.29 GiB` RSS at 6 tabs on `2G/4G`.
- **Firefox behavior:** Completed `6/6` tabs cleanly at `1024 / 2048 / 4096 MiB` with `0` OOM kills and `0` crashes (`~232–278 MiB` ZRAM swap at `1024 MiB`, `0` swap at `2048/4096 MiB`).
- **Decision (Conservative):** Keep browsers `optional` in Lite ISOs until bare-metal GPU-accelerated browser testing is completed; **do not** auto-select Falkon as the Lite default browser based on the assumption that QtWebEngine is lighter than Firefox — measured QEMU evidence shows **Firefox** is currently more reliable and uses less RAM at `4–6` tabs, while `512–768 MiB` remains unsuitable for heavy multi-tab web browsing.

## Option B Architectural Decision & ZRAM Tier Policy

- **Option B retained:** `lite-lxqt` is primary for `>= 1 GiB` RAM (`Alpha` at `1024 / 2048 / 4096 MiB`); `lite` Openbox is retained for `512–768 MiB` (`Experimental` at `512 MiB`, `Development` at `768 MiB`). Neither edition is promoted to `Beta` or `Stable` without physical bare-metal qualification.
