#!/usr/bin/env bash
# Unified NEXUS OS Control Centre status & safe hardware-control helper.
# Reports honest hardware/service capability across Cinnamon, XFCE, Lite LXQt, and Lite Openbox.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"
SECURITY_CLI="${NEXUS_SECURITY_CLI:-$SCRIPT_DIR/nexus-security-cli.sh}"
if [[ ! -x "$SECURITY_CLI" && -x "/usr/local/bin/nexus-security-cli" ]]; then
  SECURITY_CLI="/usr/local/bin/nexus-security-cli"
fi
GAMING_CLI="${NEXUS_GAMING_CLI:-$SCRIPT_DIR/nexus-gaming-cli.sh}"
if [[ ! -x "$GAMING_CLI" && -x "/usr/local/bin/nexus-gaming-cli" ]]; then
  GAMING_CLI="/usr/local/bin/nexus-gaming-cli"
fi
STATE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nexus-os"
DND_FILE="$STATE_DIR/dnd"

usage() {
  cat <<'USAGE'
Usage: nexus-control-centre [status [--json] | --plain | action --type TYPE [--value VAL]]

Commands:
  status [--json]   Print Control Centre hardware, security, updates, and notification status
  --plain           Print concise one-line summary
  action            Perform a quick-setting action:
                      --type volume --value 0..100
                      --type mute --value toggle|on|off
                      --type brightness --value 5..100
                      --type wifi --value on|off
                      --type bluetooth --value on|off
                      --type dnd --value on|off
USAGE
}

CMD="status"
if (($# > 0)); then
  case "$1" in
    status|action) CMD="$1"; shift ;;
    --plain) CMD="plain"; shift ;;
    --json) CMD="status"; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
fi

ACTION_TYPE=""
ACTION_VAL=""
while (($#)); do
  case "$1" in
    --json) shift ;;
    --type) [[ $# -ge 2 ]] || { echo '--type requires a value' >&2; exit 2; }; ACTION_TYPE="$2"; shift 2 ;;
    --value) [[ $# -ge 2 ]] || { echo '--value requires a value' >&2; exit 2; }; ACTION_VAL="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

collect_status_json() {
  python3 - "$SECURITY_CLI" "$GAMING_CLI" "$DND_FILE" <<'PY'
import json
import os
import re
import shutil
import subprocess
from pathlib import Path
import sys

security_cli, gaming_cli, dnd_file = sys.argv[1], sys.argv[2], Path(sys.argv[3])

def run(cmd, timeout=3.0):
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return res.returncode, res.stdout.strip(), res.stderr.strip()
    except Exception as exc:
        return 1, "", str(exc)

desktop = (os.environ.get("XDG_CURRENT_DESKTOP") or os.environ.get("DESKTOP_SESSION") or "").lower()
if "cinnamon" in desktop:
    edition = "cinnamon"
elif "xfce" in desktop:
    edition = "xfce"
elif "lxqt" in desktop:
    edition = "lite-lxqt"
elif "openbox" in desktop:
    edition = "lite"
elif Path("/etc/nexus-os/edition").is_file():
    edition = Path("/etc/nexus-os/edition").read_text(encoding="utf-8").strip() or "lite"
elif shutil.which("cinnamon-settings"):
    edition = "cinnamon"
elif shutil.which("xfconf-query"):
    edition = "xfce"
elif shutil.which("pcmanfm-qt"):
    edition = "lite-lxqt"
else:
    edition = "lite"

# 1. Network & Wi-Fi
wifi_ifaces = []
wired_ifaces = []
net_dir = Path("/sys/class/net")
if net_dir.is_dir():
    for iface in sorted(net_dir.iterdir()):
        name = iface.name
        if name == "lo":
            continue
        oper = ""
        try:
            oper = (iface / "operstate").read_text(encoding="utf-8").strip()
        except OSError:
            pass
        if (iface / "wireless").is_dir() or name.startswith(("wl", "wlan")):
            wifi_ifaces.append((name, oper))
        else:
            wired_ifaces.append((name, oper))

wifi_available = bool(wifi_ifaces)
wifi_enabled = None
ssid = None
active_iface = None
connected = False
if shutil.which("nmcli"):
    rc, out, _ = run(["nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "dev"])
    if rc == 0 and out:
        for line in out.splitlines():
            parts = line.split(":")
            if len(parts) >= 4:
                dev, dev_type, state, conn = parts[0], parts[1], parts[2], parts[3]
                if dev_type == "wifi":
                    wifi_available = True
                if state == "connected":
                    connected = True
                    active_iface = active_iface or dev
                    if dev_type == "wifi" and conn and conn != "--":
                        ssid = conn
    if wifi_available:
        rc2, out2, _ = run(["nmcli", "radio", "wifi"])
        if rc2 == 0:
            wifi_enabled = out2.lower() == "enabled"

if not connected:
    for name, oper in wired_ifaces + wifi_ifaces:
        if oper == "up":
            connected = True
            active_iface = name
            break

net_status_text = (
    f"Connected ({ssid or active_iface or 'online'})" if connected
    else ("Wi-Fi off" if wifi_available and wifi_enabled is False else "Disconnected")
)
network = {
    "supported": bool(wired_ifaces or wifi_ifaces or shutil.which("nmcli")),
    "connected": connected,
    "wifi_available": wifi_available,
    "wifi_enabled": wifi_enabled,
    "ssid": ssid,
    "interface": active_iface,
    "status_text": net_status_text,
}

# 2. Bluetooth
bt_dir = Path("/sys/class/bluetooth")
bt_adapters = [p.name for p in sorted(bt_dir.iterdir())] if bt_dir.is_dir() else []
bt_supported = bool(bt_adapters)
bt_powered = None
if bt_supported and shutil.which("bluetoothctl"):
    rc, out, _ = run(["bluetoothctl", "show"], timeout=2.5)
    if rc == 0:
        m = re.search(r"Powered:\s+(yes|no)", out, re.I)
        if m:
            bt_powered = m.group(1).lower() == "yes"
if bt_supported and bt_powered is None and shutil.which("rfkill"):
    rc, out, _ = run(["rfkill", "list", "bluetooth"])
    if rc == 0 and out:
        bt_powered = "Soft blocked: yes" not in out and "Hard blocked: yes" not in out

bluetooth = {
    "supported": bt_supported,
    "powered": bt_powered,
    "adapters": bt_adapters,
    "status_text": (
        "No Bluetooth adapter" if not bt_supported
        else ("On" if bt_powered else ("Off" if bt_powered is False else "Available"))
    ),
}

# 3. Sound
sound_supported = False
sound_backend = None
vol_pct = None
muted = None
if shutil.which("wpctl"):
    rc, out, _ = run(["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"])
    m = re.search(r"Volume:\s+([0-9.]+)", out)
    if rc == 0 and m:
        sound_supported = True
        sound_backend = "wpctl"
        vol_pct = max(0, min(150, round(float(m.group(1)) * 100)))
        muted = "[MUTED]" in out
if not sound_supported and shutil.which("pactl"):
    rc, out, _ = run(["pactl", "get-sink-volume", "@DEFAULT_SINK@"])
    m = re.search(r"(\d+)%", out)
    if rc == 0 and m:
        sound_supported = True
        sound_backend = "pactl"
        vol_pct = int(m.group(1))
        rc_m, out_m, _ = run(["pactl", "get-sink-mute", "@DEFAULT_SINK@"])
        if rc_m == 0:
            muted = "yes" in out_m.lower()
if not sound_supported and shutil.which("amixer"):
    rc, out, _ = run(["amixer", "get", "Master"])
    m = re.search(r"\[(\d+)%\]", out)
    if rc == 0 and m:
        sound_supported = True
        sound_backend = "amixer"
        vol_pct = int(m.group(1))
        muted = "[off]" in out.lower()

sound = {
    "supported": sound_supported,
    "backend": sound_backend,
    "volume_percent": vol_pct,
    "muted": muted,
    "status_text": (
        "Audio controls unavailable" if not sound_supported
        else ("Muted" if muted else f"{vol_pct}%")
    ),
}

# 4. Backlight Brightness
bl_dir = Path("/sys/class/backlight")
bl_devices = sorted(bl_dir.iterdir()) if bl_dir.is_dir() else []
bl_supported = False
bl_pct = None
bl_dev_name = None
for dev in bl_devices:
    try:
        cur_v = int((dev / "brightness").read_text(encoding="utf-8").strip())
        max_v = int((dev / "max_brightness").read_text(encoding="utf-8").strip())
        if max_v > 0:
            bl_supported = True
            bl_pct = max(0, min(100, round((cur_v / max_v) * 100)))
            bl_dev_name = dev.name
            break
    except Exception:
        pass
brightness = {
    "supported": bl_supported,
    "percent": bl_pct,
    "device": bl_dev_name,
    "status_text": f"{bl_pct}%" if bl_supported else "Hardware backlight unavailable",
}

# 5. Battery
ps_dir = Path("/sys/class/power_supply")
bat_supported = False
bat_pct = None
bat_state = None
if ps_dir.is_dir():
    for dev in sorted(ps_dir.iterdir()):
        if not dev.name.startswith("BAT"):
            continue
        try:
            cap = int((dev / "capacity").read_text(encoding="utf-8").strip())
            st = (dev / "status").read_text(encoding="utf-8").strip() if (dev / "status").is_file() else "Unknown"
            bat_supported = True
            bat_pct = cap
            bat_state = st
            break
        except Exception:
            pass
battery = {
    "supported": bat_supported,
    "percent": bat_pct,
    "status": bat_state,
    "status_text": f"{bat_pct}% ({bat_state})" if bat_supported else "AC / Desktop (no battery)",
}

# 6. Notifications / DND
dnd = dnd_file.is_file() and dnd_file.read_text(encoding="utf-8").strip() == "1"
notif_daemon = None
if edition == "cinnamon" and shutil.which("gsettings"):
    notif_daemon = "cinnamon"
    rc, out, _ = run(["gsettings", "get", "org.cinnamon.desktop.notifications", "display-notifications"])
    if rc == 0 and out.lower() == "false":
        dnd = True
elif edition == "xfce" and shutil.which("xfconf-query"):
    notif_daemon = "xfce4-notifyd"
    rc, out, _ = run(["xfconf-query", "-c", "xfce4-notifyd", "-p", "/do-not-disturb"])
    if rc == 0 and out.lower() == "true":
        dnd = True
elif edition == "lite-lxqt" and shutil.which("lxqt-notificationd"):
    notif_daemon = "lxqt-notificationd"

notifications = {
    "supported": bool(notif_daemon or shutil.which("notify-send")),
    "daemon": notif_daemon,
    "dnd": dnd,
    "status_text": ("No notification daemon (minimal Openbox)" if not (notif_daemon or shutil.which("notify-send")) else ("Do Not Disturb" if dnd else "Active")),
}

# 7. Security & Updates summary
sec_data = {}
if Path(security_cli).is_file():
    rc, out, _ = run(["bash", security_cli, "status"], timeout=5.0)
    if rc == 0 and out:
        try:
            sec_data = json.loads(out)
        except Exception:
            pass

apt_avail = bool(shutil.which("apt-get") and shutil.which("dpkg-query"))
upgradable_count = None
if apt_avail:
    rc, out, _ = run(["apt-get", "-s", "-q", "upgrade"], timeout=5.0)
    if rc == 0:
        upgradable_count = sum(1 for line in out.splitlines() if line.startswith("Inst "))

flatpak_updates_count = None
if shutil.which("flatpak"):
    rc, out, _ = run(["flatpak", "remote-ls", "--updates", "--columns=application"], timeout=4.0)
    if rc == 0:
        flatpak_updates_count = len([l for l in out.splitlines() if l.strip()])

updates = {
    "apt_available": apt_avail,
    "upgradable_count": upgradable_count,
    "flatpak_updates_count": flatpak_updates_count,
    "auto_upgrades": (sec_data.get("security_updates") or {}).get("status", "unknown"),
    "status_text": (
        "Package tools unavailable" if not apt_avail
        else ("Up to date" if (upgradable_count or 0) == 0 and (flatpak_updates_count or 0) == 0
              else f"{(upgradable_count or 0) + (flatpak_updates_count or 0)} update(s) pending")
    ),
}

security = {
    "firewall": (sec_data.get("firewall") or {}).get("status", "unknown"),
    "secure_boot": (sec_data.get("secure_boot") or {}).get("status", "unknown"),
    "disk_encryption": (sec_data.get("disk_encryption") or {}).get("status", "unknown"),
    "status_text": f"Firewall: {(sec_data.get('firewall') or {}).get('status', 'unknown')}",
}

gaming_mode = "disabled"
if Path(gaming_cli).is_file():
    rc, out, _ = run(["bash", gaming_cli, "status"], timeout=5.0)
    if rc == 0 and out:
        try:
            gdata = json.loads(out)
            gaming_mode = (gdata.get("performance") or {}).get("gaming_mode", "disabled")
        except Exception:
            pass

print(json.dumps({
    "edition": edition,
    "network": network,
    "bluetooth": bluetooth,
    "sound": sound,
    "brightness": brightness,
    "battery": battery,
    "notifications": notifications,
    "security": security,
    "updates": updates,
    "performance": {"gaming_mode": gaming_mode},
}, indent=2))
PY
}

perform_action() {
  case "$ACTION_TYPE" in
    volume)
      if ! [[ "$ACTION_VAL" =~ ^[0-9]+$ ]] || (( ACTION_VAL < 0 || ACTION_VAL > 100 )); then
        echo '{"ok":false,"message":"Volume must be 0..100"}' >&2
        exit 2
      fi
      if command -v wpctl >/dev/null 2>&1; then
        frac="$(python3 -c 'import sys; print(f"{int(sys.argv[1])/100:.2f}")' "$ACTION_VAL")"
        wpctl set-volume @DEFAULT_AUDIO_SINK@ "$frac" && printf '{"ok":true,"volume":%s}\n' "$ACTION_VAL" && return 0
      elif command -v pactl >/dev/null 2>&1; then
        pactl set-sink-volume @DEFAULT_SINK@ "${ACTION_VAL}%" && printf '{"ok":true,"volume":%s}\n' "$ACTION_VAL" && return 0
      elif command -v amixer >/dev/null 2>&1; then
        amixer -q sset Master "${ACTION_VAL}%" && printf '{"ok":true,"volume":%s}\n' "$ACTION_VAL" && return 0
      fi
      echo '{"ok":false,"message":"No audio mixer (wpctl/pactl/amixer) available"}'
      return 1
      ;;
    mute)
      case "$ACTION_VAL" in
        toggle|on|off) ;;
        *) echo '{"ok":false,"message":"Mute value must be toggle|on|off"}'; return 2 ;;
      esac
      if command -v wpctl >/dev/null 2>&1; then
        v="toggle"
        if [[ "$ACTION_VAL" == "on" ]]; then v=1; elif [[ "$ACTION_VAL" == "off" ]]; then v=0; fi
        wpctl set-mute @DEFAULT_AUDIO_SINK@ "$v" && printf '{"ok":true,"mute":"%s"}\n' "$ACTION_VAL" && return 0
      elif command -v pactl >/dev/null 2>&1; then
        v="toggle"
        if [[ "$ACTION_VAL" == "on" ]]; then v=1; elif [[ "$ACTION_VAL" == "off" ]]; then v=0; fi
        pactl set-sink-mute @DEFAULT_SINK@ "$v" && printf '{"ok":true,"mute":"%s"}\n' "$ACTION_VAL" && return 0
      elif command -v amixer >/dev/null 2>&1; then
        v="toggle"
        if [[ "$ACTION_VAL" == "on" ]]; then v="mute"; elif [[ "$ACTION_VAL" == "off" ]]; then v="unmute"; fi
        amixer -q sset Master "$v" && printf '{"ok":true,"mute":"%s"}\n' "$ACTION_VAL" && return 0
      fi
      echo '{"ok":false,"message":"No audio mixer available"}'
      return 1
      ;;
    brightness)
      if ! [[ "$ACTION_VAL" =~ ^[0-9]+$ ]] || (( ACTION_VAL < 5 || ACTION_VAL > 100 )); then
        echo '{"ok":false,"message":"Brightness must be 5..100"}'
        return 2
      fi
      if command -v brightnessctl >/dev/null 2>&1; then
        if brightnessctl -q set "${ACTION_VAL}%"; then
          printf '{"ok":true,"brightness":%s}\n' "$ACTION_VAL"
          return 0
        fi
      fi
      echo '{"ok":false,"message":"Hardware backlight control unavailable or requires brightnessctl permission"}'
      return 1
      ;;
    wifi)
      case "$ACTION_VAL" in
        on|off) ;;
        *) echo '{"ok":false,"message":"Wi-Fi value must be on|off"}'; return 2 ;;
      esac
      if command -v nmcli >/dev/null 2>&1; then
        if nmcli radio wifi "$ACTION_VAL"; then
          printf '{"ok":true,"wifi":"%s"}\n' "$ACTION_VAL"
          return 0
        fi
      fi
      echo '{"ok":false,"message":"Wi-Fi control via NetworkManager (nmcli) is unavailable"}'
      return 1
      ;;
    bluetooth)
      case "$ACTION_VAL" in
        on|off) ;;
        *) echo '{"ok":false,"message":"Bluetooth value must be on|off"}'; return 2 ;;
      esac
      if [[ ! -d /sys/class/bluetooth ]] || [[ -z "$(find /sys/class/bluetooth -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null || true)" ]]; then
        echo '{"ok":false,"message":"No Bluetooth adapter detected on this system"}'
        return 1
      fi
      if command -v bluetoothctl >/dev/null 2>&1; then
        if bluetoothctl power "$ACTION_VAL" >/dev/null 2>&1; then
          printf '{"ok":true,"bluetooth":"%s"}\n' "$ACTION_VAL"
          return 0
        fi
      fi
      echo '{"ok":false,"message":"Bluetooth service control unavailable"}'
      return 1
      ;;
    dnd)
      case "$ACTION_VAL" in
        on|off) ;;
        *) echo '{"ok":false,"message":"DND value must be on|off"}'; return 2 ;;
      esac
      mkdir -p "$STATE_DIR"
      dnd_bool=false
      if [[ "$ACTION_VAL" == "on" ]]; then
        dnd_bool=true
        printf '1\n' > "$DND_FILE"
        if command -v gsettings >/dev/null 2>&1; then
          gsettings set org.cinnamon.desktop.notifications display-notifications false >/dev/null 2>&1 || true
        fi
        if command -v xfconf-query >/dev/null 2>&1; then
          xfconf-query -c xfce4-notifyd -p /do-not-disturb -n -t bool -s true >/dev/null 2>&1 || true
        fi
      else
        printf '0\n' > "$DND_FILE"
        if command -v gsettings >/dev/null 2>&1; then
          gsettings set org.cinnamon.desktop.notifications display-notifications true >/dev/null 2>&1 || true
        fi
        if command -v xfconf-query >/dev/null 2>&1; then
          xfconf-query -c xfce4-notifyd -p /do-not-disturb -n -t bool -s false >/dev/null 2>&1 || true
        fi
      fi
      printf '{"ok":true,"dnd":%s}\n' "$dnd_bool"
      ;;
    *)
      printf '{"ok":false,"message":"Unknown action type: %s"}\n' "$ACTION_TYPE"
      return 2
      ;;
  esac
}

case "$CMD" in
  status)
    collect_status_json
    ;;
  plain)
    collect_status_json | python3 -c 'import json,sys; d=json.load(sys.stdin); print(f"NEXUS Control Centre ({d[\"edition\"]}) | Net: {d[\"network\"][\"status_text\"]} | BT: {d[\"bluetooth\"][\"status_text\"]} | Audio: {d[\"sound\"][\"status_text\"]} | Updates: {d[\"updates\"][\"status_text\"]} | {d[\"security\"][\"status_text\"]}")'
    ;;
  action)
    perform_action
    ;;
esac
