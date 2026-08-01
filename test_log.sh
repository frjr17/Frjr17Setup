#!/usr/bin/env bash
# Self-check for log.sh. Run it: ./test_log.sh
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

fixture=$(mktemp) out=$(mktemp)
trap 'rm -f "$fixture" "$out"' EXIT

assert() { # assert <description> <extended regex> [file]
  if grep -qE "$2" "${3:-$out}"; then
    echo "ok   $1"
  else
    echo "FAIL $1 -- no line matching /$2/ in:"; sed 's/^/     /' "${3:-$out}"; exit 1
  fi
}

# --- happy path ------------------------------------------------------------
cat > "$fixture" <<EOF
set -euo pipefail
source $PWD/log.sh
step "first"
run bash -c 'echo hello; sleep 0.2; echo world'
say "a note"
step "second"
cached "nothing to do"
step "third"
EOF
bash "$fixture" > "$out" 2>&1 || { echo "FAIL fixture exited $?"; cat "$out"; exit 1; }

assert "step header carries [n/total]"  '^#1 \[1/3\] first$'
assert "command output is prefixed"     '^#1 [0-9]+\.[0-9]{3} hello$'
assert "elapsed advances within a step" '^#1 0\.2[0-9]{2} world$'
assert "say hangs off the open step"    '^#1 [0-9]+\.[0-9]{3} a note$'
assert "step closes as DONE with time"  '^#1 DONE 0\.2s$'
assert "cached closes without a time"   '^#2 CACHED$'
assert "the last step closes on exit"   '^#3 DONE 0\.0s$'
assert "run ends with a total"          '^\[\+\] Building 0\.2s \(3/3\) FINISHED$'

# --- failure path ----------------------------------------------------------
cat > "$fixture" <<EOF
set -euo pipefail
source $PWD/log.sh
step "one"
step "two"
run bash -c 'echo "boom" >&2; exit 3'
step "never reached"
EOF
bash "$fixture" > "$out" 2>&1
rc=$?

[[ $rc -eq 3 ]] && echo "ok   exit code propagates" || { echo "FAIL exit code was $rc, want 3"; exit 1; }
assert "stderr is captured too"     '^#2 [0-9]+\.[0-9]{3} boom$'
assert "the failing step is marked" '^#2 ERROR: exit code 3$'
assert "the failing step is named"  '^ > \[2/3\] two:$'
assert "no FINISHED after an error" '^ERROR: failed to solve: two: exit code 3$'
grep -q 'FINISHED' "$out" && { echo "FAIL printed FINISHED for a failed run"; exit 1; }
grep -q 'never reached' "$out" && { echo "FAIL kept going after a failed step"; exit 1; }

echo "all good"
