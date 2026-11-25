# NEXUS OS Security & Privacy Architecture (Phase 5)

## Core Principles

- **Honest status reporting:** Statuses use `enabled`, `disabled`, `attention_required`, or `unavailable`. NEXUS never fabricates security scores, green checkmarks, or unverified Secure Boot / disk encryption claims.
- **No bypass of Linux Mint protections:** Keeps APT GPG signature checks, `unattended-upgrades`, `mintupdate`, Polkit (`pkexec`), and standard non-root user permissions intact.
- **Clear APT vs Flatpak boundary:** Traditional APT packages run with the logged-in user's full permissions and are never misrepresented as sandboxed. Only Flatpak applications expose per-app portal/sandbox permission controls (`flatpak info --show-permissions`, `flatpak override --user`).

## Implemented Components

1. **`linux/mint/nexus-security-cli.sh`**:
   - `status`: inspects UFW configuration (`/etc/ufw/ufw.conf` / `ufw`), UEFI Secure Boot (`/sys/firmware/efi/efivars/SecureBoot-*`), LUKS/dm-crypt (`lsblk`), `unattended-upgrades`, current user privilege flags (`is_root`, `in_admin_group`), and XDG autostart entries.
   - `firewall <enable|disable>`: delegates UFW changes through `pkexec` (Polkit authentication) and supports `--dry-run`.
   - `permissions <app-id>`, `flatpak-revoke <app-id> <flag>`, `flatpak-reset <app-id>`: inspects and restricts allowlisted per-user Flatpak sandbox permissions (`--nofilesystem=home`, `--nofilesystem=host`, `--nosocket=x11`, `--nosocket=wayland`, `--unshare=network`, `--nodevice=all`).
   - `startup-list`: lists user and system XDG `.desktop` autostart entries.

2. **`linux/mint/nexus-system-bridge.py` (`GET /api/security/status`)**:
   - Exposes `nexus-security-cli.sh status` over the loopback-only, token-authenticated local bridge (`X-Nexus-Token` + Origin check).

3. **Settings Privacy & Security UI (`apps/settings-sections.js`)**:
   - Displays a transparent security overview (`Firewall`, `Security updates`, `Disk encryption`, `UEFI Secure Boot`, `Flatpak permissions`, `Startup apps`) showing `Unavailable` in the browser prototype and live status badges + warnings when `"privacy-security"` is registered on `window.NexusNativeServices`.

## Verification & Current Limits

- **Tested locally & in CI:** `bash -n`, `shellcheck`, JSON output from `nexus-security-cli.sh status`, `--dry-run` UFW & Flatpak override commands, rejection of arbitrary override flags / malformed Flatpak IDs, `/api/security/status` over authenticated loopback HTTP, and Node UI boundary tests (`scripts/check-security-privacy.js`).
- **Requires booted Linux Mint hardware / VM (not yet tested):** Live `pkexec ufw` prompts, UEFI Secure Boot `efivars` toggling, LUKS partition verification on encrypted Mint installs, and `flatpak override` enforcement on installed Flatpak apps.
