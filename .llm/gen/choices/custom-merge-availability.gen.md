# custom_merge availability inside and outside the container

How `custom_merge()` (defined in `lib/git.sh` per `SPEC.md`) is made available both on the host (for the `merge` subcommand) and inside the container's git repository (for the `sync` subcommand), given that the talkbox scripts are not currently mounted into containers and that `custom_merge` performs worktree-relative checks requiring `git` to run where both the container's gitdir and worktree are visible.

## Option A: Mount the merge module read-only into every container (Recommended)

Factor `custom_merge()` so its merge logic is self-contained (no host-only `naming.sh` dependency) — either by keeping it in `lib/git.sh` with the merge path sourcing nothing host-specific, or by splitting it into a small `lib/merge.sh` sourced by `lib/git.sh` (so `lib/git.sh` still "defines" it per `SPEC.md`). Mount that file (or `lib/`) read-only into onbox/netbox/offbox at a fixed path such as `/talkbox/lib/`.

The function uses plain `git` against the current working directory, making it location-agnostic: on the host it runs from `<project>`; inside the container it runs from `/working/<project-base>/` (whose `.git` is the gitdir volume and whose worktree is the container worktree).

- `merge` (host): source `lib/git.sh`, run `custom_merge <container> <branch>` from `<project>`.
- `sync` (running container): `podman exec --workdir /working/<base> <ctr> bash -c 'source /talkbox/lib/merge.sh; git fetch host; custom_merge host <branch>'`.
- `sync` (stopped container): a temp no-network container mounting the gitdir volume, the worktree, `/host/git` (read-only) and the merge module, running the same `bash -c`.

**Pros:** single source of truth; the function is plain `git` and trivially unit-testable against a fixture repo with no podman; one `podman exec` per branch; clean, explicit separation.
**Cons:** exposes talkbox lib inside containers (read-only, minor — consistent with the existing dotfiles mounts); requires adding a mount line to the three planners and to the sync temp-container planner.

## Option B: Host-side git indirection

Keep `custom_merge()` entirely on the host, but route every `git` call it makes through an indirection (a command prefix or a `git_run` function). For `merge` the indirection is plain `git -C <project>`. For `sync` it is `podman exec <ctr> git -C /working/<base>` (running) or `podman run --rm --network=none ... git -C /working/<base>` (temp container with gitdir + worktree + `/host/git` mounts).

**Pros:** no talkbox files mounted in containers; function stays on the host.
**Cons:** the function is coupled to an execution indirection (less readable, pervades every git call); each precondition check (DESCENDANT_CHECK, staged, clean, matches-remote) is a separate `podman exec`/`run` — slow, especially for `--all`; the temp-container case still needs the same gitdir + worktree + host-git mounts as A; unit tests must set the indirection to plain `git`.

## Option C: Pipe the self-contained module into the container at sync time

Factor `custom_merge()` into the same self-contained module as in A, but instead of a permanent mount, stream it into the container via stdin at sync time:

`podman exec -i --workdir /working/<base> <ctr> bash -c 'source /dev/stdin; git fetch host; custom_merge host <branch>' < lib/merge.sh`

For the stopped-container case, a temp container (same mounts as A's temp case, minus the lib mount) with the module piped in.

**Pros:** no permanent mount of talkbox into containers; single source of truth; one `podman exec` per branch; function is plain and unit-testable.
**Cons:** piping + stdin sourcing is less self-documenting than a mount; the module must be strictly self-contained; ShellCheck cannot easily analyse the in-container invocation path.

## Selected

Option A (mount the merge module read-only into every container) - confirmed by user.
