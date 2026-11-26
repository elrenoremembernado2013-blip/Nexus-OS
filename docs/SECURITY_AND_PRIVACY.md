# NEXUS OS Security & Privacy Architecture (Phase 5–12.4)

## Core Principles

- **Honest status reporting:** Statuses use `pass` / `enabled`, `info`, `warn` / `attention_required`, `fail` / `disabled`, or `unavailable`. NEXUS never fabricates security scores or unverified Secure Boot / LUKS encryption claims.
- **No bypass of Ubuntu/Mint protections:** Keeps APT GPG signature checks (`0` `trusted=yes` entries), `unattended-upgrades`, `ufw`, Polkit (`pkexec`), and standard non-root user permissions intact across Standard, Openbox Lite, and LXQt Lite.
- **Clear APT vs Flatpak boundary:** Traditional APT packages run with the logged-in user's permissions and are never misrepresented as sandboxed. Only Flatpak applications expose per-app portal/sandbox permission controls (`nexus-security-cli.sh`).
- **Strict Production / Test Separation:** Ephemeral QEMU telemetry (`nexus-test-agent.service`, `org.nexus.test.0`, `/usr/local/libexec/nexus-test`) is injected only inside QEMU test runners and **never** exists inside built ISOs or `nexus-disk-install.sh` targets.

## Implemented Components

1. **`linux/security/nexus-security-audit.sh` (`/usr/local/bin/nexus-security-audit`)**:
   - Read-only auditor (`--json`, `--markdown`, `--root PATH`, `--repo PATH`, `--repo-only`, `--strict`) inspecting APT repository trust (`trusted=yes` and third-party URIs), UFW `/etc/ufw/ufw.conf`, `20auto-upgrades`, wildcard TCP listening sockets (`/proc/net/tcp*`), `/etc/sudoers.d` `NOPASSWD` rules, LightDM autologin overrides, `/etc/default/zramswap`, runtime test-agent separation, and static repository installer/channel hygiene.
   - Verified in QEMU across `lite` and `lite-lxqt` live sessions (`sec_summary`: `5 PASS, 2 WARN, 0 FAIL` — the `2` warnings correspond to live ISO non-Ubuntu/Mint `packages.linuxmint.com` vs upstream/live state & `casper`/live runner `ufw` pre-enable check, `0` FAIL) and in CI static checks (`2 PASS, 0 WARN, 0 FAIL` via `--repo-only --repo . --strict`).
2. **`linux/hardware/nexus-hw-diagnostics.sh` (`/usr/local/bin/nexus-hw-diagnostics`)**:
   - Privacy-preserving hardware/connectivity diagnostics omitting serials, MAC addresses, UUIDs, usernames, and external IPs; never auto-uploads data.
3. **`linux/mint/nexus-security-cli.sh` & `linux/mint/nexus-system-bridge.py`**:
   - Polkit-authenticated UFW toggling (`pkexec`), UEFI Secure Boot / LUKS status inspection, Flatpak sandbox permission inspection/overrides, and loopback-only token-authenticated bridge (`X-Nexus-Token` + Origin check).
4. **Settings Privacy & Security UI (`apps/settings-sections.js`)**:
   - Displays transparent security status (`Firewall`, `Security updates`, `Disk encryption`, `UEFI Secure Boot`, `Flatpak permissions`, `Startup apps`) with explicit `Unavailable` boundary in standalone browser preview.

## Verification & Current Limits

- **Verified in CI & QEMU (`45808626482`, `45808636617`):** `bash -n`, `shellcheck`, `npm test`, `verify-nexus-iso.sh` (`unmkinitramfs` + `unsquashfs` zero test-agent leaks on both `lite` and `lite-lxqt` ISOs), `nexus-security-audit.sh --repo-only --repo . --strict`, live QEMU `sec_summary` (`0 FAIL`), and non-root `/etc/sudoers.d` permission handling.
- **Untested (requires bare-metal / manual interactive validation):** Live `pkexec ufw` Polkit GUI prompts, UEFI Secure Boot enforced mode with signed `shimx64.efi`, interactive Ubiquity LUKS+LVM passphrase entry and cold-boot unlock, and multi-user physical non-autologin deployments.
