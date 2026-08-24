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
#   Rule 8 — outbound egress allowlist for curl/wget. THE ODD ONE OUT: its
#            decision fails CLOSED. Configurable via GUARD_EGRESS_ALLOW.
#
# TWO FAMILIES, OPPOSITE FAILURE PHILOSOPHIES. Rules 1-4 guard against the agent
# being clumsy, and clumsiness is not adversarial: a guard that blocks a
# legitimate command is worse than the mistake it prevents, so they fail open.
# Rule 8 guards against the agent being LIED TO. Everything an agent reads
# through a tool - a web page, an email body, a file another agent wrote, text
# inside an image - is authored by someone else and can carry instructions aimed
# at the agent. The payoff for a landed injection is almost always exfiltration,
# and outbound network is the chokepoint. So Rule 8's decision fails closed: an
# unlisted destination never passes silently. Do not merge the two families when
# editing this file; the asymmetry is the design.
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

ask() {                      # $1 = reason - surfaces a permission prompt to the human
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":%s}}\n' \
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

# --- Rule 8: outbound network egress (the fail-CLOSED rule) ----------------
# See the header for why this one is different. Three outcomes:
#   deny  - a download piped into an interpreter (remote code execution), ALWAYS,
#           even for an allowlisted host; and an upload flag aimed at an
#           unlisted host, which is the exfiltration shape itself.
#   ask   - any other curl/wget touching an unlisted host, and the case where no
#           literal URL is readable. The human sees the host and decides.
#   allow - every literal host in the command is allowlisted.
#
# Host matching is EXACT, or a leading-dot suffix for wildcard entries. This is
# why the check PARSES hosts instead of stripping known-good substrings: a URL
# whose host merely BEGINS with an allowlisted name (allowed-host DOT attacker
# DOT com) must not satisfy that entry, and a substring strip would let it
# straight through. If you re-implement this, that is the bug you will write.
#
# HONEST LIMITS - be aware of them rather than trusting the rule past them:
#   1. Only Bash. Write/Edit/WebFetch and MCP tools never reach this hook.
#   2. Only URLs literally present in the command. A first-party script makes its
#      own calls that this never sees.
#   3. Only exfiltration by network. Nothing about an injection that corrupts
#      data in place or talks the agent into reporting something false.
#   4. NO HEREDOC STRIPPING, unlike Rule 3. A heredoc body that merely discusses
#      an upload flag next to an unlisted URL - documentation, a test fixture,
#      this very comment - reads as the real thing and triggers an ask or a deny.
#      Found by writing the patch that added this rule, which the rule then
#      blocked. Fail-closed means accepting false positives; that is the trade
#      the other four rules deliberately refuse to make.
#
# The default list is deliberately minimal: package registries, GitHub, and the
# model APIs. Set GUARD_EGRESS_ALLOW to your own space-separated list; add a host
# only after asking what reaches it and who controls what it serves.
EGRESS_ALLOW="${GUARD_EGRESS_ALLOW:-localhost 127.0.0.1 ::1 api.github.com github.com raw.githubusercontent.com objects.githubusercontent.com pypi.org files.pythonhosted.org registry.npmjs.org api.anthropic.com api.openai.com}"

re_netcmd='(^[[:space:]]*|[;&|(`$][[:space:]]*)(curl|wget)([[:space:]]|$)'
re_pipe_shell='(curl|wget)[^;&]*\|[[:space:]]*(sudo[[:space:]]+)?(bash|sh|zsh|ksh|fish|python3?|perl|ruby|node|osascript)([[:space:]]|$|\|)'
re_upload='([[:space:]](-d|-F|-T)[[:space:]=]|--data(-binary|-raw|-urlencode)?[[:space:]=]|--form[[:space:]=]|--upload-file[[:space:]=]|--post-data[[:space:]=]|--post-file[[:space:]=]|-X[[:space:]]+(POST|PUT|PATCH))'

if [[ "$CMD" =~ $re_netcmd ]]; then
  # THE TRAP FLIPS FOR THIS SECTION. The file-wide `trap allow ERR` would swallow
  # an error raised inside this evaluation into a silent allow, which would make
  # the fail-closed claim false. For the length of this block, an unexpected
  # error is a DENY. Restored to fail-open immediately after, because every other
  # rule here belongs to the fail-open family and must stay there.
  _egress_error_deny() {
    deny "Blocked by Rule 8: the egress check itself errored, so the allowlist was never applied. Rule 8's decision fails CLOSED by design - an unverifiable network call is refused rather than waved through. Re-run it yourself if you know the destination."
  }
  trap '_egress_error_deny' ERR

  # Remote code execution is denied regardless of host: an allowlisted domain can
  # still serve an attacker-controlled file (a gist, a PR branch, a bucket).
  if [[ "$CMD" =~ $re_pipe_shell ]]; then
    deny "Blocked by Rule 8: refusing to pipe a download straight into an interpreter. This is the classic remote-code-execution shape and it is denied even for allowlisted hosts, because a trusted domain can still serve an attacker-controlled file. Download to a file, read it, then run it deliberately. See rules/08-outbound-egress-allowlist.md."
  fi

  # Walk every literal http(s) host in the command; collect the unlisted ones.
  _rest_urls="$CMD"
  _unlisted=""
  _sawurl=0
  while [[ "$_rest_urls" =~ https?://([A-Za-z0-9._:-]+) ]]; do
    _sawurl=1
    _host="${BASH_REMATCH[1]%%:*}"
    _match=0
    for _d in $EGRESS_ALLOW; do
      case "$_d" in
        .*) if [[ "$_host" == *"$_d" ]]; then _match=1; fi ;;
        *)  if [[ "$_host" == "$_d" ]]; then _match=1; fi ;;
      esac
    done
    if [ "$_match" = 0 ]; then
      _unlisted="${_unlisted:+$_unlisted, }$_host"
    fi
    _rest_urls="${_rest_urls#*"${BASH_REMATCH[0]}"}"
  done

  if [ -n "$_unlisted" ]; then
    # An upload flag pointed at an unlisted host IS the exfiltration shape.
    if [[ "$CMD" =~ $re_upload ]]; then
      deny "Blocked by Rule 8: refusing to SEND data to a non-allowlisted host ($_unlisted). An upload flag (-d/--data/-F/-T/--upload-file/-X POST) aimed at an unknown domain is the exfiltration shape a prompt injection would use. If this is legitimate, run it yourself, or add the host to GUARD_EGRESS_ALLOW deliberately. See rules/08-outbound-egress-allowlist.md."
    fi
    ask "Rule 8 (egress): this reaches a host that is not on the allowlist - $_unlisted. Approve only if you recognise it and expected this call. Content the agent read (a web page, an email, a file another agent wrote) can name a destination; the allowlist is what keeps that from being acted on silently. See rules/08-outbound-egress-allowlist.md."
  fi

  if [ "$_sawurl" = 0 ]; then
    ask "Rule 8 (egress): a curl/wget with no readable literal URL - the destination is built at runtime (a variable, a shell substitution), so the allowlist cannot be checked statically. Approve only if you know where this points. See rules/08-outbound-egress-allowlist.md."
  fi
  trap 'allow' ERR   # back to the fail-open family
fi

allow
