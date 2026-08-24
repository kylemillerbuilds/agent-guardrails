# A false claim, caught by a control that already existed

A short case study in checking an AI agent's work. It is here because the guard in this repo and
the practice below solve the same problem from opposite ends: the guard stops an agent from doing
something destructive, and this stops me from believing something untrue.

## The problem with a confident report

I hand research and build tasks to AI agents and read what comes back. The failure I care about is
not an agent breaking something loudly. It is an agent finishing, reporting success, and being
wrong. A confident report and a correct one look identical on the screen.

The specific version of this that costs the most is the word "unavailable." An agent that cannot
reach a source will often say the source cannot be reached, and that statement is unfalsifiable
from where I am sitting. It closes the question. If I accept it, it becomes a fact I build the next
three decisions on.

## The practice

Before I dispatch a task, I answer one question from it myself and keep the answer.

Not a spot check afterward. Before. The order is the entire mechanism. A control I build after
reading a delivery is shaped by the delivery, because I already know what answer I am looking for.
A control that existed first does not care what the report says.

It costs a few minutes and it only has to work occasionally to pay for itself.

## What happened

I was researching a regulated trade and needed to know which edition of a national safety standard
my state legally enforces. Getting this wrong means studying the wrong book, so before sending the
task out I spent about twenty minutes finding the rule myself. The state's own site was awkward, so
I pulled the full text off a law-school mirror instead and saved it with its citation and amendment
date.

An hour later the agent's report came back. It said the rule could not be retrieved, that the
state's site sat behind bot protection, and it delivered a stub file explaining the gap. It was
honest about the failure. It logged the exact command it ran and the status it got back. By its own
standards it did nothing wrong.

It had tried one URL.

The rule I already had in hand was mirrored in at least three places. One host blocking a request
is not a document being unreachable, and the difference between those two sentences is the whole
finding. Because the control was already written, the false claim died in about a minute instead of
becoming an assumption underneath the next month of work.

## What I changed

Three rules came out of this and its neighbors.

**A check reads a different thing than the writer wrote.** My worst verification bug was a check
that confirmed an image was in the position I had just moved it to. It passed every time and it was
measuring nothing. If the check and the write touch the same field, the check can only tell you the
write happened.

**A check has to fail before I trust it passing.** Every gate gets run against deliberately broken
input, and I watch it go red, and the transcript gets saved next to it. A check nobody has watched
fail is a description of a check.

**"I could not look" is its own answer.** Not a pass, not a failure. Collapsing it into either one
is how quiet becomes health. Most of what I have caught was hiding in that collapse.

## The honest limits

None of this is clever, and none of it is automated. The image bug above was found by opening a
page and looking at it, not by any instrument I own. Controls narrow the space where a false report
can survive. They do not remove the need to occasionally go look at the real thing with your own
eyes, and any system that claims otherwise is selling the same confidence problem one layer up.
