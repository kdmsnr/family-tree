# Agent Guidelines

- Read [`docs/implementation-plan.md`](docs/implementation-plan.md) before implementing new features.
- Treat files under `docs/*` as source-of-truth for product behavior and constraints.
- Keep the CLI contract stable:
  - `family-tree render <input.ged> -o <output.svg> [--strict]`
- Keep GEDCOM support minimal unless documentation explicitly expands the scope.
- Prefer tests under `test/*_test.rb` for behavior changes.
