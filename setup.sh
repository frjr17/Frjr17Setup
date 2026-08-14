#!/usr/bin/env bash
#
# Provision this machine end to end, in dependency order.
#
#   sudo -v && ./setup.sh          # ~40 minutes, no supervision needed
#
# Git identity for favoriteShell.sh comes from the environment (or its flags):
#
#   GITHUB_NAME="Jane Doe" GITHUB_USERNAME=janedoe GITHUB_EMAIL=jane@example.com ./setup.sh
#
# Every stage is idempotent, so a run that dies partway is resumed by running
# this script again — there is no --resume flag because none is needed.
#
# Each stage prints its own BuildKit-style output (see log.sh); this script only
# separates them and reports which ones failed.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Nobody is watching: stages take the safe default at every prompt, and `run sudo`
# refuses to hang waiting for a password.
export NONINTERACTIVE=1

# Claim sudo at t=0 rather than 20 minutes in.
if ! sudo -n true 2>/dev/null; then
  printf 'setup.sh needs a cached sudo timestamp so it can run unattended.\nRun `sudo -v`, then start it again.\n' >&2
  exit 1
fi
# Keep the timestamp warm for the whole provision.
while sudo -n true 2>/dev/null; do sleep 50; done &
KEEPALIVE=$!
trap 'kill "$KEEPALIVE" 2>/dev/null' EXIT

# Order matters:
#   gnomeSettings  enables RPM Fusion, which apps needs for libavcodec-freeworld
#   whitesurTheme  installs the GTK theme gnomeExtensions then selects as the shell theme
#   bravePwa       needs Brave from apps, and needs Brave to have never been launched
STAGES=(
  gnomeSettings.sh
  apps.sh
  favoriteShell.sh
  dev.sh
  whitesurTheme.sh
  gnomeExtensions.sh
  "bravePwa.sh install"
)

FAILED=()
n=0

for stage in "${STAGES[@]}"; do
  n=$(( n + 1 ))
  # Word-split deliberately: entries may carry arguments.
  # shellcheck disable=SC2086
  set -- $stage
  script=$1; shift

  printf '\n=== [%d/%d] %s ===\n\n' "$n" "${#STAGES[@]}" "$stage"
  if ! "$SCRIPT_DIR/$script" "$@"; then
    FAILED+=("$stage")
  fi
done

printf '\n=== setup.sh finished ===\n\n'

if (( ${#FAILED[@]} )); then
  printf 'FAILED (re-run ./setup.sh to retry, or run these directly):\n'
  printf '  %s\n' "${FAILED[@]}"
  printf '\n'
fi

cat <<'EOF'
Not run automatically, by design:
  ./fedoraHarden.sh --apply --yes   hardening; dry-run by default so you can read it first
  ./googleDrive.sh --init           needs `rclone config`, an interactive OAuth flow
  ./snapper.sh                      Btrfs-only, and changes your boot menu

Reboot to pick up the docker group and the lid-close setting.
EOF

(( ${#FAILED[@]} == 0 ))
