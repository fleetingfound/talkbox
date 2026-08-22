load helpers

load_onbox_plan() {
	load_lib naming.sh
	load_lib containers.sh
}

plan_line() {
	local re="$1"
	local line
	while IFS= read -r line; do
		if [[ "$line" =~ $re ]]; then
			return 0
		fi
	done <<<"$output"
	return 1
}

last_line() {
	tail -n 1 <<<"$output"
}

@test "onbox plan sets the working directory to /working/<project-base>" {
	load_onbox_plan
	run plan_onbox '/tmp/talkbox-proj' '' yes
	[[ "$status" -eq 0 ]]
	plan_line '^--workdir=/working/talkbox-proj$'
}

@test "onbox plan maps the host user to container uid/gid 1000" {
	load_onbox_plan
	run plan_onbox '/tmp/talkbox-proj' '' yes
	[[ "$status" -eq 0 ]]
	plan_line '^--userns=keep-id:uid=1000,gid=1000$'
}

@test "onbox plan uses rootless pasta networking without host-port forwarding" {
	load_onbox_plan
	run plan_onbox '/tmp/talkbox-proj' '' yes
	[[ "$status" -eq 0 ]]
	plan_line '^--network=pasta$'
	[[ "$output" != *'-T,'* ]]
}

@test "onbox plan drops NET_ADMIN and NET_RAW capabilities" {
	load_onbox_plan
	run plan_onbox '/tmp/talkbox-proj' '' yes
	[[ "$status" -eq 0 ]]
	plan_line '^--cap-drop=NET_ADMIN$'
	plan_line '^--cap-drop=NET_RAW$'
}

@test "onbox plan bind-mounts the host worktree read-write" {
	load_onbox_plan
	run plan_onbox '/tmp/talkbox-proj' '' yes
	[[ "$status" -eq 0 ]]
	plan_line '^-v /tmp/talkbox-proj:/working/talkbox-proj(:rw)?$'
	if plan_line '^-v /tmp/talkbox-proj:/working/talkbox-proj:ro$'; then
		return 1
	fi
}

@test "onbox plan bind-mounts global dotfiles read-only" {
	load_onbox_plan
	run plan_onbox '/tmp/talkbox-proj' '' yes
	[[ "$status" -eq 0 ]]
	plan_line '^.*/defaults/dotfiles:/talkbox/dotfiles.global:ro$'
}

@test "onbox plan bind-mounts project dotfiles read-only" {
	load_onbox_plan
	run plan_onbox '/tmp/talkbox-proj' '' yes
	[[ "$status" -eq 0 ]]
	plan_line '^-v /tmp/talkbox-proj/.dotfiles:/talkbox/dotfiles.project:ro$'
}

@test "onbox plan runs the shared base image" {
	load_onbox_plan
	local img
	img="$(base_image_name)"
	run plan_onbox '/tmp/talkbox-proj' '' yes
	[[ "$status" -eq 0 ]]
	plan_line "^$img$"
}

@test "onbox interactive plan allocates a terminal" {
	load_onbox_plan
	run plan_onbox '/tmp/talkbox-proj' '' yes
	[[ "$status" -eq 0 ]]
	if plan_line '^--interactive$|^-it$|^-i$|^--tty$|^-t$'; then
		:
	else
		return 1
	fi
}

@test "onbox noninteractive plan does not allocate a terminal" {
	load_onbox_plan
	run plan_onbox '/tmp/talkbox-proj' 'pwd' no
	[[ "$status" -eq 0 ]]
	if plan_line '^--interactive$|^-it$|^-i$|^--tty$|^-t$'; then
		return 1
	fi
}

@test "onbox noninteractive plan appends the command" {
	load_onbox_plan
	run plan_onbox '/tmp/talkbox-proj' 'pwd' no
	[[ "$status" -eq 0 ]]
	[[ "$(last_line)" == 'pwd' ]]
}
