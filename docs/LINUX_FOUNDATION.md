# NEXUS OS Linux Foundation

## Status and decision

For the HP Chromebook x360 14b reference device, the first-choice base is **Linux Mint 22.3 Xfce**, on Ubuntu 24.04 LTS (Noble). This is the better starting desktop for the reported 4 GB RAM and 32 GB eMMC: Mint recommends 4 GB RAM and requires at least 20 GB disk, while Ubuntu 26.04 Desktop lists 6 GB RAM and 25 GB free storage for a comfortable experience. Ubuntu minimal/server remains an alternative only if Mint has a documented blocker or fails qualification. The exact Mint release is pinned for this milestone and should be reassessed before later builds.

The repository contains a signed-media verification script, a QEMU launcher, and an experimental Buildroot external tree. The scripts can acquire official Mint media, verify its signed manifest and image digest, and launch a stock Mint guest. They do not build or boot a customized NEXUS image. NEXUS is not yet a bootable OS.

## Repository roles

- `scripts/download-linux-mint.sh`: acquire Linux Mint 22.3 Xfce and verify its signed checksum manifest and ISO digest.
- `scripts/download-ubuntu.sh`: retained Ubuntu media path for explicit comparison or fallback; not the default.
- `scripts/launch-qemu.sh`: run the Mint installer or an installed guest using UEFI/OVMF.
- `linux/config/`: declarative design defaults; not consumed by an image build.
- `nexus-br2-external/`: separate Buildroot external-tree entry points for future lightweight experiments.
- `docs/PLATFORM_ARCHITECTURE.md`: platform, session, security, compatibility, and acceptance decisions.

## Foundation decisions

1. **Primary base:** Linux Mint 22.3 Xfce (Ubuntu Noble 24.04 package base).
2. **Alternate base:** Ubuntu minimal/server only after documenting a Mint blocker or failed resource/hardware qualification.
3. **Reference device:** HP Chromebook x360 14b-cb0 (MADOO), N4500, 4 GB RAM, 32 GB eMMC.
4. **Target boot:** x86-64 UEFI/OVMF in QEMU, then separate physical-device qualification; GRUB for initial boot.
5. **Desktop prototype:** Mint Xfce session, X11, and Xfwm4; begin with theme/panel/menu changes, then one focused NEXUS panel integration.
6. **Validation:** QEMU tests the generic guest workflow only; Chromebook firmware and drivers require physical-device checks.
7. **Buildroot:** experimental lightweight/appliance or recovery-image path, not the primary desktop.
8. **Memory:** 128 MB idle is an aspiration only. No measurement or achievement is claimed.

## Desktop prototype baseline

Use Mint Xfce for the first native desktop spike. Customize the Xfce theme, panel, menu, and NEXUS identity; keep Xfwm4 and established session services. Defer a separate NEXUS shell until memory and storage use are measured on the reference device. This avoids starting with a custom compositor or a larger desktop stack on a 4 GB system.

Keep the existing HTML/CSS/JavaScript desktop as a design reference; do not claim it is already native or directly reusable. Check login, panel/menu, window operations, keyboard access, reduced-motion behavior, logout, package versions, memory, and disk use in QEMU before the physical-device test. Then test MADOO hardware separately.

## Reproducibility requirements

The Mint media script authenticates the signed SHA-256 manifest using the Linux Mint ISO signing key's published fingerprint and checks the ISO digest. This does not make a customized NEXUS image reproducible. Before building such an image, pin and record the Mint release/edition artifact, checksum, signing fingerprint, package sources and versions, tools, kernel and boot components, desktop dependencies, and external source revisions. Use immutable revisions or checksums, a clean documented build environment, and a recorded output digest. Compare independent clean builds before describing results as reproducible. Never publish guessed pins or checksums.

## QEMU acceptance gate

Before calling a NEXUS image bootable, it must boot from a clean virtual disk through x86-64 UEFI/OVMF and GRUB, reach a usable Mint Xfce-based NEXUS session, exercise the declared virtio input/display/storage/network/audio devices, and shut down cleanly. Record the image digest, QEMU and OVMF versions, exact launch command, VM profile, and results. Verify standard-user access and elevation boundaries. A successful Mint installer boot is not NEXUS image acceptance. QEMU also does not establish Chromebook-specific compatibility.

## Services, session, and permissions

Use systemd for system boot and service supervision. Run the Xfce graphical session and desktop apps under a standard user account, not root. Require authenticated elevation for administrative tasks; use dedicated service accounts and narrow device permissions where services need them. Prefer established D-Bus, portal, networking, audio, and device interfaces. Avoid broad privileges and unnecessary listening services. Keep Mint's authenticated update path and its Ubuntu security updates enabled. The shell must not claim privileged hardware control until a permission-checked native service exists.

## Updates and recovery

Use Mint's authenticated package update path for the initial base. Before distributing a bootable image, document how user data is protected and how a failed update or disk problem can be recovered. Test a recovery path before promising rollback or atomic updates. Buildroot may be evaluated for a recovery environment, but no such environment currently exists. Do not add an unreviewed custom updater.

## Desktop and compatibility boundary

Mint supplies the Ubuntu-based kernel, drivers, libraries, system services, desktop foundation, and package/update base; NEXUS supplies its desktop identity, shell additions, application integration, and permission-checked interfaces. The browser prototype is not the native desktop and does not control the host.

Steam/Proton, Wine, Waydroid, and Darling remain future conditional integrations, each requiring feasibility, security, maintenance, and feature-specific testing before inclusion or compatibility claims. Steam/Proton additionally depends on tested multilib and graphics drivers, Vulkan/OpenGL, audio, and display integration. Quantum is a future application, not part of the base OS or a delivered native feature.

## Current readiness

- [x] Linux Mint Xfce selected as primary for the reported Chromebook constraints; Ubuntu minimal/server retained as a conditional alternative.
- [x] x86-64, UEFI/OVMF, GRUB, systemd, and QEMU-first direction recorded.
- [x] Buildroot scoped as experimental, separate lightweight image work.
- [x] 128 MB idle described as an unverified aspiration.
- [x] Download and verify pinned Mint media on the Mac host; the signed manifest and ISO SHA-256 both passed on 2026-11-23.
- [x] Boot the stock Mint installer to its Xfce live desktop in QEMU using compatibility mode on 2026-11-24. Normal mode remained on a black screen after the splash. In compatibility mode, the desktop appeared after startup logs and a guest key event refreshed the captured display. This confirms only the stock Mint live environment under Mac TCG, not a NEXUS image or Chromebook compatibility.
- [ ] Reproduce the live desktop observation before starting the Xfce customization milestone. A separate exploratory QEMU 11.1.3 TCG retry on 2026-11-24 used 4 GiB RAM, 2 vCPUs, UEFI, the verified Mint ISO, and compatibility mode. Startup logs appeared, but after switching virtual consoles the captured display was black; no usable desktop or resource measurement was confirmed. This retry used a temporary host-share device and is inconclusive; it does not replace the earlier recorded live-desktop pass. A standard-VGA comparison was started but stopped before a result. No Chromebook firmware or storage was touched.
- A further 2026-11-24 attempt without the host-share device also showed a black captured frame and did not reach the UEFI menu within the first minute; QEMU then exited without an error in the captured output. The cause is unknown. Do not treat either retry as evidence about MADOO or as an OS boot result; resolve a repeatable QEMU baseline before applying native Xfce changes.
- A separate UTM x86-64 emulation run on 2026-11-24 (Q35/ICH9, UEFI, 4 GiB RAM, 2 cores, 24 GiB virtual disk, default virtio-gpu; exact UTM build not recorded) reached Mint's GRUB menu from the verified ISO. After selecting compatibility mode, the display reported `Display output is not active.` and no usable live desktop was confirmed. The VM was stopped. This is inconclusive; it does not establish the cause or Chromebook compatibility. The temporary UTM bundle is at `/private/tmp/NEXUS Mint Disposable Test.utm`.
- [ ] Prototype Xfce theme/panel/menu changes and measure resource use.
- [ ] Add reviewed image configuration and repeatable build tooling.
- [ ] Build a custom image and meet the QEMU acceptance criteria.
- [ ] Test the image on MADOO only after firmware/recovery steps are independently reviewed.
- [ ] Measure idle memory and storage using documented, repeatable methods.
- [ ] Test and document user-data recovery and update failure handling.
- [ ] Evaluate compatibility integrations individually before making support claims.

## Safety principles

- Keep generated images, downloads, and VM state under ignored build output directories.
- Never commit credentials, private keys, personal data, or guest state.
- Verify upstream versions and signatures before pinning inputs.
- Keep browser-preview behavior distinct from native OS functionality.
