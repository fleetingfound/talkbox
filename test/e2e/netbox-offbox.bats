load helpers

setup() {
	PROJECT="$(mk_project)"
	TALKBOX="$(mk_talkbox)"
	PROJECT_SLUG="$(project_slug_e2e "$PROJECT")"
	ONBOX_CTR="$PROJECT_SLUG.onbox"
	NETBOX_CTR="$PROJECT_SLUG.netbox"
	OFFBOX_CTR="$PROJECT_SLUG.offbox"
	NETBOX_ROOT="$PROJECT_SLUG.netbox.root"
	OFFBOX_ROOT="$PROJECT_SLUG.offbox.root"
}

teardown() {
	sdrun podman rm -f -v "$NETBOX_CTR" "$OFFBOX_CTR" "$ONBOX_CTR" >/dev/null 2>&1 || true
	sdrun podman rmi "$NETBOX_ROOT" "$OFFBOX_ROOT" >/dev/null 2>&1 || true
	local v
	for v in $(sdrun podman volume ls -q --filter "name=$PROJECT_SLUG" 2>/dev/null); do
		sdrun podman volume rm -f "$v" >/dev/null 2>&1 || true
	done
	rm -rf "$PROJECT" "$TALKBOX"
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
	shimdir="$(mk_gpu_shim "$log")"
	# shellcheck disable=SC2016 # $0/$1/$2 expand inside the wrapped bash -c
	run sdrun bash -c 'cd "$1" && PATH="$2:$PATH" "$0/talkbox.sh" netbox --gpu -c --noninteractive true' "$TALKBOX" "$PROJECT" "$shimdir"
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
	shimdir="$(mk_gpu_shim "$log")"
	# shellcheck disable=SC2016 # $0/$1/$2 expand inside the wrapped bash -c
	run sdrun bash -c 'cd "$1" && PATH="$2:$PATH" "$0/talkbox.sh" offbox --gpu -c --noninteractive true' "$TALKBOX" "$PROJECT" "$shimdir"
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
	run run_talkbox "$PROJECT" "$TALKBOX" netbox --rm-container --write "$data:/talkbox/wdata"
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

@test "netbox --rm-image removes the base image" {
	run run_talkbox "$PROJECT" "$TALKBOX" netbox -c --noninteractive 'true'
	[[ "$status" -eq 0 ]]
	run sdrun podman image exists talkbox/base:latest
	[[ "$status" -eq 0 ]]
	run run_talkbox "$PROJECT" "$TALKBOX" netbox --rm-image
	[[ "$status" -eq 0 ]]
	run sdrun podman image exists talkbox/base:latest
	[[ "$status" -ne 0 ]]
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
