# `git status` in the container fatals on a submodule gitfile pointing into the missing `.git/modules/`

## symptom

When a host repository contains a submodule (e.g. `.opencode` in this repository), creating a container with `onbox` and then running `git status` (`gs`) at the top of the working tree inside the container fails:

```
fatal: not a git repository: .opencode/../.git/modules/.opencode
```

## reproduction

Without podman, by reproducing the container-side filesystem layout:

1. copy the host worktree (excluding `.git`) to a temp `worktree/`, keeping the submodule checkout with its `.git` gitfile
2. create a fresh empty git repository in a separate `gitvol/` directory, standing in for the `<project-slug>.onbox.gitdir` volume
3. wire it as `image/setup.sh` does: add the host git dir as the `host` remote, `git fetch host`, point `HEAD` at the host's current branch and `git reset --mixed refs/remotes/host/<branch>`
4. run `git status` in `worktree/`

Step 4 reproduces the exact fatal message.

## root cause

A chain of three facts:

1. `absorb_submodules()` in [lib/git.sh](lib/git.sh) runs `git submodule absorbgitdirs` on the host before the container is created. This relocates each submodule's git directory from `<project>/<submodule>/.git/` into the superproject's `<project>/.git/modules/<submodule>/` and leaves behind a gitfile `<project>/<submodule>/.git` containing the relative pointer `gitdir: ../.git/modules/<submodule>`.

2. Inside the container, the project's `.git` is shadowed: the gitdir volume `<project-slug>.<container>.gitdir` is mounted at `/working/<project-base>/.git`. `image/setup.sh` initializes this volume as a *fresh* `git init` repository (connected to the host history only via fetch and `reset --mixed` of refs and the index). The volume therefore has no `modules/` directory at all, and nothing ever copies or recreates the absorbed submodule git directories there. The host's real `.git`, including `modules/`, is only available read-only at `/host/git/`, which is not where the gitfile points.

3. After the initial `reset --mixed`, the container repository's index contains the gitlink entry for the submodule. `git status` at the superproject level descends into each gitlink to compute the submodule's state, reads `.opencode/.git`, resolves the relative pointer `../.git/modules/.opencode` against the container's shadowed `.git`, finds that `/working/<project-base>/.git/modules/.opencode` does not exist, and aborts the whole `git status` (it does not merely report the submodule as broken).

In other words, SPEC.md requires that submodules are "absorbed into the host's top-level git directory **and then included in the container**", but the second half is unimplemented: the absorbed `modules/` tree is never included in the container gitdir volume, leaving a dangling relative gitfile in the worktree.

## why tests did not catch it

- [test/e2e/git-transport.bats](test/e2e/git-transport.bats) only asserts that `git -C sub status` *fails* inside the container. It does fail, but for the wrong reason (the pointed-to git directory is absent) rather than because submodule operations are explicitly prevented. No test runs a superproject-level `git status` (or any `gs`-equivalent) in a container whose project has a submodule.

## affected behaviour

- superproject-level `git status`, `git diff`, `git add -A` and similar index/commit operations that need to summarize submodule state all fail inside the container while the project contains a submodule checkout
- the failure mode is a hard fatal, not a degraded report

## fix directions (for planning)

- make the absorbed submodule git directories reachable at the path the gitfile points to inside the container, or rewrite/neutralize the gitfile so that superproject status works while submodule git operations remain prevented per SPEC.md
- cover the superproject-level `git status` case in the e2e suite, and tighten the existing "submodule operations are blocked" test so it does not pass merely because the gitdir is missing
