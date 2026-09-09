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

array_has() {
	local needle="$1"
	shift
	local element
	for element in "$@"; do
		if [[ "$element" == *"$needle"* ]]; then
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

# shellcheck disable=SC2034 # arrays are consumed by nameref planner parameters
setup() {
	PROJECT="$BATS_TEST_TMPDIR/talkbox-proj"
	mkdir -p "$PROJECT"
	READ_MOUNTS=()
	WRITE_MOUNTS=()
	PORTS=()
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
	[[ "$(inherit_source offbox yes no no no '')" == onbox ]]
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

@test "netbox plan mounts the worktree volume and names the container" {
	load_netbox_plan
	local args=()
	plan_netbox args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS PORTS "$(base_image_name)"
	array_contains 'talkbox-proj.netbox.worktree:/working/talkbox-proj' "${args[@]}"
	array_contains '--name=talkbox-proj.netbox' "${args[@]}"
}

@test "netbox plan keeps read mounts read-only and write mounts as volumes" {
	load_netbox_plan
	local home="$BATS_TEST_TMPDIR/home" args=()
	mkdir -p "$home"
	# shellcheck disable=SC2034 # arrays are consumed by nameref planner parameters
	local read_mounts=() write_mounts=()
	mount_args read_mounts read "$BATS_TEST_TMPDIR/absent" "$PROJECT" "$home" '/host/data:/talkbox/wdata'
	mount_volume_args write_mounts netbox "$BATS_TEST_TMPDIR/absent" "$PROJECT" "$home" '/host/data:/talkbox/wdata'
	plan_netbox args "$PROJECT" yes read_mounts write_mounts PORTS "$(base_image_name)"
	array_contains '/host/data:/talkbox/wdata:ro' "${args[@]}"
	array_contains 'talkbox-proj.netbox.write.talkbox-wdata:/talkbox/wdata' "${args[@]}"
	array_has_none 'talkbox-proj.netbox.write.talkbox-wdata:/talkbox/wdata:ro' "${args[@]}"
}

@test "netbox plan uses pasta networking without loopback restriction and drops caps" {
	load_netbox_plan
	local args=()
	plan_netbox args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS PORTS "$(base_image_name)"
	array_contains '--network=pasta:--dns-forward,169.254.1.1,--map-guest-addr,none' "${args[@]}"
	array_has_none '-i,lo' "${args[@]}"
	array_contains '--cap-drop=NET_ADMIN' "${args[@]}"
	array_contains '--cap-drop=NET_RAW' "${args[@]}"
}

@test "netbox plan appends the GPU device and group options when TALKBOX_GPU is yes" {
	load_netbox_plan
	# shellcheck disable=SC2034 # global consumed by plan_netbox
	TALKBOX_GPU=yes
	local args=()
	plan_netbox args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS PORTS "$(base_image_name)"
	array_has 'nvidia.com/gpu=all' "${args[@]}"
	array_has 'keep-groups' "${args[@]}"
}

@test "netbox plan forwards -T ports on pasta" {
	load_netbox_plan
	# shellcheck disable=SC2054 # -T,<port> tokens are single array elements
	# shellcheck disable=SC2034 # ports is consumed by nameref planner parameter
	local -a ports=(-T,8080 -T,9090) args=()
	plan_netbox args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS ports "$(base_image_name)"
	array_contains '--network=pasta:-T,8080,-T,9090,--dns-forward,169.254.1.1,--map-guest-addr,none' "${args[@]}"
}

@test "netbox plan binds dotfiles read-only and runs the supplied image" {
	load_netbox_plan
	local img args=()
	img="$(netbox_root_image "$PROJECT")"
	plan_netbox args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS PORTS "$img"
	array_contains "$TALKBOX_ROOT/defaults/dotfiles:/talkbox/dotfiles.global:ro" "${args[@]}"
	array_contains "$img" "${args[@]}"
}

@test "offbox plan mounts the worktree volume and names the container" {
	load_netbox_plan
	local args=()
	plan_offbox args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS PORTS "$(base_image_name)"
	array_contains 'talkbox-proj.offbox.worktree:/working/talkbox-proj' "${args[@]}"
	array_contains '--name=talkbox-proj.offbox' "${args[@]}"
}

@test "offbox plan restricts pasta to loopback and excludes talkbox0" {
	load_netbox_plan
	local args=()
	plan_offbox args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS PORTS "$(base_image_name)"
	array_contains '--network=pasta:-i,lo,-I,talkbox0' "${args[@]}"
	array_contains '--cap-drop=NET_ADMIN' "${args[@]}"
	array_contains '--cap-drop=NET_RAW' "${args[@]}"
}

@test "offbox plan appends the GPU device and group options when TALKBOX_GPU is yes" {
	load_netbox_plan
	# shellcheck disable=SC2034 # global consumed by plan_offbox
	TALKBOX_GPU=yes
	local args=()
	plan_offbox args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS PORTS "$(base_image_name)"
	array_has 'nvidia.com/gpu=all' "${args[@]}"
	array_has 'keep-groups' "${args[@]}"
}

@test "offbox plan forwards -T ports alongside the loopback restriction" {
	load_netbox_plan
	# shellcheck disable=SC2054 # -T,<port> tokens are single array elements
	# shellcheck disable=SC2034 # ports is consumed by nameref planner parameter
	local -a ports=(-T,8080) args=()
	plan_offbox args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS ports "$(base_image_name)"
	array_contains '--network=pasta:-T,8080,-i,lo,-I,talkbox0' "${args[@]}"
}

@test "offbox plan emits write-mount volumes and read-only read mounts" {
	load_netbox_plan
	local home="$BATS_TEST_TMPDIR/home" args=()
	mkdir -p "$home"
	# shellcheck disable=SC2034 # arrays are consumed by nameref planner parameters
	local read_mounts=() write_mounts=()
	mount_args read_mounts read "$BATS_TEST_TMPDIR/absent" "$PROJECT" "$home" '/host/data:/talkbox/wdata'
	mount_volume_args write_mounts offbox "$BATS_TEST_TMPDIR/absent" "$PROJECT" "$home" '/host/data:/talkbox/wdata'
	plan_offbox args "$PROJECT" yes read_mounts write_mounts PORTS "$(base_image_name)"
	array_contains '/host/data:/talkbox/wdata:ro' "${args[@]}"
	array_contains 'talkbox-proj.offbox.write.talkbox-wdata:/talkbox/wdata' "${args[@]}"
	array_has_none 'talkbox-proj.offbox.write.talkbox-wdata:/talkbox/wdata:ro' "${args[@]}"
}

@test "netbox plan emits git identity env vars for a git-tracked project but not for a non-git project" {
	load_netbox_plan
	git -C "$PROJECT" init -q
	git -C "$PROJECT" config user.name host-user
	git -C "$PROJECT" config user.email host@example.com
	local args=()
	plan_netbox args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS PORTS "$(base_image_name)"
	array_has 'TALKBOX_GIT_USER_NAME=host-user' "${args[@]}"
	array_has 'TALKBOX_GIT_USER_EMAIL=host@example.com' "${args[@]}"
	local plain
	plain="$BATS_TEST_TMPDIR/plain"
	mkdir -p "$plain"
	args=()
	plan_netbox args "$plain" yes READ_MOUNTS WRITE_MOUNTS PORTS "$(base_image_name)"
	array_has_none 'TALKBOX_GIT_USER' "${args[@]}"
}

@test "offbox plan emits git identity env vars for a git-tracked project but not for a non-git project" {
	load_netbox_plan
	git -C "$PROJECT" init -q
	git -C "$PROJECT" config user.name host-user
	git -C "$PROJECT" config user.email host@example.com
	local args=()
	plan_offbox args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS PORTS "$(base_image_name)"
	array_has 'TALKBOX_GIT_USER_NAME=host-user' "${args[@]}"
	array_has 'TALKBOX_GIT_USER_EMAIL=host@example.com' "${args[@]}"
	local plain
	plain="$BATS_TEST_TMPDIR/plain"
	mkdir -p "$plain"
	args=()
	plan_offbox args "$plain" yes READ_MOUNTS WRITE_MOUNTS PORTS "$(base_image_name)"
	array_has_none 'TALKBOX_GIT_USER' "${args[@]}"
}

@test "netbox plan emits --init for the persistent container" {
	load_netbox_plan
	local img args=()
	img="$(base_image_name)"
	plan_netbox args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS PORTS "$img"
	array_contains '--init' "${args[@]}"
}

@test "netbox plan emits --init ahead of the image name and the sleep command" {
	load_netbox_plan
	local img args=() init_at=-1 img_at=-1 i
	img="$(base_image_name)"
	plan_netbox args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS PORTS "$img"
	for ((i = 0; i < ${#args[@]}; i++)); do
		if [[ "${args[$i]}" == --init ]]; then
			init_at=$i
		fi
		if [[ "${args[$i]}" == "$img" ]]; then
			img_at=$i
		fi
	done
	[[ $init_at -ge 0 ]]
	[[ $init_at -lt $img_at ]]
}

@test "offbox plan emits --init for the persistent container" {
	load_netbox_plan
	local img args=()
	img="$(base_image_name)"
	plan_offbox args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS PORTS "$img"
	array_contains '--init' "${args[@]}"
}

@test "offbox plan emits --init ahead of the image name and the sleep command" {
	load_netbox_plan
	local img args=() init_at=-1 img_at=-1 i
	img="$(base_image_name)"
	plan_offbox args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS PORTS "$img"
	for ((i = 0; i < ${#args[@]}; i++)); do
		if [[ "${args[$i]}" == --init ]]; then
			init_at=$i
		fi
		if [[ "${args[$i]}" == "$img" ]]; then
			img_at=$i
		fi
	done
	[[ $init_at -ge 0 ]]
	[[ $init_at -lt $img_at ]]
}

@test "netbox recontain plan propagates --init to podman create" {
	load_netbox_plan
	# shellcheck disable=SC2034 # arrays are consumed by nameref planner parameters
	local -a srcs=() dsts=() args=()
	plan_netbox_recontain args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS srcs dsts PORTS base
	array_contains '--init' "${args[@]}"
}

@test "offbox recontain plan propagates --init to podman create" {
	load_netbox_plan
	# shellcheck disable=SC2034 # arrays are consumed by nameref planner parameters
	local -a srcs=() dsts=() args=()
	plan_offbox_recontain args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS srcs dsts PORTS base
	array_contains '--init' "${args[@]}"
}

@test "netbox rebuild plan propagates --init to podman create" {
	load_netbox_plan
	# shellcheck disable=SC2034 # arrays are consumed by nameref planner parameters
	local -a srcs=() dsts=() args=()
	plan_netbox_rebuild args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS srcs dsts PORTS base
	array_contains '--init' "${args[@]}"
}

@test "offbox rebuild plan propagates --init to podman create" {
	load_netbox_plan
	# shellcheck disable=SC2034 # arrays are consumed by nameref planner parameters
	local -a srcs=() dsts=() args=()
	plan_offbox_rebuild args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS srcs dsts PORTS base
	array_contains '--init' "${args[@]}"
}

@test "netbox plan adds the git mounts and the populate leaves the gitdir volume empty" {
	load_netbox_plan
	mkdir -p "$PROJECT/.git"
	local args=()
	plan_netbox args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS PORTS "$(base_image_name)"
	array_contains "$PROJECT/.git:/host/git:ro" "${args[@]}"
	array_contains 'talkbox-proj.netbox.gitdir:/working/talkbox-proj/.git' "${args[@]}"
	# shellcheck disable=SC2034 # arrays are consumed by nameref planner parameters
	local srcs=() dsts=() plan=()
	plan_netbox_populate plan "$PROJECT" srcs dsts
	array_has_none 'talkbox-proj.netbox.gitdir' "${plan[@]}"
}

@test "offbox plan adds the git mounts and the populate leaves the gitdir volume empty" {
	load_netbox_plan
	mkdir -p "$PROJECT/.git"
	local args=()
	plan_offbox args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS PORTS "$(base_image_name)"
	array_contains "$PROJECT/.git:/host/git:ro" "${args[@]}"
	array_contains 'talkbox-proj.offbox.gitdir:/working/talkbox-proj/.git' "${args[@]}"
	# shellcheck disable=SC2034 # arrays are consumed by nameref planner parameters
	local srcs=() dsts=() plan=()
	plan_offbox_populate plan "$PROJECT" base srcs dsts
	array_has_none 'talkbox-proj.offbox.gitdir' "${plan[@]}"
}

@test "netbox plan emits the prompt host env vars for git-tracked and non-git projects" {
	load_netbox_plan
	git -C "$PROJECT" init -q
	git -C "$PROJECT" config user.name host-user
	git -C "$PROJECT" config user.email host@example.com
	local args=()
	plan_netbox args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS PORTS "$(base_image_name)"
	array_contains 'TALKBOX_PROJECT_SLUG=talkbox-proj' "${args[@]}"
	array_contains 'TALKBOX_CONTAINER_TYPE=netbox' "${args[@]}"
	array_has 'TALKBOX_GIT_USER_NAME=host-user' "${args[@]}"
	local plain
	plain="$BATS_TEST_TMPDIR/plain"
	mkdir -p "$plain"
	args=()
	plan_netbox args "$plain" yes READ_MOUNTS WRITE_MOUNTS PORTS "$(base_image_name)"
	array_contains 'TALKBOX_PROJECT_SLUG=plain' "${args[@]}"
	array_contains 'TALKBOX_CONTAINER_TYPE=netbox' "${args[@]}"
	array_has_none 'TALKBOX_GIT_USER' "${args[@]}"
}

@test "offbox plan emits the prompt host env vars for git-tracked and non-git projects" {
	load_netbox_plan
	git -C "$PROJECT" init -q
	git -C "$PROJECT" config user.name host-user
	git -C "$PROJECT" config user.email host@example.com
	local args=()
	plan_offbox args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS PORTS "$(base_image_name)"
	array_contains 'TALKBOX_PROJECT_SLUG=talkbox-proj' "${args[@]}"
	array_contains 'TALKBOX_CONTAINER_TYPE=offbox' "${args[@]}"
	array_has 'TALKBOX_GIT_USER_NAME=host-user' "${args[@]}"
	local plain
	plain="$BATS_TEST_TMPDIR/plain"
	mkdir -p "$plain"
	args=()
	plan_offbox args "$plain" yes READ_MOUNTS WRITE_MOUNTS PORTS "$(base_image_name)"
	array_contains 'TALKBOX_PROJECT_SLUG=plain' "${args[@]}"
	array_contains 'TALKBOX_CONTAINER_TYPE=offbox' "${args[@]}"
	array_has_none 'TALKBOX_GIT_USER' "${args[@]}"
}

@test "netbox recontain and rebuild plans propagate the prompt host env vars to podman create" {
	load_netbox_plan
	# shellcheck disable=SC2034 # arrays are consumed by nameref planner parameters
	local -a srcs=() dsts=() args=()
	plan_netbox_recontain args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS srcs dsts PORTS base
	array_contains 'TALKBOX_PROJECT_SLUG=talkbox-proj' "${args[@]}"
	array_contains 'TALKBOX_CONTAINER_TYPE=netbox' "${args[@]}"
	args=()
	plan_netbox_rebuild args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS srcs dsts PORTS base
	array_contains 'TALKBOX_PROJECT_SLUG=talkbox-proj' "${args[@]}"
	array_contains 'TALKBOX_CONTAINER_TYPE=netbox' "${args[@]}"
}

@test "offbox recontain and rebuild plans propagate the prompt host env vars to podman create" {
	load_netbox_plan
	# shellcheck disable=SC2034 # arrays are consumed by nameref planner parameters
	local -a srcs=() dsts=() args=()
	plan_offbox_recontain args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS srcs dsts PORTS base
	array_contains 'TALKBOX_PROJECT_SLUG=talkbox-proj' "${args[@]}"
	array_contains 'TALKBOX_CONTAINER_TYPE=offbox' "${args[@]}"
	args=()
	plan_offbox_rebuild args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS srcs dsts PORTS base
	array_contains 'TALKBOX_PROJECT_SLUG=talkbox-proj' "${args[@]}"
	array_contains 'TALKBOX_CONTAINER_TYPE=offbox' "${args[@]}"
}

@test "netbox plan does not mount a tmpfs at /run/talkbox" {
	load_netbox_plan
	local args=()
	plan_netbox args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS PORTS "$(base_image_name)"
	array_has_none '--tmpfs' "${args[@]}"
	array_has_none '/run/talkbox' "${args[@]}"
}

@test "offbox plan does not mount a tmpfs at /run/talkbox" {
	load_netbox_plan
	local args=()
	plan_offbox args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS PORTS "$(base_image_name)"
	array_has_none '--tmpfs' "${args[@]}"
	array_has_none '/run/talkbox' "${args[@]}"
}

@test "netbox recontain plan does not emit a /run/talkbox tmpfs" {
	load_netbox_plan
	# shellcheck disable=SC2034 # arrays are consumed by nameref planner parameters
	local -a srcs=() dsts=() args=()
	plan_netbox_recontain args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS srcs dsts PORTS base
	array_has_none '--tmpfs' "${args[@]}"
	array_has_none '/run/talkbox' "${args[@]}"
}

@test "offbox recontain plan does not emit a /run/talkbox tmpfs" {
	load_netbox_plan
	# shellcheck disable=SC2034 # arrays are consumed by nameref planner parameters
	local -a srcs=() dsts=() args=()
	plan_offbox_recontain args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS srcs dsts PORTS base
	array_has_none '--tmpfs' "${args[@]}"
	array_has_none '/run/talkbox' "${args[@]}"
}

@test "netbox rebuild plan does not emit a /run/talkbox tmpfs" {
	load_netbox_plan
	# shellcheck disable=SC2034 # arrays are consumed by nameref planner parameters
	local -a srcs=() dsts=() args=()
	plan_netbox_rebuild args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS srcs dsts PORTS base
	array_has_none '--tmpfs' "${args[@]}"
	array_has_none '/run/talkbox' "${args[@]}"
}

@test "offbox rebuild plan does not emit a /run/talkbox tmpfs" {
	load_netbox_plan
	# shellcheck disable=SC2034 # arrays are consumed by nameref planner parameters
	local -a srcs=() dsts=() args=()
	plan_offbox_rebuild args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS srcs dsts PORTS base
	array_has_none '--tmpfs' "${args[@]}"
	array_has_none '/run/talkbox' "${args[@]}"
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
