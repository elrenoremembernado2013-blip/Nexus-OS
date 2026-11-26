#!/usr/bin/env bash
# Read-only NEXUS OS Security Audit utility.
# Inspects APT repo trust, UFW, unattended-upgrades, listeners, sudoers,
# autostart/autologin, ZRAM, installer safety, and production/test separation.
set -euo pipefail

FORMAT="json"
ROOT_PREFIX="/"
REPO_CHECK=""
STRICT=false

usage() {
  cat <<'USAGE'
Usage: bash linux/security/nexus-security-audit.sh [OPTIONS]

Performs a read-only security audit of the running Linux host/chroot and/or
NEXUS repository scripts without emitting secrets or passwords.

Options:
  --json           Output JSON audit report (default)
  --markdown       Output Markdown audit report
  --root PATH      Target root filesystem prefix (default: /)
  --repo PATH      Also run static repository security checks against PATH
  --strict         Exit non-zero if any finding has severity=fail
  --help, -h       Show this help message
USAGE
}

while (($#)); do
  case "$1" in
    --json) FORMAT="json"; shift ;;
    --markdown) FORMAT="markdown"; shift ;;
    --root) [[ $# -ge 2 ]] || { echo '--root requires a path' >&2; exit 2; }; ROOT_PREFIX="$2"; shift 2 ;;
    --repo) [[ $# -ge 2 ]] || { echo '--repo requires a path' >&2; exit 2; }; REPO_CHECK="$2"; shift 2 ;;
    --strict) STRICT=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

python3 - "$FORMAT" "$ROOT_PREFIX" "$REPO_CHECK" "$STRICT" <<'PY'
import datetime
import json
from pathlib import Path
import re
import sys

fmt = sys.argv[1]
root = Path(sys.argv[2])
repo_arg = sys.argv[3]
strict = sys.argv[4] == "true"

findings = []

def add_finding(check_id, severity, area, message, details=None):
    findings.append({
        "id": check_id,
        "severity": severity,  # pass | info | warn | fail
        "area": area,
        "message": message,
        "details": details,
    })

# 1. APT repository & signing trust
sources_files = []
main_src = root / "etc/apt/sources.list"
if main_src.is_file():
    sources_files.append(main_src)
src_d = root / "etc/apt/sources.list.d"
if src_d.is_dir():
    sources_files.extend(sorted(src_d.glob("*.list")) + sorted(src_d.glob("*.sources")))

untrusted_opts = []
repo_uris = []
trusted_hosts = ("ubuntu.com", "linuxmint.com", "canonical.com", "archive.ubuntu.com", "security.ubuntu.com", "packages.linuxmint.com")
third_party_uris = []
for sf in sources_files:
    txt = sf.read_text(encoding="utf-8", errors="replace")
    for line in txt.splitlines():
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        if "trusted=yes" in s.lower():
            untrusted_opts.append(f"{sf.name}: {s[:120]}")
        for m in re.findall(r"https?://[^\s'\"]+", s):
            repo_uris.append(m)
            host = m.split("/")[2].lower()
            if not any(host == th or host.endswith("." + th) for th in trusted_hosts):
                third_party_uris.append(m)

if sources_files:
    if untrusted_opts:
        add_finding("apt_trusted_yes", "fail", "apt", "Found APT source with trusted=yes bypassing GPG verification.", untrusted_opts)
    elif third_party_uris:
        add_finding("apt_repos", "warn", "apt", "Detected non-Ubuntu/Mint APT repository URI.", third_party_uris[:8])
    else:
        add_finding("apt_repos", "pass", "apt", f"Verified {len(sources_files)} APT source config(s); official Ubuntu/Mint signed URIs only.", len(repo_uris))
else:
    add_finding("apt_repos", "info", "apt", "No /etc/apt/sources.list* present under target root.")

# 2. Firewall (UFW)
ufw_conf = root / "etc/ufw/ufw.conf"
if ufw_conf.is_file():
    utxt = ufw_conf.read_text(encoding="utf-8", errors="replace")
    if re.search(r"^ENABLED=yes", utxt, re.M):
        add_finding("firewall_ufw", "pass", "firewall", "UFW firewall configured ENABLED=yes.")
    else:
        add_finding("firewall_ufw", "warn", "firewall", "UFW present but ENABLED=no in /etc/ufw/ufw.conf.")
else:
    add_finding("firewall_ufw", "info", "firewall", "UFW config not present under target root.")

# 3. Unattended security upgrades
auto_upg = root / "etc/apt/apt.conf.d/20auto-upgrades"
if auto_upg.is_file():
    atxt = auto_upg.read_text(encoding="utf-8", errors="replace")
    if 'Unattended-Upgrade "1"' in atxt:
        add_finding("unattended_upgrades", "pass", "updates", "Unattended security upgrades enabled.")
    else:
        add_finding("unattended_upgrades", "warn", "updates", "20auto-upgrades exists but Unattended-Upgrade is not '1'.")
else:
    add_finding("unattended_upgrades", "info", "updates", "20auto-upgrades not present under target root.")

# 4. Listening TCP sockets (when inspecting running host '/')
if str(root) == "/" and Path("/proc/net/tcp").is_file():
    wildcard_ports = []
    for pfile, proto in ((Path("/proc/net/tcp"), "tcp4"), (Path("/proc/net/tcp6"), "tcp6")):
        if not pfile.is_file():
            continue
        for line in pfile.read_text(encoding="utf-8", errors="replace").splitlines()[1:]:
            cols = line.split()
            if len(cols) >= 4 and cols[3] == "0A":  # LISTEN
                addr_hex, port_hex = cols[1].split(":")
                port = int(port_hex, 16)
                if addr_hex in ("00000000", "00000000000000000000000000000000"):
                    wildcard_ports.append(f"{proto}:{port}")
    if wildcard_ports:
        add_finding("listening_ports", "info", "network", f"Wildcard listening sockets detected ({len(wildcard_ports)}); verify none are unapproved daemons.", sorted(set(wildcard_ports))[:15])
    else:
        add_finding("listening_ports", "pass", "network", "Zero wildcard (0.0.0.0/[::]) TCP listening sockets detected.")

# 5. Sudoers check (without leaking user details)
sudoers_d = root / "etc/sudoers.d"
nopass_files = []
if sudoers_d.is_dir():
    for f in sorted(sudoers_d.iterdir()):
        if not f.is_file():
            continue
        try:
            txt = f.read_text(encoding="utf-8", errors="replace")
            if "NOPASSWD" in txt and "casper" not in f.name.lower():
                nopass_files.append(f.name)
        except OSError:
            pass
if nopass_files:
    add_finding("sudoers_nopasswd", "warn", "privileges", "Non-live sudoers.d entries contain NOPASSWD.", nopass_files)
else:
    add_finding("sudoers_nopasswd", "pass", "privileges", "No unexpected NOPASSWD sudoers rules detected.")

# 6. LightDM autologin check
dm_dir = root / "etc/lightdm/lightdm.conf.d"
autologin_cfgs = []
if dm_dir.is_dir():
    for f in sorted(dm_dir.glob("*.conf")):
        txt = f.read_text(encoding="utf-8", errors="replace")
        if re.search(r"^\s*autologin-user\s*=", txt, re.M):
            autologin_cfgs.append(f.name)
if autologin_cfgs:
    add_finding("lightdm_autologin", "info", "authentication", "LightDM autologin configured (expected in live ISO / CI test VMs; review for multi-user physical installs).", autologin_cfgs)
else:
    add_finding("lightdm_autologin", "pass", "authentication", "No unconditional LightDM autologin override present.")

# 7. ZRAM configuration
zram_cfg = root / "etc/default/zramswap"
if zram_cfg.is_file():
    ztxt = zram_cfg.read_text(encoding="utf-8", errors="replace")
    add_finding("zram_config", "pass", "memory", "ZRAM config present in /etc/default/zramswap.", [l for l in ztxt.splitlines() if l and not l.startswith("#")])

# 8. Production vs Test Infrastructure Separation
test_unit = root / "etc/systemd/system/nexus-test-agent.service"
test_libexec = root / "usr/local/libexec/nexus-test"
active_test_port = Path("/dev/virtio-ports/org.nexus.test.0").exists()
if test_unit.exists() or test_libexec.exists():
    if str(root) == "/" and active_test_port:
        add_finding("test_separation", "info", "separation", "Running inside ephemeral QEMU test VM with virtio-serial port active.")
    else:
        add_finding("test_separation", "fail", "separation", "Test-only telemetry agent/service found inside non-test root filesystem!")
else:
    add_finding("test_separation", "pass", "separation", "Zero test-agent units or scripts found in target filesystem.")

# 9. Static Repository Audit (when --repo is provided)
if repo_arg:
    repo = Path(repo_arg)
    prod_dirs = [repo / "linux" / d for d in ("mint", "cinnamon", "lite", "xfce", "installer", "hardware") if (repo / "linux" / d).is_dir()]
    leak_hits = []
    for pd in prod_dirs:
        for fp in pd.rglob("*"):
            if fp.is_file() and fp.suffix in (".sh", ".py", ".conf", ".list", ".desktop"):
                content = fp.read_text(encoding="utf-8", errors="replace")
                if "org.nexus.test.0" in content:
                    leak_hits.append(str(fp.relative_to(repo)))
                elif "nexus-test-agent.service" in content and fp.name != "nexus-disk-install.sh":
                    leak_hits.append(str(fp.relative_to(repo)))
    if leak_hits:
        add_finding("repo_test_separation", "fail", "separation", "Production linux/ directories reference test-only channels or units.", leak_hits)
    else:
        add_finding("repo_test_separation", "pass", "separation", "Zero test-only channel/unit references in production linux/ directories.")

    disk_inst = repo / "linux/installer/nexus-disk-install.sh"
    if disk_inst.is_file():
        dtxt = disk_inst.read_text(encoding="utf-8", errors="replace")
        has_guard = "--yes-erase-disk" in dtxt and "Refusing destructive disk" in dtxt
        no_hardcoded_pw = "PASSWORD_HASH=" in dtxt and "chpasswd -e" in dtxt
        if has_guard and no_hardcoded_pw:
            add_finding("repo_installer_safety", "pass", "installer", "nexus-disk-install.sh enforces --yes-erase-disk and avoids hardcoded passwords.")
        else:
            add_finding("repo_installer_safety", "fail", "installer", "nexus-disk-install.sh missing destructive guard or password hygiene.")

fail_count = sum(1 for f in findings if f["severity"] == "fail")
warn_count = sum(1 for f in findings if f["severity"] == "warn")
pass_count = sum(1 for f in findings if f["severity"] == "pass")

report = {
    "generated_at_utc": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "target_root": str(root),
    "summary": {"pass": pass_count, "warn": warn_count, "fail": fail_count},
    "findings": findings,
}

if fmt == "markdown":
    print("# NEXUS OS Security Audit Report")
    print(f"- **Target Root:** `{root}`")
    print(f"- **Summary:** `{pass_count}` PASS, `{warn_count}` WARN, `{fail_count}` FAIL\n")
    for f in findings:
        print(f"- **[{f['severity'].upper()}]** `{f['id']}` ({f['area']}): {f['message']}")
else:
    print(json.dumps(report, indent=2))

if strict and fail_count > 0:
    sys.exit(1)
PY
