# NEXUS OS Release Readiness Dashboard (Phase 13.0)

**Current Release Stage:** `Development` / `Alpha` (Verified Phase 13.0 QEMU/OVMF baseline on commit `b5594a2`: all **12/12 jobs** in `Build NEXUS ISOs and QEMU RAM Matrix` run [`45919673389`](https://github.com/elrenoremembernado2013-blip/Nexus-OS/actions/runs/45919673389) and `NEXUS checks and browser preview` run [`45919678771`](https://github.com/elrenoremembernado2013-blip/Nexus-OS/actions/runs/45919678771) passed, verifying Stage A/B bare-metal qualification tooling, dual-boot `--keep-efi` + NTFS preservation, and enforced OVMF Secure Boot on `lite-lxqt` alongside all 4 edition ISO builds and RAM matrices).
**Stable Release Decision:** **HOLD — Not eligible for `Beta` or `Stable`.** QEMU/OVMF passes do not substitute for physical bare-metal hardware qualification (Intel/AMD/NVIDIA GPUs, Wi-Fi/Bluetooth, SOF audio, touchpads, battery/suspend, physical NVMe/eMMC, physical-GPU browser runs, and physical OEM Secure Boot all remain **`NOT TESTED`** on physical computers).

## Edition Maturity Classification Matrix

| Edition | Target RAM | QEMU/OVMF Status (`45919673389`) | Physical Bare-Metal Status | Assigned Maturity |
|---|---|---|---|---|
| **NEXUS Standard (Cinnamon)** | `2048 MiB` floor / `4096 MiB` rec | `3/3` live (`4G`), `2/2` inst (`4G`, `1585.0s`), `1/1` live & `1/1` inst (`2G`, `1541.5s`), `3/3` ISO-free boots (`4G` & `2G`), `persist=true` | `NOT TESTED` | `Development` (`2G`) / `Alpha` (`4G`) |
| **MADOO Xfce Baseline** | `4096 MiB` | `3/3` live, `2/2` inst (`1687.9s`), `3/3` ISO-free boots, `persist=true` | `NOT TESTED` | `Alpha` |
| **NEXUS Lite LXQt** (`lite-lxqt`) | `1024 MiB+` primary (`512–768 MiB` fallback) | `512/768/1024/2048/4096M` live+ZRAM PASS; `512/768/1024/2048M` inst + `12/12` boots PASS; manual, recovery, LUKS2 cold-boot unlock, dual-boot `--keep-efi` + NTFS, enforced OVMF Secure Boot, & Firefox `6`-tab `1G/2G/4G` PASS | `NOT TESTED` | `Experimental` (`512M`) / `Development` (`768M`) / `Alpha` (`1G+`) |
| **NEXUS Lite Openbox** (`lite`) | `512–768 MiB` fallback / `1024 MiB+` | `512/768/1024/2048/4096M` live+ZRAM PASS; `1024M` inst (`1213.7s`) + `3/3` boots PASS; Firefox `6`-tab `1G/2G/4G` PASS | `NOT TESTED` | `Experimental` (`512M`) / `Development` (`768M`) / `Alpha` (`1G+`) |

## Installer, Dual-Boot & Secure Boot Qualification Matrix

| Test Stream | Environment | Status | Notes |
|---|---|---|---|
| **Unencrypted Guided (`lite`, `lite-lxqt`, `cinnamon`, `xfce`)** | Disposable QEMU/OVMF | **PASS (`45919673389`)** | All 4 editions installed to `/dev/vda` and completed `3/3` ISO-free boots (`persist=true`, `0` failed units). |
| **Unencrypted Manual Partitioning (`lite-lxqt`)** | Disposable QEMU/OVMF | **PASS (`45919673389`)** | `1669.4s`; `/dev/vda3` preserved during & after installed boot (`0` failed units). |
| **Interrupted-Install Recovery (`lite-lxqt`)** | Disposable QEMU/OVMF | **PASS (`45919673389`)** | Unconfirmed run refused; stale mounted `/mnt/nexus-install-target` cleanly recovered (`1693.6s`). |
| **Separate LUKS2 Cold-Boot Unlock (`lite-lxqt`)** | Disposable QEMU/OVMF | **PASS (`45919673389`)** | Wrong passphrase rejected (`prompts_count: 3`), valid ephemeral passphrase unlocked `boot1` & `boot2` (`persist=true`, `1867.5s`). |
| **Simulated Dual-Boot / NTFS / `--keep-efi` (`--dualboot-test`)** | Disposable QEMU/OVMF | **PASS (`45919673389`)** | `dualboot_preflight_detected: true`, `dualboot_efi_preserved_after_boot: true`, `dualboot_os_part_preserved_after_boot: true`, `0` failed units (`lite-lxqt`). |
| **Enforced OVMF Secure Boot Signed Chain (`--secure-boot-test`)** | Disposable QEMU/OVMF SB | **PASS (`45919673389`)** | Installed `lite-lxqt` booted under `OVMF_CODE_4M.secboot.fd` + `OVMF_VARS_4M.ms.fd` (`smm=on`) with `secure_boot_state: "enabled"`, `efi_boot_ok: true`, `0` failed units. |
| **Physical-GPU Browser Qualification (`cinnamon`, `xfce`, `lite`, `lite-lxqt`)** | Bare Metal | **`NOT TESTED`** | Tooling shipped (`nexus-browser-qualify`, WebGL + HTML5 video probes); physical GPU runs awaited. |
| **Ubiquity GUI Click-Through & Legacy BIOS / MBR** | Interactive / BIOS | **`NOT TESTED`** | Ubiquity GTK window launch verified; manual wizard click-through & Legacy BIOS/MBR remain untested/unsupported in CLI path. |

## Remaining Gates Before `Beta` / `Stable`

1. Bare-metal Stage A & Stage B hardware qualification (`docs/HARDWARE_TESTING_GUIDE.md`) across Intel, AMD, NVIDIA, Wi-Fi/BT, SOF audio, touchpads, battery, suspend/resume, internal NVMe/eMMC, and physical OEM UEFI Secure Boot (`NOT TESTED`).
2. Physical GPU-accelerated browser verification across all 4 editions (`NOT TESTED`) and manual Ubiquity GUI wizard walkthrough on spare test disks (`NOT TESTED`).
3. Community hardware compatibility review via `nexus-hw-diagnostics --contribute-template` (human review mandatory; zero automatic uploads).
