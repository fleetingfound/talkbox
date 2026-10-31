# Choice: How the user customizes the release notes in the main commit message

## context

The main commit message carries the version number in its subject (`talkbox v<version>`), release-note bullets, and a trailing `Commit: <dev-hash>` line. Currently the release notes are hand-written when the main commit is crafted by hand. The release script must provide an opportunity for the user to add additional release notes before the commit is created.

## options

### A. Editor session over a template message (Recommended)

The script writes a template message (subject `talkbox v<version>`, blank line, placeholder notes section, trailing `Commit: <dev-hash>` line) to a temporary file, opens it in `$GIT_EDITOR`/`$EDITOR`, and re-reads it after the editor exits. The script aborts if the user leaves the template unedited-empty or exits non-zero. This mirrors `git commit -e` semantics.

- Pros: matches how release notes are authored today; allows free-form multi-line notes; no message-size quoting problems; the `Commit:` trailer is guaranteed present because the script appends/validates it.
- Cons: requires an interactive terminal; less scriptable in CI.

### B. Notes passed as flags/argv

The script accepts the release notes as flags (e.g. `-m <msg>`/`--notes` lines) or arguments and composes the message non-interactively, with a fallback template of no notes.

- Pros: scriptable; no interactive prompt.
- Cons: does not match "opportunity to customize" as naturally; multi-line notes via flags are awkward.

### C. Non-interactive with a default message

The script composes a default message (subject + `Commit:` trailer, no notes) and commits it directly, with the user amending afterwards (`git commit --amend` on main) if they want notes.

- Pros: simplest implementation.
- Cons: no real in-flow customization; amending main afterwards defeats automation.

## selection

Selected: **A. Editor over template** (message template written to a temp file, opened in $GIT_EDITOR/$EDITOR, re-read afterwards; the `Commit:` trailer is preserved/validated).
