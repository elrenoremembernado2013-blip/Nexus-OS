# NEXUS OS Hardware Compatibility & Diagnostics Matrix (Phase 12.5)

**Foundation:** Linux Mint 22.3 (`noble` Ubuntu 24.04 LTS kernel & drivers, `x86_64`).
**Classification Policy:** NEXUS OS strictly distinguishes:
- **`tested` (QEMU/OVMF only):** Verified in automated QEMU/OVMF virtual hardware tests (`bochs-drm`, `virtio_blk`, `virtio-net-pci`, `zram0`). Never presented as physical bare-metal proof.
- **`supported`:** Driver/firmware shipped in the Ubuntu 24.04 LTS / Linux Mint 22.3 baseline, **`NOT TESTED` on physical bare metal**.
- **`partially_tested` / `detected`:** Probed read-only by NEXUS hardware tools or exhibits hardware-dependent caveats (e.g., `llvmpipe` latency or proprietary driver requirements).
- **`unknown` / `unsupported`:** Unverified third-party/USB hardware or unsupported architectures (`ARM64`, `i386`, Apple Silicon).

## Hardware Database (`linux/hardware/hw-compatibility-db.json`, `schema_version: 2`)

Upgraded in Phase 12.5 to `schema_version: 2` across **15 hardware categories** (`cpu_x86_64`, `gpu_intel`, `gpu_amd`, `gpu_nvidia`, `wifi`, `bluetooth`, `audio_hda_sof`, `speakers_mics`, `touchpad_multitouch`, `usb_peripherals`, `battery_power`, `suspend_resume`, `internal_storage`, `uefi_boot`, `secure_boot_shim`) with per-entry fields:
- `device_driver`, `tested_editions`, `test_environment`, `status`, `known_issues`, `required_firmware`, `evidence`, and `last_updated_utc`.
- All bare-metal categories remain explicitly **`NOT TESTED`** on physical hardware (`test_environment: "none (bare-metal NOT TESTED)"`).

## Automated Read-Only Inventory, Diagnostics & Community Submission (`linux/hardware/`)

- **`linux/hardware/nexus-hw-inventory.sh` (`/usr/local/bin/nexus-hw-inventory`, `--json` / `--markdown`):**
  - Strictly **read-only** detection of architecture, UEFI/Secure Boot (`mokutil --sb-state`, `efivarfs`, signed `shimx64.efi`), DMI system/QEMU detection, CPU, RAM, block storage (`nvme`, `ahci`, `mmcblk`, `virtio_blk`, `zram`), PCI GPUs (`i915`, `amdgpu`, `nouveau`, `nvidia`, `bochs-drm`, `virtio_gpu`), Wi-Fi & Bluetooth (`iwlwifi`, `ath9k`, `ath10k`, `rtw88`, `mt7921e`, `btusb`), Audio/SOF (`snd_hda_intel`, `snd_sof_pci`, ALSA cards, playback/capture streams, `pactl`/`wpctl`), touchpads/multi-touch (`libinput` + `/proc/bus/input/devices`), USB peripherals (`vendor:product` only), battery/power (`BAT*`), suspend modes (`/sys/power/state`, `/sys/power/mem_sleep`), missing-firmware `dmesg` hints, and a 10-row `component_matrix`.
- **`linux/hardware/nexus-hw-diagnostics.sh` (`/usr/local/bin/nexus-hw-diagnostics`, `--preview` / `--json` / `--export DIR` / `--contribute-template`):**
  - Safe live-session diagnostics adding `nmcli` connectivity, `rfkill` soft/hard blocks, `glxinfo -B`, `pactl` sinks/sources, battery health (`energy_full` vs `energy_full_design`), and read-only `/sys/block/*/stat` metrics.
  - **`--contribute-template`:** Generates a privacy-redacted JSON submission template matching `hw-compatibility-db.json` `schema_version: 2` for community bare-metal reports (with `bare_metal_disclaimer` and placeholder `checklist` items to fill out manually after human verification).
  - **Safety & Privacy Guarantees:** Never flashes firmware, modifies partitions, formats drives, alters bootloaders/Secure Boot, installs drivers, runs destructive SMART/storage tests, or auto-uploads diagnostics. Strictly omits serial numbers, MAC addresses, UUIDs, hostnames/usernames, and external IPs.

## Compatibility Classification Matrix

| Hardware / Feature | Classification | Bare-Metal Status | Evidence & Notes |
|---|---|---|---|
| `x86_64` Virtualized CPU (`qemu64`/`max` under `tcg`) | **Tested (QEMU)** | `NOT TESTED` | Verified in CI QEMU/OVMF across `lite`, `lite-lxqt`, `cinnamon`, and `xfce` (`45876350800`). |
| VirtIO block (`/dev/vda` GPT ESP + ext4 / LUKS2), VirtIO NIC (`virtio-net-pci`), `bochs-drm`, `virtio_gpu`, OVMF UEFI | **Tested (QEMU/OVMF)** | `NOT TESTED` | Verified in `45876350800` (`hw_summary`: `bochs-drm: tested`, `/dev/vda virtio_blk: tested`, `missing_fw_count: 0`, plus LUKS2 cold-boot unlock). |
| Software OpenGL (`Mesa llvmpipe`) with Cinnamon & QtWebEngine (`falkon`) | **Partially tested (QEMU)** | `NOT TESTED` | Cinnamon works at `4G` with `>30s` initial frame warm-up under `-vga std` + `tcg`; `falkon` stalls on multi-tab benchmarks under `llvmpipe` while `firefox` completes `6/6` tabs. |
| Intel `i915` & AMD `amdgpu` / RADV Vulkan | **Supported** | `NOT TESTED` | Shipped in Mint 22.3 / Ubuntu 24.04; hardware compositing, browser GPU decode, HDMI/DP hotplug, and suspend require physical testing. |
| NVIDIA GPUs (`nouveau` vs `nvidia-driver`) | **Partially tested / Driver-dependent** | `NOT TESTED` | Proprietary driver requires Mint **Driver Manager** (`mintdrivers`); Wayland/Xorg/Vulkan behavior unverified on hardware. |
| Wi-Fi (`iwlwifi`, `ath9k`, `ath10k`, `rtw88`, `mt7921e`) & Bluetooth (`btusb`) | **Supported / Unknown by USB chipset** | `NOT TESTED` | Common PCIe chipsets supported via `linux-firmware`; arbitrary Broadcom/Realtek USB dongles remain `unknown` until bare-metal tested. |
| Audio (`snd_hda_intel`, `snd_sof_pci` / Chromebook MADOO), Speakers & Mics | **Supported / Hardware-dependent** | `NOT TESTED` | HDA + PipeWire/ALSA shipped; Chromebook SOF UCM/topology requires physical validation (`docs/MADOO_CHROMEBOOK_QUALIFICATION.md`). |
| Touchpads / Multi-touch (`libinput`), USB Peripherals, Battery (`BAT*`), S3 / `s2idle` Suspend & Resume | **Detected / Supported** | `NOT TESTED` | Read-only probes implemented in `nexus-hw-inventory` / `nexus-hw-diagnostics`; physical wake, palm rejection, and drain curves untested. |
| Internal NVMe / SATA AHCI / eMMC & Physical UEFI + Signed `shimx64.efi` Secure Boot | **Supported** | `NOT TESTED` | Installer supports `/dev/nvme*`, `/dev/mmcblk*`, `/dev/sd*` and copies signed `shimx64.efi`; Secure Boot enforced boot on physical OEM firmware is untested. |
| ARM64 / `i386` / Apple Silicon native | **Unsupported** | `Unsupported` | NEXUS OS targets `x86_64` (`amd64`) only. |
