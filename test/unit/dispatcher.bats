# shellcheck disable=SC2030,SC2031 # bats runs each test in a subshell; the PODMAN_* exports are scoped to their own test
load helpers

PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

setup() {
	PROJECT="$BATS_TEST_TMPDIR/talkbox-proj"
	mkdir -p "$PROJECT"
	git -C "$PROJECT" init -q
	git -C "$PROJECT" config user.name host-user
	git -C "$PROJECT" config user.email host@example.com
	SHIM="$BATS_TEST_TMPDIR/shim"
	LOG="$BATS_TEST_TMPDIR/podman.log"
	make_podman_shim "$SHIM"
}

use_podman_shim() {
	PATH="$SHIM:$PATH"
	export PODMAN_LOG="$LOG"
	export PODMAN_IMAGES="${TALKBOX_BASE_IMAGE:-talkbox/base:latest}"
}

run_dispatcher() {
	local container="$1"
	shift
	cd "$PROJECT" || return 1
	run "$PROJECT_ROOT/talkbox.sh" "$container" "$@"
}

count_token() {
	local line="$1" token="$2" n=0 element
	for element in $line; do
		[[ "$element" == "$token" ]] && n=$((n + 1))
	done
	printf '%s\n' "$n"
}

mk_talkbox_copy() {
	local dir="$1"
	mkdir -p "$dir"
	cp -r "$PROJECT_ROOT/lib" "$PROJECT_ROOT/defaults" "$dir/"
	cp "$PROJECT_ROOT/talkbox.sh" "$dir/talkbox.sh"
}

@test "talkbox.sh onbox creates the container with the host worktree bind-mount and runs setup then the command" {
	use_podman_shim
	run_dispatcher onbox -c --noninteractive 'echo hi'
	[[ "$status" -eq 0 ]]
	local create
	create="$(podman_create_line)"
	line_has_token "$create" '--name=talkbox-proj.onbox'
	line_has_token "$create" "$PROJECT:/working/talkbox-proj"
	line_has_token "$create" "$PROJECT/.git:/host/git:ro"
	line_has_token "$create" 'talkbox-proj.onbox.gitdir:/working/talkbox-proj/.git'
	[[ -n "$(podman_line '^volume create talkbox-proj.onbox.gitdir$')" ]]
	[[ -n "$(podman_line '^start talkbox-proj.onbox$')" ]]
	[[ -n "$(podman_line '^unshare nsenter -t 12345 -n nft -f -$')" ]]
	[[ "$(podman_line_no '^unshare nsenter')" -lt "$(podman_line_no '^exec talkbox-proj.onbox setup.sh$')" ]]
	[[ "$(podman_line_no '^exec talkbox-proj.onbox setup.sh$')" -lt "$(podman_line_no '^exec talkbox-proj.onbox bash -c echo hi$')" ]]
	[[ -n "$(podman_line '^stop -t 5 talkbox-proj.onbox$')" ]]
}

@test "talkbox.sh onbox defaults to an interactive shell when no command is given" {
	use_podman_shim
	run_dispatcher onbox
	[[ "$status" -eq 0 ]]
	local create
	create="$(podman_create_line)"
	line_has_token "$create" '--interactive'
	line_has_token "$create" '--tty'
	[[ -n "$(podman_line '^exec --interactive --tty talkbox-proj.onbox /bin/bash$')" ]]
}

@test "talkbox.sh netbox populates its volumes from the host and installs the nft deny rules after start" {
	use_podman_shim
	run_dispatcher netbox -c --noninteractive true
	[[ "$status" -eq 0 ]]
	local create populate
	create="$(podman_create_line)"
	line_has_token "$create" '--name=talkbox-proj.netbox'
	line_has_token "$create" 'talkbox-proj.netbox.worktree:/working/talkbox-proj'
	line_has_token "$create" "$PROJECT/.git:/host/git:ro"
	populate="$(podman_line 'talkbox-proj.netbox.worktree:/talkbox/target')"
	line_has_token "$populate" '--network=none'
	line_has_token "$populate" "$PROJECT:/talkbox/source:ro"
	[[ -n "$(podman_line '^volume create talkbox-proj.netbox.gitdir$')" ]]
	[[ "$(podman_line_no '^start talkbox-proj.netbox$')" -lt "$(podman_line_no '^unshare nsenter')" ]]
	[[ "$(podman_line_no '^unshare nsenter')" -lt "$(podman_line_no '^exec talkbox-proj.netbox setup.sh$')" ]]
}

@test "talkbox.sh offbox restricts pasta to loopback and installs no nft rules" {
	use_podman_shim
	run_dispatcher offbox -c --noninteractive true
	[[ "$status" -eq 0 ]]
	local create
	create="$(podman_create_line)"
	line_has_token "$create" '--network=pasta:-i,lo,-I,talkbox0'
	line_has_token "$create" 'talkbox-proj.offbox.worktree:/working/talkbox-proj'
	[[ "$(podman_count '^unshare nsenter')" -eq 0 ]]
	[[ "$(podman_count '^inspect -f')" -eq 0 ]]
	[[ -n "$(podman_line '^exec talkbox-proj.offbox setup.sh$')" ]]
	[[ -n "$(podman_line '^stop -t 5 talkbox-proj.offbox$')" ]]
}

@test "talkbox.sh onbox bind-mounts CLI write specs and never populates volumes" {
	use_podman_shim
	run_dispatcher onbox --write /host/data:/talkbox/wdata -c --noninteractive true
	[[ "$status" -eq 0 ]]
	local create
	create="$(podman_create_line)"
	line_has_token "$create" '/host/data:/talkbox/wdata'
	[[ "$create" != *'talkbox-proj.onbox.write'* ]]
	[[ "$(podman_count '^run ')" -eq 0 ]]
}

@test "talkbox.sh netbox mounts a CLI write spec as a volume named <slug>.netbox.write.<dest-slug> and populates it from the host" {
	use_podman_shim
	run_dispatcher netbox --write /host/data:/talkbox/wdata -c --noninteractive true
	[[ "$status" -eq 0 ]]
	local create populate
	create="$(podman_create_line)"
	line_has_token "$create" 'talkbox-proj.netbox.write.talkbox-wdata:/talkbox/wdata'
	populate="$(podman_line 'talkbox-proj.netbox.write.talkbox-wdata:/talkbox/target')"
	line_has_token "$populate" '/host/data:/talkbox/source:ro'
}

@test "talkbox.sh offbox mounts a CLI write spec as a volume named <slug>.offbox.write.<dest-slug>" {
	use_podman_shim
	run_dispatcher offbox --write /host/data:/talkbox/wdata -c --noninteractive true
	[[ "$status" -eq 0 ]]
	line_has_token "$(podman_create_line)" 'talkbox-proj.offbox.write.talkbox-wdata:/talkbox/wdata'
}

@test "talkbox.sh netbox derives the write-volume dest-slug from the dest basename path" {
	use_podman_shim
	run_dispatcher netbox --write /host/data:/a/b/c -c --noninteractive true
	[[ "$status" -eq 0 ]]
	line_has_token "$(podman_create_line)" 'talkbox-proj.netbox.write.a-b-c:/a/b/c'
}

@test "talkbox.sh netbox collapses identical write dests into a single volume populated from the last source" {
	use_podman_shim
	run_dispatcher netbox --write /first:/x --write /cli:/x -c --noninteractive true
	[[ "$status" -eq 0 ]]
	local create populate
	create="$(podman_create_line)"
	[[ "$(count_token "$create" 'talkbox-proj.netbox.write.x:/x')" -eq 1 ]]
	populate="$(podman_line 'talkbox-proj.netbox.write.x:/talkbox/target')"
	line_has_token "$populate" '/cli:/talkbox/source:ro'
	[[ "$(grep -c 'talkbox-proj.netbox.write.x:/talkbox/target' "$LOG" || true)" -eq 1 ]]
}

@test "talkbox.sh netbox merges defaults-file and CLI write specs in order" {
	use_podman_shim
	local copy="$BATS_TEST_TMPDIR/talkbox-copy"
	mk_talkbox_copy "$copy"
	printf '/def:/x\n' >>"$copy/defaults/write.mounts"
	cd "$PROJECT" || return 1
	run "$copy/talkbox.sh" netbox --write /cli:/y -c --noninteractive true
	[[ "$status" -eq 0 ]]
	[[ "$(podman_create_line)" == *'-v talkbox-proj.netbox.write.x:/x'*'-v talkbox-proj.netbox.write.y:/y'* ]]
}

@test "talkbox.sh threads --port into the per-container pasta network string" {
	use_podman_shim
	run_dispatcher onbox --port 8080 --port 9090 -c --noninteractive true
	[[ "$status" -eq 0 ]]
	line_has_token "$(podman_create_line)" '--network=pasta:-T,8080,-T,9090,--dns-forward,169.254.1.1,--map-guest-addr,none'
	: >"$LOG"
	run_dispatcher offbox --port 8080 -c --noninteractive true
	[[ "$status" -eq 0 ]]
	line_has_token "$(podman_create_line)" '--network=pasta:-T,8080,-i,lo,-I,talkbox0'
}

@test "talkbox.sh netbox --recontain recreates the container and volumes without a commit" {
	use_podman_shim
	run_dispatcher netbox --recontain
	[[ "$status" -eq 0 ]]
	[[ "$(podman_count '^commit ')" -eq 0 ]]
	[[ "$(podman_count '^build ')" -eq 0 ]]
	[[ -n "$(podman_line '^rm -f --volumes talkbox-proj.netbox$')" ]]
	[[ -n "$(podman_line 'talkbox-proj.netbox.worktree:/talkbox/target')" ]]
	[[ -n "$(podman_line '^volume create talkbox-proj.netbox.gitdir$')" ]]
	[[ -n "$(podman_line '^create ')" ]]
	[[ -n "$(podman_line '^start talkbox-proj.netbox$')" ]]
	[[ -n "$(podman_line '^unshare nsenter')" ]]
	[[ -n "$(podman_line '^exec talkbox-proj.netbox setup.sh$')" ]]
	[[ -n "$(podman_line '^stop -t 5 talkbox-proj.netbox$')" ]]
}

@test "talkbox.sh onbox --recontain recreates without populating, nft or setup" {
	use_podman_shim
	run_dispatcher onbox --recontain
	[[ "$status" -eq 0 ]]
	[[ "$(podman_count '^run ')" -eq 0 ]]
	[[ "$(podman_count '^commit ')" -eq 0 ]]
	[[ "$(podman_count '^build ')" -eq 0 ]]
	[[ "$(podman_count '^unshare ')" -eq 0 ]]
	[[ "$(podman_count '^exec ')" -eq 0 ]]
	[[ -n "$(podman_line '^rm -f --volumes talkbox-proj.onbox$')" ]]
	[[ "$(podman_line_no '^rm -f --volumes')" -lt "$(podman_line_no '^volume create')" ]]
	[[ "$(podman_line_no '^volume create')" -lt "$(podman_line_no '^create ')" ]]
	[[ -n "$(podman_line '^start talkbox-proj.onbox$')" ]]
	[[ -n "$(podman_line '^stop -t 5 talkbox-proj.onbox$')" ]]
}

@test "talkbox.sh onbox --rebuild builds the base image before recreating" {
	use_podman_shim
	run_dispatcher onbox --rebuild
	[[ "$status" -eq 0 ]]
	[[ -n "$(podman_line '^build -t ')" ]]
	[[ "$(podman_line_no '^build -t')" -lt "$(podman_line_no '^rm -f --volumes')" ]]
	[[ "$(podman_line_no '^rm -f --volumes')" -lt "$(podman_line_no '^create ')" ]]
	[[ "$(podman_count '^commit ')" -eq 0 ]]
	[[ "$(podman_count '^unshare ')" -eq 0 ]]
	[[ "$(podman_count '^exec ')" -eq 0 ]]
	[[ -n "$(podman_line '^start talkbox-proj.onbox$')" ]]
}

@test "talkbox.sh netbox --rebuild builds the base image and skips the commit when no source container exists" {
	use_podman_shim
	run_dispatcher netbox --rebuild
	[[ "$status" -eq 0 ]]
	[[ -n "$(podman_line '^build -t ')" ]]
	[[ "$(podman_line_no '^build -t')" -lt "$(podman_line_no '^rm -f --volumes')" ]]
	[[ "$(podman_count '^commit ')" -eq 0 ]]
	[[ -n "$(podman_line '^unshare nsenter')" ]]
	[[ -n "$(podman_line '^exec talkbox-proj.netbox setup.sh$')" ]]
	[[ -n "$(podman_line '^start talkbox-proj.netbox$')" ]]
}

@test "talkbox.sh netbox commits the onbox container as the netbox root image by default" {
	use_podman_shim
	export PODMAN_CONTAINERS="talkbox-proj.onbox"
	run_dispatcher netbox -c --noninteractive true
	[[ "$status" -eq 0 ]]
	[[ -n "$(podman_line '^commit talkbox-proj.onbox talkbox-proj.netbox.root$')" ]]
	[[ "$(podman_line_no '^commit ')" -lt "$(podman_line_no '^create ')" ]]
	line_has_token "$(podman_create_line)" 'talkbox-proj.netbox.root'
}

@test "talkbox.sh netbox --fresh skips the commit even when the onbox container exists" {
	use_podman_shim
	export PODMAN_CONTAINERS="talkbox-proj.onbox"
	run_dispatcher netbox --fresh -c --noninteractive true
	[[ "$status" -eq 0 ]]
	[[ "$(podman_count '^commit ')" -eq 0 ]]
	line_has_token "$(podman_create_line)" "${TALKBOX_BASE_IMAGE:-talkbox/base:latest}"
}

@test "talkbox.sh netbox --rm-container removes the container, its volumes and its root image" {
	use_podman_shim
	export PODMAN_VOLUMES="talkbox-proj.netbox.worktree talkbox-proj.netbox.gitdir"
	export PODMAN_IMAGES="${TALKBOX_BASE_IMAGE:-talkbox/base:latest} talkbox-proj.netbox.root"
	run_dispatcher netbox --rm-container
	[[ "$status" -eq 0 ]]
	[[ -n "$(podman_line '^rm -f --volumes talkbox-proj.netbox$')" ]]
	[[ -n "$(podman_line '^volume rm -f talkbox-proj.netbox.worktree$')" ]]
	[[ -n "$(podman_line '^volume rm -f talkbox-proj.netbox.gitdir$')" ]]
	[[ "$(podman_count '^volume rm -f talkbox-proj.netbox.write')" -eq 0 ]]
	[[ -n "$(podman_line '^rmi talkbox-proj.netbox.root$')" ]]
	[[ "$(podman_line_no '^volume rm -f')" -lt "$(podman_line_no '^rmi ')" ]]
}

@test "talkbox.sh onbox --rm-container removes only the container and its gitdir volume" {
	use_podman_shim
	export PODMAN_VOLUMES="talkbox-proj.onbox.gitdir"
	run_dispatcher onbox --rm-container
	[[ "$status" -eq 0 ]]
	[[ -n "$(podman_line '^rm -f --volumes talkbox-proj.onbox$')" ]]
	[[ -n "$(podman_line '^volume rm -f talkbox-proj.onbox.gitdir$')" ]]
	[[ "$(podman_count '^volume rm -f')" -eq 1 ]]
	[[ "$(podman_count '^rmi ')" -eq 0 ]]
	[[ "$(podman_count '^image exists')" -eq 0 ]]
}

@test "talkbox.sh onbox --rm-image removes the base image when it is not in use" {
	use_podman_shim
	run_dispatcher onbox --rm-image
	[[ "$status" -eq 0 ]]
	[[ "$(podman_line '^rmi ')" == "rmi ${TALKBOX_BASE_IMAGE:-talkbox/base:latest}" ]]
	[[ "$(podman_count '^rm ')" -eq 0 ]]
}

@test "talkbox.sh without arguments prints the usage and exits 2" {
	cd "$PROJECT" || return 1
	run "$PROJECT_ROOT/talkbox.sh"
	[[ "$status" -eq 2 ]]
	[[ "$output" == *'usage: talkbox.sh <onbox|netbox|offbox> ...'* ]]
}
