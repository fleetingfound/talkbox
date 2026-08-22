# Review: Phase 1 onbox implementation as a scaffold

Related plan: [phase-1-onbox-minimal.gen.md](../plans/phase-1-onbox-minimal.gen.md)
Related spec: [SPEC.md](../../../SPEC.md)
Related choices: [module-structure](../choices/module-structure.gen.md), [test-modularization](../choices/test-modularization.gen.md), [planner-dotfiles-existence](../choices/planner-dotfiles-existence.gen.md)

## Scope of review

Assesses the style, structure, organization and quality of the Phase 1 implementation (`talkbox.sh`, `lib/naming.sh`, `lib/options.sh`, `lib/containers.sh`, `image/Containerfile`, `image/entrypoint.sh`) against its role as a scaffold for Phases 2-5. It does not re-cover the test suite (see [phase-1-onbox-test-suite.gen.md](phase-1-onbox-test-suite.gen.md)).

## What the implementation does well

- **Module split matches the chosen design.** `lib/naming.sh`, `lib/options.sh`, `lib/containers.sh` follow the functional split in [module-structure.gen.md](../choices/module-structure.gen.md). Each file has a single, clear responsibility and the dispatcher (`talkbox.sh`) stays tiny.
- **Dispatcher is clean and correct.** `talkbox.sh` resolves `TALKBOX_ROOT` via `readlink -f "$0"` (works for both `talkbox.sh onbox` and `onbox`-symlink invocation), routes `onbox`, rejects `netbox`/`offbox` with a clear "not implemented yet" message, and rejects unknown containers with exit 2. The `case` is exhaustive.
- **Planner/executor separation exists.** `plan_onbox` assembles the `podman` argument list; `run_onbox` executes it. This matches the test-modularization choice and lets unit tests assert on the planner without invoking podman.
- **`entrypoint.sh` is minimal and idempotent.** Global then project dotfiles copied with `cp -a .../.`, project overrides global, then `exec` of the command or shell. `set -euo pipefail` is set.
- **Containerfile is well-structured.** Single `RUN` for apt install, separate `RUN` for user creation, `--chmod=755` on `COPY` of the entrypoint, `USER dev` before `WORKDIR`, `ENTRYPOINT` exec form.
- **Naming helpers are pure and well-factored.** `project_base`, `project_slug` (lowercasing, non-alphanumeric → `-`, run collapsing, edge trimming) and `base_image_name` are side-effect-free and trivially unit-testable.

## Significant shortcomings as a scaffold

### 1. The planner emits text; the executor re-parses text (architectural smell)

This is the most consequential scaffold limitation. `plan_onbox` prints arguments one per line via `printf`; `run_onbox` reads lines back and re-splits:

```
while IFS= read -r line; do
    if [[ "$line" == -v\ * ]]; then
        args+=("-v" "${line#-v }")
    else
        args+=("$line")
    fi
done < <(plan_onbox "$project" "$command" "$interactive")
```

This line-oriented text protocol is fragile and does not scale to Phase 2+:

- **Argument boundaries are not preserved.** A mount source or destination containing a space (entirely possible for host paths) cannot be represented, because the `-v ` prefix-strip assumes the remainder is a single token with no embedded whitespace.
- **Every flag-with-value needs bespoke re-parsing.** Phase 2 adds `--network=pasta:-T,<port1>,-T,<port2>` (single token, fine), but also many more `-v` lines, `--mount`-style entries, and potentially `podman create` arguments that differ from `run`. Each value-bearing flag would need its own prefix-match branch in the executor.
- **The subshell boundary blocks input sharing.** `plan_onbox` runs in a process substitution, so it cannot consult variables set in the caller (e.g. option records parsed by `options.sh`). It must receive every input as a positional argument. As the planner's input set grows (mounts, ports, inheritance source, `--fresh`), the positional signature becomes unwieldy.
- **Tests are coupled to the text protocol.** `containers.bats` asserts on planner output via line regex (`plan_line '^--workdir=...$'`). Refactoring the planner to use an array would force a test rewrite.

**Recommendation:** replace the printf-line protocol with a nameref-populating planner (e.g. `plan_onbox <out_array_name> <project> <command> <interactive>` that appends to a caller-declared array via `local -n out=$1`) or a `printf '%s\0'` + `mapfile -d ''` pair that preserves exact argument boundaries. The executor then becomes a trivial `podman run "${args[@]}"` with no re-parsing. Unit tests assert on array membership rather than line regex.

### 2. `run_onbox` hard-codes `podman run --rm` with no create/start/rm distinction

`run_onbox` is a single `podman run` invocation. Phase 2 introduces `--recontain` (recreate container + volumes, then start), `--rm-container` (remove container + volumes) and `--rebuild` (rebuild image, recreate, start). These need `podman create`, `podman start`, `podman rm`, `podman volume rm`, `podman image rm`. The current executor has no abstraction for the create/start/run distinction, no notion of a named (non-`--rm`) container, and no volume-management surface.

As a scaffold, `lib/containers.sh` should anticipate at minimum a separation between:
- image operations (`ensure_base_image`, future `remove_base_image`, `commit_root_image`)
- container lifecycle (`create`, `start`, `run`, `rm`)
- volume operations (`volume_create`, `volume_rm`, future `volume_populate`)

Even if Phase 1 only implements `run`, factoring the executor so that `run` is one verb among several would make Phase 2 a smaller, more additive change.

### 3. `plan_onbox` is onbox-specific with no shared container-planning skeleton

Phase 3 (`netbox`, `offbox`) shares the bulk of the onbox plan: `--workdir=/working/<project-base>`, `--userns=keep-id:...`, `--cap-drop=NET_ADMIN`, `--cap-drop=NET_RAW`, the dotfiles bind-mounts, and (in Phase 2) the read mounts. The differences are: network options (offbox gets the `-i,lo,-I,talkbox0` form), write mounts (bind for onbox, volumes for netbox/offbox), worktree source (bind for onbox, volume for netbox/offbox), and root image source.

The current `plan_onbox` has all of these inline with no extension points. Phase 3 will either duplicate `plan_onbox` into `plan_netbox`/`plan_offbox` (with the maintenance burden that implies) or refactor a shared `plan_container` out. The scaffold would be friendlier if `plan_onbox` were already structured as "shared base args + container-specific overrides", e.g. a `plan_container_base` that emits workdir/userns/caps/dotfiles, composed with a container-specific mount/network/image layer.

### 4. No `lib/mounts.sh` or `lib/ports.sh` seam foreshadowed

The Phase 2 plan creates `lib/mounts.sh` and `lib/ports.sh`. The current `plan_onbox` emits the hardcoded `-v` lines and `--network=pasta` inline; there is no call-out to a mount-emission or port-emission function that Phase 2 can replace. As a result Phase 2 must surgically extract the inline `-v` lines from `plan_onbox` and reroute them through the new modules.

A more scaffold-friendly shape would have `plan_onbox` call (even stub) functions like `emit_read_mounts` / `emit_write_mounts` / `emit_network_options` from day one, so Phase 2 replaces stub bodies rather than refactoring `plan_onbox`'s internals.

### 5. `options.sh` uses onbox-prefixed globals

`parse_onbox_options` sets `ONBOX_COMMAND` and `ONBOX_INTERACTIVE` (with a `shellcheck disable=SC2034` acknowledging they are unused in the lib). This works for Phase 1 but:

- The `ONBOX_` prefix is container-specific. Phase 3's `netbox`/`offbox` parsers would naturally produce `NETBOX_*`/`OFFBOX_*` globals, duplicating the parser. The SPEC's option surface (`-c`, `--interactive`, `--noninteractive`, `--read`, `--write`, `--port`, `--fresh`, `--inherit`, lifecycle verbs, git subcommands) is common across all three containers.
- Phase 2 adds repeatable `--read`/`--write`/`--port` (lists) and lifecycle verbs. Lists don't fit naturally into the current "one scalar global per option" model.

**Recommendation:** a single `parse_options` that returns a structured record (via nameref or a single associative array) covering the common option surface, with container-specific interpretation handled by the container action. This avoids three near-duplicate parsers in Phase 3.

### 6. `plan_onbox` mixes pure planning with filesystem side effects — keep this, don't extract it

Per the Phase 1a choice, the `$project/.dotfiles` existence check was moved into `plan_onbox` to make its output truthful. This was the right call and the principle should be preserved: the planner consults the filesystem at emit time for point-in-time existence checks, and its output reflects what `podman` will actually receive.

A tempting but brittle alternative would be to split the planner into a "gather" step that consults the filesystem and produces a structured description, then a pure "build args from description" function. This was considered and rejected because:

- It partially reverses the Phase 1a truthfulness gain: a gather step checks earlier, introducing a window where the description and the filesystem diverge (e.g. `.dotfiles` created or removed between gather and build). Checking at emit time is *more* truthful.
- The intermediate description becomes a new synchronization surface: every future input requires a field added to the description, with both gather (to populate it) and build (to consume it) updated in lockstep. In bash, with no native structs, this is a hand-rolled mini-type-system maintained by discipline.
- It conflates two kinds of input with different lifecycles. Pre-parsed structured data (mount-file entries, port lists) is read-once and naturally passed as arguments. Point-in-time existence checks (`does .dotfiles exist right now?`, `does the netbox volume exist?`) are only meaningful at emit time. Forcing both into one intermediate representation is artificial.

Instead, the principle to preserve is:

- **The planner consults the filesystem directly for existence checks**, at the point where the corresponding mount line is emitted. Each such check is a single `[[ -d ... ]]` / `[[ -e ... ]]` guard. This is already the Phase 1a shape.
- **Pre-parsed structured inputs are passed in as arguments.** Mount lists and port lists should be parsed by `lib/mounts.sh` / `lib/ports.sh` (pure, unit-testable in isolation) and passed to the planner as array arguments (or namerefs), not re-read from disk inside the planner. This keeps the planner's disk touches limited to cheap, point-in-time existence checks.
- **Unit tests exercise the planner via filesystem setup.** The test harness creates the directory structure (e.g. `$project/.dotfiles`) in `BATS_TEST_TMPDIR` before calling the planner, and asserts on its output. The planner's filesystem dependency is real but testable via setup, not via mocking.

This keeps recommendation 1 (array-populating planner) and this recommendation consistent: the planner is impure but its impurity is limited to existence checks exercised by filesystem-based test setup, while heavier parsing lives in separately-testable pure modules that feed the planner structured input.

### 7. No image-management abstraction beyond `ensure_base_image`

`ensure_base_image` is the only image operation. Phase 2 adds `--rm-image` (with in-use detection across containers); Phase 3 adds `podman commit <container> <project-slug>.<container>.root` for root filesystem inheritance. There is no `lib/images.sh` or image-operation seam. The naming helpers similarly only know the shared base image name (`talkbox/base:latest`); there is no `root_image_name()` for the per-project inherited images that Phase 3 requires.

**Recommendation:** add `root_image_name()` (and similar) to `lib/naming.sh` now or in Phase 2, and consider an image-operations module so Phase 3's `podman commit` and Phase 2's `--rm-image` in-use check have a home.

### 8. `run_onbox`'s executor special-cases only `-v`

The executor's `if [[ "$line" == -v\ * ]]` branch exists solely to split `-v src:dst:mode` into two array entries. No other value-bearing flag is handled. If the planner emits `--network=pasta:-T,8080` (Phase 2), the executor's `else` branch appends it as a single token, which is correct for `--opt=value` form but would be wrong for `--opt value` form. The protocol is under-specified and the executor is doing the bare minimum to survive Phase 1. This reinforces recommendation 1.

## Style and minor issues

- **Shebangs in sourced `lib/*.sh` files.** `lib/naming.sh`, `lib/options.sh`, `lib/containers.sh` each begin with `#!/usr/bin/env bash`. These files are always sourced, never executed, so the shebang is misleading. ShellCheck does not flag it but it is inconsistent with the "sourced library" convention.
- **Ad-hoc error messages.** `talkbox: unknown option: %s`, `talkbox: unknown container: %s`, `talkbox: %s is not implemented yet` are formatted inline at each call site. A small `die()` helper (print to stderr, exit with code) would centralize the prefix and reduce duplication as error paths multiply in Phase 2+.
- **`base_image_name` is a zero-argument function returning a constant.** This is fine, but it reads as a function only because the alternative (a variable) would not be overridable by tests. If Phase 3 wants per-project root image names, the naming module needs to grow; a single `base_image_name` is a thin seed.
- **`entrypoint.sh` uses `exec bash -c "$*"`.** `$*` joins argv with the first character of `IFS` (a space). For Phase 1's single-command-string usage this is acceptable and matches SPEC's `onbox -c <command>` (a single command string). However, `exec "$@"` would be more robust if the entrypoint is ever asked to exec an argv array. Minor, given the SPEC's single-string contract.
- **`entrypoint.sh` has no error handling around `cp -a`.** If a dotfile in `defaults/dotfiles/` or `<project>/.dotfiles/` is unreadable, `cp -a` will fail and `set -e` will abort the entrypoint. This is probably the desired behaviour (fail fast) but is worth noting.
- **`plan_onbox` emits `-v $TALKBOX_ROOT/defaults/dotfiles:/talkbox/dotfiles.global:ro` unconditionally.** This assumes `defaults/dotfiles` exists in the repo. The repo ships it, so this works, but it is a hardcoded assumption that `lib/mounts.sh` (Phase 2) will need to generalize (e.g. dotfiles mount should be conditional on existence, like the project dotfiles mount is).
- **`plan_onbox` emits `--rm` unconditionally** even for non-interactive commands. Phase 2's `--recontain` and `--rm-container` semantics conflict with `--rm` (which removes the container on exit). There is no way to keep the container after exit. The scaffold would be friendlier if `--rm` were a planner input rather than a constant.
- **`test/unit/helpers.bash`'s `load_lib` returns 1 with a "not implemented yet" message** if the lib file is absent. This is a reasonable fallback but couples the helper to Phase 1's "some libs not yet present" state. Once all libs exist, the message is dead code.
- **`talkbox.sh` sources all libs unconditionally.** Fine for Phase 1. Phase 4's `lib/git.sh` could be sourced lazily (only when a git subcommand is invoked) to avoid pulling git logic into every invocation, but this is a micro-optimization.

## Summary of recommendations

Ordered by impact on scaffold suitability for Phases 2-5:

1. **Replace the text-protocol planner with an array-populating planner** (nameref or `\0`-delimited). This is the single highest-value refactor; it eliminates the fragile executor re-parsing, preserves argument boundaries, and decouples unit tests from line-regex matching.
2. **Factor `run_onbox` into a lifecycle-aware executor** with image/container/volume operation seams, so Phase 2's `--recontain`/`--rebuild`/`--rm-*` are additive rather than a rewrite.
3. **Restructure `plan_onbox` as shared base + container-specific overrides**, so Phase 3's `plan_netbox`/`plan_offbox` compose rather than duplicate.
4. **Introduce stub `lib/mounts.sh` and `lib/ports.sh` seams** (even if Phase 1 bodies are trivial) so Phase 2 replaces stubs rather than refactoring `plan_onbox` internals.
5. **Generalize `options.sh` to a single structured parser** for the common option surface, dropping the `ONBOX_` prefix, so Phase 3 doesn't gain two near-duplicate parsers.
6. **Keep the planner's filesystem checks at emit time; pass pre-parsed data in as arguments.** Do not introduce a gather/build split (it would reverse the Phase 1a truthfulness gain and create a brittle intermediate representation). Instead keep existence checks inline in the planner (tested via filesystem setup) and feed parsed mount/port lists from pure modules as array arguments.
7. **Add `root_image_name()` and an image-operations seam** to anticipate Phase 3 inheritance and Phase 2 `--rm-image`.
8. **Make `--rm` a planner input, not a constant**, so lifecycle verbs that need a persistent container can opt out.

None of these block Phase 1's correctness; the implementation passes its tests and meets the Phase 1 spec slice. They are forward-looking improvements that would make Phases 2-5 smaller, more additive, and less prone to text-protocol and duplication regressions.
