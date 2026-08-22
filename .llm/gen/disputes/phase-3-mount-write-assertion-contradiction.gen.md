# Dispute: netbox/offbox write-mount assertions are internally contradictory

Linked plan: [phase-3-netbox-offbox.gen.md](../plans/phase-3-netbox-offbox.gen.md)

Two unit tests in `test/unit/netbox-offbox.bats` each contain a set of assertions that cannot all hold simultaneously, regardless of the implementation. Each test asserts both that the read-only read bind-mount `.../talkbox/wdata:ro` is present and that no argument contains the substring `/talkbox/wdata:ro` — but the read bind-mount element itself contains that substring.

## Disputed tests

### `netbox plan keeps read mounts read-only and write mounts as volumes`

- Test file: [test/unit/netbox-offbox.bats](../../../test/unit/netbox-offbox.bats)
- Failing assertion (line 142): `array_has_none '/talkbox/wdata:ro' "${args[@]}"`
- Exact failure output:

```
not ok 11 netbox plan keeps read mounts read-only and write mounts as volumes
# (from function `array_has_none' in file test/unit/netbox-offbox.bats, line 28,
#  in test file test/unit/netbox-offbox.bats, line 142)
#   `array_has_none '/talkbox/wdata:ro' "${args[@]}"' failed
```

- Related core files: [lib/containers.sh](../../../lib/containers.sh) (`plan_netbox`), [lib/mounts.sh](../../../lib/mounts.sh) (`mount_args`, `mount_volume_args`)

### `offbox plan emits write-mount volumes and read-only read mounts`

- Test file: [test/unit/netbox-offbox.bats](../../../test/unit/netbox-offbox.bats)
- Failing assertion (line 210): `array_has_none '/talkbox/wdata:ro' "${args[@]}"`
- Exact failure output:

```
not ok 18 offbox plan emits write-mount volumes and read-only read mounts
# (from function `array_has_none' in file test/unit/netbox-offbox.bats, line 28,
#  in test file test/unit/netbox-offbox.bats, line 210)
#   `array_has_none '/talkbox/wdata:ro' "${args[@]}"' failed
```

- Related core files: [lib/containers.sh](../../../lib/containers.sh) (`plan_offbox`), [lib/mounts.sh](../../../lib/mounts.sh) (`mount_args`, `mount_volume_args`)

## Justification

Each test creates a read mount and a write mount for the *same* dest `/talkbox/wdata` (`mount_args ... '/host/data:/talkbox/wdata'` and `mount_volume_args ... '/host/data:/talkbox/wdata'`) and then asserts:

1. `array_contains '/host/data:/talkbox/wdata:ro'` — the read-only read bind-mount must be emitted (per [SPEC.md §netbox/§offbox](../../../SPEC.md) "every read mount as a read-only bind-mount");
2. `array_contains 'talkbox-proj.{netbox,offbox}.write.talkbox-wdata:/talkbox/wdata'` — the read-write write volume must be emitted;
3. `array_has_none '/talkbox/wdata:ro'` — no element may contain the substring `/talkbox/wdata:ro`.

`array_has_none` performs a per-element substring match (`[[ "$element" == *"$needle"* ]]`). The element from assertion 1, `/host/data:/talkbox/wdata:ro`, contains the substring `/talkbox/wdata:ro`, so assertion 3 fails whenever assertion 1 holds. There is no argument-list assembly that can satisfy assertions 1 and 3 simultaneously, so the test cannot pass under any implementation.

The implementation satisfies assertions 1 and 2 and matches the plan and SPEC exactly: read mounts are emitted as read-only bind-mounts (`-v /host/data:/talkbox/wdata:ro`) and write mounts as read-write volumes without `:ro` (`-v talkbox-proj.netbox.write.talkbox-wdata:/talkbox/wdata` / `talkbox-proj.offbox.write.talkbox-wdata:/talkbox/wdata`). The intent of assertion 3 is clearly to verify that the write-volume mount is not read-only; the needle should have been scoped to the write-volume element, e.g. `array_has_none 'talkbox-proj.netbox.write.talkbox-wdata:/talkbox/wdata:ro'` (and the offbox analogue), rather than the dest-wide substring `/talkbox/wdata:ro`.
