# NEXUS OS Platform Architecture

## Confirmed direction

| Area | Decision |
|---|---|
| First target architecture | x86_64 (AMD64) |
| Display protocol | Wayland |
| Legacy application compatibility | XWayland is part of the planned desktop stack |
| First validation target | A virtual machine before physical hardware |

These decisions define the initial development target. They do not imply that a bootable image exists yet.

## Proposed graphics bring-up sequence

1. Bring up a minimal x86_64 Linux image in QEMU.
2. Confirm kernel graphics/input support and a working Wayland session.
3. Use Weston as a temporary reference compositor for early hardware and session testing.
4. Add XWayland and verify that X11 applications can run inside the Wayland session.
5. Prototype the NEXUS native shell separately, then decide whether Weston remains useful as a base or is replaced by the production compositor/shell.
6. Measure memory after each layer is added; do not treat the 128 MB aspiration as a guaranteed target.

Weston is a bring-up tool choice, not a final visual-design decision. The NEXUS Liquid Glass interface and NEXUS ORBIT remain product requirements, not features delivered by this initial Linux scaffold.

## Steam compatibility: a release gate

Steam support must be tested rather than inferred from the CPU architecture or the presence of Wayland.

Valve's published Linux requirements include:
- x86_64 plus both 64-bit and 32-bit runtime libraries and graphics drivers;
- X11 or XWayland;
- D-Bus session services;
- PulseAudio or PipeWire's PulseAudio-compatible service;
- working OpenGL and Vulkan drivers.

Valve also states that Steam no longer supports Linux distributions with glibc older than 2.31. The project must therefore choose and maintain a compatible C library/runtime and keep it security-updated.

Steam compatibility checklist:
- [ ] glibc version meets Valve's current minimum.
- [ ] 32-bit and 64-bit userspace libraries are available.
- [ ] 32-bit and 64-bit graphics driver support is available for supported GPUs.
- [ ] XWayland works in the Wayland session.
- [ ] D-Bus, audio, OpenGL and Vulkan requirements are satisfied.
- [ ] Steam installs, launches and updates in a repeatable test environment.
- [ ] At least one Proton game is tested on supported hardware before making a compatibility claim.

Official references:
- Valve Steam Linux requirements: https://github.com/ValveSoftware/steam-for-linux
- Valve Steam Linux beta requirements: https://github.com/ValveSoftware/steam-for-linux/blob/master/README.beta.md
- Steam Linux support and glibc notice: https://help.steampowered.com/en/faqs/view/107F-BB20-FB5A-1CE4

## Build-system decision still open

The existing NEXUS Buildroot external tree is only a scaffold. Buildroot is attractive for a compact, controlled system image, but a general-purpose gaming desktop has a broader maintenance burden: multilib, graphics drivers, audio, D-Bus, desktop portals, firmware and ongoing security updates.

Before committing to Buildroot as the final desktop base, compare two paths:

### Path A — Buildroot-based image
- Strong control over the package set and image footprint.
- Suitable for a minimal appliance-like base and tightly controlled hardware targets.
- Requires explicit validation that the needed 32-bit Steam runtime, graphics stack and update strategy can be maintained.

### Path B — General-purpose x86_64 Linux base
- A maintained desktop distribution base may make Steam, multilib graphics drivers and ongoing security updates easier to support.
- NEXUS can still provide its own Wayland shell, launcher, settings and branded experience.
- Likely larger than a highly trimmed Buildroot image; measure rather than assume.

**Current recommendation:** keep the Buildroot scaffold as an experimental minimal-image path, but do not make it the final gaming-desktop base until the Steam requirements have been proven. Compare both paths with a small reproducible QEMU prototype before choosing.

## Decisions still needed

- [ ] BIOS, UEFI, or both for the first boot target.
- [ ] Buildroot versus a general-purpose Linux base for the desktop release.
- [ ] Init/service manager and update model.
- [ ] Production Wayland compositor and native shell toolkit.
- [ ] Supported GPU scope and driver strategy.

## Non-goals for this stage

- No claim that NEXUS OS is bootable.
- No claim of Steam or Proton compatibility.
- No promise of a 128 MB desktop idle footprint.
- No hardware-control features until their native implementation and permissions are tested.
