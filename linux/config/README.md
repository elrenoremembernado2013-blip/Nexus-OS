# NEXUS Linux configuration directory

This directory holds human-reviewed NEXUS host/guest defaults for the Linux Mint 22.3 Xfce foundation:

- `nexus-system.conf`: base OS, architecture, memory/storage targets, X11/Xfwm4, and UEFI/GRUB defaults consumed by `scripts/launch-qemu.sh` (`NEXUS_TARGET_RAM_MB`), `linux/mint/nexus-panel-status.sh`, `linux/mint/provision-nexus-guest.sh`, and `linux/build/build-nexus-iso.sh`.
- `mint-packages.list`: categorized APT package manifest (`core`, `desktop`, `nexus`, `gaming`, `development`, `optional`) consumed by `provision-nexus-guest.sh` and `build-nexus-iso.sh`.

Do not put credentials, private keys, tokens, or machine-specific secrets here.
