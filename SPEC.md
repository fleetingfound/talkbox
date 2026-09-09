# talkbox (specification)

## design goals

This project enables the contents of a working repository `<project>/` from the host machine (where it is the current working directory) to be edited in a sandboxed environment while preventing access to the rest of the host system.

This enables the use of coding agents while preventing unwanted edits to the host and protecting private data.

The commands provided are `onbox`, `netbox` and `offbox` which create podman containers with distinct configurations.

The command `onbox` creates a container which:

- allows internet access
- allows direct edits to `<project>/` on the host

The command `netbox` creates a container which:

- allows internet access
- disables direct edits to the host

The command `offbox` creates a container which:

- disables internet access
- disables edits to the host

By default, all three commands `onbox`, `netbox` and `offbox` start an interactive shell in the container.

Git may be used to make changes within the container visible and as transport for syncing changes committed inside the container to the host.

## naming conventions

The placeholder `<project-base>` is used to refer to the basename of `<project>`.

The placeholder `<project-slug>` refers to `<project-base>` converted to a hyphenated alphanumeric slug.

## mounts

### mount files

Default read-only mounts are specified in `defaults/read.mounts` in this repository. For example, the following line makes OpenCode configuration from the host available in every container:

```
~/.local/share/opencode/auth.json : /home/dev/.local/share/opencode/auth.json
```

Default read-write mounts are specified in `defaults/write.mounts` in this repository.

Any of these configuration files may be empty or absent.

### mount specification format

Each mount file consists of lines in the format

```
<source>
```

or

```
<source> : <dest>
```

where `<source>` refers to the path on the host and `<dest>` refers to the target path within the container. The spaces before and after the colon may or may not be present.

When `<dest>` is omitted, use `/host/read/<basename>` for read mounts and `/host/write/<basename>` for write mounts, where `<basename>` is the basename of `<source>`.

The path `<source>` may use the placeholders `~` or `$HOME` to reference the host home folder.

The path `<dest>` may use the placeholders `~` or `$HOME` to reference the container home folder, and it may use the placeholder `$PROJECT` to reference the path `/working/<project-base>` of the working repository.

As an alternative to the files `read.mounts` and `write.mounts`, the arguments `--read` and `--write` accept the same input format `<source>` or `<source>:<dest>`, and may be used multiple times in the command which creates the container.

### mount precedence

All paths specified by the global defaults and the mounts declared on the command which creates the container are mounted.

When identical or nested `<dest>` paths are provided, mount them in order from shallower paths to deeper paths so that the permissions of deeper paths override the permissions of shallower paths.

### read-only mounts

Read-only mounts may be either files or folders.

They are always bind-mounts in `onbox`, `netbox` and `offbox` containers.

### read-write mounts

Read-write mounts must be folders on the host, not arbitrary files.

In the `onbox` container, these are bind-mounted.

For the `netbox` container, at time of the container creation, the contents of `<source>` on the host are copied into a volume corresponding to that folder and then mounted at `<dest>` in the container. The volume is named `<project-slug>.netbox.write.<dest-slug>`, where `<container>` is `netbox` or `offbox` and `<dest-slug>` is `<dest>` converted to a hyphenated alphanumeric slug.

For the `offbox` container, the volume `<project-slug>.offbox.write.<dest-slug>` is copied from `<project-slug>.netbox.write.<dest-slug>` instead, if the `netbox` container exists. If not, then the contents of `<project-slug>.offbox.write.<dest-slug>` are copied from the host as with `netbox`.

## containers

Interactive sessions in all `onbox`, `netbox` and `offbox` containers are started with a shell with `/working/<project-base>/` as the working directory.

### onbox

This container is always created from the shared base image defined by `Containerfile`.

It includes the following mounts:

- the host's working tree `<project>/`, bind-mounted to `/working/<project-base>/` (read-write bind-mount)
- the host's git folder `<project>/.git/`, bind-mounted to `/host/git/` (read-only bind-mount)
- the volume `<project-slug>.onbox.gitdir` is mounted to `/working/<project-base>/.git/` (read-write volume)

  - After creating and mounting the volume, `/host/git/` is set as a remote and `/working/<project-base>/` as its working tree.

- the global dotfiles folder `defaults/dotfiles/` from this repository, bind-mounted to `/talkbox/dotfiles.global/` (read-only bind-mount)
- the project dotfiles folder `<project>/.dotfiles/`, bind-mounted to `/talkbox/dotfiles.project/` when it exists on the host (read-only bind-mount)
- every read mount as a read-only bind-mount
- every write mount as a read-write bind-mount

### netbox

At the time of creation of the `netbox` container, if the `onbox` container exists, then `podman commit` is used to commit it as the image `<project-slug>.netbox.root`, which is then used as the base for the `netbox` container. Otherwise, use the shared base image as a fallback.

The `netbox` container includes the following mounts:

- the volume `<project-slug>.netbox.worktree`, mounted to `/working/<project-base>/` (read-write volume)

  - created by copying the contents of the host's working tree `<project>/` into the volume

- the host's git folder `<project>/.git/`, bind-mounted to `/host/git/` (read-only bind-mount)
- the volume `<project-slug>.netbox.gitdir` is mounted to `/working/<project-base>/.git/` (read-write volume)

  - After creating and mounting the volume, `/host/git/` is set as a remote and `/working/<project-base>/` as its working tree.

- the global dotfiles folder `defaults/dotfiles/` from this repository, bind-mounted to `/talkbox/dotfiles.global/` (read-only bind-mount)
- the project dotfiles folder `<project>/.dotfiles/`, bind-mounted to `/talkbox/dotfiles.project/` when it exists on the host (read-only bind-mount)
- every read mount as a read-only bind-mount (read-only bind-mount)
- every write mount as a read-write volume (read-write volume)

The `netbox` container is never given write access to the host system. Every mount it receives is either a read-only bind-mount or a volume.

### offbox

At the time of creation of the `offbox` container, if the `netbox` container exists, then `podman commit` is used to commit it as the image `<project-slug>.offbox.root`, which is then used as the base for the `offbox` container. If the `netbox` container does not exist, then commit the `onbox` container instead to obtain `<project-slug>.offbox.root`. If neither the `netbox` nor `onbox` containers exist, then use the shared base image as a fallback.

The `offbox` container includes the following mounts:

- the volume `<project-slug>.offbox.worktree`, mounted to `/working/<project-base>/` (read-write volume)

  - created as a copy of `<project-slug>.netbox.worktree` if that volume exists
  - created by copying the contents of the host's working tree `<project>/` into the volume otherwise

- the host's git folder `<project>/.git/`, bind-mounted to `/host/git/` (read-only bind-mount)
- the volume `<project-slug>.offbox.gitdir` is mounted to `/working/<project-base>/.git/` (read-write volume)

  - After creating and mounting the volume, `/host/git/` is set as a remote and `/working/<project-base>/` as its working tree.

- the global dotfiles folder `defaults/dotfiles/` from this repository, bind-mounted to `/talkbox/dotfiles.global/` (read-only bind-mount)
- the project dotfiles folder `<project>/.dotfiles/`, bind-mounted to `/talkbox/dotfiles.project/` when it exists on the host (read-only bind-mount)
- every read mount as a read-only bind-mount (read-only bind-mount)
- every write mount as a read-write volume (read-write volume)

  - initialized as a copy of the corresponding `netbox` write mount volume if that volume exists, or copied from `<source>` on the host otherwise

The `offbox` container is never given write access to the host system. Every mount it receives is either a read-only bind-mount or a volume.

## filesystem inheritance

### root filesystem inheritance

When the commands `netbox` or `offbox` create a container, the root filesystem is inherited from a source container by committing an image of that container using `podman commit`.

By default,

- `onbox` uses the shared base image defined by `Containerfile`
- `netbox` inherits from `onbox` if it exists, or from the shared base image otherwise
- `offbox` inherits from `netbox` if it exists, from `onbox` otherwise, or uses the shared base image if neither `onbox` or `netbox` containers exist

### read-write volume inheritence

The read-write volumes of `offbox` are copied from `netbox` by default, or from the host system otherwise.

The read-write volumes of `onbox` and `netbox` are always copied from the host.

### inheritance options

Use the option `--fresh` to prevent default inheritance of the root filesystem and read-write volumes.

Use the option `--inherit <onbox|netbox|offbox>` to be explicit about which container a new container inherits its root filesystem and read-write volumes from.

## dotfiles

Dotfiles are applied from two places.

Global dotfiles which are reused across all working repositories may be provided in the subfolder `defaults/dotfiles/` of this repository.

Dotfiles specific to a working repository may be provided in `<project>/.dotfiles/`.

Both folders are bind-mounted read-only in the created `onbox`, `netbox` or `offbox` containers. After the container has been started, then `image/setup.sh` is invoked with `podman exec` in order to install the dotfiles. For the `onbox` and `netbox` containers, this happens after `nft` has been configured.

Dotfiles originating from `<project>/.dotfiles/` should override those derived from `defaults/dotfiles/`.

## user mapping

All three containers are created with `--userns=keep-id:uid=1000,gid=1000` so that the host user is mapped to the container user `dev`. Read and write permissions assigned to `dev` for files in `/working/<project-base>/` and the read and write mounts should match the host permissions for the same files.

## network

The container runs with rootless networking via `pasta`.

Internet access should be allowed for the `onbox` and `netbox` containers but blocked for the `offbox` container.

However, all three containers require access to specific ports on the host in order to access tools like local language models.

For `offbox`, this is achieved by running `podman create` with the options:

```
--network="pasta:-T,<port1>,-T,<port2>,-i,lo,-I,talkbox0"
--cap-drop=NET_ADMIN
--cap-drop=NET_RAW
```

For `onbox` and `netbox`, use only the options:

```
--network="pasta:-T,<port1>,-T,<port2>,--dns-forward,169.254.1.1,--map-guest-addr,none"
--cap-drop=NET_ADMIN
--cap-drop=NET_RAW
```

Setting `--dns-forward=169.254.1.1` ensures that DNS forwarding is available at a fixed address within the container.

In all cases, replace `-T,<port1>,-T,<port2>` with the ports which the containers should have access to.

Default ports may be specified in `defaults/ports` in this repository, which lists one port per line.

As an alternative to the file `ports`, the argument `--port` accepts a single port and may be used multiple times in the command which creates the container.

The union of the ports specified by `defaults/ports` and the ports declared as an argument to the command which creates the container is used.

For the `onbox` and `netbox` containers, IP addresses and CIDR ranges listed in `defaults/deny.ip` are blocked. Access is always allowed to loopback addresses and `169.254.1.1` since it is used for DNS forwarding, even if those addresses are matched by `defaults/deny.ip`. For any address or CIDR range listed in `defaults/allow.ip`, access is allowed even if is matched by `defaults/deny.ip`.

As an alternative to the files `defaults/deny.ip` and `defaults/allow.ip`, use the argument `--deny-ip` and `--allow-ip`. Take the union of blocked entries specified with `defaults/deny.ip` and `--deny-ip`. Also take the union of `defaults/allow.ip` and `--allow-ip` for allowed entries.

Addresses or CIDR ranges not matched by `defaults/deny.ip` or an argument `--deny-ip` are allowed. These options do not affect the `offbox` container.

For the `onbox` and `netbox` containers, the restrictions are enforced via `nft` before `image/setup.sh` is invoked.

## image and container management

The following commands are provided for managing images and containers:

- `onbox --recontain` recreates the `onbox` container and all of its associated volumes and then starts the container
- `onbox --rebuild` rebuilds the base image and recreates the `onbox` container and then starts the container
- `onbox --rm-container` removes the `onbox` container, together with associated volumes
- `onbox --rm-image` removes the base image, but will not remove the image if it is being used by other containers

Analogous commands are provided for `netbox` and `offbox`. For `netbox` and `offbox`:

- `--recontain` and `--rebuild` also recreate the root image according to the root filesystem inheritance rules
- `--rm-container` additionally removes the container's root image `<project-slug>.<container>.root` when it exists

The base image is shared across all project directories which use this repository for sandboxing. Root images produced by inheritance are specific to a project.

## command execution

The command `onbox -c <command>` or `onbox --command <command>` runs the provided command within the container.

By default, this executes as `onbox -c --interactive <command>`, running the command interactively.

Alternatively, `onbox -c --noninteractive <command>` runs the command noninteractively.

Analogous commands are provided for `netbox` and `offbox`.

## git as transport

`git` plays two roles:

1. Enabling changes made to the working tree within the container to be visible and auditable from the host.
2. Enabling changes made to the git history within the container to be transferred to the host.

The host's git directory, mounted at `/host/git/` in the container, is available as a remote called `host` for git commands run inside the container, allowing changes made on the host to be fetched and merged from within the container. When the git directory of `<project>/` on the host lies outside of `<project>/`, then the `onboxs`, `netbox` and `offbox` refuse to mount.

The only way that changes made to the git history within the container are transferred to the git history on the host is via git bundles, preventing content such as git configs and hooks from being inadvertently transferred from the container to the host. Commands are provided to be used on the host side to manage this workflow, invoked as subcommands of `onbox`, `netbox` and `offbox`.

All merge operations performed by these commands are fast-forward only.

None of the git-related subcommands should affect the contents of the working tree except when fast-forwarding a branch with no staged changes and a clean worktree.

Submodules are supported. When `onbox`, `netbox` or `offbox` are used to create a container, the submodules are absorbed into the host's top-level git directory and then included in 

However, git operations within a submodule are prevented within the container and must be made on the host instead.

If the `<project>/` is not tracked by git on the host, the commands `onbox`, `netbox` and `offbox` may still be used, though the git-related aspects of this specification will not be available.

### `custom_merge()`

The shell function `custom_merge <remote> <branchname>` implements a merge logic which accounts for the fact that the host and container repositories use a shared working tree.

The function always starts with the following check:

**DESCENDANT_CHECK:** If `refs/heads/<branchname>` exists, then DESCENDANT_CHECK passes if `refs/remotes/<remote>/<branchname>` exists and is a descendant of `refs/heads/<branchname>`. If `refs/heads/<branchname>` does not exist, then DESCENDANT_CHECK passes anyway.

If DESCENDANT_CHECK fails, no changes are made and the user is warned instead.

#### `custom_merge` for current branch

If DESCENDANT_CHECK passes, proceed according to the following cases:

- **Case 1:** If there are no staged changes and the worktree is clean relative to `HEAD`, run `git merge --ff-only refs/remotes/<remote>/<branchname>`. This may update the host worktree.
- **Case 2:** If there are no staged changes and the worktree already matches `refs/remotes/<remote>/<branchname>`, update the current branch using `git reset --mixed refs/remotes/<remote>/<branchname>`.
- **Case 3:** If neither **Case 1** or **Case 2** holds, make no changes and warn the user instead.

#### `custom_merge` for other branch

If DESCENDANT_CHECK passes, then advance the branch ref without switching branches using `git branch -f`.

### fetch

The command `onbox fetch` fetches the changes from the git directory contained in `<project-slug>.onbox.gitdir`. These changes are obtained via a git bundle.

Analogously, `netbox fetch` fetches from `<project-slug>.netbox.gitdir` and `offbox fetch` fetches from `<project-slug>.offbox.gitdir`.

Any of `onbox fetch --all`, `netbox fetch --all` or `offbox fetch --all` may be used to fetch changes from the `onbox`, `netbox` and `offbox` git histories.

### merge

The command `onbox merge` and its options are used to apply `custom_merge` in the host repository relative to the `onbox` remote. The command applies the following steps.

1. From the host repository, fetch the changes from the `onbox` remote.
2. Apply `custom_merge onbox <branchname>`.

The default when running `onbox merge` is that `<branchname>` corresponds to the currently checked out branch in the host repository.

The command `onbox merge <branchname>` may be used to specify a particular branch of the `onbox` remote.

The command `onbox merge --all` applies `custom_merge onbox <branchname>` to all `onbox` branches.

Analogously, `netbox merge` is used with `custom_merge netbox <branchname>` and `offbox merge` is used with `custom_merge offbox <branchname>`.

### sync

The command `onbox sync` and its options are used to sync changes from the host git history back to the container history.

The command applies the following steps.

1. Within the `onbox` container's git repository `/working/<project-base>/`, fetch the changes from the host remote.
2. Within the `onbox` container's git repository, apply `custom_merge host <branchname>`.

The default when running `onbox sync` is that `<branchname>` corresponds to the currently checked out branch in the host repository.

The command `onbox sync <branchname>` may be used to specify a particular branch of the `host` remote.

The command `onbox sync --all` applies `custom_merge host <branchname>` to all `host` branches.

Analogously, `netbox sync` is used to sync changes back to the `netbox` container and `offbox sync` is used to sync changes back to the `offbox` container.

## gpu support

When the flag `--gpu` is given to any of the commands `onbox`, `netbox` or `offbox`, then any available Nvidia GPUs from the host are made available in the container when it is created by passing the following options to `podman`:

```
--device nvidia.com/gpu=all
--group-add keep-groups
```

## implementation

The core shell script by which `onbox`, `netbox` and `offbox` are defined is `talkbox.sh`. Additional logic used by `talkbox.sh` may be provided as shell scripts in `lib/`. This includes:

- `lib/git.sh` which defines `custom_merge()` and other git logic

When symlinked as `onbox` or called as `talkbox.sh onbox`, then `talkbox.sh` acts as `onbox`.

When symlinked as `netbox` or called as `talkbox.sh netbox`, then `talkbox.sh` acts as `netbox`.

When symlinked as `offbox` or called as `talkbox.sh offbox`, then `talkbox.sh` acts as `offbox`.

`Containerfile` is used to specify an image that includes:

- `image/setup.sh` which defines operations to be executed on container initialization, including installation of dotfiles, configuration of git identity and initialization of the container's git directory

The directory `defaults/` may include:

- files `read.mounts` and `write.mounts` specifying read-only and read-write mounts
- the file `ports` specifying the ports which the containers should have access to
- files `deny.ip` and `allow.ip` specify blocked and allowed IP addresses and CIDR ranges
- the folder `dotfiles` providing default dotfiles

In the files read.mounts, write.mounts, ports, deny.ip and allow.ip, blank lines and lines whose first non-whitespace character is # are ignored.

All shell scripts should be implemented in Bash. Shell scripts should be checked with ShellCheck (invoked via `make lint`) and formatted with `shfmt` (invoked via `make format`).

If temporary containers other than those used directly by `onbox`, `netbox` and `offbox` are created to support the implementation, they should be created without any network access. Where such a container is used to copy host contents into a volume, the host source must be mounted read-only.

## testing

Tests are implemented with `bats-core` and invoked with `make test-unit` for unit tests and `make test-e2e` for end-to-end tests.

End-to-end tests should capture external usage, where `talkbox.sh` is invoked with `onbox`, `netbox` and `offbox` subcommands.

Any test which invokes `podman`, including those which call `talkbox.sh`, `onbox`, `netbox` or `offbox`, must be called via `systemd-run` with the options `RuntimeMaxSec` and `KillMode=control-group` passed via the flag `-p` in order to prevent commands from hanging indefinitely. Additionally, the `make` implementation wraps the entirety of both the unit test suite and end-to-end test suite in `systemd-run` to prevent indefinite hangs at the suite level.

All tests which create a `podman` container should use a temporary git repository or non-git folder as a stand-in for `<project>`.

Most end-to-end tests should be implemented with `-c --noninteractive` to ensure that the container is run non-interactively. However, some tests should test `talkbox.sh` running interactively. Tests for interactive cases should drive the session through `expect`, running scripts that terminate with `exit`.

Do not write tests for GPU usage, since a GPU may not be available on all systems where tests are run.

## references

References to relevant documentation and source are available in `.llm/ref/`, indexed by `.llm/ref/sources.yaml`. These include:

- `.llm/ref/podman.docs` - podman documentation
- `.llm/ref/passt.docs` - passt documentation
- `.llm/ref/bats-core.docs` - bats man page
- `.llm/ref/linux.man/capabilities.7.txt` - capabilities man page for linux
