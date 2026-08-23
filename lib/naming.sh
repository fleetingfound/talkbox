# shellcheck shell=bash

project_base() {
	local project="$1"
	local base
	base="${project%/}"
	printf '%s\n' "${base##*/}"
}

project_slug() {
	local base
	base="$(project_base "$1")"
	base="${base,,}"
	base="${base//[^a-z0-9]/-}"
	while [[ "$base" == *--* ]]; do
		base="${base//--/-}"
	done
	base="${base#-}"
	base="${base%-}"
	printf '%s\n' "$base"
}

base_image_name() {
	printf '%s\n' 'talkbox/base:latest'
}

onbox_container_name() {
	printf '%s\n' "$(project_slug "$1").onbox"
}

netbox_container_name() {
	printf '%s\n' "$(project_slug "$1").netbox"
}

offbox_container_name() {
	printf '%s\n' "$(project_slug "$1").offbox"
}

dest_slug() {
	local dest="$1"
	dest="${dest#/}"
	dest="${dest%/}"
	dest="${dest,,}"
	dest="${dest//[^a-z0-9]/-}"
	while [[ "$dest" == *--* ]]; do
		dest="${dest//--/-}"
	done
	dest="${dest#-}"
	dest="${dest%-}"
	printf '%s\n' "$dest"
}

netbox_worktree_volume() {
	printf '%s\n' "$(project_slug "$1").netbox.worktree"
}

offbox_worktree_volume() {
	printf '%s\n' "$(project_slug "$1").offbox.worktree"
}

netbox_write_volume() {
	printf '%s\n' "$(project_slug "$1").netbox.write.$2"
}

offbox_write_volume() {
	printf '%s\n' "$(project_slug "$1").offbox.write.$2"
}

netbox_root_image() {
	printf '%s\n' "$(project_slug "$1").netbox.root"
}

offbox_root_image() {
	printf '%s\n' "$(project_slug "$1").offbox.root"
}

gitdir_volume() {
	printf '%s\n' "$(project_slug "$1").$2.gitdir"
}
