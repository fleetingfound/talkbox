# Choices

## Implementation design choices

- [x] [Module Structure](module-structure.gen.md) - how to split `talkbox.sh` logic across `lib/`.
- [x] [Volume Population Strategy](volume-population.gen.md) - how read-write volumes and root filesystem inheritance are populated.
- [x] [Test Modularization](test-modularization.gen.md) - split of unit vs end-to-end test coverage.
- [x] [Planner-vs-executor project-dotfiles existence handling](planner-dotfiles-existence.gen.md) - whether the project-dotfiles existence check lives in the planner or the executor.

## Planner/executor divergence resolution

- [x] [Planner/executor resolution strategy](planner-executor-resolution.gen.md) - whether to wire the executors to their `plan_*` counterparts, extend the plan model for the conditional run path, or delete the unused plan functions.

## Phase 5 design choices

- [x] [custom_merge availability inside and outside the container](custom-merge-availability.gen.md) - how `custom_merge()` reaches both the host (`merge`) and the container's git repository (`sync`).

## Scaffold refactor choices (Phase 1c)

- [x] [Scaffold refactor scope](scaffold-refactor-scope.gen.md) - which of the review's recommendations to address in the scaffold-refactor phase before Phase 2.
- [x] [Planner array-population mechanism](planner-array-mechanism.gen.md) - nameref-populating planner vs NUL-delimited stdout for the array-based planner interface.
