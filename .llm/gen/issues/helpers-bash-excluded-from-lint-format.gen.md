# Issue: `helpers.bash` files are excluded from `make lint` and `make format`

## affected files

- [test/runner.mk](../../../test/runner.mk) — `SHELL_SCRIPTS` definition (line 10)

## description

The `SHELL_SCRIPTS` variable that drives the `lint` (shellcheck) and `format` (shfmt) targets is:

```make
SHELL_SCRIPTS := test/run-suite.sh test/lib.bash test/unit/*.bats test/e2e/*.bats test/canary/*.bats test/timeout/*.bats
```

The globs `test/unit/*.bats` and `test/e2e/*.bats` only match `.bats` files. The two `helpers.bash` files — [test/unit/helpers.bash](../../../test/unit/helpers.bash) and [test/e2e/helpers.bash](../../../test/e2e/helpers.bash) — have a `.bash` extension and are therefore **not** matched. As a result they are never checked by `make lint` or formatted by `make format`.

This was verified: `shfmt -d test/e2e/helpers.bash` reports a formatting deviation (`(( SD_TIMEOUT > 0 ))` vs shfmt's preferred `((SD_TIMEOUT > 0))`), and `shellcheck test/e2e/helpers.bash` reports warnings (SC2034 false positives for nameref variables, SC2016 for intentional single-quoted `bash -c` scripts) that are not surfaced by `make lint`.

## impact

Minor. The `helpers.bash` files contain non-trivial logic (the e2e `sdrun` wrapper, `mk_gpu_shim`, `start_host_http_server`, `run_talkbox`, etc.) and silently drift out of format compliance and escape shellcheck scrutiny. The current shellcheck findings are all benign (false positives or intentional patterns already suppressed in `.bats` files with the same constructs), but future regressions would go undetected.

## suggested fix

Add `test/unit/helpers.bash` and `test/e2e/helpers.bash` to the `SHELL_SCRIPTS` glob, e.g. by including `test/**/helpers.bash` or listing them explicitly. Apply `shfmt -w` once to bring them into compliance and add the same `# shellcheck disable=SC2016,SC2034` suppressions used in the `.bats` files where appropriate.
