# Administrator guide — installing talkbox on a shared server

Setup steps for a sysadmin to make the `onbox`, `netbox` and `offbox` commands available to all users on a shared server from a single install of [talkbox](README.md).

## Prerequisites

Install on the server:

- **`podman`** (rootless mode) — talkbox uses `--userns=keep-id` and never invokes `sudo podman`.
- **`passt`** (provides the `pasta` binary) — the rootless networking backend hard-coded by all three containers.
- **`git`** — only needed for the `fetch`/`merge`/`sync` git-transport commands.

For each user:

- A **disjoint `subuid`/`subgid` range** in `/etc/subuid` and `/etc/subgid` (see [Subuid/subgid allocation](#subuidsubgid-allocation)).
- **`systemd` lingering** — `loginctl enable-linger <user>` — so the user's rootless podman runtime is available without a full login session.

## 1. Install the repository

Clone to a single canonical path, readable by all users:

```
sudo git clone <repo-url> /opt/talkbox
sudo chown -R root:root /opt/talkbox
sudo chmod -R a+rX /opt/talkbox
```

Create three symlinks on every user's `PATH`. The dispatcher [talkbox.sh](talkbox.sh) resolves `TALKBOX_ROOT` via `readlink -f "$0"`, so symlinks transparently resolve back to `/opt/talkbox`:

```
sudo ln -sf /opt/talkbox/talkbox.sh /usr/local/bin/onbox
sudo ln -sf /opt/talkbox/talkbox.sh /usr/local/bin/netbox
sudo ln -sf /opt/talkbox/talkbox.sh /usr/local/bin/offbox
```

Keep [defaults/](defaults/) world-readable; it is shared site-wide (mounts, ports, dotfiles). Per-user overrides come from `<project>/.dotfiles/` and CLI flags.

## 2. Pre-build and preload the base image

All containers use the image `talkbox/base:latest` ([image/Containerfile](image/Containerfile)). Rootless podman storage is per-user (`~/.local/share/containers/storage`), so a single build cannot reach every user. The sysadmin builds once, saves a tarball, and preloads it into each user's store. Users who are not preloaded fall back to an automatic on-demand build on first run.

### Build and save

```
sudo podman build -t talkbox/base:latest -f /opt/talkbox/image/Containerfile /opt/talkbox/image
sudo podman save -o /opt/talkbox/talkbox-base.latest.tar talkbox/base:latest
sudo chmod a+r /opt/talkbox/talkbox-base.latest.tar
```

### Preload per user (manual)

Run `podman load` as each user so the image lands in that user's rootless store:

```
for user in alice bob carol; do
    sudo -u "$user" podman load -i /opt/talkbox/talkbox-base.latest.tar
done
```

Or, for all members of a group:

```
for user in $(getent group talkbox-users | cut -d: -f4 | tr ',' ' '); do
    sudo -u "$user" podman load -i /opt/talkbox/talkbox-base.latest.tar
done
```

`podman load` is idempotent, so re-running unconditionally after a rebuild is safe.

### Preload per user (Ansible)

```yaml
- name: Preload talkbox base image into each user's rootless store
  ansible.builtin.command:
    cmd: podman load -i /opt/talkbox/talkbox-base.latest.tar
  become: true
  become_user: "{{ item }}"
  loop: "{{ talkbox_users }}"
  changed_when: false
```

### Refresh after a Containerfile update

Rebuild the tarball (Build and save above) and re-run the preload loop.

## Subuid/subgid allocation

Rootless podman requires each user to have a disjoint range in both `/etc/subuid` and `/etc/subgid` (format: `username:start:count`). A range of 65536 IDs per user is sufficient. talkbox maps each host user to container UID 1000 (`dev`) via `--userns=keep-id:uid=1000,gid=1000`, so no per-user UID allocation or per-user image account is needed — only the subuid/subgid ranges.

### Manual

For an existing user:

```
sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 alice
sudo usermod --add-subuids 165536-231071 --add-subgids 165536-231071 bob
```

`useradd` creates ranges automatically on distributions with `SUB_UID_MIN`/`SUB_UID_MAX` configured in `/etc/login.defs`, so no explicit step is needed for new users:

```
sudo useradd -m alice
```

To find the next free range:

```
awk -F: '{ if ($2+$3 > max) max=$2+$3 } END { print max }' /etc/subuid
```

### Ansible

```yaml
vars:
  talkbox_subuid_base: 100000
  talkbox_subuid_size: 65536
  talkbox_users:
    - alice
    - bob
    - carol

tasks:
  - name: Ensure /etc/subuid has a disjoint range for each talkbox user
    ansible.builtin.lineinfile:
      path: /etc/subuid
      line: "{{ item }}:{{ talkbox_subuid_base + (ansible_loop.index0 * talkbox_subuid_size) }}:{{ talkbox_subuid_size }}"
      regexp: "^{{ item }}:"
      create: true
    loop: "{{ talkbox_users }}"
    loop_control:
      extended: true

  - name: Ensure /etc/subgid has a disjoint range for each talkbox user
    ansible.builtin.lineinfile:
      path: /etc/subgid
      line: "{{ item }}:{{ talkbox_subuid_base + (ansible_loop.index0 * talkbox_subuid_size) }}:{{ talkbox_subuid_size }}"
      regexp: "^{{ item }}:"
      create: true
    loop: "{{ talkbox_users }}"
    loop_control:
      extended: true
```

`regexp` makes the task idempotent. Keep `talkbox_users` in a fixed order so index-based ranges stay disjoint; if reordering, reassign deliberately.

## Verification

Per-user smoke check from a throwaway directory:

```
mkdir -p /tmp/talkbox-smoke && cd /tmp/talkbox-smoke
onbox -c --noninteractive 'echo hello from $(whoami)'
onbox --rm-container
```

Prints `hello from dev` if the image is loaded (or builds it first if not).

## Maintenance

- **Upgrade talkbox:** `sudo git -C /opt/talkbox pull`. Symlinks need no change.
- **Rebuild after a Containerfile change:** rebuild the tarball, re-run the preload loop, then each user runs `onbox --rebuild` (and analogously for `netbox`/`offbox`) to recreate their container from the updated image.
- **Remove a user's talkbox footprint:** the user runs `onbox --rm-container`, `netbox --rm-container`, `offbox --rm-container` (per project) and `podman rmi talkbox/base:latest`. Only that user's rootless storage is affected.
