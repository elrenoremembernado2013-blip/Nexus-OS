# NEXUS OS Platform Architecture

## Decision

NEXUS's first full desktop foundation is **Ubuntu 26.04 LTS minimal/server**, customized with a NEXUS Wayland desktop. Linux Mint is a contingency fallback only if a documented blocker makes Ubuntu unsuitable; it is not a second target or parallel default. Reconsider that fallback only against concrete needs such as hardware support, package availability, maintenance, or Steam requirements, and record the reason before changing the base.

The Ubuntu installer/QEMU scripts currently create a stock Ubuntu guest. They do not build, install, or boot a NEXUS OS image. The browser desktop remains a prototype and does not control host hardware.

## Platform decisions

| Area | Initial direction |
|---|---|
| Distribution | Ubuntu 26.04 LTS minimal/server, customized by NEXUS |
| Fallback | Linux Mint only after a documented Ubuntu blocker; no parallel image |
| Main architecture | x86-64 (AMD64) |
| Firmware / boot | UEFI with OVMF in QEMU; GRUB as the initial bootloader |
| Init and system services | Ubuntu's systemd |
| Session | Wayland; compositor and production shell toolkit remain undecided |
| X11 apps | XWayland planned and subject to acceptance tests |
| First validation | QEMU virtual machine before physical hardware |
| Experimental small image | Existing Buildroot external tree, separate from the primary desktop |

These choices set a development direction, not a claim that a bootable NEXUS image exists.

## Why Ubuntu first

The intended product is a general-purpose desktop for daily applications, development, and potential gaming. Ubuntu LTS provides a maintained package ecosystem and a familiar path to graphics, firmware, audio, 32-bit libraries, and security updates. Buildroot remains useful for tightly scoped appliance or recovery experiments, but its small, hand-assembled system would make the primary desktop's package, graphics, audio, and Steam compatibility work harder to maintain.

Ubuntu is a pragmatic base choice. It does not imply official Ubuntu or Valve support for NEXUS, and Steam/Proton compatibility must be demonstrated on the actual NEXUS image before it is advertised.

## Reproducible build and release rules

The current scripts verify an official Ubuntu ISO against its signed checksum manifest and launch a local QEMU guest. This makes media acquisition verifiable; it is not yet a reproducible NEXUS image build.

Before the first custom image build:

1. Pin the Ubuntu point-release media URL, published SHA-256, and signed-manifest verification result in a release record.
2. Pin build tools, package sources/snapshots, package versions, kernel, bootloader, desktop components, and external source revisions. Record checksums or immutable commit IDs.
3. Build from a clean checkout using documented commands and dependencies; keep generated output outside tracked source.
4. Record the build inputs and output artifact digest. Do not call builds reproducible until repeated clean builds have been compared and any expected nondeterminism is documented.

Do not invent or pre-claim pins that have not been selected and verified.

## Boot and QEMU acceptance

The first custom-image target is x86-64 UEFI/OVMF on QEMU, using a virtual disk and virtio devices where practical. A release candidate must:

- boot from a clean virtual disk through UEFI and GRUB without manual repair;
- reach a usable NEXUS Wayland session and shut down cleanly;
- pass documented checks for keyboard, pointer, display, storage, network, and audio within the declared VM device profile;
- demonstrate that the intended unprivileged user can use the desktop while administrative actions require elevation;
- record the exact artifact digest, QEMU/OVMF versions, command, virtual hardware profile, and observed result.

These are future acceptance criteria. The existing launch script starts a stock Ubuntu installer or installed guest and does not meet them on behalf of NEXUS. Physical hardware support follows repeatable QEMU acceptance.

## OS services and session boundaries

Use Ubuntu's systemd for boot, service supervision, logging, device/session integration, and scheduled maintenance. Keep system services narrowly scoped and independently reviewable. The graphical login should start a per-user Wayland session; the chosen compositor owns display/input session coordination, while the NEXUS shell and applications run as the logged-in user.

Use established system interfaces for D-Bus, networking, audio, portals, and device access. Do not let the shell impersonate privileged services or directly expose unrestricted host operations. The production compositor, display manager, audio stack, and shell toolkit remain decisions for a later working session prototype.

## Users and security

Create and use a standard, non-root desktop account. Keep administrative access behind Ubuntu's supported privilege elevation and authentication flow. Services run as dedicated system users where appropriate, with only the device access and capabilities they need. Avoid setuid helpers and broad group membership unless a documented feature requires them.

Keep the base firewall and Ubuntu security updates enabled, minimize listening services, and use signed, authenticated package sources. Store user data with normal per-user ownership and restrictive defaults. Native settings and hardware controls must use permission-checked system APIs and report unavailable operations honestly.

## Updates and recovery

For the first Ubuntu-based image, retain Ubuntu's authenticated package update path and security updates; do not add a custom updater until its trust and failure model are designed. Before changing a bootable image, provide a tested backup/recovery route and preserve user data. Define rollback behavior for failed updates before promising atomic updates or automatic rollback. A recovery environment may be explored through the separate Buildroot path, but it is not currently implemented.

## Desktop integration boundary

Ubuntu supplies the kernel, drivers, base libraries, system services, and package/update foundation. NEXUS supplies the desktop identity, shell, settings experience, application integration, and carefully permissioned interfaces. The current browser-based desktop is only a UI prototype; its preview controls are not Linux services. Keep this boundary explicit in user-facing status and code.

## Compatibility layers and future applications

Treat each compatibility feature as a conditional future integration with its own hardware, licensing, security, maintenance, and acceptance review:

- **Steam/Proton:** investigate after the native graphics, audio, 32-bit libraries, Vulkan/OpenGL drivers, D-Bus, and XWayland paths work. Test Steam installation/update and at least one Proton title before claiming support.
- **Wine:** optional Windows application compatibility, evaluated per use case and tested application; not a system-wide guarantee.
- **Waydroid:** optional Android container integration, only if kernel, graphics, binder, security, and distribution requirements can be met and maintained.
- **Darling:** exploratory macOS API compatibility, with feasibility and licensing reviewed before considering distribution.

**Quantum** is a future NEXUS application, not an OS component or currently delivered native app. Keep its product scope separate from base-system bring-up.

## Memory target

A 128 MB idle footprint is an aspiration for measurement, not an achieved result or a minimum requirement. Measure the booted system with a named metric (for example, MemAvailable and process/cgroup totals), a defined post-login idle interval, fixed VM hardware, and a recorded image digest. Repeat measurements and report the desktop features enabled; a graphical desktop may require substantially more memory.

## Official references

- [Ubuntu 26.04 release notes](https://documentation.ubuntu.com/release-notes/26.04/)
- [Ubuntu release lifecycle](https://ubuntu.com/about/release-cycle)
- [Valve Steam for Linux](https://github.com/ValveSoftware/steam-for-linux)
- [Valve Steam support notice](https://help.steampowered.com/en/faqs/view/107F-BB20-FB5A-1CE4)
- [Buildroot manual](https://buildroot.org/downloads/manual/manual.html)
