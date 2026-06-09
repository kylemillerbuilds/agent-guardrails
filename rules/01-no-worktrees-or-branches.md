# Rule 1 — No git worktrees or branches

**The agent MUST NOT use `git worktree add` or create git branches.** All edits commit directly to main in the live working tree.

**Why:** If anything else indexes your working tree — an IDE agent, a notes vault, a file watcher, another AI session — work done inside a hidden worktree or branch is invisible to it. The knowledge graph splits. In my case this broke the paired IDE for a full day: it tried to index thousands of duplicated worktree files and choked.

**This rule is situational.** If you run a single agent with no paired tooling, branches are fine and you should delete this rule. It earns its place the moment two systems share one tree.

**How to apply:** Operate exclusively on the main branch in the root directory. `guard.sh` blocks `git worktree add` and branch-creating `git checkout -b` / `git switch -c` / `git branch <new>`.
