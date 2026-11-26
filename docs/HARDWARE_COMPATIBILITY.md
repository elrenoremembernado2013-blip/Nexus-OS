# NEXUS OS Hardware Compatibility & Diagnostics Matrix (Phase 12.4)

**Foundation:** Linux Mint 22.3 (`noble` Ubuntu 24.04 LTS kernel & drivers, `x86_64`).
**Classification Policy:** NEXUS OS strictly distinguishes **Tested** (`verified in QEMU/OVMF`), **Supported** (`shipped kernel/driver in Ubuntu 24.04 LTS base`), **Partially tested**, **Detected** (`hardware/driver bound, unverified`), **Unknown**, and **Unsupported**. Linux hardware detection never implies bare-metal qualification.

## Automated Inventory & Privacy-Safe Diagnostics (`linux/hardware/`)

- **`linux/hardware/hw-compatibility-db.json`**: Declarative driver/bus readiness table (`virtio_blk`, `nvme`, `ahci`, `bochs-drm`, `virtio_gpu`, `i915`, `amdgpu`, `nouveau`, `iwlwifi`, `ath9k`/`ath10k`, `r8169`, `virtio_net`, `snd_hda_intel`, `snd_sof_pci`).
- **`linux/hardware/nexus-hw-inventory.sh` (`/usr/local/bin/nexus-hw-inventory`)**: Read-only probe of architecture, UEFI/Secure Boot state, CPU, RAM, block storage drivers, PCI GPUs/audio/NICs, Ethernet/Wi-Fi, Bluetooth, ALSA cards, DRM displays, `libinput` touchpads, USB vendor:product IDs, and missing-firmware `dmesg` hints.
- **`linux/hardware/nexus-hw-diagnostics.sh` (`/usr/local/bin/nexus-hw-diagnostics`)**: Safe live-session diagnostics (`--preview`, `--json`, `--export DIR`) adding `nmcli` connectivity, `rfkill` soft/hard blocks, `glxinfo -B`, `pactl` audio sinks, battery health (`energy_full` vs `energy_full_design`), and read-only `/sys/block/*/stat` metrics. **Never** flashes firmware, modifies partitions, formats drives, auto-installs drivers, or uploads data. Strictly omits serial numbers, MAC addresses, UUIDs, usernames, and external IPs, and requires user review before sharing exported files.

## Compatibility Classification Matrix

| Hardware / Feature | Classification | Evidence & Notes |
|---|---|---|
| `x86_64` Virtualized CPU (`qemu64`/`max` under `tcg`) | **Tested (QEMU)** | Verified across live ISO boots, `nexus-disk-install` UEFI/GPT installs, and 3-reboot installed boots (`lite`, `lite-lxqt`, `cinnamon`, `xfce`). |
| VirtIO block (`/dev/vda` GPT ESP + ext4), VirtIO NIC (`virtio-net-pci`), `bochs-drm` (`-vga std`), `virtio_gpu`, OVMF UEFI (`1280x800`) | **Tested (QEMU/OVMF)** | Verified in Run `45808626482` (`hw_summary`: `bochs-drm: tested`, `/dev/vda virtio_blk: tested`, `missing_fw_count: 0`) and Run `45722286627`. |
| Software OpenGL (`Mesa llvmpipe`) with Cinnamon Muffin | **Partially tested** | Works with `0` OOM, but `llvmpipe` imposes >30s initial frame latency under `-vga std` + `tcg`; `Openbox` & `LXQt+Openbox` bypass 3D compositor dependency. |
| NVMe / SATA AHCI / USB Mass Storage (`nvme`, `ahci`, `usb_storage`) | **Supported (untested on bare metal)** | Standard Ubuntu 24.04 kernel drivers; SMART/health tools never run destructively by default. |
| Intel `i915` & AMD `amdgpu` / RADV Vulkan | **Supported (untested on bare metal)** | Shipped in Mint 22.3 / Ubuntu 24.04; hardware acceleration, HDMI/DP hotplug, and S3/s2idle suspend require physical testing. |
| NVIDIA GPUs (`nouveau` vs `nvidia-driver`) | **Partially tested / Driver-dependent** | Requires proprietary driver install via Linux Mint **Driver Manager** (`mintdrivers`) for full Vulkan/Proton support. |
| Wi-Fi (`iwlwifi`, `ath9k`, `ath10k`, `rtw88`, `mt7921e`) & Bluetooth (`btusb`) | **Supported / Unknown by USB chipset** | Common PCIe chipsets supported via `linux-firmware`; arbitrary Broadcom/Realtek USB dongles remain **Unknown** until hardware-tested. |
| Audio (`snd_hda_intel`, `snd_sof_pci` / Chromebook MADOO) | **Supported / Hardware-dependent** | Standard HDA via PipeWire/ALSA; Chromebook SOF topology/UCM requires bare-metal validation (`docs/MADOO_CHROMEBOOK_QUALIFICATION.md`). |
| Touchpads (`libinput`), Batteries (`BAT*`), & Physical UEFI Secure Boot | **Detected / Partially tested** | Read-only sysfs/input probes implemented in `nexus-hw-diagnostics`; physical palm rejection, battery drain curves, and signed `shimx64.efi` Secure Boot enforcement untested on bare metal. |
| ARM64 / `i386` / Apple Silicon native | **Unsupported** | NEXUS OS targets `x86_64` (`amd64`) only. |
