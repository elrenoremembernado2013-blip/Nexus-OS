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

## Decisions required before a real defconfig

1. **Primary target:** x86_64 PC/VM first, with other architectures considered separately.
2. **Boot mode:** begin with a QEMU-compatible BIOS or UEFI path and document the chosen firmware.
3. **Init system:** select and justify the smallest maintainable option.
4. **Graphics stack:** decide between a minimal Wayland compositor and an X11-based prototype path after measuring package and RAM costs.
5. **Desktop implementation:** preserve the existing browser prototype as a design reference; do not assume it is the final native shell.
6. **Buildroot release:** pin a verified stable release or commit and record its source checksum/commit. Do not rely on an unverified version label.
7. **RAM target:** treat 128 MB as an aspirational measurement target, not a promise. A graphical desktop and modern browser-based shell may require substantially more memory.

## Readiness checklist

- [x] Create a separate NEXUS Buildroot external-tree scaffold.
- [ ] Choose and document the first target architecture and QEMU machine.
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
