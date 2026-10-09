# shellcheck disable=SC2030,SC2031 # bats runs each test in a subshell; the PODMAN_* exports are scoped to their own test
load helpers

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

# Prints the plan produced by plan_container_volumes_rm with one podman
# subcommand per line, so tests can assert the emitted volume removals.
volume_rm_plan() {
	local -a args=()
	plan_container_volumes_rm args "$PROJECT" "$1"
	local arg line=""
	for arg in "${args[@]}"; do
		if [[ "$arg" == podman && -n "$line" ]]; then
			printf '%s\n' "$line"
			line=""
		fi
		if [[ -n "$line" ]]; then
			line+=" $arg"
		else
			line="$arg"
		fi
	done
	printf '%s\n' "$line"
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

@test "run_recreate onbox no removes, recreates and starts the onbox container, installing nft, running setup and stopping" {
	load_container_libs
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	# shellcheck disable=SC2034 # array is passed by name to the executor
	DENY=(1.1.1.1)
	export PODMAN_VOLUMES="talkbox-proj.onbox.gitdir"
	run run_recreate onbox no "$PROJECT" no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	local rm_line volrm_line create_line start_line nft_line setup_line stop_line
	rm_line="$(podman_line_no '^rm -f --volumes talkbox-proj.onbox$')"
	volrm_line="$(podman_line_no '^volume rm -f talkbox-proj.onbox.gitdir$')"
	create_line="$(podman_line_no '^create ')"
	start_line="$(podman_line_no '^start talkbox-proj.onbox$')"
	nft_line="$(podman_line_no 'unshare.*nsenter.*nft')"
	setup_line="$(podman_line_no '^exec talkbox-proj.onbox setup.sh$')"
	stop_line="$(podman_line_no '^stop -t 5 talkbox-proj.onbox$')"
	[[ -n "$rm_line" && -n "$volrm_line" && -n "$create_line" && -n "$start_line" && -n "$nft_line" && -n "$setup_line" && -n "$stop_line" ]]
	[[ "$rm_line" -lt "$volrm_line" ]]
	[[ "$volrm_line" -lt "$create_line" ]]
	[[ "$create_line" -lt "$start_line" ]]
	[[ "$start_line" -lt "$nft_line" ]]
	[[ "$nft_line" -lt "$setup_line" ]]
	[[ "$setup_line" -lt "$stop_line" ]]
	[[ -z "$(podman_line '^volume create ')" ]]
	local probe_line
	probe_line="$(podman_line_no "^image exists $(base_image_name)$")"
	[[ -n "$probe_line" ]]
	[[ "$probe_line" -lt "$create_line" ]]
	[[ "$(podman_count 'image exists')" -eq 1 ]]
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

@test "run_recreate onbox no probes the base image and builds it when missing before recreating the onbox container" {
	load_container_libs
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	export PODMAN_VOLUMES="talkbox-proj.onbox.gitdir"
	run run_recreate onbox no "$PROJECT" no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	[[ -n "$(podman_line "^image exists $(base_image_name)$")" ]]
	[[ "$(podman_count '^build ')" -eq 0 ]]
	: >"$LOG"
	export PODMAN_IMAGES=""
	run run_recreate onbox no "$PROJECT" no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	[[ -n "$(podman_line "^image exists $(base_image_name)$")" ]]
	[[ "$(podman_count '^commit ')" -eq 0 ]]
	local build_line rm_line volrm_line create_line start_line
	build_line="$(podman_line_no '^build ')"
	rm_line="$(podman_line_no '^rm -f --volumes talkbox-proj.onbox$')"
	volrm_line="$(podman_line_no '^volume rm -f talkbox-proj.onbox.gitdir$')"
	create_line="$(podman_line_no '^create ')"
	start_line="$(podman_line_no '^start talkbox-proj.onbox$')"
	[[ -n "$build_line" && -n "$rm_line" && -n "$volrm_line" && -n "$create_line" && -n "$start_line" ]]
	[[ "$build_line" -lt "$rm_line" ]]
	[[ "$rm_line" -lt "$volrm_line" ]]
	[[ "$volrm_line" -lt "$create_line" ]]
	[[ "$create_line" -lt "$start_line" ]]
	local build
	build="$(podman_line '^build ')"
	line_has_token "$build" '-t'
	line_has_token "$build" "$(base_image_name)"
	line_has_token "$build" "$TALKBOX_ROOT/image/Containerfile"
}

@test "run_recreate onbox no removes only the volumes that exist and creates the missing gitdir volume" {
	load_container_libs
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	run run_recreate onbox no "$PROJECT" no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	[[ "$(podman_count '^volume rm ')" -eq 0 ]]
	[[ -n "$(podman_line '^volume create talkbox-proj.onbox.gitdir$')" ]]
	[[ "$(podman_line_no '^rm -f --volumes talkbox-proj.onbox$')" -lt "$(podman_line_no '^volume create talkbox-proj.onbox.gitdir$')" ]]
	[[ "$(podman_line_no '^volume create talkbox-proj.onbox.gitdir$')" -lt "$(podman_line_no '^create ')" ]]
}

@test "run_recreate onbox yes builds the base image first, then installs nft and runs setup before stopping" {
	load_container_libs
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	# shellcheck disable=SC2034 # array is passed by name to the executor
	DENY=(1.1.1.1)
	export PODMAN_VOLUMES="talkbox-proj.onbox.gitdir"
	run run_recreate onbox yes "$PROJECT" no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	local build_line rm_line create_line start_line nft_line setup_line stop_line
	build_line="$(podman_line_no '^build ')"
	rm_line="$(podman_line_no '^rm -f --volumes talkbox-proj.onbox$')"
	create_line="$(podman_line_no '^create ')"
	start_line="$(podman_line_no '^start talkbox-proj.onbox$')"
	nft_line="$(podman_line_no 'unshare.*nsenter.*nft')"
	setup_line="$(podman_line_no '^exec talkbox-proj.onbox setup.sh$')"
	stop_line="$(podman_line_no '^stop -t 5 talkbox-proj.onbox$')"
	[[ -n "$build_line" && -n "$rm_line" && -n "$create_line" && -n "$start_line" && -n "$nft_line" && -n "$setup_line" && -n "$stop_line" ]]
	[[ "$build_line" -lt "$rm_line" ]]
	[[ "$rm_line" -lt "$create_line" ]]
	[[ "$create_line" -lt "$start_line" ]]
	[[ "$start_line" -lt "$nft_line" ]]
	[[ "$nft_line" -lt "$setup_line" ]]
	[[ "$setup_line" -lt "$stop_line" ]]
	local build
	build="$(podman_line '^build ')"
	line_has_token "$build" '-t'
	line_has_token "$build" "$(base_image_name)"
	line_has_token "$build" "$TALKBOX_ROOT/image/Containerfile"
	[[ "$(podman_count 'image exists')" -eq 0 ]]
}

@test "run_rm_container removes the container without volume or image commands when nothing exists" {
	load_container_libs
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	local c
	for c in onbox netbox offbox; do
		: >"$LOG"
		run run_rm_container "$c" "$PROJECT"
		[[ "$status" -eq 0 ]]
		[[ -n "$(podman_line "^rm -f --volumes talkbox-proj.$c$")" ]]
		[[ "$(podman_count '^volume rm ')" -eq 0 ]]
		[[ -z "$(podman_line '^create ')" ]]
		[[ -z "$(podman_line '^start ')" ]]
		[[ -z "$(podman_line '^rmi ')" ]]
	done
}

@test "run_rm_container removes the container, its per-container volumes and its root image when present" {
	load_container_libs
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	local -a containers=(onbox netbox offbox)
	# shellcheck disable=SC2034 # per-container data arrays are indexed alongside containers
	local -a volsets=('talkbox-proj.onbox.gitdir' 'talkbox-proj.netbox.worktree talkbox-proj.netbox.gitdir talkbox-proj.netbox.write.talkbox-wdata' 'talkbox-proj.offbox.worktree talkbox-proj.offbox.gitdir talkbox-proj.offbox.write.talkbox-wdata')
	local -a roots=("" "talkbox-proj.netbox.root" "talkbox-proj.offbox.root")
	local -a counts=(1 3 3)
	local i c vol rm_line volrm_line rmi_line
	for i in "${!containers[@]}"; do
		c="${containers[$i]}"
		: >"$LOG"
		export PODMAN_CONTAINERS="talkbox-proj.$c"
		export PODMAN_INSPECT_MOUNTS="${volsets[$i]}"
		export PODMAN_VOLUMES="${volsets[$i]}"
		export PODMAN_IMAGES="${roots[$i]}"
		run run_rm_container "$c" "$PROJECT"
		[[ "$status" -eq 0 ]]
		[[ -n "$(podman_line "^rm -f --volumes talkbox-proj.$c$")" ]]
		# shellcheck disable=SC2206 # the volume set is intended word splitting
		for vol in ${volsets[$i]}; do
			[[ -n "$(podman_line "^volume rm -f $vol$")" ]]
			[[ "$(podman_count "^volume rm -f $vol$")" -eq 1 ]]
		done
		[[ "$(podman_count '^volume rm ')" -eq "${counts[$i]}" ]]
		rm_line="$(podman_line_no "^rm -f --volumes talkbox-proj.$c$")"
		volrm_line="$(podman_line_no "^volume rm -f talkbox-proj.$c.gitdir$")"
		[[ -n "$rm_line" && -n "$volrm_line" ]]
		[[ "$rm_line" -lt "$volrm_line" ]]
		if [[ -n "${roots[$i]}" ]]; then
			rmi_line="$(podman_line_no "^rmi ${roots[$i]}$")"
			[[ -n "$rmi_line" ]]
			[[ "$volrm_line" -lt "$rmi_line" ]]
		else
			[[ "$(podman_count '^rmi ')" -eq 0 ]]
		fi
	done
}

@test "run_recreate netbox no commits the source before removing and recreates volumes, container and image" {
	load_container_libs
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	export PODMAN_CONTAINERS="talkbox-proj.onbox"
	export PODMAN_VOLUMES="talkbox-proj.netbox.worktree talkbox-proj.netbox.gitdir"
	run run_recreate netbox no "$PROJECT" no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
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

@test "run_recreate netbox no skips the commit when the source is base and probes the base image" {
	load_container_libs
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	run run_recreate netbox no "$PROJECT" no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	[[ "$(podman_count '^commit ')" -eq 0 ]]
	[[ -n "$(podman_line "^image exists $(base_image_name)$")" ]]
	[[ "$(podman_count '^build ')" -eq 0 ]]
	[[ -n "$(podman_line '^volume create talkbox-proj.netbox.gitdir$')" ]]
	line_has_token "$(podman_create_line)" "$(base_image_name)"
	: >"$LOG"
	export PODMAN_IMAGES=""
	run run_recreate netbox no "$PROJECT" no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	[[ -n "$(podman_line '^build ')" ]]
}

@test "run_recreate netbox no removes and repopulates the write volumes when present" {
	load_container_libs
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	export PODMAN_CONTAINERS="talkbox-proj.onbox talkbox-proj.netbox"
	export PODMAN_INSPECT_MOUNTS="talkbox-proj.netbox.worktree talkbox-proj.netbox.gitdir talkbox-proj.netbox.write.talkbox-wdata"
	export PODMAN_VOLUMES="talkbox-proj.netbox.worktree talkbox-proj.netbox.gitdir talkbox-proj.netbox.write.talkbox-wdata"
	# shellcheck disable=SC2034 # arrays are consumed by nameref parameters
	local -a srcs=('/host/data') dsts=('/talkbox/wdata')
	run run_recreate netbox no "$PROJECT" no READ_MOUNTS WRITE_MOUNTS srcs dsts PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	[[ -n "$(podman_line '^volume rm -f talkbox-proj.netbox.write.talkbox-wdata$')" ]]
	[[ "$(podman_count '^volume rm ')" -eq 3 ]]
	[[ "$(podman_count '^run --rm --network=none')" -eq 2 ]]
	local populate
	populate="$(podman_line 'talkbox-proj.netbox.write.talkbox-wdata:/talkbox/target')"
	line_has_token "$populate" '/host/data:/talkbox/source:ro'
}

@test "run_recreate netbox no removes the previous configuration's write volumes before repopulating" {
	load_container_libs
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	export PODMAN_CONTAINERS="talkbox-proj.onbox talkbox-proj.netbox"
	export PODMAN_INSPECT_MOUNTS="talkbox-proj.netbox.worktree talkbox-proj.netbox.gitdir talkbox-proj.netbox.write.talkbox-wdata"
	export PODMAN_VOLUMES="talkbox-proj.netbox.worktree talkbox-proj.netbox.gitdir talkbox-proj.netbox.write.talkbox-wdata"
	# shellcheck disable=SC2034 # arrays are consumed by nameref parameters
	local -a srcs=('/host/alt') dsts=('/talkbox/walt')
	run run_recreate netbox no "$PROJECT" no READ_MOUNTS WRITE_MOUNTS srcs dsts PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	[[ -n "$(podman_line '^volume rm -f talkbox-proj.netbox.write.talkbox-wdata$')" ]]
	[[ "$(podman_count '^volume rm ')" -eq 3 ]]
	local populate
	populate="$(podman_line 'talkbox-proj.netbox.write.talkbox-walt:/talkbox/target')"
	[[ -n "$populate" ]]
	line_has_token "$populate" '/host/alt:/talkbox/source:ro'
}

@test "run_recreate offbox no commits the netbox source before removing and recreating, with no nft step" {
	load_container_libs
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	export PODMAN_CONTAINERS="talkbox-proj.netbox"
	export PODMAN_VOLUMES="talkbox-proj.offbox.worktree talkbox-proj.offbox.gitdir"
	# shellcheck disable=SC2034 # array is passed by name to the executor
	DENY=(1.1.1.1)
	run run_recreate offbox no "$PROJECT" no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
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

@test "run_recreate offbox no with no source container probes the base image and skips commit and build when it exists" {
	load_container_libs
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	run run_recreate offbox no "$PROJECT" no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	[[ "$(podman_count '^commit ')" -eq 0 ]]
	[[ -n "$(podman_line "^image exists $(base_image_name)$")" ]]
	[[ "$(podman_count '^build ')" -eq 0 ]]
	line_has_token "$(podman_create_line)" "$(base_image_name)"
	local rm_line populate_line volcreate_line create_line start_line
	rm_line="$(podman_line_no '^rm -f --volumes talkbox-proj.offbox$')"
	populate_line="$(podman_line_no 'talkbox-proj.offbox.worktree:/talkbox/target')"
	volcreate_line="$(podman_line_no '^volume create talkbox-proj.offbox.gitdir$')"
	create_line="$(podman_line_no '^create ')"
	start_line="$(podman_line_no '^start talkbox-proj.offbox$')"
	[[ -n "$rm_line" && -n "$populate_line" && -n "$volcreate_line" && -n "$create_line" && -n "$start_line" ]]
	[[ "$rm_line" -lt "$populate_line" ]]
	[[ "$populate_line" -lt "$volcreate_line" ]]
	[[ "$volcreate_line" -lt "$create_line" ]]
	[[ "$create_line" -lt "$start_line" ]]
}

@test "run_recreate netbox yes builds the base image first, then commits and recreates the container" {
	load_container_libs
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	export PODMAN_CONTAINERS="talkbox-proj.onbox"
	export PODMAN_VOLUMES="talkbox-proj.netbox.worktree talkbox-proj.netbox.gitdir"
	run run_recreate netbox yes "$PROJECT" no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
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

@test "run_recreate netbox yes with no source container builds without probing or committing" {
	load_container_libs
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	run run_recreate netbox yes "$PROJECT" no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	[[ "$(podman_count '^commit ')" -eq 0 ]]
	[[ "$(podman_count 'image exists')" -eq 0 ]]
	local build_line rm_line populate_line volcreate_line create_line start_line
	build_line="$(podman_line_no '^build ')"
	rm_line="$(podman_line_no '^rm -f --volumes talkbox-proj.netbox$')"
	populate_line="$(podman_line_no 'talkbox-proj.netbox.worktree:/talkbox/target')"
	volcreate_line="$(podman_line_no '^volume create talkbox-proj.netbox.gitdir$')"
	create_line="$(podman_line_no '^create ')"
	start_line="$(podman_line_no '^start talkbox-proj.netbox$')"
	[[ -n "$build_line" && -n "$rm_line" && -n "$populate_line" && -n "$volcreate_line" && -n "$create_line" && -n "$start_line" ]]
	[[ "$build_line" -lt "$rm_line" ]]
	[[ "$rm_line" -lt "$populate_line" ]]
	[[ "$populate_line" -lt "$volcreate_line" ]]
	[[ "$volcreate_line" -lt "$create_line" ]]
	[[ "$create_line" -lt "$start_line" ]]
	line_has_token "$(podman_create_line)" "$(base_image_name)"
}

@test "run_recreate offbox yes builds the base image first, then commits and recreates the container" {
	load_container_libs
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	export PODMAN_CONTAINERS="talkbox-proj.netbox"
	export PODMAN_VOLUMES="talkbox-proj.offbox.worktree talkbox-proj.offbox.gitdir"
	# shellcheck disable=SC2034 # array is passed by name to the executor
	DENY=(1.1.1.1)
	run run_recreate offbox yes "$PROJECT" no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
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

@test "run_rm_container removes the inspected write volumes without write dsts" {
	load_container_libs
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	local c rm_line inspect_line
	for c in netbox offbox; do
		: >"$LOG"
		export PODMAN_CONTAINERS="talkbox-proj.$c"
		export PODMAN_INSPECT_MOUNTS="talkbox-proj.$c.write.talkbox-wdata talkbox-proj.$c.write.a-b-c"
		export PODMAN_VOLUMES="talkbox-proj.$c.write.talkbox-wdata talkbox-proj.$c.write.a-b-c"
		run run_rm_container "$c" "$PROJECT"
		[[ "$status" -eq 0 ]]
		rm_line="$(podman_line_no "^rm -f --volumes talkbox-proj.$c$")"
		inspect_line="$(podman_line_no 'inspect -f')"
		[[ -n "$rm_line" && -n "$inspect_line" ]]
		[[ "$inspect_line" -lt "$rm_line" ]]
		[[ -n "$(podman_line "^volume rm -f talkbox-proj.$c.write.talkbox-wdata$")" ]]
		[[ -n "$(podman_line "^volume rm -f talkbox-proj.$c.write.a-b-c$")" ]]
		[[ "$(podman_count '^volume rm ')" -eq 2 ]]
		[[ "$(podman_count '^rmi ')" -eq 0 ]]
	done
}

@test "run_rm_container omits the rmi when the root image does not exist" {
	load_container_libs
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	local c
	for c in netbox offbox; do
		: >"$LOG"
		export PODMAN_VOLUMES="talkbox-proj.$c.worktree talkbox-proj.$c.gitdir"
		run run_rm_container "$c" "$PROJECT"
		[[ "$status" -eq 0 ]]
		[[ -n "$(podman_line "^rm -f --volumes talkbox-proj.$c$")" ]]
		[[ -n "$(podman_line "^volume rm -f talkbox-proj.$c.worktree$")" ]]
		[[ -n "$(podman_line "^volume rm -f talkbox-proj.$c.gitdir$")" ]]
		[[ "$(podman_count '^rmi ')" -eq 0 ]]
		[[ "$(podman_count 'inspect -f')" -eq 0 ]]
		[[ "$(podman_count "^volume rm -f talkbox-proj.$c.write")" -eq 0 ]]
	done
}

@test "rm-container volume removal is guarded by volume existence for every container" {
	load_container_libs
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	local c
	for c in onbox netbox offbox; do
		: >"$LOG"
		run run_rm_container "$c" "$PROJECT"
		[[ "$status" -eq 0 ]]
		[[ "$(podman_count '^volume rm ')" -eq 0 ]]
		[[ "$(podman_count 'inspect -f')" -eq 0 ]]
	done
}

@test "plan_volume_rm emits podman volume rm -f only when the volume exists" {
	load_container_libs
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

@test "plan_container_volumes_rm emits a volume rm for every write volume the container mounts" {
	load_container_libs
	use_podman_shim
	export PODMAN_CONTAINERS="talkbox-proj.netbox"
	export PODMAN_INSPECT_MOUNTS="talkbox-proj.netbox.worktree talkbox-proj.netbox.gitdir talkbox-proj.netbox.write.talkbox-wdata talkbox-proj.netbox.write.a-b-c"
	export PODMAN_VOLUMES="talkbox-proj.netbox.worktree talkbox-proj.netbox.gitdir talkbox-proj.netbox.write.talkbox-wdata talkbox-proj.netbox.write.a-b-c"
	run volume_rm_plan netbox
	[[ "$status" -eq 0 ]]
	[[ "$(printf '%s\n' "$output" | grep -c '^podman volume rm -f talkbox-proj.netbox.worktree$' || true)" -eq 1 ]]
	[[ "$(printf '%s\n' "$output" | grep -c '^podman volume rm -f talkbox-proj.netbox.gitdir$' || true)" -eq 1 ]]
	[[ "$(printf '%s\n' "$output" | grep -c '^podman volume rm -f talkbox-proj.netbox.write.talkbox-wdata$' || true)" -eq 1 ]]
	[[ "$(printf '%s\n' "$output" | grep -c '^podman volume rm -f talkbox-proj.netbox.write.a-b-c$' || true)" -eq 1 ]]
	[[ "$(printf '%s\n' "$output" | grep -c '^podman volume rm -f' || true)" -eq 4 ]]
	[[ "$(printf '%s\n' "$output" | grep -vc '^podman volume rm -f' || true)" -eq 0 ]]
}

@test "run_rm_image refuses to remove the base image while it is in use by other containers" {
	load_container_libs
	use_podman_shim
	export PODMAN_PS_NAMES="other-box"
	run run_rm_image onbox "$PROJECT"
	[[ "$status" -ne 0 ]]
	[[ "$output" == *'talkbox:'* ]]
	[[ "$(podman_count '^rmi ')" -eq 0 ]]
	: >"$LOG"
	run run_rm_image netbox "$PROJECT"
	[[ "$status" -ne 0 ]]
	[[ "$output" == *'talkbox:'* ]]
	[[ "$(podman_count '^rmi ')" -eq 0 ]]
	: >"$LOG"
	run run_rm_image offbox "$PROJECT"
	[[ "$status" -ne 0 ]]
	[[ "$output" == *'talkbox:'* ]]
	[[ "$(podman_count '^rmi ')" -eq 0 ]]
}

@test "prune_external_image_containers queries external containers by ancestor and force-removes each returned ID" {
	load_container_libs
	use_podman_shim
	export PODMAN_EXTERNAL="ext1 ext2"
	run prune_external_image_containers "$(base_image_name)"
	[[ "$status" -eq 0 ]]
	[[ "$(grep -c -- '--external --filter ancestor=talkbox/base:latest' "$PODMAN_LOG")" -ge 1 ]]
	[[ "$(grep -c '^rm -f ext1$' "$PODMAN_LOG")" -eq 1 ]]
	[[ "$(grep -c '^rm -f ext2$' "$PODMAN_LOG")" -eq 1 ]]
}

@test "prune_external_image_containers silently succeeds when no external working containers match" {
	load_container_libs
	use_podman_shim
	run prune_external_image_containers "$(base_image_name)"
	[[ "$status" -eq 0 ]]
	[[ "$(grep -c -- '--external --filter ancestor=talkbox/base:latest' "$PODMAN_LOG")" -ge 1 ]]
	[[ "$(grep -c '^rm ' "$PODMAN_LOG" || true)" -eq 0 ]]
}

@test "run_rm_image prunes external working containers before removing the base image for every container" {
	load_container_libs
	use_podman_shim
	export PODMAN_EXTERNAL="ext1"
	local c ext_line rm_line rmi_line
	for c in onbox netbox offbox; do
		: >"$LOG"
		run run_rm_image "$c" "$PROJECT"
		[[ "$status" -eq 0 ]]
		ext_line="$(log_line_no '--external --filter ancestor=talkbox/base:latest' "$PODMAN_LOG")"
		rm_line="$(log_line_no '^rm -f ext1$' "$PODMAN_LOG")"
		rmi_line="$(log_line_no '^rmi talkbox/base:latest$' "$PODMAN_LOG")"
		[[ -n "$ext_line" && -n "$rm_line" && -n "$rmi_line" ]]
		[[ "$ext_line" -lt "$rm_line" ]]
		[[ "$rm_line" -lt "$rmi_line" ]]
	done
}
