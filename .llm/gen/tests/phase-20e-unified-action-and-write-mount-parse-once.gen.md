# Tests: Phase 20e unified container action and single write-mount parse

Pinning-test pass for [phase-20e-unified-action-and-write-mount-parse-once](../plans/phase-20e-unified-action-and-write-mount-parse-once.gen.md), which merges `onbox_action`/`sandbox_action` into one container-parameterised action in `talkbox.sh`, drops the redundant explicit `ensure_base_image` calls in the onbox branches, and changes `mount_volume_args` in `lib/mounts.sh` to accept precomputed write srcs/dsts arrays instead of re-parsing the defaults file and CLI specs, with external-facing behaviour unchanged. These tests pin the current dispatcher behaviour at the unit level so the refactor can proceed safely; no core files were modified and every new and surviving test passes against the current implementation.

Because the implementation change has not landed yet, the superseded tests are rewritten onto the interfaces the plan preserves (`mount_entries`, the naming layer, the `run_*` executors, and the `talkbox.sh` CLI surface) rather than onto the planned new `mount_volume_args` signature: the volume tokens the old tests asserted are now asserted through the real dispatcher with the logging podman shim, which pins the same emitted `-v` tokens before and after the signature change.

## New tests

### test/unit/dispatcher.bats

Twenty-one tests driving `talkbox.sh <container>` as a subprocess (as `test/unit/smoke.bats` already does) with the shared logging podman shim from `test/unit/helpers.bash`, asserting on the logged podman command lines:

1. `talkbox.sh onbox creates the container with the host worktree bind-mount and runs setup then the command` — default verb for onbox: container name, read-write host worktree bind-mount, host git and gitdir-volume mounts, eager gitdir `volume create`, `start`, the nft `unshare nsenter` applied before the `setup.sh` exec, the `setup.sh` exec before the user command exec, and the final `stop`.
2. `talkbox.sh onbox defaults to an interactive shell when no command is given` — the create args carry `--interactive --tty` and the session execs `/bin/bash` interactively.
3. `talkbox.sh netbox populates its volumes from the host and installs the nft deny rules after start` — worktree-volume mount and no-network populate run sourcing the host read-only, gitdir-volume creation, and `start` → nft → `setup.sh` ordering.
4. `talkbox.sh offbox restricts pasta to loopback and installs no nft rules` — `pasta:-i,lo,-I,talkbox0`, no `unshare`/`inspect` PID lookup, and the `setup.sh` exec after start.
5. `talkbox.sh onbox bind-mounts CLI write specs and never populates volumes` — a `--write` spec appears as a plain bind-mount token (no `.onbox.write` volume) and no populate `podman run` is issued.
6. `talkbox.sh netbox mounts a CLI write spec as a volume named <slug>.netbox.write.<dest-slug> and populates it from the host` — the create line carries `talkbox-proj.netbox.write.talkbox-wdata:/talkbox/wdata` and the populate run sources the host read-only.
7. `talkbox.sh offbox mounts a CLI write spec as a volume named <slug>.offbox.write.<dest-slug>` — the offbox variant of the volume naming.
8. `talkbox.sh netbox derives the write-volume dest-slug from the dest basename path` — dest `/a/b/c` yields volume `talkbox-proj.netbox.write.a-b-c:/a/b/c`.
9. `talkbox.sh netbox collapses identical write dests into a single volume populated from the last source` — `--write /first:/x --write /cli:/x` produces exactly one volume token in the create line, exactly one populate run, sourced from the last CLI spec.
10. `talkbox.sh netbox merges defaults-file and CLI write specs in order` — against a temporary copy of `talkbox.sh`/`lib`/`defaults` with a defaults-file write entry appended, both the defaults-file volume (`…write.x:/x`) and the CLI volume (`…write.y:/y`) appear in defaults-then-CLI order in the create line.
11. `talkbox.sh threads --port into the per-container pasta network string` — repeated `--port` flags yield `pasta:-T,8080,-T,9090,--dns-forward,…` for onbox and `pasta:-T,8080,-i,lo,-I,talkbox0` for offbox.
12. `talkbox.sh netbox --recontain recreates the container and volumes without a commit` — rm → volume populate → gitdir-volume create → create → start → nft → setup exec → stop, with no commit or build.
13. `talkbox.sh onbox --recontain recreates without populating, nft or setup` — rm → gitdir-volume create → create → start → stop with no populate run, commit, build, nft or exec.
14. `talkbox.sh onbox --rebuild builds the base image before recreating` — build precedes rm precedes create, with no commit, nft or exec.
15. `talkbox.sh netbox --rebuild builds the base image and skips the commit when no source container exists` — build first, no commit, nft and setup after start.
16. `talkbox.sh netbox commits the onbox container as the netbox root image by default` — `commit talkbox-proj.onbox talkbox-proj.netbox.root` precedes the create, whose image is the root image.
17. `talkbox.sh netbox --fresh skips the commit even when the onbox container exists` — no commit and the create uses the base image.
18. `talkbox.sh netbox --rm-container removes the container, its volumes and its root image` — rm, worktree/gitdir volume rms (no write volumes without write specs) and the root-image `rmi` after them.
19. `talkbox.sh onbox --rm-container removes only the container and its gitdir volume` — one `rm`, one gitdir `volume rm`, and no root-image probe or `rmi`.
20. `talkbox.sh onbox --rm-image removes the base image when it is not in use` — `rmi talkbox/base:latest` with no container rm.
21. `talkbox.sh without arguments prints the usage and exits 2` — the usage message and exit code 2.

The `fetch`/`merge`/`sync` verbs are not pinned here: their bundle/host-git interplay is not shim-able at unit level and the e2e suite covers them end-to-end. No assertion pins the `ensure_base_image` probe count or the double parse, since the plan removes the redundant onbox probes and the parse-once invariant is not directly observable.

## Tests edited

- `test/unit/netbox-offbox.bats` — the two `mount_volume_args` call sites inside `run_netbox keeps read mounts read-only and write mounts as volumes, populating them from the host` and `run_offbox emits write-mount volumes and read-only read mounts, populating from the host` are rewritten: the write srcs/dsts arrays are now built first with `mount_entries`, and `write_mounts` is derived from them via `netbox_write_volume`/`offbox_write_volume` + `dest_slug`, instead of calling `mount_volume_args`. Superseded per the plan's tests section (they "exercise the changed `mount_volume_args` internal interface"); the asserted create/populate tokens are unchanged and the tests still pass against the current implementation.

## Tests removed

All removed tests are the direct `mount_volume_args` unit tests of `test/unit/mounts.bats`, identified as superseded by the plan's tests section and by the linked [write-mount-parse-once choice](../choices/write-mount-parse-once.gen.md) ("the existing `mount_volume_args` unit tests are superseded"), because they call `mount_volume_args` with the file/project/home/CLI-spec signature that the phase's `lib/mounts.sh` change replaces. Their volume-token coverage is preserved one-for-one by the dispatcher tests listed above.

- `mount_volume_args emits netbox write mounts as volumes named <slug>.netbox.write.<dest-slug>` → replaced by dispatcher test 6.
- `mount_volume_args emits offbox write mounts as volumes named <slug>.offbox.write.<dest-slug>` → replaced by dispatcher test 7.
- `mount_volume_args derives the dest-slug from the dest basename path` → replaced by dispatcher test 8.
- `mount_volume_args merges defaults-file and CLI write specs` → replaced by dispatcher test 10 (the defaults-file side via a temporary talkbox copy; the defaults/CLI merge logic itself remains pinned by the retained `mount_entries`/`mount_args` union and override tests).
- `mount_volume_args collapses an identical defaults-file and CLI write dest into a single volume mount` (added by phase 20a) → replaced by dispatcher test 9.

`test/unit/mounts.bats` retains all `mount_args`/`mount_entries` tests unchanged (`mount_entries` and `mount_args` are unchanged by the plan). No end-to-end tests were added or changed; `make test-unit` (287/287), `make test-e2e` (76/76), `make lint` and `make format` all pass with the tests in place, against the unmodified implementation.
