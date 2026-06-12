# Contributing

This repo is extracted from a real production setup. Contributions are welcome if they follow the design philosophy:

1. **Fail-open, always.** A guard that can break your workflow gets deleted. Guards only ever block explicit, matched dangerous patterns.
2. **Tests before wiring.** Every new rule or pattern change must have test cases in `test_guard.sh` — both the positive (block) and negative (allow) cases. The matrix runs green before any edit ships.
3. **No dependencies beyond bash + python3.** The guard runs in every environment without setup.

## Adding a new rule

1. Write the rule document in `rules/` explaining the incident and the why.
2. Add the detection pattern to `guard.sh`.
3. Add test cases to `test_guard.sh` — at minimum: one case that should block, one that should allow, and one edge case that previously false-positived.
4. Run `./test_guard.sh` and confirm green.
5. Open a PR.
