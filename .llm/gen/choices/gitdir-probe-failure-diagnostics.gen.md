# Choice: gitdir probe failure diagnostics

## Context

With a podman-backed probe (see [gitdir history probe mechanism](gitdir-history-probe-mechanism.gen.md)), three outcomes are possible: the probe command exits 0 (`HEAD` present), exits with the probe's own failure code (`HEAD` absent), or the `podman run` itself fails (image missing, volume access failure, remote connection failure). The current code conflates transport failures with "no history" because inspect stderr is discarded.

## Option A (Recommended): three-way exit-code interpretation with surfaced stderr

Interpret the probe outcome: exit 󠀠0 = history present; the probe's own "not found" exit code = die with the existing `no git history in the <container> gitdir volume; start the container first` message; any other `podman run` exit status or start failure = die with a distinct message naming the container and the gitdir volume and surfacing the podman stderr (e.g. captured to a temporary file or stderr passthrough). Genuine podman failures stop conflating with the "no history" message.

## Option B: uniform "no git history" message on any probe failure

Map every probe failure to the existing message. Simplest, but a broken podman connection keeps reporting "start the container first" misleadingly — the very defect being fixed for the inspect path.

## Recommendation

Option A: it directly implements the issue's requirement to make genuine failures distinguishable from missing history.

## Selection

**Option A: three-way exit-code interpretation with surfaced stderr.** Selected by the user.
