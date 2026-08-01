#!/usr/bin/env bash
#
# BuildKit-style progress output for the scripts in this repo — the same shape
# `docker build --progress=plain` prints:
#
#   #3 [3/9] Installing Vim
#   #3 0.412 Installing:  vim-enhanced  x86_64  9.1.1775-1.fc44
#   #3 DONE 8.1s
#
# Source it, then:
#
#   step "Installing Vim"      open a step (closes the previous one as DONE)
#   run  sudo dnf install vim  run a command, prefixing its output with #N <elapsed>
#   say  "text"                extra line under the current step
#   warn "text"                #N WARN: text
#   cached "already there"     close the current step as CACHED (no time)
#
# The last step and the trailing "[+] Building 45.2s (9/9) FINISHED" (or the
# ERROR block) are printed by the EXIT trap — nothing to call at the end.
#
# Step total is counted from `^step ` lines in the running script; set BK_TOTAL
# yourself if the steps aren't literal top-level calls (see fedoraHarden.sh).

_bk_n=0
_bk_total=0
_bk_name=""
_bk_step_us=0
_bk_run_us=0
_bk_autototal=$(grep -cE '^[[:space:]]*step ' "$0" 2>/dev/null) || _bk_autototal=0

# Microseconds since the epoch, no forks (bash 5's EPOCHREALTIME, locale-safe).
_bk_us() { local e=${EPOCHREALTIME/,/.}; echo $(( ${e%.*} * 1000000 + 10#${e#*.} )); }

_bk_dt()  { local us=$(( $(_bk_us) - $1 )); printf '%d.%03d' $((us / 1000000)) $(( us % 1000000 / 1000 )); }
_bk_dts() { local us=$(( $(_bk_us) - $1 )); printf '%d.%d'   $((us / 1000000)) $(( us % 1000000 / 100000 )); }

_bk_run_us=$(_bk_us)
_bk_step_us=$_bk_run_us

# Close the open step. $1 = DONE | CACHED | "ERROR: exit code 1"
_bk_close() {
  [[ -n $_bk_name ]] || return 0
  case $1 in
    CACHED) printf '#%d CACHED\n' "$_bk_n" ;;
    DONE)   printf '#%d DONE %ss\n' "$_bk_n" "$(_bk_dts "$_bk_step_us")" ;;
    *)      printf '#%d %s\n' "$_bk_n" "$1" ;;
  esac
  _bk_name=""
}

step() {
  _bk_close DONE
  _bk_n=$(( _bk_n + 1 ))
  _bk_name="$1"
  _bk_step_us=$(_bk_us)

  _bk_total=${BK_TOTAL:-$_bk_autototal}
  (( _bk_total < _bk_n )) && _bk_total=$_bk_n
  if (( _bk_total )); then
    printf '#%d [%d/%d] %s\n' "$_bk_n" "$_bk_n" "$_bk_total" "$1"
  else
    printf '#%d %s\n' "$_bk_n" "$1"
  fi
}

# Before the first step there is no #N to hang a line off — print it bare.
say()  { (( _bk_n )) && printf '#%d %s %s\n' "$_bk_n" "$(_bk_dt "$_bk_step_us")" "$*" || printf '%s\n' "$*"; }
warn() { say "WARN: $*" >&2; }

cached() { [[ $# -gt 0 ]] && say "$*"; _bk_close CACHED; }

run() {
  # sudo's password prompt has no trailing newline, so inside the pipe below it
  # would sit in the line buffer, invisible. Refresh the timestamp out here.
  [[ ${1:-} == sudo ]] && sudo -v

  local n=$_bk_n start=$_bk_step_us
  "$@" 2>&1 | while IFS= read -r line || [[ -n $line ]]; do
    printf '#%d %s %s\n' "$n" "$(_bk_dt "$start")" "$line"
  done
  return "${PIPESTATUS[0]}"
}

_bk_finish() {
  local rc=$? name=$_bk_name n=$_bk_n total=$_bk_total
  trap - EXIT

  if (( rc == 0 )); then
    _bk_close DONE
    (( n )) && printf '[+] Building %ss (%d/%d) FINISHED\n' "$(_bk_dts "$_bk_run_us")" "$n" "$n"
  elif (( n )); then
    _bk_close "ERROR: exit code $rc"
    printf -- '------\n > [%d/%d] %s:\n------\n' "$n" "$total" "$name"
    printf 'ERROR: failed to solve: %s: exit code %d\n' "$name" "$rc"
  fi
  exit "$rc"
}
trap _bk_finish EXIT
