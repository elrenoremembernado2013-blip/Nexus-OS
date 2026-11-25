# NEXUS Linux configuration directory

This directory holds human-reviewed NEXUS host/guest defaults for the Linux Mint 22.3 Xfce foundation milestone (`nexus-system.conf`). `scripts/launch-qemu.sh` reads `NEXUS_TARGET_RAM_MB` as a fallback default when `NEXUS_RAM_MB` is unset; no custom OS image builder consumes these files yet. Do not put credentials, private keys, tokens, or machine-specific secrets here.
