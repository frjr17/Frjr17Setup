#!/usr/bin/env bash
#
# Point one or more Brave/Chromium profiles at the Noto font families.
#
#   ./braveFonts.sh ~/.config/BraveSoftware/Brave-Browser/Default
#   ./braveFonts.sh ~/.local/share/brave-pwa/claude/claude
#
# Chromium keeps web font defaults in webkit.webprefs.fonts inside the profile's
# Preferences JSON, keyed by ISO 15924 script code — "Zyyy" (Common) is the
# default that applies to Latin text. There is no enterprise policy for these,
# so editing Preferences is the only way to set them without clicking through
# brave://settings/fonts.
#
# The file is merged, never replaced: a profile that already exists keeps every
# other setting in it. Brave rewrites Preferences when it exits, so a profile
# that is currently open is skipped rather than clobbered.
#
# Deliberately not a log.sh script — callers wrap it in `run` and get the
# prefixing from there.

set -euo pipefail

[ $# -ge 1 ] || { echo "usage: $0 <profile-dir> [profile-dir ...]" >&2; exit 1; }

# The SingletonLock that marks a live browser sits in the user data dir, one
# level above the profile itself.
profile_in_use() {
  local lock="${1%/*}/SingletonLock" pid
  [ -L "$lock" ] || return 1
  pid="$(readlink "$lock")"; pid="${pid##*-}"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

status=0

for profile in "$@"; do
  if profile_in_use "$profile"; then
    echo "WARN: $profile is open in a running browser — skipping (close it and re-run)" >&2
    status=1
    continue
  fi

  mkdir -p "$profile"
  python3 - "$profile/Preferences" <<'PY'
import json, os, sys

path = sys.argv[1]

# generic CSS family -> Noto family. "standard" is what a page gets when it
# names no font at all.
FONTS = {
    "standard":  "Noto Sans",
    "sansserif": "Noto Sans",
    "serif":     "Noto Serif",
    "fixed":     "Noto Sans Mono",
    "math":      "Noto Sans Math",
}

try:
    with open(path, encoding="utf-8") as fh:
        prefs = json.load(fh)
except FileNotFoundError:
    prefs = {}            # profile has never been launched; Chromium fills the rest in
except json.JSONDecodeError:
    print(f"ERROR: {path} is not valid JSON; refusing to overwrite it", file=sys.stderr)
    raise SystemExit(1)

node = prefs.setdefault("webkit", {}).setdefault("webprefs", {}).setdefault("fonts", {})
for generic, family in FONTS.items():
    node.setdefault(generic, {})["Zyyy"] = family

# Write via a temp file in the same directory so an interrupted run can't leave
# a half-written Preferences behind.
tmp = path + ".frjr17.tmp"
with open(tmp, "w", encoding="utf-8") as fh:
    json.dump(prefs, fh, separators=(",", ":"))
os.replace(tmp, path)

print("fonts set: " + ", ".join(f"{g}={f}" for g, f in FONTS.items()))
PY
  echo "  in $profile"
done

exit "$status"
