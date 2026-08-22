# Module Structure

How the core logic of `talkbox.sh` is split across files in `lib/`, in order to keep units small and individually testable.

## Option A: Functional split (Recommended)

Split by domain concern into focused library files sourced by `talkbox.sh`:

- `lib/naming.sh` - `<project-base>`, `<project-slug>`, volume/image name construction.
- `lib/options.sh` - argument parsing for the dispatcher and per-container subcommands (`-c`, `--read`, `--write`, `--port`, `--fresh`, `--inherit`, `--recontain`, `--rebuild`, `--rm-container`, `--rm-image`, git subcommand verbs).
- `lib/mounts.sh` - parse `read.mounts`/`write.mounts` and `--read`/`--write`, expand `~`/`$HOME`/`$PROJECT`, default dest derivation, depth-ordered deduplication, emission of `podman` mount arguments.
- `lib/ports.sh` - parse `defaults/ports` and `--port`, emission of `pasta` network options per container type.
- `lib/containers.sh` - base image build, container create/start, volume population, root filesystem inheritance (`podman commit`), `--recontain`/`--rebuild`/`--rm-*` operations.
- `lib/git.sh` - `custom_merge()`, submodule absorption, bundle-based fetch/merge/sync.

`talkbox.sh` itself only dispatches (resolve invocation name / first arg, source the relevant libs, route to the selected action). `image/entrypoint.sh` handles in-container setup (dotfiles, git remote/worktree wiring) and sources no `lib/` file.

**Pros:** clear responsibilities; each file's pure logic (slug, mount parsing/sorting, port parsing) is unit-testable in isolation by sourcing the file alone; the dispatcher stays tiny.
**Cons:** more files; `containers.sh` and `git.sh` remain sizeable.

## Option B: Per-container split

One file per command: `lib/onbox.sh`, `lib/netbox.sh`, `lib/offbox.sh`, plus `lib/git.sh` and a small shared `lib/common.sh`.

**Pros:** mirrors the user-facing commands; easy to find onbox-specific behaviour.
**Cons:** heavy duplication of mount/port/volume logic across the three container files, or a large shared `common.sh` that defeats the separation; netbox/offbox share most behaviour so the split is artificial.

## Option C: Single-file

Keep everything in `talkbox.sh` with section comments.

**Pros:** simplest navigation.
**Cons:** hard to unit test pure helpers without sourcing the whole dispatcher; conflicts with the testing requirement in `SPEC.md` and the modularization goal.

## Selected

Option A (functional split) - confirmed by user.
