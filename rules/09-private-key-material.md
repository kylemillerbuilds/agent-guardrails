# Rule 9 — Private key material is never read

**A command that reads, copies, or pipes the CONTENTS of a private key does not run.** Using a key
is fine: `ssh`, `scp`, `sftp`, `ssh-add`, `ssh-keygen`, `ssh-copy-id`, `chmod`, `chown`, `ls`,
`stat` and `file` may all name one. `cat`, `base64`, `cp`, `tar`, `curl -T`, a Python `open()` —
those are refused. Public keys (`.pub`), `known_hosts`, `config` and `authorized_keys` are
untouched; reading those is ordinary work.

## Why this is separate from Rule 8, which already blocks exfiltration

Because a key is not like other secrets. An API token usually buys an API, and usually a rate-limited
one. An SSH key with no passphrase buys the machine it opens, with **no exploit anywhere in the
path** — the read *is* the compromise and the upload is a formality.

I found this by working out what an attacker would actually need to get root on a server I run,
rather than what I assumed they would need. The perimeter answers were all reassuring: key-only
SSH, fail2ban, unattended upgrades, nothing listening that should not be, no sudo for the service
account. None of it mattered, because the shortest path did not go through the server at all. It
went through the client — one file, one outbound request — and my agent tooling could reach both
ends of that.

## Two surfaces, two rules, and you need both

The file-reading tool and the shell are **different tools**. A deny rule on the agent's file reader
stops it opening `~/.ssh/**` and does exactly nothing about `cat key | curl`, which is Bash and
never passes through the file reader at all. I had the first and not the second, and believed I was
covered because I had "a rule for that."

This is Rule 8's scope note restated, and it generalizes past keys: **a secret worth protecting
needs a rule on every tool that can reach it.** Enumerate the tools, not the secrets.

## Segment by segment, and that is the whole design

The first version scanned the command as one string with two blanket escapes: skip if `.pub`
appears anywhere, skip if the command starts with a safe verb. Both are defeated by appending or
prepending — a harmless read placed beside a dangerous one vouched for it, and the whole command
sailed through.

So the command is **split on shell separators and every segment is judged alone.** A safe segment
can no longer speak for a dangerous one. This is the same disease as any substring test standing in
for a security decision, and the same cure.

## Family: Rule 8's, not Rule 1–7's

This one faces an adversary rather than your own clumsiness, so its **decision fails closed**.

**Do not resolve a false positive by loosening the pattern.** Run the command yourself, outside the
agent. It will produce false positives and that is the correct trade — grepping this repository's
own source trips it, because the patterns it matches on are written in the file it is scanning.

## What it does not cover

The same three gaps Rule 8 names, and they are worth stating rather than trusting past:

1. **Only the shell.** The file writer, the fetcher, and every MCP tool bypass it entirely.
2. **Only what is literally in the command string.** A script that reads a key makes its own calls,
   and this never sees them.
3. **Only reads.** Nothing here stops a key being *used* by something that legitimately holds it.

**A hook is a backstop, not a boundary.** The durable fixes are upstream of it: a passphrase, so a
stolen copy is inert on its own; a forced command in `authorized_keys`, so a stolen key can only run
one read-only thing; and a non-root login user, so it buys less when it does work.
