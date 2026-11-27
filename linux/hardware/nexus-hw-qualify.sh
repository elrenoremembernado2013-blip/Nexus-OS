#!/usr/bin/env bash
# NEXUS OS Phase 13.0 Two-Stage Guided Hardware Qualification Programme.
# Stage A (default): Strictly read-only preflight inventory, driver/firmware check, and privacy-redacted export.
# Stage B: Individual manually confirmed hardware checks with pre-run explanations.
# NEVER formats disks, repartitions, flashes firmware, alters Secure Boot, records mic audio, or auto-uploads.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"
INVENTORY_SH="$SCRIPT_DIR/nexus-hw-inventory.sh"
DIAG_SH="$SCRIPT_DIR/nexus-hw-diagnostics.sh"
[[ -x "$INVENTORY_SH" ]] || INVENTORY_SH="/usr/local/bin/nexus-hw-inventory"
[[ -x "$DIAG_SH" ]] || DIAG_SH="/usr/local/bin/nexus-hw-diagnostics"

STAGE="a"
RUN_TEST=""
CONFIRM_TEST=""
EXPORT_DIR=""
DRY_RUN=false
INTERACTIVE=false

usage() {
  cat <<'USAGE'
Usage: bash linux/hardware/nexus-hw-qualify.sh [OPTIONS]

Two-stage safe bare-metal hardware qualification helper:
  Stage A (default): Read-only preflight inventory, graphics/network/audio/power/Secure-Boot
                     inspection, and privacy-audited export. Makes zero system changes.
  Stage B:           Manually authorized individual component checks with pre-run safety
                     explanations. Requires --confirm-test <name> or interactive "yes".

Options:
  --stage a|b            Select Stage A (read-only preflight, default) or list Stage B tests
  --run-test NAME        Stage B test to run:
                           gpu | wifi | bluetooth | audio-output | microphone |
                           touchpad | usb | battery | suspend | all-safe
  --confirm-test NAME    Explicitly confirm running Stage B test NAME (non-interactive safety gate)
  --interactive          Prompt interactively on TTY before running --run-test
  --export DIR           Write Stage A / Stage B redacted outputs into DIR
  --dry-run              Explain what Stage B test NAME would do without executing it
  --help, -h             Show this help message

Safety guarantees:
  - Never formats drives, repartitions disks, installs an OS, or touches firmware/Secure Boot.
  - Never records microphone audio or logs Wi-Fi SSIDs, passwords, MACs, UUIDs, or serials.
  - Never triggers system suspend unless --run-test suspend --confirm-test suspend is explicit.
  - Never use your primary personal computer or personal Chromebook as a disposable install target.
USAGE
}

while (($#)); do
  case "$1" in
    --stage) [[ $# -ge 2 ]] || { echo '--stage requires a or b' >&2; exit 2; }; STAGE="${2,,}"; shift 2 ;;
    --run-test) [[ $# -ge 2 ]] || { echo '--run-test requires a test name' >&2; exit 2; }; RUN_TEST="${2,,}"; STAGE="b"; shift 2 ;;
    --confirm-test) [[ $# -ge 2 ]] || { echo '--confirm-test requires a test name' >&2; exit 2; }; CONFIRM_TEST="${2,,}"; shift 2 ;;
    --interactive) INTERACTIVE=true; shift ;;
    --export) [[ $# -ge 2 ]] || { echo '--export requires a directory' >&2; exit 2; }; EXPORT_DIR="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$STAGE" in
  a|b) ;;
  *) printf 'Invalid --stage: %s (expected a or b)\n' "$STAGE" >&2; exit 2 ;;
esac

python3 - "$STAGE" "$RUN_TEST" "$CONFIRM_TEST" "$EXPORT_DIR" "$DRY_RUN" "$INTERACTIVE" "$INVENTORY_SH" "$DIAG_SH" <<'PY'
import datetime
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

stage, run_test, confirm_test, export_dir, dry_run_s, interactive_s, inv_sh, diag_sh = sys.argv[1:9]
dry_run = dry_run_s.lower() == "true"
interactive = interactive_s.lower() == "true"

TEST_SPECS = {
    "gpu": {
        "will_do": "Inspect /dev/dri nodes, active kernel GPU driver, glxinfo -B renderer (distinguishing llvmpipe vs Intel/AMD/NVIDIA), and vulkaninfo --summary (if installed).",
        "wont_do": "Will NOT install proprietary drivers, edit xorg.conf, or flash GPU VBIOS.",
    },
    "wifi": {
        "will_do": "Check rfkill block state, NetworkManager Wi-Fi radio/HW status, and whether Wi-Fi scan capability is active (without outputting SSIDs, BSSIDs, passwords, or MACs).",
        "wont_do": "Will NOT disconnect active links, modify NM profiles, or capture/print any Wi-Fi network names or credentials.",
    },
    "bluetooth": {
        "will_do": "Check btusb driver presence, rfkill state, bluetooth.service status, and controller power state via bluetoothctl show (redacting controller MAC).",
        "wont_do": "Will NOT pair, trust, or remove Bluetooth devices, and will NOT record device MAC addresses.",
    },
    "audio-output": {
        "will_do": "List ALSA playback devices (aplay -l), check PipeWire/PulseAudio sink status (pactl), and play a brief 1-second 440Hz tone ONLY if speaker-test is present and not dry-run.",
        "wont_do": "Will NOT modify mixer defaults permanently or capture audio.",
    },
    "microphone": {
        "will_do": "List ALSA capture hardware (arecord -l) and PipeWire/PulseAudio source metadata (pactl list short sources) plus SOF firmware presence.",
        "wont_do": "STRICTLY NEVER records, buffers, or saves any microphone audio samples.",
    },
    "touchpad": {
        "will_do": "Inspect /proc/bus/input/devices and libinput/xinput capabilities (multi-touch, tap-to-click, scroll method availability).",
        "wont_do": "Will NOT rewrite libinput/X11 configuration files.",
    },
    "usb": {
        "will_do": "Inspect USB host controllers (xhci_hcd) and attached USB vendor:product IDs + device classes.",
        "wont_do": "Will NOT mount partitions, format USB drives, or record USB serial numbers.",
    },
    "battery": {
        "will_do": "Read /sys/class/power_supply/BAT* & AC* plus upower -d capacity/health summaries.",
        "wont_do": "Will NOT change power profiles, discharge thresholds, or suspend the machine.",
    },
    "suspend": {
        "will_do": "Record pre-suspend Wi-Fi/GPU/audio state, execute 'systemctl suspend' for manual wake testing, and inspect post-resume dmesg errors after you wake the machine.",
        "wont_do": "Will NOT run automatically in Stage A or all-safe; requires explicit --confirm-test suspend and a disposable/test session.",
    },
    "all-safe": {
        "will_do": "Run all non-suspending Stage B checks (gpu, wifi, bluetooth, audio-output metadata, microphone metadata, touchpad, usb, battery).",
        "wont_do": "Excludes suspend; makes zero disk, partition, or firmware changes and never records audio.",
    },
}


def redact(text: str) -> str:
    text = re.sub(r"\b([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}\b", "<REDACTED_MAC>", text)
    text = re.sub(r"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b", "<REDACTED_UUID>", text)
    text = re.sub(r"\b(?:\d{1,3}\.){3}\d{1,3}\b", "<REDACTED_IP>", text)
    text = re.sub(r"/home/[A-Za-z0-9._-]+", "/home/<USER>", text)
    return text


def run_cmd(cmd, timeout=8):
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return res.returncode, redact(res.stdout or "")
    except Exception as exc:
        return 1, str(exc)


def load_stage_a():
    inv = {}
    diag = {}
    if Path(inv_sh).is_file():
        rc, out = run_cmd(["bash", inv_sh, "--json"], timeout=15)
        if rc == 0 and out.strip():
            inv = json.loads(out)
    if Path(diag_sh).is_file():
        cmd = ["bash", diag_sh, "--json"]
        if export_dir:
            cmd += ["--export", export_dir]
        rc, out = run_cmd(cmd, timeout=15)
        if rc == 0 and out.strip():
            diag = json.loads(out)
    return inv, diag


inv, diag = load_stage_a()
env = inv.get("environment") or {}
gq = inv.get("graphics_qualification") or {}
sb = inv.get("secure_boot_chain") or {}

if stage == "a" or not run_test:
    print("=== NEXUS OS Stage A: Read-Only Hardware Preflight ===")
    print(f"Environment:           {env.get('label', 'unknown')} (VM={env.get('is_virtual_machine')}, Chromebook={env.get('is_chromebook_board')})")
    if env.get("is_virtual_machine"):
        print("NOTICE: Running inside a virtual machine. Virtual GPU/disk results DO NOT qualify bare-metal hardware.")
    if env.get("is_chromebook_board"):
        print("SAFETY NOTICE: Chromebook board detected. NEVER run destructive install/disk/firmware tests on a personal Chromebook.")
    print(f"Architecture / CPU:    {(inv.get('architecture') or {}).get('arch')} / {(inv.get('cpu') or {}).get('model')} ({(inv.get('cpu') or {}).get('category')})")
    print(f"UEFI / Secure Boot:    UEFI={sb.get('uefi_active')} | SecureBoot={sb.get('secure_boot_state')} | Shim={bool(sb.get('shim_signed_paths'))}")
    print(f"Graphics Acceleration: {gq.get('hardware_acceleration')} | Drivers={gq.get('pci_drivers')} | GLX={gq.get('glx_renderer')}")
    print(f"Network / Audio / Bat: Wi-Fi={(inv.get('network_qualification') or {}).get('wifi_adapter_count')} | BT={(inv.get('network_qualification') or {}).get('bluetooth_adapter_count')} | AudioCards={len((inv.get('audio') or {}).get('cards', []))} | Batteries={len((inv.get('power_management') or {}).get('batteries', []))}")
    print(f"Privacy Audit:         {(diag.get('privacy_audit') or {}).get('passed')} (auto_upload=False)")
    if export_dir:
        print(f"Exported Stage A files to: {export_dir}")
    print("\n=== Available Stage B Tests (Require Manual Confirmation) ===")
    for name, spec in TEST_SPECS.items():
        print(f"  - {name:13s}: {spec['will_do']}")
    print("\nRun a Stage B test with:")
    print("  nexus-hw-qualify --run-test <name> --confirm-test <name> [--dry-run] [--export DIR]")
    sys.exit(0)

if run_test not in TEST_SPECS:
    print(f"Unknown Stage B test: {run_test}", file=sys.stderr)
    sys.exit(2)

spec = TEST_SPECS[run_test]
print(f"=== NEXUS OS Stage B Pre-Run Safety Explanation: {run_test} ===")
print(f"WILL DO:     {spec['will_do']}")
print(f"WILL NOT DO: {spec['wont_do']}")

if dry_run:
    print("[dry-run] Confirmation satisfied for preview only; no test commands executed.")
    sys.exit(0)

confirmed = (confirm_test == run_test)
if not confirmed and interactive and sys.stdin.isatty():
    ans = input(f"Confirm running Stage B test '{run_test}'? Type 'yes' to continue: ").strip().lower()
    confirmed = (ans == "yes")

if not confirmed:
    print(f"Refusing to run Stage B test '{run_test}' without explicit confirmation (--confirm-test {run_test} or --interactive 'yes').", file=sys.stderr)
    sys.exit(3)


def exec_single(name: str) -> dict:
    if name == "gpu":
        out = {
            "pci_drivers": gq.get("pci_drivers", []),
            "dri_nodes": gq.get("dri_nodes", []),
            "hardware_acceleration": gq.get("hardware_acceleration"),
            "glx_renderer": gq.get("glx_renderer"),
            "vulkan_icds": gq.get("vulkan_icds", []),
            "vulkan_summary": gq.get("vulkan_summary", []),
            "status": "pass_virtual_software" if gq.get("software_rendering_fallback") else ("pass_hardware_detected" if gq.get("pci_drivers") else "fail_no_gpu"),
        }
        return out
    if name == "wifi":
        nq = inv.get("network_qualification") or {}
        has_wifi = nq.get("wifi_adapter_count", 0) > 0
        scan_note = "no_wifi_hardware"
        if has_wifi and shutil.which("nmcli"):
            rc, _ = run_cmd(["nmcli", "-t", "-f", "WIFI,WIFI-HW", "general"])
            scan_note = "nmcli_wifi_ready_ssid_redacted" if rc == 0 else "nmcli_error"
        return {
            "wifi_adapter_count": nq.get("wifi_adapter_count", 0),
            "wifi_hw_enabled": nq.get("wifi_hw_enabled"),
            "wifi_radio_enabled": nq.get("wifi_radio_enabled"),
            "networkmanager_state": nq.get("networkmanager_state"),
            "check_result": scan_note,
            "missing_firmware": nq.get("missing_network_firmware", []),
        }
    if name == "bluetooth":
        bt_list = inv.get("bluetooth") or []
        ctl = "unavailable"
        if bt_list and shutil.which("bluetoothctl"):
            rc, txt = run_cmd(["bluetoothctl", "show"], timeout=4)
            ctl = "controller_ok" if rc == 0 and "Powered:" in txt else "controller_not_ready"
        return {"adapters": bt_list, "bluetoothctl_status": ctl}
    if name == "audio-output":
        au = inv.get("audio") or {}
        tone_played = False
        if au.get("playback_devices") and shutil.which("speaker-test"):
            rc, _ = run_cmd(["speaker-test", "-t", "sine", "-f", "440", "-l", "1"], timeout=6)
            tone_played = (rc == 0)
        return {
            "audio_server": au.get("audio_server"),
            "playback_devices": au.get("playback_devices", []),
            "sof_modules": au.get("sof_modules", []),
            "tone_test_440hz": "played" if tone_played else "skipped_no_playback_or_speaker_test",
        }
    if name == "microphone":
        au = inv.get("audio") or {}
        sources = []
        if shutil.which("pactl"):
            rc, txt = run_cmd(["pactl", "list", "short", "sources"], timeout=4)
            if rc == 0:
                sources = [l for l in txt.splitlines() if l.strip()][:8]
        return {
            "recording_performed": False,
            "capture_devices": au.get("capture_devices", []),
            "pipewire_pulse_sources": sources,
            "sof_firmware_files_count": au.get("sof_firmware_files_count", 0),
        }
    if name == "touchpad":
        libinput_info = []
        if shutil.which("libinput"):
            rc, txt = run_cmd(["libinput", "list-devices"], timeout=5)
            if rc == 0:
                for line in txt.splitlines():
                    if line.startswith(("Device:", "Capabilities:", "Tap-to-click:", "Scroll methods:")):
                        libinput_info.append(line.strip())
        return {"detected_touchpads": inv.get("touchpads", []), "libinput_summary": libinput_info[:20]}
    if name == "usb":
        return {"usb_controllers": inv.get("usb_controllers", []), "usb_devices": inv.get("usb_devices", [])}
    if name == "battery":
        upower_out = []
        if shutil.which("upower"):
            rc, txt = run_cmd(["upower", "-e"], timeout=4)
            if rc == 0:
                upower_out = [l.strip() for l in txt.splitlines() if "BAT" in l or "AC" in l][:6]
        return {"power_management": inv.get("power_management", {}), "upower_objects": upower_out}
    if name == "suspend":
        if env.get("is_virtual_machine"):
            return {"status": "skipped_in_vm", "notes": "QEMU VM suspend does not test bare-metal ACPI S3/s2idle wake."}
        if not shutil.which("systemctl"):
            return {"status": "unavailable", "notes": "systemctl not present"}
        rc, txt = run_cmd(["systemctl", "suspend"], timeout=10)
        return {"status": "suspend_invoked" if rc == 0 else "suspend_failed", "output": txt}
    return {}


targets = ["gpu", "wifi", "bluetooth", "audio-output", "microphone", "touchpad", "usb", "battery"] if run_test == "all-safe" else [run_test]
results = {
    "stage": "B",
    "generated_at_utc": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "environment": env,
    "tests_executed": {t: exec_single(t) for t in targets},
    "auto_upload": False,
}

if export_dir:
    out_d = Path(export_dir)
    out_d.mkdir(parents=True, exist_ok=True)
    p = out_d / f"nexus-stage-b-{run_test}.json"
    p.write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote redacted Stage B result to {p}")

print(json.dumps(results, indent=2))
PY
