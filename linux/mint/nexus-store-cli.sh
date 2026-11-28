#!/usr/bin/env bash
# NEXUS Store Linux Mint package-management helper (APT + Flatpak).
# Validates package identifiers strictly, refuses removal of protected base
# packages, and uses Polkit (pkexec) for privileged install/remove/update actions.
set -euo pipefail

DRY_RUN=false
JSON_OUT=false

usage() {
  cat <<'USAGE'
Usage: bash linux/mint/nexus-store-cli.sh [OPTIONS] <command> [args...]

Real Linux Mint package backend for NEXUS Store (APT and Flatpak).
Read-only queries run as the current user; mutating commands invoke pkexec so
system authentication is never bypassed.

Options:
  --json          Emit structured JSON output for search/info/installed/updates/install/remove
  --dry-run       Print exact APT/Flatpak commands without executing mutations
  --help, -h      Show this help message

Commands:
  sources                        Report available package managers (apt, flatpak, mintupdate)
  search <query>                 Search APT and Flatpak metadata (read-only)
  info <apt|flatpak> <pkg>       Show real package metadata, dependencies, and installed state
  installed                      List manually installed APT apps and Flatpak apps
  updates                        Check real upgradable APT and Flatpak updates
  install <apt|flatpak> <pkg>    Install a package via pkexec apt-get or flatpak
  remove <apt|flatpak> <pkg>     Remove a non-protected package via pkexec apt-get or flatpak
USAGE
}

while (($#)); do
  case "$1" in
    --json) JSON_OUT=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --help|-h) usage; exit 0 ;;
    --) shift; break ;;
    -*) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    *) break ;;
  esac
done

[[ $# -ge 1 ]] || { usage >&2; exit 2; }
CMD="$1"
shift

validate_pkg_id() {
  local source="$1" pkg="$2"
  case "$source" in
    apt)
      [[ "$pkg" =~ ^[a-z0-9][a-z0-9+.-]{0,127}$ ]] || {
        printf 'Invalid APT package name: %s\n' "$pkg" >&2
        exit 2
      }
      ;;
    flatpak)
      [[ "$pkg" =~ ^[A-Za-z0-9_.-]{3,128}$ && "$pkg" == *.* ]] || {
        printf 'Invalid Flatpak application ID: %s\n' "$pkg" >&2
        exit 2
      }
      ;;
    *)
      printf 'Unsupported package source: %s (expected apt or flatpak)\n' "$source" >&2
      exit 2
      ;;
  esac
}

is_protected_apt_pkg() {
  local pkg="$1"
  case "$pkg" in
    apt|apt-utils|base-files|base-passwd|bash|coreutils|cryptsetup|cryptsetup-initramfs|dash|dpkg|e2fsprogs|findutils|grep|grub2-common|grub-efi-amd64|grub-efi-amd64-bin|grub-efi-amd64-signed|gzip|init|libc6|lightdm|lightdm-gtk-greeter|linux-base|linux-generic|linux-image-*|login|lxqt-panel|lxqt-policykit|lxqt-session|mintsystem|mintupdate|mount|network-manager|openbox|passwd|pcmanfm|pcmanfm-qt|pkexec|policykit-1|policykit-1-gnome|polkitd|sed|sudo|systemd|systemd-sysv|tar|tint2|ubuntu-minimal|ufw|util-linux|xfce4-session|xfwm4|cinnamon|zram-tools)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

run_mutating() {
  if [[ "$DRY_RUN" == true ]]; then
    if [[ "$JSON_OUT" == true ]]; then
      python3 - "$@" <<'PY'
import json, sys
print(json.dumps({"ok": True, "dryRun": True, "command": sys.argv[1:]}))
PY
    else
      printf '[dry-run]'
      printf ' %q' "$@"
      printf '\n'
    fi
  else
    if [[ "$JSON_OUT" == true ]]; then
      set +e
      out="$("$@" 2>&1)"
      rc=$?
      set -e
      python3 - "$rc" "$out" <<'PY'
import json, sys
rc = int(sys.argv[1])
out = sys.argv[2].strip()
err_kind = None
if rc == 126:
    err_kind = "polkit_cancelled"
elif rc == 127:
    err_kind = "polkit_unavailable"
elif rc != 0:
    low = out.lower()
    if "could not get lock" in low or "unable to lock" in low:
        err_kind = "apt_locked"
    elif "unable to locate package" in low or "no matches" in low:
        err_kind = "not_found"
    else:
        err_kind = "command_failed"
print(json.dumps({"ok": rc == 0, "exitCode": rc, "errorKind": err_kind, "message": out[-1200:] if out else ("Completed" if rc == 0 else f"Failed with exit code {rc}")}))
sys.exit(0 if rc == 0 else rc)
PY
    else
      "$@"
    fi
  fi
}

case "$CMD" in
  sources)
    apt_ok=false
    flatpak_ok=false
    mintupdate_ok=false
    pkexec_ok=false
    command -v apt-cache >/dev/null 2>&1 && command -v apt-get >/dev/null 2>&1 && apt_ok=true
    command -v flatpak >/dev/null 2>&1 && flatpak_ok=true
    command -v mintupdate >/dev/null 2>&1 && mintupdate_ok=true
    command -v pkexec >/dev/null 2>&1 && pkexec_ok=true
    printf '{"apt":%s,"flatpak":%s,"mintupdate":%s,"pkexec":%s}\n' "$apt_ok" "$flatpak_ok" "$mintupdate_ok" "$pkexec_ok"
    ;;

  search)
    [[ $# -ge 1 && -n "${1//[[:space:]]/}" ]] || { echo 'search requires a non-empty query' >&2; exit 2; }
    query="$1"
    if [[ "$JSON_OUT" == true ]]; then
      python3 - "$query" <<'PY'
import json, shutil, subprocess, sys
query = sys.argv[1]
results = []
installed_apt = set()
if shutil.which("dpkg-query"):
    r = subprocess.run(["dpkg-query", "-W", "-f=${Package}\t${db:Status-Abbrev}\n"], capture_output=True, text=True, timeout=5)
    for line in r.stdout.splitlines():
        parts = line.split("\t")
        if len(parts) == 2 and parts[1].startswith("ii"):
            installed_apt.add(parts[0])
apt_ok = shutil.which("apt-cache") is not None
if apt_ok:
    r = subprocess.run(["apt-cache", "search", "--names-only", "--", query], capture_output=True, text=True, timeout=8)
    for line in r.stdout.splitlines()[:40]:
        if " - " in line:
            name, desc = line.split(" - ", 1)
            name = name.strip()
            results.append({"id": name, "name": name, "source": "apt", "summary": desc.strip(), "installed": name in installed_apt})
installed_fp = set()
flatpak_ok = shutil.which("flatpak") is not None
if flatpak_ok:
    r_i = subprocess.run(["flatpak", "list", "--app", "--columns=application"], capture_output=True, text=True, timeout=5)
    if r_i.returncode == 0:
        installed_fp = {l.strip() for l in r_i.stdout.splitlines() if l.strip()}
    r = subprocess.run(["flatpak", "search", "--columns=application,name,version,remotes,description", "--", query], capture_output=True, text=True, timeout=8)
    if r.returncode == 0:
        for line in r.stdout.splitlines()[:40]:
            cols = line.split("\t")
            if cols and cols[0].strip():
                app_id = cols[0].strip()
                results.append({
                    "id": app_id,
                    "name": cols[1].strip() if len(cols) > 1 else app_id,
                    "version": cols[2].strip() if len(cols) > 2 else "",
                    "remote": cols[3].strip() if len(cols) > 3 else "",
                    "summary": cols[4].strip() if len(cols) > 4 else "",
                    "source": "flatpak",
                    "installed": app_id in installed_fp,
                })
print(json.dumps({"query": query, "apt_available": apt_ok, "flatpak_available": flatpak_ok, "results": results}, indent=2))
PY
      exit 0
    fi
    if command -v apt-cache >/dev/null 2>&1; then
      echo '=== APT ==='
      apt-cache search --names-only -- "$query" 2>/dev/null | head -n 40 || true
    else
      echo 'APT unavailable on this host.'
    fi
    if command -v flatpak >/dev/null 2>&1; then
      echo '=== Flatpak ==='
      flatpak search --columns=application,name,version,remotes,description -- "$query" 2>/dev/null | head -n 40 || true
    fi
    ;;

  info)
    [[ $# -eq 2 ]] || { echo 'info requires <apt|flatpak> <pkg>' >&2; exit 2; }
    source="$1"
    pkg="$2"
    validate_pkg_id "$source" "$pkg"
    if [[ "$JSON_OUT" == true ]]; then
      python3 - "$source" "$pkg" <<'PY'
import json, shutil, subprocess, sys
source, pkg = sys.argv[1], sys.argv[2]
if source == "apt":
    if not shutil.which("apt-cache"):
        print(json.dumps({"error": "apt-cache unavailable"}))
        sys.exit(1)
    r = subprocess.run(["apt-cache", "show", "--", pkg], capture_output=True, text=True, timeout=6)
    if r.returncode != 0 or not r.stdout.strip():
        print(json.dumps({"error": f"Package not found in APT: {pkg}"}))
        sys.exit(1)
    version, desc, size_kb = "", "", None
    for line in r.stdout.splitlines():
        if not version and line.startswith("Version: "):
            version = line.split(": ", 1)[1].strip()
        elif not desc and line.startswith("Description"):
            desc = line.split(": ", 1)[1].strip() if ": " in line else ""
        elif size_kb is None and line.startswith("Installed-Size: "):
            tok = line.split(": ", 1)[1].strip()
            if tok.isdigit():
                size_kb = int(tok)
    inst = False
    if shutil.which("dpkg-query"):
        d = subprocess.run(["dpkg-query", "-W", "-f=${db:Status-Abbrev}", pkg], capture_output=True, text=True, timeout=4)
        inst = d.returncode == 0 and d.stdout.strip().startswith("ii")
    deps = []
    dep_r = subprocess.run(["apt-cache", "depends", "--no-recommends", "--no-suggests", "--no-conflicts", "--no-breaks", "--no-replaces", "--no-enhances", pkg], capture_output=True, text=True, timeout=6)
    for line in dep_r.stdout.splitlines():
        s = line.strip()
        if s.startswith("Depends:"):
            deps.append(s.split(":", 1)[1].strip())
    print(json.dumps({"source": "apt", "id": pkg, "version": version, "installed": inst, "summary": desc, "installed_size_kb": size_kb, "dependencies": deps[:20]}, indent=2))
else:
    if not shutil.which("flatpak"):
        print(json.dumps({"error": "flatpak unavailable"}))
        sys.exit(1)
    r = subprocess.run(["flatpak", "info", "--", pkg], capture_output=True, text=True, timeout=6)
    inst = r.returncode == 0
    if not inst:
        r = subprocess.run(["flatpak", "remote-info", "flathub", "--", pkg], capture_output=True, text=True, timeout=8)
    if r.returncode != 0:
        print(json.dumps({"error": f"Flatpak app not found: {pkg}"}))
        sys.exit(1)
    print(json.dumps({"source": "flatpak", "id": pkg, "installed": inst, "raw": r.stdout.strip()}, indent=2))
PY
      exit $?
    fi
    if [[ "$source" == "apt" ]]; then
      command -v apt-cache >/dev/null 2>&1 || { echo 'apt-cache unavailable on this host.' >&2; exit 1; }
      apt-cache show -- "$pkg"
    else
      command -v flatpak >/dev/null 2>&1 || { echo 'flatpak unavailable on this host.' >&2; exit 1; }
      flatpak info -- "$pkg" 2>/dev/null || flatpak remote-info flathub -- "$pkg"
    fi
    ;;

  installed)
    if [[ "$JSON_OUT" == true ]]; then
      python3 - <<'PY'
import json, shutil, subprocess
apt_pkgs, fp_pkgs = [], []
if shutil.which("dpkg-query"):
    manual = set()
    if shutil.which("apt-mark"):
        mr = subprocess.run(["apt-mark", "showmanual"], capture_output=True, text=True, timeout=6)
        manual = {l.strip() for l in mr.stdout.splitlines() if l.strip()}
    dr = subprocess.run(["dpkg-query", "-W", "-f=${Package}\t${Version}\t${db:Status-Abbrev}\n"], capture_output=True, text=True, timeout=6)
    for line in dr.stdout.splitlines():
        parts = line.split("\t")
        if len(parts) == 3 and parts[2].startswith("ii"):
            if not manual or parts[0] in manual:
                apt_pkgs.append({"id": parts[0], "name": parts[0], "version": parts[1], "source": "apt"})
if shutil.which("flatpak"):
    fr = subprocess.run(["flatpak", "list", "--app", "--columns=application,name,version,origin"], capture_output=True, text=True, timeout=6)
    if fr.returncode == 0:
        for line in fr.stdout.splitlines():
            cols = line.split("\t")
            if cols and cols[0].strip():
                fp_pkgs.append({"id": cols[0].strip(), "name": cols[1].strip() if len(cols) > 1 else cols[0].strip(), "version": cols[2].strip() if len(cols) > 2 else "", "origin": cols[3].strip() if len(cols) > 3 else "", "source": "flatpak"})
print(json.dumps({"apt": apt_pkgs[:120], "flatpak": fp_pkgs, "total_apt_manual": len(apt_pkgs), "total_flatpak": len(fp_pkgs)}, indent=2))
PY
      exit 0
    fi
    if command -v dpkg-query >/dev/null 2>&1; then
      echo '=== APT (manually installed) ==='
      if command -v apt-mark >/dev/null 2>&1; then
        apt-mark showmanual | head -n 100
      else
        dpkg-query -W -f='${Package}\t${Version}\n' | head -n 100
      fi
    else
      echo 'dpkg-query unavailable on this host.'
    fi
    if command -v flatpak >/dev/null 2>&1; then
      echo '=== Flatpak ==='
      flatpak list --app --columns=application,name,version,origin
    fi
    ;;

  updates)
    if [[ "$JSON_OUT" == true ]]; then
      python3 - <<'PY'
import json, shutil, subprocess
apt_up, fp_up = [], []
apt_ok = shutil.which("apt-get") is not None
if apt_ok:
    r = subprocess.run(["apt-get", "-s", "-q", "upgrade"], capture_output=True, text=True, timeout=8)
    for line in r.stdout.splitlines():
        if line.startswith("Inst "):
            parts = line.split()
            if len(parts) >= 2:
                apt_up.append({"id": parts[1], "detail": line[5:].strip(), "source": "apt"})
fp_ok = shutil.which("flatpak") is not None
if fp_ok:
    r = subprocess.run(["flatpak", "remote-ls", "--updates", "--columns=application,version,origin"], capture_output=True, text=True, timeout=8)
    if r.returncode == 0:
        for line in r.stdout.splitlines():
            cols = line.split("\t")
            if cols and cols[0].strip():
                fp_up.append({"id": cols[0].strip(), "version": cols[1].strip() if len(cols) > 1 else "", "origin": cols[2].strip() if len(cols) > 2 else "", "source": "flatpak"})
print(json.dumps({"apt_available": apt_ok, "flatpak_available": fp_ok, "apt": apt_up, "flatpak": fp_up, "total": len(apt_up) + len(fp_up)}, indent=2))
PY
      exit 0
    fi
    if command -v apt >/dev/null 2>&1; then
      echo '=== APT upgradable ==='
      apt list --upgradable 2>/dev/null || true
    else
      echo 'APT unavailable on this host.'
    fi
    if command -v flatpak >/dev/null 2>&1; then
      echo '=== Flatpak updates ==='
      flatpak remote-ls --updates --columns=application,version,origin 2>/dev/null || true
    fi
    ;;

  install)
    [[ $# -eq 2 ]] || { echo 'install requires <apt|flatpak> <pkg>' >&2; exit 2; }
    source="$1"
    pkg="$2"
    validate_pkg_id "$source" "$pkg"
    if [[ "$source" == "apt" ]]; then
      if [[ "$DRY_RUN" == false ]]; then
        command -v apt-get >/dev/null 2>&1 || { echo 'apt-get unavailable on this host.' >&2; exit 1; }
        command -v pkexec >/dev/null 2>&1 || { echo 'pkexec (PolicyKit) is required for privileged APT installation.' >&2; exit 1; }
      fi
      run_mutating pkexec env DEBIAN_FRONTEND=noninteractive apt-get install -y -- "$pkg"
    else
      if [[ "$DRY_RUN" == false ]]; then
        command -v flatpak >/dev/null 2>&1 || { echo 'flatpak unavailable on this host.' >&2; exit 1; }
      fi
      run_mutating flatpak install -y -- "$pkg"
    fi
    ;;

  remove)
    [[ $# -eq 2 ]] || { echo 'remove requires <apt|flatpak> <pkg>' >&2; exit 2; }
    source="$1"
    pkg="$2"
    validate_pkg_id "$source" "$pkg"
    if [[ "$source" == "apt" ]]; then
      if is_protected_apt_pkg "$pkg"; then
        printf 'Refusing to remove protected Linux Mint / NEXUS base package: %s\n' "$pkg" >&2
        exit 1
      fi
      if [[ "$DRY_RUN" == false ]]; then
        command -v apt-get >/dev/null 2>&1 || { echo 'apt-get unavailable on this host.' >&2; exit 1; }
        command -v pkexec >/dev/null 2>&1 || { echo 'pkexec (PolicyKit) is required for privileged APT removal.' >&2; exit 1; }
      fi
      run_mutating pkexec env DEBIAN_FRONTEND=noninteractive apt-get remove -y -- "$pkg"
    else
      if [[ "$DRY_RUN" == false ]]; then
        command -v flatpak >/dev/null 2>&1 || { echo 'flatpak unavailable on this host.' >&2; exit 1; }
      fi
      run_mutating flatpak uninstall -y -- "$pkg"
    fi
    ;;

  *)
    printf 'Unknown command: %s\n' "$CMD" >&2
    usage >&2
    exit 2
    ;;
esac
