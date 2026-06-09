# Rule 3 — Protected paths: never delete during cleanup

**The agent never `rm`s or `mv`s anything under the protected directories.** Default set: `core/ config/ scripts/ memory/` — override with the `GUARD_PROTECTED_DIRS` env var to match your tree.

**Why:** "Clean up the workspace" is a routine agent task, and an agent doing cleanup will eventually decide something important looks like clutter. Protected paths hold load-bearing code, single-source-of-truth configs, live automation, and durable knowledge. Logs and temp files are fair game; these are not.

**How to apply:** Archive, don't delete. Move candidates to an `Archive/` directory instead of removing them. `guard.sh` blocks `rm` and `mv` commands whose text touches any protected directory.

**Engineering note:** the naive version of this check false-positives constantly — a heredoc body containing `var mv :=` next to a `"scripts/foo"` string literal reads as `mv` touching `scripts/`. The guard strips heredoc bodies and requires rm/mv at a command-start boundary. See the comments in `guard.sh`; that fix is most of the file's complexity.
