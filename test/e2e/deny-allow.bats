load helpers

setup() {
	# nft lives in /usr/sbin on Debian derivatives, which is not on the
	# default user PATH; the enforcement under test invokes `nft` via
	# `podman unshare nsenter`, so make it resolvable.
	export PATH="/usr/sbin:/sbin:$PATH"
	e2e_setup
}

teardown() {
	e2e_teardown
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
	local www port srv
	www="$(mktemp -d)"
	printf 'deny-marker\n' >"$www/marker"
	start_host_http_server "$www" srv port
	e2e_register_pid "$srv"
	wait_for_http "http://127.0.0.1:$port/marker"
	run run_talkbox "$PROJECT" "$TALKBOX" onbox --deny-ip 1.1.1.1 --port "$port" -c --noninteractive \
		'curl -sS --max-time 8 -o /dev/null http://1.1.1.1/ 2>/dev/null && echo DENIED-REACHABLE || echo DENIED-BLOCKED
		curl -fsS --max-time 8 "http://127.0.0.1:'"$port"'/marker" && echo ALLOWED-REACHABLE'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'DENIED-BLOCKED'* ]]
	[[ "$output" == *'ALLOWED-REACHABLE'* ]]
	[[ "$output" != *'talkbox:'* ]]
	kill "$srv" 2>/dev/null || true
	e2e_clear_pids
	rm -rf "$www"
}

@test "netbox --deny-ip blocks a denied address while a non-denied address remains reachable" {
	require_nft_and_internet
	command -v python3 >/dev/null 2>&1 || skip "python3 is required for the deny/allow e2e test"
	local www port srv
	www="$(mktemp -d)"
	printf 'deny-marker\n' >"$www/marker"
	start_host_http_server "$www" srv port
	e2e_register_pid "$srv"
	wait_for_http "http://127.0.0.1:$port/marker"
	run run_talkbox "$PROJECT" "$TALKBOX" netbox --deny-ip 1.1.1.1 --port "$port" -c --noninteractive \
		'curl -sS --max-time 8 -o /dev/null http://1.1.1.1/ 2>/dev/null && echo DENIED-REACHABLE || echo DENIED-BLOCKED
		curl -fsS --max-time 8 "http://127.0.0.1:'"$port"'/marker" && echo ALLOWED-REACHABLE'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'DENIED-BLOCKED'* ]]
	[[ "$output" == *'ALLOWED-REACHABLE'* ]]
	[[ "$output" != *'talkbox:'* ]]
	kill "$srv" 2>/dev/null || true
	e2e_clear_pids
	rm -rf "$www"
}

@test "onbox runs the nft installer for a non-empty deny set, also when allow entries are present; offbox does not" {
	command -v nft >/dev/null 2>&1 || skip "nft is required for the deny/allow enforcement e2e tests"
	local shimdir log
	log="$BATS_TEST_TMPDIR/podman.log"
	shimdir="$(mk_podman_logging_shim "$log")"
	e2e_register_dir "$shimdir"
	e2e_use_podman_shim "$shimdir"
	run run_talkbox "$PROJECT" "$TALKBOX" onbox --deny-ip 1.1.1.1 -c --noninteractive true
	[[ "$status" -eq 0 ]]
	[[ "$(grep -c 'nsenter.*nft' "$log" 2>/dev/null || true)" -ge 1 ]]
	: >"$log"
	# An allow entry no longer empties the deny set: the deny set stays raw,
	# so the installer must still run.
	run run_talkbox "$PROJECT" "$TALKBOX" onbox --deny-ip 1.1.1.1 --allow-ip 1.1.1.1 -c --noninteractive true
	[[ "$status" -eq 0 ]]
	[[ "$(grep -c 'nsenter.*nft' "$log" 2>/dev/null || true)" -ge 1 ]]
	: >"$log"
	run run_talkbox "$PROJECT" "$TALKBOX" offbox --deny-ip 1.1.1.1 -c --noninteractive true
	[[ "$status" -eq 0 ]]
	[[ "$(grep -c 'nsenter.*nft' "$log" 2>/dev/null || true)" -eq 0 ]]
}

@test "onbox --deny-ip ::/0 keeps the IPv6 loopback ::1 reachable" {
	require_nft_ipv6
	local www port srv
	www="$(mktemp -d)"
	printf 'ipv6-loopback-marker\n' >"$www/marker"
	start_host_http_server "$www" srv port ::1
	e2e_register_pid "$srv"
	wait_for_http "http://[::1]:$port/marker"
	run run_talkbox "$PROJECT" "$TALKBOX" onbox --deny-ip ::/0 --port "$port" -c --noninteractive \
		'curl -fsS --max-time 8 "http://[::1]:'"$port"'/marker" && echo IPV6-LOOPBACK-REACHABLE'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'IPV6-LOOPBACK-REACHABLE'* ]]
	[[ "$output" != *'talkbox:'* ]]
	kill "$srv" 2>/dev/null || true
	e2e_clear_pids
	rm -rf "$www"
}

@test "a deny entry overridden by --allow-ip remains reachable" {
	require_nft_and_internet
	run run_talkbox "$PROJECT" "$TALKBOX" onbox --deny-ip 1.1.1.1 -c --noninteractive \
		'curl -sS --max-time 8 -o /dev/null http://1.1.1.1/ 2>/dev/null && echo DENY-REACHABLE || echo DENY-BLOCKED'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'DENY-BLOCKED'* ]]
	[[ "$output" != *'talkbox:'* ]]
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
