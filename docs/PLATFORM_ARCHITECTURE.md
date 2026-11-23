# NEXUS OS Platform Architecture

## Decision

For the HP Chromebook x360 14b reference device, NEXUS's first native desktop base is **Linux Mint 22.3 Xfce**, using its Ubuntu 24.04 LTS (Noble) package base. This is a deliberate hardware-fit choice: the device has 4 GB RAM and 32 GB eMMC, and the Mint team recommends 4 GB RAM and 20 GB disk for Mint. Ubuntu 26.04 Desktop lists 6 GB RAM and 25 GB free disk for a comfortable experience. Ubuntu remains the upstream base; an Ubuntu minimal/server build may be reconsidered only if Mint has a documented blocker or fails device qualification.

The exact Mint release is a pinned starting point, not a claim that it will remain the newest supported version. Mint 22.3 is supported until April 2029. Reassess the pinned release before later builds and document any upgrade.

The media and QEMU scripts install or launch an unmodified Mint guest. They do not build, install, or boot a NEXUS OS image. The browser desktop remains a prototype and does not control host hardware.

## Reference device

The physical reference device is the **HP Chromebook x360 14b-cb0 (MADOO)** with Intel Celeron N4500 (2 cores/2 threads), 4 GB RAM, and 32 GB eMMC, based on the owner's reported specifications. HP documents this model family with the N4500, 4 GB and 32 GB configurations. The reported firmware version is 158.16868.0; MADOO is the board/platform name, not that version number.

Treat memory and storage as hard constraints. Measure free eMMC after install and update; reserve space for recovery and user data. The 128 MB idle figure remains an aspiration, not an achieved result. The QEMU launch script's 4 GB guest RAM and 40 GB virtual disk defaults are for development-host testing and do not describe a VM to run on the Chromebook.

MADOO is listed as supporting UEFI Full ROM firmware. This indicates a possible firmware path for testing, not that NEXUS has booted or that every Chromebook component is supported. Firmware modification, recovery, and device-specific driver validation are separate prerequisites before installing NEXUS to the Chromebook.

## Platform decisions

| Area | Initial direction |
|---|---|
| Distribution | Linux Mint 22.3 Xfce (Ubuntu Noble 24.04 LTS package base) |
| Alternate base | Ubuntu minimal/server only if Mint has a documented blocker or fails qualification |
| Main architecture | x86-64 (AMD64) |
| Firmware / boot | UEFI with OVMF in QEMU; GRUB as the initial bootloader |
| Init and system services | systemd |
| Session | X11 with the Xfce session and Xfwm4 window manager |
| Native desktop direction | Customize Xfce theme, panel, menu, and NEXUS identity before adding custom shell processes |
| First validation | QEMU virtual machine on the development host, then controlled physical-device qualification |
| Experimental small image | Existing Buildroot external tree, separate from the primary desktop |

These choices set a development direction, not a claim that a bootable NEXUS image exists.

## Desktop prototype baseline

Start the native desktop spike with the Mint Xfce session. Apply a NEXUS theme, panel layout, launcher/menu styling, and one small focused Xfce panel integration. Keep Xfwm4 and established session services. Consider a separate NEXUS shell only after this baseline is measured on the 4 GB device; do not begin with a custom compositor or replace the login/session stack.

This is a prototype baseline, not a claim that a NEXUS session has been installed or tested. Xfce is the lower-resource option for this hardware profile, while still providing a usable panel, launcher, window manager, and accessibility options. The repository's static HTML/CSS/JavaScript desktop remains a design reference; it is not a native GTK application and this decision does not imply an automatic code-reuse path.

### Approaches considered

- **Mint Xfce (selected first):** light desktop with Mint's Ubuntu-based package/update foundation; 4 GB is the stated comfortable memory recommendation, while 32 GB is above the stated disk minimum but leaves limited room for user files.
- **Ubuntu 26.04 minimal/server plus a desktop:** remains a possible alternative, but adding the NEXUS session creates an unmeasured memory and storage profile. Stock Ubuntu Desktop's published memory target exceeds the device's 4 GB.
- **KWin/Plasma or GNOME Shell:** defer until measurements show adequate memory headroom; they are not the current low-resource baseline.
- **labwc + standalone NEXUS shell:** potentially leaner, but requires NEXUS to build and maintain panels, launcher, notifications, task handling, and session integration.

### Prototype acceptance

On a clean Mint Xfce QEMU guest, demonstrate login, NEXUS theme/panel/menu integration, ordinary window focus/minimize/restore, keyboard navigation, reduced-motion behavior, and clean logout. Record exact package versions, VM resources, startup and idle memory, disk use, and remaining free space. Then qualify the physical MADOO device separately for keyboard, touchpad, touchscreen, display, Wi-Fi, Bluetooth, audio, suspend/resume, storage, and battery behavior. A QEMU pass is not physical-device validation. No 128 MB result is assumed.

## Why Mint Xfce for the reference device

Linux Mint's published requirements are 2 GB RAM and 20 GB disk minimum, with 4 GB RAM recommended for comfortable use. Ubuntu 26.04 Desktop lists 6 GB RAM and 25 GB free storage for a comfortable experience. This makes Mint Xfce the better starting desktop for the specific 4 GB/32 GB device, while keeping Ubuntu as its package foundation. This choice does not guarantee NEXUS will meet the same footprint or that all Chromebook hardware works.

Buildroot remains useful for tightly scoped appliance or recovery experiments, but it is not the primary general-purpose desktop path. Steam/Proton and other compatibility layers remain conditional future work and require tests on the actual NEXUS image.

## Reproducible build and release rules

The Mint media script verifies the release's signed checksum manifest and the ISO digest. This makes media acquisition verifiable; it is not yet a reproducible NEXUS image build.

Before the first custom image build:

1. Pin the Mint release, edition, ISO URL, published SHA-256, signing-key fingerprint, and manifest verification result in a release record.
2. Pin build tools, package sources/snapshots, package versions, kernel, bootloader, desktop components, and external source revisions. Record checksums or immutable commit IDs.
3. Build from a clean checkout using documented commands and dependencies; keep generated output outside tracked source.
4. Record the build inputs and output artifact digest. Do not call builds reproducible until repeated clean builds have been compared and expected nondeterminism is documented.

Do not invent or pre-claim pins that have not been selected and verified.

## Boot and QEMU acceptance

The first custom-image target is x86-64 UEFI/OVMF on QEMU, using a virtual disk and virtio devices where practical. A release candidate must:

- boot a clean virtual disk through UEFI and GRUB without manual repair;
- reach a usable NEXUS Xfce session and shut down cleanly;
- pass documented checks for keyboard, pointer, display, storage, network, and audio within the declared VM device profile;
- demonstrate that the intended unprivileged user can use the desktop while administrative actions require elevation;
- record the exact artifact digest, QEMU/OVMF versions, command, virtual hardware profile, and observed result.

These are future acceptance criteria. The existing launch script runs a stock Mint installer or installed guest and does not meet them on behalf of NEXUS. Physical hardware support follows repeatable QEMU acceptance and separate device testing.

## OS services and session boundaries

Use systemd for boot, service supervision, logging, device/session integration, and scheduled maintenance. Keep system services narrowly scoped and independently reviewable. The graphical login starts a per-user Xfce X11 session; Xfwm4 owns window management and the NEXUS shell and applications run as the logged-in user.

Use established system interfaces for D-Bus, networking, audio, portals, and device access. Do not let the shell impersonate privileged services or directly expose unrestricted host operations. Installation, integration, memory use, accessibility, and hardware behavior remain to be validated.

## Users and security

Create and use a standard, non-root desktop account. Keep administrative access behind Mint's supported privilege elevation and authentication flow. Services run as dedicated system users where appropriate, with only the device access and capabilities they need. Avoid setuid helpers and broad group membership unless a documented feature requires them.

Keep authenticated package sources and security updates enabled, minimize listening services, and use signed packages. Store user data with normal per-user ownership and restrictive defaults. Native settings and hardware controls must use permission-checked system APIs and report unavailable operations honestly.

## Updates and recovery

For the first Mint-based image, retain Mint's authenticated package update path and the Ubuntu base security updates; do not add a custom updater until its trust and failure model are designed. Before changing a bootable image, provide a tested backup/recovery route and preserve user data. Define rollback behavior for failed updates before promising atomic updates or automatic rollback. A recovery environment may be explored through the separate Buildroot path, but it is not currently implemented.

## Desktop integration boundary

Mint supplies the Ubuntu-based kernel, drivers, base libraries, system services, desktop foundation, and package/update path. NEXUS supplies the desktop identity, shell additions, settings experience, application integration, and carefully permissioned interfaces. The current browser-based desktop is only a UI prototype; its preview controls are not Linux services. Keep this boundary explicit in user-facing status and code.

## Compatibility layers and future applications

Treat each compatibility feature as a conditional future integration with its own hardware, licensing, security, maintenance, and acceptance review:

- **Steam/Proton:** investigate after native graphics, audio, 32-bit libraries, Vulkan/OpenGL drivers, D-Bus, and X11 paths work. Test Steam installation/update and at least one Proton title before claiming support.
- **Wine:** optional Windows application compatibility, evaluated per use case and tested application; not a system-wide guarantee.
- **Waydroid:** optional Android container integration, only if kernel, graphics, binder, security, and distribution requirements can be met and maintained.
- **Darling:** exploratory macOS API compatibility, with feasibility and licensing reviewed before considering distribution.

**Quantum** is a future NEXUS application, not an OS component or currently delivered native app. Keep its product scope separate from base-system bring-up.

## Memory target

A 128 MB idle footprint is an aspiration for measurement, not an achieved result or a minimum requirement. Measure the booted system with a named metric (for example, MemAvailable and process/cgroup totals), a defined post-login idle interval, fixed VM hardware, and a recorded image digest. Repeat measurements and report enabled desktop features; the physical reference device has 4 GB RAM, and a graphical desktop may require substantially more than 128 MB.

## References

- [Linux Mint 22.3 Xfce edition](https://linuxmint.com/edition.php?id=327)
- [Linux Mint system requirements](https://linuxmint.com/faq.php)
- [Linux Mint release lifecycle](https://linuxmint.com/download_all.php)
- [Linux Mint ISO verification instructions](https://linuxmint.com/verify.php)
- [Ubuntu 26.04 release notes](https://documentation.ubuntu.com/release-notes/26.04/)
- [HP x360 14b service guide](https://kaas.hpcloud.hp.com/pdf-public/pdf_12135253_en-US-1.pdf)
- [MrChromebox supported devices](https://docs.mrchromebox.tech/docs/supported-devices)
- [Valve Steam for Linux](https://github.com/ValveSoftware/steam-for-linux)
- [Valve Steam support notice](https://help.steampowered.com/en/faqs/view/107F-BB20-FB5A-1CE4)
- [Buildroot manual](https://buildroot.org/downloads/manual/manual.html)
