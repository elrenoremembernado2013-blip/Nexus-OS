# NEXUS OS Hardware Compatibility & Diagnostics Matrix (Phase 13.1)

**Foundation:** Linux Mint 22.3 (`noble` Ubuntu 24.04 LTS kernel & drivers, `x86_64`).
**Classification Policy:** NEXUS OS strictly separates QEMU/OVMF virtual verification from physical bare-metal qualification:
- **`tested` (QEMU/OVMF only):** Verified in automated QEMU/OVMF virtual hardware tests (`bochs-drm`, `virtio_blk`, `virtio-net-pci`, `zram0`). Never presented as physical bare-metal proof.
- **`supported`:** Driver/firmware shipped in the Ubuntu 24.04 LTS / Linux Mint 22.3 baseline, **`NOT TESTED` on physical bare metal**.
- **`partially_tested` / `detected`:** Probed read-only by NEXUS hardware tools or exhibits hardware-dependent caveats (e.g., `llvmpipe` latency or proprietary driver requirements).
- **`unknown` / `unsupported`:** Unverified third-party/USB hardware or unsupported architectures (`ARM64`, `i386`, Apple Silicon).

## Hardware Qualification Toolkit (`linux/hardware/`, Packaged in All 4 Editions)

All 4 NEXUS OS editions (`cinnamon`, `xfce`, `lite`, `lite-lxqt`) package `/usr/local/share/nexus-os/hardware/hw-compatibility-db.json` (`schema_version: 2`, 16 categories) and the non-destructive qualification suite:

1. **`linux/hardware/nexus-hw-inventory.sh` (`/usr/local/bin/nexus-hw-inventory`, `--json` / `--markdown`):**
   - Strictly **read-only** detection of CPU architecture/category (`intel_x86_64` / `amd_x86_64` / `virtual_or_emulated`), RAM, `environment` (`is_virtual_machine`, `is_chromebook_board`), `graphics_qualification` (PCI GPU drivers + vendor names, `/dev/dri` nodes, Mesa DRI, `glxinfo -B`, Vulkan ICDs + `vulkaninfo --summary`, `gpu_driver_errors`, explicitly separating `genuine_hardware_gpu_driver_bound` from `software_llvmpipe_or_virtual`), `network_qualification` (NetworkManager, Wi-Fi HW/radio state, Bluetooth adapters — **zero SSIDs, BSSIDs, passwords, MACs, or IPs**), `audio` (ALSA cards, HDA/SOF `codecs`, playback/capture counts, PipeWire/PulseAudio server, SOF modules + `/lib/firmware/intel/sof*`, `audio_service_errors` — **zero audio capture**), `touchpads` & sanitized `input_devices`, `usb_controllers` & peripheral `category` classification (`vendor:product` only, zero serials), `storage_controllers` (`nvme`/`sata_ahci`/`scsi`) & `drive_type` (`nvme_ssd`/`emmc_or_sd`/`sata_ssd`/`sata_hdd`/`virtio_virtual_disk`), `power_management` (`BAT*`, `AC*`, `upower`, `power-profiles-daemon`, `cpu_scaling_governor`), `suspend_capabilities` (exposed states only, `tested: false`), and `secure_boot_chain` (`efivars`/`mokutil`, `shimx64.efi`, `grubx64.efi`, `vmlinuz-*`, `sbverify` PE signature checks).
2. **`linux/hardware/nexus-hw-diagnostics.sh` (`/usr/local/bin/nexus-hw-diagnostics`, `--preview` / `--json` / `--export DIR` / `--contribute-template`):**
   - Adds `rfkill` block state, `service_states` (`NetworkManager`, `wpa_supplicant`, `bluetooth`, `upower`, `pipewire`, `wireplumber`, `pulseaudio`), `glxinfo -B`, `pactl` sink status, read-only `/sys/block/*/stat`, an automated `privacy_audit` self-check confirming `0` unredacted MACs/UUIDs/IPv4s/IPv6s/hostnames/usernames, and `--contribute-template` (`schema_version: 2`, `compatibility_status`, `untested_components`, `evidence_references`, `human_review_required: true`, `auto_upload: false`).
3. **`linux/hardware/nexus-hw-qualify.sh` (`/usr/local/bin/nexus-hw-qualify`) & `docs/HARDWARE_TESTING_GUIDE.md`:**
   - **Stage A (default):** Read-only preflight, environment/Chromebook safety check, and privacy-audited export.
   - **Stage B (`--run-test <name> --confirm-test <name>`):** Individually confirmed checks (`gpu`, `wifi`, `bluetooth`, `audio-output`, `microphone` [metadata only, never records], `touchpad`, `usb`, `battery`, `suspend` [explicit opt-in only], `all-safe` [excludes `suspend`]) with pre-run safety explanations (`WILL DO` / `WILL NOT DO`) and Stage B `privacy_audit` self-check.
4. **`linux/hardware/nexus-browser-qualify.sh` (`/usr/local/bin/nexus-browser-qualify`):**
   - Standalone physical-GPU browser benchmark wrapper (`startup`, load ms, WebGL/renderer, HTML5 video codecs `H.264`/`VP9`/`VP8`/`AV1`, RSS/CPU/ZRAM/swap across `1–6` tabs, post-close recovery).

## Compatibility Classification Matrix

| Hardware / Feature | Classification | Bare-Metal Status | Evidence & Notes |
|---|---|---|---|
| `x86_64` Virtualized CPU (`qemu64`/`max` under `tcg`) | **Tested (QEMU)** | `NOT TESTED` | Verified in CI QEMU/OVMF across `lite`, `lite-lxqt`, `cinnamon`, and `xfce` (`45919673389`). |
| VirtIO block (`/dev/vda` GPT ESP + ext4 / LUKS2 / simulated NTFS+ESP), VirtIO NIC (`virtio-net-pci`), `bochs-drm`, `virtio_gpu`, OVMF UEFI + Enforced OVMF Secure Boot | **Tested (QEMU/OVMF)** | `NOT TESTED` | Verified in `45919673389` (`hw_summary`: `bochs-drm: tested`, `/dev/vda virtio_blk: tested`, `missing_fw_count: 0`, LUKS2 cold-boot unlock, dual-boot `--keep-efi`, and `lite-lxqt` enforced OVMF Secure Boot `secure_boot_state=enabled`). |
| Software OpenGL (`Mesa llvmpipe`) with Cinnamon & QtWebEngine (`falkon`) | **Partially tested (QEMU)** | `NOT TESTED` | Cinnamon works at `4G` with `>30s` initial frame warm-up under `-vga std` + `tcg`; `falkon` stalls past `1–2` tabs under `llvmpipe` while `firefox` completes `6/6` tabs. |
| Intel `i915` / `xe` & AMD `amdgpu` / RADV Vulkan | **Supported** | `NOT TESTED` | Shipped in Mint 22.3 / Ubuntu 24.04; hardware compositing, browser WebGL/video, HDMI/DP hotplug, and suspend require physical testing. |
| NVIDIA GPUs (`nouveau` vs `nvidia-driver`) | **Partially tested / Driver-dependent** | `NOT TESTED` | Proprietary driver requires Mint **Driver Manager** (`mintdrivers`); Wayland/Xorg/Vulkan/MOK behavior unverified on hardware. |
| Wi-Fi (`iwlwifi`, `ath10k_pci`, `ath11k_pci`, `rtw88`, `mt7921e`) & Bluetooth (`btusb`) | **Supported / Unknown by USB chipset** | `NOT TESTED` | Common PCIe chipsets supported via `linux-firmware`; Broadcom/Realtek USB dongles remain `unknown` until bare-metal tested. |
| Audio (`snd_hda_intel`, `snd_sof_pci` / Chromebook MADOO), Speakers & Mics | **Supported / Hardware-dependent** | `NOT TESTED` | HDA + PipeWire/ALSA shipped; Chromebook SOF UCM/topology requires physical validation (`docs/MADOO_CHROMEBOOK_QUALIFICATION.md`). |
| Touchpads / Multi-touch (`libinput`), USB Peripherals, Battery (`BAT*`), S3 / `s2idle` Suspend & Resume | **Detected / Supported** | `NOT TESTED` | Stage A/B probes implemented in `nexus-hw-qualify`; physical wake, palm rejection, and drain curves untested. |
| Internal NVMe / SATA AHCI / eMMC & Physical UEFI + Signed `shimx64.efi` Secure Boot | **Supported** | `NOT TESTED` | All 4 manifests include `shim-signed`, `grub-efi-amd64-signed`, `mokutil`; `nexus-install-preflight` & `nexus-recovery` verify EFI/Secure Boot readiness read-only; physical NVMe/eMMC & OEM Secure Boot untested on bare metal. |
| ARM64 / `i386` / Apple Silicon native | **Unsupported** | `Unsupported` | NEXUS OS targets `x86_64` (`amd64`) only. |
