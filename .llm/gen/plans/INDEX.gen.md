# Plans

Implementation plan for `SPEC.md`, in recommended order. Each phase builds on the previous one; by Phase 5 every aspect of `SPEC.md` is implemented.

- [x] [Phase 1: onbox minimal working application](phase-1-onbox-minimal.gen.md) #flow/redgreen #model/default
- [x] [Phase 1a: Planner truthfulness — project-dotfiles existence in plan_onbox](phase-1a-planner-dotfiles-truthfulness.gen.md) #flow/redgreen #model/default
- [x] [Phase 1b: Test-suite revision — correctness, timeouts and coverage gaps](phase-1b-test-suite-revision.gen.md) #flow/pin #model/default
- [x] [Phase 1c: Scaffold refactor — array-based planner and style fixes](phase-1c-scaffold-refactor.gen.md) #flow/unified #model/default
- [x] [Phase 2: mounts, ports and onbox lifecycle management](phase-2-mounts-ports-lifecycle.gen.md) #flow/redgreen #model/default
- [x] [Phase 3: netbox and offbox containers](phase-3-netbox-offbox.gen.md) #flow/redgreen #model/default
- [x] [Phase 4: git integration (onbox/netbox/offbox) and fetch](phase-4-git-integration-fetch.gen.md) #flow/redgreen #model/default
- [x] [Phase 4a: Planner/executor lifecycle symmetry + run-plan cleanup](phase-4a-planner-executor-symmetry.gen.md) #flow/redgreen #model/default
- [x] [Phase 5: git merge and sync](phase-5-merge-sync.gen.md) #flow/redgreen #model/default
- [x] [Phase 5a: git transport error diagnostics](phase-5a-error-diagnostics.gen.md) #flow/redgreen #model/default
- [x] [Phase 5b: git transport behavioural alignment](phase-5b-behavioural-alignment.gen.md) #flow/redgreen #model/default
- [x] [Phase 5c: git transport coverage gaps](phase-5c-coverage-gaps.gen.md) #flow/pin #model/default
- [x] [Phase 6a: Fix e2e --port TOCTOU race](phase-6a-e2e-port-toctou-fix.gen.md) #flow/pin #model/default
- [x] [Phase 6b: Rename `parse_onbox_options` to `parse_talkbox_options`](phase-6b-rename-parse-talkbox-options.gen.md) #flow/unified #model/default
- [x] [Phase 6c: Replace `execute_fetch_plan` with two-array `plan_fetch` output](phase-6c-execute-fetch-plan-two-array.gen.md) #flow/unified #model/default
- [x] [Phase 6d: Increase `podman stop` grace period to 5 seconds](phase-6d-podman-stop-grace-period.gen.md) #flow/unified #model/default
- [x] [Phase 7: GPU support (`--gpu` flag)](phase-7-gpu-support.gen.md) #flow/redgreen #model/default
- [x] [Phase 8a: Lifecycle verbs remove and recreate named volumes](phase-8a-lifecycle-named-volume-cleanup.gen.md) #flow/redgreen #model/default
- [ ] [Phase 8b: Options requiring a value emit talkbox messages instead of raw bash errors](phase-8b-options-missing-value-diagnostics.gen.md) #flow/redgreen #model/default
- [ ] [Phase 8c: Bring `helpers.bash` files under `make lint` and `make format`](phase-8c-helpers-bash-lint-format.gen.md) #flow/unified #model/default
