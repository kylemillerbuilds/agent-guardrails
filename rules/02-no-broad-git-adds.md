# Rule 2 — No broad git adds, no massive commits

**Never `git add -A` / `git add .` / `git add --all`, and never `git commit -a` / `-am` / `--all`.** Stage specific named files in coherent sets.

**Why:** A workspace running multiple agent sessions carries dirty files from parallel work at all times. A blanket add stages someone else's half-finished work, commits binaries that bloat `.git`, and sends any indexing tool into thrash. Big blob churn in `.git` is part of what broke my IDE.

**How to apply:** Named adds only (`git add path/to/file`), then `git commit -m`. Keep binaries and large assets out of history.

**Hook-enforced**, with one subtlety worth stealing: the guard's match is anchored to a command-start boundary, so a commit *message* that merely mentions the banned tokens (e.g. `git commit -m "stop using git add -A"`) is NOT blocked. That false positive will hit you within a week if you anchor naively.
