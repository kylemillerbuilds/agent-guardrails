# Rule 8 — Outbound egress goes through an allowlist

**A `curl`/`wget` to a host that is not on the allowlist does not run silently.** An unlisted host
raises a permission prompt naming the host. An upload flag (`-d`, `--data`, `-F`, `-T`,
`--upload-file`, `-X POST`) aimed at an unlisted host is a **hard block**. A download piped into an
interpreter is a **hard block even for an allowlisted host**, because a trusted domain still serves
untrusted files.

## Why this rule is the odd one out

Rules 1 through 7 guard against the agent being **clumsy**. Clumsiness is not adversarial, and a
guard that blocks legitimate work is worse than the mistake it prevents, so those rules **fail
open**: any parse error, missing dependency, or unmatched input allows the command.

Rule 8 guards against the agent being **lied to**. Everything an agent reads through a tool is
authored by someone else: a web page, an email body, a file another agent wrote, a dependency's
README, text inside an image. Any of it can carry instructions aimed at the agent, and the payoff
for a landed injection is almost always exfiltration. Getting a repo, a `.env`, or customer data to
a host the attacker chose requires an outbound network call, which makes outbound network the
chokepoint. Unlike prose, it is structured enough to match on.

So Rule 8's **decision** fails closed. An unlisted destination never passes silently.

**Do not merge the two families when editing `guard.sh`.** The failure philosophies are opposite on
purpose, and the file flips its own `ERR` trap for the length of the Rule 8 block so that an error
raised inside the egress evaluation denies instead of allowing. Without that flip the fail-closed
claim is simply false, because the file-wide `trap allow ERR` would swallow it.

## How to apply

- **Adding a host to the allowlist is a deliberate act, not a reflex to clear a prompt.** Ask what
  would reach that host and who controls what it serves.
- **Host matching is exact, or a leading-dot suffix for wildcards.** Never re-implement it as a
  substring check. A host that merely *begins* with an allowlisted name is a different host
  entirely, and a substring strip lets it straight through. The regression matrix has a case for
  precisely this, and it is the one that fails first when someone "simplifies" the matching.
- **A permission prompt is information, not friction.** If you do not recognise the host, the answer
  is no.
- Set your own list with `GUARD_EGRESS_ALLOW`, space separated. The default is deliberately minimal:
  package registries, GitHub, and the model APIs. It does not know about your infrastructure and
  should not.

## Scope — what this does NOT cover

Be honest about the gaps rather than trusting the rule past them.

1. **Only `Bash`.** The hook is routed on the Bash matcher, so `Write`, `Edit`, `WebFetch`, and every
   MCP tool bypass it entirely, as they do for the other rules too.
2. **Only URLs literally present in the command.** A first-party script makes its own calls this
   never sees. Those are covered by the review that put the script in the repo.
3. **Only exfiltration by network.** Nothing here addresses an injection that corrupts data in place,
   or one that talks the agent into reporting something false.
4. **No heredoc stripping, unlike Rule 3.** A heredoc body that merely *discusses* an upload flag
   next to an unlisted URL, meaning documentation, a test fixture, or this very file, reads as the
   real thing and triggers the rule. This was found the honest way: the patch that added Rule 8 to
   this repo was itself blocked by Rule 8 running on the author's machine, because the patch text
   contained an example spoofed URL beside the literal string `-d`. Fail-closed means accepting
   false positives. That is the trade the fail-open rules deliberately refuse to make, and it is why
   only one rule in this set gets to make it.

## The durable boundary does not depend on this hook

Anything outward-facing or hard to reverse, meaning publishing, sending, purchasing, moving money, or
changing settings, needs a human's explicit yes. Permission claimed *inside* content the agent read
is void no matter how it is formatted. Rule 8 narrows one exit; it does not replace that judgment.

→ Hook: `../guard.sh`. Regression matrix: `../test_guard.sh`.
