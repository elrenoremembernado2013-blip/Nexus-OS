# NEXUS Linux configuration directory

This directory holds human-reviewed NEXUS host/guest defaults for the Linux Mint 22.3 foundation:

- `nexus-standard-cinnamon.conf`: flagship **NEXUS Standard** defaults (`cinnamon` / Muffin, `>= 2 GiB` min / `4 GiB` recommended).
- `cinnamon-packages.list`: categorized APT manifest for the flagship Standard Cinnamon ISO (`build-nexus-iso.sh --edition cinnamon`).
- `nexus-system.conf`: historical 4 GB / 32 GB MADOO Chromebook baseline (`xfce` / Xfwm4), preserved intact for `launch-qemu.sh` and legacy Xfce target builds (`build-nexus-iso.sh --edition xfce`).
- `mint-packages.list`: categorized APT package manifest for the Xfce target.

Note: **NEXUS Lite** (`Openbox + tint2 + zram`) lives separately under `linux/lite/` (`nexus-lite.conf`, `lite-packages.list`) so editions never overwrite each other.

Do not put credentials, private keys, tokens, or machine-specific secrets here.
