#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/log.sh"

# One step per app, so the count only depends on what we're actually acting on.
BK_TOTAL=0

APPS_DIR="$HOME/.local/share/applications"
ICONS_DIR="$HOME/.local/share/icons"
DATA_DIR="$HOME/.local/share/brave-pwa"

MAIN_USER_DATA="$HOME/.config/BraveSoftware/Brave-Browser"
MAIN_PROFILE="$MAIN_USER_DATA/Default"

# On Wayland, force native Wayland so the app_id is the wayland form we match below.
OZONE=""
[ "${XDG_SESSION_TYPE:-}" = wayland ] && OZONE="--ozone-platform=wayland"

# name|display name|url|icon url (optional)|svg fill override (optional)
# Each app runs as its own isolated Brave instance (own --user-data-dir + a profile
# named after the app). That gives it a unique, non-colliding window identity so GNOME
# shows its own icon. The data dir is seeded once from your main Brave profile, so your
# logins, extensions and settings carry over.
APPS=(
  "whatsapp|WhatsApp|https://web.whatsapp.com|https://cdn.simpleicons.org/whatsapp"
  "work-whatsapp|Work WhatsApp|https://web.whatsapp.com|https://cdn.simpleicons.org/whatsapp"
  "chatgpt|ChatGPT|https://chatgpt.com|https://cdn.jsdelivr.net/npm/simple-icons@11/icons/openai.svg|#ffffff"
  "claude|Claude|https://claude.ai|https://cdn.simpleicons.org/claude"
  "canva|Canva|https://www.canva.com"
  "notion|Notion|https://www.notion.so|https://upload.wikimedia.org/wikipedia/commons/e/e9/Notion-logo.svg"
)

# Apps that must NOT inherit your main Brave profile — they need a fresh, independent
# login (e.g. a second WhatsApp account). They start logged out so you sign in separately;
# otherwise they'd clone the same session and show the same account as the seeded app.
NOSEED=(work-whatsapp)

is_noseed() { [[ " ${NOSEED[*]} " == *" $1 "* ]]; }

usage() {
  cat <<EOF
Usage:
  $0 install   [app ...]   Install all apps, or only the ones given
  $0 uninstall [app ...]   Uninstall all apps, or only the ones given
  $0 list                  List available apps

Apps: $(for entry in "${APPS[@]}"; do echo -n "${entry%%|*} "; done)
EOF
  exit 1
}

find_app() {
  for entry in "${APPS[@]}"; do
    [ "${entry%%|*}" = "$1" ] && echo "$entry" && return 0
  done
  echo "ERROR: unknown app: $1" >&2
  return 1
}

# True while the main Brave profile is locked by a live process (copying it then is unsafe).
main_brave_running() {
  local lock="$MAIN_USER_DATA/SingletonLock" pid
  [ -L "$lock" ] || return 1
  pid="$(readlink "$lock")"; pid="${pid##*-}"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

# Copy the main Brave profile into an app's isolated data dir so it starts logged in,
# with your extensions and settings. Local State (holds the os_crypt key) MUST come
# along or saved cookies won't decrypt. --reflink=auto makes this a copy-on-write clone
# on Btrfs/XFS (near-zero disk); it degrades to a normal copy elsewhere.
# ponytail: the copy is a one-time snapshot — it won't stay in sync with the main
#   profile afterward. Re-run install after uninstalling an app to reseed it.
seed_profile() {
  local name="$1" udd="$DATA_DIR/$name" dst="$DATA_DIR/$name/$name"
  mkdir -p "$udd"
  cp -a "$MAIN_USER_DATA/Local State" "$udd/Local State" 2>/dev/null || true
  rm -rf "$dst"
  cp -a --reflink=auto "$MAIN_PROFILE" "$dst"
  # Drop regenerable caches and the stale process lock from the copy.
  rm -rf "$dst/Cache" "$dst/Code Cache" "$dst/GPUCache" "$dst"/*DawnCache \
         "$dst/GraphiteDawnCache" "$dst/Shared Dictionary" \
         "$dst/Service Worker/CacheStorage" "$dst/Service Worker/ScriptCache" 2>/dev/null || true
  rm -f "$dst"/Singleton* 2>/dev/null || true
  touch "$udd/.seeded"
}

install_app() {
  IFS='|' read -r name display url icon_url fill <<<"$1"
  local domain ext icon desktop wmclass
  domain="${url#*//}" domain="${domain%%/*}"
  desktop="$APPS_DIR/brave-pwa-$name.desktop"

  # The Wayland app_id Brave emits for this instance (verified via WAYLAND_DEBUG).
  # ponytail: the "__" is Brave's encoding of the empty URL path; holds for the
  #   root-domain URLs here. If you add a URL with a path, re-derive with:
  #   WAYLAND_DEBUG=1 <exec> 2>&1 | grep set_app_id
  wmclass="brave-${domain}__-${name}"

  # ponytail: transparent-background icon urls where the favicon service ships a white plate
  icon_url="${icon_url:-https://www.google.com/s2/favicons?domain=$domain&sz=256}"
  ext=png
  case "$icon_url" in *simpleicons*|*.svg) ext=svg ;; esac
  icon="$ICONS_DIR/brave-pwa-$name.$ext"

  step "Installing $display"

  rm -f "$ICONS_DIR/brave-pwa-$name".{png,svg}
  curl -fsSL -A "Mozilla/5.0" "$icon_url" -o "$icon" ||
    warn "could not download icon for $display"
  say "icon: $icon"

  if [ -n "$fill" ] && [ "$ext" = svg ]; then
    sed -i "s|<svg |<svg fill=\"$fill\" |" "$icon"
  fi

  if [ -f "$DATA_DIR/$name/.seeded" ]; then
    say "profile already seeded"
  elif is_noseed "$name"; then
    say "fresh profile (separate login; not seeded from your main Brave)"
    mkdir -p "$DATA_DIR/$name/$name"
    touch "$DATA_DIR/$name/.seeded"
  elif [ -d "$MAIN_PROFILE" ]; then
    say "seeding from your main Brave profile (logins, extensions, settings)"
    seed_profile "$name"
  else
    warn "no main Brave profile found; app will start logged out"
  fi

  cat >"$desktop" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=$display
Exec=brave-browser --user-data-dir=$DATA_DIR/$name --profile-directory=$name --class=brave-pwa-$name $OZONE --app=$url
Icon=$icon
Terminal=false
StartupWMClass=$wmclass
Categories=Network;
EOF
  say "wrote $desktop"
}

uninstall_app() {
  IFS='|' read -r name display url _ <<<"$1"

  step "Uninstalling $display"
  rm -f "$APPS_DIR/brave-pwa-$name.desktop" "$ICONS_DIR/brave-pwa-$name".{png,svg}
  say "removed the launcher and icon"

  if [ -d "$DATA_DIR/$name" ]; then
    say "app data (login) kept — remove it with: rm -rf \"$DATA_DIR/$name\""
  fi
}

[ $# -ge 1 ] || usage
cmd="$1"
shift

case "$cmd" in
  list)
    for entry in "${APPS[@]}"; do
      IFS='|' read -r name display url _ <<<"$entry"
      installed=" "
      [ -f "$APPS_DIR/brave-pwa-$name.desktop" ] && installed="✅"
      printf "%s %-15s %-15s %s\n" "$installed" "$name" "$display" "$url"
    done
    exit 0
    ;;
  install)
    if ! command -v brave-browser >/dev/null 2>&1; then
      echo "ERROR: brave-browser not found. Install it with:" >&2
      echo "  curl -fsS https://dl.brave.com/install.sh | sh" >&2
      exit 1
    fi
    mkdir -p "$APPS_DIR" "$ICONS_DIR" "$DATA_DIR"
    action=install_app
    ;;
  uninstall)
    action=uninstall_app
    ;;
  *)
    usage
    ;;
esac

# Resolve which apps we're acting on.
entries=()
if [ $# -eq 0 ]; then
  entries=("${APPS[@]}")
else
  for name in "$@"; do entries+=("$(find_app "$name")"); done
fi
BK_TOTAL=$(( ${#entries[@]} + 1 ))   # +1 for the desktop-database refresh

# Seeding copies your live Brave profile, so Brave must be closed for a clean copy.
if [ "$cmd" = install ]; then
  need_seed=0
  for entry in "${entries[@]}"; do
    n="${entry%%|*}"
    is_noseed "$n" && continue
    [ -f "$DATA_DIR/$n/.seeded" ] || need_seed=1
  done
  if [ "$need_seed" = 1 ] && main_brave_running; then
    echo "ERROR: first-time setup copies your Brave profile (logins, extensions, settings)" >&2
    echo "       into each app. That needs Brave fully closed so the copy isn't corrupted." >&2
    echo "       Quit Brave completely, then re-run:  $0 install $*" >&2
    exit 1
  fi
fi

for entry in "${entries[@]}"; do "$action" "$entry"; done

step "Exporting to the desktop database"
command -v update-desktop-database >/dev/null 2>&1 &&
  run update-desktop-database "$APPS_DIR" || true
