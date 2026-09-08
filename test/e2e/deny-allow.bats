load helpers

setup() {
	# nft lives in /usr/sbin on Debian derivatives, which is not on the
	# default user PATH; the enforcement under test invokes `nft` via
	# `podman unshare nsenter`, so make it resolvable.
	export PATH="/usr/sbin:/sbin:$PATH"
	PROJECT="$(mk_project)"
	TALKBOX="$(mk_talkbox)"
	PROJECT_SLUG="$(project_slug_e2e "$PROJECT")"
	HOST_SRV_PID=""
}

teardown() {
	if [[ -n "$HOST_SRV_PID" ]]; then
		kill "$HOST_SRV_PID" 2>/dev/null || true
	fi
	teardown_talkbox "$PROJECT_SLUG"
	rm -rf "$PROJECT" "$TALKBOX"
}

require_nft_and_internet() {
	command -v nft >/dev/null 2>&1 || skip "nft is required for the deny/allow enforcement e2e tests"
	if ! curl -fsS --max-time 10 https://example.com >/dev/null 2>&1; then
		skip "host has no internet connectivity; skipping the deny/allow e2e test"
	fi
}

@test "onbox --deny-ip blocks a denied address while a non-denied address remains reachable" {
	require_nft_and_internet
	command -v python3 >/dev/null 2>&1 || skip "python3 is required for the deny/allow e2e test"
	local www port srv n
	www="$(mktemp -d)"
	printf 'deny-marker\n' >"$www/marker"
	start_host_http_server "$www" srv port
	HOST_SRV_PID=$srv
	for ((n = 0; n < 20; n++)); do
		if curl -fsS --max-time 2 "http://127.0.0.1:$port/marker" >/dev/null 2>&1; then
			break
		fi
		sleep 0.5
	done
	# shellcheck disable=SC2016 # $0/$1/$2 expand inside the wrapped bash -c
	run run_talkbox "$PROJECT" "$TALKBOX" onbox --deny-ip 1.1.1.1 --port "$port" -c --noninteractive \
		'curl -sS --max-time 8 -o /dev/null http://1.1.1.1/ 2>/dev/null && echo DENIED-REACHABLE || echo DENIED-BLOCKED
		curl -fsS --max-time 8 "http://127.0.0.1:'"$port"'/marker" && echo ALLOWED-REACHABLE'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'DENIED-BLOCKED'* ]]
	[[ "$output" == *'ALLOWED-REACHABLE'* ]]
	kill "$srv" 2>/dev/null || true
	HOST_SRV_PID=""
	rm -rf "$www"
}

@test "netbox --deny-ip blocks a denied address while a non-denied address remains reachable" {
	require_nft_and_internet
	command -v python3 >/dev/null 2>&1 || skip "python3 is required for the deny/allow e2e test"
	local www port srv n
	www="$(mktemp -d)"
	printf 'deny-marker\n' >"$www/marker"
	start_host_http_server "$www" srv port
	HOST_SRV_PID=$srv
	for ((n = 0; n < 20; n++)); do
		if curl -fsS --max-time 2 "http://127.0.0.1:$port/marker" >/dev/null 2>&1; then
			break
		fi
		sleep 0.5
	done
	# shellcheck disable=SC2016 # $0/$1/$2 expand inside the wrapped bash -c
	run run_talkbox "$PROJECT" "$TALKBOX" netbox --deny-ip 1.1.1.1 --port "$port" -c --noninteractive \
		'curl -sS --max-time 8 -o /dev/null http://1.1.1.1/ 2>/dev/null && echo DENIED-REACHABLE || echo DENIED-BLOCKED
		curl -fsS --max-time 8 "http://127.0.0.1:'"$port"'/marker" && echo ALLOWED-REACHABLE'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'DENIED-BLOCKED'* ]]
	[[ "$output" == *'ALLOWED-REACHABLE'* ]]
	kill "$srv" 2>/dev/null || true
	HOST_SRV_PID=""
	rm -rf "$www"
}

@test "onbox runs the nft installer for a non-empty deny set; offbox and an allow-emptied set do not" {
	command -v nft >/dev/null 2>&1 || skip "nft is required for the deny/allow enforcement e2e tests"
	local shimdir log real
	shimdir="$BATS_TEST_TMPDIR/shim"
	log="$BATS_TEST_TMPDIR/podman.log"
	mkdir -p "$shimdir"
	real="$(command -v podman)"
	cat >"$shimdir/podman" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>'$log'
exec '$real' "\$@"
EOF
	chmod +x "$shimdir/podman"
	# shellcheck disable=SC2016 # $0/$1/$2 expand inside the wrapped bash -c
	run sdrun bash -c 'cd "$1" && PATH="$2:$PATH" "$0/talkbox.sh" onbox --deny-ip 1.1.1.1 -c --noninteractive true' "$TALKBOX" "$PROJECT" "$shimdir"
	[[ "$status" -eq 0 ]]
	[[ "$(grep -c 'nsenter.*nft' "$log" 2>/dev/null || true)" -ge 1 ]]
	: >"$log"
	# shellcheck disable=SC2016 # $0/$1/$2 expand inside the wrapped bash -c
	run sdrun bash -c 'cd "$1" && PATH="$2:$PATH" "$0/talkbox.sh" onbox --deny-ip 1.1.1.1 --allow-ip 1.1.1.1 -c --noninteractive true' "$TALKBOX" "$PROJECT" "$shimdir"
	[[ "$status" -eq 0 ]]
	[[ "$(grep -c 'nsenter.*nft' "$log" 2>/dev/null || true)" -eq 0 ]]
	: >"$log"
	# shellcheck disable=SC2016 # $0/$1/$2 expand inside the wrapped bash -c
	run sdrun bash -c 'cd "$1" && PATH="$2:$PATH" "$0/talkbox.sh" offbox --deny-ip 1.1.1.1 -c --noninteractive true' "$TALKBOX" "$PROJECT" "$shimdir"
	[[ "$status" -eq 0 ]]
	[[ "$(grep -c 'nsenter.*nft' "$log" 2>/dev/null || true)" -eq 0 ]]
}

@test "a deny entry overridden by --allow-ip remains reachable" {
	require_nft_and_internet
	# shellcheck disable=SC2016 # $0/$1/$2 expand inside the wrapped bash -c
	run run_talkbox "$PROJECT" "$TALKBOX" onbox --deny-ip 1.1.1.1 -c --noninteractive \
		'curl -sS --max-time 8 -o /dev/null http://1.1.1.1/ 2>/dev/null && echo DENY-REACHABLE || echo DENY-BLOCKED'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'DENY-BLOCKED'* ]]
	# shellcheck disable=SC2016 # $0/$1/$2 expand inside the wrapped bash -c
	run run_talkbox "$PROJECT" "$TALKBOX" onbox --deny-ip 1.1.1.1 --allow-ip 1.1.1.1 -c --noninteractive \
		'curl -sS --max-time 8 -o /dev/null http://1.1.1.1/ 2>/dev/null && echo ALLOW-REACHABLE || echo ALLOW-BLOCKED'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'ALLOW-REACHABLE'* ]]
}
