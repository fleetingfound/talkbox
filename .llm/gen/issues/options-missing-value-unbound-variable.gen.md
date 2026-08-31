# Issue: Options requiring a value produce raw bash errors instead of talkbox messages

## affected files

- [lib/options.sh](../../../lib/options.sh) — `parse_talkbox_options`, lines handling `--read`, `--write`, `--port`, `--inherit`

## description

The options `--read`, `--write`, `--port` and `--inherit` each consume the next positional argument with `shift` followed by an unguarded `TALKBOX_*+=("$1")` / `TALKBOX_INHERIT="$1"`. Because `talkbox.sh` runs under `set -u`, when one of these options is supplied as the final argument (with no value following), `$1` is unbound and bash aborts with a raw diagnostic:

```
$ onbox --read
/home/alex/talkbox/lib/options.sh: line 33: $1: unbound variable
```

The exit code is 1 (non-zero), so no incorrect action is taken, but the message is not in the `talkbox:` format used everywhere else and exposes an internal file path and line number.

## impact

Minor UX issue. A user who forgets the value for `--read`/`--write`/`--port`/`--inherit` sees a confusing bash internals error rather than a talkbox usage message such as `talkbox: --read requires a value`.

## suggested fix

After `shift`, check that an argument is available before consuming it, e.g. `[[ $# -gt 0 ]] || die "--read requires a value" 2`, or access it via `${1-}` and validate that it is non-empty.
