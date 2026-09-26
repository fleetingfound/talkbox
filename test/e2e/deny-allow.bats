load helpers

setup() {
	# nft lives in /usr/sbin on Debian derivatives, which is not on the
	# default user PATH; the enforcement under test invokes `nft` via
	# `podman unshare nsenter`, so make it resolvable.
	export PATH="/usr/sbin:/sbin:$PATH"
	PROJECT="$(mk_project)"
	TALKBOX="$(mk_talkbox)"
	ensure_base_image_e2e "$TALKBOX"
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

require_nft_ipv6() {
	command -v nft >/dev/null 2>&1 || skip "nft is required for the deny/allow enforcement e2e tests"
	command -v python3 >/dev/null 2>&1 || skip "python3 is required for the IPv6 deny/allow e2e test"
	# pasta enables IPv6 (and only then binds forwarded ports on the container's
	# ::1) when the host's outbound interface has a global IPv6 address, so a
	# bind-only check of ::1 is not sufficient to run these tests.
	if [[ -z "$(ip -6 addr show scope global 2>/dev/null)" ]]; then
		skip "host has no global IPv6 address; skipping the IPv6 deny/allow e2e test"
	fi
	if ! python3 -c 'import socket; s = socket.socket(socket.AF_INET6); s.bind(("::1", 0))' >/dev/null 2>&1; then
		skip "host has no IPv6 loopback connectivity; skipping the IPv6 deny/allow e2e test"
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
	[[ "$output" != *'talkbox:'* ]]
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
	[[ "$output" != *'talkbox:'* ]]
	kill "$srv" 2>/dev/null || true
	HOST_SRV_PID=""
	rm -rf "$www"
}

@test "onbox runs the nft installer for a non-empty deny set, also when allow entries are present; offbox does not" {
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
	# An allow entry no longer empties the deny set: the deny set stays raw,
	# so the installer must still run.
	# shellcheck disable=SC2016 # $0/$1/$2 expand inside the wrapped bash -c
	run sdrun bash -c 'cd "$1" && PATH="$2:$PATH" "$0/talkbox.sh" onbox --deny-ip 1.1.1.1 --allow-ip 1.1.1.1 -c --noninteractive true' "$TALKBOX" "$PROJECT" "$shimdir"
	[[ "$status" -eq 0 ]]
	[[ "$(grep -c 'nsenter.*nft' "$log" 2>/dev/null || true)" -ge 1 ]]
	: >"$log"
	# shellcheck disable=SC2016 # $0/$1/$2 expand inside the wrapped bash -c
	run sdrun bash -c 'cd "$1" && PATH="$2:$PATH" "$0/talkbox.sh" offbox --deny-ip 1.1.1.1 -c --noninteractive true' "$TALKBOX" "$PROJECT" "$shimdir"
	[[ "$status" -eq 0 ]]
	[[ "$(grep -c 'nsenter.*nft' "$log" 2>/dev/null || true)" -eq 0 ]]
}

@test "onbox --deny-ip ::/0 keeps the IPv6 loopback ::1 reachable" {
	require_nft_ipv6
	local www port srv n
	www="$(mktemp -d)"
	printf 'ipv6-loopback-marker\n' >"$www/marker"
	start_host_http_server "$www" srv port ::1
	HOST_SRV_PID=$srv
	for ((n = 0; n < 20; n++)); do
		if curl -6 -fsS --max-time 2 "http://[::1]:$port/marker" >/dev/null 2>&1; then
			break
		fi
		sleep 0.5
	done
	# shellcheck disable=SC2016 # $0/$1/$2 expand inside the wrapped bash -c
	run run_talkbox "$PROJECT" "$TALKBOX" onbox --deny-ip ::/0 --port "$port" -c --noninteractive \
		'curl -fsS --max-time 8 "http://[::1]:'"$port"'/marker" && echo IPV6-LOOPBACK-REACHABLE'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'IPV6-LOOPBACK-REACHABLE'* ]]
	[[ "$output" != *'talkbox:'* ]]
	kill "$srv" 2>/dev/null || true
	HOST_SRV_PID=""
	rm -rf "$www"
}

@test "a deny entry overridden by --allow-ip remains reachable" {
	require_nft_and_internet
	# shellcheck disable=SC2016 # $0/$1/$2 expand inside the wrapped bash -c
	run run_talkbox "$PROJECT" "$TALKBOX" onbox --deny-ip 1.1.1.1 -c --noninteractive \
		'curl -sS --max-time 8 -o /dev/null http://1.1.1.1/ 2>/dev/null && echo DENY-REACHABLE || echo DENY-BLOCKED'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'DENY-BLOCKED'* ]]
	[[ "$output" != *'talkbox:'* ]]
	# shellcheck disable=SC2016 # $0/$1/$2 expand inside the wrapped bash -c
	run run_talkbox "$PROJECT" "$TALKBOX" onbox --deny-ip 1.1.1.1 --allow-ip 1.1.1.1 -c --noninteractive \
		'curl -sS --max-time 8 -o /dev/null http://1.1.1.1/ 2>/dev/null && echo ALLOW-REACHABLE || echo ALLOW-BLOCKED'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'ALLOW-REACHABLE'* ]]
	[[ "$output" != *'talkbox:'* ]]
}

@test "onbox --deny-ip blocks a deny-listed connection attempted during setup" {
	require_nft_and_internet
	local base vol cfg upsh
	base="$(basename "$PROJECT")"
	vol="$PROJECT_SLUG.onbox.gitdir"
	ensure_base_image_e2e "$TALKBOX"
	sdrun podman volume rm -f "$vol" >/dev/null 2>&1 || true
	sdrun podman volume create "$vol" >/dev/null
	cfg="$(mktemp)"
	upsh="$PROJECT/uploadpack-hook.sh"
	printf '[remote "host"]\n\tuploadpack = /bin/sh /working/%s/uploadpack-hook.sh\n' "$base" >"$cfg"
	cat >"$upsh" <<EOF
#!/bin/sh
if curl -sS --max-time 5 -o /dev/null http://1.1.1.1/ 2>/dev/null; then
  echo REACHED > /working/$base/hook-result.txt
else
  echo BLOCKED > /working/$base/hook-result.txt
fi
exec git-upload-pack "\$@"
EOF
	chmod +x "$upsh"
	# The pre-planted gitdir config makes the gitdir-init `git fetch host` run
	# the uploadpack script inside the container; the connection attempt thus
	# happens during setup (entrypoint today, setup.sh after the refactor).
	sdrun podman run --rm -i --network=none --userns=keep-id:uid=1000,gid=1000 \
		-v "$vol:/v" -v "$cfg:/cfg:ro" "$E2E_BASE_IMAGE" cp /cfg /v/config
	run run_talkbox "$PROJECT" "$TALKBOX" onbox --deny-ip 1.1.1.1 -c --noninteractive 'cat hook-result.txt'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'BLOCKED'* ]]
	[[ "$output" != *'REACHED'* ]]
	[[ "$output" != *'talkbox:'* ]]
	rm -f "$cfg"
}
