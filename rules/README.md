# The rules

Nine rules for running AI coding agents on a workspace you care about. Seven of them exist because skipping it cost something real: a broken IDE, a bloated repo, a fabricated "done." The last two exist because the others all assume the agent is merely careless, and something has to assume it is being lied to.

- **Canonical copy:** your agent's always-loaded instructions file (CLAUDE.md or equivalent) should carry a terse copy. These files are the long version with the *why*.
- **Enforced subset:** `../guard.sh` (a PreToolUse hook) enforces rules 1-3, 8 and 9 before a tool call runs, and warns on rule 4. Rules 5-7 are honor-system.
- **Two failure philosophies.** Rules 1-7 fail OPEN: they catch clumsiness, and a guard that blocks legitimate work gets deleted within a week. Rules 8 and 9 face an adversary, so their decisions fail CLOSED. Keep the two families apart when editing the hook.
- If the two copies ever drift, the always-loaded copy wins.

| # | Rule | Enforcement |
|---|---|---|
| 1 | No git worktrees or branches | guard.sh blocks |
| 2 | No broad git adds or commit -a | guard.sh blocks |
| 3 | Protected paths: never rm/mv | guard.sh blocks |
| 4 | No background daemons without approval | guard.sh warns |
| 5 | Read logs before guessing | honor system |
| 6 | Config changes are reversible or they don't happen | honor system |
| 7 | Verify agent claims on disk | honor system |
| 8 | Outbound egress goes through an allowlist | guard.sh blocks / asks (**fails closed**) |
