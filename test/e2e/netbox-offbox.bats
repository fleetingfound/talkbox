load helpers

setup() {
	e2e_setup
	NETBOX_ROOT="$PROJECT_SLUG.netbox.root"
}

teardown() {
	e2e_teardown
}

@test "netbox container has internet access" {
	if ! curl -fsS --max-time 10 https://example.com >/dev/null 2>&1; then
		skip "host has no internet connectivity; skipping the netbox internet test"
	fi
	run run_talkbox "$PROJECT" "$TALKBOX" netbox -c --noninteractive 'curl -fsS --max-time 15 https://example.com >/dev/null && echo ONLINE'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'ONLINE'* ]]
}

@test "netbox edits land in the worktree volume, never the host" {
	printf 'host-worktree-file\n' >"$PROJECT/host-file.txt"
	run run_talkbox "$PROJECT" "$TALKBOX" netbox -c --noninteractive 'cat host-file.txt && echo netbox-worktree > netbox-file.txt'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'host-worktree-file'* ]]
	[[ ! -e "$PROJECT/netbox-file.txt" ]]
	run run_talkbox "$PROJECT" "$TALKBOX" netbox -c --noninteractive 'cat netbox-file.txt'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'netbox-worktree'* ]]
}

@test "netbox inherits the onbox root filesystem when onbox exists" {
	run run_onbox_noninteractive "$PROJECT" "$TALKBOX" 'echo inherited-marker > /tmp/netbox-inherit-marker'
	[[ "$status" -eq 0 ]]
	run run_talkbox "$PROJECT" "$TALKBOX" netbox -c --noninteractive 'test -f /tmp/netbox-inherit-marker && echo INHERITED'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'INHERITED'* ]]
}

@test "offbox blocks internet access" {
	run run_talkbox "$PROJECT" "$TALKBOX" offbox -c --noninteractive 'curl -fsS --max-time 5 http://example.com >/dev/null 2>&1 && echo ONLINE || echo OFFLINE'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'OFFLINE'* ]]
}

@test "offbox writes land in its volumes, never the host" {
	run run_talkbox "$PROJECT" "$TALKBOX" offbox -c --noninteractive 'echo offbox-worktree > offbox-file.txt'
	[[ "$status" -eq 0 ]]
	[[ ! -e "$PROJECT/offbox-file.txt" ]]
	run run_talkbox "$PROJECT" "$TALKBOX" offbox -c --noninteractive 'cat offbox-file.txt'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'offbox-worktree'* ]]
}

@test "offbox created after netbox copies the netbox worktree and write volumes" {
	local data
	data="$(mktemp -d)"
	printf 'host-source\n' >"$data/host-src.txt"
	run run_talkbox "$PROJECT" "$TALKBOX" netbox --write "$data:/talkbox/wdata" -c --noninteractive 'echo from-netbox-worktree > netbox-wt.txt && echo from-netbox-write > /talkbox/wdata/netbox-write.txt'
	[[ "$status" -eq 0 ]]
	run run_talkbox "$PROJECT" "$TALKBOX" offbox --write "$data:/talkbox/wdata" -c --noninteractive 'cat netbox-wt.txt && cat /talkbox/wdata/netbox-write.txt && cat /talkbox/wdata/host-src.txt'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'from-netbox-worktree'* ]]
	[[ "$output" == *'from-netbox-write'* ]]
	[[ "$output" == *'host-source'* ]]
	rm -rf "$data"
}

@test "netbox --fresh ignores existing containers and copies from host" {
	run run_onbox_noninteractive "$PROJECT" "$TALKBOX" 'echo root-marker > /tmp/root-marker'
	[[ "$status" -eq 0 ]]
	run run_talkbox "$PROJECT" "$TALKBOX" netbox -c --noninteractive 'test -f /tmp/root-marker && echo INHERITED'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'INHERITED'* ]]
	run run_talkbox "$PROJECT" "$TALKBOX" netbox --rm-container
	[[ "$status" -eq 0 ]]
	run run_talkbox "$PROJECT" "$TALKBOX" netbox --fresh -c --noninteractive 'test ! -f /tmp/root-marker && echo FRESH'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'FRESH'* ]]
}

@test "--inherit selects the explicit inheritance source" {
	run run_onbox_noninteractive "$PROJECT" "$TALKBOX" 'echo from-onbox > /tmp/inherit-marker'
	[[ "$status" -eq 0 ]]
	run run_talkbox "$PROJECT" "$TALKBOX" netbox --fresh -c --noninteractive 'echo from-netbox > /tmp/inherit-marker'
	[[ "$status" -eq 0 ]]
	run run_talkbox "$PROJECT" "$TALKBOX" offbox --inherit onbox -c --noninteractive 'cat /tmp/inherit-marker'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'from-onbox'* ]]
	[[ "$output" != *'from-netbox'* ]]
}

@test "netbox --gpu passes the GPU options to podman create on a GPU-less host" {
	local shimdir log
	log="$(mktemp)"
	shimdir="$(mk_podman_logging_shim "$log" start exec stop)"
	e2e_use_podman_shim "$shimdir"
	run run_talkbox "$PROJECT" "$TALKBOX" netbox --gpu -c --noninteractive true
	[[ "$status" -eq 0 ]]
	[[ "$(grep -c 'nvidia.com/gpu=all' "$log")" -ge 1 ]]
	[[ "$(grep -c 'keep-groups' "$log")" -ge 1 ]]
	run sdrun podman container exists "$NETBOX_CTR"
	[[ "$status" -eq 0 ]]
	rm -rf "$shimdir" "$log"
}

@test "offbox --gpu passes the GPU options to podman create on a GPU-less host" {
	local shimdir log
	log="$(mktemp)"
	shimdir="$(mk_podman_logging_shim "$log" start exec stop)"
	e2e_use_podman_shim "$shimdir"
	run run_talkbox "$PROJECT" "$TALKBOX" offbox --gpu -c --noninteractive true
	[[ "$status" -eq 0 ]]
	[[ "$(grep -c 'nvidia.com/gpu=all' "$log")" -ge 1 ]]
	[[ "$(grep -c 'keep-groups' "$log")" -ge 1 ]]
	run sdrun podman container exists "$OFFBOX_CTR"
	[[ "$status" -eq 0 ]]
	rm -rf "$shimdir" "$log"
}

@test "netbox --rm-container removes the container, its root image and named volumes" {
	local data
	data="$(mktemp -d)"
	run run_onbox_noninteractive "$PROJECT" "$TALKBOX" 'true'
	[[ "$status" -eq 0 ]]
	run run_talkbox "$PROJECT" "$TALKBOX" netbox --write "$data:/talkbox/wdata" -c --noninteractive 'true'
	[[ "$status" -eq 0 ]]
	run sdrun podman image exists "$NETBOX_ROOT"
	[[ "$status" -eq 0 ]]
	run sdrun podman volume exists "$PROJECT_SLUG.netbox.worktree"
	[[ "$status" -eq 0 ]]
	run sdrun podman volume exists "$PROJECT_SLUG.netbox.gitdir"
	[[ "$status" -eq 0 ]]
	run sdrun podman volume exists "$PROJECT_SLUG.netbox.write.talkbox-wdata"
	[[ "$status" -eq 0 ]]
	run run_talkbox "$PROJECT" "$TALKBOX" netbox --rm-container
	[[ "$status" -eq 0 ]]
	run sdrun podman image exists "$NETBOX_ROOT"
	[[ "$status" -ne 0 ]]
	run sdrun podman container exists "$NETBOX_CTR"
	[[ "$status" -ne 0 ]]
	run sdrun podman volume exists "$PROJECT_SLUG.netbox.worktree"
	[[ "$status" -ne 0 ]]
	run sdrun podman volume exists "$PROJECT_SLUG.netbox.gitdir"
	[[ "$status" -ne 0 ]]
	run sdrun podman volume exists "$PROJECT_SLUG.netbox.write.talkbox-wdata"
	[[ "$status" -ne 0 ]]
	rm -rf "$data"
}

@test "netbox --recontain leaves no write volume from the previous write-mount configuration" {
	local data alt
	data="$(mktemp -d)"
	alt="$(mktemp -d)"
	e2e_register_dir "$data"
	e2e_register_dir "$alt"
	printf 'new-config\n' >"$alt/new.txt"
	run run_talkbox "$PROJECT" "$TALKBOX" netbox --write "$data:/talkbox/wdata" -c --noninteractive true
	[[ "$status" -eq 0 ]]
	run sdrun podman volume exists "$PROJECT_SLUG.netbox.write.talkbox-wdata"
	[[ "$status" -eq 0 ]]
	run run_talkbox "$PROJECT" "$TALKBOX" netbox --recontain --write "$alt:/talkbox/walt"
	[[ "$status" -eq 0 ]]
	run sdrun podman volume exists "$PROJECT_SLUG.netbox.write.talkbox-wdata"
	[[ "$status" -ne 0 ]]
	run sdrun podman volume exists "$PROJECT_SLUG.netbox.write.talkbox-walt"
	[[ "$status" -eq 0 ]]
	run run_talkbox "$PROJECT" "$TALKBOX" netbox -c --noninteractive 'cat /talkbox/walt/new.txt'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'new-config'* ]]
}

@test "netbox --rm-image removes the base image" {
	run run_talkbox "$PROJECT" "$TALKBOX" netbox -c --noninteractive 'true'
	[[ "$status" -eq 0 ]]
	run sdrun podman image exists "$E2E_BASE_IMAGE"
	[[ "$status" -eq 0 ]]
	run run_talkbox "$PROJECT" "$TALKBOX" netbox --rm-image
	[[ "$status" -eq 0 ]]
	run sdrun podman image exists "$E2E_BASE_IMAGE"
	[[ "$status" -ne 0 ]]
}

@test "netbox --recontain recreates the container with setup.sh available" {
	run run_onbox_noninteractive "$PROJECT" "$TALKBOX" 'true'
	[[ "$status" -eq 0 ]]
	run run_talkbox "$PROJECT" "$TALKBOX" netbox -c --noninteractive 'true'
	[[ "$status" -eq 0 ]]
	run run_talkbox "$PROJECT" "$TALKBOX" netbox --recontain
	[[ "$status" -eq 0 ]]
	run run_talkbox "$PROJECT" "$TALKBOX" netbox -c --noninteractive 'head -n 1 /usr/local/bin/setup.sh'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'#!/usr/bin/env bash'* ]]
}

@test "netbox --rebuild commits onbox and recreates the container" {
	run run_onbox_noninteractive "$PROJECT" "$TALKBOX" 'echo rebuild-marker > /tmp/rebuild-marker'
	[[ "$status" -eq 0 ]]
	run run_talkbox "$PROJECT" "$TALKBOX" netbox --rebuild
	[[ "$status" -eq 0 ]]
	run sdrun podman image exists "$NETBOX_ROOT"
	[[ "$status" -eq 0 ]]
	run run_talkbox "$PROJECT" "$TALKBOX" netbox -c --noninteractive 'test -f /tmp/rebuild-marker && echo INHERITED'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'INHERITED'* ]]
}

@test "netbox --write with a file source is refused with a talkbox diagnostic and leaves no named volumes" {
	printf 'notes\n' >"$PROJECT/wfile.txt"
	run run_talkbox "$PROJECT" "$TALKBOX" netbox --write "$PROJECT/wfile.txt:/talkbox/wdata" -c --noninteractive true
	[[ "$status" -ne 0 ]]
	[[ "$output" == *'talkbox:'* ]]
	[[ "$output" == *"$PROJECT/wfile.txt"* ]]
	local vols
	vols="$(sdrun podman volume ls -q --filter "name=$PROJECT_SLUG" 2>/dev/null)"
	[[ -z "$vols" ]]
	run sdrun podman container exists "$NETBOX_CTR"
	[[ "$status" -ne 0 ]]
}

@test "a failed netbox populate leaves no named volumes and no container" {
	local data
	data="$(mktemp -d)"
	e2e_register_dir "$data"
	mkdir -p "$data/secret"
	printf 'secret\n' >"$data/secret/key.txt"
	chmod 000 "$data/secret"
	run run_talkbox "$PROJECT" "$TALKBOX" netbox --write "$data/secret:/talkbox/wdata" -c --noninteractive true
	chmod 755 "$data/secret"
	[[ "$status" -ne 0 ]]
	[[ "$output" == *'talkbox:'* ]]
	local vols
	vols="$(sdrun podman volume ls -q --filter "name=$PROJECT_SLUG" 2>/dev/null)"
	[[ -z "$vols" ]]
	run sdrun podman container exists "$NETBOX_CTR"
	[[ "$status" -ne 0 ]]
}
