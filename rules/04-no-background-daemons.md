# Rule 4 — No background daemons without human approval

**No launchd/cron/daemon background processes — including KeepAlive AND StartInterval — unless a human explicitly approves first.** Default to zero-background designs.

**Why:** An agent-created KeepAlive job once misbehaved into an infinite restart loop; a StartInterval poller later re-bloated the same way. A background process that misbehaves burns CPU and API tokens silently, after the session that created it is gone. Nobody is watching.

**How to apply:** The agent proposes the design and gets an explicit yes before any `launchctl load` / `crontab` of a self-restarting job. `guard.sh` warns (does not hard-block) on `launchctl load` — warn-only because legitimate, pre-approved daemons need to reload during normal work.
