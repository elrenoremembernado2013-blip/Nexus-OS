# NEXUS OS Hardware Compatibility Matrix (Phase 10)

**Foundation:** Linux Mint 22.3 (`noble` Ubuntu 24.04 LTS kernel & drivers, `x86_64`).
**Policy:** Categories strictly distinguish what has been **Tested and working** from **Expected to work (untested)**, **Partially supported**, **Unsupported**, or **Unknown**. No universal hardware compatibility is claimed.

| Hardware / Feature | Classification | Notes & Evidence |
|---|---|---|
| `x86_64` Intel Xeon CPU (`2.60 GHz` VM host) | **Tested and working** | Verified via `nexus-install-preflight.sh` & `nexus-gaming-cli.sh` (`3940 MiB` RAM, `/proc/stat`, `/proc/cpuinfo`). |
| VirtIO / QEMU block disk (`/dev/vda`), virtual NIC (`eth0`), & VGA/OVMF (`1280x800`) | **Tested and working** (QEMU/OVMF live VM) | Verified in live QEMU graphical boots across `lite`, `cinnamon`, and `xfce` (`lsblk /dev/vda`, `nmcli` `connected`, `1280x800` Xorg/QMP screenshots, run `45656960059`). |
| Intel Core / Celeron / Pentium (`i915` / Mesa) | **Expected to work (not tested on NEXUS ISO)** | Standard Ubuntu 24.04 / Linux Mint 22.3 `i915` + `mesa-vulkan-drivers` support. |
| AMD Ryzen CPUs & Radeon GPUs (`amdgpu` / Mesa) | **Expected to work (not tested on NEXUS ISO)** | Open-source `amdgpu` + RADV Vulkan included in Mint 22.3. |
| NVIDIA discrete/hybrid GPUs | **Partially supported (not tested)** | Requires installing proprietary drivers via Linux Mint **Driver Manager** (`mintdrivers`); `nouveau` lacks full Vulkan/Proton performance. |
| Common Intel / Qualcomm Atheros Wi-Fi & Bluetooth | **Expected to work (not tested)** | Provided by `linux-firmware` in Mint 22.3; Broadcom/Realtek USB dongles vary by chipset (**Unknown** until tested). |
| Intel SOF / HDA audio & Chromebook MADOO audio | **Partially supported (not tested)** | Standard HDA works via PipeWire/ALSA; Chromebook `sof-audio` requires topology/UCM validation (`docs/MADOO_CHROMEBOOK_QUALIFICATION.md`). |
| USB storage, keyboards, mice, touchpads (`libinput`) | **Expected to work (not tested)** | Standard Linux Mint kernel + `libinput`. |
| Laptop internal panels & external HDMI/DP monitors | **Expected to work (not tested)** | Cinnamon/Xfce display settings (`cinnamon-settings display` / `xfce4-display-settings`). |
| Xbox / PlayStation / USB & Bluetooth controllers | **Expected to work (not tested)** | `xpad`, `hid-playstation`, `hid-generic`, `/dev/input/js*` + `steam-devices`. |
| 64-bit UEFI & Secure Boot (signed Mint/Ubuntu shim) | **Expected to work (not tested)** | `build-nexus-iso.sh` builds hybrid BIOS+UEFI ISO (`boot/grub/efi.img`); Secure Boot `efivars` probe tested (`unavailable` in non-EFI container). |
| ARM64 / 32-bit x86 (`i386`) / Apple Silicon native | **Unsupported** | NEXUS OS targets `x86_64` (`amd64`) only. |
