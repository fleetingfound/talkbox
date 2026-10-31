# Choice: Whether the release script pushes branches and tags to remotes

## context

The repository carries `gh` (github remote) and `origin` (local mirror) remotes for both `main` and `dev`. The release script creates a commit on `main` and two tags. Whether it should also push them to the remotes after creating them affects how much it does on the user's behalf.

## options

### A. No push; push left to the user (Recommended)

The script stops after the commit and tags; the user pushes `main`, `dev` (if desired) and the tags with `git push --follow-tags` or however they choose.

- Pros: the script performs only local, reversible operations; a bad release message can be fixed before anything is published; the heterogeneous remotes (`gh` vs `origin`, and origin holding many other refs) keep explicit user control over what is pushed where.
- Cons: an extra manual step.

### B. Push on completion

After the commit and tags, push `main` and both tags to every remote that has a matching branch (`gh`, `origin`), and `dev` only if it is not already pushed.

- Cons: irreversibility on completion; publishing is a policy decision the script should not own; pushing `dev` may be unwanted.

## selection

Selected: **A. No push** (the script performs local operations only; pushing branches and tags is left to the user).
