# shellcheck disable=SC2030,SC2031 # bats runs setup/test/teardown in one subshell; cross-test record reads are intentional
load helpers

setup() {
	TALKBOX_COMMAND=""
	TALKBOX_INTERACTIVE=""
	TALKBOX_VERB=""
	TALKBOX_READ=()
	TALKBOX_WRITE=()
	TALKBOX_PORT=()
	TALKBOX_FRESH=""
	TALKBOX_INHERIT=""
	TALKBOX_GPU=""
	TALKBOX_ALL=""
	TALKBOX_BRANCH=""
}

@test "onbox defaults to an interactive shell with no command" {
	load_lib options.sh
	parse_talkbox_options
	[[ -z "$TALKBOX_COMMAND" ]]
	[[ "$TALKBOX_INTERACTIVE" == yes ]]
}

@test "-c <command> sets the command and keeps the interactive default" {
	load_lib options.sh
	parse_talkbox_options -c 'echo hello'
	[[ "$TALKBOX_COMMAND" == 'echo hello' ]]
	[[ "$TALKBOX_INTERACTIVE" == yes ]]
}

@test "--command <command> sets the command" {
	load_lib options.sh
	parse_talkbox_options --command 'pwd'
	[[ "$TALKBOX_COMMAND" == 'pwd' ]]
	[[ "$TALKBOX_INTERACTIVE" == yes ]]
}

@test "-c --interactive <command> runs the command interactively" {
	load_lib options.sh
	parse_talkbox_options -c --interactive 'ls -la'
	[[ "$TALKBOX_COMMAND" == 'ls -la' ]]
	[[ "$TALKBOX_INTERACTIVE" == yes ]]
}

@test "-c --noninteractive <command> runs the command noninteractively" {
	load_lib options.sh
	parse_talkbox_options -c --noninteractive 'make test-unit'
	[[ "$TALKBOX_COMMAND" == 'make test-unit' ]]
	[[ "$TALKBOX_INTERACTIVE" == no ]]
}

@test "--noninteractive is recognised before the command" {
	load_lib options.sh
	parse_talkbox_options --noninteractive -c 'true'
	[[ "$TALKBOX_COMMAND" == 'true' ]]
	[[ "$TALKBOX_INTERACTIVE" == no ]]
}

@test "unknown options are rejected with exit code 2 and a message" {
	load_lib options.sh
	run parse_talkbox_options --bogus
	[[ "$status" -eq 2 ]]
	[[ "$output" == *"talkbox: unknown option: --bogus"* ]]
}

@test "--read records repeatable read specs" {
	load_lib options.sh
	parse_talkbox_options --read '/a:/b' --read '/c'
	[[ "${#TALKBOX_READ[@]}" -eq 2 ]]
	[[ "${TALKBOX_READ[0]}" == '/a:/b' ]]
	[[ "${TALKBOX_READ[1]}" == '/c' ]]
}

@test "--write records repeatable write specs" {
	load_lib options.sh
	parse_talkbox_options --write '/w1' --write '/w2:/x'
	[[ "${#TALKBOX_WRITE[@]}" -eq 2 ]]
	[[ "${TALKBOX_WRITE[0]}" == '/w1' ]]
	[[ "${TALKBOX_WRITE[1]}" == '/w2:/x' ]]
}

@test "--port records repeatable ports" {
	load_lib options.sh
	parse_talkbox_options --port 8080 --port 9090
	[[ "${#TALKBOX_PORT[@]}" -eq 2 ]]
	[[ "${TALKBOX_PORT[0]}" == '8080' ]]
	[[ "${TALKBOX_PORT[1]}" == '9090' ]]
}

@test "lifecycle verbs are recognised" {
	load_lib options.sh
	parse_talkbox_options --recontain
	[[ "$TALKBOX_VERB" == recontain ]]
	parse_talkbox_options --rebuild
	[[ "$TALKBOX_VERB" == rebuild ]]
	parse_talkbox_options --rm-container
	[[ "$TALKBOX_VERB" == 'rm-container' ]]
	parse_talkbox_options --rm-image
	[[ "$TALKBOX_VERB" == 'rm-image' ]]
}

@test "the default verb is empty" {
	load_lib options.sh
	TALKBOX_VERB="sentinel"
	parse_talkbox_options
	[[ -z "$TALKBOX_VERB" ]]
}

@test "--read value is not treated as the command" {
	load_lib options.sh
	parse_talkbox_options --read '/a:/b' -c 'pwd'
	[[ "${#TALKBOX_READ[@]}" -eq 1 ]]
	[[ "${TALKBOX_READ[0]}" == '/a:/b' ]]
	[[ "$TALKBOX_COMMAND" == 'pwd' ]]
}

@test "--fresh is recognised" {
	load_lib options.sh
	parse_talkbox_options --fresh
	[[ "$TALKBOX_FRESH" == yes ]]
}

@test "--inherit <source> records the explicit inheritance source" {
	load_lib options.sh
	parse_talkbox_options --inherit offbox
	[[ "$TALKBOX_INHERIT" == offbox ]]
	parse_talkbox_options --inherit netbox
	[[ "$TALKBOX_INHERIT" == netbox ]]
}

@test "the default is not fresh and has no explicit inherit source" {
	load_lib options.sh
	parse_talkbox_options
	[[ "$TALKBOX_FRESH" == no ]]
	[[ -z "$TALKBOX_INHERIT" ]]
}

@test "--fresh and --inherit are not treated as the command" {
	load_lib options.sh
	parse_talkbox_options --fresh --inherit onbox -c 'pwd'
	[[ "$TALKBOX_FRESH" == yes ]]
	[[ "$TALKBOX_INHERIT" == onbox ]]
	[[ "$TALKBOX_COMMAND" == 'pwd' ]]
}

@test "--gpu is recognised" {
	load_lib options.sh
	parse_talkbox_options --gpu
	[[ "$TALKBOX_GPU" == yes ]]
}

@test "--gpu defaults to no" {
	load_lib options.sh
	parse_talkbox_options
	[[ "$TALKBOX_GPU" == no ]]
}

@test "--gpu is not treated as the command" {
	load_lib options.sh
	parse_talkbox_options --gpu -c 'pwd'
	[[ "$TALKBOX_GPU" == yes ]]
	[[ "$TALKBOX_COMMAND" == 'pwd' ]]
}

@test "onbox fetch is parsed as the fetch verb while -c fetch remains a command" {
	load_lib options.sh
	parse_talkbox_options fetch
	[[ "$TALKBOX_VERB" == fetch ]]
	[[ -z "$TALKBOX_COMMAND" ]]
	parse_talkbox_options -c fetch
	[[ "$TALKBOX_COMMAND" == fetch ]]
	[[ -z "$TALKBOX_VERB" ]]
}

@test "onbox fetch --all sets the fetch verb and the --all flag" {
	load_lib options.sh
	parse_talkbox_options fetch --all
	[[ "$TALKBOX_VERB" == fetch ]]
	[[ "$TALKBOX_ALL" == yes ]]
}

@test "the --all flag defaults to no" {
	load_lib options.sh
	parse_talkbox_options
	[[ "$TALKBOX_ALL" == no ]]
}

@test "onbox merge is parsed as the merge verb while -c merge remains a command" {
	load_lib options.sh
	parse_talkbox_options merge
	[[ "$TALKBOX_VERB" == merge ]]
	[[ -z "$TALKBOX_COMMAND" ]]
	parse_talkbox_options -c merge
	[[ "$TALKBOX_COMMAND" == merge ]]
	[[ -z "$TALKBOX_VERB" ]]
}

@test "onbox merge <branchname> records the merge verb and the branch positional" {
	load_lib options.sh
	parse_talkbox_options merge mybranch
	[[ "$TALKBOX_VERB" == merge ]]
	[[ "$TALKBOX_BRANCH" == mybranch ]]
	[[ -z "$TALKBOX_COMMAND" ]]
}

@test "onbox merge --all sets the merge verb and the --all flag" {
	load_lib options.sh
	parse_talkbox_options merge --all
	[[ "$TALKBOX_VERB" == merge ]]
	[[ "$TALKBOX_ALL" == yes ]]
	[[ -z "$TALKBOX_COMMAND" ]]
}

@test "onbox sync is parsed as the sync verb while -c sync remains a command" {
	load_lib options.sh
	parse_talkbox_options sync
	[[ "$TALKBOX_VERB" == sync ]]
	[[ -z "$TALKBOX_COMMAND" ]]
	parse_talkbox_options -c sync
	[[ "$TALKBOX_COMMAND" == sync ]]
	[[ -z "$TALKBOX_VERB" ]]
}

@test "onbox sync <branchname> --all records the sync verb, branch and --all flag" {
	load_lib options.sh
	parse_talkbox_options sync mybranch --all
	[[ "$TALKBOX_VERB" == sync ]]
	[[ "$TALKBOX_BRANCH" == mybranch ]]
	[[ "$TALKBOX_ALL" == yes ]]
	[[ -z "$TALKBOX_COMMAND" ]]
}
