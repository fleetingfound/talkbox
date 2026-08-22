# Issue: unit terminal-allocation assertion is too loose

## Affected files

- [test/unit/containers.bats](../../../test/unit/containers.bats) - `onbox interactive plan allocates a terminal`

## Description

The test asserts that the planner output contains at least one of:

```
--interactive | -it | -i | --tty | -t
```

This regex union means an implementation that emitted only `-i` (interactive flag, no tty) would pass the test. Yet `-i` alone does not allocate a pseudo-terminal, and the interactive shell experience depends on a tty being allocated. The implemented `plan_onbox` emits both `--interactive` and `--tty` (on separate lines), which is correct, but the test does not enforce that both are present.

The mirror test `onbox noninteractive plan does not allocate a terminal` uses the same loose union and would fail if either flag appeared, which is fine for the negative case.

## Suggested fix

Require both an interactive flag and a tty flag in the interactive case. For example, assert that the output contains a line matching `^--interactive$` AND a line matching `^--tty$` (or `^-i$` AND `^-t$`, etc., matching whatever pair the implementation is expected to emit).

## Related

- [Review: Phase 1 onbox test suite](../reviews/phase-1-onbox-test-suite.gen.md)
