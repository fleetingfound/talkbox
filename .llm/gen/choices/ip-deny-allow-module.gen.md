# IP deny/allow module structure

Where the parsing of `defaults/deny.ip` / `defaults/allow.ip` and the `--deny-ip` / `--allow-ip` arguments, plus the effective-set computation (deny minus allow minus always-allowed) and the firewall-rule application, should live.

This follows the functional-split convention established by the existing `lib/` modules (`lib/ports.sh`, `lib/mounts.sh`, etc.).

## Option A: new module `lib/netfilter.sh` (Recommended)

A dedicated `lib/netfilter.sh` mirrors `lib/ports.sh`: it parses the deny/allow files and CLI arguments (reusing the same blank-line/comment-line conventions as the other defaults files), computes the effective deny set, and exposes a function that applies the firewall ruleset to a container's network namespace. `talkbox.sh` sources it alongside the other libs and the action functions call it from the onbox/netbox executors.

**Pros:** keeps `lib/ports.sh` focused on port forwarding; the deny/allow logic (parsing + set arithmetic + rule application) is cohesive and independently unit-testable by sourcing the file alone, matching the pattern of `lib/ports.sh`; consistent with the [Module Structure](module-structure.gen.md) choice.
**Cons:** one more file to source.

## Option B: extend `lib/ports.sh` (rename to `lib/network.sh`)

Fold IP deny/allow parsing and rule application into the existing ports module, renaming it to `lib/network.sh` to reflect its broader scope.

**Pros:** single networking module; no new file.
**Cons:** renames a file that is referenced across `talkbox.sh`, `lib/containers.sh` and many unit tests, churning the whole repo for an additive feature; conflates two distinct concerns (port forwarding vs. destination filtering); larger diff than the value it adds.

## Option C: inline in `lib/containers.sh`

Put the parsing and rule application directly in `lib/containers.sh` next to the executors.

**Pros:** no new file; logic sits next to its only caller.
**Cons:** `lib/containers.sh` is already the largest module; the pure parsing/set-arithmetic logic loses its independent unit-testability; violates the functional-split convention.

## Selected

Option B — extend and rename `lib/ports.sh` to `lib/network.sh`, folding in deny/allow parsing, effective-set computation and firewall-rule application. Confirmed by user.
