# Phase 20e: unified container action in talkbox.sh and single write-mount parse

#flow/refactor #model/default

## scope

Resolves duplication items §5 and the write-mount double-parse item of §9 of the [duplication and reusable-abstraction review](../../reviews/duplication-abstraction-review.gen.md).

- Implemented:
  - `onbox_action` and `sandbox_action` in [talkbox.sh](../../../talkbox.sh) are merged into one container-parameterised action. The unified action assembles the mount/port/deny-allow arrays once and dispatches on the verb, passing dummy empty write srcs/dsts arrays for `onbox` exactly as the `run_onbox`/`run_recontain` delegates in [lib/containers.sh](../../../lib/containers.sh) already do. The `deny_allow_args` computation is invoked for `onbox` and `netbox` (empty for `offbox`), matching current behaviour. Executor dispatch uses the container-parameterised `run_${container}_*` names, adding onbox-named delegates where only the generic name exists today, so the executor surface documented in [MAP.gen.md](../../../MAP.gen.md) is preserved;
  - the redundant explicit `ensure_base_image` calls in the onbox branches are dropped, since `create_sandbox` and `run_recreate` already perform the same idempotent probe internally for a base source (removing the drift the review identified);
  - the write-mount double parse is eliminated per the [write-mount-parse-once choice](../../choices/write-mount-parse-once.gen.md): `mount_volume_args` in [lib/mounts.sh](../../../lib/mounts.sh) changes signature to accept the precomputed write srcs/dsts arrays (namerefs, as produced by `mount_entries`) instead of re-parsing the defaults file and CLI specs, and `sandbox_action`/the unified action passes the arrays it already computed.
- Deferred: the test-harness duplication items (§10–§16), per instructions.

No aspect of `SPEC.md` changes; this refactors the dispatcher described in `SPEC.md`'s "implementation" section. External-facing behaviour is unchanged: same option parsing, same per-verb execution, same error messages, and `mount_volume_args` emits the identical `-v` volume tokens.

## files to be created

None. Modified: [talkbox.sh](../../../talkbox.sh), [lib/mounts.sh](../../../lib/mounts.sh), [lib/containers.sh](../../../lib/containers.sh) (onbox-named executor delegates if needed). Update the [MAP.gen.md](../../../MAP.gen.md) descriptions of [talkbox.sh](../../../talkbox.sh), [lib/mounts.sh](../../../lib/mounts.sh) and [lib/containers.sh](../../../lib/containers.sh).

## relevant files to be read

- [talkbox.sh](../../../talkbox.sh), [lib/mounts.sh](../../../lib/mounts.sh), [lib/containers.sh](../../../lib/containers.sh), [lib/options.sh](../../../lib/options.sh)
- [test/unit/mounts.bats](../../../test/unit/mounts.bats), [test/unit/netbox-offbox.bats](../../../test/unit/netbox-offbox.bats), [test/unit/containers.bats](../../../test/unit/containers.bats)

## key internal interfaces

- `talkbox.sh` keeps a single container-parameterised action function; `onbox_action`/`sandbox_action` are dropped.
- `mount_volume_args <out-nameref> <container> <srcs-nameref> <dsts-nameref>` replaces the file/project/home/CLI-spec signature. `mount_entries` and `mount_args` are unchanged.
- The `run_*` executor names (including any onbox-named delegates added for uniform dispatch) remain the dispatch surface, per the Phase 19 [consolidation-boundary choice](../../choices/containers-consolidation-boundary.gen.md).

## tests

Unit tests required. Tests to be superseded and removed/rewritten because they exercise the changed `mount_volume_args` internal interface: the four `mount_volume_args` tests in [test/unit/mounts.bats](../../../test/unit/mounts.bats) ("emits netbox write mounts as volumes named `<slug>.netbox.write.<dest-slug>`", "emits offbox write mounts as volumes named `<slug>.offbox.write.<dest-slug>`", "derives the dest-slug from the dest basename path", "merges defaults-file and CLI write specs") and the two `mount_volume_args` call sites in [test/unit/netbox-offbox.bats](../../../test/unit/netbox-offbox.bats) (around lines 231–232 and 334–335) — these are rewritten to build the srcs/dsts arrays first and then assert the same emitted volume tokens. The pinning pass must otherwise capture current dispatcher behaviour at the unit level where practical (e.g. the parse-once invariant is not directly observable; the e2e suite covers the dispatcher end-to-end). End-to-end tests are not otherwise affected: the existing [test/e2e](../../../test/e2e) suite must keep passing unchanged.
