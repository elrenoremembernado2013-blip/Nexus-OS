# MADOO Chromebook Qualification Plan

## Status

**Status: not yet qualified.** NEXUS has not been installed or tested on the owner's Chromebook. The Mac QEMU run only confirms that the stock Linux Mint live environment reached its desktop in a virtual machine.

The target reported by the owner is an HP Chromebook x360 14b with MADOO board, Intel Celeron N4500 (2 cores/2 threads), 4 GB RAM, and 32 GB eMMC. Firmware version reported: 158.16868.0. Confirm the exact product/model identifier and hardware revision from ChromeOS before choosing any firmware or OS path. HP documents more than one display and wireless configuration for this family, so the model name alone does not identify all devices.

## Safe qualification sequence

1. **Record the exact unit.** In stock ChromeOS, record the model/product name, board name, hardware ID, firmware version, storage capacity, and available device information for the Wi-Fi adapter and display. Do not publish serial numbers or other unique identifiers.
2. **Prepare recovery first.** Back up local files and make sure the owner can restore ChromeOS with a recovery USB and has access to the Google account used on the device. Google's Developer Mode transition erases local data. ChromeOS recovery also erases local data. Keep the recovery media separate from the Chromebook.
3. **Prefer reversible live qualification.** MrChromebox lists HP Chromebook x360 14b-cb0 / MADOO as supporting RW_LEGACY and UEFI Full ROM paths. For an initial test, evaluate the supported RW_LEGACY route to boot external live media while retaining the existing ChromeOS firmware and internal installation. Do not select Full ROM firmware for this milestone. Confirm the exact board against the current upstream device guidance immediately before any device-side action.
4. **Live-test before installing.** Boot the signed Mint Xfce live image from external media. Do not launch the installer or write to internal eMMC. Run the checks below and record results, exact image digest, kernel, and relevant hardware IDs.
5. **Decide from evidence.** Any failed core function leaves the device unqualified. Fix and repeat the live test, or document the blocker and reconsider the base. Only after the complete matrix passes should an installation plan be written, with a verified recovery route and a measured storage budget.

Developer Mode and firmware changes can erase or endanger local data. This plan does not authorize or perform those device changes. Review the current MrChromebox and Google instructions before proceeding; do not treat this document as a flashing guide.

## Live-media acceptance matrix

Record each item as **Pass**, **Fail**, or **Not tested**, with a short observation. Do not infer a pass from QEMU.

| Area | Pass condition |
|---|---|
| Boot and shutdown | Live image boots from external media through the chosen supported path; restart and shutdown complete without repair. |
| Display and graphics | Internal panel works at its native resolution; brightness controls work; graphical session remains stable and hardware acceleration status is recorded. |
| Input and convertible use | Built-in keyboard, touchpad, touchscreen, volume/brightness keys, and tablet/hinge behavior work as applicable; rotation is checked if the unit exposes it. |
| Wireless | Identify the installed adapter; Wi-Fi connects, obtains network access, and remains connected through a reboot. |
| Bluetooth | Adapter is detected and can pair and reconnect to a test device, if present. |
| Audio | Internal speakers, headphone output, microphone, and volume/mute controls are checked individually. |
| Camera | Camera is detected and a preview works, if present. |
| Power | Suspend and resume work at least three times; battery status and charging are reported correctly while unplugged and connected to power. |
| Ports and storage | Available USB-C, USB-A, and card-reader ports are checked with removable test media; internal eMMC is detected and its capacity is recorded without writing to it. |
| Stability | Complete three cold boots and one full sleep/wake cycle without a hang, display loss, or unexplained reboot. |
| Resource fit | Record RAM after login and after five minutes idle, CPU use, free live-session storage, and the amount of internal storage the proposed installed system would leave for updates and user data. No 128 MB idle claim is implied. |

A feature not present on the exact unit may be marked “Not applicable” with evidence. Missing or unstable Wi-Fi, display, input, suspend/resume, or recovery access is a blocker for an everyday-use recommendation. Other gaps must be documented before deciding whether the device still meets the intended use.

## Constraints and scope

- 4 GB RAM and 32 GB eMMC are fixed reported limits; HP service documentation describes memory as soldered for this family. Leave meaningful room for system updates, recovery, and user files.
- The N4500 is a two-core Jasper Lake processor. This makes an x86-64 Mint Xfce live test plausible, but does not prove that the exact Chromebook hardware works.
- The selected base remains Linux Mint Xfce on Ubuntu LTS. Ubuntu minimal/server is a fallback only if Mint has a documented blocker or fails qualification.
- Buildroot remains an experimental lightweight-image path, not the desktop target.
- No native NEXUS image, installer, or Chromebook-specific driver configuration has passed these checks yet.

## References

- [MrChromebox supported devices](https://docs.mrchromebox.tech/docs/supported-devices)
- [MrChromebox getting started and firmware paths](https://docs.mrchromebox.tech/docs/getting-started.html)
- [HP Chromebook x360 14b service guide](https://kaas.hpcloud.hp.com/pdf-public/pdf_12135253_en-US-1.pdf)
- [Google Chromebook recovery](https://support.google.com/chromebook/answer/1080595?hl=en)
- [Google Developer Mode data warning](https://support.google.com/chrome/a/answer/1360642?hl=en)
- [Intel Celeron N4500 specifications](https://www.intel.com/content/www/us/en/products/sku/212326/intel-celeron-processor-n4500-4m-cache-up-to-2-80-ghz/specifications.html)

Hardware and upstream instructions checked 2026-11-24. Recheck upstream guidance before device work.
