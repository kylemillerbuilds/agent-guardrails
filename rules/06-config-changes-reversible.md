# Rule 6 — Config changes are reversible or they don't happen

**Every config change must be reversible, and the agent documents what changed so it can be undone.**

**Why:** Irreversible or undocumented config changes leave the system in a state no one can recover, and the agent that made them won't be in context when it matters.

**How to apply:** Honor system. Snapshot before editing shared config (a dated `.bak` next to the file is fine). Note the before and after. Prefer additive changes over destructive ones. The guard hook itself follows this rule: it's wired into settings via a documented, single-line hook entry, and it's fail-open, so removing it (or it breaking) restores stock behavior exactly.
