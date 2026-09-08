load helpers

load_onbox_plan() {
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
	DENY=()
}

@test "onbox plan sets the working directory to /working/<project-base>" {
	load_onbox_plan
	local args=()
	plan_onbox args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS PORTS
	array_contains '--workdir=/working/talkbox-proj' "${args[@]}"
}

@test "onbox plan maps the host user to container uid/gid 1000" {
	load_onbox_plan
	local args=()
	plan_onbox args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS PORTS
	array_contains '--userns=keep-id:uid=1000,gid=1000' "${args[@]}"
}

@test "onbox plan uses rootless pasta networking without host-port forwarding" {
	load_onbox_plan
	local args=()
	plan_onbox args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS PORTS
	array_contains '--network=pasta:--dns-forward,169.254.1.1,--map-guest-addr,none' "${args[@]}"
	[[ "${args[*]}" != *'-T,'* ]]
}

@test "onbox plan drops NET_ADMIN and NET_RAW capabilities" {
	load_onbox_plan
	local args=()
	plan_onbox args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS PORTS
	array_contains '--cap-drop=NET_ADMIN' "${args[@]}"
	array_contains '--cap-drop=NET_RAW' "${args[@]}"
}

@test "onbox plan bind-mounts the host worktree read-write" {
	load_onbox_plan
	local args=()
	plan_onbox args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS PORTS
	array_contains "$PROJECT:/working/talkbox-proj" "${args[@]}"
	if array_contains "$PROJECT:/working/talkbox-proj:ro" "${args[@]}"; then
		return 1
	fi
}

@test "onbox plan bind-mounts global dotfiles read-only" {
	load_onbox_plan
	local args=()
	plan_onbox args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS PORTS
	array_contains "$TALKBOX_ROOT/defaults/dotfiles:/talkbox/dotfiles.global:ro" "${args[@]}"
}

@test "onbox plan bind-mounts project dotfiles read-only when they exist" {
	load_onbox_plan
	mkdir -p "$PROJECT/.dotfiles"
	local args=()
	plan_onbox args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS PORTS
	array_contains "$PROJECT/.dotfiles:/talkbox/dotfiles.project:ro" "${args[@]}"
}

@test "onbox plan omits the project dotfiles bind-mount when .dotfiles is absent" {
	load_onbox_plan
	local args=()
	plan_onbox args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS PORTS
	array_has_none 'dotfiles.project' "${args[@]}"
}

@test "onbox plan appends the GPU device and group options when TALKBOX_GPU is yes" {
	load_onbox_plan
	# shellcheck disable=SC2034 # global consumed by plan_onbox
	TALKBOX_GPU=yes
	local args=()
	plan_onbox args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS PORTS
	array_has 'nvidia.com/gpu=all' "${args[@]}"
	array_has 'keep-groups' "${args[@]}"
}

@test "onbox recontain plan passes the GPU options to podman create when TALKBOX_GPU is yes" {
	load_onbox_plan
	# shellcheck disable=SC2034 # global consumed by plan_onbox
	TALKBOX_GPU=yes
	local args=()
	plan_recontain args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS PORTS DENY
	array_has 'nvidia.com/gpu=all' "${args[@]}"
	array_has 'keep-groups' "${args[@]}"
}

@test "onbox rebuild plan passes the GPU options to podman create when TALKBOX_GPU is yes" {
	load_onbox_plan
	# shellcheck disable=SC2034 # global consumed by plan_onbox
	TALKBOX_GPU=yes
	local args=()
	plan_rebuild args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS PORTS DENY
	array_has 'nvidia.com/gpu=all' "${args[@]}"
	array_has 'keep-groups' "${args[@]}"
}

@test "onbox plan emits --init for the persistent container" {
	load_onbox_plan
	local args=()
	plan_onbox args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS PORTS
	array_contains '--init' "${args[@]}"
}

@test "onbox plan emits --init ahead of the image name and the sleep command" {
	load_onbox_plan
	local img args=() init_at=-1 img_at=-1 i
	img="$(base_image_name)"
	plan_onbox args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS PORTS
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

@test "onbox recontain plan propagates --init to podman create" {
	load_onbox_plan
	local args=()
	plan_recontain args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS PORTS DENY
	array_contains '--init' "${args[@]}"
}

@test "onbox rebuild plan propagates --init to podman create" {
	load_onbox_plan
	local args=()
	plan_rebuild args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS PORTS DENY
	array_contains '--init' "${args[@]}"
}

@test "onbox plan runs the shared base image" {
	load_onbox_plan
	local img args=()
	img="$(base_image_name)"
	plan_onbox args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS PORTS
	array_contains "$img" "${args[@]}"
}

@test "onbox plan names the persistent container <project-slug>.onbox" {
	load_onbox_plan
	local args=()
	plan_onbox args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS PORTS
	array_contains '--name=talkbox-proj.onbox' "${args[@]}"
}

@test "onbox plan does not emit --rm for the persistent normal run" {
	load_onbox_plan
	local args=()
	plan_onbox args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS PORTS
	array_has_none '--rm' "${args[@]}"
}

@test "onbox plan applies default mounts and pasta -T ports" {
	load_onbox_plan
	local home="$BATS_TEST_TMPDIR/home"
	mkdir -p "$home"
	printf '/host/etc\n' >"$BATS_TEST_TMPDIR/read.mounts"
	printf '/host/var\n' >"$BATS_TEST_TMPDIR/write.mounts"
	printf '8080\n' >"$BATS_TEST_TMPDIR/ports"
	# shellcheck disable=SC2034 # arrays are consumed by nameref parameters
	local read_mounts=() write_mounts=() ports=() args=()
	mount_args read_mounts read "$BATS_TEST_TMPDIR/read.mounts" "$PROJECT" "$home"
	mount_args write_mounts write "$BATS_TEST_TMPDIR/write.mounts" "$PROJECT" "$home"
	port_args ports "$BATS_TEST_TMPDIR/ports" 9090
	plan_onbox args "$PROJECT" yes read_mounts write_mounts ports
	array_contains '/host/etc:/host/read/etc:ro' "${args[@]}"
	array_contains '/host/var:/host/write/var' "${args[@]}"
	array_contains '--network=pasta:-T,8080,-T,9090,--dns-forward,169.254.1.1,--map-guest-addr,none' "${args[@]}"
}

@test "onbox interactive plan allocates a terminal" {
	load_onbox_plan
	local args=()
	plan_onbox args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS PORTS
	array_contains '--interactive' "${args[@]}"
	array_contains '--tty' "${args[@]}"
}

@test "onbox noninteractive plan does not allocate a terminal" {
	load_onbox_plan
	local args=()
	plan_onbox args "$PROJECT" no READ_MOUNTS WRITE_MOUNTS PORTS
	if array_contains '--interactive' "${args[@]}" || array_contains '--tty' "${args[@]}"; then
		return 1
	fi
}

@test "onbox plan omits the global dotfiles bind-mount when defaults/dotfiles is absent" {
	load_onbox_plan
	TALKBOX_ROOT="$BATS_TEST_TMPDIR/talkbox-root-no-dotfiles"
	mkdir -p "$TALKBOX_ROOT"
	local args=()
	plan_onbox args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS PORTS
	array_has_none 'dotfiles.global' "${args[@]}"
}

@test "onbox plan adds the git mounts for a git-tracked project and omits them for a non-git project" {
	load_onbox_plan
	mkdir -p "$PROJECT/.git"
	local args=()
	plan_onbox args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS PORTS
	array_contains "$PROJECT/.git:/host/git:ro" "${args[@]}"
	array_contains 'talkbox-proj.onbox.gitdir:/working/talkbox-proj/.git' "${args[@]}"
	local plain
	plain="$BATS_TEST_TMPDIR/plain"
	mkdir -p "$plain"
	args=()
	plan_onbox args "$plain" yes READ_MOUNTS WRITE_MOUNTS PORTS
	array_has_none '/host/git' "${args[@]}"
	array_has_none '.gitdir' "${args[@]}"
}

@test "onbox plan emits git identity env vars for a git-tracked project but not for a non-git project" {
	load_onbox_plan
	git -C "$PROJECT" init -q
	git -C "$PROJECT" config user.name host-user
	git -C "$PROJECT" config user.email host@example.com
	local args=()
	plan_onbox args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS PORTS
	array_has 'TALKBOX_GIT_USER_NAME=host-user' "${args[@]}"
	array_has 'TALKBOX_GIT_USER_EMAIL=host@example.com' "${args[@]}"
	local plain
	plain="$BATS_TEST_TMPDIR/plain"
	mkdir -p "$plain"
	args=()
	plan_onbox args "$plain" yes READ_MOUNTS WRITE_MOUNTS PORTS
	array_has_none 'TALKBOX_GIT_USER' "${args[@]}"
}

@test "onbox plan omits a git identity env var for a field the host has not configured" {
	load_onbox_plan
	export HOME="$BATS_TEST_TMPDIR/home"
	export GIT_CONFIG_NOSYSTEM=1
	git -C "$PROJECT" init -q
	git -C "$PROJECT" config user.email host@example.com
	local args=()
	plan_onbox args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS PORTS
	array_has_none 'TALKBOX_GIT_USER_NAME' "${args[@]}"
	array_has 'TALKBOX_GIT_USER_EMAIL=host@example.com' "${args[@]}"
}

@test "onbox plan emits the prompt host env vars for git-tracked and non-git projects" {
	load_onbox_plan
	git -C "$PROJECT" init -q
	git -C "$PROJECT" config user.name host-user
	git -C "$PROJECT" config user.email host@example.com
	local args=()
	plan_onbox args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS PORTS
	array_contains 'TALKBOX_PROJECT_SLUG=talkbox-proj' "${args[@]}"
	array_contains 'TALKBOX_CONTAINER_TYPE=onbox' "${args[@]}"
	array_has 'TALKBOX_GIT_USER_NAME=host-user' "${args[@]}"
	local plain
	plain="$BATS_TEST_TMPDIR/plain"
	mkdir -p "$plain"
	args=()
	plan_onbox args "$plain" yes READ_MOUNTS WRITE_MOUNTS PORTS
	array_contains 'TALKBOX_PROJECT_SLUG=plain' "${args[@]}"
	array_contains 'TALKBOX_CONTAINER_TYPE=onbox' "${args[@]}"
	array_has_none 'TALKBOX_GIT_USER' "${args[@]}"
}

@test "onbox recontain and rebuild plans propagate the prompt host env vars to podman create" {
	load_onbox_plan
	local args=()
	plan_recontain args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS PORTS DENY
	array_contains 'TALKBOX_PROJECT_SLUG=talkbox-proj' "${args[@]}"
	array_contains 'TALKBOX_CONTAINER_TYPE=onbox' "${args[@]}"
	args=()
	plan_rebuild args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS PORTS DENY
	array_contains 'TALKBOX_PROJECT_SLUG=talkbox-proj' "${args[@]}"
	array_contains 'TALKBOX_CONTAINER_TYPE=onbox' "${args[@]}"
}

@test "onbox plan mounts a tmpfs at /run/talkbox for the entrypoint readiness sentinel" {
	load_onbox_plan
	local img args=() tmpfs_at=-1 img_at=-1 i
	img="$(base_image_name)"
	plan_onbox args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS PORTS
	for ((i = 0; i < ${#args[@]}; i++)); do
		if [[ "${args[$i]}" == --tmpfs ]]; then
			tmpfs_at=$i
		fi
		if [[ "${args[$i]}" == "$img" ]]; then
			img_at=$i
		fi
	done
	[[ $tmpfs_at -ge 0 ]]
	[[ "${args[$((tmpfs_at + 1))]}" == /run/talkbox ]]
	[[ $tmpfs_at -lt $img_at ]]
}

@test "onbox recontain plan propagates the /run/talkbox tmpfs to podman create" {
	load_onbox_plan
	local args=()
	plan_recontain args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS PORTS DENY
	array_contains '--tmpfs' "${args[@]}"
	array_contains '/run/talkbox' "${args[@]}"
}

@test "onbox rebuild plan propagates the /run/talkbox tmpfs to podman create" {
	load_onbox_plan
	local args=()
	plan_rebuild args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS PORTS DENY
	array_contains '--tmpfs' "${args[@]}"
	array_contains '/run/talkbox' "${args[@]}"
}

@test "wait_for_entrypoint returns success once podman exec reports the sentinel file" {
	load_onbox_plan
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
	PATH="$shimdir:$PATH" run wait_for_entrypoint talkbox-proj.onbox
	[[ "$status" -eq 0 ]]
	[[ -f "$log" ]]
	[[ "$(cat "$log")" == *'exec'* ]]
	[[ "$(cat "$log")" == *'/run/talkbox/ready'* ]]
}

@test "wait_for_entrypoint dies with a talkbox error when the sentinel never appears" {
	load_onbox_plan
	local shimdir
	shimdir="$BATS_TEST_TMPDIR/shim"
	mkdir -p "$shimdir"
	cat >"$shimdir/podman" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
	chmod +x "$shimdir/podman"
	PATH="$shimdir:$PATH" run wait_for_entrypoint talkbox-proj.onbox
	[[ "$status" -ne 0 ]]
	[[ "$output" == *'talkbox:'* ]]
}
