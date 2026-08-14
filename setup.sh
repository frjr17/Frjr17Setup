#!/usr/bin/env bash
#
# Provision this machine end to end, in dependency order.
#
#   ./setup.sh          # asks a few questions, then ~40 minutes unattended
#
# Everything interactive happens in the preamble below: your Git identity and
# your sudo password. After that nothing stops for input.
#
# Pre-set any of them to skip that question:
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

# ─────────────────────────────────────────────
# Preamble — the only part that talks to you
# ─────────────────────────────────────────────

# favoriteShell.sh writes these into your global Git config. Ask here, at t=0,
# so the stage doesn't stall 20 minutes in waiting for an answer.
ask_identity() {
  local var=$1 label=$2
  if [[ -n ${!var:-} ]]; then
    printf '%s: %s (from the environment)\n' "$label" "${!var}"
    return 0
  fi
  if [[ ! -t 0 ]]; then
    printf '%s is not set and there is no terminal to ask on.\nPass it in the environment: %s="..." ./setup.sh\n' "$var" "$var" >&2
    exit 1
  fi
  read -rp "$label: " "$var"
  [[ -n ${!var} ]] || { printf '%s is required.\n' "$label" >&2; exit 1; }
  export "$var"
}

echo "Git identity for this machine:"
ask_identity GITHUB_NAME     "  Git full name"
ask_identity GITHUB_USERNAME "  GitHub username"
ask_identity GITHUB_EMAIL    "  Git email"
echo

# Claim sudo in the same breath, so no later stage stops for a password.
sudo -v || {
  printf '\nsetup.sh needs sudo to install packages.\n' >&2
  exit 1
}

# From here on nobody is watching: stages take the safe default at every prompt,
# and `run sudo` refuses to hang waiting for a password.
export NONINTERACTIVE=1
# Keep the timestamp warm for the whole provision.
while sudo -n true 2>/dev/null; do sleep 50; done &
KEEPALIVE=$!
trap 'kill "$KEEPALIVE" 2>/dev/null' EXIT

# Order matters:
#   snapper        first, so the dnf snapshot hook is in place before any other
#                  stage installs anything — that's what makes the rest of this
#                  provision rollback-able. Btrfs only; it fails loudly elsewhere
#                  and the remaining stages still run.
#   gnomeSettings  enables RPM Fusion, which apps needs for libavcodec-freeworld
#   whitesurTheme  installs the GTK theme gnomeExtensions then selects as the shell theme
#   bravePwa       needs Brave from apps, and needs Brave to have never been launched
STAGES=(
  snapper.sh
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

Reboot to pick up the docker group and the lid-close setting.
EOF

(( ${#FAILED[@]} == 0 ))
