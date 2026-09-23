# Choice: ASCII art file format and storage

#flow/unified

## Context

Distinct ASCII art files are needed for `onbox`, `netbox` and `offbox`. The art must support ANSI SGR sequences such as `\033[0;34m` for colours. Two sub-questions arise: where the art files are stored in the repository, and how escape sequences are represented within those files so that colours render correctly when displayed.

The existing `defaults/` directory holds repo-provided, runtime-read configuration files (`read.mounts`, `write.mounts`, `ports`, `deny.ip`, `allow.ip`, `dotfiles/`). The host-side executor (per the companion choice [ASCII art display location](ascii-art-display-location.gen.md), Option A) will read the art file from `$TALKBOX_ROOT` and print it to the terminal.

## Option A — `defaults/art/` with `\033` notation interpreted by `printf '%b'` (Recommended)

Store three files in `defaults/art/` — `onbox.txt`, `netbox.txt`, `offbox.txt` — containing ASCII art with ANSI SGR sequences written in `\033` octal notation (e.g. `\033[0;34m`). The display helper reads the file content and passes it through `printf '%b'`, which interprets `\033` (and other backslash escapes) into the raw ESC byte so the terminal renders colours. A trailing `\033[0m` reset is expected in each file.

- `\033` notation is human-editable in any text editor; the escape sequences are visible as text, not as invisible control bytes.
- `printf '%b'` is a POSIX builtin, already used effectively elsewhere in the codebase's shell scripts; no external dependency.
- `defaults/art/` follows the established `defaults/` pattern (repo-provided assets read at runtime from `$TALKBOX_ROOT`), keeping art alongside other runtime-read defaults.
- The file extension `.txt` avoids any special handling by `shfmt` or ShellCheck (which target `.sh`/`.bash`).

## Option B — `defaults/art/` with raw ESC bytes displayed by `cat`

Same storage location, but the art files contain literal raw escape bytes (the actual `0x1b` character) rather than `\033` text. The display helper simply `cat`s the file.

- `cat` is the simplest possible display mechanism.
- But raw ESC bytes are invisible in most text editors, making the art hard to author, review and diff. A reviewer cannot see which colour a given line is without piping through `cat -v`.
- Git diffs are opaque (binary-looking) for lines containing raw escapes.

## Option C — `art/` at the repo root with `\033` notation

Store the files under a top-level `art/` directory rather than under `defaults/`, using `\033` notation and `printf '%b'` for display.

- Separates art (a static asset) from `defaults/` (runtime configuration).
- However, the distinction is marginal: `defaults/dotfiles/` already contains static assets (dotfiles), so `defaults/` is not purely config. A new top-level directory adds a navigation cost for no clear benefit.

## Selection

**Option A** — `defaults/art/` with `\033` notation interpreted by `printf '%b'`. (Selected, per user.)
