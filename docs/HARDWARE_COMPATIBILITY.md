# NEXUS OS Hardware Compatibility Matrix (Phase 12.3)

**Foundation:** Linux Mint 22.3 (`noble` Ubuntu 24.04 LTS kernel & drivers, `x86_64`).
**Policy:** Categories strictly distinguish what has been **Tested and working (QEMU/OVMF)** from **Expected to work (untested on bare metal)**, **Partially supported**, **Unsupported**, or **Hardware-dependent**. QEMU results never imply real bare-metal hardware qualification.

| Hardware / Feature | Classification | Notes & Evidence |
|---|---|---|
| `x86_64` Virtualized CPU (`qemu64`/`max` under `tcg`) | **Tested and working (QEMU)** | Verified across live ISO boots, `nexus-disk-install` UEFI/GPT installs, and 3-reboot installed boots (`lite`, `cinnamon`, `xfce`, run `45722286627`). |
| VirtIO block disk (`/dev/vda` GPT ESP + ext4), VirtIO NIC (`virtio-net-pci`), & OVMF UEFI (`1280x800`, `-vga std` / `-vga virtio`) | **Tested and working (QEMU/OVMF)** | Verified in live and installed-disk OVMF boots (`booted_from_vda=true`, `EFI/BOOT/BOOTX64.EFI`, `nmcli=connected`, `1280x800` QMP screenshots). |
| Software OpenGL (`Mesa llvmpipe`) with Cinnamon Muffin compositor | **Partially supported (slow initial render)** | Cinnamon at `2048 MiB` & `4096 MiB` under `llvmpipe` (`Accelerated: no`) takes >30s idle to flush first compositor frame under `-vga std`; `-vga virtio` at `90s` renders `96.65–96.7%`. Hardware 3D GPU or KVM recommended for Cinnamon. |
| Intel Core / Celeron / Pentium (`i915` / Mesa) | **Hardware-dependent / Untested on bare metal** | Standard Ubuntu 24.04 / Linux Mint 22.3 `i915` + `mesa-vulkan-drivers` support expected. |
| AMD Ryzen CPUs & Radeon GPUs (`amdgpu` / Mesa) | **Hardware-dependent / Untested on bare metal** | Open-source `amdgpu` + RADV Vulkan included in Mint 22.3. |
| NVIDIA discrete/hybrid GPUs | **Partially supported (untested)** | Requires installing proprietary drivers via Linux Mint **Driver Manager** (`mintdrivers`); `nouveau` lacks full Vulkan/Proton performance. |
| Common Intel / Qualcomm Atheros Wi-Fi & Bluetooth | **Hardware-dependent / Untested on bare metal** | Provided by `linux-firmware` in Mint 22.3; Broadcom/Realtek USB dongles vary by chipset (**Unknown** until tested). |
| Intel SOF / HDA audio & Chromebook MADOO audio | **Hardware-dependent / Untested on bare metal** | Standard HDA works via PipeWire/ALSA; Chromebook `sof-audio` requires topology/UCM validation (`docs/MADOO_CHROMEBOOK_QUALIFICATION.md`). |
| USB storage, keyboards, mice, touchpads (`libinput`) | **Hardware-dependent / Untested on bare metal** | Standard Linux Mint kernel + `libinput` (only PS/2/QMP synthetic input tested in CI). |
| Laptop internal panels, external HDMI/DP, & S3/s2idle suspend | **Hardware-dependent / Untested on bare metal** | Not tested inside headless QEMU (`systemctl suspend` / lid close untested). |
| Xbox / PlayStation / USB & Bluetooth controllers | **Hardware-dependent / Untested on bare metal** | `xpad`, `hid-playstation`, `hid-generic`, `/dev/input/js*` + `steam-devices` shipped in Mint 22.3. |
| 64-bit UEFI & Secure Boot (signed Mint/Ubuntu `shimx64.efi`) | **Partially verified** | Unsigned OVMF boot (`BOOTX64.EFI` + `EFI/ubuntu/grub.cfg`) verified in QEMU across `21/21` installed boots; physical firmware with **Secure Boot enforced** untested. |
| ARM64 / 32-bit x86 (`i386`) / Apple Silicon native | **Unsupported** | NEXUS OS targets `x86_64` (`amd64`) only. |
