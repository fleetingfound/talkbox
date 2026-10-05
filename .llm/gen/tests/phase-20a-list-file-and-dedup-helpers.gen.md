# Tests: Phase 20a — shared list-file reading and ordered dedup helpers

Linked plan: [phase-20a-list-file-and-dedup-helpers.gen.md](../plans/phase-20a-list-file-and-dedup-helpers.gen.md)

Summary: the plan refactors the defaults-file line-parsing and ordered-dedup plumbing behind `mount_entries` in [lib/mounts.sh](../../../lib/mounts.sh) and `port_args`/`deny_allow_args` in [lib/network.sh](../../../lib/network.sh) into shared `read_list_file`/`dedup_ordered` helpers in [lib/common.sh](../../../lib/common.sh) with all external behaviour (emitted podman arguments, error behaviour, ordering) unchanged, so this pinning pass keeps every existing mounts/network test unchanged and adds the missing defaults-file-side coverage to [test/unit/mounts.bats](../../../test/unit/mounts.bats) — in particular the CLI-spec-over-defaults-file last-wins precedence for identical dests called out by the plan.

## New tests

All five new tests live in `test/unit/mounts.bats` and pass against the current, unmodified implementation:

- `mount_args lets a CLI read spec override an identical defaults-file dest keeping the CLI source` — a defaults-file line `/def:/x` plus CLI spec `/cli:/x` collapses to the single mount `-v /cli:/x:ro`, pinning that the CLI spec wins last-wins precedence over the defaults file for identical read dests (previously only CLI-vs-CLI last-wins was pinned).
- `mount_args lets a CLI write spec override an identical defaults-file write dest keeping the CLI source` — the same precedence for identical write dests in bind-mount form, `-v /cli:/x`, which is the exact gap the plan's tests section calls out ("in particular the CLI-spec-over-defaults-file last-wins precedence for identical write dests").
- `mount_volume_args collapses an identical defaults-file and CLI write dest into a single volume mount` — the netbox volume form emits exactly one `-v talkbox-proj.netbox.write.x:/x` for the duplicated dest, pinning that no duplicate volume mount survives; the winning source is deliberately unobservable here because volume names encode the dest slug, not the source.
- `mount_args collapses identical dests within the defaults file keeping the last source` — two defaults-file lines with the same dest keep the later source, pinning the last-source-wins semantics of the `mount_entries` dedup loop within a single source (the file) rather than only across CLI specs.
- `mount_args expands ~ and \$PROJECT in defaults-file lines` — a defaults-file line `~/cfg : $PROJECT/cfg` expands to `-v <home>/cfg:/working/<project-base>/cfg:ro`, pinning that defaults-file lines receive the same placeholder expansion as CLI specs (previously expansion was only pinned through CLI specs), which guards the refactor's shared line reader from changing what the file half of `mount_entries` feeds to `mount_spec`/`expand_mount`.

Unit tests for the `read_list_file`/`dedup_ordered` helpers themselves were not added: the helpers do not exist in the current implementation, the invariant forbids editing core files, and the plan only permits ("may be added") adding them alongside the refactor.

## Tests edited

None. The plan requires the existing behaviour-pinning tests in [test/unit/mounts.bats](../../../test/unit/mounts.bats) and [test/unit/network.bats](../../../test/unit/network.bats) to "keep passing unchanged" — every one of them passes against the current implementation and none is superseded, so all are retained verbatim.

## Tests removed

None. The plan states "No existing tests are superseded or removed — no tested internal interface is dropped": the refactor only replaces internal loops behind the unchanged public signatures of `mount_entries`, `mount_args`, `mount_volume_args`, `port_args` and `deny_allow_args`, all of which remain tested by the retained suites.

## Results

`make test-unit` passes 252/252 (was 247 before this pass) and `make test-e2e` passes 76/76; `make lint` and `make format` are clean. Environment note: the three interactive e2e tests require `expect`, which was absent from the machine; it is now installed user-level (`~/.local/bin/expect` wrapper over the Debian `expect`/`tcl` packages unpacked at `~/.local/share/expect-runtime/`), which is what turns the pre-existing 3 e2e failures into passes. `shellcheck` 0.10.0 and `shfmt` 3.10.0 were likewise installed user-level for `make lint`/`make format`.
