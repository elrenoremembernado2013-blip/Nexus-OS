# NEXUS OS Linux Foundation

## Status and decision

The first full NEXUS desktop foundation is **Ubuntu 26.04 LTS minimal/server**. Linux Mint is a fallback only if a specific, documented blocker makes Ubuntu unsuitable; Mint is not a competing default or a parallel build target.

The current repository contains verified-media and QEMU helper scripts plus an initial Buildroot external-tree scaffold. The scripts can download official Ubuntu media, verify it against the signed checksum manifest, and launch a stock Ubuntu installer or guest. They do not create a customized NEXUS image. The Buildroot tree is experimental scaffolding and is not ready to build or boot. NEXUS is not yet a bootable OS.

## Repository roles

- `scripts/download-ubuntu.sh`: acquire Ubuntu Server media and verify its signed checksum manifest.
- `scripts/launch-qemu.sh`: run the installer or an installed Ubuntu guest using UEFI/OVMF.
- `linux/config/`: declarative design defaults; not consumed by an image build.
- `nexus-br2-external/`: separate Buildroot external-tree entry points for future lightweight experiments.
- `docs/PLATFORM_ARCHITECTURE.md`: full platform, session, security, compatibility, and acceptance decisions.

## Foundation decisions

1. **Primary base:** Ubuntu 26.04 LTS minimal/server, customized by NEXUS.
2. **Fallback:** Linux Mint only after recording an Ubuntu blocker and evaluating the tradeoffs; do not maintain both as equal targets.
3. **Target:** x86-64 PC/VM, UEFI firmware via OVMF in QEMU, and GRUB for initial boot.
4. **Desktop prototype:** KWin Wayland with the Plasma shell and Qt Quick/QML; start with a NEXUS theme/layout and one custom plasmoid. This is a selected spike baseline, pending QEMU and memory validation.
5. **Validation:** QEMU acceptance before physical-hardware claims. The existing QEMU script currently runs a stock Ubuntu guest.
6. **Buildroot:** experimental lightweight/appliance or recovery-image path, not the primary general-purpose desktop.
7. **Memory:** 128 MB idle is an aspiration only. No measurement or achievement is claimed.

## Desktop stack prototype baseline

Use KWin on Wayland with the Plasma shell and Qt Quick/QML for the first native desktop spike. Customize Plasma's global theme and panel layout, then add one focused QML plasmoid. Keep the existing HTML/CSS/JavaScript desktop as a design reference; do not claim it is already native or directly reusable. This avoids writing a compositor and lets the spike test whether Plasma can express the NEXUS desktop while running on Ubuntu.

The tradeoff is package and memory overhead versus a minimal compositor such as labwc. GNOME Shell/Mutter would follow Ubuntu's default desktop more closely but would couple NEXUS to GNOME extension behavior. The selection is only a prototype baseline. Check login, panel/launcher, QML widget, window operations, accessibility, logout, package versions, and memory in QEMU before keeping it as the production direction. No memory target is presumed met.

## Reproducibility requirements

The signed-manifest check makes downloaded Ubuntu media verifiable, but does not make a customized NEXUS image reproducible. Before building such an image, pin and record the Ubuntu point-release artifact and checksum, package sources and versions, toolchain/build tools, kernel and boot components, desktop dependencies, and external source revisions. Use authenticated sources, immutable revisions or checksums, a clean documented build environment, and a recorded output digest. Compare independent clean builds before describing results as reproducible. Never publish guessed pins or checksums.

## QEMU acceptance gate

Before calling a NEXUS image bootable, it must boot from a clean virtual disk through x86-64 UEFI/OVMF and GRUB, reach a usable Wayland session, exercise the declared virtio input/display/storage/network/audio devices, and shut down cleanly. Record the image digest, QEMU and OVMF versions, exact launch command, VM profile, and observed results. Verify standard-user access and elevation boundaries. These criteria are not yet met by the current stock-Ubuntu workflow.

## Services, session, and permissions

Use systemd for system boot and service supervision. Run the graphical session and desktop apps under a standard user account, not root. Require authenticated elevation for administrative tasks; use dedicated service accounts and narrow device permissions where services need them. Prefer established D-Bus, portal, networking, audio, and device interfaces. Avoid broad privileges and unnecessary listening services. Keep Ubuntu's authenticated security update path enabled. The shell must not claim privileged hardware control until a permission-checked native service exists.

## Updates and recovery

Use Ubuntu's authenticated package updates for the initial base. Before distributing a bootable image, document how user data is protected and how a failed update or disk problem can be recovered. Test a recovery path before promising rollback or atomic updates. Buildroot may be evaluated for a recovery environment, but no such environment currently exists. Do not add an unreviewed custom updater.

## Desktop and compatibility boundary

Ubuntu provides the kernel, drivers, libraries, system services, and package/update base; NEXUS provides the shell, desktop identity, applications, and permission-checked integrations. The browser prototype is not the native desktop and does not control the host.

Steam/Proton, Wine, Waydroid, and Darling are future conditional integrations, each requiring a feasibility, security, maintenance, and feature-specific test before inclusion or compatibility claims. Steam/Proton additionally depends on tested multilib and graphics drivers, Vulkan/OpenGL, audio, D-Bus, and XWayland. Quantum is a future application, not part of the base OS or a delivered native feature.

## Current readiness

- [x] Ubuntu selected as the primary base; Mint specified as contingency only.
- [x] x86-64, UEFI/OVMF, GRUB, systemd, and QEMU-first direction recorded.
- [x] Buildroot scoped as experimental, separate lightweight image work.
- [x] 128 MB idle described as an unverified aspiration.
- [ ] Verify and pin exact Ubuntu media and build inputs for a custom image.
- [ ] Prototype the KWin/Plasma/QML baseline in QEMU and measure its memory use before treating it as production-ready.
- [ ] Add reviewed image configuration and repeatable build tooling.
- [ ] Build a custom image and meet the QEMU acceptance criteria.
- [ ] Measure idle memory using a documented, repeatable method.
- [ ] Test and document user-data recovery and update failure handling.
- [ ] Evaluate compatibility integrations individually before making support claims.

## Safety principles

- Keep generated images, downloads, and VM state under ignored build output directories.
- Never commit credentials, private keys, personal data, or guest state.
- Verify upstream versions and checksums before pinning inputs.
- Keep browser-preview behavior distinct from native OS functionality.
