> [!WARNING]
> talkbox is experimental software. Podman containers simplify deployment and support GPU access, but they offer weaker isolation than virtual machines and may be more vulnerable to to security exploits. Do not use talkbox as the only security layer.

# talkbox

## design goals

This project enables the contents of a working repository `<project>/` from the host machine to be edited in a sandboxed environment while preventing access to the rest of the host system.

This enables the use of coding agents while preventing unwanted edits and protecting private data.

Three commands are provided:

- `onbox` creates a container which **allows** internet access and direct edits to `<project>/` on the host.
- `netbox` creates a container which **allows** internet access and **disables** direct edits to the host.
- `offbox` creates a container which **disables** internet access and edits to the host, while still allowing explicitly specified ports on the local host to be accessed.

The project assumes that Git will be used to review changes being made by the agent. The host subfolder `<project>/.git/` is mounted as read only, where it is available as a remote called `host`. Each container commits to a git directory of its own. This ensures that the host's git history remains intact and also mitigates security concerns by ensuring:

- changes to the repository remain visible (via `git diff`)
- the host's configs, remotes and hooks cannot be changed
- a clear separation between "safe" and "dangerous" branches of the git repository can be maintained

This project enables two possible Git workflows:

- **Git Workflow 1:** The `onbox` container is used to edit the working tree and all changes to Git history are made on the host.
- **Git Workflow 2:** Any of the `onbox`, `netbox` or `offbox` containers are used to edit git history which is then reviewed and synchronized from the host side using commands such as: `onbox merge`, `onbox sync`, `netbox merge`, `netbox sync`, `offbox merge`, `offbox sync`.

Changes to the git history within a container are transferred to the host only via git bundles, preventing content such as git configs and hooks being inadvertently transferred from the container to the host.

A host folder which is not tracked by git may be edited with the `onbox` image, in which case git-related `talkbox` commands will not be available.

The intention of `offbox` is to enable the use of local coding agents and untrusted code with sensitive data.

It is possible to start with `onbox` or `netbox` and then switch to `offbox` in the same repository, in which case installed packages will persist because of a cloned home volume. This enables an `offbox` environment to be prepared with internet access using `onbox` or `netbox`.

## development

This repository was developed from the specifications given in [SPEC.md](SPEC.md), using the Opencode configuration [zettel-agents](https://github.com/fleetingfound/zettel-agents/), which implements red/green test-driven development.

## references

- [Github - Correct way to create a podman-network that can only communicate to services bound on localhost #22570](https://github.com/podman-container-tools/podman/discussions/22570?utm_source=chatgpt.com#discussioncomment-9438485)
- [TAAG](https://patorjk.com/software/taag/) by `patorjk` was used to generate the ascii art, with font `Rebel` by Valerie Mates
- [A field guide to sandboxes for AI](https://www.luiscardoso.dev/blog/sandboxes-for-ai) by Christian Weiss
