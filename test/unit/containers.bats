load helpers

load_onbox_plan() {
	load_lib naming.sh
	load_lib mounts.sh
	load_lib ports.sh
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

# shellcheck disable=SC2034 # arrays are consumed by nameref planner parameters
setup() {
	PROJECT="$BATS_TEST_TMPDIR/talkbox-proj"
	mkdir -p "$PROJECT"
	READ_MOUNTS=()
	WRITE_MOUNTS=()
	PORTS=()
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
	array_contains '--network=pasta' "${args[@]}"
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
	array_contains '--network=pasta:-T,8080,-T,9090' "${args[@]}"
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

@test "onbox run plan creates and starts the persistent container for an interactive shell" {
	load_onbox_plan
	local args=()
	plan_onbox_run args "$PROJECT" '' yes READ_MOUNTS WRITE_MOUNTS PORTS
	[[ "$(plan_subcommands args)" == $'create\nstart' ]]
}

@test "onbox run plan execs a command after creating and starting the container" {
	load_onbox_plan
	local args=()
	plan_onbox_run args "$PROJECT" 'pwd' no READ_MOUNTS WRITE_MOUNTS PORTS
	[[ "$(plan_subcommands args)" == $'create\nstart\nexec' ]]
	[[ "${args[${#args[@]} - 1]}" == 'pwd' ]]
}

@test "onbox plan omits the global dotfiles bind-mount when defaults/dotfiles is absent" {
	load_onbox_plan
	TALKBOX_ROOT="$BATS_TEST_TMPDIR/talkbox-root-no-dotfiles"
	mkdir -p "$TALKBOX_ROOT"
	local args=()
	plan_onbox args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS PORTS
	array_has_none 'dotfiles.global' "${args[@]}"
}
