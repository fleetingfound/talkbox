# E2e run wrapper mechanism

How the ~16 hand-rolled `sdrun bash -c 'cd "$1" && …'` invocations across the e2e suite (review §15) are routed through the shared helpers.

The existing `run_talkbox` helper covers the plain `cd <project> && <talkbox>/talkbox.sh <args…>` case, but the hand-rolled sites fall into three groups: plain invocations not yet converted (drift), invocations that additionally prepend a shim directory to `PATH` before calling `talkbox.sh` (the GPU/nft-logging tests), and one invocation of a symlinked `onbox` executable rather than `talkbox.sh`.

Note that `sdrun` propagates the caller's `PATH` via `-E "PATH=$PATH"`, so a caller-side `PATH="<shimdir>:$PATH" run_talkbox …` prefix would already reach the wrapped command without any helper change.

## Options

### A. Extend `run_talkbox` plus a symlink helper (Recommended)

Extend `run_talkbox` with an optional mechanism to prepend a directory to the wrapped command's `PATH` (e.g. an optional shim-directory argument), and add one sibling helper for invoking talkbox through a differently-named executable (the symlink case). Convert all hand-rolled sites.

- Pros: the PATH override is explicit in the helper signature rather than relying on a subtle propagation property; one helper family covers all sites.
- Cons: `run_talkbox`'s argument list grows an optional leading form.

### B. Caller-side PATH prefixing plus a symlink helper

Selected: **A. Extend `run_talkbox` plus a symlink helper.**

Convert the plain sites to `run_talkbox` as-is, rely on `PATH="<shimdir>:$PATH" run_talkbox …` propagation for the shim sites, and add only the symlink-invocation helper.

- Pros: no change to the existing helper signature; fewest new helpers.
- Cons: the shim sites' correctness depends on remembering that `sdrun` copies the ambient `PATH`; easy to break in future edits.

### C. Leave hand-rolled sites

Keep the ~16 sites as they are.

- Pros: no change.
- Cons: leaves ~15 `# shellcheck disable=SC2016` sites and the per-site drift risk the review flags.
