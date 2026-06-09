# The rules

Seven rules for running AI coding agents on a workspace you care about. Each one exists because skipping it cost something real: a broken IDE, a bloated repo, a fabricated "done."

- **Canonical copy:** your agent's always-loaded instructions file (CLAUDE.md or equivalent) should carry a terse copy. These files are the long version with the *why*.
- **Enforced subset:** `../guard.sh` (a PreToolUse hook) enforces rules 1-3 before a tool call runs, and warns on rule 4. Rules 5-7 are honor-system.
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
