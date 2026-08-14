#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/log.sh"

REMOTE_NAME="${REMOTE_NAME:-googleDrive}"
REMOTE="${REMOTE_NAME}:"
LOCAL_DIR="${LOCAL_DIR:-$HOME/GoogleDrive}"
TIMER_INTERVAL="${TIMER_INTERVAL:-1m}"
MAX_DELETE="${MAX_DELETE:-100}"

SERVICE_NAME="rclone-gdrive.service"
TIMER_NAME="rclone-gdrive.timer"
WRAPPER="$HOME/.local/bin/rclone-gdrive-bisync-notify"
SYSTEMD_DIR="$HOME/.config/systemd/user"
CACHE_DIR="$HOME/.cache/rclone"
LATEST_LOG="$CACHE_DIR/rclone-gdrive-bisync.log"

RUN_INIT=0
ASSUME_YES=${NONINTERACTIVE:-0}   # NONINTERACTIVE=1 implies --yes

for arg in "$@"; do
  case "$arg" in
    --init)
      RUN_INIT=1
      ;;
    --yes|-y)
      ASSUME_YES=1
      ;;
    --help|-h)
      cat <<EOF
Usage:
  $0              Install/update service, timer, and notifications only
  $0 --init       Also run first baseline bisync with --resync
  $0 --init --yes Skip the baseline confirmation (for unattended runs)

Environment variables:
  REMOTE_NAME     Default: googleDrive
  LOCAL_DIR       Default: \$HOME/GoogleDrive
  TIMER_INTERVAL  Default: 1m
  MAX_DELETE      Default: 100
  NONINTERACTIVE  1 implies --yes
EOF
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg"
      exit 1
      ;;
  esac
done

step "Checking dependencies"

# cmd or cmd:package (when the dnf package name differs from the command)
MISSING=0
for dep in rclone systemctl flock notify-send:libnotify fusermount3:fuse3; do
  cmd="${dep%%:*}"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    warn "missing $cmd — install it with: sudo dnf install ${dep#*:}"
    MISSING=1
  fi
done

if [ "$MISSING" -ne 0 ]; then
  say "install the missing packages, then rerun this script"
  exit 1
fi

step "Checking rclone remote $REMOTE"

if ! rclone listremotes | grep -qx "${REMOTE_NAME}:"; then
  warn "remote ${REMOTE_NAME}: does not exist — create it first with: rclone config"
  exit 1
fi

rclone lsf "$REMOTE" --drive-skip-dangling-shortcuts >/dev/null
say "remote is reachable"

step "Stopping any old rclone service and timer"

systemctl --user disable --now "$TIMER_NAME" >/dev/null 2>&1 || true
systemctl --user disable --now "$SERVICE_NAME" >/dev/null 2>&1 || true

if findmnt "$LOCAL_DIR" >/dev/null 2>&1; then
  say "$LOCAL_DIR is mounted — unmounting the stale rclone mount"
  fusermount3 -uz "$LOCAL_DIR" >/dev/null 2>&1 || true
fi

if findmnt "$LOCAL_DIR" >/dev/null 2>&1; then
  warn "could not unmount $LOCAL_DIR — check it with: findmnt $LOCAL_DIR ; fusermount3 -uz $LOCAL_DIR"
  exit 1
fi

mkdir -p "$LOCAL_DIR" "$SYSTEMD_DIR" "$CACHE_DIR" "$HOME/.local/bin"

step "Importing the GNOME notification environment"

systemctl --user import-environment DISPLAY WAYLAND_DISPLAY XAUTHORITY DBUS_SESSION_BUS_ADDRESS >/dev/null 2>&1 || true
dbus-update-activation-environment --systemd DISPLAY WAYLAND_DISPLAY XAUTHORITY DBUS_SESSION_BUS_ADDRESS >/dev/null 2>&1 || true

step "Writing the notification wrapper"
say "$WRAPPER"

cat > "$WRAPPER" <<'EOF'
#!/usr/bin/env bash
set -u

LOCAL="${LOCAL_DIR:-$HOME/GoogleDrive}"
REMOTE_NAME="${REMOTE_NAME:-googleDrive}"
REMOTE="${REMOTE_NAME}:"
MAX_DELETE="${MAX_DELETE:-100}"

LOG_DIR="$HOME/.cache/rclone"
LOG_FILE="$LOG_DIR/rclone-gdrive-bisync.log"
LOCK_FILE="$LOG_DIR/rclone-gdrive-bisync.lock"

mkdir -p "$LOG_DIR"

notify() {
  local title="$1"
  local body="$2"
  local urgency="${3:-normal}"

  if command -v notify-send >/dev/null 2>&1; then
    notify-send -a "rclone Google Drive" -u "$urgency" "$title" "$body"
  fi
}

summarize_changes() {
  local file="$1"

  grep -E 'INFO  : .+: (Copied|Deleted|Moved|Renamed)' "$file" 2>/dev/null \
    | grep -vEi 'Duplicate object|Duplicate directory|ignoring' \
    | sed -E 's/^[0-9\/: ]+ INFO  : //' \
    | head -n 12
}

exec 9>"$LOCK_FILE"

if ! flock -n 9; then
  exit 0
fi

# ponytail: single log file, truncated per run; add rotation if history matters
: > "$LOG_FILE"

rclone bisync "$LOCAL" "$REMOTE" \
  --recover \
  --resilient \
  --max-lock 5m \
  --max-delete "$MAX_DELETE" \
  --conflict-resolve newer \
  --conflict-loser pathname \
  --create-empty-src-dirs \
  --drive-skip-dangling-shortcuts \
  --log-file "$LOG_FILE" \
  --log-level INFO

STATUS=$?

if [ "$STATUS" -eq 0 ]; then
  SUMMARY="$(summarize_changes "$LOG_FILE")"

  if [ -n "$SUMMARY" ]; then
    notify "Google Drive synced changes" "$SUMMARY"
  fi

  exit 0
else
  ERROR_SUMMARY="$(tail -n 12 "$LOG_FILE" 2>/dev/null)"
  notify "Google Drive sync failed" "$ERROR_SUMMARY" "critical"
  exit "$STATUS"
fi
EOF

chmod +x "$WRAPPER"

step "Writing the systemd user service"

cat > "$SYSTEMD_DIR/$SERVICE_NAME" <<EOF
[Unit]
Description=Bisync local Google Drive folder with Google Drive
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
Environment=REMOTE_NAME=$REMOTE_NAME
Environment=LOCAL_DIR=$LOCAL_DIR
Environment=MAX_DELETE=$MAX_DELETE
ExecStart=$WRAPPER
EOF
say "$SYSTEMD_DIR/$SERVICE_NAME"

step "Writing the systemd user timer"

cat > "$SYSTEMD_DIR/$TIMER_NAME" <<EOF
[Unit]
Description=Run Google Drive bisync every $TIMER_INTERVAL

[Timer]
OnBootSec=2m
OnUnitActiveSec=$TIMER_INTERVAL
AccuracySec=15s
Unit=$SERVICE_NAME
Persistent=true

[Install]
WantedBy=timers.target
EOF
say "$SYSTEMD_DIR/$TIMER_NAME — every $TIMER_INTERVAL"

if [ "$RUN_INIT" -eq 1 ]; then
  step "Running the initial baseline"
  say "local:  $LOCAL_DIR"
  say "remote: $REMOTE"

  if [ -z "$(find "$LOCAL_DIR" -mindepth 1 -maxdepth 1 2>/dev/null | head -n 1)" ]; then
    say "local folder is empty — downloading remote files first"
    run rclone copy "$REMOTE" "$LOCAL_DIR" \
      --progress \
      --drive-skip-dangling-shortcuts
  else
    say "local folder is not empty — skipping the initial rclone copy"
  fi

  say "dry run first"
  run rclone bisync "$LOCAL_DIR" "$REMOTE" \
    --resync \
    --resync-mode newer \
    --drive-skip-dangling-shortcuts \
    --dry-run \
    -v

  # This gates a --resync that can delete files, so it stays a prompt for humans
  # and only an explicit --yes (or NONINTERACTIVE=1) skips it.
  if [ "$ASSUME_YES" -eq 1 ]; then
    say "--yes given — proceeding with the real baseline without confirmation"
  else
    # Not wrapped: the prompt must reach the terminal unbuffered.
    read -r -p "Proceed with real baseline bisync? Type YES to continue: " CONFIRM

    if [ "$CONFIRM" != "YES" ]; then
      warn "baseline cancelled — service files were written, but the timer will not be enabled"
      exit 1
    fi
  fi

  say "running the real baseline"
  run rclone bisync "$LOCAL_DIR" "$REMOTE" \
    --resync \
    --resync-mode newer \
    --drive-skip-dangling-shortcuts \
    -v
fi

step "Enabling the timer"

run systemctl --user daemon-reload
run systemctl --user enable --now "$TIMER_NAME"
run systemctl --user --no-pager status "$TIMER_NAME" || true

step "Exporting sync setup"
say "local Google Drive folder: $LOCAL_DIR"
say "useful commands:"
say "  systemctl --user list-timers | grep rclone"
say "  systemctl --user start $SERVICE_NAME"
say "  journalctl --user -u $SERVICE_NAME -f"
say "  tail -f $LATEST_LOG"
