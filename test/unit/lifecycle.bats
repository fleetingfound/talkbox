# shellcheck disable=SC2030,SC2031 # bats runs each test in a subshell; the PODMAN_* exports are scoped to their own test
load helpers

load_lifecycle_plan() {
	load_lib naming.sh
	load_lib mounts.sh
	load_lib network.sh
	load_lib containers.sh
}

plan_subcommands() {
	local -n _plan="$1"
	local i
	for ((i = 0; i < ${#_plan[@]}; i++)); do
		if [[ "${_plan[$i]}" == podman ]]; then
			printf '%s\n' "${_plan[$((i + 1))]}"
		fi
	done
}

plan_has_volume_rm() {
	local -n _plan="$1"
	local vol="$2"
	local i
	for ((i = 0; i + 4 < ${#_plan[@]}; i++)); do
		if [[ "${_plan[$i]}" == podman && "${_plan[$((i + 1))]}" == volume && "${_plan[$((i + 2))]}" == rm && "${_plan[$((i + 3))]}" == -f && "${_plan[$((i + 4))]}" == "$vol" ]]; then
			return 0
		fi
	done
	return 1
}

plan_has_volume_rm_none() {
	local -n _plan="$1"
	local vol="$2"
	if plan_has_volume_rm "$1" "$vol"; then
		return 1
	fi
	return 0
}

stub_volumes() {
	EXISTING_VOLUMES=("$@")
	volume_exists() {
		local name="$1"
		local v
		for v in "${EXISTING_VOLUMES[@]}"; do
			if [[ "$v" == "$name" ]]; then
				return 0
			fi
		done
		return 1
	}
}

# shellcheck disable=SC2034 # arrays are consumed by nameref parameters
setup() {
	PROJECT="$BATS_TEST_TMPDIR/talkbox-proj"
	mkdir -p "$PROJECT"
	READ_MOUNTS=()
	WRITE_MOUNTS=()
	SRCS=()
	DSTS=()
	PORTS=()
	DENY=()
	ALLOW=()
	SHIM="$BATS_TEST_TMPDIR/shim"
	LOG="$BATS_TEST_TMPDIR/podman.log"
}

use_podman_shim() {
	make_podman_shim "$SHIM"
	PATH="$SHIM:$PATH"
	export PODMAN_LOG="$LOG"
	local img
	img="$(base_image_name)"
	export PODMAN_IMAGES="$img"
}

@test "run_recontain removes, recreates and starts the onbox container, running no nft, setup or user command" {
	load_lifecycle_plan
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	# shellcheck disable=SC2034 # array is passed by name to the executor
	DENY=(1.1.1.1)
	export PODMAN_VOLUMES="talkbox-proj.onbox.gitdir"
	run run_recontain "$PROJECT" no READ_MOUNTS WRITE_MOUNTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	local rm_line volrm_line create_line start_line stop_line
	rm_line="$(podman_line_no '^rm -f --volumes talkbox-proj.onbox$')"
	volrm_line="$(podman_line_no '^volume rm -f talkbox-proj.onbox.gitdir$')"
	create_line="$(podman_line_no '^create ')"
	start_line="$(podman_line_no '^start talkbox-proj.onbox$')"
	stop_line="$(podman_line_no '^stop -t 5 talkbox-proj.onbox$')"
	[[ -n "$rm_line" && -n "$volrm_line" && -n "$create_line" && -n "$start_line" && -n "$stop_line" ]]
	[[ "$rm_line" -lt "$volrm_line" ]]
	[[ "$volrm_line" -lt "$create_line" ]]
	[[ "$create_line" -lt "$start_line" ]]
	[[ "$start_line" -lt "$stop_line" ]]
	[[ -z "$(podman_line '^volume create ')" ]]
	[[ "$(podman_count 'unshare')" -eq 0 ]]
	[[ "$(podman_count 'nsenter')" -eq 0 ]]
	[[ "$(podman_count '^exec ')" -eq 0 ]]
	[[ "$(podman_count 'image exists')" -eq 0 ]]
	[[ "$(podman_count '^build ')" -eq 0 ]]
	local create
	create="$(podman_create_line)"
	line_has_token "$create" '--name=talkbox-proj.onbox'
	line_has_token "$create" '--init'
	line_has_token "$create" 'TALKBOX_PROJECT_SLUG=talkbox-proj'
	line_has_token "$create" 'TALKBOX_CONTAINER_TYPE=onbox'
	line_lacks_token "$create" '--tmpfs'
	[[ "$create" != *'/run/talkbox'* ]]
}

@test "run_recontain removes only the volumes that exist and creates the missing gitdir volume" {
	load_lifecycle_plan
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	run run_recontain "$PROJECT" no READ_MOUNTS WRITE_MOUNTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	[[ "$(podman_count '^volume rm ')" -eq 0 ]]
	[[ -n "$(podman_line '^volume create talkbox-proj.onbox.gitdir$')" ]]
	[[ "$(podman_line_no '^rm -f --volumes talkbox-proj.onbox$')" -lt "$(podman_line_no '^volume create talkbox-proj.onbox.gitdir$')" ]]
	[[ "$(podman_line_no '^volume create talkbox-proj.onbox.gitdir$')" -lt "$(podman_line_no '^create ')" ]]
}

@test "run_rebuild builds the base image first, then recreates and starts the onbox container" {
	load_lifecycle_plan
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	# shellcheck disable=SC2034 # array is passed by name to the executor
	DENY=(1.1.1.1)
	export PODMAN_VOLUMES="talkbox-proj.onbox.gitdir"
	run run_rebuild "$PROJECT" no READ_MOUNTS WRITE_MOUNTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	local build_line rm_line create_line start_line stop_line
	build_line="$(podman_line_no '^build ')"
	rm_line="$(podman_line_no '^rm -f --volumes talkbox-proj.onbox$')"
	create_line="$(podman_line_no '^create ')"
	start_line="$(podman_line_no '^start talkbox-proj.onbox$')"
	stop_line="$(podman_line_no '^stop -t 5 talkbox-proj.onbox$')"
	[[ -n "$build_line" && -n "$rm_line" && -n "$create_line" && -n "$start_line" && -n "$stop_line" ]]
	[[ "$build_line" -lt "$rm_line" ]]
	[[ "$rm_line" -lt "$create_line" ]]
	[[ "$create_line" -lt "$start_line" ]]
	[[ "$start_line" -lt "$stop_line" ]]
	local build
	build="$(podman_line '^build ')"
	line_has_token "$build" '-t'
	line_has_token "$build" "$(base_image_name)"
	line_has_token "$build" "$TALKBOX_ROOT/image/Containerfile"
	[[ "$(podman_count 'unshare')" -eq 0 ]]
	[[ "$(podman_count '^exec ')" -eq 0 ]]
	[[ "$(podman_count 'image exists')" -eq 0 ]]
}

@test "run_rm_container removes the onbox container and only its gitdir volume" {
	load_lifecycle_plan
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	run run_rm_container "$PROJECT"
	[[ "$status" -eq 0 ]]
	[[ -n "$(podman_line '^rm -f --volumes talkbox-proj.onbox$')" ]]
	[[ "$(podman_count '^volume rm ')" -eq 0 ]]
	[[ -z "$(podman_line '^create ')" ]]
	[[ -z "$(podman_line '^start ')" ]]
	: >"$LOG"
	export PODMAN_VOLUMES="talkbox-proj.onbox.gitdir"
	run run_rm_container "$PROJECT"
	[[ "$status" -eq 0 ]]
	[[ -n "$(podman_line '^volume rm -f talkbox-proj.onbox.gitdir$')" ]]
	[[ "$(podman_count '^volume rm ')" -eq 1 ]]
	[[ -z "$(podman_line '^rmi ')" ]]
}

@test "run_netbox_recontain commits the source before removing and recreates volumes, container and image" {
	load_lifecycle_plan
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	export PODMAN_CONTAINERS="talkbox-proj.onbox"
	export PODMAN_VOLUMES="talkbox-proj.netbox.worktree talkbox-proj.netbox.gitdir"
	run run_netbox_recontain "$PROJECT" no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	local commit_line rm_line volrm_line populate_line create_line start_line stop_line
	commit_line="$(podman_line_no '^commit talkbox-proj.onbox talkbox-proj.netbox.root$')"
	rm_line="$(podman_line_no '^rm -f --volumes talkbox-proj.netbox$')"
	volrm_line="$(podman_line_no '^volume rm -f talkbox-proj.netbox.worktree$')"
	populate_line="$(podman_line_no 'talkbox-proj.netbox.worktree:/talkbox/target')"
	create_line="$(podman_line_no '^create ')"
	start_line="$(podman_line_no '^start talkbox-proj.netbox$')"
	stop_line="$(podman_line_no '^stop -t 5 talkbox-proj.netbox$')"
	[[ -n "$commit_line" && -n "$rm_line" && -n "$volrm_line" && -n "$populate_line" && -n "$create_line" && -n "$start_line" && -n "$stop_line" ]]
	[[ "$commit_line" -lt "$rm_line" ]]
	[[ "$rm_line" -lt "$volrm_line" ]]
	[[ "$volrm_line" -lt "$populate_line" ]]
	[[ "$populate_line" -lt "$create_line" ]]
	[[ "$create_line" -lt "$start_line" ]]
	[[ "$start_line" -lt "$stop_line" ]]
	[[ -n "$(podman_line '^volume rm -f talkbox-proj.netbox.gitdir$')" ]]
	[[ -z "$(podman_line '^volume create ')" ]]
	[[ -n "$(podman_line '^exec talkbox-proj.netbox setup.sh$')" ]]
	[[ "$(podman_count 'image exists')" -eq 0 ]]
	local create populate
	create="$(podman_create_line)"
	line_has_token "$create" '--name=talkbox-proj.netbox'
	line_has_token "$create" 'talkbox-proj.netbox.root'
	line_has_token "$create" '--init'
	line_has_token "$create" 'TALKBOX_CONTAINER_TYPE=netbox'
	line_lacks_token "$create" '--tmpfs'
	populate="$(podman_line 'talkbox-proj.netbox.worktree:/talkbox/target')"
	line_has_token "$populate" "$PROJECT:/talkbox/source:ro"
}

@test "run_netbox_recontain skips the commit when the source is base and probes the base image" {
	load_lifecycle_plan
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	run run_netbox_recontain "$PROJECT" no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	[[ "$(podman_count '^commit ')" -eq 0 ]]
	[[ -n "$(podman_line "^image exists $(base_image_name)$")" ]]
	[[ "$(podman_count '^build ')" -eq 0 ]]
	[[ -n "$(podman_line '^volume create talkbox-proj.netbox.gitdir$')" ]]
	line_has_token "$(podman_create_line)" "$(base_image_name)"
	: >"$LOG"
	export PODMAN_IMAGES=""
	run run_netbox_recontain "$PROJECT" no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	[[ -n "$(podman_line '^build ')" ]]
}

@test "run_netbox_recontain removes and repopulates the write volumes when present" {
	load_lifecycle_plan
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	export PODMAN_CONTAINERS="talkbox-proj.onbox"
	export PODMAN_VOLUMES="talkbox-proj.netbox.worktree talkbox-proj.netbox.gitdir talkbox-proj.netbox.write.talkbox-wdata"
	# shellcheck disable=SC2034 # arrays are consumed by nameref parameters
	local -a srcs=('/host/data') dsts=('/talkbox/wdata')
	run run_netbox_recontain "$PROJECT" no READ_MOUNTS WRITE_MOUNTS srcs dsts PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	[[ -n "$(podman_line '^volume rm -f talkbox-proj.netbox.write.talkbox-wdata$')" ]]
	[[ "$(podman_count '^volume rm ')" -eq 3 ]]
	[[ "$(podman_count '^run --rm --network=none')" -eq 2 ]]
	local populate
	populate="$(podman_line 'talkbox-proj.netbox.write.talkbox-wdata:/talkbox/target')"
	line_has_token "$populate" '/host/data:/talkbox/source:ro'
}

@test "run_offbox_recontain commits the netbox source before removing and recreating, with no nft step" {
	load_lifecycle_plan
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	export PODMAN_CONTAINERS="talkbox-proj.netbox"
	export PODMAN_VOLUMES="talkbox-proj.offbox.worktree talkbox-proj.offbox.gitdir"
	# shellcheck disable=SC2034 # array is passed by name to the executor
	DENY=(1.1.1.1)
	run run_offbox_recontain "$PROJECT" no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	local commit_line rm_line volrm_line populate_line create_line start_line stop_line
	commit_line="$(podman_line_no '^commit talkbox-proj.netbox talkbox-proj.offbox.root$')"
	rm_line="$(podman_line_no '^rm -f --volumes talkbox-proj.offbox$')"
	volrm_line="$(podman_line_no '^volume rm -f talkbox-proj.offbox.worktree$')"
	populate_line="$(podman_line_no 'talkbox-proj.offbox.worktree:/talkbox/target')"
	create_line="$(podman_line_no '^create ')"
	start_line="$(podman_line_no '^start talkbox-proj.offbox$')"
	stop_line="$(podman_line_no '^stop -t 5 talkbox-proj.offbox$')"
	[[ -n "$commit_line" && -n "$rm_line" && -n "$volrm_line" && -n "$populate_line" && -n "$create_line" && -n "$start_line" && -n "$stop_line" ]]
	[[ "$commit_line" -lt "$rm_line" ]]
	[[ "$rm_line" -lt "$volrm_line" ]]
	[[ "$volrm_line" -lt "$populate_line" ]]
	[[ "$populate_line" -lt "$create_line" ]]
	[[ "$create_line" -lt "$start_line" ]]
	[[ "$start_line" -lt "$stop_line" ]]
	[[ -n "$(podman_line '^volume rm -f talkbox-proj.offbox.gitdir$')" ]]
	[[ "$(podman_count 'nsenter')" -eq 0 ]]
	[[ "$(podman_count 'image exists')" -eq 0 ]]
	local create
	create="$(podman_create_line)"
	line_has_token "$create" '--name=talkbox-proj.offbox'
	line_has_token "$create" 'talkbox-proj.offbox.root'
	line_has_token "$create" 'TALKBOX_CONTAINER_TYPE=offbox'
	line_lacks_token "$create" '--tmpfs'
}

@test "run_netbox_rebuild builds the base image first, then commits and recreates the container" {
	load_lifecycle_plan
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	export PODMAN_CONTAINERS="talkbox-proj.onbox"
	export PODMAN_VOLUMES="talkbox-proj.netbox.worktree talkbox-proj.netbox.gitdir"
	run run_netbox_rebuild "$PROJECT" no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	local build_line commit_line rm_line populate_line create_line start_line stop_line
	build_line="$(podman_line_no '^build ')"
	commit_line="$(podman_line_no '^commit talkbox-proj.onbox talkbox-proj.netbox.root$')"
	rm_line="$(podman_line_no '^rm -f --volumes talkbox-proj.netbox$')"
	populate_line="$(podman_line_no 'talkbox-proj.netbox.worktree:/talkbox/target')"
	create_line="$(podman_line_no '^create ')"
	start_line="$(podman_line_no '^start talkbox-proj.netbox$')"
	stop_line="$(podman_line_no '^stop -t 5 talkbox-proj.netbox$')"
	[[ -n "$build_line" && -n "$commit_line" && -n "$rm_line" && -n "$populate_line" && -n "$create_line" && -n "$start_line" && -n "$stop_line" ]]
	[[ "$build_line" -lt "$commit_line" ]]
	[[ "$commit_line" -lt "$rm_line" ]]
	[[ "$rm_line" -lt "$populate_line" ]]
	[[ "$populate_line" -lt "$create_line" ]]
	[[ "$create_line" -lt "$start_line" ]]
	[[ "$start_line" -lt "$stop_line" ]]
	[[ "$(podman_count 'image exists')" -eq 0 ]]
	local build
	build="$(podman_line '^build ')"
	line_has_token "$build" '-t'
	line_has_token "$build" "$(base_image_name)"
	line_has_token "$build" "$TALKBOX_ROOT/image/Containerfile"
	[[ -n "$(podman_line '^volume rm -f talkbox-proj.netbox.gitdir$')" ]]
	[[ -n "$(podman_line '^exec talkbox-proj.netbox setup.sh$')" ]]
	[[ "$(podman_count 'unshare')" -eq 0 ]]
}

@test "run_offbox_rebuild builds the base image first, then commits and recreates the container" {
	load_lifecycle_plan
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	export PODMAN_CONTAINERS="talkbox-proj.netbox"
	export PODMAN_VOLUMES="talkbox-proj.offbox.worktree talkbox-proj.offbox.gitdir"
	# shellcheck disable=SC2034 # array is passed by name to the executor
	DENY=(1.1.1.1)
	run run_offbox_rebuild "$PROJECT" no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	local build_line commit_line rm_line populate_line create_line start_line stop_line
	build_line="$(podman_line_no '^build ')"
	commit_line="$(podman_line_no '^commit talkbox-proj.netbox talkbox-proj.offbox.root$')"
	rm_line="$(podman_line_no '^rm -f --volumes talkbox-proj.offbox$')"
	populate_line="$(podman_line_no 'talkbox-proj.offbox.worktree:/talkbox/target')"
	create_line="$(podman_line_no '^create ')"
	start_line="$(podman_line_no '^start talkbox-proj.offbox$')"
	stop_line="$(podman_line_no '^stop -t 5 talkbox-proj.offbox$')"
	[[ -n "$build_line" && -n "$commit_line" && -n "$rm_line" && -n "$populate_line" && -n "$create_line" && -n "$start_line" && -n "$stop_line" ]]
	[[ "$build_line" -lt "$commit_line" ]]
	[[ "$commit_line" -lt "$rm_line" ]]
	[[ "$rm_line" -lt "$populate_line" ]]
	[[ "$populate_line" -lt "$create_line" ]]
	[[ "$create_line" -lt "$start_line" ]]
	[[ "$start_line" -lt "$stop_line" ]]
	[[ "$(podman_count 'image exists')" -eq 0 ]]
	[[ "$(podman_count 'nsenter')" -eq 0 ]]
	[[ -n "$(podman_line '^volume rm -f talkbox-proj.offbox.gitdir$')" ]]
	local populate
	populate="$(podman_line 'talkbox-proj.offbox.worktree:/talkbox/target')"
	line_has_token "$populate" "$PROJECT:/talkbox/source:ro"
}

@test "run_netbox_rm_container removes the container, its volumes and its root image when the root image exists" {
	load_lifecycle_plan
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	export PODMAN_IMAGES="talkbox-proj.netbox.root"
	export PODMAN_VOLUMES="talkbox-proj.netbox.worktree talkbox-proj.netbox.gitdir talkbox-proj.netbox.write.talkbox-wdata"
	# shellcheck disable=SC2034 # arrays are consumed by nameref parameters
	local -a dsts=('/talkbox/wdata')
	run run_netbox_rm_container "$PROJECT" dsts
	[[ "$status" -eq 0 ]]
	[[ -n "$(podman_line '^rm -f --volumes talkbox-proj.netbox$')" ]]
	[[ -n "$(podman_line '^volume rm -f talkbox-proj.netbox.worktree$')" ]]
	[[ -n "$(podman_line '^volume rm -f talkbox-proj.netbox.gitdir$')" ]]
	[[ -n "$(podman_line '^volume rm -f talkbox-proj.netbox.write.talkbox-wdata$')" ]]
	[[ "$(podman_count '^volume rm ')" -eq 3 ]]
	local rm_line volrm_line rmi_line
	rm_line="$(podman_line_no '^rm -f --volumes talkbox-proj.netbox$')"
	volrm_line="$(podman_line_no '^volume rm -f talkbox-proj.netbox.worktree$')"
	rmi_line="$(podman_line_no '^rmi talkbox-proj.netbox.root$')"
	[[ -n "$rm_line" && -n "$volrm_line" && -n "$rmi_line" ]]
	[[ "$rm_line" -lt "$volrm_line" ]]
	[[ "$volrm_line" -lt "$rmi_line" ]]
}

@test "run_netbox_rm_container omits the rmi when the root image does not exist" {
	load_lifecycle_plan
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	export PODMAN_VOLUMES="talkbox-proj.netbox.worktree talkbox-proj.netbox.gitdir"
	run run_netbox_rm_container "$PROJECT" DSTS
	[[ "$status" -eq 0 ]]
	[[ -n "$(podman_line '^rm -f --volumes talkbox-proj.netbox$')" ]]
	[[ -n "$(podman_line '^volume rm -f talkbox-proj.netbox.worktree$')" ]]
	[[ -n "$(podman_line '^volume rm -f talkbox-proj.netbox.gitdir$')" ]]
	[[ "$(podman_count '^rmi ')" -eq 0 ]]
}

@test "run_offbox_rm_container removes the container, its volumes and its root image when the root image exists" {
	load_lifecycle_plan
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	export PODMAN_IMAGES="talkbox-proj.offbox.root"
	export PODMAN_VOLUMES="talkbox-proj.offbox.worktree talkbox-proj.offbox.gitdir talkbox-proj.offbox.write.talkbox-wdata"
	# shellcheck disable=SC2034 # arrays are consumed by nameref parameters
	local -a dsts=('/talkbox/wdata')
	run run_offbox_rm_container "$PROJECT" dsts
	[[ "$status" -eq 0 ]]
	[[ -n "$(podman_line '^rm -f --volumes talkbox-proj.offbox$')" ]]
	[[ -n "$(podman_line '^volume rm -f talkbox-proj.offbox.worktree$')" ]]
	[[ -n "$(podman_line '^volume rm -f talkbox-proj.offbox.gitdir$')" ]]
	[[ -n "$(podman_line '^volume rm -f talkbox-proj.offbox.write.talkbox-wdata$')" ]]
	[[ -n "$(podman_line '^rmi talkbox-proj.offbox.root$')" ]]
}

@test "run_offbox_rm_container omits the rmi when the root image does not exist" {
	load_lifecycle_plan
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	export PODMAN_VOLUMES="talkbox-proj.offbox.worktree talkbox-proj.offbox.gitdir"
	run run_offbox_rm_container "$PROJECT" DSTS
	[[ "$status" -eq 0 ]]
	[[ -n "$(podman_line '^rm -f --volumes talkbox-proj.offbox$')" ]]
	[[ "$(podman_count '^rmi ')" -eq 0 ]]
}

@test "netbox and offbox rm-container volume removal is guarded by volume existence" {
	load_lifecycle_plan
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	run run_netbox_rm_container "$PROJECT" DSTS
	[[ "$status" -eq 0 ]]
	[[ "$(podman_count '^volume rm ')" -eq 0 ]]
	: >"$LOG"
	run run_offbox_rm_container "$PROJECT" DSTS
	[[ "$status" -eq 0 ]]
	[[ "$(podman_count '^volume rm ')" -eq 0 ]]
}

@test "plan_volume_rm emits podman volume rm -f only when the volume exists" {
	load_lifecycle_plan
	stub_volumes 'talkbox-proj.onbox.gitdir'
	local args=()
	plan_volume_rm args 'talkbox-proj.onbox.gitdir'
	[[ "$(plan_subcommands args)" == 'volume' ]]
	plan_has_volume_rm args 'talkbox-proj.onbox.gitdir'
	stub_volumes
	args=()
	plan_volume_rm args 'talkbox-proj.onbox.gitdir'
	[[ ${#args[@]} -eq 0 ]]
	plan_has_volume_rm_none args 'talkbox-proj.onbox.gitdir'
}

@test "run_rm_image refuses to remove the base image while it is in use by other containers" {
	load_lifecycle_plan
	use_podman_shim
	export PODMAN_PS_NAMES="other-box"
	run run_rm_image "$PROJECT"
	[[ "$status" -ne 0 ]]
	[[ "$output" == *'talkbox:'* ]]
	[[ "$(podman_count '^rmi ')" -eq 0 ]]
	: >"$LOG"
	run run_netbox_rm_image "$PROJECT"
	[[ "$status" -ne 0 ]]
	[[ "$output" == *'talkbox:'* ]]
	[[ "$(podman_count '^rmi ')" -eq 0 ]]
	: >"$LOG"
	run run_offbox_rm_image "$PROJECT"
	[[ "$status" -ne 0 ]]
	[[ "$output" == *'talkbox:'* ]]
	[[ "$(podman_count '^rmi ')" -eq 0 ]]
}

@test "prune_external_image_containers queries external containers by ancestor and force-removes each returned ID" {
	load_lifecycle_plan
	local shimdir log
	shimdir="$BATS_TEST_TMPDIR/shim"
	log="$BATS_TEST_TMPDIR/podman.log"
	mkdir -p "$shimdir"
	cat >"$shimdir/podman" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>'$log'
if [[ "\$*" == *'ps -a --external'* ]]; then
	printf 'ext1\n'
	printf 'ext2\n'
fi
exit 0
EOF
	chmod +x "$shimdir/podman"
	PATH="$shimdir:$PATH" run prune_external_image_containers "$(base_image_name)"
	[[ "$status" -eq 0 ]]
	[[ "$(grep -c -- '--external --filter ancestor=talkbox/base:latest' "$log")" -ge 1 ]]
	[[ "$(grep -c '^rm -f ext1$' "$log")" -eq 1 ]]
	[[ "$(grep -c '^rm -f ext2$' "$log")" -eq 1 ]]
}

@test "prune_external_image_containers silently succeeds when no external working containers match" {
	load_lifecycle_plan
	local shimdir log
	shimdir="$BATS_TEST_TMPDIR/shim"
	log="$BATS_TEST_TMPDIR/podman.log"
	mkdir -p "$shimdir"
	cat >"$shimdir/podman" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>'$log'
exit 0
EOF
	chmod +x "$shimdir/podman"
	PATH="$shimdir:$PATH" run prune_external_image_containers "$(base_image_name)"
	[[ "$status" -eq 0 ]]
	[[ "$(grep -c -- '--external --filter ancestor=talkbox/base:latest' "$log")" -ge 1 ]]
	[[ "$(grep -c '^rm ' "$log" || true)" -eq 0 ]]
}

@test "run_rm_image prunes external working containers before removing the base image" {
	load_lifecycle_plan
	local shimdir log ctr
	shimdir="$BATS_TEST_TMPDIR/shim"
	log="$BATS_TEST_TMPDIR/podman.log"
	mkdir -p "$shimdir"
	ctr="$(onbox_container_name "$PROJECT")"
	cat >"$shimdir/podman" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>'$log'
if [[ "\$*" == *'ps -a --external'* ]]; then
	printf 'ext1\n'
fi
if [[ "\$*" == *"container exists $ctr"* ]]; then
	exit 1
fi
exit 0
EOF
	chmod +x "$shimdir/podman"
	PATH="$shimdir:$PATH" run run_rm_image "$PROJECT"
	[[ "$status" -eq 0 ]]
	local ext_line rm_line rmi_line
	ext_line="$(grep -n -- '--external --filter ancestor=talkbox/base:latest' "$log" | head -n 1 | cut -d: -f1)"
	rm_line="$(grep -n '^rm -f ext1$' "$log" | head -n 1 | cut -d: -f1)"
	rmi_line="$(grep -n '^rmi talkbox/base:latest$' "$log" | head -n 1 | cut -d: -f1)"
	[[ -n "$ext_line" && -n "$rm_line" && -n "$rmi_line" ]]
	[[ "$ext_line" -lt "$rm_line" ]]
	[[ "$rm_line" -lt "$rmi_line" ]]
}

@test "run_netbox_rm_image prunes external working containers before removing the base image" {
	load_lifecycle_plan
	local shimdir log ctr
	shimdir="$BATS_TEST_TMPDIR/shim"
	log="$BATS_TEST_TMPDIR/podman.log"
	mkdir -p "$shimdir"
	ctr="$(netbox_container_name "$PROJECT")"
	cat >"$shimdir/podman" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>'$log'
if [[ "\$*" == *'ps -a --external'* ]]; then
	printf 'ext1\n'
fi
if [[ "\$*" == *"container exists $ctr"* ]]; then
	exit 1
fi
exit 0
EOF
	chmod +x "$shimdir/podman"
	PATH="$shimdir:$PATH" run run_netbox_rm_image "$PROJECT"
	[[ "$status" -eq 0 ]]
	local ext_line rm_line rmi_line
	ext_line="$(grep -n -- '--external --filter ancestor=talkbox/base:latest' "$log" | head -n 1 | cut -d: -f1)"
	rm_line="$(grep -n '^rm -f ext1$' "$log" | head -n 1 | cut -d: -f1)"
	rmi_line="$(grep -n '^rmi talkbox/base:latest$' "$log" | head -n 1 | cut -d: -f1)"
	[[ -n "$ext_line" && -n "$rm_line" && -n "$rmi_line" ]]
	[[ "$ext_line" -lt "$rm_line" ]]
	[[ "$rm_line" -lt "$rmi_line" ]]
}

@test "run_offbox_rm_image prunes external working containers before removing the base image" {
	load_lifecycle_plan
	local shimdir log ctr
	shimdir="$BATS_TEST_TMPDIR/shim"
	log="$BATS_TEST_TMPDIR/podman.log"
	mkdir -p "$shimdir"
	ctr="$(offbox_container_name "$PROJECT")"
	cat >"$shimdir/podman" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>'$log'
if [[ "\$*" == *'ps -a --external'* ]]; then
	printf 'ext1\n'
fi
if [[ "\$*" == *"container exists $ctr"* ]]; then
	exit 1
fi
exit 0
EOF
	chmod +x "$shimdir/podman"
	PATH="$shimdir:$PATH" run run_offbox_rm_image "$PROJECT"
	[[ "$status" -eq 0 ]]
	local ext_line rm_line rmi_line
	ext_line="$(grep -n -- '--external --filter ancestor=talkbox/base:latest' "$log" | head -n 1 | cut -d: -f1)"
	rm_line="$(grep -n '^rm -f ext1$' "$log" | head -n 1 | cut -d: -f1)"
	rmi_line="$(grep -n '^rmi talkbox/base:latest$' "$log" | head -n 1 | cut -d: -f1)"
	[[ -n "$ext_line" && -n "$rm_line" && -n "$rmi_line" ]]
	[[ "$ext_line" -lt "$rm_line" ]]
	[[ "$rm_line" -lt "$rmi_line" ]]
}
