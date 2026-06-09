# Rule 5 — Read logs before guessing

**When tooling breaks, the agent reads the actual log file before attempting any fix.** Write the log path into the rule so nobody has to find it under pressure.

**Why:** An agent confronted with a broken tool will shotgun plausible fixes, and some of those fixes make things worse. Diagnose-before-fixing is the whole game. The expensive failure here was an agent "fixing" a broken IDE for hours when the log named the real problem in line one.

**How to apply:** Honor system. Open the newest log, find the actual error, then act. If your stack has a known log location (IDE logs, daemon stderr, build output), hardcode the path in this file.
