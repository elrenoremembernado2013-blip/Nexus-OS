# NEXUS OS Release Readiness Dashboard (Phase 13.0)

**Current Release Stage:** `Development` / `Alpha` (Verified Phase 12.5 baseline: all **11/11 jobs** in `Build NEXUS ISOs and QEMU RAM Matrix` run [`45876350800`](https://github.com/elrenoremembernado2013-blip/Nexus-OS/actions/runs/45876350800) and `NEXUS checks and browser preview` run [`45876358426`](https://github.com/elrenoremembernado2013-blip/Nexus-OS/actions/runs/45876358426) passed on commit `b4879cb`; Phase 13.0 adds the bare-metal Stage A/B qualification toolkit, physical-GPU browser/WebGL/video runner, dual-boot + Secure Boot CI checks, and `docs/HARDWARE_TESTING_GUIDE.md`).
**Stable Release Decision:** **HOLD — Not eligible for `Beta` or `Stable`.** QEMU/OVMF passes do not substitute for physical bare-metal hardware qualification (Intel/AMD/NVIDIA GPUs, Wi-Fi/Bluetooth, SOF audio, touchpads, battery/suspend, physical NVMe/eMMC, and physical OEM Secure Boot all remain **`NOT TESTED`** on physical computers).

## Edition Maturity Classification Matrix

| Edition | Target RAM | QEMU/OVMF Status (`45876350800`) | Physical Bare-Metal Status | Assigned Maturity |
|---|---|---|---|---|
| **NEXUS Standard (Cinnamon)** | `2048 MiB` floor / `4096 MiB` rec | `3/3` live (`4G`), `2/2` inst (`4G`), `3/3` ISO-free boots (`4G` & `2G`), `persist=true` | `NOT TESTED` | `Development` (`2G`) / `Alpha` (`4G`) |
| **MADOO Xfce Baseline** | `4096 MiB` | `3/3` live, `2/2` inst (`1063.4s`), `3/3` ISO-free boots, `persist=true` | `NOT TESTED` | `Alpha` |
| **NEXUS Lite LXQt** (`lite-lxqt`) | `1024 MiB+` primary (`512–768 MiB` fallback) | `512/768/1024/2048/4096M` live+ZRAM PASS; `512/768/1024/2048M` inst + `12/12` boots PASS; manual, recovery, LUKS2 cold-boot unlock & Firefox `6`-tab `1G/2G/4G` PASS | `NOT TESTED` | `Experimental` (`512M`) / `Development` (`768M`) / `Alpha` (`1G+`) |
| **NEXUS Lite Openbox** (`lite`) | `512–768 MiB` fallback / `1024 MiB+` | `512/768/1024/2048/4096M` live+ZRAM PASS; `1024M` inst + `3/3` boots PASS; Firefox `6`-tab `1G/2G/4G` PASS | `NOT TESTED` | `Experimental` (`512M`) / `Development` (`768M`) / `Alpha` (`1G+`) |

## Installer, Dual-Boot & Secure Boot Qualification Matrix

| Test Stream | Environment | Status | Notes |
|---|---|---|---|
| **Unencrypted Guided (`lite`, `lite-lxqt`, `cinnamon`, `xfce`)** | Disposable QEMU/OVMF | **PASS (`45876350800`)** | All 4 editions installed to `/dev/vda` and completed `3/3` ISO-free boots (`persist=true`, `0` failed units). |
| **Unencrypted Manual Partitioning (`lite-lxqt`)** | Disposable QEMU/OVMF | **PASS (`45876350800`)** | `1700.1s`; `/dev/vda3` preserved during & after installed boot (`0` failed units). |
| **Interrupted-Install Recovery (`lite-lxqt`)** | Disposable QEMU/OVMF | **PASS (`45876350800`)** | Unconfirmed run refused; stale mounted `/mnt/nexus-install-target` cleanly recovered (`1674.4s`). |
| **Separate LUKS2 Cold-Boot Unlock (`lite-lxqt`)** | Disposable QEMU/OVMF | **PASS (`45876350800`)** | Wrong passphrase rejected (`prompts_count: 3`), valid ephemeral passphrase unlocked `boot1` & `boot2` (`persist=true`). |
| **Simulated Dual-Boot / NTFS / `--keep-efi` (`--dualboot-test`)** | Disposable QEMU/OVMF | **Implemented (CI Pending)** | Added in Phase 13.0 (`run-phase130-tests.sh`); status `NOT TESTED` until Phase 13.0 CI run finishes. |
| **Enforced OVMF Secure Boot Signed Chain (`--secure-boot-test`)** | Disposable QEMU/OVMF SB | **Implemented (CI Pending)** | Added `shim-signed`/`grub-efi-amd64-signed`/`mokutil` + `OVMF_CODE_4M.secboot.fd` test; `NOT TESTED` until Phase 13.0 CI finishes. |
| **Physical-GPU Browser Qualification (`cinnamon`, `xfce`, `lite`, `lite-lxqt`)** | Bare Metal | **`NOT TESTED`** | Tooling shipped (`nexus-browser-qualify`, WebGL + HTML5 video probes); physical GPU runs awaited. |
| **Ubiquity GUI Click-Through & Legacy BIOS / MBR** | Interactive / BIOS | **`NOT TESTED`** | Ubiquity GTK window launch verified; manual wizard click-through & Legacy BIOS/MBR remain untested. |

## Remaining Gates Before `Beta` / `Stable`

1. Pass Phase 13.0 disposable-QEMU dual-boot & enforced OVMF Secure Boot CI checks across the updated ISOs.
2. Bare-metal Stage A & Stage B hardware qualification (`docs/HARDWARE_TESTING_GUIDE.md`) across Intel, AMD, NVIDIA, Wi-Fi/BT, SOF audio, touchpads, battery, suspend/resume, internal NVMe/eMMC, and OEM UEFI Secure Boot (`NOT TESTED`).
3. Physical GPU-accelerated browser verification across all 4 editions (`NOT TESTED`) and manual Ubiquity GUI wizard walkthrough on spare test disks (`NOT TESTED`).
