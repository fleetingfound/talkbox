load helpers

setup() {
	ONBOX_COMMAND=""
	ONBOX_INTERACTIVE=""
	ONBOX_VERB=""
	ONBOX_READ=()
	ONBOX_WRITE=()
	ONBOX_PORT=()
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

@test "unknown options are rejected with exit code 2 and a message" {
	load_lib options.sh
	run parse_onbox_options --bogus
	[[ "$status" -eq 2 ]]
	[[ "$output" == *"talkbox: unknown option: --bogus"* ]]
}

@test "--read records repeatable read specs" {
	load_lib options.sh
	parse_onbox_options --read '/a:/b' --read '/c'
	[[ "${#ONBOX_READ[@]}" -eq 2 ]]
	[[ "${ONBOX_READ[0]}" == '/a:/b' ]]
	[[ "${ONBOX_READ[1]}" == '/c' ]]
}

@test "--write records repeatable write specs" {
	load_lib options.sh
	parse_onbox_options --write '/w1' --write '/w2:/x'
	[[ "${#ONBOX_WRITE[@]}" -eq 2 ]]
	[[ "${ONBOX_WRITE[0]}" == '/w1' ]]
	[[ "${ONBOX_WRITE[1]}" == '/w2:/x' ]]
}

@test "--port records repeatable ports" {
	load_lib options.sh
	parse_onbox_options --port 8080 --port 9090
	[[ "${#ONBOX_PORT[@]}" -eq 2 ]]
	[[ "${ONBOX_PORT[0]}" == '8080' ]]
	[[ "${ONBOX_PORT[1]}" == '9090' ]]
}

@test "lifecycle verbs are recognised" {
	load_lib options.sh
	parse_onbox_options --recontain
	[[ "$ONBOX_VERB" == recontain ]]
	parse_onbox_options --rebuild
	[[ "$ONBOX_VERB" == rebuild ]]
	parse_onbox_options --rm-container
	[[ "$ONBOX_VERB" == 'rm-container' ]]
	parse_onbox_options --rm-image
	[[ "$ONBOX_VERB" == 'rm-image' ]]
}

@test "the default verb is empty" {
	load_lib options.sh
	ONBOX_VERB="sentinel"
	parse_onbox_options
	[[ -z "$ONBOX_VERB" ]]
}

@test "--read value is not treated as the command" {
	load_lib options.sh
	parse_onbox_options --read '/a:/b' -c 'pwd'
	[[ "${#ONBOX_READ[@]}" -eq 1 ]]
	[[ "${ONBOX_READ[0]}" == '/a:/b' ]]
	[[ "$ONBOX_COMMAND" == 'pwd' ]]
}
