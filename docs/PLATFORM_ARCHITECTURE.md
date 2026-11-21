# NEXUS OS Platform Architecture

## Confirmed direction

| Area | Decision |
|---|---|
| First target architecture | x86_64 (AMD64) |
| Display protocol | Wayland |
| Legacy application compatibility | XWayland is part of the planned desktop stack |
| First validation target | QEMU virtual machine before physical hardware |\n| First firmware target | UEFI using OVMF in QEMU; legacy BIOS can be evaluated later |\n| Bootloader | GRUB for the first Ubuntu-based image |\n| Init/service manager | systemd, matching the Ubuntu base |
| Main desktop base | Ubuntu 26.04 LTS minimal/server base, customised by NEXUS |
| Experimental image path | Keep the existing Buildroot external tree for small appliance-style experiments |

These decisions define the initial development target. They do not imply that a bootable NEXUS image exists yet.

## Why Ubuntu LTS is the recommended main base

NEXUS is intended to be a general-purpose desktop with gaming, programming and everyday application support. A custom desktop distribution needs a maintainable package ecosystem, graphics drivers, firmware, audio, session services, 32-bit compatibility libraries and regular security updates.

Valve's current Steam Linux documentation identifies the latest Ubuntu LTS as its supported stable-client baseline. Its requirements also include 64-bit and 32-bit runtime libraries and graphics drivers, X11 or XWayland, D-Bus, PulseAudio or PipeWire's PulseAudio-compatible service, and OpenGL/Vulkan drivers. Steam's newer runtime documentation also describes typical desktop distributions such as Arch, Debian and Fedora, and requires glibc 2.31 or newer. These are a much more natural fit for a maintained general-purpose Linux base than a hand-assembled Buildroot desktop.

**Selected starting point: Ubuntu 26.04 LTS minimal/server base, not the full Ubuntu GNOME desktop.** NEXUS will provide its own Wayland desktop shell and visual identity on top. Ubuntu 26.04 LTS is the current LTS release and receives standard security maintenance until May 2031. We will pin an exact point-release image and verify its checksums when the image-build stage begins.

This is a pragmatic engineering base, not a claim that NEXUS is an Ubuntu derivative officially supported by Valve. Steam and Proton must still pass NEXUS's own tests before compatibility is advertised.

Official references:
- Valve Steam Linux requirements: https://github.com/ValveSoftware/steam-for-linux
- Valve Steam Linux beta requirements: https://github.com/ValveSoftware/steam-for-linux/blob/master/README.beta.md
- Valve Steam Linux support notice: https://help.steampowered.com/en/faqs/view/107F-BB20-FB5A-1CE4
- Ubuntu 26.04 LTS release notes and support lifespan: https://documentation.ubuntu.com/release-notes/26.04/
- Ubuntu release lifecycle: https://ubuntu.com/about/release-cycle

## First VM boot profile\n\nThe initial virtual-machine target will use **QEMU x86_64 with UEFI firmware (OVMF), a virtual disk, and virtio devices where practical**. GRUB will provide the first bootloader path, and systemd will remain the service manager supplied by Ubuntu. This deliberately follows the selected base rather than introducing a second boot or service stack prematurely.\n\nThese are first-bring-up defaults, not a claim that a NEXUS image already boots. The exact QEMU command, firmware package, image format, and checksum must be recorded alongside the first successful boot test. Legacy BIOS and broader hardware support can be evaluated after the UEFI path is repeatable.\n\n## Role of Buildroot

The existing NEXUS Buildroot external tree will be retained as a separate experimental path for:
- very small recovery or diagnostic images;
- appliance-style builds with a tightly controlled hardware target;
- learning and measuring how much smaller a purpose-built image can be.

It will **not** be the primary foundation for the first full NEXUS gaming desktop. This avoids making Steam multilib, GPU drivers, audio services, desktop integration and long-term security maintenance unnecessarily difficult.

## Proposed graphics bring-up sequence

1. Build a minimal x86_64 Ubuntu-based test image or VM environment.
2. Confirm kernel graphics/input support and a working Wayland session.
3. Use Weston temporarily as a reference compositor for early hardware/session testing.
4. Add XWayland and verify that X11 applications run inside the Wayland session.
5. Prototype the NEXUS native shell separately; choose the production compositor and toolkit after a working prototype.
6. Measure memory after each layer is added. The 128 MB aspiration is not a guaranteed target.

Weston is a bring-up tool choice, not a final visual-design decision. The NEXUS Liquid Glass interface and NEXUS ORBIT remain product requirements, not features delivered by the Linux base.

## Steam compatibility: release gate

Steam support must be tested rather than inferred from CPU architecture or Wayland support.

- [ ] Current glibc meets Valve's minimum.
- [ ] 32-bit and 64-bit userspace libraries are available.
- [ ] 32-bit and 64-bit graphics driver support is available for supported GPUs.
- [ ] XWayland works in the Wayland session.
- [ ] D-Bus, audio, OpenGL and Vulkan requirements are satisfied.
- [ ] Steam installs, launches and updates in a repeatable test environment.
- [ ] At least one Proton game is tested on supported hardware before making a compatibility claim.

## Decisions still needed

- [x] First boot target: UEFI in QEMU (OVMF); legacy BIOS can be evaluated later.\n- [x] First bootloader: GRUB.\n- [x] Init/service manager: systemd from Ubuntu.
- [ ] Exact Ubuntu 26.04 point-release image and checksum to pin.
- [ ] Init/service manager and update/rollback model.
- [ ] Production Wayland compositor and native shell toolkit.
- [ ] Supported GPU scope and driver strategy.
- [ ] Installer and partitioning approach.

## Non-goals for this stage

- No claim that NEXUS OS is bootable.
- No claim of Steam or Proton compatibility until tested.
- No promise of a 128 MB desktop idle footprint.
- No hardware-control features until their native implementation and permissions are tested.
