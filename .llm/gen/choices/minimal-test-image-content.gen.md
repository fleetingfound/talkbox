# Choice: Content and base of the minimal test image

## context

The minimal test image must provide everything the e2e suite exercises inside containers, and nothing the suite does not need. Verified in-container usage across `test/e2e/*.bats`:

- `bash`/`sh` (commands, `expect`-driven interactive shells, the `.bashrc` banner/prompt from the bind-mounted dotfiles, which also uses `clear`, `cat`, `git`)
- `git` including `git-upload-pack` (git transport, merge/sync, identity tests, the setup.sh gitdir init and the uploadpack hook test)
- `curl` (internet-access probes against `https://example.com` and the deny/allow probes against `http://1.1.1.1/` and loopback HTTP servers)
- `cp`, `cat`, `head`, `grep`, `chmod`, `touch`, `printf`, `pwd`, `test`, `sleep` (coreutils; `sleep infinity` is the container command)
- the `dev` user/group with uid/gid 1000 and a writable `/home/dev` (the containers run with `--userns=keep-id:uid=1000,gid=1000`; `image/setup.sh` copies dotfiles into `/home/dev/`)
- `/working` owned by `dev` (the `--workdir=/working/<project-base>` create argument)
- `setup.sh` at `/usr/local/bin/setup.sh` per the spec's image contract (although persistent containers bind-mount it read-only, the image contract includes it)

No test uses `sudo`, `less`, `neovim`, `tmux`, `fzf`, `tree`, `wget`, `node`, `npm`, `uv`, `python` (in-container), or any of the installed coding agents. The `.bashrc` references `claude`/`opencode` only through dormant aliases and sets `EDITOR=vi`, which no test invokes. `nft` is not needed in the image — the deny/allow ruleset is applied from the host via `podman unshare nsenter` into the container netns.

## options

### Option 1: Debian-slim base with `git`, `curl`, `ca-certificates` (Recommended)

`FROM debian:trixie-slim` (the same base as the production image), `apt-get install git curl ca-certificates` (plus the dev user/group 1000, `/working`, `COPY setup.sh`, `USER dev`, `WORKDIR /working`, `ENV LANG=C.UTF-8` — mirroring the production image's structure). Everything else the suite needs (bash, coreutils, grep, findutils, `clear` from ncurses-bin) is already in the Debian base as required-priority packages.

- Userland parity with production: same bash, same coreutils, same git packaging — the behaviour under test is not distorted by a different distro.
- `ca-certificates` is required for the `https://example.com` probes; `curl` for all network probes; `git` for all git tests.
- Fast build: one small apt layer, no external copy stages (`uv`, `node`), no agent installs.
- Keeps the image contract from the spec (`setup.sh` included, dev user, `/working`).

### Option 2: multi-stage `test` target in the production Containerfile

Add an early stage to [image/Containerfile](../../../image/Containerfile) (common structure up to the dev user and `setup.sh` COPY) and build tests with `--target`.

- Single source of truth for the shared image structure (user, setup.sh, `/working`).
- Test concerns leak into the production artifact; the production file's complexity grows for a purely test-driven reason.
- The production build must keep producing the same image; stage interleaving risks accidental drift.

### Option 3: Alpine-based tiny image

`FROM alpine` with `bash git curl` installed.

- Smallest and fastest to pull/build.
- Different userland (busybox `sh`, `ash` semantics, different `useradd`, no `/bin/bash` by default) — parity with the production Debian image is lost, and interactive-shell/`.bashrc`/setup behaviour under test could diverge from production.
- uid/gid 1000 user creation and `--userns=keep-id` semantics need re-verification against a different base.

## recommendation

**Option 1.** Debian-slim with `git curl ca-certificates` keeps the behaviour under test identical to production (same distro, same packaging) while cutting the build to a single small apt layer. The e2e suite's in-container footprint is fully covered by those packages plus the Debian base; every heavier dependency in the production image exists for interactive agent use that tests never exercise.

## selected

**Option 1 (user-selected): Debian-slim base with `git`, `curl`, `ca-certificates`.**

`FROM debian:trixie-slim` (same base as production), `apt-get install git curl ca-certificates`, the `dev` user/group (uid/gid 1000, bash shell), `/working` owned by `dev`, `COPY setup.sh` to `/usr/local/bin/setup.sh`, `USER dev`, `WORKDIR /working`, `ENV LANG=C.UTF-8`. No sudo, editors, terminal tools, runtimes or coding agents — everything else the e2e suite needs is required-priority in the Debian base.
