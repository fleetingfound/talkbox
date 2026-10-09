# Help Flag (`--help` / `-h`)

Adds a help flag to the talkbox commands (`onbox`, `netbox`, `offbox` and `talkbox.sh <container>`), displaying minimal documentation with concise references to the supported container types and command-line options.

## Changes

- [lib/options.sh](../../../lib/options.sh) - new `print_talkbox_help()` printing the shared reference (usage line, the three container types with one-line descriptions, every command-line option, the `-h`/`--help` flag and the `fetch`/`merge`/`sync` git subcommands) to stdout; `parse_talkbox_options` recognises `-h`/`--help` anywhere in the arguments, prints the reference and exits 0 before any mount assembly or podman call.
- [talkbox.sh](../../../talkbox.sh) - the dispatcher accepts `-h`/`--help` as the container argument, so `talkbox.sh --help` and `talkbox.sh -h` print the same reference and exit 0 (the no-argument usage error and unknown-container diagnostics are unchanged).

## Tests

- [test/unit/options.bats](../../../test/unit/options.bats) - three parser tests: `--help` exits 0 with the usage line, container types and option/subcommand references; `-h` is an alias; `--help` is honoured after other options.
- [test/unit/dispatcher.bats](../../../test/unit/dispatcher.bats) - two dispatcher tests: `talkbox.sh --help`/`-h` exit 0 with the reference and no podman call; `talkbox.sh <container> --help` does the same for all three containers.

No existing tests were edited.
