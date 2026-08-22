# Verdict: netbox/offbox write-mount assertions are internally contradictory

Linked dispute: [phase-3-mount-write-assertion-contradiction.gen.md](../disputes/phase-3-mount-write-assertion-contradiction.gen.md)

Linked plan: [phase-3-netbox-offbox.gen.md](../plans/phase-3-netbox-offbox.gen.md) — summarised in one sentence: the plan implements `netbox`/`offbox` containers whose read mounts are read-only bind-mounts and whose write mounts are read-write named volumes, with all required inheritance and networking behaviour.

No new issue documents were created: the disputed behaviour was entirely a test bug and was resolved during this mediation; the implementation in [lib/mounts.sh](../../../lib/mounts.sh) and [lib/containers.sh](../../../lib/containers.sh) already satisfies the SPEC and plan.

## Test 1: `netbox plan keeps read mounts read-only and write mounts as volumes`

- Test file: [test/unit/netbox-offbox.bats](../../../test/unit/netbox-offbox.bats)
- Verdict: `BROKEN_TEST`

### Justification

The test, in the same body, asserts all three of the following on the assembled `plan_netbox` argument list:

1. `array_contains '/host/data:/talkbox/wdata:ro' "${args[@]}"` — the read-only read bind-mount must be emitted.
2. `array_contains 'talkbox-proj.netbox.write.talkbox-wdata:/talkbox/wdata' "${args[@]}"` — the read-write write volume must be emitted.
3. `array_has_none '/talkbox/wdata:ro' "${args[@]}"` — no element may contain the substring `/talkbox/wdata:ro`.

`array_has_none` performs a per-element substring match (`[[ "$element" == *"$needle"* ]]`). The element from assertion 1, `/host/data:/talkbox/wdata:ro`, contains the substring `/talkbox/wdata:ro`, so assertion 3 fails whenever assertion 1 holds. No argument-list assembly can satisfy assertions 1 and 3 simultaneously, regardless of implementation.

This contradicts [SPEC.md](../../../SPEC.md), which mandates for `netbox`:

> - every read mount as a read-only bind-mount (read-only bind-mount)
> - every write mount as a read-write volume (read-write volume)

and:

> The `netbox` container is never given write access to the host system. Every mount it receives is either a read-only bind-mount or a volume.

A read-only bind-mount such as `/host/data:/talkbox/wdata:ro` is *required* by the SPEC, so assertion 3 (which forbids the `:ro` suffix anywhere the dest `/talkbox/wdata` appears) cannot be consistent with the SPEC.

### Repair

The intent of assertion 3 was to verify that the *write volume* mount is not read-only, not to forbid any `:ro` suffix on the shared dest. The needle was therefore rescoped to the write-volume element only:

```bash
array_has_none 'talkbox-proj.netbox.write.talkbox-wdata:/talkbox/wdata:ro' "${args[@]}"
```

This weakens the test only to the minimum extent required to align it with the SPEC and plan; the read-only read bind-mount assertion (1) and the read-write write-volume assertion (2) are unchanged.

## Test 2: `offbox plan emits write-mount volumes and read-only read mounts`

- Test file: [test/unit/netbox-offbox.bats](../../../test/unit/netbox-offbox.bats)
- Verdict: `BROKEN_TEST`

### Justification

Identical internal contradiction to Test 1, applied to `plan_offbox`. The test asserts simultaneously:

1. `array_contains '/host/data:/talkbox/wdata:ro' "${args[@]}"` — read-only read bind-mount emitted.
2. `array_contains 'talkbox-proj.offbox.write.talkbox-wdata:/talkbox/wdata' "${args[@]}"` — read-write write volume emitted.
3. `array_has_none '/talkbox/wdata:ro' "${args[@]}"` — no element may contain `/talkbox/wdata:ro`.

As above, the element from assertion 1 contains the substring forbidden by assertion 3, so the test cannot pass under any implementation.

This contradicts [SPEC.md](../../../SPEC.md), which mandates for `offbox`:

> - every read mount as a read-only bind-mount (read-only bind-mount)
> - every write mount as a read-write volume (read-write volume)

and:

> The `offbox` container is never given write access to the host system. Every mount it receives is either a read-only bind-mount or a volume.

### Repair

The needle of assertion 3 was rescoped to the write-volume element only:

```bash
array_has_none 'talkbox-proj.offbox.write.talkbox-wdata:/talkbox/wdata:ro' "${args[@]}"
```

Assertions 1 and 2 are unchanged.

## Verification

After repair, both tests pass:

- `make test-unit` — `total=117 pass=117 fail=0 skip=0 exit=0`.
- `make test-e2e` — `total=33 pass=33 fail=0 skip=0 exit=0`.

Every remaining failure (none) would be attributable to the project implementation rather than to a test error or timeout.
