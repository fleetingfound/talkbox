# Test Modularization

Which parts of the implementation are covered by unit tests versus end-to-end tests, and how the code is shaped to make that split clean.

## Option A: Pure helpers unit-tested, podman behaviour e2e (Recommended)

Shape `lib/*.sh` so that pure, side-effect-free logic (slug generation, mount-file parsing, dest defaulting, placeholder expansion, depth-ordered mount deduplication, port-file parsing, pasta-option construction, argument parsing, volume/image name construction) lives in functions that emit strings/arrays and never call `podman`/`git`. Unit tests (bats, `test/unit/`) source a single `lib/*.sh` file and assert on these outputs without any container.

Everything that invokes `podman` or `git` (container creation, volume population, root inheritance, dotfile application, git transport) is exercised only through end-to-end tests (`test/e2e/`) that invoke `talkbox.sh onbox|netbox|offbox` against a temporary git repo / non-git folder, mostly with `-c --noninteractive`, plus a few `expect`-driven interactive cases. e2e tests reuse a shared helper in `test/lib.bash` (or a new `test/e2e/helpers.bash`) that sets up a throwaway git project and a fake `defaults/` set, and wraps every `podman`-invoking call in the required `systemd-run` envelope via the existing runner.

`lib/*.sh` files are written to print assembled `podman` argument lists to stdout (or a named array) rather than executing `podman` directly where practical, so unit tests can assert the assembled command without running podman.

**Pros:** fast, deterministic unit tests catch regressions in the fiddly parsing/sorting logic; e2e tests stay focused on real external behaviour; clear boundary matches `SPEC.md`'s `make test-unit`/`make test-e2e` split.
**Cons:** requires discipline to keep `podman`/`git` calls out of the pure helpers (they go in thin wrapper functions in `containers.sh`/`git.sh`).

## Option B: Mostly e2e, minimal unit tests

Unit test only slug/arg helpers; cover everything else through e2e.

**Pros:** less structuring effort; tests real behaviour end to end.
**Cons:** slow feedback; parsing/sorting regressions surface only as opaque podman failures; harder to test edge cases (nested mounts, depth ordering, inheritance fallbacks) without real containers.

## Option C: Heavy mocking

Mock `podman`/`git` in unit tests via PATH shim binaries.

**Pros:** broad unit coverage.
**Cons:** brittle, couples tests to exact `podman` invocation shape; mocks diverge from real podman behaviour; high maintenance.

## Selected

Option A (pure helpers unit-tested, podman/git behaviour e2e) - confirmed by user.
