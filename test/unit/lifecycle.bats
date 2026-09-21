load helpers

load_lifecycle_plan() {
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

plan_has_subcommand() {
	local -n _plan="$1"
	local needle="$2"
	local line
	while IFS= read -r line; do
		if [[ "$line" == "$needle" ]]; then
			return 0
		fi
	done < <(plan_subcommands "$1")
	return 1
}

plan_volume_rm_tokens() {
	local -n _plan="$1"
	local i count=0
	for ((i = 0; i + 4 < ${#_plan[@]}; i++)); do
		if [[ "${_plan[$i]}" == podman && "${_plan[$((i + 1))]}" == volume && "${_plan[$((i + 2))]}" == rm && "${_plan[$((i + 3))]}" == -f ]]; then
			((count++))
		fi
	done
	printf '%s\n' "$count"
}

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
	mkdir -p "$PROJECT/.git"
	stub_volumes 'talkbox-proj.onbox.gitdir'
	local args=()
	plan_recontain args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS PORTS
	[[ "$(plan_subcommands args)" == $'rm\nvolume\ncreate\nstart' ]]
	[[ "$(plan_volume_rm_tokens args)" -eq 1 ]]
	array_contains '--volumes' "${args[@]}"
	array_contains 'talkbox-proj.onbox' "${args[@]}"
	array_contains '--name=talkbox-proj.onbox' "${args[@]}"
	plan_has_volume_rm args 'talkbox-proj.onbox.gitdir'
}

@test "rebuild plan rebuilds the base image then recreates and starts" {
	load_lifecycle_plan
	mkdir -p "$PROJECT/.git"
	stub_volumes 'talkbox-proj.onbox.gitdir'
	local args=()
	plan_rebuild args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS PORTS
	[[ "$(plan_subcommands args)" == $'build\nrm\nvolume\ncreate\nstart' ]]
	[[ "$(plan_volume_rm_tokens args)" -eq 1 ]]
	array_contains '-t' "${args[@]}"
	array_contains 'talkbox/base:latest' "${args[@]}"
	array_contains "$TALKBOX_ROOT/image/Containerfile" "${args[@]}"
	plan_has_volume_rm args 'talkbox-proj.onbox.gitdir'
}

@test "recontain plan removes only the volumes that exist" {
	load_lifecycle_plan
	mkdir -p "$PROJECT/.git"
	local args=()
	plan_recontain args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS PORTS
	[[ "$(plan_volume_rm_tokens args)" -eq 0 ]]
	plan_has_volume_rm_none args 'talkbox-proj.onbox.gitdir'
	stub_volumes 'talkbox-proj.onbox.gitdir'
	args=()
	plan_recontain args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS PORTS
	[[ "$(plan_volume_rm_tokens args)" -eq 1 ]]
	plan_has_volume_rm args 'talkbox-proj.onbox.gitdir'
}

@test "rm-container plan removes the container with its volumes" {
	load_lifecycle_plan
	mkdir -p "$PROJECT/.git"
	stub_volumes 'talkbox-proj.onbox.gitdir'
	local args=()
	plan_rm_container args "$PROJECT"
	[[ "$(plan_volume_rm_tokens args)" -eq 1 ]]
	plan_has_volume_rm args 'talkbox-proj.onbox.gitdir'
	plan_has_subcommand args rm
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

@test "netbox recontain plan commits the source, removes volumes, populates and recreates the container" {
	load_lifecycle_plan
	mkdir -p "$PROJECT/.git"
	stub_volumes 'talkbox-proj.netbox.worktree' 'talkbox-proj.netbox.gitdir'
	local args=()
	plan_netbox_recontain args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS onbox
	[[ "$(plan_subcommands args)" == $'commit\nrm\nvolume\nvolume\nrun\ncreate\nstart' ]]
	[[ "$(plan_volume_rm_tokens args)" -eq 2 ]]
	array_contains 'talkbox-proj.onbox' "${args[@]}"
	array_contains 'talkbox-proj.netbox.root' "${args[@]}"
	array_contains '--name=talkbox-proj.netbox' "${args[@]}"
	array_contains 'talkbox-proj.netbox.worktree:/talkbox/target' "${args[@]}"
	plan_has_volume_rm args 'talkbox-proj.netbox.worktree'
	plan_has_volume_rm args 'talkbox-proj.netbox.gitdir'
}

@test "offbox recontain plan commits the netbox source, removes volumes, populates and recreates the container" {
	load_lifecycle_plan
	mkdir -p "$PROJECT/.git"
	stub_volumes 'talkbox-proj.offbox.worktree' 'talkbox-proj.offbox.gitdir'
	local args=()
	plan_offbox_recontain args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS netbox
	[[ "$(plan_subcommands args)" == $'commit\nrm\nvolume\nvolume\nrun\ncreate\nstart' ]]
	[[ "$(plan_volume_rm_tokens args)" -eq 2 ]]
	array_contains 'talkbox-proj.netbox' "${args[@]}"
	array_contains 'talkbox-proj.offbox.root' "${args[@]}"
	array_contains '--name=talkbox-proj.offbox' "${args[@]}"
	array_contains 'talkbox-proj.offbox.worktree:/talkbox/target' "${args[@]}"
	plan_has_volume_rm args 'talkbox-proj.offbox.worktree'
	plan_has_volume_rm args 'talkbox-proj.offbox.gitdir'
}

@test "netbox recontain plan skips the commit when the source is the base image" {
	load_lifecycle_plan
	mkdir -p "$PROJECT/.git"
	stub_volumes 'talkbox-proj.netbox.worktree' 'talkbox-proj.netbox.gitdir'
	local args=()
	plan_netbox_recontain args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS base
	[[ "$(plan_subcommands args)" == $'rm\nvolume\nvolume\nrun\ncreate\nstart' ]]
	array_has_none 'podman commit' "${args[@]}"
	array_contains 'talkbox-proj.netbox.worktree:/talkbox/target' "${args[@]}"
	plan_has_volume_rm args 'talkbox-proj.netbox.gitdir'
}

@test "netbox recontain plan removes the write volumes and populates them when present" {
	load_lifecycle_plan
	mkdir -p "$PROJECT/.git"
	stub_volumes 'talkbox-proj.netbox.worktree' 'talkbox-proj.netbox.gitdir' 'talkbox-proj.netbox.write.talkbox-wdata'
	# shellcheck disable=SC2034 # arrays are consumed by nameref planner parameters
	local -a srcs=('/host/data') dsts=('/talkbox/wdata') args=()
	plan_netbox_recontain args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS srcs dsts PORTS onbox
	[[ "$(plan_subcommands args)" == $'commit\nrm\nvolume\nvolume\nvolume\nrun\nrun\ncreate\nstart' ]]
	[[ "$(plan_volume_rm_tokens args)" -eq 3 ]]
	array_contains 'talkbox-proj.netbox.worktree:/talkbox/target' "${args[@]}"
	array_contains 'talkbox-proj.netbox.write.talkbox-wdata:/talkbox/target' "${args[@]}"
	plan_has_volume_rm args 'talkbox-proj.netbox.write.talkbox-wdata'
}

@test "offbox recontain plan removes the write volumes and populates them when present" {
	load_lifecycle_plan
	mkdir -p "$PROJECT/.git"
	stub_volumes 'talkbox-proj.offbox.worktree' 'talkbox-proj.offbox.gitdir' 'talkbox-proj.offbox.write.talkbox-wdata'
	# shellcheck disable=SC2034 # arrays are consumed by nameref planner parameters
	local -a srcs=('/host/data') dsts=('/talkbox/wdata') args=()
	plan_offbox_recontain args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS srcs dsts PORTS onbox
	[[ "$(plan_subcommands args)" == $'commit\nrm\nvolume\nvolume\nvolume\nrun\nrun\ncreate\nstart' ]]
	[[ "$(plan_volume_rm_tokens args)" -eq 3 ]]
	array_contains 'talkbox-proj.offbox.worktree:/talkbox/target' "${args[@]}"
	array_contains 'talkbox-proj.offbox.write.talkbox-wdata:/talkbox/target' "${args[@]}"
	plan_has_volume_rm args 'talkbox-proj.offbox.write.talkbox-wdata'
}

@test "netbox rebuild plan rebuilds the base image, commits, removes volumes and recreates" {
	load_lifecycle_plan
	mkdir -p "$PROJECT/.git"
	stub_volumes 'talkbox-proj.netbox.worktree' 'talkbox-proj.netbox.gitdir'
	local args=()
	plan_netbox_rebuild args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS onbox
	[[ "$(plan_subcommands args)" == $'build\ncommit\nrm\nvolume\nvolume\nrun\ncreate\nstart' ]]
	[[ "$(plan_volume_rm_tokens args)" -eq 2 ]]
	array_contains 'talkbox/base:latest' "${args[@]}"
	array_contains 'talkbox-proj.netbox.root' "${args[@]}"
	array_contains 'talkbox-proj.netbox.worktree:/talkbox/target' "${args[@]}"
	plan_has_volume_rm args 'talkbox-proj.netbox.gitdir'
}

@test "offbox rebuild plan rebuilds the base image, commits, removes volumes and recreates" {
	load_lifecycle_plan
	mkdir -p "$PROJECT/.git"
	stub_volumes 'talkbox-proj.offbox.worktree' 'talkbox-proj.offbox.gitdir'
	local args=()
	plan_offbox_rebuild args "$PROJECT" yes READ_MOUNTS WRITE_MOUNTS SRCS DSTS PORTS onbox
	[[ "$(plan_subcommands args)" == $'build\ncommit\nrm\nvolume\nvolume\nrun\ncreate\nstart' ]]
	[[ "$(plan_volume_rm_tokens args)" -eq 2 ]]
	array_contains 'talkbox/base:latest' "${args[@]}"
	array_contains 'talkbox-proj.offbox.root' "${args[@]}"
	array_contains 'talkbox-proj.offbox.worktree:/talkbox/target' "${args[@]}"
	plan_has_volume_rm args 'talkbox-proj.offbox.gitdir'
}

@test "netbox rm-container plan removes the container, its root image and named volumes" {
	load_lifecycle_plan
	mkdir -p "$PROJECT/.git"
	stub_volumes 'talkbox-proj.netbox.worktree' 'talkbox-proj.netbox.gitdir'
	local args=()
	plan_netbox_rm_container args "$PROJECT" DSTS
	[[ "$(plan_volume_rm_tokens args)" -eq 2 ]]
	plan_has_volume_rm args 'talkbox-proj.netbox.worktree'
	plan_has_volume_rm args 'talkbox-proj.netbox.gitdir'
	plan_has_subcommand args rm
	plan_has_subcommand args rmi
	array_contains 'talkbox-proj.netbox' "${args[@]}"
	array_contains '--volumes' "${args[@]}"
	array_contains 'talkbox-proj.netbox.root' "${args[@]}"
}

@test "offbox rm-container plan removes the container, its root image and named volumes" {
	load_lifecycle_plan
	mkdir -p "$PROJECT/.git"
	stub_volumes 'talkbox-proj.offbox.worktree' 'talkbox-proj.offbox.gitdir'
	local args=()
	plan_offbox_rm_container args "$PROJECT" DSTS
	[[ "$(plan_volume_rm_tokens args)" -eq 2 ]]
	plan_has_volume_rm args 'talkbox-proj.offbox.worktree'
	plan_has_volume_rm args 'talkbox-proj.offbox.gitdir'
	plan_has_subcommand args rm
	plan_has_subcommand args rmi
	array_contains 'talkbox-proj.offbox' "${args[@]}"
	array_contains '--volumes' "${args[@]}"
	array_contains 'talkbox-proj.offbox.root' "${args[@]}"
}

@test "netbox rm-container plan removes the write volumes when write dests are supplied" {
	load_lifecycle_plan
	mkdir -p "$PROJECT/.git"
	stub_volumes 'talkbox-proj.netbox.worktree' 'talkbox-proj.netbox.gitdir' 'talkbox-proj.netbox.write.talkbox-wdata'
	# shellcheck disable=SC2034 # arrays are consumed by nameref planner parameters
	local -a dsts=('/talkbox/wdata') args=()
	plan_netbox_rm_container args "$PROJECT" dsts
	[[ "$(plan_volume_rm_tokens args)" -eq 3 ]]
	plan_has_volume_rm args 'talkbox-proj.netbox.worktree'
	plan_has_volume_rm args 'talkbox-proj.netbox.gitdir'
	plan_has_volume_rm args 'talkbox-proj.netbox.write.talkbox-wdata'
}

@test "rm-container volume removal is guarded by volume existence" {
	load_lifecycle_plan
	mkdir -p "$PROJECT/.git"
	local args=()
	plan_netbox_rm_container args "$PROJECT" DSTS
	[[ "$(plan_volume_rm_tokens args)" -eq 0 ]]
	plan_has_volume_rm_none args 'talkbox-proj.netbox.worktree'
	plan_has_volume_rm_none args 'talkbox-proj.netbox.gitdir'
	stub_volumes 'talkbox-proj.netbox.worktree'
	args=()
	plan_netbox_rm_container args "$PROJECT" DSTS
	[[ "$(plan_volume_rm_tokens args)" -eq 1 ]]
	plan_has_volume_rm args 'talkbox-proj.netbox.worktree'
	plan_has_volume_rm_none args 'talkbox-proj.netbox.gitdir'
}

@test "plan_volume_rm emits podman volume rm -f only when the volume exists" {
	load_lifecycle_plan
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

@test "prune_external_image_containers queries external containers by ancestor and force-removes each returned ID" {
	load_lifecycle_plan
	local shimdir log
	shimdir="$BATS_TEST_TMPDIR/shim"
	log="$BATS_TEST_TMPDIR/podman.log"
	mkdir -p "$shimdir"
	cat >"$shimdir/podman" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>'$log'
if [[ "\$*" == *'ps -a --external'* ]]; then
	printf 'ext1\n'
	printf 'ext2\n'
fi
exit 0
EOF
	chmod +x "$shimdir/podman"
	PATH="$shimdir:$PATH" run prune_external_image_containers "$(base_image_name)"
	[[ "$status" -eq 0 ]]
	[[ "$(grep -c -- '--external --filter ancestor=talkbox/base:latest' "$log")" -ge 1 ]]
	[[ "$(grep -c '^rm -f ext1$' "$log")" -eq 1 ]]
	[[ "$(grep -c '^rm -f ext2$' "$log")" -eq 1 ]]
}

@test "prune_external_image_containers silently succeeds when no external working containers match" {
	load_lifecycle_plan
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
	PATH="$shimdir:$PATH" run prune_external_image_containers "$(base_image_name)"
	[[ "$status" -eq 0 ]]
	[[ "$(grep -c -- '--external --filter ancestor=talkbox/base:latest' "$log")" -ge 1 ]]
	[[ "$(grep -c '^rm ' "$log" || true)" -eq 0 ]]
}

@test "run_rm_image prunes external working containers before removing the base image" {
	load_lifecycle_plan
	local shimdir log ctr
	shimdir="$BATS_TEST_TMPDIR/shim"
	log="$BATS_TEST_TMPDIR/podman.log"
	mkdir -p "$shimdir"
	ctr="$(onbox_container_name "$PROJECT")"
	cat >"$shimdir/podman" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>'$log'
if [[ "\$*" == *'ps -a --external'* ]]; then
	printf 'ext1\n'
fi
if [[ "\$*" == *"container exists $ctr"* ]]; then
	exit 1
fi
exit 0
EOF
	chmod +x "$shimdir/podman"
	PATH="$shimdir:$PATH" run run_rm_image "$PROJECT"
	[[ "$status" -eq 0 ]]
	local ext_line rm_line rmi_line
	ext_line="$(grep -n -- '--external --filter ancestor=talkbox/base:latest' "$log" | head -n 1 | cut -d: -f1)"
	rm_line="$(grep -n '^rm -f ext1$' "$log" | head -n 1 | cut -d: -f1)"
	rmi_line="$(grep -n '^rmi talkbox/base:latest$' "$log" | head -n 1 | cut -d: -f1)"
	[[ -n "$ext_line" && -n "$rm_line" && -n "$rmi_line" ]]
	[[ "$ext_line" -lt "$rm_line" ]]
	[[ "$rm_line" -lt "$rmi_line" ]]
}

@test "run_netbox_rm_image prunes external working containers before removing the base image" {
	load_lifecycle_plan
	local shimdir log ctr
	shimdir="$BATS_TEST_TMPDIR/shim"
	log="$BATS_TEST_TMPDIR/podman.log"
	mkdir -p "$shimdir"
	ctr="$(netbox_container_name "$PROJECT")"
	cat >"$shimdir/podman" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>'$log'
if [[ "\$*" == *'ps -a --external'* ]]; then
	printf 'ext1\n'
fi
if [[ "\$*" == *"container exists $ctr"* ]]; then
	exit 1
fi
exit 0
EOF
	chmod +x "$shimdir/podman"
	PATH="$shimdir:$PATH" run run_netbox_rm_image "$PROJECT"
	[[ "$status" -eq 0 ]]
	local ext_line rm_line rmi_line
	ext_line="$(grep -n -- '--external --filter ancestor=talkbox/base:latest' "$log" | head -n 1 | cut -d: -f1)"
	rm_line="$(grep -n '^rm -f ext1$' "$log" | head -n 1 | cut -d: -f1)"
	rmi_line="$(grep -n '^rmi talkbox/base:latest$' "$log" | head -n 1 | cut -d: -f1)"
	[[ -n "$ext_line" && -n "$rm_line" && -n "$rmi_line" ]]
	[[ "$ext_line" -lt "$rm_line" ]]
	[[ "$rm_line" -lt "$rmi_line" ]]
}

@test "run_offbox_rm_image prunes external working containers before removing the base image" {
	load_lifecycle_plan
	local shimdir log ctr
	shimdir="$BATS_TEST_TMPDIR/shim"
	log="$BATS_TEST_TMPDIR/podman.log"
	mkdir -p "$shimdir"
	ctr="$(offbox_container_name "$PROJECT")"
	cat >"$shimdir/podman" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>'$log'
if [[ "\$*" == *'ps -a --external'* ]]; then
	printf 'ext1\n'
fi
if [[ "\$*" == *"container exists $ctr"* ]]; then
	exit 1
fi
exit 0
EOF
	chmod +x "$shimdir/podman"
	PATH="$shimdir:$PATH" run run_offbox_rm_image "$PROJECT"
	[[ "$status" -eq 0 ]]
	local ext_line rm_line rmi_line
	ext_line="$(grep -n -- '--external --filter ancestor=talkbox/base:latest' "$log" | head -n 1 | cut -d: -f1)"
	rm_line="$(grep -n '^rm -f ext1$' "$log" | head -n 1 | cut -d: -f1)"
	rmi_line="$(grep -n '^rmi talkbox/base:latest$' "$log" | head -n 1 | cut -d: -f1)"
	[[ -n "$ext_line" && -n "$rm_line" && -n "$rmi_line" ]]
	[[ "$ext_line" -lt "$rm_line" ]]
	[[ "$rm_line" -lt "$rmi_line" ]]
}
