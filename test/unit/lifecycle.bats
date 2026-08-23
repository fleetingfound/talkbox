load helpers

load_lifecycle_plan() {
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
	SRCS=()
	DSTS=()
	PORTS=()
}

@test "recontain plan removes, recreates and starts the container" {
	load_lifecycle_plan
	local args=()
	plan_recontain args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS PORTS
	[[ "$(plan_subcommands args)" == $'rm\ncreate\nstart' ]]
	array_contains '--volumes' "${args[@]}"
	array_contains 'talkbox-proj.onbox' "${args[@]}"
	array_contains '--name=talkbox-proj.onbox' "${args[@]}"
}

@test "rebuild plan rebuilds the base image then recreates and starts" {
	load_lifecycle_plan
	local args=()
	plan_rebuild args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS PORTS
	[[ "$(plan_subcommands args)" == $'build\nrm\ncreate\nstart' ]]
	array_contains '-t' "${args[@]}"
	array_contains 'talkbox/base:latest' "${args[@]}"
	array_contains "$TALKBOX_ROOT/image/Containerfile" "${args[@]}"
}

@test "rm-container plan removes the container with its volumes" {
	load_lifecycle_plan
	local args=()
	plan_rm_container args "$PROJECT"
	[[ "$(plan_subcommands args)" == 'rm' ]]
	array_contains '--volumes' "${args[@]}"
	array_contains 'talkbox-proj.onbox' "${args[@]}"
}

@test "rm-image plan removes the base image when it is not in use" {
	load_lifecycle_plan
	local args=()
	plan_rm_image args "$PROJECT" no
	[[ "$(plan_subcommands args)" == 'rmi' ]]
	array_contains 'talkbox/base:latest' "${args[@]}"
}

@test "rm-image plan refuses to remove the base image when it is in use" {
	load_lifecycle_plan
	local args=()
	plan_rm_image args "$PROJECT" yes
	[[ ${#args[@]} -eq 0 ]]
	[[ -z "$(plan_subcommands args)" ]]
}

@test "netbox recontain plan commits the source, populates and recreates the container" {
	load_lifecycle_plan
	local args=()
	plan_netbox_recontain args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS onbox
	[[ "$(plan_subcommands args)" == $'commit\nrm\nrun\ncreate\nstart' ]]
	array_contains 'talkbox-proj.onbox' "${args[@]}"
	array_contains 'talkbox-proj.netbox.root' "${args[@]}"
	array_contains '--name=talkbox-proj.netbox' "${args[@]}"
	array_contains 'talkbox-proj.netbox.worktree:/talkbox/target' "${args[@]}"
}

@test "offbox recontain plan commits the netbox source, populates and recreates the container" {
	load_lifecycle_plan
	local args=()
	plan_offbox_recontain args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS netbox
	[[ "$(plan_subcommands args)" == $'commit\nrm\nrun\ncreate\nstart' ]]
	array_contains 'talkbox-proj.netbox' "${args[@]}"
	array_contains 'talkbox-proj.offbox.root' "${args[@]}"
	array_contains '--name=talkbox-proj.offbox' "${args[@]}"
	array_contains 'talkbox-proj.offbox.worktree:/talkbox/target' "${args[@]}"
}

@test "netbox recontain plan skips the commit when the source is the base image" {
	load_lifecycle_plan
	local args=()
	plan_netbox_recontain args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS base
	[[ "$(plan_subcommands args)" == $'rm\nrun\ncreate\nstart' ]]
	array_has_none 'podman commit' "${args[@]}"
	array_contains 'talkbox-proj.netbox.worktree:/talkbox/target' "${args[@]}"
}

@test "netbox recontain plan populates the write volumes when present" {
	load_lifecycle_plan
	# shellcheck disable=SC2034 # arrays are consumed by nameref planner parameters
	local -a srcs=('/host/data') dsts=('/talkbox/wdata') args=()
	plan_netbox_recontain args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS srcs dsts PORTS onbox
	[[ "$(plan_subcommands args)" == $'commit\nrm\nrun\nrun\ncreate\nstart' ]]
	array_contains 'talkbox-proj.netbox.worktree:/talkbox/target' "${args[@]}"
	array_contains 'talkbox-proj.netbox.write.talkbox-wdata:/talkbox/target' "${args[@]}"
}

@test "offbox recontain plan populates the write volumes when present" {
	load_lifecycle_plan
	# shellcheck disable=SC2034 # arrays are consumed by nameref planner parameters
	local -a srcs=('/host/data') dsts=('/talkbox/wdata') args=()
	plan_offbox_recontain args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS srcs dsts PORTS onbox
	[[ "$(plan_subcommands args)" == $'commit\nrm\nrun\nrun\ncreate\nstart' ]]
	array_contains 'talkbox-proj.offbox.worktree:/talkbox/target' "${args[@]}"
	array_contains 'talkbox-proj.offbox.write.talkbox-wdata:/talkbox/target' "${args[@]}"
}

@test "netbox rebuild plan rebuilds the base image, commits, populates and recreates" {
	load_lifecycle_plan
	local args=()
	plan_netbox_rebuild args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS onbox
	[[ "$(plan_subcommands args)" == $'build\ncommit\nrm\nrun\ncreate\nstart' ]]
	array_contains 'talkbox/base:latest' "${args[@]}"
	array_contains 'talkbox-proj.netbox.root' "${args[@]}"
	array_contains 'talkbox-proj.netbox.worktree:/talkbox/target' "${args[@]}"
}

@test "offbox rebuild plan rebuilds the base image, commits, populates and recreates" {
	load_lifecycle_plan
	local args=()
	plan_offbox_rebuild args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS onbox
	[[ "$(plan_subcommands args)" == $'build\ncommit\nrm\nrun\ncreate\nstart' ]]
	array_contains 'talkbox/base:latest' "${args[@]}"
	array_contains 'talkbox-proj.offbox.root' "${args[@]}"
	array_contains 'talkbox-proj.offbox.worktree:/talkbox/target' "${args[@]}"
}

@test "netbox rm-container plan removes the container and its root image" {
	load_lifecycle_plan
	local args=()
	plan_netbox_rm_container args "$PROJECT"
	[[ "$(plan_subcommands args)" == $'rm\nrmi' ]]
	array_contains 'talkbox-proj.netbox' "${args[@]}"
	array_contains '--volumes' "${args[@]}"
	array_contains 'talkbox-proj.netbox.root' "${args[@]}"
}

@test "offbox rm-container plan removes the container and its root image" {
	load_lifecycle_plan
	local args=()
	plan_offbox_rm_container args "$PROJECT"
	[[ "$(plan_subcommands args)" == $'rm\nrmi' ]]
	array_contains 'talkbox-proj.offbox' "${args[@]}"
	array_contains '--volumes' "${args[@]}"
	array_contains 'talkbox-proj.offbox.root' "${args[@]}"
}

@test "netbox rm-image plan removes the base image when it is not in use" {
	load_lifecycle_plan
	local args=()
	plan_netbox_rm_image args "$PROJECT" no
	[[ "$(plan_subcommands args)" == 'rmi' ]]
	array_contains 'talkbox/base:latest' "${args[@]}"
}

@test "netbox rm-image plan refuses to remove the base image when it is in use" {
	load_lifecycle_plan
	local args=()
	plan_netbox_rm_image args "$PROJECT" yes
	[[ ${#args[@]} -eq 0 ]]
	[[ -z "$(plan_subcommands args)" ]]
}
