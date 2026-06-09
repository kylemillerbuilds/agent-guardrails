# Rule 7 — Verify agent claims on disk

**Never relay an agent's "done" without checking the disk.** Files exist (`ls`), in the right location (`find`), containing what was claimed (grep for an identifier you'd only find in real output). For visual work: open the pixels. For audio: play it.

**Why:** Agents fabricate completions. Not occasionally — reliably enough that I have a documented incident list. The failure mode is always the same: a confident summary of work that doesn't exist, or exists somewhere wrong, or is a placeholder. If a second agent (or you) approves work based on the first agent's summary, fabrication compounds into the record.

**How to apply:** Honor system, and it's the most important rule in this set. Minimum bar for accepting "done": one `ls`, one content check on a named identifier. For anything that renders: look at the output with your eyes. "Ran against mocks" is not "ran against real data" — synthetic tests must be labeled as synthetic.
