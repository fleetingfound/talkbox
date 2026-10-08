# shellcheck disable=SC2030,SC2031 # bats runs each test in a subshell; TALKBOX_ROOT is overridden only within its own test
load helpers

# shellcheck disable=SC2034 # arrays are consumed by nameref parameters
setup() {
	PROJECT="$BATS_TEST_TMPDIR/talkbox-proj"
	mkdir -p "$PROJECT"
	READ_MOUNTS=()
	WRITE_MOUNTS=()
	PORTS=()
	DENY=()
	ALLOW=()
	SHIM="$BATS_TEST_TMPDIR/shim"
	LOG="$BATS_TEST_TMPDIR/podman.log"
}

@test "run_onbox creates the container with the workdir, userns and capability drops, probing the base image" {
	load_container_libs
	use_podman_shim
	run run_onbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	local create probe_line
	create="$(podman_create_line)"
	[[ -n "$create" ]]
	line_has_token "$create" '--workdir=/working/talkbox-proj'
	line_has_token "$create" '--userns=keep-id:uid=1000,gid=1000'
	line_has_token "$create" '--cap-drop=NET_ADMIN'
	line_has_token "$create" '--cap-drop=NET_RAW'
	probe_line="$(podman_line_no "^image exists $(base_image_name)$")"
	[[ -n "$probe_line" ]]
	[[ "$probe_line" -lt "$(podman_line_no '^create ')" ]]
	[[ "$(podman_count 'image exists')" -eq 1 ]]
	[[ "$(podman_count '^build ')" -eq 0 ]]
}

@test "run_onbox probes the base image and builds it when missing on the create path" {
	load_container_libs
	use_podman_shim
	run run_onbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	[[ -n "$(podman_line "^image exists $(base_image_name)$")" ]]
	[[ "$(podman_count '^build ')" -eq 0 ]]
	: >"$LOG"
	export PODMAN_IMAGES=""
	run run_onbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	[[ -n "$(podman_line "^image exists $(base_image_name)$")" ]]
	[[ "$(podman_count '^commit ')" -eq 0 ]]
	local build_line create_line
	build_line="$(podman_line_no '^build ')"
	create_line="$(podman_line_no '^create ')"
	[[ -n "$build_line" && -n "$create_line" ]]
	[[ "$build_line" -lt "$create_line" ]]
	local build
	build="$(podman_line '^build ')"
	line_has_token "$build" '-t'
	line_has_token "$build" "$(base_image_name)"
	line_has_token "$build" "$TALKBOX_ROOT/image/Containerfile"
}

@test "run_onbox uses the pasta network with the DNS-forward suffix and no host-port forwarding by default" {
	load_container_libs
	use_podman_shim
	run run_onbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	local create
	create="$(podman_create_line)"
	line_has_token "$create" '--network=pasta:--dns-forward,169.254.1.1,--map-guest-addr,none'
	[[ "$create" != *'-T,'* ]]
}

@test "run_onbox forwards pasta -T ports and applies read mounts read-only and write mounts as bind-mounts" {
	load_container_libs
	use_podman_shim
	local home="$BATS_TEST_TMPDIR/home"
	mkdir -p "$home"
	printf '/host/etc\n' >"$BATS_TEST_TMPDIR/read.mounts"
	printf '/host/var\n' >"$BATS_TEST_TMPDIR/write.mounts"
	printf '8080\n' >"$BATS_TEST_TMPDIR/ports"
	# shellcheck disable=SC2034 # arrays are consumed by nameref parameters
	local -a read_mounts=() write_mounts=() ports=()
	mount_args read_mounts read "$BATS_TEST_TMPDIR/read.mounts" "$PROJECT" "$home"
	mount_args write_mounts write "$BATS_TEST_TMPDIR/write.mounts" "$PROJECT" "$home"
	port_args ports "$BATS_TEST_TMPDIR/ports" 9090
	run run_onbox "$PROJECT" 'true' no read_mounts write_mounts ports DENY ALLOW
	[[ "$status" -eq 0 ]]
	local create
	create="$(podman_create_line)"
	line_has_token "$create" '--network=pasta:-T,8080,-T,9090,--dns-forward,169.254.1.1,--map-guest-addr,none'
	line_has_token "$create" '/host/etc:/host/read/etc:ro'
	line_has_token "$create" '/host/var:/host/write/var'
}

@test "run_onbox bind-mounts the host worktree read-write" {
	load_container_libs
	use_podman_shim
	run run_onbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	local create
	create="$(podman_create_line)"
	line_has_token "$create" "$PROJECT:/working/talkbox-proj"
	line_lacks_token "$create" "$PROJECT:/working/talkbox-proj:ro"
}

@test "run_onbox bind-mounts global dotfiles and art read-only and project dotfiles when they exist" {
	load_container_libs
	use_podman_shim
	mkdir -p "$PROJECT/.dotfiles"
	run run_onbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	local create
	create="$(podman_create_line)"
	line_has_token "$create" "$TALKBOX_ROOT/defaults/dotfiles:/talkbox/dotfiles.global:ro"
	line_has_token "$create" "$TALKBOX_ROOT/defaults/art:/talkbox/art:ro"
	line_has_token "$create" "$PROJECT/.dotfiles:/talkbox/dotfiles.project:ro"
}

@test "run_onbox omits the dotfiles and art bind-mounts when absent" {
	load_container_libs
	use_podman_shim
	TALKBOX_ROOT="$BATS_TEST_TMPDIR/talkbox-root-no-dotfiles"
	mkdir -p "$TALKBOX_ROOT"
	run run_onbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	local create
	create="$(podman_create_line)"
	[[ "$create" != *'dotfiles.global'* ]]
	[[ "$create" != *'dotfiles.project'* ]]
	[[ "$create" != *'/talkbox/art'* ]]
}

@test "run_onbox names the container, runs the base image with sleep infinity behind --init, without --rm or tmpfs" {
	load_container_libs
	use_podman_shim
	run run_onbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	local create img init_at img_at sleep_at
	create="$(podman_create_line)"
	img="$(base_image_name)"
	line_has_token "$create" '--init'
	line_has_token "$create" '--name=talkbox-proj.onbox'
	line_has_token "$create" "$img"
	line_has_token "$create" 'sleep'
	line_has_token "$create" 'infinity'
	init_at="$(line_token_at "$create" --init)"
	img_at="$(line_token_at "$create" "$img")"
	sleep_at="$(line_token_at "$create" sleep)"
	[[ "$init_at" -gt 0 ]]
	[[ "$init_at" -lt "$img_at" ]]
	[[ "$img_at" -lt "$sleep_at" ]]
	line_lacks_token "$create" '--rm'
	line_lacks_token "$create" '--tmpfs'
	[[ "$create" != *'/run/talkbox'* ]]
}

@test "run_onbox interactive create allocates a terminal and noninteractive does not" {
	load_container_libs
	use_podman_shim
	run run_onbox "$PROJECT" 'true' yes READ_MOUNTS WRITE_MOUNTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	local create
	create="$(podman_create_line)"
	line_has_token "$create" '--interactive'
	line_has_token "$create" '--tty'
	: >"$LOG"
	run run_onbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	create="$(podman_create_line)"
	line_lacks_token "$create" '--interactive'
	line_lacks_token "$create" '--tty'
}

@test "run_onbox adds the git mounts and creates the gitdir volume for a git-tracked project only" {
	load_container_libs
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	run run_onbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	local create
	create="$(podman_create_line)"
	line_has_token "$create" "$PROJECT/.git:/host/git:ro"
	line_has_token "$create" 'talkbox-proj.onbox.gitdir:/working/talkbox-proj/.git'
	line_has_token "$create" "$TALKBOX_ROOT/lib/merge.sh:/talkbox/lib/merge.sh:ro"
	line_has_token "$create" "$TALKBOX_ROOT/image/setup.sh:/usr/local/bin/setup.sh:ro"
	[[ -n "$(podman_line '^volume create talkbox-proj.onbox.gitdir$')" ]]
	[[ "$(podman_line_no '^volume create talkbox-proj.onbox.gitdir$')" -lt "$(podman_line_no '^create ')" ]]
	local plain="$BATS_TEST_TMPDIR/plain"
	mkdir -p "$plain"
	: >"$LOG"
	run run_onbox "$plain" 'true' no READ_MOUNTS WRITE_MOUNTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	create="$(podman_create_line)"
	[[ "$create" != *'/host/git'* ]]
	[[ "$create" != *'.gitdir'* ]]
	[[ -z "$(podman_line '^volume create ')" ]]
}

@test "run_onbox omits the gitdir volume create when the gitdir volume already exists" {
	load_container_libs
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	export PODMAN_VOLUMES="talkbox-proj.onbox.gitdir"
	run run_onbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	[[ -z "$(podman_line '^volume create ')" ]]
	line_has_token "$(podman_create_line)" 'talkbox-proj.onbox.gitdir:/working/talkbox-proj/.git'
}

@test "run_onbox emits git identity env vars for a git-tracked project but not for a non-git project" {
	load_container_libs
	use_podman_shim
	git -C "$PROJECT" init -q
	git -C "$PROJECT" config user.name host-user
	git -C "$PROJECT" config user.email host@example.com
	run run_onbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	local create
	create="$(podman_create_line)"
	line_has_token "$create" 'TALKBOX_GIT_USER_NAME=host-user'
	line_has_token "$create" 'TALKBOX_GIT_USER_EMAIL=host@example.com'
	local plain="$BATS_TEST_TMPDIR/plain"
	mkdir -p "$plain"
	: >"$LOG"
	run run_onbox "$plain" 'true' no READ_MOUNTS WRITE_MOUNTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	create="$(podman_create_line)"
	[[ "$create" != *'TALKBOX_GIT_USER'* ]]
}

@test "run_onbox omits a git identity env var for a field the host has not configured" {
	load_container_libs
	use_podman_shim
	export HOME="$BATS_TEST_TMPDIR/home"
	export GIT_CONFIG_NOSYSTEM=1
	mkdir -p "$HOME"
	git -C "$PROJECT" init -q
	git -C "$PROJECT" config user.email host@example.com
	run run_onbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	local create
	create="$(podman_create_line)"
	[[ "$create" != *'TALKBOX_GIT_USER_NAME'* ]]
	line_has_token "$create" 'TALKBOX_GIT_USER_EMAIL=host@example.com'
}

@test "run_onbox emits the prompt host env vars for git-tracked and non-git projects" {
	load_container_libs
	use_podman_shim
	git -C "$PROJECT" init -q
	run run_onbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	local create
	create="$(podman_create_line)"
	line_has_token "$create" 'TALKBOX_PROJECT_SLUG=talkbox-proj'
	line_has_token "$create" 'TALKBOX_CONTAINER_TYPE=onbox'
	local plain="$BATS_TEST_TMPDIR/plain"
	mkdir -p "$plain"
	: >"$LOG"
	run run_onbox "$plain" 'true' no READ_MOUNTS WRITE_MOUNTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	create="$(podman_create_line)"
	line_has_token "$create" 'TALKBOX_PROJECT_SLUG=plain'
	line_has_token "$create" 'TALKBOX_CONTAINER_TYPE=onbox'
}

@test "run_onbox appends the GPU device and group options when TALKBOX_GPU is yes" {
	load_container_libs
	use_podman_shim
	# shellcheck disable=SC2034 # global consumed by the sourced containers.sh
	TALKBOX_GPU=yes
	run run_onbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	local create
	create="$(podman_create_line)"
	line_has_token "$create" 'nvidia.com/gpu=all'
	line_has_token "$create" 'keep-groups'
}

@test "run_onbox starts an interactive /bin/bash when no command is given and stops the container afterwards" {
	load_container_libs
	use_podman_shim
	run run_onbox "$PROJECT" '' no READ_MOUNTS WRITE_MOUNTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	local exec_line stop_line
	exec_line="$(podman_line_no '^exec --interactive --tty talkbox-proj.onbox /bin/bash$')"
	stop_line="$(podman_line_no '^stop -t 5 talkbox-proj.onbox$')"
	[[ -n "$exec_line" && -n "$stop_line" ]]
	[[ "$exec_line" -lt "$stop_line" ]]
}

@test "run_onbox runs a non-empty command via bash -c, returns its exit status and stops best-effort" {
	load_container_libs
	use_podman_shim
	export PODMAN_FAIL_PATTERN='bash -c exit 3'
	export PODMAN_FAIL_CODE=7
	run run_onbox "$PROJECT" 'exit 3' no READ_MOUNTS WRITE_MOUNTS PORTS DENY ALLOW
	[[ "$status" -eq 7 ]]
	local exec_line stop_line
	exec_line="$(podman_line_no '^exec talkbox-proj.onbox bash -c exit 3$')"
	stop_line="$(podman_line_no '^stop -t 5 talkbox-proj.onbox$')"
	[[ -n "$exec_line" && -n "$stop_line" ]]
	[[ "$exec_line" -lt "$stop_line" ]]
}

@test "run_onbox succeeds even when the best-effort stop fails" {
	load_container_libs
	use_podman_shim
	export PODMAN_FAIL_PATTERN='stop -t 5'
	run run_onbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	[[ -n "$(podman_line '^stop -t 5 talkbox-proj.onbox$')" ]]
}

@test "run_onbox applies the nft deny rules before running setup.sh and runs setup.sh before the user command" {
	load_container_libs
	local ctr
	ctr="$(onbox_container_name "$PROJECT")"
	use_podman_shim
	export PODMAN_CONTAINERS="$ctr"
	# shellcheck disable=SC2034 # arrays are consumed by nameref parameters
	local -a deny=(1.1.1.1) allow=()
	run run_onbox "$PROJECT" 'echo hi' no READ_MOUNTS WRITE_MOUNTS PORTS deny allow
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

@test "run_onbox stops the container and raises a talkbox error when the setup.sh exec fails" {
	load_container_libs
	local ctr
	ctr="$(onbox_container_name "$PROJECT")"
	use_podman_shim
	export PODMAN_CONTAINERS="$ctr"
	export PODMAN_FAIL_PATTERN='setup.sh'
	export PODMAN_FAIL_CODE=1
	# shellcheck disable=SC2034 # arrays are consumed by nameref parameters
	local -a deny=(1.1.1.1) allow=()
	run run_onbox "$PROJECT" 'echo hi' no READ_MOUNTS WRITE_MOUNTS PORTS deny allow
	[[ "$status" -ne 0 ]]
	[[ "$output" == *'talkbox:'* ]]
	[[ "$(grep -c "^stop " "$PODMAN_LOG")" -ge 1 ]]
}

@test "run_onbox create line is byte-identical to the run_recontain recreate line" {
	load_container_libs
	use_podman_shim
	run run_onbox "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	local create_create
	create_create="$(podman_create_line)"
	[[ -n "$create_create" ]]
	: >"$LOG"
	run run_recontain "$PROJECT" no READ_MOUNTS WRITE_MOUNTS PORTS DENY ALLOW
	[[ "$status" -eq 0 ]]
	[[ "$(podman_create_line)" == "$create_create" ]]
}

@test "run_onbox stops the container and dies with the exact nft error when the nft deny step fails" {
	load_container_libs
	use_podman_shim
	export PODMAN_FAIL_PATTERN='nsenter'
	export PODMAN_FAIL_CODE=1
	# shellcheck disable=SC2034 # arrays are consumed by nameref parameters
	local -a deny=(1.1.1.1) allow=()
	run run_onbox "$PROJECT" 'echo hi' no READ_MOUNTS WRITE_MOUNTS PORTS deny allow
	[[ "$status" -eq 1 ]]
	[[ "$output" == *'talkbox: cannot apply nftables deny/allow rules in container talkbox-proj.onbox; deny list left unenforced'* ]]
	local nft_line stop_line
	nft_line="$(podman_line_no 'unshare nsenter')"
	stop_line="$(podman_line_no '^stop -t 5 talkbox-proj.onbox$')"
	[[ -n "$nft_line" && -n "$stop_line" ]]
	[[ "$nft_line" -lt "$stop_line" ]]
}

@test "run_onbox stops the container and dies with the exact setup error when the setup.sh exec fails" {
	load_container_libs
	use_podman_shim
	export PODMAN_FAIL_PATTERN='exec talkbox-proj.onbox setup.sh'
	export PODMAN_FAIL_CODE=1
	# shellcheck disable=SC2034 # arrays are consumed by nameref parameters
	local -a deny=(1.1.1.1) allow=()
	run run_onbox "$PROJECT" 'echo hi' no READ_MOUNTS WRITE_MOUNTS PORTS deny allow
	[[ "$status" -eq 1 ]]
	[[ "$output" == *'talkbox: cannot run setup.sh in container talkbox-proj.onbox; setup failed'* ]]
	local nft_line setup_line stop_line
	nft_line="$(podman_line_no 'unshare nsenter')"
	setup_line="$(podman_line_no '^exec talkbox-proj.onbox setup.sh$')"
	stop_line="$(podman_line_no '^stop -t 5 talkbox-proj.onbox$')"
	[[ -n "$nft_line" && -n "$setup_line" && -n "$stop_line" ]]
	[[ "$nft_line" -lt "$setup_line" ]]
	[[ "$setup_line" -lt "$stop_line" ]]
}
