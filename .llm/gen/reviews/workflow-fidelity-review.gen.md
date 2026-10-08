# Workflow review — `onbox`/`netbox`/`offbox` workflows, `sync`/`merge` and test-suite fidelity to SPEC.md

Review date: 2026-10-08. Environment: podman 5.4.2 (rootless), bats 1.11.1, `nft` present under `/usr/sbin` (not on the default interactive `PATH`).

## scope and method

The investigation combined:

1. full runs of `make test-unit` and `make test-e2e` (plus `make lint`),
2. manual reproduction of the intended workflows against scratch projects under `/tmp/opencode`, using the same fixture strategy as the e2e harness (`mk_talkbox`-style talkbox copy with `image/Containerfile.minimal`, hermetic emptied `defaults/`, base image `talkbox/base-e2e:latest`), including one fixture with the **real shipped `defaults/deny.ip`**,
3. reading [SPEC.md](../../../SPEC.md), [README.md](../../../README.md), the implementation in [talkbox.sh](../../../talkbox.sh) and [lib/](../../../lib/) and the test suites in [test/](../../../test/).

All experiment containers, volumes and root images were removed afterwards.

## baseline results

- `make test-unit`: 302/302 pass.
- `make test-e2e`: 72/72 pass (no skips observed for internet-bearing tests; the host has connectivity and `nft`).
- `make lint`: clean.

## workflow experiments and results

### onbox as intended

- `onbox -c --noninteractive` starts (or reuses) the persistent container, working directory `/working/<project-base>/` (verified with a project base containing spaces, underscores and uppercase: `proj Demo_42` → container `proj-demo-42.onbox`, workdir `/working/proj Demo_42`).
- Files written in the container appear immediately in the host worktree (bind-mount semantics).
- Internet access works from the container.
- Interactive `onbox` (driven via `expect`) shows the ASCII-art banner and coloured prompt `dev@<slug>.onbox /working/<base>`, and exits cleanly via `exit`; a non-git project is handled gracefully (`fatal: not a git repository` from git, not from talkbox).

### host commits + `sync`

- `onbox sync` after a host commit: fetches `host` inside the container's gitdir volume, fast-forwards the container branch (`Updating … Fast-forward`), updates the container worktree, exit 0; the gitdir volume ref matches the host `HEAD`.
- `netbox sync` / `offbox sync`: same behaviour; the merge runs inside the container (or in a no-network temporary container when the target container is stopped — the stopped-container path was exercised naturally in these experiments and works, including re-running `setup.sh` inside the temp container).
- `onbox sync <branchname>` and `--all` are covered by e2e tests that passed.

### container commits + `merge`

- A commit made inside any container lands in that container's gitdir volume, never in the host git dir.
- `<container> fetch` transfers it to the host via a git bundle from a no-network temporary container (the `podman commit`-free path; bundle directories under `/tmp/talkbox-*` are created and removed).
- `<container> merge` fast-forwards the host branch and updates the host worktree (Case 1), leaving the host status clean. Verified for `onbox`, `netbox` and `offbox`.
- Guards verified manually: with host and container histories diverged, both `onbox merge` and `onbox sync` refuse with `talkbox: refusing to merge … not a descendant`, exit 1, and leave `HEAD` unchanged in both repositories. The dirty-worktree refusal (Case 3) and `--all` stop-at-first-failure behaviour are pinned by the e2e suite (passed).
- Bundle transport isolation (no configs/hooks transfer) is covered by e2e and passed.

### onbox → netbox → offbox editing workflow

Performed as one continuous chain on `proj Demo_42`:

1. **onbox**: edit `README.txt`, commit on the host (Git Workflow 1).
2. **netbox** (created after onbox): `podman commit`s `onbox` into `<slug>.netbox.root` (visible in the output) and copies the host worktree into `<slug>.netbox.worktree` — the onbox edit is present. A netbox edit + commit leaves the host file untouched; `netbox merge` fast-forwards the host and the edit appears in the host worktree.
3. **offbox** (created after netbox): `podman commit`s `netbox` into `<slug>.offbox.root`, copies `<slug>.netbox.worktree` into `<slug>.offbox.worktree` (the netbox edit is present), blocks internet (`curl` → `OFFLINE`), leaves the host untouched; `offbox merge` fast-forwards the host again.
4. A further host commit was then synced into both `netbox` (fast-forward, worktree volume updated) and `offbox` (via Case 2 `reset --mixed` — see nuances below).

Inheritance options (`--fresh`, `--inherit`), root-image removal with `--rm-container` and `--rebuild` commit-from-source behaviour are covered by the passing e2e suite.

### write mounts (netbox/offbox volume lifecycle)

- `netbox --write <dir>:<dest>` (fresh container): the named volume `<slug>.netbox.write.<dest-slug>` is seeded from the host directory, writes land in the volume, and the host directory is untouched.
- `offbox --write` created afterwards: the offbox write volume is copied from the netbox write volume (host seed + netbox's file both visible).
- Mount arguments only apply at container creation: invoking an *existing* netbox with a new `--write` silently ignores it. This matches the spec (mounts come from "the command which creates the container") but is worth knowing operationally.

### nft deny/allow enforcement with the real shipped defaults

Using a talkbox copy with the real 61-line `defaults/deny.ip` (the e2e suite empties it), `onbox --deny-ip 1.1.1.1` inside the container showed:

- `http://10.9.9.9/` (RFC1918, deny-listed by the shipped defaults) → blocked,
- `http://1.1.1.1/` (CLI-denied) → blocked,
- `https://example.com` → reachable.

So the interval-set nftables ruleset (allow-set before deny-set, loopback/DNS-forwarder unconditionally allowed) is enforced correctly with the production defaults on this host. Note `nft` lives in `/usr/sbin`, which is not on the default interactive `PATH`; the e2e `deny-allow.bats` setup exports it explicitly, and `lib/network.sh` prepends `/usr/sbin:/sbin` for its own pipeline.

## findings

### issues (new, documented in `.llm/gen/issues/`)

1. [rm-container-write-volumes-need-repeated-write](../issues/rm-container-write-volumes-need-repeated-write.gen.md) — `--rm-container` leaks `<slug>.<container>.write.<dest-slug>` volumes unless the original `--write` spec is repeated on the removal command. The e2e suite masks this by always repeating `--write` on `--rm-container` invocations. Residual gap of the resolved orphaned-volumes issue.
2. [write-mount-file-source-unvalidated](../issues/write-mount-file-source-unvalidated.gen.md) — the spec requires write mounts to be folders, but nothing validates this: `onbox --write <file>` silently bind-mounts a single file read-write, while `netbox`/`offbox --write <file>` fails with a raw `cp: cannot stat '/talkbox/source/.'` error and leaves the auto-created named volumes orphaned.

### nuances (no issue raised)

- **`custom_merge` case precedence.** [SPEC.md](../../../SPEC.md) lists Case 1 (ff-only merge) before Case 2 (reset --mixed), while [lib/merge.sh](../../../lib/merge.sh) evaluates the Case 2 condition first. When both conditions hold the outcomes are identical (branch advanced to the remote ref; worktree already matches it), so this is unobservable in practice; the order was deliberately chosen when resolving [custom-merge-case1-shadowing-case2](../issues/custom-merge-case1-shadowing-case2.gen.md), and the spec text simply has not been updated to reflect it.
- **netbox/offbox worktree volumes contain a copy of the host `.git` directory** (the `cp -a` populate copies everything). The copy is occluded by the gitdir-volume mount at `/working/<base>/.git`, so it is only dead weight inside the volume, not a correctness problem.
- **Interactive `PATH`.** A user whose interactive shell lacks `/usr/sbin` will see strict-mode `talkbox:` failures ("cannot apply nftables…") when the deny set is non-empty, since the nft pipeline relies on `nsenter -n` executing the host `nft`. This is a documentation/onboarding nuance rather than a defect.

## does the test suite accurately represent SPEC.md?

**Overall: yes, to a high standard.** Every workflow the review was asked to exercise is represented by passing end-to-end tests that invoke `talkbox.sh` externally with the onbox/netbox/offbox subcommands, use temporary git repositories (or non-git folders), run podman through `systemd-run --user` with `RuntimeMaxSec`/`KillMode=control-group`, prefer `-c --noninteractive`, and include two `expect`-driven interactive tests. `custom_merge`'s full case matrix (DESCENDANT_CHECK, Cases 1–3, other-branch, missing refs) is covered twice: as unit tests in [test/unit/merge.bats](../../../test/unit/merge.bats) and through the `merge`/`sync` e2e surface in [test/e2e/merge-sync.bats](../../../test/e2e/merge-sync.bats).

Deliberate approximations the suite makes (all reasonable, all documented in the harness):

1. **Minimal image.** [test/e2e/helpers.bash](../../../test/e2e/helpers.bash) swaps in [image/Containerfile.minimal](../../../image/Containerfile.minimal), so the production [Containerfile](../../../image/Containerfile) is never built or tested; `image/setup.sh` itself is exercised.
2. **Emptied defaults.** `mk_talkbox` empties `read.mounts`, `write.mounts`, `ports`, `deny.ip` and `allow.ip`, so the *shipped* default mounts (e.g. the OpenCode auth read-mount) and the 61-line production deny list are only exercised as parsing units, never end-to-end. This review's manual probe confirms the shipped deny list enforces correctly, but the suite would not catch a regression in it.
3. **GPU untested** (per spec, since GPUs may be unavailable); the `--gpu` e2e tests only assert the podman create options via a logging shim.
4. **The `--rm-container` write-volume repeat** (finding 1) is an example of a test encoding a workaround for a behaviour gap rather than the spec's wording.

Spec behaviours verified to match the implementation during this review include: container/volume/root-image naming, root-filesystem and volume inheritance (including `--fresh`/`--inherit`), worktree/gitdir volume wiring via `/host/git` + `host` remote, bundle-only transfer of container history, fast-forward-only merges with warnings on refusal, stopped-container sync via a no-network temporary container, user mapping (`keep-id:uid=1000,gid=1000`), pasta port forwarding, offbox's `-i,lo,-I,talkbox0` network string, and the nft deny/allow pipeline with unconditional loopback/DNS-forwarder allowances.

## conclusion

The commands behave as specified across all the intended workflows tried, including the three-container editing chain and both git-transport directions with their refusal guards. The test suite is an accurate and unusually thorough external representation of SPEC.md; its remaining blind spots are the production image/defaults and the two newly-filed volume-lifecycle issues above.
