# NEXUS OS — Proposed Architecture

**Status:** proposal, not yet implemented. Decisions below are initial engineering recommendations and must be validated against the target hardware.

## 1. System layers

```text
Applications (optional, user-installed)
        |
NEXUS desktop shell / ORBIT launcher
        |
Wayland compositor + desktop services
        |
Linux kernel + device drivers
        |
Buildroot-generated root filesystem
        |
Firmware / bootloader / hardware
```

Keep the layers loosely coupled. The launcher must not be responsible for security policy, package management, or system updates.

## 2. Initial platform strategy

- **Build system:** Buildroot, pinned to a documented release or commit once selected.
- **Kernel:** use the kernel version supported by the chosen Buildroot release and required hardware.
- **Init:** start with the simplest supported init/service arrangement; add services only when a concrete requirement exists.
- **Graphics:** investigate a Wayland compositor suitable for low-resource devices. Select one only after checking its Buildroot package, input support, GPU requirements, and memory cost.
- **Desktop shell:** implement NEXUS UI as a separate application/process so it can be restarted without restarting the compositor.
- **Applications:** keep optional applications outside the minimal base image wherever practical.

Do not pin a version based only on a planning note. Record the exact Buildroot release/commit and toolchain versions in the repository when the source tree is added.

## 3. Hardware and memory targets

The initial design goal is to support older x86-64 computers, with 4 GB RAM as an important test profile. Other architectures and smaller memory configurations require separate testing.

A 128 MB idle-RAM figure has been discussed as an aspiration, not a verified requirement. It is not yet an acceptance criterion. Define exactly what is included (kernel, compositor, shell, services, cache) before measuring it. Report both `MemAvailable` and process/service usage; do not compare unlike measurement methods.

## 4. Security model

- Build from pinned, verifiable source versions.
- Enable kernel and userspace security features supported by the selected toolchain.
- Run desktop applications as an unprivileged user.
- Keep network-facing services disabled unless needed.
- Minimise setuid binaries and privileged helpers.
- Use signed update metadata and verify packages/images before installation.
- Protect update rollback and recovery paths.
- Keep secrets out of the repository and build logs.
- Document threat assumptions and known limitations.

A secure-by-default claim requires a threat model, configuration review, and tests; it cannot be inferred from using Linux or Buildroot alone.

## 5. Updates and software

Buildroot is designed to generate embedded Linux systems; it is not a general-purpose rolling desktop package manager. NEXUS must choose an update strategy deliberately (for example, signed whole-image updates with a recovery slot) before promising an app-store or desktop package-management experience.

Steam support is a separate compatibility investigation. It depends on CPU architecture, graphics drivers, Vulkan/OpenGL support, available storage, userspace libraries, and the supported Steam runtime. Do not include Steam in a minimal image until a supported hardware/software path is proven.

## 6. UI direction

The visual direction is a restrained futuristic interface:

- Liquid Glass-inspired translucent surfaces, with a solid/opaque fallback.
- Wallpaper categories and user-selectable themes.
- Control Centre for quick settings and notifications.
- ORBIT for application search, pinned apps, categories, and keyboard navigation.
- Accessibility options, including reduced motion and high contrast.

The interface must remain usable without transparency, blur, or animation. These effects should be optional because they can increase GPU and memory costs.

## 7. Decisions still open

- Target architectures and minimum CPU instruction set.
- Bootloader and image layout.
- Kernel configuration and firmware policy.
- Wayland compositor and desktop toolkit.
- Audio, networking, Bluetooth, and power-management stack.
- Image update/recovery mechanism.
- App installation model and Steam compatibility scope.

Resolve each decision with a small prototype and recorded measurements rather than selecting components by appearance alone.
