[![CI](https://github.com/kylemillerbuilds/agent-guardrails/actions/workflows/ci.yml/badge.svg)](https://github.com/kylemillerbuilds/agent-guardrails/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

# agent-guardrails

Safety rails for running AI coding agents on a workspace you actually care about. A fail-open PreToolUse hook for Claude Code, seven written rules, and a regression test matrix. Every piece exists because skipping it cost me something real.

<p align="center">
  <img src="diagram.svg" alt="How agent-guardrails judges a command before it runs" width="840">
</p>

## The story

I run multiple AI agents against production code: a CLI agent, an IDE agent, and a paired notes vault, all sharing one working tree. One day an agent decided to use git worktrees. The IDE tried to index thousands of duplicated files and died for an entire day.

That was the first rule. The rest accumulated the same way. An agent ran `git add -A` on a tree carrying hundreds of dirty files from parallel sessions. An agent-created daemon got stuck in a restart loop, burning tokens silently. An agent confidently reported finishing work that did not exist on disk.

You can tell an agent the rules in its instructions file, and you should. But instructions are advisory and context windows are long. So the rules that matter most are also enforced in code, before the tool call runs.

## What's in the box

```
guard.sh          the PreToolUse hook (bash, no dependencies beyond python3)
test_guard.sh     regression matrix; run it green before changing the guard
rules/            the seven rules, with the why behind each one
```

The guard blocks three classes of mistake and warns on a fourth:

1. **Git worktrees and branch creation.** Hidden work is invisible to every tool indexing the live tree.
2. **Broad git adds** (`git add -A` / `.` / `--all`, `git commit -a`). Blanket staging on a shared tree commits things nobody intended.
3. **`rm`/`mv` touching protected directories.** Configurable via `GUARD_PROTECTED_DIRS`. An agent doing "cleanup" will eventually decide something important is clutter.
4. **`launchctl load`** gets a warning, not a block. Background daemons need a human yes.

## Design decisions that matter

**Fail-open, always.** Any parse error, missing dependency, or unmatched input allows the command. The hook is shared across concurrent sessions, so a buggy guard must never be able to freeze a parallel chat. A guard that can break your workflow gets deleted within a week. A guard that only ever blocks explicit, matched dangerous patterns gets to stay forever.

**Command-start anchoring.** The naive regex blocks `git commit -m "stop using git add -A"`, which is a commit message *about* the rule. The guard requires the dangerous invocation to actually begin a command (start of string or right after `;` `&` `|` `(`). Trade-off: an env-prefixed `FOO=bar git add .` slips through. Fail-open means accepting rare misses to guarantee zero false positives.

**Heredoc stripping.** The expensive false positive: a Python heredoc containing `var mv := Camera.new()` next to the string `"scripts/core/foo.gd"` reads to a naive scanner as `mv` touching a protected `scripts/` directory. The guard strips heredoc bodies before scanning for rm/mv, while converting newlines to `;` so a real `rm -rf scripts/x` on its own script line still blocks. That fix is most of the complexity in the file, and it's tested in both directions.

**Tests before wiring.** `test_guard.sh` feeds synthetic hook payloads to the guard and asserts BLOCK or ALLOW for 50+ cases, including every false positive that ever happened. The rule: the matrix runs green before any guard edit ships.

## Install

1. Drop `guard.sh` somewhere stable (e.g. `.claude/hooks/guard.sh`) and `chmod +x` it.
2. Wire it as a PreToolUse hook in `.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [{ "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/guard.sh" }]
      }
    ]
  }
}
```

3. Set your protected directories if the defaults don't fit:

```bash
export GUARD_PROTECTED_DIRS="src config data docs"
```

4. Run the tests:

```bash
./test_guard.sh
```

## The rules

The hook enforces rules 1-3 and warns on 4. Rules 5-7 are honor-system, and rule 7 is the one I'd keep if I could only keep one: **verify agent claims on disk.** Agents fabricate completions. Check that the files exist, in the right place, containing what was claimed, before anyone builds on top of "done."

Full write-ups with the incident behind each rule: [rules/](rules/).

## Who made this

Kyle Miller. I build AI systems that run real businesses: e-commerce automation, internal tools, content engines. This repo is a piece of my actual operating setup, extracted and cleaned up. The business logic stays home.

**Hire me:** [themisfoundry.com](https://themisfoundry.com)

## License

MIT
