# shellcheck shell=bash

TALKBOX_ROOT="${TALKBOX_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$TALKBOX_ROOT/lib/common.sh"

print_talkbox_help() {
	cat <<'EOF'
usage: onbox|netbox|offbox [options] [fetch|merge|sync [<branchname>]]

containers:
  onbox    internet access, edits the host project directly
  netbox   internet access, no host edits
  offbox   no internet access, no host edits

options:
  -c, --command <command>     run <command> in the container
  --interactive               run the command interactively (default)
  --noninteractive            run the command noninteractively
  --read <source>[:<dest>]    extra read-only mount (repeatable)
  --write <source>[:<dest>]   extra read-write mount (repeatable)
  --port <port>               extra host port to reach (repeatable)
  --deny-ip <address>         blocked IP or CIDR range (repeatable, onbox/netbox)
  --allow-ip <address>        allowed IP or CIDR range overriding denials (repeatable)
  --fresh                     skip default root filesystem and volume inheritance
  --inherit <container>       inherit from onbox, netbox or offbox
  --gpu                       expose host Nvidia GPUs
  --all                       fetch, merge or sync every branch
  --recontain                 recreate the container and its volumes
  --rebuild                   rebuild the image and recreate the container
  --rm-container              remove the container and its volumes
  --rm-image                  remove the image
  -h, --help                  show this help

git subcommands:
  fetch [<branchname>]        fetch container git history to the host
  merge [<branchname>]        apply container changes to the host repository
  sync [<branchname>]         apply host changes to the container repository
EOF
}

# shellcheck disable=SC2034
parse_talkbox_options() {
	TALKBOX_COMMAND=""
	TALKBOX_INTERACTIVE="yes"
	TALKBOX_VERB=""
	TALKBOX_ALL="no"
	TALKBOX_BRANCH=""
	TALKBOX_READ=()
	TALKBOX_WRITE=()
	TALKBOX_PORT=()
	TALKBOX_DENY_IP=()
	TALKBOX_ALLOW_IP=()
	TALKBOX_FRESH="no"
	TALKBOX_INHERIT=""
	TALKBOX_GPU="no"
	local after_command=no
	while [[ $# -gt 0 ]]; do
		case "$1" in
		-h | --help)
			print_talkbox_help
			exit 0
			;;
		-c | --command)
			after_command=yes
			;;
		--interactive)
			TALKBOX_INTERACTIVE="yes"
			;;
		--noninteractive)
			TALKBOX_INTERACTIVE="no"
			;;
		--read)
			shift
			[[ $# -gt 0 ]] || die "--read requires a value" 2
			TALKBOX_READ+=("$1")
			;;
		--write)
			shift
			[[ $# -gt 0 ]] || die "--write requires a value" 2
			TALKBOX_WRITE+=("$1")
			;;
		--port)
			shift
			[[ $# -gt 0 ]] || die "--port requires a value" 2
			TALKBOX_PORT+=("$1")
			;;
		--deny-ip)
			shift
			[[ $# -gt 0 ]] || die "--deny-ip requires a value" 2
			TALKBOX_DENY_IP+=("$1")
			;;
		--allow-ip)
			shift
			[[ $# -gt 0 ]] || die "--allow-ip requires a value" 2
			TALKBOX_ALLOW_IP+=("$1")
			;;
		--fresh)
			TALKBOX_FRESH="yes"
			;;
		--inherit)
			shift
			[[ $# -gt 0 ]] || die "--inherit requires a value" 2
			TALKBOX_INHERIT="$1"
			;;
		--all)
			TALKBOX_ALL="yes"
			;;
		--gpu)
			TALKBOX_GPU="yes"
			;;
		fetch | merge | sync)
			if [[ "$after_command" == yes ]]; then
				TALKBOX_COMMAND="$1"
			else
				TALKBOX_VERB="$1"
			fi
			;;
		--recontain)
			TALKBOX_VERB="recontain"
			;;
		--rebuild)
			TALKBOX_VERB="rebuild"
			;;
		--rm-container)
			TALKBOX_VERB="rm-container"
			;;
		--rm-image)
			TALKBOX_VERB="rm-image"
			;;
		-*)
			die "unknown option: $1" 2
			;;
		*)
			if [[ "$after_command" == yes ]]; then
				TALKBOX_COMMAND="$1"
			elif [[ "$TALKBOX_VERB" == merge || "$TALKBOX_VERB" == sync ]]; then
				TALKBOX_BRANCH="$1"
			else
				TALKBOX_COMMAND="$1"
			fi
			;;
		esac
		shift
	done
}
