# shellcheck disable=SC2030,SC2031 # bats runs each test in a subshell; TALKBOX_ROOT is overridden only within its own test
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

@test "run_container creates each container with the workdir, userns and capability drops, probing the base image" {
	load_container_libs
	use_podman_shim
	local c create probe_line
	for c in onbox netbox offbox; do
		: >"$LOG"
		run run_container "$c" "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
		[[ "$status" -eq 0 ]]
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
	done
}

@test "run_container probes the base image and builds it when missing on the create path" {
	load_container_libs
	use_podman_shim
	local c build_line create_line build
	for c in onbox netbox offbox; do
		: >"$LOG"
		run run_container "$c" "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
		[[ "$status" -eq 0 ]]
		[[ -n "$(podman_line "^image exists $(base_image_name)$")" ]]
		[[ "$(podman_count '^build ')" -eq 0 ]]
		: >"$LOG"
		export PODMAN_IMAGES=""
		run run_container "$c" "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
		[[ "$status" -eq 0 ]]
		[[ -n "$(podman_line "^image exists $(base_image_name)$")" ]]
		[[ "$(podman_count '^commit ')" -eq 0 ]]
		build_line="$(podman_line_no '^build ')"
		create_line="$(podman_line_no '^create ')"
		[[ -n "$build_line" && -n "$create_line" ]]
		[[ "$build_line" -lt "$create_line" ]]
		build="$(podman_line '^build ')"
		line_has_token "$build" '-t'
		line_has_token "$build" "$(base_image_name)"
		line_has_token "$build" "$TALKBOX_ROOT/image/Containerfile"
		PODMAN_IMAGES="$(base_image_name)"
		export PODMAN_IMAGES
	done
}

@test "run_container uses the per-container pasta network string, without host ports by default and with -T ports when given" {
	load_container_libs
	use_podman_shim
	local -a containers=(onbox netbox offbox)
	local -a suffixes=('--dns-forward,169.254.1.1,--map-guest-addr,none' '--dns-forward,169.254.1.1,--map-guest-addr,none' '-i,lo,-I,talkbox0')
	local i c create
	for i in "${!containers[@]}"; do
		c="${containers[$i]}"
		: >"$LOG"
		run run_container "$c" "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
		[[ "$status" -eq 0 ]]
		create="$(podman_create_line)"
		line_has_token "$create" "--network=pasta:${suffixes[$i]}"
		[[ "$create" != *'-T,'* ]]
		: >"$LOG"
		# shellcheck disable=SC2054 # -T,<port> tokens are single array elements
		# shellcheck disable=SC2034 # ports is consumed by nameref parameters
		local -a ports=(-T,8080 -T,9090)
		run run_container "$c" "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS ports DENY ALLOW
		[[ "$status" -eq 0 ]]
		line_has_token "$(podman_create_line)" "--network=pasta:-T,8080,-T,9090,${suffixes[$i]}"
	done
}

@test "run_container applies read mounts read-only and write mounts in the per-container style" {
	load_container_libs
	use_podman_shim
	local home="$BATS_TEST_TMPDIR/home"
	mkdir -p "$home"
	local wdir="$BATS_TEST_TMPDIR/var"
	mkdir -p "$wdir"
	printf '/host/etc\n' >"$BATS_TEST_TMPDIR/read.mounts"
	printf '%s\n' "$wdir" >"$BATS_TEST_TMPDIR/write.mounts"
	local c write_token create populate
	for c in onbox netbox offbox; do
		# shellcheck disable=SC2034 # arrays are consumed by nameref parameters
		local -a read_mounts=() write_mounts=() srcs=() dsts=() ports=()
		mount_args read_mounts read "$BATS_TEST_TMPDIR/read.mounts" "$PROJECT" "$home"
		if [[ "$c" == onbox ]]; then
			mount_args write_mounts write "$BATS_TEST_TMPDIR/write.mounts" "$PROJECT" "$home"
			write_token="$wdir:/host/write/var"
		else
			mount_entries srcs dsts write "$BATS_TEST_TMPDIR/write.mounts" "$PROJECT" "$home"
			mount_volume_args write_mounts "$c" "$PROJECT" srcs dsts
			write_token="talkbox-proj.$c.write.host-write-var:/host/write/var"
		fi
		port_args ports "$BATS_TEST_TMPDIR/ports" 9090
		: >"$LOG"
		run run_container "$c" "$PROJECT" 'true' no read_mounts write_mounts srcs dsts ports DENY ALLOW
		[[ "$status" -eq 0 ]]
		create="$(podman_create_line)"
		line_has_token "$create" '/host/etc:/host/read/etc:ro'
		line_has_token "$create" "$write_token"
		if [[ "$c" == onbox ]]; then
			[[ "$(podman_count '^run ')" -eq 0 ]]
		else
			populate="$(podman_line "talkbox-proj.$c.write.host-write-var:/talkbox/target")"
			line_has_token "$populate" "$wdir:/talkbox/source:ro"
		fi
	done
}

@test "run_container mounts the per-container worktree at /working/<project-base> read-write" {
	load_container_libs
	use_podman_shim
	local c token create
	for c in onbox netbox offbox; do
		if [[ "$c" == onbox ]]; then
			token="$PROJECT:/working/talkbox-proj"
		else
			token="talkbox-proj.$c.worktree:/working/talkbox-proj"
		fi
		: >"$LOG"
		run run_container "$c" "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
		[[ "$status" -eq 0 ]]
		create="$(podman_create_line)"
		line_has_token "$create" "$token"
		line_lacks_token "$create" "${token}:ro"
	done
}

@test "run_container bind-mounts global dotfiles and art read-only and project dotfiles when they exist" {
	load_container_libs
	use_podman_shim
	mkdir -p "$PROJECT/.dotfiles"
	local c create
	for c in onbox netbox offbox; do
		: >"$LOG"
		run run_container "$c" "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
		[[ "$status" -eq 0 ]]
		create="$(podman_create_line)"
		line_has_token "$create" "$TALKBOX_ROOT/defaults/dotfiles:/talkbox/dotfiles.global:ro"
		line_has_token "$create" "$TALKBOX_ROOT/defaults/art:/talkbox/art:ro"
		line_has_token "$create" "$PROJECT/.dotfiles:/talkbox/dotfiles.project:ro"
	done
}

@test "run_container omits the dotfiles and art bind-mounts when absent" {
	load_container_libs
	use_podman_shim
	TALKBOX_ROOT="$BATS_TEST_TMPDIR/talkbox-root-no-dotfiles"
	mkdir -p "$TALKBOX_ROOT"
	local c create
	for c in onbox netbox offbox; do
		: >"$LOG"
		run run_container "$c" "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
		[[ "$status" -eq 0 ]]
		create="$(podman_create_line)"
		[[ "$create" != *'dotfiles.global'* ]]
		[[ "$create" != *'dotfiles.project'* ]]
		[[ "$create" != *'/talkbox/art'* ]]
	done
}

@test "run_container names the container, runs the base image with sleep infinity behind --init, without --rm or tmpfs" {
	load_container_libs
	use_podman_shim
	local c create img init_at img_at sleep_at
	for c in onbox netbox offbox; do
		: >"$LOG"
		run run_container "$c" "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
		[[ "$status" -eq 0 ]]
		create="$(podman_create_line)"
		img="$(base_image_name)"
		line_has_token "$create" '--init'
		line_has_token "$create" "--name=talkbox-proj.$c"
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
	done
}

@test "run_container interactive create allocates a terminal and noninteractive does not" {
	load_container_libs
	use_podman_shim
	local c create
	for c in onbox netbox offbox; do
		: >"$LOG"
		run run_container "$c" "$PROJECT" 'true' yes READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
		[[ "$status" -eq 0 ]]
		create="$(podman_create_line)"
		line_has_token "$create" '--interactive'
		line_has_token "$create" '--tty'
		: >"$LOG"
		run run_container "$c" "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
		[[ "$status" -eq 0 ]]
		create="$(podman_create_line)"
		line_lacks_token "$create" '--interactive'
		line_lacks_token "$create" '--tty'
	done
}

@test "run_container adds the git mounts and creates the gitdir volume for a git-tracked project only" {
	load_container_libs
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	local plain="$BATS_TEST_TMPDIR/plain"
	mkdir -p "$plain"
	local c create
	for c in onbox netbox offbox; do
		: >"$LOG"
		run run_container "$c" "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
		[[ "$status" -eq 0 ]]
		create="$(podman_create_line)"
		line_has_token "$create" "$PROJECT/.git:/host/git:ro"
		line_has_token "$create" "talkbox-proj.$c.gitdir:/working/talkbox-proj/.git"
		line_has_token "$create" "$TALKBOX_ROOT/lib/merge.sh:/talkbox/lib/merge.sh:ro"
		line_has_token "$create" "$TALKBOX_ROOT/image/setup.sh:/usr/local/bin/setup.sh:ro"
		[[ -n "$(podman_line "^volume create talkbox-proj.$c.gitdir$")" ]]
		[[ "$(podman_line_no "^volume create talkbox-proj.$c.gitdir$")" -lt "$(podman_line_no '^create ')" ]]
		: >"$LOG"
		run run_container "$c" "$plain" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
		[[ "$status" -eq 0 ]]
		create="$(podman_create_line)"
		[[ "$create" != *'/host/git'* ]]
		[[ "$create" != *'.gitdir'* ]]
		[[ -z "$(podman_line '^volume create ')" ]]
	done
}

@test "run_container omits the gitdir volume create when the gitdir volume already exists" {
	load_container_libs
	use_podman_shim
	mkdir -p "$PROJECT/.git"
	local c
	for c in onbox netbox offbox; do
		: >"$LOG"
		export PODMAN_VOLUMES="talkbox-proj.$c.gitdir"
		run run_container "$c" "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
		[[ "$status" -eq 0 ]]
		[[ -z "$(podman_line '^volume create ')" ]]
		line_has_token "$(podman_create_line)" "talkbox-proj.$c.gitdir:/working/talkbox-proj/.git"
	done
}

@test "run_container emits git identity env vars for a git-tracked project but not for a non-git project" {
	load_container_libs
	use_podman_shim
	git -C "$PROJECT" init -q
	git -C "$PROJECT" config user.name host-user
	git -C "$PROJECT" config user.email host@example.com
	local plain="$BATS_TEST_TMPDIR/plain"
	mkdir -p "$plain"
	local c create
	for c in onbox netbox offbox; do
		: >"$LOG"
		run run_container "$c" "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
		[[ "$status" -eq 0 ]]
		create="$(podman_create_line)"
		line_has_token "$create" 'TALKBOX_GIT_USER_NAME=host-user'
		line_has_token "$create" 'TALKBOX_GIT_USER_EMAIL=host@example.com'
		: >"$LOG"
		run run_container "$c" "$plain" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
		[[ "$status" -eq 0 ]]
		create="$(podman_create_line)"
		[[ "$create" != *'TALKBOX_GIT_USER'* ]]
	done
}

@test "run_container omits a git identity env var for a field the host has not configured" {
	load_container_libs
	use_podman_shim
	export HOME="$BATS_TEST_TMPDIR/home"
	export GIT_CONFIG_NOSYSTEM=1
	mkdir -p "$HOME"
	git -C "$PROJECT" init -q
	git -C "$PROJECT" config user.email host@example.com
	local c create
	for c in onbox netbox offbox; do
		: >"$LOG"
		run run_container "$c" "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
		[[ "$status" -eq 0 ]]
		create="$(podman_create_line)"
		[[ "$create" != *'TALKBOX_GIT_USER_NAME'* ]]
		line_has_token "$create" 'TALKBOX_GIT_USER_EMAIL=host@example.com'
	done
}

@test "run_container emits the prompt host env vars for git-tracked and non-git projects" {
	load_container_libs
	use_podman_shim
	git -C "$PROJECT" init -q
	local plain="$BATS_TEST_TMPDIR/plain"
	mkdir -p "$plain"
	local c create
	for c in onbox netbox offbox; do
		: >"$LOG"
		run run_container "$c" "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
		[[ "$status" -eq 0 ]]
		create="$(podman_create_line)"
		line_has_token "$create" 'TALKBOX_PROJECT_SLUG=talkbox-proj'
		line_has_token "$create" "TALKBOX_CONTAINER_TYPE=$c"
		: >"$LOG"
		run run_container "$c" "$plain" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
		[[ "$status" -eq 0 ]]
		create="$(podman_create_line)"
		line_has_token "$create" 'TALKBOX_PROJECT_SLUG=plain'
		line_has_token "$create" "TALKBOX_CONTAINER_TYPE=$c"
	done
}

@test "run_container appends the GPU device and group options when TALKBOX_GPU is yes" {
	load_container_libs
	use_podman_shim
	# shellcheck disable=SC2034 # global consumed by the sourced containers.sh
	TALKBOX_GPU=yes
	local c create
	for c in onbox netbox offbox; do
		: >"$LOG"
		run run_container "$c" "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
		[[ "$status" -eq 0 ]]
		create="$(podman_create_line)"
		line_has_token "$create" 'nvidia.com/gpu=all'
		line_has_token "$create" 'keep-groups'
	done
}

@test "run_container starts an interactive /bin/bash when no command is given and stops the container afterwards" {
	load_container_libs
	use_podman_shim
	local c exec_line stop_line
	for c in onbox netbox offbox; do
		: >"$LOG"
		run run_container "$c" "$PROJECT" '' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
		[[ "$status" -eq 0 ]]
		exec_line="$(podman_line_no "^exec --interactive --tty talkbox-proj.$c /bin/bash$")"
		stop_line="$(podman_line_no "^stop -t 5 talkbox-proj.$c$")"
		[[ -n "$exec_line" && -n "$stop_line" ]]
		[[ "$exec_line" -lt "$stop_line" ]]
	done
}

@test "run_container runs a non-empty command via bash -c, returns its exit status and stops best-effort" {
	load_container_libs
	use_podman_shim
	export PODMAN_FAIL_PATTERN='bash -c exit 3'
	export PODMAN_FAIL_CODE=7
	local c exec_line stop_line
	for c in onbox netbox offbox; do
		: >"$LOG"
		run run_container "$c" "$PROJECT" 'exit 3' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
		[[ "$status" -eq 7 ]]
		exec_line="$(podman_line_no "^exec talkbox-proj.$c bash -c exit 3$")"
		stop_line="$(podman_line_no "^stop -t 5 talkbox-proj.$c$")"
		[[ -n "$exec_line" && -n "$stop_line" ]]
		[[ "$exec_line" -lt "$stop_line" ]]
	done
}

@test "run_container succeeds even when the best-effort stop fails" {
	load_container_libs
	use_podman_shim
	export PODMAN_FAIL_PATTERN='stop -t 5'
	local c
	for c in onbox netbox offbox; do
		: >"$LOG"
		run run_container "$c" "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
		[[ "$status" -eq 0 ]]
		[[ -n "$(podman_line "^stop -t 5 talkbox-proj.$c$")" ]]
	done
}

@test "run_container applies the nft deny rules before running setup.sh for onbox and netbox, with no nft step for offbox" {
	load_container_libs
	use_podman_shim
	local -a containers=(onbox netbox offbox)
	local -a has_nft=(yes yes no)
	local i c ctr start_line nft_line setup_line cmd_line
	for i in "${!containers[@]}"; do
		c="${containers[$i]}"
		ctr="$(container_name_of "$c" "$PROJECT")"
		: >"$LOG"
		export PODMAN_CONTAINERS="$ctr"
		# shellcheck disable=SC2034 # arrays are consumed by nameref parameters
		local -a deny=(1.1.1.1) allow=()
		run run_container "$c" "$PROJECT" 'echo hi' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS deny allow
		[[ "$status" -eq 0 ]]
		start_line="$(log_line_no "^start $ctr$" "$PODMAN_LOG")"
		setup_line="$(log_line_no "exec $ctr setup.sh$" "$PODMAN_LOG")"
		cmd_line="$(log_line_no 'bash -c echo hi' "$PODMAN_LOG")"
		[[ -n "$start_line" && -n "$setup_line" && -n "$cmd_line" ]]
		[[ "$start_line" -lt "$setup_line" ]]
		[[ "$setup_line" -lt "$cmd_line" ]]
		if [[ "${has_nft[$i]}" == yes ]]; then
			nft_line="$(log_line_no 'unshare.*nsenter.*nft' "$PODMAN_LOG")"
			[[ -n "$nft_line" ]]
			[[ "$start_line" -lt "$nft_line" ]]
			[[ "$nft_line" -lt "$setup_line" ]]
		else
			[[ "$(grep -c 'nsenter' "$PODMAN_LOG" || true)" -eq 0 ]]
		fi
	done
}

@test "run_container stops the container and raises a talkbox error when the setup.sh exec fails" {
	load_container_libs
	use_podman_shim
	export PODMAN_FAIL_PATTERN='setup.sh'
	export PODMAN_FAIL_CODE=1
	local c ctr
	for c in onbox netbox offbox; do
		ctr="$(container_name_of "$c" "$PROJECT")"
		: >"$LOG"
		export PODMAN_CONTAINERS="$ctr"
		# shellcheck disable=SC2034 # arrays are consumed by nameref parameters
		local -a deny=(1.1.1.1) allow=()
		run run_container "$c" "$PROJECT" 'echo hi' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS deny allow
		[[ "$status" -ne 0 ]]
		[[ "$output" == *'talkbox:'* ]]
		[[ "$(grep -c "^stop " "$PODMAN_LOG")" -ge 1 ]]
	done
}

@test "run_container create line is byte-identical to the recontain recreate line" {
	load_container_libs
	use_podman_shim
	local c create_create
	for c in onbox netbox offbox; do
		: >"$LOG"
		run run_container "$c" "$PROJECT" 'true' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
		[[ "$status" -eq 0 ]]
		create_create="$(podman_create_line)"
		[[ -n "$create_create" ]]
		: >"$LOG"
		run run_recreate "$c" no "$PROJECT" no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS DENY ALLOW
		[[ "$status" -eq 0 ]]
		[[ "$(podman_create_line)" == "$create_create" ]]
	done
}

@test "run_container stops the container and dies with the exact nft error when the nft deny step fails" {
	load_container_libs
	use_podman_shim
	export PODMAN_FAIL_PATTERN='nsenter'
	export PODMAN_FAIL_CODE=1
	local c ctr nft_line stop_line
	for c in onbox netbox; do
		ctr="$(container_name_of "$c" "$PROJECT")"
		: >"$LOG"
		# shellcheck disable=SC2034 # arrays are consumed by nameref parameters
		local -a deny=(1.1.1.1) allow=()
		run run_container "$c" "$PROJECT" 'echo hi' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS deny allow
		[[ "$status" -eq 1 ]]
		[[ "$output" == *"talkbox: cannot apply nftables deny/allow rules in container talkbox-proj.$c; deny list left unenforced"* ]]
		nft_line="$(podman_line_no 'unshare nsenter')"
		stop_line="$(podman_line_no "^stop -t 5 talkbox-proj.$c$")"
		[[ -n "$nft_line" && -n "$stop_line" ]]
		[[ "$nft_line" -lt "$stop_line" ]]
	done
}

@test "run_container stops the container and dies with the exact setup error when the setup.sh exec fails" {
	load_container_libs
	use_podman_shim
	local c ctr nft_line setup_line stop_line
	for c in onbox netbox offbox; do
		ctr="$(container_name_of "$c" "$PROJECT")"
		: >"$LOG"
		export PODMAN_CONTAINERS="$ctr"
		export PODMAN_FAIL_PATTERN="exec talkbox-proj.$c setup.sh"
		export PODMAN_FAIL_CODE=1
		# shellcheck disable=SC2034 # arrays are consumed by nameref parameters
		local -a deny=(1.1.1.1) allow=()
		run run_container "$c" "$PROJECT" 'echo hi' no READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS deny allow
		[[ "$status" -eq 1 ]]
		[[ "$output" == *"talkbox: cannot run setup.sh in container talkbox-proj.$c; setup failed"* ]]
		setup_line="$(podman_line_no "^exec talkbox-proj.$c setup.sh$")"
		stop_line="$(podman_line_no "^stop -t 5 talkbox-proj.$c$")"
		[[ -n "$setup_line" && -n "$stop_line" ]]
		[[ "$setup_line" -lt "$stop_line" ]]
		if [[ "$c" != offbox ]]; then
			nft_line="$(podman_line_no 'unshare nsenter')"
			[[ -n "$nft_line" ]]
			[[ "$nft_line" -lt "$setup_line" ]]
		else
			[[ "$(grep -c 'nsenter' "$PODMAN_LOG" || true)" -eq 0 ]]
		fi
	done
}
