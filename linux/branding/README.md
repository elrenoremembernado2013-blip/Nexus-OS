# NEXUS OS Branding Layer

Files in this directory supply non-invasive visual branding for Linux Mint 22.3
Xfce guests without overwriting `/etc/os-release` or replacing Mint core packages:

- `nexus-logo.svg`: vector emblem installed to `/usr/local/share/nexus-os/branding/nexus-logo.svg`.
- `nexus-firstboot.desktop`: XFCE autostart entry pointing to `/usr/local/bin/nexus-firstboot`.
- Panel, Whisker Menu, and GTK3 CSS overrides live in `linux/xfce/nexus-dark.css` and are applied per-user by `linux/mint/apply-nexus-xfce.sh`.

Boot (Plymouth/GRUB) and login (LightDM) branding assets remain future work and
should be packaged cleanly as additive configuration overrides once live guest testing
begins.
