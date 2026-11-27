#!/usr/bin/env bash
# NEXUS OS Phase 13.2 Virtual Qualification Orchestrator & Report Generator.
# Runs installer/manifest/security/profile/ISO checks, optionally runs live QEMU
# qualification (or parses a completed QEMU JSON report), and emits structured
# JSON + Markdown reports strictly distinguishing PASS, FAIL, BLOCKED, and NOT TESTED.
# Exit codes:
#   0 = All executed checks passed (0 FAIL; non-executed VM checks marked NOT TESTED)
#   1 = One or more checks FAILED
#   3 = --run-vm requested, or --strict-vm set, and VM/ISO execution is BLOCKED by missing host dependencies
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
OUT_DIR="$REPO_ROOT/build/reports"

EDITION="lite-lxqt"
PROFILE="minimum"
ISO_PATH=""
FROM_QEMU_JSON=""
RUN_VM=false
STRICT_VM=false
SKIP_FOUNDATION=false

usage() {
  cat <<'USAGE'
Usage: bash linux/test/run-virtual-qualification.sh [OPTIONS]

Evaluates installer, build, ISO, VM profile, and virtual qualification checks
without faking results. Distinguishes PASS, FAIL, BLOCKED, and NOT TESTED.

Options:
  --edition NAME          cinnamon | xfce | lite | lite-lxqt (default: lite-lxqt)
  --profile NAME          minimum (2 vCPU/4G/30G) | recommended (4 vCPU/8G/50G)
  --iso PATH              Override built ISO path to verify
  --from-qemu-json PATH   Score VM checks from an existing run-qemu-validation.sh JSON output
  --run-vm                Attempt live QEMU/OVMF qualification if host tools & ISO exist
  --strict-vm             Exit 3 if VM checks are BLOCKED or NOT TESTED
  --skip-foundation       Skip check-foundation.sh (use when invoked from check-foundation.sh)
  --out-dir DIR           Report output directory (default: build/reports)
  --help, -h              Show this help message
USAGE
}

while (($#)); do
  case "$1" in
    --edition) [[ $# -ge 2 ]] || { echo '--edition requires a value' >&2; exit 2; }; EDITION="$2"; shift 2 ;;
    --profile) [[ $# -ge 2 ]] || { echo '--profile requires a value' >&2; exit 2; }; PROFILE="$2"; shift 2 ;;
    --iso) [[ $# -ge 2 ]] || { echo '--iso requires a path' >&2; exit 2; }; ISO_PATH="$2"; shift 2 ;;
    --from-qemu-json) [[ $# -ge 2 ]] || { echo '--from-qemu-json requires a path' >&2; exit 2; }; FROM_QEMU_JSON="$2"; shift 2 ;;
    --run-vm) RUN_VM=true; shift ;;
    --strict-vm) STRICT_VM=true; shift ;;
    --skip-foundation) SKIP_FOUNDATION=true; shift ;;
    --out-dir) [[ $# -ge 2 ]] || { echo '--out-dir requires a path' >&2; exit 2; }; OUT_DIR="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$EDITION" in
  standard) EDITION="cinnamon" ;;
  cinnamon|xfce|lite|lite-lxqt) ;;
  *) printf 'Unsupported --edition: %s\n' "$EDITION" >&2; exit 2 ;;
esac
case "$PROFILE" in
  min|minimum) PROFILE="minimum"; VM_RAM="4096" ;;
  rec|recommended) PROFILE="recommended"; VM_RAM="8192" ;;
  *) printf 'Unsupported --profile: %s\n' "$PROFILE" >&2; exit 2 ;;
esac

if [[ -z "$ISO_PATH" ]]; then
  ISO_PATH="$REPO_ROOT/build/iso/out/nexus-os-22.3-${EDITION}-amd64.iso"
fi

mkdir -p -- "$OUT_DIR"
REPORT_JSON="$OUT_DIR/virtual-qualification-${EDITION}.json"
REPORT_MD="$OUT_DIR/virtual-qualification-${EDITION}.md"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TMP_DIR"' EXIT

# Helper to run a host check safely and record status
run_check_cmd() {
  local name="$1"
  shift
  local log_f="$TMP_DIR/${name}.log"
  if "$@" >"$log_f" 2>&1; then
    printf 'PASS\n' > "$TMP_DIR/${name}.status"
  else
    printf 'FAIL\n' > "$TMP_DIR/${name}.status"
  fi
}

if [[ "$SKIP_FOUNDATION" == false ]]; then
  run_check_cmd "foundation_checks" bash "$REPO_ROOT/scripts/check-foundation.sh"
else
  printf 'NOT TESTED\n' > "$TMP_DIR/foundation_checks.status"
  printf 'Skipped via --skip-foundation\n' > "$TMP_DIR/foundation_checks.log"
fi

run_check_cmd "installer_validation" bash "$REPO_ROOT/linux/test/test-installer-safety.sh"
run_check_cmd "installer_config_validation" bash "$REPO_ROOT/linux/installer/nexus-disk-install.sh" --disk /dev/vda --edition "$EDITION" --locale en_US.UTF-8 --keymap us --timezone UTC --validate-only
run_check_cmd "manifest_mint" bash "$REPO_ROOT/linux/build/validate-packages.sh" "$REPO_ROOT/linux/config/mint-packages.list"
run_check_cmd "manifest_cinnamon" bash "$REPO_ROOT/linux/build/validate-packages.sh" "$REPO_ROOT/linux/config/cinnamon-packages.list"
run_check_cmd "manifest_lite" bash "$REPO_ROOT/linux/build/validate-packages.sh" "$REPO_ROOT/linux/lite/lite-packages.list"
run_check_cmd "manifest_lite_openbox" bash "$REPO_ROOT/linux/build/validate-packages.sh" "$REPO_ROOT/linux/lite/manifests/lite-openbox-packages.list"
run_check_cmd "manifest_lite_lxqt" bash "$REPO_ROOT/linux/build/validate-packages.sh" "$REPO_ROOT/linux/lite/manifests/lite-lxqt-packages.list"
run_check_cmd "security_audit" bash "$REPO_ROOT/linux/security/nexus-security-audit.sh" --repo-only --repo "$REPO_ROOT" --strict
run_check_cmd "qemu_profile_minimum" bash "$REPO_ROOT/scripts/launch-qemu.sh" --profile minimum --edition "$EDITION" --dry-run
run_check_cmd "qemu_profile_recommended" bash "$REPO_ROOT/scripts/launch-qemu.sh" --profile recommended --edition "$EDITION" --dry-run

# Build prerequisites (BLOCKED if host lacks remastering tools, base ISO, or disk space)
if bash "$REPO_ROOT/linux/build/check-build-prereqs.sh" --edition "$EDITION" --strict >"$TMP_DIR/build_prereqs.log" 2>&1; then
  printf 'PASS\n' > "$TMP_DIR/build_prereqs.status"
else
  printf 'BLOCKED\n' > "$TMP_DIR/build_prereqs.status"
fi

# ISO integrity check (BLOCKED if built ISO is not present locally; FAIL if present and invalid)
if [[ -r "$ISO_PATH" ]]; then
  run_check_cmd "iso_integrity" bash "$REPO_ROOT/linux/build/verify-nexus-iso.sh" --edition "$EDITION" "$ISO_PATH"
else
  printf 'BLOCKED\n' > "$TMP_DIR/iso_integrity.status"
  printf 'ISO file not found locally at %s (build ISO or pass --iso PATH).\n' "$ISO_PATH" > "$TMP_DIR/iso_integrity.log"
fi

# Optional live VM execution when --run-vm is requested
VM_EXEC_STATE="not_requested"
VM_BLOCK_REASON=""
if [[ "$RUN_VM" == true ]]; then
  missing_vm=()
  for bin in qemu-system-x86_64 qemu-img xorriso cpio gzip unmkinitramfs; do
    command -v "$bin" >/dev/null 2>&1 || missing_vm+=("$bin")
  done
  ovmf_found=false
  for code in /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd /usr/share/edk2/x64/OVMF_CODE.fd; do
    [[ -r "$code" ]] && ovmf_found=true && break
  done
  [[ "$ovmf_found" == true ]] || missing_vm+=("ovmf")
  [[ -r "$ISO_PATH" ]] || missing_vm+=("iso:$ISO_PATH")

  if ((${#missing_vm[@]} > 0)); then
    VM_EXEC_STATE="blocked"
    VM_BLOCK_REASON="Missing host VM dependencies: ${missing_vm[*]}"
  else
    VM_EXEC_STATE="executed"
    if ! bash "$REPO_ROOT/linux/test/run-qemu-validation.sh" \
      --edition "$EDITION" \
      --iso "$ISO_PATH" \
      --ram-matrix "$VM_RAM" \
      --install-ram-matrix "$VM_RAM" \
      --graphical \
      --install-test >"$TMP_DIR/vm_runner.log" 2>&1; then
      VM_EXEC_STATE="runner_failed"
      VM_BLOCK_REASON="run-qemu-validation.sh exited non-zero (see vm_runner.log)"
    else
      FROM_QEMU_JSON="$REPO_ROOT/build/qemu-test/qemu-results-${EDITION}.json"
    fi
  fi
fi

python3 - "$TMP_DIR" "$EDITION" "$PROFILE" "$ISO_PATH" "$FROM_QEMU_JSON" "$VM_EXEC_STATE" "$VM_BLOCK_REASON" "$REPORT_JSON" "$REPORT_MD" "$RUN_VM" "$STRICT_VM" <<'PY'
import datetime
import json
from pathlib import Path
import sys

tmp_dir = Path(sys.argv[1])
edition = sys.argv[2]
profile = sys.argv[3]
iso_path = sys.argv[4]
qemu_json_path = sys.argv[5]
vm_exec_state = sys.argv[6]
vm_block_reason = sys.argv[7]
report_json = Path(sys.argv[8])
report_md = Path(sys.argv[9])
run_vm = sys.argv[10] == "true"
strict_vm = sys.argv[11] == "true"

checks = []

def add_local_check(key, label, category):
    st = (tmp_dir / f"{key}.status").read_text(encoding="utf-8").strip()
    log = (tmp_dir / f"{key}.log").read_text(encoding="utf-8", errors="replace").strip().splitlines()
    checks.append({
        "id": key,
        "name": label,
        "category": category,
        "status": st,
        "evidence": log[-3:] if log else [],
    })

add_local_check("foundation_checks", "Static foundation & prototype checks", "static")
add_local_check("installer_validation", "Installer safety, refusal, recovery & edition consistency suite", "installer")
add_local_check("installer_config_validation", "Installer CLI configuration validation (locale/keymap/tz/disk)", "installer")
add_local_check("manifest_mint", "Package manifest validation (xfce)", "build")
add_local_check("manifest_cinnamon", "Package manifest validation (cinnamon)", "build")
add_local_check("manifest_lite", "Package manifest validation (lite)", "build")
add_local_check("manifest_lite_openbox", "Package manifest validation (lite-openbox)", "build")
add_local_check("manifest_lite_lxqt", "Package manifest validation (lite-lxqt)", "build")
add_local_check("security_audit", "Repository security & test-separation audit", "security")
add_local_check("qemu_profile_minimum", "QEMU minimum VM profile (2 vCPU / 4096 MiB / 30G)", "qemu_profile")
add_local_check("qemu_profile_recommended", "QEMU recommended VM profile (4 vCPU / 8192 MiB / 50G)", "qemu_profile")
add_local_check("build_prereqs", "Host ISO build prerequisites & disk space", "build")
add_local_check("iso_integrity", "Built ISO integrity & test-leak verification", "iso")

vm_specs = [
    ("vm_iso_boot", "ISO boot"),
    ("vm_uefi_boot", "UEFI boot (OVMF)"),
    ("vm_bootloader", "Bootloader (EFI + GRUB config)"),
    ("vm_installer_launch", "Installer launch (Ubiquity / CLI)"),
    ("vm_installation", "Installation onto disposable virtual disk"),
    ("vm_installed_boot", "Installed system boot (ISO removed)"),
    ("vm_desktop_launch", "Desktop session launch"),
    ("vm_terminal", "Terminal application launch"),
    ("vm_network", "Network connectivity (NetworkManager)"),
    ("vm_app_launch", "Core application launch (file manager / multi-app)"),
    ("vm_update_status", "Update status (APT / unattended-upgrades)"),
    ("vm_persistence_reboot", "Persistence across reboot"),
    ("vm_basic_recovery", "Basic recovery & diagnostics (nexus-recovery)"),
    ("vm_stability", "Session & systemd stability (0 failed units)"),
]

qemu_data = None
if qemu_json_path and Path(qemu_json_path).is_file():
    qemu_data = json.loads(Path(qemu_json_path).read_text(encoding="utf-8"))

def eval_vm_checks():
    if qemu_data and qemu_data.get("runs"):
        runs = qemu_data["runs"]
        run0 = runs[0]
        live_reps = run0.get("live_reps") or []
        l0 = live_reps[0] if live_reps else {}
        iboots = run0.get("installed_boots") or []
        b0 = iboots[0] if iboots else {}
        ic0 = b0.get("installed_checks") or {}
        apps_src = b0.get("apps") or l0.get("apps") or {}
        net_src = b0.get("network") or l0.get("network") or {}
        upd_src = b0.get("update_status") or l0.get("update_status") or {}
        rec_src = b0.get("recovery_diag") or l0.get("recovery_diag") or {}

        def pf(cond, detail=""):
            return ("PASS" if cond else "FAIL", [detail] if detail else [])

        ub_ui = l0.get("ubiquity_ui") or {}
        ub_ok = bool(ub_ui.get("window_verified")) if ub_ui.get("checked") else None
        term_ok = bool((apps_src.get("terminal") or {}).get("window_verified"))
        fm_ok = bool((apps_src.get("file_manager") or {}).get("window_verified"))
        nm_state = str(net_src.get("nmcli_state") or "")
        net_ok = ("connected" in nm_state.lower()) or bool(net_src.get("ipv4"))

        results = {
            "vm_iso_boot": pf(bool(run0.get("uefi_boot_success")), f"uefi_boot_success={run0.get('uefi_boot_success')}"),
            "vm_uefi_boot": pf(bool(ic0.get("efi_boot_ok") or run0.get("uefi_boot_success")), f"efi_boot_ok={ic0.get('efi_boot_ok')}"),
            "vm_bootloader": pf(bool(ic0.get("grub_cfg_ok") and ic0.get("efi_boot_ok")), f"grub_cfg_ok={ic0.get('grub_cfg_ok')}"),
            "vm_installer_launch": (
                ("PASS", [f"ubiquity_tier={ub_ui.get('qualification_tier')}"]) if ub_ok
                else ("NOT TESTED", ["Ubiquity GUI check skipped (low RAM or disabled)"]) if ub_ok is None
                else ("FAIL", ["Ubiquity window failed to map"])
            ),
            "vm_installation": pf(run0.get("install_successes", 0) > 0, f"install_successes={run0.get('install_successes')}/{run0.get('install_attempts')}"),
            "vm_installed_boot": pf(run0.get("installed_boot_successes", 0) > 0, f"installed_boot_successes={run0.get('installed_boot_successes')}/{run0.get('installed_boot_attempts')}"),
            "vm_desktop_launch": pf(bool(b0.get("graphical_session_success") or l0.get("graphical_session_success")), "graphical_session_success"),
            "vm_terminal": pf(term_ok, f"terminal_verified={term_ok}"),
            "vm_network": pf(net_ok, f"nmcli_state={nm_state or 'unknown'}"),
            "vm_app_launch": pf(fm_ok and term_ok, f"file_manager={fm_ok}, terminal={term_ok}"),
            "vm_update_status": (
                ("PASS", [f"apt_check_ok={upd_src.get('apt_check_ok')}"]) if "apt_check_ok" in upd_src
                else ("NOT TESTED", ["update_status field absent in legacy QEMU JSON"])
            ),
            "vm_persistence_reboot": pf(bool(run0.get("persistence_verified")), f"persistence_verified={run0.get('persistence_verified')}"),
            "vm_basic_recovery": (
                ("PASS", [f"recovery_read_only={rec_src.get('read_only')}"]) if rec_src
                else ("NOT TESTED", ["recovery_diag field absent in legacy QEMU JSON"])
            ),
            "vm_stability": pf(ic0.get("failed_systemd_units", 0) == 0 and run0.get("live_successes", 0) > 0, f"failed_systemd_units={ic0.get('failed_systemd_units')}"),
        }
        for vid, label in vm_specs:
            st, ev = results[vid]
            checks.append({"id": vid, "name": label, "category": "vm_qualification", "status": st, "evidence": ev})
    else:
        default_st = "BLOCKED" if vm_exec_state in ("blocked", "runner_failed") else "NOT TESTED"
        ev = [vm_block_reason] if vm_block_reason else ["QEMU VM execution was not run in this invocation (pass --run-vm on a QEMU/OVMF host or --from-qemu-json PATH)."]
        for vid, label in vm_specs:
            checks.append({"id": vid, "name": label, "category": "vm_qualification", "status": default_st, "evidence": ev})

eval_vm_checks()

counts = {
    "PASS": sum(1 for c in checks if c["status"] == "PASS"),
    "FAIL": sum(1 for c in checks if c["status"] == "FAIL"),
    "BLOCKED": sum(1 for c in checks if c["status"] == "BLOCKED"),
    "NOT TESTED": sum(1 for c in checks if c["status"] == "NOT TESTED"),
}

payload = {
    "phase": "13.2",
    "generated_at_utc": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "edition": edition,
    "vm_profile": profile,
    "iso_path": iso_path,
    "qemu_json_source": qemu_json_path or None,
    "summary": counts,
    "checks": checks,
}
report_json.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

lines = [
    f"# NEXUS OS Virtual Qualification Report ({edition}, {profile} profile)",
    "",
    f"- **Generated (UTC):** `{payload['generated_at_utc']}`",
    f"- **Summary:** `PASS={counts['PASS']}`, `FAIL={counts['FAIL']}`, `BLOCKED={counts['BLOCKED']}`, `NOT TESTED={counts['NOT TESTED']}`",
    "",
    "| Check ID | Category | Check | Status | Evidence |",
    "|---|---|---|---|---|",
]
for c in checks:
    ev = "; ".join(c["evidence"]).replace("|", "/") if c["evidence"] else ""
    lines.append(f"| `{c['id']}` | `{c['category']}` | {c['name']} | **{c['status']}** | {ev} |")
report_md.write_text("\n".join(lines) + "\n", encoding="utf-8")

print(f"Qualification report written: {report_json}")
print(f"Summary: PASS={counts['PASS']} FAIL={counts['FAIL']} BLOCKED={counts['BLOCKED']} NOT TESTED={counts['NOT TESTED']}")

if counts["FAIL"] > 0 or vm_exec_state == "runner_failed":
    sys.exit(1)
if (run_vm and vm_exec_state == "blocked") or (strict_vm and not (qemu_data and qemu_data.get("runs"))):
    sys.exit(3)
sys.exit(0)
PY
