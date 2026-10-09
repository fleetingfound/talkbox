# shellcheck shell=bash

container_config() {
	local field="$1" container="$2"
	case "$field" in
	pasta_suffix)
		case "$container" in
		onbox | netbox) printf '%s\n' '--dns-forward,169.254.1.1,--map-guest-addr,none' ;;
		offbox) printf '%s\n' '-i,lo,-I,talkbox0' ;;
		esac
		;;
	nft_enforce)
		case "$container" in
		onbox | netbox) printf 'yes\n' ;;
		offbox) printf 'no\n' ;;
		esac
		;;
	write_style)
		case "$container" in
		onbox) printf 'bind\n' ;;
		netbox | offbox) printf 'volume\n' ;;
		esac
		;;
	named_worktree_volume)
		case "$container" in
		onbox) printf 'no\n' ;;
		netbox | offbox) printf 'yes\n' ;;
		esac
		;;
	root_image)
		case "$container" in
		onbox) printf 'no\n' ;;
		netbox | offbox) printf 'yes\n' ;;
		esac
		;;
	populate_policy)
		case "$container" in
		onbox) printf 'none\n' ;;
		netbox) printf 'host\n' ;;
		offbox) printf 'source-else-host\n' ;;
		esac
		;;
	default_parents)
		case "$container" in
		netbox) printf 'onbox\n' ;;
		offbox) printf 'netbox onbox\n' ;;
		esac
		;;
	esac
}
