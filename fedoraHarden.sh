#!/usr/bin/env bash
#
# fedora-harden.sh — security hardening baseline for a personal Fedora
# Workstation laptop (single user, GNOME, developer machine).
#
# Threat model: lost/stolen laptop, untrusted Wi-Fi, malicious downloads.
# NOT a server, NOT internet-exposed, no compliance target.
#
# Usage:
#   ./fedora-harden.sh                 # dry run (default) — prints what it WOULD do
#   ./fedora-harden.sh --apply         # actually make changes, confirm each section
#   ./fedora-harden.sh --apply --yes   # no per-section confirmation (services still prompt)
#   ./fedora-harden.sh --only firewall --only updates
#   ./fedora-harden.sh --skip audit
#   ./fedora-harden.sh --apply --force # re-init AIDE db even if one exists
#
# Design rules baked in:
#   * Dry-run is the default. Nothing changes without --apply.
#   * Idempotent: every step checks current state first and prints "[ok]" if
#     already correct instead of reapplying.
#   * Never disables SELinux, never touches disk encryption or Secure Boot
#     (those are detect-and-report only — they need a reinstall / firmware).
#   * Never touches docker. Never disables a service without an explicit
#     per-service "yes", even under --yes.
#   * Every config file edited is backed up first to <file>.bak-<timestamp>.
#
# INTENTIONALLY OMITTED (don't "fix" these — they are skipped on purpose):
# These are Lynis/server/enterprise controls that add friction on a personal
# laptop without addressing this threat model:
#   - Login banners (BANN-*): legal-notice theater; nobody else logs in.
#   - Password aging (AUTH-9286): forced rotation weakens single-user passwords.
#   - umask tightening (AUTH-9328): breaks dev tooling expectations, protects
#     against other local users that don't exist here.
#   - Separate /var, /home, /tmp partitions (FILE-6310): reinstall-level change
#     for a DoS-resistance benefit servers care about, laptops don't.
#   - Remote logging (LOGG-2154): there is no log server; local logs suffice.
#   - sysstat/process accounting (ACCT-*): server capacity forensics.
#   - Disabling USB storage (STRG-1840): a laptop user uses USB sticks.
#   - Uncommon-protocol module blacklisting (dccp/sctp/rds/tipc): kernel
#     already doesn't autoload these on Fedora; near-zero real exposure.
#   - Most KRNL-6000 sysctl tweaks: marginal on a NATed laptop, easy to
#     break Docker/libvirt networking with them.

set -Eeuo pipefail

# ---------------------------------------------------------------------------
# Globals
# ---------------------------------------------------------------------------
DRY_RUN=1            # default; --apply flips to 0
ASSUME_YES=0         # --yes: skip per-SECTION confirmation (not per-service)
FORCE=0              # --force: re-init AIDE even if a db exists
ONLY_SECTIONS=()     # --only foo (repeatable)
SKIP_SECTIONS=()     # --skip foo (repeatable)

LOG_FILE=/var/log/fedora-harden.log
LOG_READY=0
RUN_STAMP=$(date +%F-%H%M%S)

ALL_SECTIONS=(preflight report updates firewall audit rkhunter aide services helpers)

# State collected for the final summary
BACKUPS=()
CHANGED=()
ALREADY_OK=()
MANUAL_FOLLOWUPS=()
BREAKAGE_NOTES=()
LUKS_STATUS="unknown"
SB_STATUS="unknown"
SELINUX_STATUS="unknown"

# Colors (only when stdout is a terminal)
if [[ -t 1 ]]; then
    C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YLW=$'\033[33m'
    C_BLU=$'\033[34m'; C_BLD=$'\033[1m';  C_RST=$'\033[0m'
else
    C_RED='' C_GRN='' C_YLW='' C_BLU='' C_BLD='' C_RST=''
fi

# ---------------------------------------------------------------------------
# Small helpers — every message goes through these so the log stays complete
# ---------------------------------------------------------------------------

# Append a timestamped line to the logfile (once it exists).
log() {
    (( LOG_READY )) && printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG_FILE" || true
}

info()  { echo "${C_BLU}::${C_RST} $*";                log ":: $*"; }
ok()    { echo "${C_GRN}[ok]${C_RST} $*";              log "[ok] $*";   ALREADY_OK+=("$*"); }
did()   { echo "${C_GRN}[changed]${C_RST} $*";         log "[changed] $*"; CHANGED+=("$*"); }
warn()  { echo "${C_YLW}[warn]${C_RST} $*" >&2;        log "[warn] $*"; }
err()   { echo "${C_RED}[error]${C_RST} $*" >&2;       log "[error] $*"; }
die()   { err "$*"; exit 1; }
header(){ echo; echo "${C_BLD}=== $* ===${C_RST}";     log "=== $* ==="; }

# ERR trap: report the failing line loudly. set -E makes it fire in functions.
on_error() {
    err "fedora-harden.sh failed at line $1 (exit code $2). See $LOG_FILE"
}
trap 'on_error $LINENO $?' ERR

# Run a state-CHANGING command. In dry-run it only prints; with --apply it
# runs and tees output into the log. Read-only probes call commands directly.
run_cmd() {
    if (( DRY_RUN )); then
        echo "${C_YLW}[dry-run]${C_RST} would run: $*"
        log "[dry-run] would run: $*"
        return 0
    fi
    log "running: $*"
    if (( LOG_READY )); then
        "$@" 2>&1 | tee -a "$LOG_FILE"
    else
        "$@"
    fi
}

# Back up a file before editing it. Records the backup for the final summary.
backup_file() {
    local f=$1 b
    b="$f.bak-$RUN_STAMP"
    if (( DRY_RUN )); then
        echo "${C_YLW}[dry-run]${C_RST} would back up $f -> $b"
        return 0
    fi
    sudo cp -a "$f" "$b"
    BACKUPS+=("$b")
    log "backed up $f -> $b"
}

# Ask a yes/no question. Returns 0 on yes. Reads from the terminal so it
# works even if stdin is redirected. Used for per-service decisions — these
# ALWAYS prompt, even under --yes.
ask() {
    local prompt=$1 reply
    read -r -p "${C_BLD}${prompt} [y/N]${C_RST} " reply < /dev/tty
    log "prompt: '$prompt' -> '$reply'"
    [[ $reply =~ ^[Yy]([Ee][Ss])?$ ]]
}

# Per-section gate: with --apply and no --yes, confirm before running.
confirm_section() {
    local name=$1
    (( DRY_RUN )) && return 0
    (( ASSUME_YES )) && return 0
    ask "Run section '$name'?"
}

# Should this section run, given --only / --skip? (preflight/report always run)
section_wanted() {
    [[ " ${SKIP_SECTIONS[*]} " == *" $1 "* ]] && return 1
    (( ${#ONLY_SECTIONS[@]} == 0 )) || [[ " ${ONLY_SECTIONS[*]} " == *" $1 "* ]]
}

# ---------------------------------------------------------------------------
# Section: preflight — sanity checks before anything else
# Verifies we're on Fedora, not root, sudo works, network is up.
# ---------------------------------------------------------------------------
section_preflight() {
    header "preflight"

    # Fedora only — the whole script assumes dnf/firewalld/SELinux defaults.
    [[ -r /etc/os-release ]] || die "no /etc/os-release; not a supported system"
    # shellcheck disable=SC1091
    source /etc/os-release
    [[ $ID == fedora ]] || die "this script is Fedora-only (detected: $ID)"
    info "Fedora $VERSION_ID, desktop: ${XDG_CURRENT_DESKTOP:-unknown}"

    # Must NOT run as root — we sudo per-command so file ownership stays sane.
    (( EUID != 0 )) || die "run as your normal user, not root (the script uses sudo internally)"

    # Confirm sudo works up front so we don't die mid-section.
    sudo -v || die "sudo is required"

    # Set up the logfile now that sudo is confirmed. Owned by the invoking
    # user so every later log append doesn't need sudo.
    sudo touch "$LOG_FILE"
    sudo chown "$(id -u):$(id -g)" "$LOG_FILE"
    LOG_READY=1
    log "===== fedora-harden.sh run $RUN_STAMP (dry_run=$DRY_RUN) ====="
    info "logging to $LOG_FILE"

    # Network check — updates/audit sections need package downloads.
    if curl -sI --max-time 10 https://mirrors.fedoraproject.org >/dev/null; then
        info "network: OK (mirrors.fedoraproject.org reachable)"
    else
        warn "network check failed — 'updates', 'audit', 'rkhunter', 'aide' sections may not work"
    fi
}

# ---------------------------------------------------------------------------
# Section: report — read-only status collection. Always runs, changes nothing.
# ---------------------------------------------------------------------------
section_report() {
    header "report (read-only)"

    # --- firewall ---
    info "firewall state: $(sudo firewall-cmd --state 2>&1 || true)"
    info "default zone:   $(sudo firewall-cmd --get-default-zone 2>/dev/null || echo '?')"
    info "active zones:"
    sudo firewall-cmd --get-active-zones 2>/dev/null | sed 's/^/    /' || true
    info "current zone rules:"
    sudo firewall-cmd --list-all 2>/dev/null | sed 's/^/    /' || true

    # --- SELinux: verify, never "fix". Weakening anything to quiet SELinux
    # warnings is exactly backwards; if it's not Enforcing, the user must fix
    # SELinux itself. ---
    SELINUX_STATUS=$(getenforce 2>/dev/null || echo unknown)
    if [[ $SELINUX_STATUS == Enforcing ]]; then
        info "SELinux: Enforcing (good)"
    else
        warn "SELinux is '$SELINUX_STATUS', NOT Enforcing!"
        warn "Fix it yourself: set SELINUX=enforcing in /etc/selinux/config and reboot."
        warn "This script will NOT weaken anything else to compensate."
        MANUAL_FOLLOWUPS+=("SELinux is $SELINUX_STATUS — set SELINUX=enforcing in /etc/selinux/config and reboot")
    fi

    # --- disk encryption: detect-and-report only (needs a reinstall to add) ---
    if lsblk -f | grep -q crypto_LUKS; then
        LUKS_STATUS="encrypted (crypto_LUKS present)"
        info "disk encryption: $LUKS_STATUS"
    else
        LUKS_STATUS="NOT encrypted (no crypto_LUKS volume found)"
        warn "disk encryption: $LUKS_STATUS"
        MANUAL_FOLLOWUPS+=("Disk is NOT LUKS-encrypted. On a laptop this is the single largest remaining gap (lost/stolen device = all data readable). Fixing it means a reinstall with 'Encrypt my data' checked.")
    fi

    # --- Secure Boot: detect-and-report only (needs firmware access to change) ---
    if command -v mokutil >/dev/null; then
        SB_STATUS=$(mokutil --sb-state 2>&1 | head -1 || true)
    else
        SB_STATUS="unknown (mokutil not installed)"
    fi
    info "Secure Boot: $SB_STATUS"
    if [[ $SB_STATUS != *enabled* ]]; then
        MANUAL_FOLLOWUPS+=("Secure Boot: $SB_STATUS — enable it in firmware setup (note: unsigned kmods like VirtualBox's need MOK signing afterwards)")
    fi

    # --- dev services enabled at boot ---
    local svc state
    for svc in httpd mariadb mysqld docker; do
        state=$(systemctl is-enabled "$svc" 2>/dev/null || true)
        info "service $svc: ${state:-not-installed}"
    done

    # --- automatic updates ---
    local timer_state apply_line
    timer_state=$(systemctl is-enabled dnf-automatic.timer 2>/dev/null || echo "not-installed/disabled")
    info "dnf-automatic.timer: $timer_state"
    if [[ -r /etc/dnf/automatic.conf ]]; then
        apply_line=$(grep -E '^\s*apply_updates' /etc/dnf/automatic.conf || echo "apply_updates not set")
        info "automatic.conf: $apply_line"
    else
        info "automatic.conf: not present (dnf-automatic not installed)"
    fi
}

# ---------------------------------------------------------------------------
# Section: updates — bring the system current and turn on unattended updates.
# Malicious downloads + known CVEs are the realistic threat; patching fast is
# the highest-value control on this list.
# ---------------------------------------------------------------------------
section_updates() {
    header "updates"

    run_cmd sudo dnf upgrade --refresh -y

    if rpm -q dnf-automatic >/dev/null 2>&1; then
        ok "dnf-automatic already installed"
    else
        run_cmd sudo dnf install -y dnf-automatic
        (( DRY_RUN )) || did "installed dnf-automatic"
    fi

    if [[ $(systemctl is-enabled dnf-automatic.timer 2>/dev/null || true) == enabled ]]; then
        ok "dnf-automatic.timer already enabled"
    else
        run_cmd sudo systemctl enable --now dnf-automatic.timer
        (( DRY_RUN )) || did "enabled dnf-automatic.timer"
    fi

    # Flip apply_updates to yes — download-only automatic updates protect nobody.
    local conf=/etc/dnf/automatic.conf
    if [[ -r $conf ]] && grep -qE '^\s*apply_updates\s*=\s*yes' "$conf"; then
        ok "apply_updates = yes already set in $conf"
    elif [[ -r $conf ]]; then
        backup_file "$conf"
        run_cmd sudo sed -i 's/^\s*apply_updates\s*=.*/apply_updates = yes/' "$conf"
        (( DRY_RUN )) || did "set apply_updates = yes in $conf"
    else
        # dnf-automatic not installed yet (pure dry-run) — just report intent.
        info "would set apply_updates = yes in $conf after install"
    fi
}

# ---------------------------------------------------------------------------
# Section: firewall — move from the permissive FedoraWorkstation zone to
# public. FedoraWorkstation opens all ports >1024, which is exactly wrong on
# untrusted Wi-Fi. public only allows ssh/mdns/dhcpv6-client.
# ---------------------------------------------------------------------------
section_firewall() {
    header "firewall"

    local current
    current=$(sudo firewall-cmd --get-default-zone 2>/dev/null || echo unknown)

    if [[ $current == public ]]; then
        ok "default zone is already 'public'"
    else
        info "current default zone: $current"
        # Default zone lives in firewalld.conf — back it up before changing.
        backup_file /etc/firewalld/firewalld.conf
        run_cmd sudo firewall-cmd --set-default-zone=public
        run_cmd sudo firewall-cmd --reload
        if (( ! DRY_RUN )); then
            did "default firewall zone: $current -> public"
            # Verify the active interface actually moved to the new zone.
            # NM connections with no explicit zone follow the default.
            info "active zones after change:"
            sudo firewall-cmd --get-active-zones | sed 's/^/    /'
            if sudo firewall-cmd --get-active-zones | grep -q '^public'; then
                info "verified: an interface is now in 'public'"
            else
                warn "no interface shows in 'public' — your NetworkManager connection may pin an explicit zone; check: nmcli -f connection.zone connection show <name>"
            fi
            BREAKAGE_NOTES+=("Firewall zone -> public: local discovery (KDE Connect, casting, GSConnect, mDNS file sharing) may break. Re-open e.g. KDE Connect with: sudo firewall-cmd --zone=public --add-port=1714-1764/udp --add-port=1714-1764/tcp --permanent && sudo firewall-cmd --reload. Full revert: sudo firewall-cmd --set-default-zone=$current")
        fi
    fi

    warn "local device discovery (KDE Connect, casting, mDNS sharing) may stop working in 'public'"
    info "to re-open a port range: sudo firewall-cmd --zone=public --add-port=1714-1764/udp --permanent && sudo firewall-cmd --reload"
    warn "Docker-published ports (-p 8080:80) BYPASS firewalld entirely — bind dev containers to loopback: -p 127.0.0.1:8080:80"
}

# ---------------------------------------------------------------------------
# Section: audit — run Lynis once for a baseline picture. We deliberately do
# NOT chase the score; the filtered suggestion list is the useful output.
# ---------------------------------------------------------------------------
section_audit() {
    header "audit (lynis)"

    if rpm -q lynis >/dev/null 2>&1; then
        ok "lynis already installed"
    else
        run_cmd sudo dnf install -y lynis
        (( DRY_RUN )) || did "installed lynis"
    fi

    local out=/var/log/fedora-harden-lynis-$RUN_STAMP.txt
    if (( DRY_RUN )); then
        run_cmd sudo lynis audit system   # prints as would-run
        info "full output would be saved to $out"
        return 0
    fi

    info "running lynis audit (takes a minute)..."
    # Lynis can exit nonzero on warnings; that's data, not a script failure.
    sudo lynis audit system --no-colors > >(sudo tee "$out" >/dev/null) 2>&1 || true
    did "lynis audit saved to $out"

    local index
    index=$(grep -oE 'Hardening index : [0-9]+' "$out" || true)
    info "${index:-hardening index not found in output}"

    # Filter out suggestions we intentionally skip (see header comment).
    # Adjust this list to taste.
    local skip_ids='BANN-|AUTH-9286|AUTH-9328|FILE-6310|LOGG-2154|ACCT-|STRG-1840|KRNL-6000|HRDN-7222'
    info "suggestions relevant to a single-user laptop:"
    grep -E '^\s*\*' "$out" | grep -vE "$skip_ids" | sed 's/^/    /' || info "    (none)"
    info "intentionally-skipped suggestion IDs: $skip_ids (see script header for why)"
}

# ---------------------------------------------------------------------------
# Section: rkhunter — rootkit scanner with a known-clean baseline. Catches
# "that download replaced a system binary" scenarios.
# ---------------------------------------------------------------------------
section_rkhunter() {
    header "rkhunter"

    if rpm -q rkhunter >/dev/null 2>&1; then
        ok "rkhunter already installed"
    else
        run_cmd sudo dnf install -y rkhunter
        (( DRY_RUN )) || did "installed rkhunter"
    fi

    # Fedora ships WEB_CMD=/bin/false which breaks 'rkhunter --update'.
    local conf=/etc/rkhunter.conf
    if [[ -r $conf ]] && grep -qE '^\s*WEB_CMD=.*/bin/false' "$conf"; then
        backup_file "$conf"
        run_cmd sudo sed -i 's|^\s*WEB_CMD=.*/bin/false.*|WEB_CMD=""|' "$conf"
        (( DRY_RUN )) || did "fixed WEB_CMD=/bin/false in $conf (was breaking --update)"
    elif [[ -r $conf ]]; then
        ok "WEB_CMD in $conf is not /bin/false"
    fi

    # --update exits 2 when data files were updated — not an error.
    run_cmd sudo rkhunter --update || true
    # --propupd records current file properties as the trusted baseline.
    run_cmd sudo rkhunter --propupd

    if (( DRY_RUN )); then
        run_cmd sudo rkhunter --check --sk
        return 0
    fi

    local out=/var/log/fedora-harden-rkhunter-$RUN_STAMP.txt
    info "running rkhunter check (takes a few minutes)..."
    # Nonzero exit just means warnings were found; we post-process below.
    sudo rkhunter --check --sk --rwo > >(sudo tee "$out" >/dev/null) 2>&1 || true
    did "rkhunter check saved to $out"

    # Post-process: on a dev laptop some warnings are structurally benign —
    # passwd/group changes come from package scriptlets adding system users,
    # and /dev oddities come from Docker/snap. Label them so real findings
    # stand out instead of drowning.
    local benign='passwd file|group file|/dev/shm|docker|snap|containerd'
    local expected unexpected
    expected=$(grep -iE "$benign" "$out" || true)
    unexpected=$(grep -ivE "$benign" "$out" | grep -iE 'warning' || true)

    if [[ -n $expected ]]; then
        info "expected/benign warnings (package users, Docker/snap /dev entries):"
        echo "$expected" | sed 's/^/    /'
    fi
    if [[ -n $unexpected ]]; then
        warn "UNEXPECTED warnings — review these:"
        echo "$unexpected" | sed 's/^/    /'
    else
        info "no unexpected warnings"
    fi
}

# ---------------------------------------------------------------------------
# Section: aide — file-integrity baseline. Tells you WHAT changed if you ever
# suspect compromise. Useless without the maintenance rhythm (see helpers).
# ---------------------------------------------------------------------------
section_aide() {
    header "aide"

    if rpm -q aide >/dev/null 2>&1; then
        ok "aide already installed"
    else
        run_cmd sudo dnf install -y aide
        (( DRY_RUN )) || did "installed aide"
    fi

    local db=/var/lib/aide/aide.db.gz new=/var/lib/aide/aide.db.new.gz
    if sudo test -f "$db" && (( ! FORCE )); then
        ok "AIDE database already exists ($db) — skipping init (use --force to redo)"
        return 0
    fi

    info "initializing AIDE database (takes several minutes)..."
    run_cmd sudo aide --init
    run_cmd sudo mv -f "$new" "$db"
    if (( ! DRY_RUN )); then
        did "AIDE database initialized at $db"
        info "verifying with aide --check (should be clean right after init)..."
        # A clean check exits 0; anything else right after init is worth seeing.
        sudo aide --check | tee -a "$LOG_FILE" || warn "aide --check reported differences immediately after init — review above"
    fi
}

# ---------------------------------------------------------------------------
# Section: services — stop dev daemons (httpd/mariadb/mysqld) from running at
# every boot. They're dev tools; start them when you need them. Each disable
# requires an explicit individual yes — even under --yes. Docker is never
# touched (explicitly in use).
# ---------------------------------------------------------------------------
section_services() {
    header "services"

    local svc
    for svc in httpd mariadb mysqld; do
        if [[ $(systemctl is-enabled "$svc" 2>/dev/null || true) != enabled ]]; then
            ok "$svc is not enabled at boot (or not installed)"
            continue
        fi
        if (( DRY_RUN )); then
            info "$svc is enabled at boot — with --apply you would be prompted to disable it"
            continue
        fi
        # ponytail: deliberate — no --yes shortcut here; disabling a service
        # without an explicit per-service answer is how you break someone's setup.
        if ask "$svc is enabled at boot. Disable it (start manually with 'systemctl start $svc' when needed)?"; then
            run_cmd sudo systemctl disable --now "$svc"
            did "disabled $svc at boot"
            BREAKAGE_NOTES+=("$svc no longer starts at boot. Start on demand: sudo systemctl start $svc. Revert: sudo systemctl enable --now $svc")
        else
            info "leaving $svc enabled (your choice)"
        fi
    done
    info "docker: intentionally untouched"
}

# ---------------------------------------------------------------------------
# Section: helpers — install sec-check / sec-rebaseline to /usr/local/bin.
# These make the AIDE/rkhunter baselines actually maintainable:
#   sec-check      before a system update  (is anything off right now?)
#   sec-rebaseline after a system update   (accept the new files as trusted)
# ---------------------------------------------------------------------------
section_helpers() {
    header "helpers"

    local tmpdir
    tmpdir=$(mktemp -d)
    # shellcheck disable=SC2064
    trap "rm -rf $tmpdir" RETURN

    cat > "$tmpdir/sec-check" <<'EOF'
#!/usr/bin/env bash
# sec-check — integrity check. Run BEFORE a system update, so you know any
# changes AIDE/rkhunter see afterwards came from the update, not something else.
set -uo pipefail
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'HELP'
sec-check: runs 'aide --check' and 'rkhunter --check --sk', prints a verdict.
Run it BEFORE a system update. If it's clean, update, then run sec-rebaseline.
If it's NOT clean, investigate before updating — an update would bury the trail.
HELP
    exit 0
fi
echo "== aide --check =="
sudo aide --check; aide_rc=$?
echo "== rkhunter --check --sk =="
sudo rkhunter --check --sk --rwo; rk_rc=$?
echo
if [[ $aide_rc -eq 0 && $rk_rc -eq 0 ]]; then
    echo "VERDICT: clean — safe to update, run sec-rebaseline afterwards."
else
    echo "VERDICT: differences/warnings found (aide=$aide_rc rkhunter=$rk_rc) — review before updating."
    exit 1
fi
EOF

    cat > "$tmpdir/sec-rebaseline" <<'EOF'
#!/usr/bin/env bash
# sec-rebaseline — accept the current system state as the new trusted
# baseline. Run AFTER a system update (and only when you trust current state).
set -euo pipefail
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'HELP'
sec-rebaseline: runs 'rkhunter --propupd' and 'aide --update', then promotes
the new AIDE database. Run it AFTER a system update so the updated files
become the trusted baseline instead of showing as warnings forever.
HELP
    exit 0
fi
echo "== rkhunter --propupd =="
sudo rkhunter --propupd
echo "== aide --update =="
# aide --update exits nonzero when it finds differences — that is the point
# of running it after an update, so don't treat it as failure.
sudo aide --update || true
sudo mv -f /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz
echo "Baselines updated. Next 'sec-check' should be clean."
EOF

    local name
    for name in sec-check sec-rebaseline; do
        local target=/usr/local/bin/$name
        if [[ -f $target ]] && cmp -s "$tmpdir/$name" "$target"; then
            ok "$target already installed and current"
        else
            run_cmd sudo install -m 0755 "$tmpdir/$name" "$target"
            (( DRY_RUN )) || did "installed $target"
        fi
    done
}

# ---------------------------------------------------------------------------
# Final summary
# ---------------------------------------------------------------------------
print_summary() {
    header "SUMMARY"
    (( DRY_RUN )) && warn "DRY RUN — nothing was changed. Re-run with --apply to make changes."

    if (( ${#CHANGED[@]} )); then
        echo "${C_BLD}Changed:${C_RST}"
        local c; for c in "${CHANGED[@]}"; do echo "  ${C_GRN}+${C_RST} $c"; log "summary changed: $c"; done
    else
        echo "${C_BLD}Changed:${C_RST} nothing"
    fi

    if (( ${#ALREADY_OK[@]} )); then
        echo "${C_BLD}Already correct:${C_RST}"
        local o; for o in "${ALREADY_OK[@]}"; do echo "  = $o"; done
    fi

    if (( ${#BACKUPS[@]} )); then
        echo "${C_BLD}Backups made:${C_RST}"
        local b; for b in "${BACKUPS[@]}"; do echo "  $b"; done
    else
        echo "${C_BLD}Backups made:${C_RST} none"
    fi

    echo "${C_BLD}Manual follow-ups (this script will not touch these):${C_RST}"
    if (( ${#MANUAL_FOLLOWUPS[@]} )); then
        local m; for m in "${MANUAL_FOLLOWUPS[@]}"; do echo "  ${C_YLW}!${C_RST} $m"; done
    else
        echo "  disk encryption: $LUKS_STATUS"
        echo "  Secure Boot:     $SB_STATUS"
        echo "  (both look fine)"
    fi

    if (( ${#BREAKAGE_NOTES[@]} )); then
        echo "${C_BLD}May now behave differently (and how to reverse):${C_RST}"
        local n; for n in "${BREAKAGE_NOTES[@]}"; do echo "  ${C_YLW}*${C_RST} $n"; done
    fi

    echo
    echo "${C_BLD}Maintenance rhythm:${C_RST}"
    echo "  before updating:  sec-check       (verify nothing is off first)"
    echo "  after updating:   sec-rebaseline  (accept the new files as trusted)"
    log "===== run complete ====="
}

# ---------------------------------------------------------------------------
# Argument parsing + main
# ---------------------------------------------------------------------------
usage() {
    cat <<EOF
fedora-harden.sh — hardening baseline for a personal Fedora Workstation laptop

  --dry-run        print what would be done, change nothing (DEFAULT)
  --apply          actually make changes (confirms before each section)
  --yes            with --apply: skip per-section confirmations
                   (per-service disable prompts still always ask)
  --only <name>    run only this section (repeatable)
  --skip <name>    skip this section (repeatable)
  --force          re-initialize the AIDE database even if one exists
  -h, --help       this help

Sections: ${ALL_SECTIONS[*]}
(preflight and report are read-only and always run)
EOF
}

valid_section() { [[ " ${ALL_SECTIONS[*]} " == *" $1 "* ]]; }

main() {
    while (( $# )); do
        case $1 in
            --dry-run) DRY_RUN=1 ;;
            --apply)   DRY_RUN=0 ;;
            --yes)     ASSUME_YES=1 ;;
            --force)   FORCE=1 ;;
            --only)    shift; valid_section "${1:-}" || die "unknown section: ${1:-<missing>}"; ONLY_SECTIONS+=("$1") ;;
            --skip)    shift; valid_section "${1:-}" || die "unknown section: ${1:-<missing>}"; SKIP_SECTIONS+=("$1") ;;
            -h|--help) usage; exit 0 ;;
            *)         usage; die "unknown argument: $1" ;;
        esac
        shift
    done

    (( DRY_RUN )) && warn "dry-run mode (default): showing what WOULD change. Use --apply to do it."

    # preflight and report always run: they're read-only and everything else
    # depends on the state they establish (sudo, logfile, status globals).
    section_preflight
    section_report

    local sec
    for sec in updates firewall audit rkhunter aide services helpers; do
        if ! section_wanted "$sec"; then
            info "skipping section: $sec"
            continue
        fi
        if confirm_section "$sec"; then
            "section_$sec"
        else
            info "section '$sec' declined — skipped"
        fi
    done

    print_summary
}

main "$@"
