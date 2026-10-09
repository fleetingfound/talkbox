# shellcheck disable=SC2030,SC2031 # bats runs each test in a subshell; the PODMAN_* exports are scoped to their own test
load helpers

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

@test "inheritance planner uses the base image when no source container exists" {
	load_container_libs
	[[ "$(inherit_source netbox no no no no '')" == base ]]
	[[ "$(inherit_source offbox no no no no '')" == base ]]
}

@test "inheritance planner defaults netbox to onbox when onbox exists" {
	load_container_libs
	[[ "$(inherit_source netbox yes no no no '')" == onbox ]]
}

@test "inheritance planner defaults offbox to netbox, then onbox, then base" {
	load_container_libs
	[[ "$(inherit_source offbox yes yes no no '')" == netbox ]]
	[[ "$(inherit_source offbox no yes no no '')" == netbox ]]
	[[ "$(inherit_source offbox yes no no '')" == onbox ]]
	[[ "$(inherit_source offbox no no no no '')" == base ]]
}

@test "inheritance planner --fresh prevents root filesystem inheritance" {
	load_container_libs
	[[ "$(inherit_source netbox yes no no yes '')" == base ]]
	[[ "$(inherit_source offbox yes yes no yes '')" == base ]]
}

@test "inheritance planner --inherit selects the explicit source" {
	load_container_libs
	[[ "$(inherit_source netbox yes yes yes no offbox)" == offbox ]]
	[[ "$(inherit_source offbox yes yes no no onbox)" == onbox ]]
	[[ "$(inherit_source netbox yes yes no no netbox)" == netbox ]]
}

@test "inheritance planner falls back to base when the --inherit source does not exist" {
	load_container_libs
	[[ "$(inherit_source netbox no no no no onbox)" == base ]]
	[[ "$(inherit_source netbox yes no no no offbox)" == base ]]
	[[ "$(inherit_source offbox no no no no netbox)" == base ]]
}

@test "inheritance planner --fresh overrides an --inherit selection" {
	load_container_libs
	[[ "$(inherit_source netbox yes yes yes no offbox)" == offbox ]]
	[[ "$(inherit_source netbox yes yes yes yes offbox)" == base ]]
}

@test "volume-population planner runs a no-network helper with the host source read-only" {
	load_container_libs
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
	load_container_libs
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
	load_container_libs
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

@test "netbox and offbox populate plans from plan_populate_and_create open every podman run with the exact no-network prefix" {
	load_container_libs
	use_podman_shim
	# shellcheck disable=SC2034 # arrays are consumed by nameref parameters
	local -a srcs=('/host/data') dsts=('/talkbox/wdata')
	local c i runs
	for c in netbox offbox; do
		# shellcheck disable=SC2034 # plan is consumed by nameref parameters
		local -a plan=()
		plan_populate_and_create plan "$c" no "$PROJECT" base "$(base_image_name)" READ_MOUNTS WRITE_MOUNTS srcs dsts PORTS
		runs=0
		for ((i = 0; i < ${#plan[@]}; i++)); do
			if [[ "${plan[i]}" == podman && "${plan[$((i + 1))]}" == run ]]; then
				runs=$((runs + 1))
				[[ "${plan[$((i + 2))]}" == --rm ]]
				[[ "${plan[$((i + 3))]}" == --network=none ]]
				[[ "${plan[$((i + 4))]}" == --userns=keep-id:uid=1000,gid=1000 ]]
			fi
		done
		[[ "$runs" -eq 2 ]]
	done
}

@test "plan_populate_and_create seeds the netbox and offbox worktree and write volumes from the host for a base source, never the gitdir volume" {
	load_container_libs
	use_podman_shim
	# shellcheck disable=SC2034 # arrays are consumed by nameref parameters
	local -a srcs=('/host/data') dsts=('/talkbox/wdata')
	local c
	for c in netbox offbox; do
		# shellcheck disable=SC2034 # plan is consumed by nameref parameters
		local -a plan=()
		plan_populate_and_create plan "$c" no "$PROJECT" base "$(base_image_name)" READ_MOUNTS WRITE_MOUNTS srcs dsts PORTS
		array_contains "talkbox-proj.$c.worktree:/talkbox/target" "${plan[@]}"
		array_contains "$PROJECT:/talkbox/source:ro" "${plan[@]}"
		array_contains "talkbox-proj.$c.write.talkbox-wdata:/talkbox/target" "${plan[@]}"
		array_contains '/host/data:/talkbox/source:ro' "${plan[@]}"
		array_has_none "$c.gitdir:/talkbox/target" "${plan[@]}"
	done
}

@test "run_container netbox always seeds its volumes from the host, even when inheriting from offbox" {
	load_container_libs
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	export PODMAN_CONTAINERS="talkbox-proj.offbox"
	export PODMAN_VOLUMES="talkbox-proj.offbox.worktree"
	# shellcheck disable=SC2034 # global consumed by the sourced containers.sh
	TALKBOX_INHERIT=offbox
	run run_container netbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	[[ -n "$(podman_line '^commit talkbox-proj.offbox talkbox-proj.netbox.root$')" ]]
	local populate
	populate="$(podman_line 'talkbox-proj.netbox.worktree:/talkbox/target')"
	line_has_token "$populate" "$PROJECT:/talkbox/source:ro"
	line_lacks_token "$populate" 'talkbox-proj.offbox.worktree:/talkbox/source'
}

@test "run_container netbox uses the base image and populates the worktree from the host when no source container exists" {
	load_container_libs
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	run run_container netbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
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

@test "run_container netbox create path creates the gitdir volume after populate and before create" {
	load_container_libs
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	run run_container netbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	local populate_line volcreate_line create_line
	populate_line="$(podman_line_no 'talkbox-proj.netbox.worktree:/talkbox/target')"
	volcreate_line="$(podman_line_no '^volume create talkbox-proj.netbox.gitdir$')"
	create_line="$(podman_line_no '^create ')"
	[[ -n "$populate_line" && -n "$volcreate_line" && -n "$create_line" ]]
	[[ "$populate_line" -lt "$volcreate_line" ]]
	[[ "$volcreate_line" -lt "$create_line" ]]
}

@test "run_container netbox create path omits the gitdir volume create when the gitdir volume already exists" {
	load_container_libs
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	export PODMAN_VOLUMES="talkbox-proj.netbox.gitdir"
	run run_container netbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	[[ -z "$(podman_line '^volume create ')" ]]
	line_has_token "$(podman_create_line)" 'talkbox-proj.netbox.gitdir:/working/talkbox-proj/.git'
}

@test "run_container netbox probes the base image and builds it when missing on the create path" {
	load_container_libs
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	run run_container netbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	[[ -n "$(podman_line "^image exists $(base_image_name)$")" ]]
	[[ "$(podman_count '^build ')" -eq 0 ]]
	: >"$LOG"
	export PODMAN_IMAGES=""
	run run_container netbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
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

@test "run_container netbox commits the onbox container as the netbox root image when onbox exists" {
	load_container_libs
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	export PODMAN_CONTAINERS="talkbox-proj.onbox"
	run run_container netbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	[[ -n "$(podman_line '^commit talkbox-proj.onbox talkbox-proj.netbox.root$')" ]]
	[[ "$(podman_line_no '^commit ')" -lt "$(podman_line_no 'talkbox-proj.netbox.worktree:/talkbox/target')" ]]
	[[ "$(podman_line_no '^commit ')" -lt "$(podman_line_no '^create ')" ]]
	[[ "$(podman_count 'image exists')" -eq 0 ]]
	line_has_token "$(podman_create_line)" 'talkbox-proj.netbox.root'
}

@test "run_container netbox create args mount the worktree volume, name the container, use pasta with the DNS-forward suffix and drop caps" {
	load_container_libs
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	run run_container netbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
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

@test "run_container netbox forwards pasta -T ports" {
	load_container_libs
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	# shellcheck disable=SC2054 # -T,<port> tokens are single array elements
	# shellcheck disable=SC2034 # ports is consumed by nameref parameters
	local -a ports=(-T,8080 -T,9090)
	run run_container netbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS ports DENY ALLOW
	[[ "$status" -eq 0 ]]
	line_has_token "$(podman_create_line)" '--network=pasta:-T,8080,-T,9090,--dns-forward,169.254.1.1,--map-guest-addr,none'
}

@test "run_container netbox keeps read mounts read-only and write mounts as volumes, populating them from the host" {
	load_container_libs
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	local home="$BATS_TEST_TMPDIR/home"
	mkdir -p "$home"
	local wsrc="$BATS_TEST_TMPDIR/wsrc"
	mkdir -p "$wsrc"
	# shellcheck disable=SC2034 # arrays are consumed by nameref parameters
	local -a read_mounts=() write_mounts=() srcs=() dsts=()
	mount_args read_mounts read "$BATS_TEST_TMPDIR/absent" "$PROJECT" "$home" '/host/data:/talkbox/wdata'
	mount_entries srcs dsts write "$BATS_TEST_TMPDIR/absent" "$PROJECT" "$home" "$wsrc:/talkbox/wdata"
	# shellcheck disable=SC2034 # write_mounts is consumed by nameref in run_container
	write_mounts=("-v" "$(write_volume_of netbox "$PROJECT" "$(dest_slug "${dsts[0]}")"):${dsts[0]}")
	run run_container netbox "$PROJECT" 'true' no read_mounts write_mounts srcs dsts PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	local create populate
	create="$(podman_create_line)"
	line_has_token "$create" '/host/data:/talkbox/wdata:ro'
	line_has_token "$create" 'talkbox-proj.netbox.write.talkbox-wdata:/talkbox/wdata'
	line_lacks_token "$create" 'talkbox-proj.netbox.write.talkbox-wdata:/talkbox/wdata:ro'
	populate="$(podman_line 'talkbox-proj.netbox.write.talkbox-wdata:/talkbox/target')"
	line_has_token "$populate" "$wsrc:/talkbox/source:ro"
}

@test "run_container netbox create args include GPU options, --init ahead of the image, dotfiles, prompt env vars, and no tmpfs" {
	load_container_libs
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	# shellcheck disable=SC2034 # global consumed by the sourced containers.sh
	TALKBOX_GPU=yes
	run run_container netbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
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

@test "run_container netbox adds the git mounts and git identity env vars for a git-tracked project only" {
	load_container_libs
	use_podman_shim
	git -C "$PROJECT" init -q
	git -C "$PROJECT" config user.name host-user
	git -C "$PROJECT" config user.email host@example.com
	run run_container netbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
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
	run run_container netbox "$plain" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	create="$(podman_create_line)"
	[[ "$create" != *'/host/git'* ]]
	[[ "$create" != *'.gitdir'* ]]
	[[ "$create" != *'TALKBOX_GIT_USER'* ]]
}

@test "run_container netbox emits the three git mounts as consecutive tokens in the shared order" {
	load_container_libs
	use_podman_shim
	git -C "$PROJECT" init -q
	run run_container netbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	local create
	create="$(podman_create_line)"
	[[ "$create" == *"-v $PROJECT/.git:/host/git:ro -v talkbox-proj.netbox.gitdir:/working/talkbox-proj/.git -v $TALKBOX_ROOT/lib/merge.sh:/talkbox/lib/merge.sh:ro"* ]]
}

@test "run_container offbox create args restrict pasta to loopback, exclude talkbox0, mount the worktree volume and drop caps" {
	load_container_libs
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	run run_container offbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	local create
	create="$(podman_create_line)"
	line_has_token "$create" '--network=pasta:-i,lo,-I,talkbox0'
	line_has_token "$create" 'talkbox-proj.offbox.worktree:/working/talkbox-proj'
	line_has_token "$create" '--name=talkbox-proj.offbox'
	line_has_token "$create" '--cap-drop=NET_ADMIN'
	line_has_token "$create" '--cap-drop=NET_RAW'
}

@test "run_container offbox forwards pasta -T ports alongside the loopback restriction" {
	load_container_libs
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	# shellcheck disable=SC2054 # -T,<port> tokens are single array elements
	# shellcheck disable=SC2034 # ports is consumed by nameref parameters
	local -a ports=(-T,8080)
	run run_container offbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS ports DENY ALLOW
	[[ "$status" -eq 0 ]]
	line_has_token "$(podman_create_line)" '--network=pasta:-T,8080,-i,lo,-I,talkbox0'
}

@test "run_container offbox emits write-mount volumes and read-only read mounts, populating from the host" {
	load_container_libs
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	local home="$BATS_TEST_TMPDIR/home"
	mkdir -p "$home"
	local wsrc="$BATS_TEST_TMPDIR/wsrc"
	mkdir -p "$wsrc"
	# shellcheck disable=SC2034 # arrays are consumed by nameref parameters
	local -a read_mounts=() write_mounts=() srcs=() dsts=()
	mount_args read_mounts read "$BATS_TEST_TMPDIR/absent" "$PROJECT" "$home" '/host/data:/talkbox/wdata'
	mount_entries srcs dsts write "$BATS_TEST_TMPDIR/absent" "$PROJECT" "$home" "$wsrc:/talkbox/wdata"
	# shellcheck disable=SC2034 # write_mounts is consumed by nameref in run_container
	write_mounts=("-v" "$(write_volume_of offbox "$PROJECT" "$(dest_slug "${dsts[0]}")"):${dsts[0]}")
	run run_container offbox "$PROJECT" 'true' no read_mounts write_mounts srcs dsts PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	local create populate
	create="$(podman_create_line)"
	line_has_token "$create" '/host/data:/talkbox/wdata:ro'
	line_has_token "$create" 'talkbox-proj.offbox.write.talkbox-wdata:/talkbox/wdata'
	line_lacks_token "$create" 'talkbox-proj.offbox.write.talkbox-wdata:/talkbox/wdata:ro'
	populate="$(podman_line 'talkbox-proj.offbox.write.talkbox-wdata:/talkbox/target')"
	line_has_token "$populate" "$wsrc:/talkbox/source:ro"
}

@test "run_container offbox create args include GPU options, --init, prompt env vars and no tmpfs" {
	load_container_libs
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	# shellcheck disable=SC2034 # global consumed by the sourced containers.sh
	TALKBOX_GPU=yes
	run run_container offbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
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

@test "run_container offbox emits git identity env vars for a git-tracked project but not for a non-git project" {
	load_container_libs
	use_podman_shim
	git -C "$PROJECT" init -q
	git -C "$PROJECT" config user.name host-user
	git -C "$PROJECT" config user.email host@example.com
	run run_container offbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	local create
	create="$(podman_create_line)"
	line_has_token "$create" 'TALKBOX_GIT_USER_NAME=host-user'
	line_has_token "$create" 'TALKBOX_GIT_USER_EMAIL=host@example.com'
	local plain="$BATS_TEST_TMPDIR/plain"
	mkdir -p "$plain"
	: >"$LOG"
	run run_container offbox "$plain" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	create="$(podman_create_line)"
	[[ "$create" != *'TALKBOX_GIT_USER'* ]]
}

@test "run_container offbox commits netbox, else onbox, else uses the base image and populates from the host" {
	load_container_libs
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	# shellcheck disable=SC2034 # arrays are consumed by nameref parameters
	local -a srcs=('/host/data') dsts=('/talkbox/wdata')
	export PODMAN_CONTAINERS="talkbox-proj.onbox talkbox-proj.netbox"
	run run_container offbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS srcs dsts PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	[[ -n "$(podman_line '^commit talkbox-proj.netbox talkbox-proj.offbox.root$')" ]]
	: >"$LOG"
	export PODMAN_CONTAINERS="talkbox-proj.onbox"
	run run_container offbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS srcs dsts PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	[[ -n "$(podman_line '^commit talkbox-proj.onbox talkbox-proj.offbox.root$')" ]]
	: >"$LOG"
	export PODMAN_CONTAINERS=""
	run run_container offbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS srcs dsts PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	[[ "$(podman_count '^commit ')" -eq 0 ]]
	line_has_token "$(podman_create_line)" "$(base_image_name)"
	local populate
	populate="$(podman_line 'talkbox-proj.offbox.worktree:/talkbox/target')"
	line_has_token "$populate" "$PROJECT:/talkbox/source:ro"
}

@test "TALKBOX_FRESH skips the commit and uses the base image even when source containers exist" {
	load_container_libs
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	export PODMAN_CONTAINERS="talkbox-proj.onbox"
	# shellcheck disable=SC2034 # globals consumed by the sourced containers.sh
	TALKBOX_FRESH=yes
	run run_container netbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	[[ "$(podman_count '^commit ')" -eq 0 ]]
	line_has_token "$(podman_create_line)" "$(base_image_name)"
	: >"$LOG"
	run run_container offbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	[[ "$(podman_count '^commit ')" -eq 0 ]]
	line_has_token "$(podman_create_line)" "$(base_image_name)"
}

@test "TALKBOX_INHERIT selects the commit source" {
	load_container_libs
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	export PODMAN_CONTAINERS="talkbox-proj.onbox talkbox-proj.offbox"
	# shellcheck disable=SC2034 # global consumed by the sourced containers.sh
	TALKBOX_INHERIT=offbox
	run run_container netbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	[[ -n "$(podman_line '^commit talkbox-proj.offbox talkbox-proj.netbox.root$')" ]]
	: >"$LOG"
	export PODMAN_CONTAINERS="talkbox-proj.onbox talkbox-proj.netbox"
	# shellcheck disable=SC2034 # global consumed by the sourced containers.sh
	TALKBOX_INHERIT=onbox
	run run_container offbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	[[ -n "$(podman_line '^commit talkbox-proj.onbox talkbox-proj.offbox.root$')" ]]
	local populate
	populate="$(podman_line 'talkbox-proj.offbox.worktree:/talkbox/target')"
	line_has_token "$populate" "$PROJECT:/talkbox/source:ro"
}

@test "run_container offbox populates from the netbox volumes when inheriting from netbox and they exist" {
	load_container_libs
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	export PODMAN_CONTAINERS="talkbox-proj.netbox"
	export PODMAN_VOLUMES="talkbox-proj.netbox.worktree talkbox-proj.netbox.write.talkbox-wdata"
	# shellcheck disable=SC2034 # arrays are consumed by nameref parameters
	local -a srcs=('/host/data') dsts=('/talkbox/wdata')
	run run_container offbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS srcs dsts PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	local populate
	populate="$(podman_line 'talkbox-proj.offbox.worktree:/talkbox/target')"
	line_has_token "$populate" 'talkbox-proj.netbox.worktree:/talkbox/source'
	line_lacks_token "$populate" 'talkbox-proj.netbox.worktree:/talkbox/source:ro'
	populate="$(podman_line 'talkbox-proj.offbox.write.talkbox-wdata:/talkbox/target')"
	line_has_token "$populate" 'talkbox-proj.netbox.write.talkbox-wdata:/talkbox/source'
	line_lacks_token "$populate" 'talkbox-proj.netbox.write.talkbox-wdata:/talkbox/source:ro'
}

@test "run_container offbox falls back to host sources per volume when the netbox volumes are missing" {
	load_container_libs
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	export PODMAN_CONTAINERS="talkbox-proj.netbox"
	export PODMAN_VOLUMES="talkbox-proj.netbox.worktree"
	# shellcheck disable=SC2034 # arrays are consumed by nameref parameters
	local -a srcs=('/host/data') dsts=('/talkbox/wdata')
	run run_container offbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS srcs dsts PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	local populate
	populate="$(podman_line 'talkbox-proj.offbox.worktree:/talkbox/target')"
	line_has_token "$populate" 'talkbox-proj.netbox.worktree:/talkbox/source'
	populate="$(podman_line 'talkbox-proj.offbox.write.talkbox-wdata:/talkbox/target')"
	line_has_token "$populate" '/host/data:/talkbox/source:ro'
}

@test "run_container netbox applies the nft deny rules before running setup.sh and runs setup.sh before the user command" {
	load_container_libs
	local ctr
	ctr="$(container_name_of netbox "$PROJECT")"
	use_podman_shim
	export PODMAN_CONTAINERS="$ctr"
	# shellcheck disable=SC2034 # arrays are consumed by nameref parameters
	local -a deny=(1.1.1.1) allow=() srcs=() dsts=()
	run run_container netbox "$PROJECT" 'echo hi' no READ_MOUNTS WRITE_MOUNTS srcs dsts PORTS deny allow
	[[ "$status" -eq 0 ]]
	local start_line nft_line setup_line cmd_line
	start_line="$(log_line_no "^start $ctr$" "$PODMAN_LOG")"
	nft_line="$(log_line_no 'unshare.*nsenter.*nft' "$PODMAN_LOG")"
	setup_line="$(log_line_no "exec $ctr setup.sh$" "$PODMAN_LOG")"
	cmd_line="$(log_line_no 'bash -c echo hi' "$PODMAN_LOG")"
	[[ -n "$start_line" && -n "$nft_line" && -n "$setup_line" && -n "$cmd_line" ]]
	[[ "$start_line" -lt "$nft_line" ]]
	[[ "$nft_line" -lt "$setup_line" ]]
	[[ "$setup_line" -lt "$cmd_line" ]]
}

@test "run_container offbox runs setup.sh after start and before the user command, with no nft step" {
	load_container_libs
	local ctr
	ctr="$(container_name_of offbox "$PROJECT")"
	use_podman_shim
	export PODMAN_CONTAINERS="$ctr"
	# shellcheck disable=SC2034 # arrays are consumed by nameref parameters
	local -a deny=(1.1.1.1) allow=() srcs=() dsts=()
	run run_container offbox "$PROJECT" 'echo hi' no READ_MOUNTS WRITE_MOUNTS srcs dsts PORTS deny allow
	[[ "$status" -eq 0 ]]
	local start_line setup_line cmd_line
	start_line="$(log_line_no "^start $ctr$" "$PODMAN_LOG")"
	setup_line="$(log_line_no "exec $ctr setup.sh$" "$PODMAN_LOG")"
	cmd_line="$(log_line_no 'bash -c echo hi' "$PODMAN_LOG")"
	[[ -n "$start_line" && -n "$setup_line" && -n "$cmd_line" ]]
	[[ "$start_line" -lt "$setup_line" ]]
	[[ "$setup_line" -lt "$cmd_line" ]]
	[[ "$(grep -c 'nsenter' "$PODMAN_LOG" || true)" -eq 0 ]]
}

@test "run_recreate recontain and rebuild order start, the nft install, setup.sh and stop per container for onbox, netbox and offbox" {
	load_container_libs
	use_podman_shim
	# shellcheck disable=SC2034 # arrays are consumed by nameref parameters
	local -a deny=(1.1.1.1) allow=() srcs=() dsts=()
	# Per-container expectations indexed alongside containers: the step that
	# must precede setup.sh (the nft deny install for onbox and netbox, the
	# start for offbox) and a pattern that must not appear in the log (empty =
	# no check).
	local -a containers=(onbox netbox offbox)
	local -a ctrs=("$(container_name_of onbox "$PROJECT")" "$(container_name_of netbox "$PROJECT")" "$(container_name_of offbox "$PROJECT")")
	local -a pre_patterns=('unshare.*nsenter.*nft' 'unshare.*nsenter.*nft' '^start ')
	local -a absent_patterns=('' '' 'nsenter')
	local i c rebuild pre_line setup_line stop_line absent_count
	for i in "${!containers[@]}"; do
		c="${containers[$i]}"
		ctr="${ctrs[$i]}"
		for rebuild in no yes; do
			: >"$LOG"
			run run_recreate "$c" "$rebuild" "$PROJECT" no READ_MOUNTS WRITE_MOUNTS srcs dsts PORTS deny allow
			[[ "$status" -eq 0 ]]
			pre_line="$(log_line_no "${pre_patterns[$i]}" "$PODMAN_LOG")"
			setup_line="$(log_line_no "exec $ctr setup.sh$" "$PODMAN_LOG")"
			stop_line="$(log_line_no '^stop ' "$PODMAN_LOG")"
			absent_count="$(grep -c "${absent_patterns[$i]}" "$PODMAN_LOG" || true)"
			[[ -n "$pre_line" && -n "$setup_line" && -n "$stop_line" ]]
			[[ "$pre_line" -lt "$setup_line" ]]
			[[ "$setup_line" -lt "$stop_line" ]]
			[[ -z "${absent_patterns[$i]}" || "$absent_count" -eq 0 ]]
		done
	done
}

@test "run_container netbox create line is byte-identical to the recontain recreate line from the base image" {
	load_container_libs
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	run run_container netbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	local create_create
	create_create="$(podman_create_line)"
	[[ -n "$create_create" ]]
	: >"$LOG"
	run run_recreate netbox no "$PROJECT" no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	[[ "$(podman_create_line)" == "$create_create" ]]
}

@test "run_container netbox create line is byte-identical to the recontain recreate line when inheriting from onbox" {
	load_container_libs
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	export PODMAN_CONTAINERS="talkbox-proj.onbox"
	run run_container netbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	local create_create
	create_create="$(podman_create_line)"
	line_has_token "$create_create" 'talkbox-proj.netbox.root'
	: >"$LOG"
	run run_recreate netbox no "$PROJECT" no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	[[ "$(podman_create_line)" == "$create_create" ]]
}

@test "run_container offbox create line is byte-identical to the recontain recreate line when inheriting from netbox" {
	load_container_libs
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	export PODMAN_CONTAINERS="talkbox-proj.netbox"
	run run_container offbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	local create_create
	create_create="$(podman_create_line)"
	line_has_token "$create_create" 'talkbox-proj.offbox.root'
	: >"$LOG"
	run run_recreate offbox no "$PROJECT" no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	[[ "$(podman_create_line)" == "$create_create" ]]
}

@test "run_container netbox and run_recreate netbox build identical create lines under TALKBOX_FRESH and TALKBOX_INHERIT" {
	load_container_libs
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	export PODMAN_CONTAINERS="talkbox-proj.onbox talkbox-proj.offbox"
	# shellcheck disable=SC2034 # globals consumed by the sourced containers.sh
	TALKBOX_FRESH=yes
	run run_container netbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	[[ "$(podman_count '^commit ')" -eq 0 ]]
	local fresh_create
	fresh_create="$(podman_create_line)"
	: >"$LOG"
	run run_recreate netbox no "$PROJECT" no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	[[ "$(podman_count '^commit ')" -eq 0 ]]
	[[ "$(podman_create_line)" == "$fresh_create" ]]
	: >"$LOG"
	unset TALKBOX_FRESH
	# shellcheck disable=SC2034 # global consumed by the sourced containers.sh
	TALKBOX_INHERIT=offbox
	run run_container netbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	local inherit_create
	inherit_create="$(podman_create_line)"
	[[ -n "$(podman_line '^commit talkbox-proj.offbox talkbox-proj.netbox.root$')" ]]
	: >"$LOG"
	run run_recreate netbox no "$PROJECT" no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	[[ "$(podman_count '^commit ')" -eq 1 ]]
	[[ "$(podman_create_line)" == "$inherit_create" ]]
}

@test "a failed netbox create plan rolls back the named volumes and reports a talkbox error" {
	load_container_libs
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	export PODMAN_VOLUMES="talkbox-proj.netbox.worktree talkbox-proj.netbox.gitdir talkbox-proj.netbox.write.talkbox-wdata"
	# shellcheck disable=SC2034 # arrays are consumed by nameref parameters
	local -a srcs=('/host/data') dsts=('/talkbox/wdata')
	export PODMAN_FAIL_PATTERN='cp -a'
	run run_container netbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS srcs dsts PORTS DENY ALLOW
	[[ "$status" -ne 0 ]]
	[[ "$output" == *'talkbox:'* ]]
	grep -q 'volume rm -f.*talkbox-proj\.netbox\.worktree' "$PODMAN_LOG"
	grep -q 'volume rm -f.*talkbox-proj\.netbox\.gitdir' "$PODMAN_LOG"
	grep -q 'volume rm -f.*talkbox-proj\.netbox\.write\.talkbox-wdata' "$PODMAN_LOG"
	[[ -z "$(podman_line '^start talkbox-proj.netbox$')" ]]
	[[ "$(podman_count '^exec ')" -eq 0 ]]
}

@test "a failed netbox recontain start rolls back the partial container and named volumes with a talkbox error" {
	load_container_libs
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	export PODMAN_VOLUMES="talkbox-proj.netbox.worktree talkbox-proj.netbox.gitdir talkbox-proj.netbox.write.talkbox-wdata"
	# shellcheck disable=SC2034 # arrays are consumed by nameref parameters
	local -a srcs=('/host/data') dsts=('/talkbox/wdata')
	export PODMAN_FAIL_PATTERN='start talkbox-proj.netbox'
	run run_recreate netbox no "$PROJECT" no READ_MOUNTS WRITE_MOUNTS srcs dsts PORTS DENY ALLOW
	[[ "$status" -ne 0 ]]
	[[ "$output" == *'talkbox:'* ]]
	local start_line rm_line vol_line
	start_line="$(podman_line_no '^start talkbox-proj.netbox$')"
	[[ -n "$start_line" ]]
	rm_line="$(grep -nE 'rm -f( --volumes)? talkbox-proj\.netbox$' "$PODMAN_LOG" | tail -1 | cut -d: -f1)"
	[[ -n "$rm_line" && "$rm_line" -gt "$start_line" ]]
	vol_line="$(grep -n 'volume rm -f' "$PODMAN_LOG" | grep 'talkbox-proj\.netbox\.worktree' | tail -1 | cut -d: -f1)"
	[[ -n "$vol_line" && "$vol_line" -gt "$start_line" ]]
	vol_line="$(grep -n 'volume rm -f' "$PODMAN_LOG" | grep 'talkbox-proj\.netbox\.gitdir' | tail -1 | cut -d: -f1)"
	[[ -n "$vol_line" && "$vol_line" -gt "$start_line" ]]
	vol_line="$(grep -n 'volume rm -f' "$PODMAN_LOG" | grep 'talkbox-proj\.netbox\.write\.talkbox-wdata' | tail -1 | cut -d: -f1)"
	[[ -n "$vol_line" && "$vol_line" -gt "$start_line" ]]
}
