#!/usr/bin/env bash
#
# guard.sh — a PreToolUse safety hook for Claude Code (FAIL-OPEN by design).
#
# Enforces a subset of the workspace rules (see rules/) before a Bash
# tool call runs:
#   Rule 1 — block `git worktree add` and branch creation (checkout -b / switch -c / branch <new>).
#   Rule 2 — block broad git adds (`git add -A` / `--all` / bare `.`) and `git commit -a/--all`.
#   Rule 3 — block an `rm`/`mv` COMMAND touching a protected path (configurable
#            via GUARD_PROTECTED_DIRS; default: core config scripts memory).
#            Heredoc bodies are skipped, and rm/mv must begin a command
#            (not a substring / var name like `var mv :=`).
#   Rule 4 — WARN (non-blocking) on `launchctl load` of a plist.
#
# FAIL-OPEN: any parse error, missing dependency, regex problem, or unmatched
# input exits 0 with no output -> the tool proceeds (status quo). This hook is
# shared across all concurrent agent sessions via .claude/settings.json, so a
# buggy guard must NEVER be able to freeze a parallel chat. Only an explicit,
# matched dangerous pattern emits a deny. It is a backstop for obvious mistakes
# (`rm -rf memory`, `git worktree add`, `git add -A`), not a bulletproof parser
# — the rules in rules/ remain the source of truth and the honor-system
# covers the rest. Regression tests live in ./test_guard.sh.
#
# Block mechanism (Claude Code PreToolUse):
#   exit 0 + {"hookSpecificOutput":{"hookEventName":"PreToolUse",
#             "permissionDecision":"deny","permissionDecisionReason":"..."}}
# Exit 0 + no output = no decision (allow). Any other failure = non-blocking (allow).

set -uo pipefail

allow() { exit 0; }          # fail-open / no-decision
trap 'allow' ERR             # any unexpected non-zero command -> allow

_json_str() {                # minimal JSON string escaping for the reason
  local s=${1//\\/\\\\}
  s=${s//\"/\\\"}
  printf '"%s"' "$s"
}

deny() {                     # $1 = reason shown to the agent
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' \
    "$(_json_str "$1")"
  exit 0
}

PYBIN=/usr/bin/python3
[ -x "$PYBIN" ] || PYBIN=python3

input="$(cat)" || allow
[ -n "$input" ] || allow

# Extract tool_name + TWO command views via python3.
# Tab-separated: tool \t cmd \t scan
#   cmd  — newlines->space (status quo). Scanned by Rules 1/2/4, unchanged.
#   scan — heredoc BODIES stripped, then newlines->";". Scanned by Rule 3 only.
#          Stripping heredocs stops a python/GDScript body (e.g. `var mv :=` next
#          to a "scripts/" path) from reading as an rm/mv shell command; the
#          newline->";" keeps a real `rm -rf scripts/` on its own script line
#          detectable at a command-start boundary. \x27=apostrophe \x22=quote
#          (hex, so this -c block carries no literal single quote that would
#          close it inside the surrounding bash single-quoted string).
parsed="$(printf '%s' "$input" | "$PYBIN" -c '
import sys, json, re
try:
    heredoc = re.compile(
        r"<<-?[ \t]*([\x27\x22]?)([A-Za-z_][A-Za-z0-9_]*)\1.*?^[ \t]*\2[ \t]*$",
        re.DOTALL | re.MULTILINE)
    d = json.load(sys.stdin)
    t = d.get("tool_name", "") or ""
    c = (d.get("tool_input", {}) or {}).get("command", "") or ""
    cmd = c.replace("\n", " ").replace("\t", " ").replace("\r", " ")
    scan = heredoc.sub(" ", c).replace("\n", ";").replace("\t", " ").replace("\r", " ")
    sys.stdout.write(t + "\t" + cmd + "\t" + scan)
except Exception:
    sys.stdout.write("\t\t")
' 2>/dev/null)" || allow

TOOL="${parsed%%$'\t'*}"
_rest="${parsed#*$'\t'}"
CMD="${_rest%%$'\t'*}"     # flattened command — Rules 1/2/4
SCAN="${_rest#*$'\t'}"     # heredoc-stripped, newline-separated — Rule 3

# rm/mv/git/launchctl only arrive via Bash. Anything else -> allow.
[ "$TOOL" = "Bash" ] || allow
[ -n "$CMD" ] || allow

# --- Rule 1: git worktrees & branch creation -------------------------------
re_worktree='(^|[^[:alnum:]_])git[[:space:]].*worktree[[:space:]]+add'
re_branchnew='(^|[^[:alnum:]_])git[[:space:]]+(checkout[[:space:]]+-[bB]|switch[[:space:]]+(-[cC]|--create)|branch[[:space:]]+[^-;&|[:space:]])'
if [[ "$CMD" =~ $re_worktree ]] || [[ "$CMD" =~ $re_branchnew ]]; then
  deny "Blocked by Rule 1: no git worktrees or branches — commit directly to main in the live working tree. A hidden worktree/branch is invisible to every tool that indexes the live tree (IDE agents, vaults, watchers). See rules/01-no-worktrees-or-branches.md."
fi

# --- Rule 2: broad git adds & commit -a (no massive commits) ---------------
# Anchored to a COMMAND-START boundary (start-of-string, or just after a shell
# separator ; & | ( ) — NOT mid-string. This is stricter than the Rule-1/3
# "anywhere" match on purpose: the literal tokens `git add -A` / `git add .` /
# `git commit -a` routinely appear inside commit *messages* (e.g. a hygiene
# commit that documents the rule), and those must NOT be blocked. So a match
# requires the git invocation to actually begin a command.
# Trade-off (fail-open): an env-prefixed form like `FOO=bar git add .` is NOT a
# command-start and will be missed — rare, and the honor-system/rules cover it.
re_add_broad='(^[[:space:]]*|[;&|(][[:space:]]*)git[[:space:]]+add[[:space:]]+(-A|--all|\./?)([[:space:];&|)]|$)'
re_commit_all='(^[[:space:]]*|[;&|(][[:space:]]*)git[[:space:]]+commit[[:space:]]+(--all|-[[:alpha:]]*a[[:alpha:]]*)([[:space:];&|)=]|$)'
if [[ "$CMD" =~ $re_add_broad ]]; then
  deny "Blocked by Rule 2: no broad 'git add' (-A / --all / bare '.'). Stage specific named files instead (git add path/to/file) — a shared tree often carries dirty files from parallel sessions, and a blanket add bloats .git and sends indexers into thrash. If you truly need it, run it yourself outside the agent. See rules/02-no-broad-git-adds.md."
fi
if [[ "$CMD" =~ $re_commit_all ]]; then
  deny "Blocked by Rule 2: no 'git commit -a/--all' (it auto-stages every modified tracked file, which is the same massive-commit hazard). Stage specific named files, then 'git commit -m'. See rules/02-no-broad-git-adds.md."
fi

# --- Rule 3: rm/mv of protected paths --------------------------------------
# Match only an actual rm/mv COMMAND, anchored to a command-start boundary
# (start-of-string, or just after a ; & | ( separator — and since newlines became
# ";" in SCAN, a command on its own script line counts too). A bare 2-letter
# token mid-command — a GDScript `var mv :=`, a substring, a variable name — must
# NOT match; that was the false positive. Heredoc bodies are already stripped from
# SCAN upstream, so code fed to python3/cat never reaches this scan. Mirrors
# Rule 2's command-start anchoring on purpose.
# Trade-off (fail-open): rm/mv not at a command start — `find ... -exec rm`,
# `xargs rm`, or rm/mv inside a quoted multi-line -c/-m arg — is missed. Rare; the
# honor-system + rules/ cover it. A real `rm -rf scripts/` / `mv x scripts/`
# (command-start) still blocks, including on a later line or after a heredoc.
PROTECTED_DIRS="${GUARD_PROTECTED_DIRS:-core config scripts memory}"
_alt="$(printf '%s' "$PROTECTED_DIRS" | tr -s ' ' '|')" || allow
re_rmmv='(^[[:space:]]*|[;&|(][[:space:]]*)(rm|mv)[[:space:]]'
re_protected='(^|[/[:space:]"'\''.])('"$_alt"')([/[:space:]"'\'']|$)'
if [[ "$SCAN" =~ $re_rmmv ]] && [[ "$SCAN" =~ $re_protected ]]; then
  deny "Blocked by Rule 3: refusing rm/mv touching a protected path ($PROTECTED_DIRS). Archive instead of deleting; if this is a false positive, run it yourself outside the agent. See rules/03-protected-paths.md."
fi

# --- Rule 4: launchctl load (WARN only, non-blocking) ----------------------
re_launchload='(^|[;&|[:space:]])launchctl[[:space:]]+load'
if [[ "$CMD" =~ $re_launchload ]]; then
  printf 'Rule 4: launchctl load detected. Background processes (KeepAlive/StartInterval) need explicit human approval first. Proceeding (warn-only) — confirm this was approved. See rules/04-no-background-daemons.md.\n' 1>&2
  allow
fi

allow
