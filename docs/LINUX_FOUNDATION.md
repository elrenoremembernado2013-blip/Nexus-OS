# NEXUS OS Linux Foundation

## Status

This is the initial, deliberately incomplete Buildroot external-tree scaffold. It is **not a bootable operating system** and is not yet ready to compile.

The browser desktop prototype remains on this branch and is preserved unchanged.

## Repository layout

- `nexus-br2-external/`: NEXUS-owned Buildroot customizations.
- `nexus-br2-external/external.desc`: Buildroot external-tree identity.
- `nexus-br2-external/Config.in`: NEXUS Kconfig menu entry.
- `nexus-br2-external/external.mk`: NEXUS package/build integration point.
- `docs/LINUX_FOUNDATION.md`: architecture decisions and readiness checklist.

## Buildroot integration

NEXUS uses Buildroot's `br2-external` mechanism so project-specific configuration and packages remain separate from upstream Buildroot. The external tree currently contains the required entry-point files only; it does not yet contain a defconfig, kernel configuration, board support, root filesystem overlay, or package recipes.

Official documentation: https://buildroot.org/downloads/manual/manual.html

## Confirmed platform direction

1. **Primary target:** x86_64 PC/VM first.
2. **Graphics protocol:** Wayland.
3. **Compatibility:** plan for XWayland so X11 applications can run within the Wayland session.
4. **First validation target:** QEMU before physical hardware.

See [PLATFORM_ARCHITECTURE.md](PLATFORM_ARCHITECTURE.md) for the Steam compatibility requirements and the still-open base-distribution decision.

## Decisions required before a real defconfig

1. **Boot mode:** choose BIOS, UEFI, or both for the first QEMU target.
2. **Base system:** prove the Steam/runtime requirements on Buildroot or select a maintained general-purpose Linux base before committing to a desktop release.
3. **Init system:** select and justify a maintainable option.
4. **Native desktop:** choose the production Wayland compositor and shell toolkit. Weston may be used temporarily for bring-up, not assumed to be the final shell.
5. **Buildroot release (if retained):** pin a verified stable release or commit and record its source checksum/commit.
6. **RAM target:** treat 128 MB as an aspirational measurement target, not a promise. A graphical desktop and modern shell may require substantially more memory.

## Readiness checklist

- [x] Create a separate NEXUS Buildroot external-tree scaffold.
- [x] Choose and document x86_64 and Wayland as the first platform direction.
- [ ] Choose the first QEMU machine and firmware mode.
- [x] Select Ubuntu 26.04 LTS minimal/server as the recommended main desktop base.
- [x] Retain Buildroot for separate minimal-image experiments, not the primary gaming desktop.
- [ ] Validate XWayland and Steam runtime requirements in the Ubuntu-based test environment.
- [ ] Pin the upstream Buildroot source revision.
- [ ] Add a minimal, reviewed defconfig.
- [ ] Add kernel and root filesystem configuration.
- [ ] Add reproducible build scripts and dependency documentation.
- [ ] Build successfully in a clean environment.
- [ ] Boot the resulting image in QEMU and record the exact command and result.
- [ ] Measure idle memory with a documented metric and repeatable procedure.
- [ ] Review security defaults before adding network-facing services.

## Safety and security principles

- Prefer least privilege and a minimal package set.
- Keep build outputs outside tracked source directories.
- Do not include secrets, credentials, or personal data in the repository.
- Verify upstream source versions and checksums before pinning dependencies.
- Keep the prototype's simulated controls clearly distinguished from real hardware controls.
