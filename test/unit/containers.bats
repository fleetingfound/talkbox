load helpers

load_onbox_plan() {
	load_lib naming.sh
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

setup() {
	PROJECT="$BATS_TEST_TMPDIR/talkbox-proj"
	mkdir -p "$PROJECT"
}

@test "onbox plan sets the working directory to /working/<project-base>" {
	load_onbox_plan
	local args=()
	plan_onbox args "$PROJECT" '' yes yes
	array_contains '--workdir=/working/talkbox-proj' "${args[@]}"
}

@test "onbox plan maps the host user to container uid/gid 1000" {
	load_onbox_plan
	local args=()
	plan_onbox args "$PROJECT" '' yes yes
	array_contains '--userns=keep-id:uid=1000,gid=1000' "${args[@]}"
}

@test "onbox plan uses rootless pasta networking without host-port forwarding" {
	load_onbox_plan
	local args=()
	plan_onbox args "$PROJECT" '' yes yes
	array_contains '--network=pasta' "${args[@]}"
	[[ "${args[*]}" != *'-T,'* ]]
}

@test "onbox plan drops NET_ADMIN and NET_RAW capabilities" {
	load_onbox_plan
	local args=()
	plan_onbox args "$PROJECT" '' yes yes
	array_contains '--cap-drop=NET_ADMIN' "${args[@]}"
	array_contains '--cap-drop=NET_RAW' "${args[@]}"
}

@test "onbox plan bind-mounts the host worktree read-write" {
	load_onbox_plan
	local args=()
	plan_onbox args "$PROJECT" '' yes yes
	array_contains "$PROJECT:/working/talkbox-proj" "${args[@]}"
	if array_contains "$PROJECT:/working/talkbox-proj:ro" "${args[@]}"; then
		return 1
	fi
}

@test "onbox plan bind-mounts global dotfiles read-only" {
	load_onbox_plan
	local args=()
	plan_onbox args "$PROJECT" '' yes yes
	array_contains "$TALKBOX_ROOT/defaults/dotfiles:/talkbox/dotfiles.global:ro" "${args[@]}"
}

@test "onbox plan bind-mounts project dotfiles read-only when they exist" {
	load_onbox_plan
	mkdir -p "$PROJECT/.dotfiles"
	local args=()
	plan_onbox args "$PROJECT" '' yes yes
	array_contains "$PROJECT/.dotfiles:/talkbox/dotfiles.project:ro" "${args[@]}"
}

@test "onbox plan omits the project dotfiles bind-mount when .dotfiles is absent" {
	load_onbox_plan
	local args=()
	plan_onbox args "$PROJECT" '' yes yes
	array_has_none 'dotfiles.project' "${args[@]}"
}

@test "onbox plan runs the shared base image" {
	load_onbox_plan
	local img args=()
	img="$(base_image_name)"
	plan_onbox args "$PROJECT" '' yes yes
	array_contains "$img" "${args[@]}"
}

@test "onbox plan emits --rm so the container is removed after exit" {
	load_onbox_plan
	local args=()
	plan_onbox args "$PROJECT" '' yes yes
	array_contains '--rm' "${args[@]}"
}

@test "onbox plan omits --rm when the rm input is no" {
	load_onbox_plan
	local args=()
	plan_onbox args "$PROJECT" '' yes no
	if array_contains '--rm' "${args[@]}"; then
		return 1
	fi
}

@test "onbox interactive plan allocates a terminal" {
	load_onbox_plan
	local args=()
	plan_onbox args "$PROJECT" '' yes yes
	array_contains '--interactive' "${args[@]}"
	array_contains '--tty' "${args[@]}"
}

@test "onbox noninteractive plan does not allocate a terminal" {
	load_onbox_plan
	local args=()
	plan_onbox args "$PROJECT" 'pwd' no yes
	if array_contains '--interactive' "${args[@]}" || array_contains '--tty' "${args[@]}"; then
		return 1
	fi
}

@test "onbox noninteractive plan appends the command as the last element" {
	load_onbox_plan
	local args=()
	plan_onbox args "$PROJECT" 'pwd' no yes
	[[ "${args[${#args[@]} - 1]}" == 'pwd' ]]
}

@test "onbox plan omits the global dotfiles bind-mount when defaults/dotfiles is absent" {
	load_onbox_plan
	TALKBOX_ROOT="$BATS_TEST_TMPDIR/talkbox-root-no-dotfiles"
	mkdir -p "$TALKBOX_ROOT"
	local args=()
	plan_onbox args "$PROJECT" '' yes yes
	array_has_none 'dotfiles.global' "${args[@]}"
}
