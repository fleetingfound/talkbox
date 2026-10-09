> [!WARNING]
> talkbox is experimental software. Podman containers simplify deployment and support GPU access, but they offer weaker isolation than virtual machines and may be more vulnerable to security exploits. Do not use talkbox as the only security layer.

# talkbox

## design goals

This project enables the contents of a git repository to be edited in a sandboxed environment while preventing access to the host.

Running `onbox` inside a git repository `<project>/` will start a podman container with `<project>/` bind-mounted. With `onbox`:

- the working tree of `<project>/` can be edited directly in the container
- the container has its own git history and the host's git history is available from inside the container as a remote (`host`)

This project supports two possible workflows:

- **Git Workflow 1:** The `onbox` container is used to edit the working tree and all changes to git history are made on the host.
- **Git Workflow 2:** The container is used to edit git history which is then reviewed and synchronized from the host side using the subcommands `merge` or `fetch`.

Inside the container, only read-access is granted to the host's `.git/` folder. This ensures:

- the host's git history remains intact
- changes to the repository remain visible (via `git diff`)
- the host's git config, remotes and hooks cannot be changed
- a clear separation between _"safe"_ and _"potentially unsafe"_ branches of the git repository can be maintained

Changes to the git history within a container are transferred to the host only via git bundles, preventing content such as git configs and hooks being inadvertently transferred from the container to the host.

Unlike the `onbox` container, the `netbox` and `offbox` containers receive separate working trees from the host. Changes made in those containers are only brought to the host via the `merge` or `fetch` subcommands.

While `netbox` receives internet access, `offbox` is disconnected from the internet in order to support running untrusted code or using local coding agents on sensitive data.

If the `offbox` container is created after an `onbox` or `netbox` containers has been created, then it inherits the underlying system including any packages that were installed in the previous containers. This enables an `offbox` environment to be prepared with internet access.

Any of `onbox`, `netbox` or `offbox` may be used with **Git Workflow 2**.

A host folder which is not tracked by git may be edited with the `onbox` container, in which case git-related `talkbox` functionality will not be available.

| container | shares host working tree | internet access | access to specified host localhost ports |
|-----------|------------------------------------------|-----------------|------------------------------------------|
| `onbox`   | ✅                                       | ✅              | ✅                                       |
| `netbox`  | ❌                                       | ✅              | ✅                                       |
| `offbox`  | ❌                                       | ❌              | ✅                                       |

## development

This repository was developed from the specifications given in [SPEC.md](SPEC.md), using the OpenCode configuration [zettel-agents](https://github.com/fleetingfound/zettel-agents/), which implements red/green test-driven development.

The [development branch](https://github.com/fleetingfound/talkbox/tree/dev) includes the [prompts](https://github.com/fleetingfound/talkbox/tree/dev/.llm/prompts) which were used to develop this repository, alongside additional [generated plain-text artifacts](https://github.com/fleetingfound/talkbox/tree/dev/.llm/gen) produced during development.

## references

- [Github - Correct way to create a podman-network that can only communicate to services bound on localhost #22570](https://github.com/podman-container-tools/podman/discussions/22570?utm_source=chatgpt.com#discussioncomment-9438485)
- [TAAG](https://patorjk.com/software/taag/) by `patorjk` was used to generate the ascii art, with font `Rebel` by Valerie Mates
- [A field guide to sandboxes for AI](https://www.luiscardoso.dev/blog/sandboxes-for-ai) by Christian Weiss
