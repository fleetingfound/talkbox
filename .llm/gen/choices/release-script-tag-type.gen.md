# Choice: Tag type and tag message for the release tags

## context

The release automation must tag the release commit on `main` (as `v<version>`) and the corresponding commit on `dev` (as `dev/v<version>`). The current repository uses lightweight tags (`v0.1.2` and `dev/v0.1.2` point directly at commits, carrying no message of their own). The request asks for "a lightweight tag with a message matching the commit message on main", which is contradictory: lightweight (lightweight) tags cannot carry a message; only annotated tags can. This choice decides the tag type and where the message lives.

## options

### A. Lightweight tags on both branches (Recommended)

Tag `v<version>` on the new main commit and `dev/v<version>` on the dev commit, both as lightweight tags (pointers, no message), exactly matching current practice. The release message lives on the main commit itself, which carries the notes and the `Commit: <hash>` trailer; the tag is just a stable name for the release.

- Pros: matches existing repository practice (`v0.1.2`, `dev/v0.1.2` are lightweight); no message duplication; the "message matching the commit message on main" is trivially satisfied by the commit itself; simple to implement and verify.
- Cons: `git tag -l` / `git show <tag>` shows no message text of its own; if a message was genuinely wanted on the tag object, this does not provide it.

### B. Annotated tag on main with the main commit message, lightweight tag on dev

Create an annotated tag `v<version>` on the main commit whose tag message reproduces the main commit message, and a lightweight `dev/v<version>` on the dev commit.

- Pros: the tag object literally carries a message matching the main commit message, satisfying the "message" reading of the request.
- Cons: diverges from the current lightweight practice; duplicates the commit message into a tag object; annotated tags need GPG-free `git tag -a -F`, and `git describe`/history behave slightly differently.

### C. Lightweight tags, but the main commit message is the "message" referred to

As A, with the interpretation that the "message matching the commit message on main" is simply satisfied because lightweight tags display their target commit's message via `git show <tag>`.

- Pros: identical to A in mechanics; the wording is read as describing where the message comes from rather than a tag-object message.
- Cons: identical to A; distinguished only by interpretation.

## selection

Selected: **A. Lightweight tags on both branches** (lightweight `v<version>` on the new main commit, lightweight `dev/v<version>` on the dev commit; the message lives on the main commit itself, as in current practice).
