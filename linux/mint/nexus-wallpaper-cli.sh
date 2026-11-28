#!/usr/bin/env bash
# Cross-edition NEXUS OS wallpaper catalogue & on-demand applier.
# Supports Cinnamon, XFCE, Lite LXQt, and Lite Openbox without downloading
# wallpaper collections during ISO build.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
WALLPAPERS_JSON=""
for candidate in \
  /usr/local/share/nexus-os/wallpapers.json \
  /usr/local/share/nexus-os/cinnamon/wallpapers.json \
  "$REPO_ROOT/linux/config/wallpapers.json" \
  "$REPO_ROOT/linux/cinnamon/wallpapers.json"; do
  if [[ -r "$candidate" ]]; then
    WALLPAPERS_JSON="$candidate"
    break
  fi
done

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/nexus-os/wallpapers"
STATE_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/nexus-os/wallpaper.conf"

usage() {
  cat <<'USAGE'
Usage: nexus-wallpaper [COMMAND] [OPTIONS]

Commands:
  list [--category KEY] [--json]   List verified wallpaper catalog entries
  apply (--id ID | --url URL | --file PATH) [--fit MODE] [--edition NAME] [--dry-run]
                                   Download on-demand (if HTTPS URL) and apply to desktop
  current [--json]                 Print the currently configured NEXUS wallpaper

Fit modes: zoom | scaled | stretched | centered | wallpaper
Editions:  auto | cinnamon | xfce | lite-lxqt | lite
USAGE
}

detect_edition() {
  local desktop="${XDG_CURRENT_DESKTOP:-${DESKTOP_SESSION:-}}"
  case "${desktop,,}" in
    *cinnamon*) echo "cinnamon" ;;
    *xfce*) echo "xfce" ;;
    *lxqt*) echo "lite-lxqt" ;;
    *openbox*) echo "lite" ;;
    *)
      if [[ -r /etc/nexus-os/edition ]]; then
        tr -d '[:space:]' < /etc/nexus-os/edition
      elif command -v cinnamon-settings >/dev/null 2>&1; then
        echo "cinnamon"
      elif command -v xfconf-query >/dev/null 2>&1; then
        echo "xfce"
      elif command -v pcmanfm-qt >/dev/null 2>&1; then
        echo "lite-lxqt"
      else
        echo "lite"
      fi
      ;;
  esac
}

CMD="${1:-list}"
if [[ "$CMD" == "--help" || "$CMD" == "-h" ]]; then
  usage
  exit 0
fi
shift || true

CATEGORY=""
JSON_OUT=false
WP_ID=""
WP_URL=""
WP_FILE=""
WP_FIT="zoom"
EDITION="auto"
DRY_RUN=false

while (($#)); do
  case "$1" in
    --category) [[ $# -ge 2 ]] || { echo '--category requires a key' >&2; exit 2; }; CATEGORY="$2"; shift 2 ;;
    --json) JSON_OUT=true; shift ;;
    --id) [[ $# -ge 2 ]] || { echo '--id requires a wallpaper id' >&2; exit 2; }; WP_ID="$2"; shift 2 ;;
    --url) [[ $# -ge 2 ]] || { echo '--url requires an https URL' >&2; exit 2; }; WP_URL="$2"; shift 2 ;;
    --file) [[ $# -ge 2 ]] || { echo '--file requires a local image path' >&2; exit 2; }; WP_FILE="$2"; shift 2 ;;
    --fit) [[ $# -ge 2 ]] || { echo '--fit requires zoom|scaled|stretched|centered|wallpaper' >&2; exit 2; }; WP_FIT="$2"; shift 2 ;;
    --edition) [[ $# -ge 2 ]] || { echo '--edition requires auto|cinnamon|xfce|lite-lxqt|lite' >&2; exit 2; }; EDITION="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$WP_FIT" in
  zoom|scaled|stretched|centered|wallpaper) ;;
  *) printf 'Invalid --fit: %s\n' "$WP_FIT" >&2; exit 2 ;;
esac

if [[ "$EDITION" == "auto" ]]; then
  EDITION="$(detect_edition)"
fi

case "$CMD" in
  list)
    [[ -n "$WALLPAPERS_JSON" ]] || { echo 'wallpapers.json catalog not found' >&2; exit 1; }
    python3 - "$WALLPAPERS_JSON" "$CATEGORY" "$JSON_OUT" "$EDITION" <<'PY'
import json, sys
path, category, json_out, edition = sys.argv[1], sys.argv[2].strip().lower(), sys.argv[3] == "true", sys.argv[4]
data = json.loads(open(path, encoding="utf-8").read())
items = data.get("wallpapers", [])
if category and category != "all":
    items = [w for w in items if str(w.get("categoryKey", "")).lower() == category or str(w.get("category", "")).lower() == category]
if json_out:
    print(json.dumps({
        "version": data.get("version"),
        "edition": edition,
        "categories": data.get("categories", []),
        "categoryKeys": data.get("categoryKeys", []),
        "wallpapers": items,
    }, indent=2))
else:
    for w in items:
        print(f"{w['id']}\t{w['categoryKey']}\t{w['title']}\t{w['photographer']}\t{w['license']}")
PY
    ;;
  current)
    local_path=""
    wp_id=""
    if [[ -r "$STATE_FILE" ]]; then
      local_path="$(grep -E '^WALLPAPER_PATH=' "$STATE_FILE" | head -n1 | cut -d= -f2- || true)"
      wp_id="$(grep -E '^WALLPAPER_ID=' "$STATE_FILE" | head -n1 | cut -d= -f2- || true)"
    fi
    if [[ "$JSON_OUT" == true ]]; then
      python3 - "$EDITION" "$wp_id" "$local_path" <<'PY'
import json, sys
print(json.dumps({"edition": sys.argv[1], "id": sys.argv[2] or None, "path": sys.argv[3] or None}))
PY
    else
      printf 'edition=%s id=%s path=%s\n' "$EDITION" "${wp_id:-none}" "${local_path:-default}"
    fi
    ;;
  apply)
    if [[ -n "$WP_ID" ]]; then
      [[ -n "$WALLPAPERS_JSON" ]] || { echo 'wallpapers.json catalog not found' >&2; exit 1; }
      WP_URL="$(python3 - "$WALLPAPERS_JSON" "$WP_ID" <<'PY'
import json, sys
data = json.loads(open(sys.argv[1], encoding="utf-8").read())
wp = next((w for w in data.get("wallpapers", []) if w.get("id") == sys.argv[2]), None)
if not wp:
    sys.exit(1)
print(wp.get("hdUrl") or wp.get("imageUrl") or "")
PY
)" || { printf 'Unknown wallpaper id: %s\n' "$WP_ID" >&2; exit 2; }
    fi

    target_path=""
    if [[ -n "$WP_FILE" ]]; then
      [[ -r "$WP_FILE" ]] || { printf 'Wallpaper file not readable: %s\n' "$WP_FILE" >&2; exit 1; }
      target_path="$(readlink -f -- "$WP_FILE")"
    elif [[ -n "$WP_URL" ]]; then
      if [[ "$WP_URL" == https://* ]]; then
        hash_name="$(printf '%s' "$WP_URL" | sha256sum | awk '{print $1}').img"
        target_path="$CACHE_DIR/$hash_name"
        if [[ "$DRY_RUN" == true ]]; then
          printf '[dry-run] Cache %s -> %s\n' "$WP_URL" "$target_path"
        else
          mkdir -p "$CACHE_DIR"
          if [[ ! -s "$target_path" ]]; then
            tmp_file="$target_path.part.$$"
            if ! curl -fsSL --proto '=https' --tlsv1.2 --max-time 25 "$WP_URL" -o "$tmp_file"; then
              rm -f "$tmp_file"
              echo "Failed to download wallpaper (check internet connection): $WP_URL" >&2
              exit 1
            fi
            if ! python3 - "$tmp_file" <<'PY'
import sys
with open(sys.argv[1], "rb") as f:
    head = f.read(16)
ok = head.startswith(b"\xff\xd8\xff") or head.startswith(b"\x89PNG\r\n\x1a\n") or (head[:4] == b"RIFF" and head[8:12] == b"WEBP") or b"<svg" in head.lower()
sys.exit(0 if ok else 1)
PY
            then
              rm -f "$tmp_file"
              echo "Downloaded file is not a valid JPEG/PNG/WebP/SVG image." >&2
              exit 1
            fi
            mv -f "$tmp_file" "$target_path"
          fi
        fi
      elif [[ -r "$WP_URL" ]]; then
        target_path="$(readlink -f -- "$WP_URL")"
      else
        printf 'Wallpaper URL must be https:// or a readable local path: %s\n' "$WP_URL" >&2
        exit 2
      fi
    else
      echo 'Specify --id, --url, or --file for apply' >&2
      exit 2
    fi

    if [[ "$DRY_RUN" == true ]]; then
      printf '[dry-run] Apply wallpaper (%s, fit=%s) for edition=%s -> %s\n' "${WP_ID:-custom}" "$WP_FIT" "$EDITION" "$target_path"
      exit 0
    fi

    mkdir -p "$(dirname "$STATE_FILE")"
    {
      printf 'WALLPAPER_ID=%s\n' "${WP_ID:-custom}"
      printf 'WALLPAPER_PATH=%s\n' "$target_path"
      printf 'WALLPAPER_FIT=%s\n' "$WP_FIT"
    } > "$STATE_FILE"

    case "$EDITION" in
      cinnamon)
        if command -v gsettings >/dev/null 2>&1; then
          gsettings set org.cinnamon.desktop.background picture-uri "file://$target_path"
          gsettings set org.cinnamon.desktop.background picture-options "$WP_FIT"
        fi
        ;;
      xfce)
        if command -v xfconf-query >/dev/null 2>&1; then
          xfce_style=5
          case "$WP_FIT" in
            centered) xfce_style=1 ;;
            wallpaper) xfce_style=2 ;;
            stretched) xfce_style=3 ;;
            scaled) xfce_style=4 ;;
            zoom) xfce_style=5 ;;
          esac
          while IFS= read -r prop; do
            if [[ "$prop" == */last-image ]]; then
              xfconf-query -c xfce4-desktop -p "$prop" -s "$target_path" || true
            elif [[ "$prop" == */image-style ]]; then
              xfconf-query -c xfce4-desktop -p "$prop" -s "$xfce_style" || true
            fi
          done < <(xfconf-query -c xfce4-desktop -l 2>/dev/null || true)
        fi
        ;;
      lite-lxqt)
        lxqt_mode="zoom"
        case "$WP_FIT" in
          centered) lxqt_mode="center" ;;
          wallpaper) lxqt_mode="tile" ;;
          stretched) lxqt_mode="stretch" ;;
          scaled) lxqt_mode="fit" ;;
          zoom) lxqt_mode="zoom" ;;
        esac
        if command -v pcmanfm-qt >/dev/null 2>&1 && [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
          pcmanfm-qt --set-wallpaper="$target_path" --wallpaper-mode="$lxqt_mode" >/dev/null 2>&1 || true
        fi
        pc_cfg="${XDG_CONFIG_HOME:-$HOME/.config}/pcmanfm-qt/lxqt/settings.conf"
        mkdir -p "$(dirname "$pc_cfg")"
        python3 - "$pc_cfg" "$target_path" "$lxqt_mode" <<'PY'
import configparser, sys
cfg_path, wp, mode = sys.argv[1], sys.argv[2], sys.argv[3]
cp = configparser.RawConfigParser()
cp.optionxform = str
cp.read(cfg_path, encoding="utf-8")
if not cp.has_section("Desktop"):
    cp.add_section("Desktop")
cp.set("Desktop", "Wallpaper", wp)
cp.set("Desktop", "WallpaperMode", mode)
with open(cfg_path, "w", encoding="utf-8") as f:
    cp.write(f, space_around_delimiters=False)
PY
        ;;
      lite)
        if command -v feh >/dev/null 2>&1 && [[ -n "${DISPLAY:-}" ]]; then
          case "$WP_FIT" in
            centered) feh --no-fehbg --bg-center "$target_path" ;;
            wallpaper) feh --no-fehbg --bg-tile "$target_path" ;;
            stretched) feh --no-fehbg --bg-scale "$target_path" ;;
            scaled) feh --no-fehbg --bg-max "$target_path" ;;
            zoom|*) feh --no-fehbg --bg-fill "$target_path" ;;
          esac
        fi
        ;;
    esac
    printf '{"ok":true,"edition":"%s","id":"%s","path":"%s","fit":"%s"}\n' "$EDITION" "${WP_ID:-custom}" "$target_path" "$WP_FIT"
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
