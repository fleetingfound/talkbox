load helpers

@test "bashrc replaces the hostname in PS1 with the talkbox project slug and container type" {
	local bashrc="$PROJECT_ROOT/defaults/dotfiles/.bashrc"
	run bash --noprofile --norc -c \
		'export TERM=xterm TALKBOX_PROJECT_SLUG=my-proj TALKBOX_CONTAINER_TYPE=onbox
		 source "$1"
		 printf "%s" "$PS1"' \
		_ "$bashrc"
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'@my-proj.onbox'* ]]
	[[ "$output" != *'\h'* ]]
}
