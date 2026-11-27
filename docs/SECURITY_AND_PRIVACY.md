# NEXUS OS Security & Privacy Architecture (Phase 5–13.0)

## Core Principles

- **Honest status reporting:** Statuses use `pass` / `enabled`, `info`, `warn` / `attention_required`, `fail` / `disabled`, or `unavailable`. NEXUS never fabricates security scores, LUKS readiness, or bare-metal Secure Boot enforcement claims.
- **No bypass of Ubuntu/Mint protections:** Keeps APT GPG signature checks (`0` `trusted=yes` entries), `unattended-upgrades`, `ufw`, Polkit (`pkexec`), and standard non-root user permissions intact across Standard (`cinnamon`, `xfce`), Lite Openbox (`lite`), and Lite LXQt (`lite-lxqt`).
- **Clear APT vs Flatpak boundary:** Traditional APT packages run with the logged-in user's permissions and are never misrepresented as sandboxed. Only Flatpak applications expose per-app portal/sandbox permission controls (`nexus-security-cli.sh`).
- **Strict Production / Test Separation:** Ephemeral QEMU telemetry (`nexus-test-agent.service`, `org.nexus.test.0`, `/usr/local/libexec/nexus-test`) is injected only inside QEMU test runners and **never** exists inside built ISOs or `nexus-disk-install.sh` targets.

## Implemented Components

1. **`linux/security/nexus-security-audit.sh` (`/usr/local/bin/nexus-security-audit`)**:
   - Read-only auditor (`--json`, `--markdown`, `--root PATH`, `--repo PATH`, `--repo-only`, `--strict`) packaged across **all 4 editions** (`cinnamon`, `xfce`, `lite`, `lite-lxqt`), inspecting APT repository trust (`trusted=yes` and third-party URIs), UFW `/etc/ufw/ufw.conf`, `20auto-upgrades`, wildcard TCP listening sockets (`/proc/net/tcp*`), `/etc/sudoers.d` `NOPASSWD` rules, LightDM autologin overrides, `/etc/default/zramswap`, runtime test-agent separation, and static repository installer/channel hygiene.
   - Verified in QEMU across `lite` and `lite-lxqt` live sessions (`sec_summary`: `5 PASS, 2 WARN, 0 FAIL`) and in CI static checks (`2 PASS, 0 WARN, 0 FAIL` via `--repo-only --repo . --strict`).
2. **Privacy-Safe Hardware Qualification & Community Template (`linux/hardware/`)**:
   - `nexus-hw-inventory`, `nexus-hw-diagnostics`, and `nexus-hw-qualify` are strictly read-only by default, never record microphone audio, never log Wi-Fi SSIDs or credentials, strip serial numbers, MAC addresses, UUIDs, IPv4/IPv6 addresses, hostnames, and `/home/<USER>` paths, run a `privacy_audit` self-check, and set `auto_upload: false` (`human_review_required: true`) on `--contribute-template`.
   - Stage B hardware checks require explicit confirmation (`--confirm-test <name>`) and pre-run safety explanations; destructive disk/firmware/Secure-Boot actions are refused, and users are warned never to treat their primary computer or personal Chromebook as a disposable test target (`docs/HARDWARE_TESTING_GUIDE.md`).
3. **LUKS2 Installer Secret Hygiene (`linux/installer/nexus-disk-install.sh`)**:
   - Includes `core:cryptsetup` and `core:cryptsetup-initramfs` across all Lite manifests, strips trailing `\r\n` before piping passphrases to `cryptsetup --key-file -`, never stores passphrases on disk or in `/etc/nexus-installed.json`/logs, and writes `/usr/local/share/nexus-os/luks-recovery-guide.txt`.
   - Also packages `core:shim-signed`, `core:grub-efi-amd64-signed`, and `core:mokutil` across all 5 edition manifests and copies signed `shimx64.efi` (`BOOTX64.EFI`) + `grubx64.efi` during UEFI installation.
4. **`linux/mint/nexus-security-cli.sh` & `linux/mint/nexus-system-bridge.py`**:
   - Polkit-authenticated UFW toggling (`pkexec`), UEFI Secure Boot / LUKS status inspection, Flatpak sandbox permission inspection/overrides, and loopback-only token-authenticated bridge (`X-Nexus-Token` + Origin check).
5. **Settings Privacy & Security UI (`apps/settings-sections.js`)**:
   - Displays transparent security status with an explicit `Unavailable` boundary in standalone browser preview.

## Verification & Current Limits (`45876350800`, `45876358426`, `b4879cb`)

- **Verified in CI & QEMU:** `bash -n`, `shellcheck` across all scripts, `npm test`, `verify-nexus-iso.sh` (`0` test-agent leaks in `lite`, `lite-lxqt`, `cinnamon`, and `xfce` ISOs), `nexus-security-audit.sh --repo-only --repo . --strict` (`2 PASS, 0 WARN, 0 FAIL`), live QEMU `sec_summary` (`0 FAIL`), and end-to-end LUKS2 cold-boot wrong-passphrase rejection + valid unlock + reboot persistence.
- **Untested (`NOT TESTED`, requires Phase 13.0 CI / bare-metal validation):** Enforced OVMF Secure Boot CI run (`--secure-boot-test`), live `pkexec ufw` Polkit GUI prompts, UEFI Secure Boot on physical OEM firmware, interactive Ubiquity GUI `partman-auto-crypto` dialogs, and multi-user physical non-autologin deployments.
