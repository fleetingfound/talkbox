load helpers

setup() {
	ONBOX_COMMAND=""
	ONBOX_INTERACTIVE=""
}

@test "onbox defaults to an interactive shell with no command" {
	load_lib options.sh
	parse_onbox_options
	[[ -z "$ONBOX_COMMAND" ]]
	[[ "$ONBOX_INTERACTIVE" == yes ]]
}

@test "-c <command> sets the command and keeps the interactive default" {
	load_lib options.sh
	parse_onbox_options -c 'echo hello'
	[[ "$ONBOX_COMMAND" == 'echo hello' ]]
	[[ "$ONBOX_INTERACTIVE" == yes ]]
}

@test "--command <command> sets the command" {
	load_lib options.sh
	parse_onbox_options --command 'pwd'
	[[ "$ONBOX_COMMAND" == 'pwd' ]]
	[[ "$ONBOX_INTERACTIVE" == yes ]]
}

@test "-c --interactive <command> runs the command interactively" {
	load_lib options.sh
	parse_onbox_options -c --interactive 'ls -la'
	[[ "$ONBOX_COMMAND" == 'ls -la' ]]
	[[ "$ONBOX_INTERACTIVE" == yes ]]
}

@test "-c --noninteractive <command> runs the command noninteractively" {
	load_lib options.sh
	parse_onbox_options -c --noninteractive 'make test-unit'
	[[ "$ONBOX_COMMAND" == 'make test-unit' ]]
	[[ "$ONBOX_INTERACTIVE" == no ]]
}

@test "--noninteractive is recognised before the command" {
	load_lib options.sh
	parse_onbox_options --noninteractive -c 'true'
	[[ "$ONBOX_COMMAND" == 'true' ]]
	[[ "$ONBOX_INTERACTIVE" == no ]]
}
