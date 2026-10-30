# Choice: Failure-path stops under concurrent sessions

## context

`run_container` has failure paths that call `stop_and_die` (nft deny install failure via `install_nft_deny_or_die`, `setup.sh` failure via `run_setup_in_container`) and `rollback_creation_and_die` (plan failure in `create_sandbox`/`run_recreate`). Each of these stops the container unconditionally, killing other live sessions' execs mid-command — the same hazard the session-exit fix addresses for normal exits.

## options

### Option A: Keep unconditional stops on failure paths (Recommended)

Failure stops (`stop_and_die`, `rollback_creation_and_die`) remain unconditional.

- **Pros:** A container with an unenforceable deny list (nft failure) or a broken setup is unsafe to leave running — for `onbox` it can write the host worktree, and the deny list may be unenforced; stopping it is the safe outcome. The condition is terminal for the environment's guarantees, so killing concurrent sessions is justified.
- **Cons:** A session failing its setup while another session is live kills the other session.

### Option B: Session-aware failure stops

Failure paths stop the container only when no other sessions are attached (using the session registry from the concurrent-session-stop choice).

- **Pros:** Sparing live sessions.
- **Cons:** Leaves a container running in a demonstrably broken or unenforced state (security risk for nft failure), with sessions attached to it; merely defers the failure to whichever session exits last.

## recommendation

**Option A.** Failure means the container is unusable or unsafe to keep running; stopping it is the correct outcome even at the cost of concurrent sessions.

## selected option

**Option A** (selected by the user).
