# Choice: how `run_fetch` reuses the git-history guard shared with `require_git_history` (review §7)

## context

In [lib/git.sh](../../../lib/git.sh), `run_fetch` duplicates the guard `podman volume exists "$(gitdir_volume …)"` plus the error message `no git history for <container>; create the container first` that `require_git_history` also implements. The review suggests `run_fetch` could call `require_git_history` instead. However, the two guards differ behaviourally:

- `run_fetch` checks only volume existence; under `--all` it **skips** containers whose gitdir volume is missing rather than failing.
- `require_git_history` additionally inspects the volume mountpoint and dies with `no git history in the <container> gitdir volume; start the container first` when `HEAD` is absent, and is fatal only.

Adopting `require_git_history` wholesale in `run_fetch` would therefore change end-to-end behaviour (`fetch --all` would die on partially-initialized volumes; single-container `fetch` would newly die on a volume without `HEAD`). Neither path currently has unit or e2e tests.

## options

### A. Extract a shared non-fatal probe (Recommended)

Extract the volume-existence check and the shared error message into one internal helper with a non-fatal mode (returns status) and a fatal mode (dies). `run_fetch` uses the probe to preserve its `--all` skip semantics and its volume-existence-only failure condition; `require_git_history` builds on the fatal mode and keeps its additional mountpoint/`HEAD` check.

- Pros: behaviour-preserving; the guard and message live in one place; no flow change (the phase stays `#flow/refactor`).
- Cons: two modes in one helper (mildly less simple than a single predicate).

### B. Have `run_fetch` call `require_git_history` directly

`run_fetch` delegates to `require_git_history` for the single-container case and keeps a volume-existence skip for `--all`.

- Pros: one guard function total; `fetch` gains the stricter "start the container first" diagnostic.
- Cons: changes end-to-end behaviour (new failure mode for existing-but-uninitialized gitdir volumes, including under `fetch --all`), so the phase must be `#flow/redgreen` with new tests pinning the changed semantics; the `--all` path would still need the probe, so not all duplication is removed.

## recommendation

Option A: the duplication being resolved is the copy-pasted guard and message, not the semantics; preserving `run_fetch`'s current failure conditions keeps the refactor safe and the flow tag `#flow/refactor`.

## decision

**Selected: Option A — shared non-fatal probe.** `run_fetch` preserves its current semantics and the phase remains `#flow/refactor`.
