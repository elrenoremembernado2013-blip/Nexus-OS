# NEXUS OS Release Readiness Dashboard (Phase 12.5)

**Current Release Stage:** `Development` / `Alpha` (All **11/11 jobs** in `Build NEXUS ISOs and QEMU RAM Matrix` run [`45876350800`](https://github.com/elrenoremembernado2013-blip/Nexus-OS/actions/runs/45876350800) and `NEXUS checks and browser preview` run [`45876358426`](https://github.com/elrenoremembernado2013-blip/Nexus-OS/actions/runs/45876358426) passed on commit `b4879cb`, covering all 4 editions, Phase 12.5 manual/recovery/LUKS2 installer qualification, and Falkon vs Firefox multi-tab benchmarks).
**Stable Release Decision:** **HOLD — Not eligible for `Beta` or `Stable`.** QEMU/OVMF passes do not substitute for physical bare-metal hardware qualification (Intel/AMD/NVIDIA GPUs, Wi-Fi/Bluetooth, SOF audio, touchpads, battery/suspend, physical NVMe/eMMC, and signed `shimx64.efi` Secure Boot all remain **`NOT TESTED`** on physical computers).

## Edition Maturity Classification Matrix

| Edition | Target RAM | QEMU/OVMF Status (`45876350800`) | Physical Bare-Metal Status | Assigned Maturity |
|---|---|---|---|---|
| **NEXUS Standard (Cinnamon)** | `2048 MiB` floor / `4096 MiB` rec | `3/3` live (`4G`), `2/2` inst (`4G`), `3/3` ISO-free boots (`4G` & `2G`), `persist=true` | `NOT TESTED` | `Development` (`2G`) / `Alpha` (`4G`) |
| **MADOO Xfce Baseline** | `4096 MiB` | `3/3` live, `2/2` inst (`1063.4s`), `3/3` ISO-free boots, `persist=true` | `NOT TESTED` | `Alpha` |
| **NEXUS Lite LXQt** (`lite-lxqt`) | `1024 MiB+` primary (`512–768 MiB` fallback) | `512/768/1024/2048/4096M` live+ZRAM PASS; `512/768/1024/2048M` inst + `12/12` boots PASS; manual, recovery, LUKS2 cold-boot unlock & Firefox `6`-tab `1G/2G/4G` PASS | `NOT TESTED` | `Experimental` (`512M`) / `Development` (`768M`) / `Alpha` (`1G+`) |
| **NEXUS Lite Openbox** (`lite`) | `512–768 MiB` fallback / `1024 MiB+` | `512/768/1024/2048/4096M` live+ZRAM PASS; `1024M` inst + `3/3` boots PASS; Firefox `6`-tab `1G/2G/4G` PASS | `NOT TESTED` | `Experimental` (`512M`) / `Development` (`768M`) / `Alpha` (`1G+`) |

## Phase 12.5 Separated Installer & LUKS2 Qualification (`lite-lxqt`, `45876350800`)

| Test Stream | Encryption | Key Verification Result |
|---|---|---|
| **Unencrypted Guided (`lite`, `lite-lxqt`, `cinnamon`, `xfce`)** | None (`GPT + ext4`) | **PASS (QEMU):** All 4 editions installed to `/dev/vda` and completed `3/3` ISO-free boots with `persist=true`, `0` failed systemd units, `0` `journalctl -p err`. |
| **Unencrypted Manual Partitioning (`lite-lxqt`)** | None (`GPT + ext4`) | **PASS (QEMU):** `1700.1s`; `/dev/vda3` (`nexus_data`) preserved before & after installed boot (`extra_partition_preserved_after_boot: true`, `0` failed units). |
| **Interrupted-Install Recovery (`lite-lxqt`)** | None (`GPT + ext4`) | **PASS (QEMU):** Unconfirmed run refused (`refused_without_confirm: true`); stale `/mnt/nexus-install-target` mount detached & cleanly installed (`1674.4s`, `0` failed units). |
| **Separate LUKS2 Cold-Boot Unlock (`lite-lxqt`)** | **LUKS2 (`argon2id`, `aes-xts-plain64`)** | **PASS (QEMU):** `1728.9s`; `crypto_luks_blkid: true`, `crypttab_ok: true`, `luks_recovery_guide_ok: true`; `ttyS0` rejected wrong passphrase (`wrong_passphrase_rejected: true`), unlocked cleanly with valid ephemeral passphrase (`prompts_count: 3`), completed `2` LUKS cold/reboot cycles (`boot1_from_luks: true`, `boot2_from_luks: true`, `boot2_persistence_verified: true`). |
| **Ubiquity GUI Click-Through / Dual-Boot / Legacy BIOS** | N/A | **`NOT TESTED`** (only Ubiquity GTK launch verified). |

## Phase 12.5 Browser Benchmark Summary (`1024 / 2048 / 4096 MiB`, QEMU TCG)

- **Firefox (`1024 / 2048 / 4096 MiB`):** Completed **`6/6` stable tabs** across every tier on both `lite-lxqt` (`775.2 / 897.9 / 845.7 MiB` RSS) and `lite` Openbox (`760.0 / 848.7 / 850.7 MiB` RSS) with `0` OOMs, `0` crashes, `1.75–3.04s` multi-tab load times, and `0.0 MiB` post-close RSS.
- **Falkon (`1024 / 2048 / 4096 MiB`):** Used **`1242.0–1291.2 MiB` RSS** at 6 tabs on `2G/4G` (`805.2–810.7 MiB` at `1G`) and stalled on `/beacon` completion past `1–2` tabs under TCG `llvmpipe` (`tabs_ok: 1` LXQt, `tabs_ok: 2` Openbox).
- **Policy:** Keep browsers `optional` in Lite ISOs until bare-metal GPU tests run; `512–768 MiB` remains unsuitable for multi-tab browsing; on `>= 1 GiB` tiers, measured evidence favors **Firefox** over Falkon.

## Remaining Gates Before `Beta` / `Stable`

1. Bare-metal hardware qualification (`docs/HARDWARE_COMPATIBILITY.md`) across Intel, AMD, NVIDIA, Wi-Fi/BT, SOF audio, touchpads, battery, suspend/resume, internal NVMe/eMMC, and enforced UEFI Secure Boot (`NOT TESTED`).
2. Manual interactive Ubiquity GUI partitioning, dual-boot resize, and Ubiquity LUKS+LVM testing (`NOT TESTED`).
3. Physical GPU-accelerated browser verification on `1G / 2G / 4G` targets (`NOT TESTED`).
