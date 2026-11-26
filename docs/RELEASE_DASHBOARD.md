# NEXUS OS Release Readiness Dashboard (Phase 12.4)

**Current Release Stage:** `Development` / `Alpha` (Parallel `NEXUS Lite Openbox` vs `NEXUS Lite LXQt` ISO builds, zero test-agent leaks, `512 MB`–`4 GB` QEMU/OVMF `300s`-idle comparison, disposable `/dev/vda` installs, 3-reboot ISO-free persistence, ZRAM pressure tests, hardware inventory, and security audits all passed across **6/6 jobs** in GitHub Actions run [`45808626482`](https://github.com/elrenoremembernado2013-blip/Nexus-OS/actions/runs/45808626482), commit `d537b2c`, building on Phase 12.3 run [`45722286627`](https://github.com/elrenoremembernado2013-blip/Nexus-OS/actions/runs/45722286627)).
**Stable Release Decision:** **HOLD — Not ready for `Stable` release.** Physical bare-metal hardware testing (Wi-Fi/Bluetooth/audio/touchpads/suspend/Secure Boot), interactive Ubiquity GUI partitioning & LUKS unlock walkthroughs, and real-world browser/desktop stress workloads remain untested outside QEMU.

## Phase 12.4 Lite Openbox vs. LXQt Comparison Matrix (Run `45808626482`, `d537b2c`, `accel=tcg`)

| Edition | RAM Tier | ISO Build & Test Leaks | Live ISO Boots | Ubiquity GTK UI | Disposable `/dev/vda` Install | Installed Boots (No ISO: 2x Warm + 1x Cold) | Persistence & Errors | Live Idle / Installed Idle RAM (`Swap`) | Edition Stage Assessment |
|---|---|---|---|---|---|---|---|---|---|
| **NEXUS Lite (Openbox)** | `512 MiB` | PASS (`2.84 GB`, 0 leaks) | `2/3` PASS | Skipped (`<850M`) | (`2/2` in `12.3`) | (`3/3` in `12.3`) | (`0` OOM) | `240 MiB` (`103` sw) live | **Experimental** (`512M` live tight: `2/3` in `12.4`) |
| **NEXUS Lite (LXQt)** | `512 MiB` | PASS (`2.87 GB`, 0 leaks) | `3/3` PASS (`96.56%`) | Skipped (`<850M`) | `2/2` PASS (`1210.8s`) | `3/3` PASS (`vda`, `no_iso`, `96.41%`) | `persist=true`, `0` err, `0` fail | `251 MiB` (`160` sw) / `275–287 MiB` | **Experimental** (heavy ZRAM paging at idle) |
| **NEXUS Lite (Openbox)** | `768 MiB` | PASS | `1/1` PASS (`99.96%`) | Skipped (`<850M`) | (`1/1` in `12.3`) | (`3/3` in `12.3`) | `0` OOM | `366 MiB` (`39` sw) live | **Development / Alpha** |
| **NEXUS Lite (LXQt)** | `768 MiB` | PASS | `1/1` PASS (`96.56%`) | Skipped (`<850M`) | `1/1` PASS (`1229.4s`) | `3/3` PASS (`vda`, `no_iso`, `96.41%`) | `persist=true`, `0` err, `0` fail | `405 MiB` (`93` sw) / `466–476 MiB` | **Development / Alpha** |
| **NEXUS Lite (Openbox)** | `1024 MiB` | PASS | `3/3` PASS (`99.96%`) | PASS (`99.96%`) | `1/1` PASS (`1554.5s`) | `3/3` PASS (`vda`, `no_iso`, `99.99%`) | `persist=true`, `0` err, `0` fail | `459 MiB` (`1` sw) / `474–485 MiB` | **Alpha** (Ultra-minimal `512–1024M` option) |
| **NEXUS Lite (LXQt)** | `1024 MiB` | PASS | `3/3` PASS (`95.92%`) | PASS (`95.92%`) | `1/1` PASS (`1154.0s`) | `3/3` PASS (`vda`, `no_iso`, `95.87%`) | `persist=true`, `0` err, `0` fail | `521 MiB` (`10` sw) / `549–564 MiB` | **Alpha** (Recommended min practical LXQt tier) |
| **NEXUS Lite (Openbox)** | `2048 MiB` | PASS | `1/1` PASS (`99.98%`) | PASS (`99.98%`) | (`1/1` in `12.3`) | (`3/3` in `12.3`) | `0` OOM | `457 MiB` (`2` sw) live | **Alpha** |
| **NEXUS Lite (LXQt)** | `2048 MiB` | PASS | `1/1` PASS (`95.92%`) | PASS (`95.92%`) | `1/1` PASS (`1189.3s`) | `3/3` PASS (`vda`, `no_iso`, `95.87%`) | `persist=true`, `0` err, `0` fail | `540 MiB` (`1` sw) / `558–578 MiB` | **Alpha** (Comfortable Lite tier) |
| **NEXUS Lite (Openbox)** | `4096 MiB` | PASS | `1/1` PASS (`99.96%`) | PASS (`99.96%`) | N/A | N/A | `0` OOM | `568 MiB` (`0` sw) live | **Alpha** |
| **NEXUS Lite (LXQt)** | `4096 MiB` | PASS | `1/1` PASS (`95.93%`) | PASS (`95.93%`) | N/A | N/A | `0` OOM | `639 MiB` (`0` sw) live | **Alpha** |
| **NEXUS Standard (Cinnamon)** | `2048 / 4096 MiB` | PASS (`3.09 GB`, `12.3`) | `1/1` & `3/3` (`12.3`) | PASS (`96.63%`) | `3/3` (`12.3`) | `6/6` (`12.3`) | `persist=true` | `1079–1103 MiB` (`4096M` Boot 1) | **Development** (`2G` floor) / **Alpha** (`4G`) |
| **MADOO Xfce** | `4096 MiB` | PASS (`3.03 GB`, `12.3`) | `3/3` (`12.3`) | PASS (`98.11%`) | `2/2` (`12.3`) | `3/3` (`12.3`) | `persist=true` | `858–907 MiB` (`4096M`) | **Alpha** (Hardware-dependent on bare metal) |

## Phase 12.4 Live Hardware & Security Probes Inside QEMU

- **`nexus-hw-inventory` (`hw_summary`):** Reported `bochs-drm: tested`, `/dev/vda (virtio_blk): tested`, `/dev/zram0 (unknown): detected`, `missing_fw_count: 0` across all `lite` and `lite-lxqt` VMs.
- **`nexus-security-audit` (`sec_summary`):** Reported `5 PASS, 2 WARN, 0 FAIL` inside live QEMU sessions (`0` test leaks, `0` `trusted=yes`, `0` failed checks) and `2 PASS, 0 WARN, 0 FAIL` in CI `--repo-only --strict`.
- **Remaining Blockers Before `Beta` / `Stable`:** Real bare-metal laptop/Chromebook testing (`docs/HARDWARE_COMPATIBILITY.md`), interactive Ubiquity LUKS+LVM unlock testing (`docs/INSTALLER_ARCHITECTURE.md`), and real-world multi-tab browser workload testing.

See `docs/NEXUS_LITE.md`, `docs/STANDARD_VS_LITE_EDITIONS.md`, `docs/HARDWARE_COMPATIBILITY.md`, `docs/SECURITY_AND_PRIVACY.md`, and `docs/INSTALLER_ARCHITECTURE.md` for detailed tables and reproduction steps.
