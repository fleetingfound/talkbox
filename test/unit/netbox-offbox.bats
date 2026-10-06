# shellcheck disable=SC2030,SC2031 # bats runs each test in a subshell; the PODMAN_* exports are scoped to their own test
load helpers

load_netbox_plan() {
	load_lib naming.sh
	load_lib mounts.sh
	load_lib network.sh
	load_lib containers.sh
}

array_contains() {
	local value="$1"
	shift
	local element
	for element in "$@"; do
		if [[ "$element" == "$value" ]]; then
			return 0
		fi
	done
	return 1
}

array_has_none() {
	local needle="$1"
	shift
	local element
	for element in "$@"; do
		if [[ "$element" == *"$needle"* ]]; then
			return 1
		fi
	done
	return 0
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

@test "inheritance planner uses the base image when no source container exists" {
	load_netbox_plan
	[[ "$(inherit_source netbox no no no no '')" == base ]]
	[[ "$(inherit_source offbox no no no no '')" == base ]]
}

@test "inheritance planner defaults netbox to onbox when onbox exists" {
	load_netbox_plan
	[[ "$(inherit_source netbox yes no no no '')" == onbox ]]
}

@test "inheritance planner defaults offbox to netbox, then onbox, then base" {
	load_netbox_plan
	[[ "$(inherit_source offbox yes yes no no '')" == netbox ]]
	[[ "$(inherit_source offbox no yes no no '')" == netbox ]]
	[[ "$(inherit_source offbox yes no no '')" == onbox ]]
	[[ "$(inherit_source offbox no no no no '')" == base ]]
}

@test "inheritance planner --fresh prevents root filesystem inheritance" {
	load_netbox_plan
	[[ "$(inherit_source netbox yes no no yes '')" == base ]]
	[[ "$(inherit_source offbox yes yes no yes '')" == base ]]
}

@test "inheritance planner --inherit selects the explicit source" {
	load_netbox_plan
	[[ "$(inherit_source netbox yes yes yes no offbox)" == offbox ]]
	[[ "$(inherit_source offbox yes yes no no onbox)" == onbox ]]
	[[ "$(inherit_source netbox yes yes no no netbox)" == netbox ]]
}

@test "inheritance planner falls back to base when the --inherit source does not exist" {
	load_netbox_plan
	[[ "$(inherit_source netbox no no no no onbox)" == base ]]
	[[ "$(inherit_source netbox yes no no no offbox)" == base ]]
	[[ "$(inherit_source offbox no no no no netbox)" == base ]]
}

@test "inheritance planner --fresh overrides an --inherit selection" {
	load_netbox_plan
	[[ "$(inherit_source netbox yes yes yes no offbox)" == offbox ]]
	[[ "$(inherit_source netbox yes yes yes yes offbox)" == base ]]
}

@test "volume-population planner runs a no-network helper with the host source read-only" {
	load_netbox_plan
	local args=()
	plan_volume_populate args 'talkbox-proj.netbox.worktree' host "$PROJECT"
	[[ "$(plan_subcommands args)" == 'run' ]]
	array_contains '--rm' "${args[@]}"
	array_contains '--network=none' "${args[@]}"
	array_contains "$PROJECT:/talkbox/source:ro" "${args[@]}"
	array_contains 'talkbox-proj.netbox.worktree:/talkbox/target' "${args[@]}"
	array_has_none '/talkbox/target:ro' "${args[@]}"
	array_contains 'cp' "${args[@]}"
	array_has_none '--init' "${args[@]}"
	array_has_none '--tmpfs' "${args[@]}"
}

@test "volume-population planner mounts a source volume read-write" {
	load_netbox_plan
	local args=()
	plan_volume_populate args 'talkbox-proj.offbox.worktree' volume 'talkbox-proj.netbox.worktree'
	[[ "$(plan_subcommands args)" == 'run' ]]
	array_contains '--network=none' "${args[@]}"
	array_contains 'talkbox-proj.netbox.worktree:/talkbox/source' "${args[@]}"
	array_has_none '/talkbox/source:ro' "${args[@]}"
	array_contains 'talkbox-proj.offbox.worktree:/talkbox/target' "${args[@]}"
	array_contains 'cp' "${args[@]}"
}

@test "volume-population planner opens the run with the exact no-network prefix tokens" {
	load_netbox_plan
	local -a host_args=() volume_args=()
	plan_volume_populate host_args 'talkbox-proj.netbox.worktree' host "$PROJECT"
	[[ "${host_args[0]}" == podman ]]
	[[ "${host_args[1]}" == run ]]
	[[ "${host_args[2]}" == --rm ]]
	[[ "${host_args[3]}" == --network=none ]]
	[[ "${host_args[4]}" == --userns=keep-id:uid=1000,gid=1000 ]]
	[[ "${host_args[5]}" == -v ]]
	[[ "${host_args[6]}" == "$PROJECT:/talkbox/source:ro" ]]
	plan_volume_populate volume_args 'talkbox-proj.offbox.worktree' volume 'talkbox-proj.netbox.worktree'
	[[ "${volume_args[0]}" == podman ]]
	[[ "${volume_args[2]}" == --rm ]]
	[[ "${volume_args[3]}" == --network=none ]]
	[[ "${volume_args[4]}" == --userns=keep-id:uid=1000,gid=1000 ]]
	[[ "${volume_args[5]}" == -v ]]
	[[ "${volume_args[6]}" == 'talkbox-proj.netbox.worktree:/talkbox/source' ]]
}

@test "netbox and offbox populate plans open every podman run with the exact no-network prefix" {
	load_netbox_plan
	# shellcheck disable=SC2034 # arrays are consumed by nameref parameters
	local -a srcs=('/host/data') dsts=('/talkbox/wdata') plan=()
	plan_netbox_populate plan "$PROJECT" srcs dsts
	plan_offbox_populate plan "$PROJECT" base srcs dsts
	[[ "$(plan_subcommands plan)" == $'run\nrun\nrun\nrun' ]]
	local i
	for ((i = 0; i < ${#plan[@]}; i++)); do
		if [[ "${plan[i]}" == podman ]]; then
			[[ "${plan[i + 1]}" == run ]]
			[[ "${plan[i + 2]}" == --rm ]]
			[[ "${plan[i + 3]}" == --network=none ]]
			[[ "${plan[i + 4]}" == --userns=keep-id:uid=1000,gid=1000 ]]
		fi
	done
}

@test "netbox populate copies the worktree and write mounts from the host but never touches the gitdir volume" {
	load_netbox_plan
	# shellcheck disable=SC2034 # arrays are consumed by nameref parameters
	local -a srcs=('/host/data') dsts=('/talkbox/wdata') plan=()
	plan_netbox_populate plan "$PROJECT" srcs dsts
	[[ "$(plan_subcommands plan)" == $'run\nrun' ]]
	array_has_none 'talkbox-proj.netbox.gitdir' "${plan[@]}"
}

@test "offbox populate copies from the host when the root source is base and never touches the gitdir volume" {
	load_netbox_plan
	# shellcheck disable=SC2034 # arrays are consumed by nameref parameters
	local -a srcs=('/host/data') dsts=('/talkbox/wdata') plan=()
	plan_offbox_populate plan "$PROJECT" base srcs dsts
	[[ "$(plan_subcommands plan)" == $'run\nrun' ]]
	array_has_none 'talkbox-proj.offbox.gitdir' "${plan[@]}"
}

@test "run_netbox uses the base image and populates the worktree from the host when no source container exists" {
	load_netbox_plan
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	run run_netbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	[[ "$(podman_count '^commit ')" -eq 0 ]]
	[[ "$(podman_count '^build ')" -eq 0 ]]
	[[ "$(podman_count 'gitdir:/talkbox')" -eq 0 ]]
	local create populate
	create="$(podman_create_line)"
	line_has_token "$create" "$(base_image_name)"
	populate="$(podman_line 'talkbox-proj.netbox.worktree:/talkbox/target')"
	line_has_token "$populate" '--network=none'
	line_has_token "$populate" "$PROJECT:/talkbox/source:ro"
	[[ "$(podman_line_no 'talkbox-proj.netbox.worktree:/talkbox/target')" -lt "$(podman_line_no '^create ')" ]]
	[[ "$(podman_line_no '^volume create talkbox-proj.netbox.gitdir$')" -lt "$(podman_line_no '^create ')" ]]
	[[ -n "$(podman_line '^start talkbox-proj.netbox$')" ]]
}

@test "run_netbox create path creates the gitdir volume after populate and before create" {
	load_netbox_plan
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	run run_netbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	local populate_line volcreate_line create_line
	populate_line="$(podman_line_no 'talkbox-proj.netbox.worktree:/talkbox/target')"
	volcreate_line="$(podman_line_no '^volume create talkbox-proj.netbox.gitdir$')"
	create_line="$(podman_line_no '^create ')"
	[[ -n "$populate_line" && -n "$volcreate_line" && -n "$create_line" ]]
	[[ "$populate_line" -lt "$volcreate_line" ]]
	[[ "$volcreate_line" -lt "$create_line" ]]
}

@test "run_netbox create path omits the gitdir volume create when the gitdir volume already exists" {
	load_netbox_plan
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	export PODMAN_VOLUMES="talkbox-proj.netbox.gitdir"
	run run_netbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	[[ -z "$(podman_line '^volume create ')" ]]
	line_has_token "$(podman_create_line)" 'talkbox-proj.netbox.gitdir:/working/talkbox-proj/.git'
}

@test "run_netbox probes the base image and builds it when missing on the create path" {
	load_netbox_plan
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	run run_netbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	[[ -n "$(podman_line "^image exists $(base_image_name)$")" ]]
	[[ "$(podman_count '^build ')" -eq 0 ]]
	: >"$LOG"
	export PODMAN_IMAGES=""
	run run_netbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	[[ -n "$(podman_line "^image exists $(base_image_name)$")" ]]
	[[ "$(podman_count '^commit ')" -eq 0 ]]
	local build_line populate_line create_line
	build_line="$(podman_line_no '^build ')"
	populate_line="$(podman_line_no 'talkbox-proj.netbox.worktree:/talkbox/target')"
	create_line="$(podman_line_no '^create ')"
	[[ -n "$build_line" && -n "$populate_line" && -n "$create_line" ]]
	[[ "$build_line" -lt "$populate_line" ]]
	[[ "$populate_line" -lt "$create_line" ]]
	local build
	build="$(podman_line '^build ')"
	line_has_token "$build" '-t'
	line_has_token "$build" "$(base_image_name)"
	line_has_token "$build" "$TALKBOX_ROOT/image/Containerfile"
}

@test "run_netbox commits the onbox container as the netbox root image when onbox exists" {
	load_netbox_plan
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	export PODMAN_CONTAINERS="talkbox-proj.onbox"
	run run_netbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	[[ -n "$(podman_line '^commit talkbox-proj.onbox talkbox-proj.netbox.root$')" ]]
	[[ "$(podman_line_no '^commit ')" -lt "$(podman_line_no 'talkbox-proj.netbox.worktree:/talkbox/target')" ]]
	[[ "$(podman_line_no '^commit ')" -lt "$(podman_line_no '^create ')" ]]
	[[ "$(podman_count 'image exists')" -eq 0 ]]
	line_has_token "$(podman_create_line)" 'talkbox-proj.netbox.root'
}

@test "run_netbox create args mount the worktree volume, name the container, use pasta with the DNS-forward suffix and drop caps" {
	load_netbox_plan
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	run run_netbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	local create
	create="$(podman_create_line)"
	line_has_token "$create" 'talkbox-proj.netbox.worktree:/working/talkbox-proj'
	line_has_token "$create" '--name=talkbox-proj.netbox'
	line_has_token "$create" '--workdir=/working/talkbox-proj'
	line_has_token "$create" '--userns=keep-id:uid=1000,gid=1000'
	line_has_token "$create" '--network=pasta:--dns-forward,169.254.1.1,--map-guest-addr,none'
	[[ "$create" != *'-i,lo'* ]]
	line_has_token "$create" '--cap-drop=NET_ADMIN'
	line_has_token "$create" '--cap-drop=NET_RAW'
}

@test "run_netbox forwards pasta -T ports" {
	load_netbox_plan
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	# shellcheck disable=SC2054 # -T,<port> tokens are single array elements
	# shellcheck disable=SC2034 # ports is consumed by nameref parameters
	local -a ports=(-T,8080 -T,9090)
	run run_netbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS ports DENY ALLOW
	[[ "$status" -eq 0 ]]
	line_has_token "$(podman_create_line)" '--network=pasta:-T,8080,-T,9090,--dns-forward,169.254.1.1,--map-guest-addr,none'
}

@test "run_netbox keeps read mounts read-only and write mounts as volumes, populating them from the host" {
	load_netbox_plan
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	local home="$BATS_TEST_TMPDIR/home"
	mkdir -p "$home"
	# shellcheck disable=SC2034 # arrays are consumed by nameref parameters
	local -a read_mounts=() write_mounts=() srcs=() dsts=()
	mount_args read_mounts read "$BATS_TEST_TMPDIR/absent" "$PROJECT" "$home" '/host/data:/talkbox/wdata'
	mount_entries srcs dsts write "$BATS_TEST_TMPDIR/absent" "$PROJECT" "$home" '/host/data:/talkbox/wdata'
	# shellcheck disable=SC2034 # write_mounts is consumed by nameref in run_netbox
	write_mounts=("-v" "$(netbox_write_volume "$PROJECT" "$(dest_slug "${dsts[0]}")"):${dsts[0]}")
	run run_netbox "$PROJECT" 'true' no read_mounts write_mounts srcs dsts PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	local create populate
	create="$(podman_create_line)"
	line_has_token "$create" '/host/data:/talkbox/wdata:ro'
	line_has_token "$create" 'talkbox-proj.netbox.write.talkbox-wdata:/talkbox/wdata'
	line_lacks_token "$create" 'talkbox-proj.netbox.write.talkbox-wdata:/talkbox/wdata:ro'
	populate="$(podman_line 'talkbox-proj.netbox.write.talkbox-wdata:/talkbox/target')"
	line_has_token "$populate" '/host/data:/talkbox/source:ro'
}

@test "run_netbox create args include GPU options, --init ahead of the image, dotfiles, prompt env vars, and no tmpfs" {
	load_netbox_plan
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	# shellcheck disable=SC2034 # global consumed by the sourced containers.sh
	TALKBOX_GPU=yes
	run run_netbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	local create img init_at img_at
	create="$(podman_create_line)"
	img="$(base_image_name)"
	line_has_token "$create" 'nvidia.com/gpu=all'
	line_has_token "$create" 'keep-groups'
	line_has_token "$create" '--init'
	init_at="$(line_token_at "$create" --init)"
	img_at="$(line_token_at "$create" "$img")"
	[[ "$init_at" -gt 0 ]]
	[[ "$init_at" -lt "$img_at" ]]
	line_has_token "$create" "$TALKBOX_ROOT/defaults/dotfiles:/talkbox/dotfiles.global:ro"
	line_has_token "$create" 'TALKBOX_PROJECT_SLUG=talkbox-proj'
	line_has_token "$create" 'TALKBOX_CONTAINER_TYPE=netbox'
	line_has_token "$create" 'sleep'
	line_has_token "$create" 'infinity'
	line_lacks_token "$create" '--tmpfs'
	line_lacks_token "$create" '--rm'
	[[ "$create" != *'/run/talkbox'* ]]
}

@test "run_netbox adds the git mounts and git identity env vars for a git-tracked project only" {
	load_netbox_plan
	use_podman_shim
	git -C "$PROJECT" init -q
	git -C "$PROJECT" config user.name host-user
	git -C "$PROJECT" config user.email host@example.com
	run run_netbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	local create
	create="$(podman_create_line)"
	line_has_token "$create" "$PROJECT/.git:/host/git:ro"
	line_has_token "$create" 'talkbox-proj.netbox.gitdir:/working/talkbox-proj/.git'
	line_has_token "$create" 'TALKBOX_GIT_USER_NAME=host-user'
	line_has_token "$create" 'TALKBOX_GIT_USER_EMAIL=host@example.com'
	local plain="$BATS_TEST_TMPDIR/plain"
	mkdir -p "$plain"
	: >"$LOG"
	run run_netbox "$plain" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	create="$(podman_create_line)"
	[[ "$create" != *'/host/git'* ]]
	[[ "$create" != *'.gitdir'* ]]
	[[ "$create" != *'TALKBOX_GIT_USER'* ]]
}

@test "run_netbox emits the three git mounts as consecutive tokens in the shared order" {
	load_netbox_plan
	use_podman_shim
	git -C "$PROJECT" init -q
	run run_netbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	local create
	create="$(podman_create_line)"
	[[ "$create" == *"-v $PROJECT/.git:/host/git:ro -v talkbox-proj.netbox.gitdir:/working/talkbox-proj/.git -v $TALKBOX_ROOT/lib/merge.sh:/talkbox/lib/merge.sh:ro"* ]]
}

@test "run_offbox create args restrict pasta to loopback, exclude talkbox0, mount the worktree volume and drop caps" {
	load_netbox_plan
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	run run_offbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	local create
	create="$(podman_create_line)"
	line_has_token "$create" '--network=pasta:-i,lo,-I,talkbox0'
	line_has_token "$create" 'talkbox-proj.offbox.worktree:/working/talkbox-proj'
	line_has_token "$create" '--name=talkbox-proj.offbox'
	line_has_token "$create" '--cap-drop=NET_ADMIN'
	line_has_token "$create" '--cap-drop=NET_RAW'
}

@test "run_offbox forwards pasta -T ports alongside the loopback restriction" {
	load_netbox_plan
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	# shellcheck disable=SC2054 # -T,<port> tokens are single array elements
	# shellcheck disable=SC2034 # ports is consumed by nameref parameters
	local -a ports=(-T,8080)
	run run_offbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS ports DENY ALLOW
	[[ "$status" -eq 0 ]]
	line_has_token "$(podman_create_line)" '--network=pasta:-T,8080,-i,lo,-I,talkbox0'
}

@test "run_offbox emits write-mount volumes and read-only read mounts, populating from the host" {
	load_netbox_plan
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	local home="$BATS_TEST_TMPDIR/home"
	mkdir -p "$home"
	# shellcheck disable=SC2034 # arrays are consumed by nameref parameters
	local -a read_mounts=() write_mounts=() srcs=() dsts=()
	mount_args read_mounts read "$BATS_TEST_TMPDIR/absent" "$PROJECT" "$home" '/host/data:/talkbox/wdata'
	mount_entries srcs dsts write "$BATS_TEST_TMPDIR/absent" "$PROJECT" "$home" '/host/data:/talkbox/wdata'
	# shellcheck disable=SC2034 # write_mounts is consumed by nameref in run_offbox
	write_mounts=("-v" "$(offbox_write_volume "$PROJECT" "$(dest_slug "${dsts[0]}")"):${dsts[0]}")
	run run_offbox "$PROJECT" 'true' no read_mounts write_mounts srcs dsts PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	local create populate
	create="$(podman_create_line)"
	line_has_token "$create" '/host/data:/talkbox/wdata:ro'
	line_has_token "$create" 'talkbox-proj.offbox.write.talkbox-wdata:/talkbox/wdata'
	line_lacks_token "$create" 'talkbox-proj.offbox.write.talkbox-wdata:/talkbox/wdata:ro'
	populate="$(podman_line 'talkbox-proj.offbox.write.talkbox-wdata:/talkbox/target')"
	line_has_token "$populate" '/host/data:/talkbox/source:ro'
}

@test "run_offbox create args include GPU options, --init, prompt env vars and no tmpfs" {
	load_netbox_plan
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	# shellcheck disable=SC2034 # global consumed by the sourced containers.sh
	TALKBOX_GPU=yes
	run run_offbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	local create img init_at img_at
	create="$(podman_create_line)"
	img="$(base_image_name)"
	line_has_token "$create" 'nvidia.com/gpu=all'
	line_has_token "$create" 'keep-groups'
	line_has_token "$create" '--init'
	init_at="$(line_token_at "$create" --init)"
	img_at="$(line_token_at "$create" "$img")"
	[[ "$init_at" -gt 0 ]]
	[[ "$init_at" -lt "$img_at" ]]
	line_has_token "$create" 'TALKBOX_PROJECT_SLUG=talkbox-proj'
	line_has_token "$create" 'TALKBOX_CONTAINER_TYPE=offbox'
	line_lacks_token "$create" '--tmpfs'
	[[ "$create" != *'/run/talkbox'* ]]
}

@test "run_offbox emits git identity env vars for a git-tracked project but not for a non-git project" {
	load_netbox_plan
	use_podman_shim
	git -C "$PROJECT" init -q
	git -C "$PROJECT" config user.name host-user
	git -C "$PROJECT" config user.email host@example.com
	run run_offbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	local create
	create="$(podman_create_line)"
	line_has_token "$create" 'TALKBOX_GIT_USER_NAME=host-user'
	line_has_token "$create" 'TALKBOX_GIT_USER_EMAIL=host@example.com'
	local plain="$BATS_TEST_TMPDIR/plain"
	mkdir -p "$plain"
	: >"$LOG"
	run run_offbox "$plain" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	create="$(podman_create_line)"
	[[ "$create" != *'TALKBOX_GIT_USER'* ]]
}

@test "run_offbox commits netbox, else onbox, else uses the base image and populates from the host" {
	load_netbox_plan
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	# shellcheck disable=SC2034 # arrays are consumed by nameref parameters
	local -a srcs=('/host/data') dsts=('/talkbox/wdata')
	export PODMAN_CONTAINERS="talkbox-proj.onbox talkbox-proj.netbox"
	run run_offbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS srcs dsts PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	[[ -n "$(podman_line '^commit talkbox-proj.netbox talkbox-proj.offbox.root$')" ]]
	: >"$LOG"
	export PODMAN_CONTAINERS="talkbox-proj.onbox"
	run run_offbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS srcs dsts PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	[[ -n "$(podman_line '^commit talkbox-proj.onbox talkbox-proj.offbox.root$')" ]]
	: >"$LOG"
	export PODMAN_CONTAINERS=""
	run run_offbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS srcs dsts PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	[[ "$(podman_count '^commit ')" -eq 0 ]]
	line_has_token "$(podman_create_line)" "$(base_image_name)"
	local populate
	populate="$(podman_line 'talkbox-proj.offbox.worktree:/talkbox/target')"
	line_has_token "$populate" "$PROJECT:/talkbox/source:ro"
}

@test "TALKBOX_FRESH skips the commit and uses the base image even when source containers exist" {
	load_netbox_plan
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	export PODMAN_CONTAINERS="talkbox-proj.onbox"
	# shellcheck disable=SC2034 # globals consumed by the sourced containers.sh
	TALKBOX_FRESH=yes
	run run_netbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	[[ "$(podman_count '^commit ')" -eq 0 ]]
	line_has_token "$(podman_create_line)" "$(base_image_name)"
	: >"$LOG"
	run run_offbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	[[ "$(podman_count '^commit ')" -eq 0 ]]
	line_has_token "$(podman_create_line)" "$(base_image_name)"
}

@test "TALKBOX_INHERIT selects the commit source" {
	load_netbox_plan
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	export PODMAN_CONTAINERS="talkbox-proj.onbox talkbox-proj.offbox"
	# shellcheck disable=SC2034 # global consumed by the sourced containers.sh
	TALKBOX_INHERIT=offbox
	run run_netbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	[[ -n "$(podman_line '^commit talkbox-proj.offbox talkbox-proj.netbox.root$')" ]]
	: >"$LOG"
	export PODMAN_CONTAINERS="talkbox-proj.onbox talkbox-proj.netbox"
	# shellcheck disable=SC2034 # global consumed by the sourced containers.sh
	TALKBOX_INHERIT=onbox
	run run_offbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	[[ -n "$(podman_line '^commit talkbox-proj.onbox talkbox-proj.offbox.root$')" ]]
	local populate
	populate="$(podman_line 'talkbox-proj.offbox.worktree:/talkbox/target')"
	line_has_token "$populate" "$PROJECT:/talkbox/source:ro"
}

@test "run_offbox populates from the netbox volumes when inheriting from netbox and they exist" {
	load_netbox_plan
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	export PODMAN_CONTAINERS="talkbox-proj.netbox"
	export PODMAN_VOLUMES="talkbox-proj.netbox.worktree talkbox-proj.netbox.write.talkbox-wdata"
	# shellcheck disable=SC2034 # arrays are consumed by nameref parameters
	local -a srcs=('/host/data') dsts=('/talkbox/wdata')
	run run_offbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS srcs dsts PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	local populate
	populate="$(podman_line 'talkbox-proj.offbox.worktree:/talkbox/target')"
	line_has_token "$populate" 'talkbox-proj.netbox.worktree:/talkbox/source'
	line_lacks_token "$populate" 'talkbox-proj.netbox.worktree:/talkbox/source:ro'
	populate="$(podman_line 'talkbox-proj.offbox.write.talkbox-wdata:/talkbox/target')"
	line_has_token "$populate" 'talkbox-proj.netbox.write.talkbox-wdata:/talkbox/source'
	line_lacks_token "$populate" 'talkbox-proj.netbox.write.talkbox-wdata:/talkbox/source:ro'
}

@test "run_offbox falls back to host sources per volume when the netbox volumes are missing" {
	load_netbox_plan
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	export PODMAN_CONTAINERS="talkbox-proj.netbox"
	export PODMAN_VOLUMES="talkbox-proj.netbox.worktree"
	# shellcheck disable=SC2034 # arrays are consumed by nameref parameters
	local -a srcs=('/host/data') dsts=('/talkbox/wdata')
	run run_offbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS srcs dsts PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	local populate
	populate="$(podman_line 'talkbox-proj.offbox.worktree:/talkbox/target')"
	line_has_token "$populate" 'talkbox-proj.netbox.worktree:/talkbox/source'
	populate="$(podman_line 'talkbox-proj.offbox.write.talkbox-wdata:/talkbox/target')"
	line_has_token "$populate" '/host/data:/talkbox/source:ro'
}

@test "run_netbox applies the nft deny rules before running setup.sh and runs setup.sh before the user command" {
	load_netbox_plan
	local shimdir log ctr
	shimdir="$BATS_TEST_TMPDIR/shim"
	log="$BATS_TEST_TMPDIR/podman.log"
	mkdir -p "$shimdir"
	cat >"$shimdir/podman" <<EOF
#!/usr/bin/env bash
cat >/dev/null 2>&1 || true
printf '%s\n' "\$*" >>'$log'
if [[ "\$*" == *'inspect -f {{.State.Pid}}'* ]]; then
	printf '12345\n'
fi
exit 0
EOF
	chmod +x "$shimdir/podman"
	ctr="$(netbox_container_name "$PROJECT")"
	# shellcheck disable=SC2034 # arrays are consumed by nameref parameters
	local -a deny=(1.1.1.1) allow=() srcs=() dsts=()
	PATH="$shimdir:$PATH" run run_netbox "$PROJECT" 'echo hi' no READ_MOUNTS WRITE_MOUNTS srcs dsts PORTS deny allow
	[[ "$status" -eq 0 ]]
	local start_line nft_line setup_line cmd_line
	start_line="$(grep -n "^start $ctr$" "$log" | head -n 1 | cut -d: -f1)"
	nft_line="$(grep -n 'unshare.*nsenter.*nft' "$log" | head -n 1 | cut -d: -f1)"
	setup_line="$(grep -n "exec $ctr setup.sh$" "$log" | head -n 1 | cut -d: -f1)"
	cmd_line="$(grep -n 'bash -c echo hi' "$log" | head -n 1 | cut -d: -f1)"
	[[ -n "$start_line" && -n "$nft_line" && -n "$setup_line" && -n "$cmd_line" ]]
	[[ "$start_line" -lt "$nft_line" ]]
	[[ "$nft_line" -lt "$setup_line" ]]
	[[ "$setup_line" -lt "$cmd_line" ]]
}

@test "run_offbox runs setup.sh after start and before the user command, with no nft step" {
	load_netbox_plan
	local shimdir log ctr
	shimdir="$BATS_TEST_TMPDIR/shim"
	log="$BATS_TEST_TMPDIR/podman.log"
	mkdir -p "$shimdir"
	cat >"$shimdir/podman" <<EOF
#!/usr/bin/env bash
cat >/dev/null 2>&1 || true
printf '%s\n' "\$*" >>'$log'
exit 0
EOF
	chmod +x "$shimdir/podman"
	ctr="$(offbox_container_name "$PROJECT")"
	# shellcheck disable=SC2034 # arrays are consumed by nameref parameters
	local -a deny=(1.1.1.1) allow=() srcs=() dsts=()
	PATH="$shimdir:$PATH" run run_offbox "$PROJECT" 'echo hi' no READ_MOUNTS WRITE_MOUNTS srcs dsts PORTS deny allow
	[[ "$status" -eq 0 ]]
	local start_line setup_line cmd_line
	start_line="$(grep -n "^start $ctr$" "$log" | head -n 1 | cut -d: -f1)"
	setup_line="$(grep -n "exec $ctr setup.sh$" "$log" | head -n 1 | cut -d: -f1)"
	cmd_line="$(grep -n 'bash -c echo hi' "$log" | head -n 1 | cut -d: -f1)"
	[[ -n "$start_line" && -n "$setup_line" && -n "$cmd_line" ]]
	[[ "$start_line" -lt "$setup_line" ]]
	[[ "$setup_line" -lt "$cmd_line" ]]
	[[ "$(grep -c 'nsenter' "$log" || true)" -eq 0 ]]
}

@test "run_netbox recontain and rebuild run setup.sh after the nft deny install and before stopping the container" {
	load_netbox_plan
	local shimdir log ctr
	shimdir="$BATS_TEST_TMPDIR/shim"
	log="$BATS_TEST_TMPDIR/podman.log"
	mkdir -p "$shimdir"
	cat >"$shimdir/podman" <<EOF
#!/usr/bin/env bash
cat >/dev/null 2>&1 || true
printf '%s\n' "\$*" >>'$log'
if [[ "\$*" == *'inspect -f {{.State.Pid}}'* ]]; then
	printf '12345\n'
fi
exit 0
EOF
	chmod +x "$shimdir/podman"
	ctr="$(netbox_container_name "$PROJECT")"
	# shellcheck disable=SC2034 # arrays are consumed by nameref parameters
	local -a deny=(1.1.1.1) allow=() srcs=() dsts=()
	local nft_line setup_line stop_line
	PATH="$shimdir:$PATH" run run_netbox_recontain "$PROJECT" no READ_MOUNTS WRITE_MOUNTS srcs dsts PORTS deny allow
	[[ "$status" -eq 0 ]]
	nft_line="$(grep -n 'unshare.*nsenter.*nft' "$log" | head -n 1 | cut -d: -f1)"
	setup_line="$(grep -n "exec $ctr setup.sh$" "$log" | head -n 1 | cut -d: -f1)"
	stop_line="$(grep -n "^stop " "$log" | head -n 1 | cut -d: -f1)"
	[[ -n "$nft_line" && -n "$setup_line" && -n "$stop_line" ]]
	[[ "$nft_line" -lt "$setup_line" ]]
	[[ "$setup_line" -lt "$stop_line" ]]
	: >"$log"
	PATH="$shimdir:$PATH" run run_netbox_rebuild "$PROJECT" no READ_MOUNTS WRITE_MOUNTS srcs dsts PORTS deny allow
	[[ "$status" -eq 0 ]]
	nft_line="$(grep -n 'unshare.*nsenter.*nft' "$log" | head -n 1 | cut -d: -f1)"
	setup_line="$(grep -n "exec $ctr setup.sh$" "$log" | head -n 1 | cut -d: -f1)"
	stop_line="$(grep -n "^stop " "$log" | head -n 1 | cut -d: -f1)"
	[[ -n "$nft_line" && -n "$setup_line" && -n "$stop_line" ]]
	[[ "$nft_line" -lt "$setup_line" ]]
	[[ "$setup_line" -lt "$stop_line" ]]
}

@test "run_offbox recontain and rebuild run setup.sh after start and before stopping the container, with no nft step" {
	load_netbox_plan
	local shimdir log ctr
	shimdir="$BATS_TEST_TMPDIR/shim"
	log="$BATS_TEST_TMPDIR/podman.log"
	mkdir -p "$shimdir"
	cat >"$shimdir/podman" <<EOF
#!/usr/bin/env bash
cat >/dev/null 2>&1 || true
printf '%s\n' "\$*" >>'$log'
exit 0
EOF
	chmod +x "$shimdir/podman"
	ctr="$(offbox_container_name "$PROJECT")"
	# shellcheck disable=SC2034 # arrays are consumed by nameref parameters
	local -a deny=(1.1.1.1) allow=() srcs=() dsts=()
	local start_line setup_line stop_line
	PATH="$shimdir:$PATH" run run_offbox_recontain "$PROJECT" no READ_MOUNTS WRITE_MOUNTS srcs dsts PORTS deny allow
	[[ "$status" -eq 0 ]]
	start_line="$(grep -n "^start $ctr$" "$log" | head -n 1 | cut -d: -f1)"
	setup_line="$(grep -n "exec $ctr setup.sh$" "$log" | head -n 1 | cut -d: -f1)"
	stop_line="$(grep -n "^stop " "$log" | head -n 1 | cut -d: -f1)"
	[[ -n "$start_line" && -n "$setup_line" && -n "$stop_line" ]]
	[[ "$start_line" -lt "$setup_line" ]]
	[[ "$setup_line" -lt "$stop_line" ]]
	[[ "$(grep -c 'nsenter' "$log" || true)" -eq 0 ]]
	: >"$log"
	PATH="$shimdir:$PATH" run run_offbox_rebuild "$PROJECT" no READ_MOUNTS WRITE_MOUNTS srcs dsts PORTS deny allow
	[[ "$status" -eq 0 ]]
	start_line="$(grep -n "^start $ctr$" "$log" | head -n 1 | cut -d: -f1)"
	setup_line="$(grep -n "exec $ctr setup.sh$" "$log" | head -n 1 | cut -d: -f1)"
	stop_line="$(grep -n "^stop " "$log" | head -n 1 | cut -d: -f1)"
	[[ -n "$start_line" && -n "$setup_line" && -n "$stop_line" ]]
	[[ "$start_line" -lt "$setup_line" ]]
	[[ "$setup_line" -lt "$stop_line" ]]
	[[ "$(grep -c 'nsenter' "$log" || true)" -eq 0 ]]
}

@test "run_netbox create line is byte-identical to the recontain recreate line from the base image" {
	load_netbox_plan
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	run run_netbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	local create_create
	create_create="$(podman_create_line)"
	[[ -n "$create_create" ]]
	: >"$LOG"
	run run_netbox_recontain "$PROJECT" no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	[[ "$(podman_create_line)" == "$create_create" ]]
}

@test "run_netbox create line is byte-identical to the recontain recreate line when inheriting from onbox" {
	load_netbox_plan
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	export PODMAN_CONTAINERS="talkbox-proj.onbox"
	run run_netbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	local create_create
	create_create="$(podman_create_line)"
	line_has_token "$create_create" 'talkbox-proj.netbox.root'
	: >"$LOG"
	run run_netbox_recontain "$PROJECT" no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	[[ "$(podman_create_line)" == "$create_create" ]]
}

@test "run_offbox create line is byte-identical to the recontain recreate line when inheriting from netbox" {
	load_netbox_plan
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	export PODMAN_CONTAINERS="talkbox-proj.netbox"
	run run_offbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	local create_create
	create_create="$(podman_create_line)"
	line_has_token "$create_create" 'talkbox-proj.offbox.root'
	: >"$LOG"
	run run_offbox_recontain "$PROJECT" no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	[[ "$(podman_create_line)" == "$create_create" ]]
}

@test "run_netbox and run_netbox_recontain build identical create lines under TALKBOX_FRESH and TALKBOX_INHERIT" {
	load_netbox_plan
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	export PODMAN_CONTAINERS="talkbox-proj.onbox talkbox-proj.offbox"
	# shellcheck disable=SC2034 # globals consumed by the sourced containers.sh
	TALKBOX_FRESH=yes
	run run_netbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	[[ "$(podman_count '^commit ')" -eq 0 ]]
	local fresh_create
	fresh_create="$(podman_create_line)"
	: >"$LOG"
	run run_netbox_recontain "$PROJECT" no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	[[ "$(podman_count '^commit ')" -eq 0 ]]
	[[ "$(podman_create_line)" == "$fresh_create" ]]
	: >"$LOG"
	unset TALKBOX_FRESH
	# shellcheck disable=SC2034 # global consumed by the sourced containers.sh
	TALKBOX_INHERIT=offbox
	run run_netbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	local inherit_create
	inherit_create="$(podman_create_line)"
	[[ -n "$(podman_line '^commit talkbox-proj.offbox talkbox-proj.netbox.root$')" ]]
	: >"$LOG"
	run run_netbox_recontain "$PROJECT" no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	[[ "$(podman_count '^commit ')" -eq 1 ]]
	[[ "$(podman_create_line)" == "$inherit_create" ]]
}
