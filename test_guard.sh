#!/usr/bin/env bash
#
# test_guard.sh — regression matrix for guard.sh (the PreToolUse safety hook).
#
# Usage:
#   ./test_guard.sh                 # test the live ./guard.sh
#   ./test_guard.sh guard.sh.candidate   # test a candidate before promoting
#
# Each case feeds a synthetic PreToolUse JSON payload to the guard and checks
# whether it DENIES (stdout contains "permissionDecision":"deny") or ALLOWS.
# Exits non-zero if any case fails. Keep this green before wiring any guard edit.

set -uo pipefail
cd "$(dirname "$0")"
GUARD="${1:-./guard.sh}"
PYBIN=/usr/bin/python3; [ -x "$PYBIN" ] || PYBIN=python3

pass=0; fail=0
check() {  # $1=expected(BLOCK|ALLOW)  $2=command  [$3=tool, default Bash]
  local expected="$1" cmd="$2" tool="${3:-Bash}" input out verdict
  input="$("$PYBIN" -c 'import json,sys; print(json.dumps({"tool_name":sys.argv[1],"tool_input":{"command":sys.argv[2]}}))' "$tool" "$cmd")"
  out="$(printf '%s' "$input" | bash "$GUARD" 2>/dev/null)"
  if printf '%s' "$out" | grep -q '"permissionDecision":"deny"'; then verdict=BLOCK; else verdict=ALLOW; fi
  if [ "$verdict" = "$expected" ]; then
    pass=$((pass+1))
  else
    fail=$((fail+1)); printf 'FAIL: expected %-5s got %-5s :: %s\n' "$expected" "$verdict" "$cmd"
  fi
}

echo "Testing guard: $GUARD"

# ===== Rule 2: broad git add — must BLOCK =====
check BLOCK 'git add -A'
check BLOCK 'git add --all'
check BLOCK 'git add .'
check BLOCK 'git add ./'
check BLOCK 'git add -A .'
check BLOCK '  git add .'
check BLOCK 'cd Projects && git add .'
check BLOCK 'git add . && git commit -m "wip"'
check BLOCK 'echo hi; git add -A'
check BLOCK '(git add .)'

# ===== Rule 2: git commit -a / --all — must BLOCK =====
check BLOCK 'git commit -a'
check BLOCK 'git commit -am "msg"'
check BLOCK 'git commit -a -m "msg"'
check BLOCK 'git commit --all -m "msg"'
check BLOCK 'git commit -sam "msg"'
check BLOCK 'git add x.py && git commit -am "msg"'

# ===== Rule 2: named adds / safe commits — must ALLOW =====
check ALLOW 'git add scripts/foo.py'
check ALLOW 'git add ./web/x.html a/b.py'
check ALLOW 'git add path/to/dir'
check ALLOW 'git add -p'
check ALLOW 'git add -u'
check ALLOW 'git add .gitignore'
check ALLOW 'git commit -m "msg"'
check ALLOW 'git commit -m "never use git add -A or git add . here"'
check ALLOW 'git commit -m "document git commit -a footgun"'
check ALLOW 'git commit --amend -m "fix"'
check ALLOW 'git commit --amend --no-edit'
check ALLOW 'git commit -C HEAD'
check ALLOW 'echo "remember: git add -A is banned"'

# ===== Rule 1: worktrees & branch creation — regression =====
check BLOCK 'git worktree add ../wt'
check BLOCK 'git checkout -b feature'
check BLOCK 'git switch -c feature'
check BLOCK 'git switch --create feature'
check BLOCK 'git branch newfeature'
check ALLOW 'git checkout main'
check ALLOW 'git switch main'
check ALLOW 'git branch'
check ALLOW 'git branch -d oldbranch'

# ===== Rule 3: rm/mv of protected paths — regression =====
check BLOCK 'rm -rf memory'
check BLOCK 'mv scripts/old.py Archive/'
check BLOCK 'rm core/worker/x.py'
check ALLOW 'cat memory/glossary.md'
check ALLOW 'python3 scripts/audit.py'
check ALLOW 'ls scripts/'
check ALLOW 'rm /tmp/scratch.txt'

# ===== Rule 3: heredoc bodies & non-command rm/mv must NOT false-positive =====
# Real bug: a python3 heredoc whose BODY has a GDScript `var mv :=`
# next to a "scripts/..." path string was wrongly blocked — the bare `mv` token
# matched rm/mv and `scripts/` matched a protected path, though no rm/mv ran.
check ALLOW $'python3 - <<\'PY\'\nvar mv := CameraViewScript.new()\nvar path = "scripts/core/foo.gd"\nprint(path)\nPY'
# Heredoc body mentioning rm/mv as a substring of a longer name + a protected path.
check ALLOW $'python3 - <<\'PY\'\ndef _refresh_inventory():\n    return "scripts/store/game_state.gd"\nPY'
check ALLOW $'cat <<\'EOF\'\nperform a move involving scripts/ and memory/\nEOF'
# Command-start anchoring (no heredoc): rm/mv NOT beginning a command -> ALLOW.
check ALLOW 'echo "var mv := node under scripts/"'
check ALLOW 'echo "perform scripts cleanup in memory"'
# Real rm/mv still BLOCKS: at start, after a ; separator, on a later line, and
# both before and after a heredoc (stripping must not swallow trailing commands).
check BLOCK 'rm -rf scripts/x'
check BLOCK 'mv a scripts/b'
check BLOCK 'echo hi; mv core/a core/b'
check BLOCK $'cd /tmp\nrm -rf scripts/x'
check BLOCK $'rm -rf scripts/x; cat <<\'EOF\'\nbody\nEOF'
check BLOCK $'cat <<\'EOF\'\nbody\nEOF\nrm -rf scripts/x'

# ===== Rule 3: configurable protected dirs =====
check ALLOW 'rm -rf assets/x'
out_custom="$("$PYBIN" -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":"rm -rf assets/x"}}))' | GUARD_PROTECTED_DIRS="assets data" bash "$GUARD" 2>/dev/null)"
if printf '%s' "$out_custom" | grep -q '"permissionDecision":"deny"'; then pass=$((pass+1)); else fail=$((fail+1)); echo 'FAIL: expected BLOCK with GUARD_PROTECTED_DIRS="assets data" :: rm -rf assets/x'; fi

# ===== Rule 4: launchctl load — warn only, must ALLOW (no deny) =====
check ALLOW 'launchctl load -w ~/Library/LaunchAgents/com.example.daemon.plist'

# ===== Non-Bash tool — must ALLOW =====
check ALLOW 'git add -A' Read
check ALLOW 'rm -rf memory' Write

echo "-----------------------------------"
echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
