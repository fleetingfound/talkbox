# shellcheck disable=SC2030,SC2031 # bats runs setup/test/teardown in one subshell
load helpers

setup() {
	PROJECT="$(mk_project)"
	TALKBOX="$(mk_talkbox)"
	PROJECT_SLUG="$(project_slug_e2e "$PROJECT")"
	ONBOX_CTR="$PROJECT_SLUG.onbox"
	NETBOX_CTR="$PROJECT_SLUG.netbox"
	OFFBOX_CTR="$PROJECT_SLUG.offbox"
	git -C "$PROJECT" commit -q --allow-empty -m host-initial
}

teardown() {
	sdrun podman rm -f -v "$ONBOX_CTR" "$NETBOX_CTR" "$OFFBOX_CTR" >/dev/null 2>&1 || true
	sdrun podman rmi "$PROJECT_SLUG.netbox.root" "$PROJECT_SLUG.offbox.root" >/dev/null 2>&1 || true
	local v
	for v in $(sdrun podman volume ls -q --filter "name=$PROJECT_SLUG" 2>/dev/null); do
		sdrun podman volume rm -f "$v" >/dev/null 2>&1 || true
	done
	rm -rf "$PROJECT" "$TALKBOX"
}

@test "onbox container git identity matches the host user.name and user.email" {
	run run_talkbox "$PROJECT" "$TALKBOX" onbox -c --noninteractive 'git config user.name && git config user.email'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'talkbox-test'* ]]
	[[ "$output" == *'test@example.com'* ]]
}

@test "onbox commits are attributed to the host git identity" {
	run run_talkbox "$PROJECT" "$TALKBOX" onbox -c --noninteractive 'git commit --allow-empty -m identity-commit && git log --format="%an <%ae>" -1'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'talkbox-test <test@example.com>'* ]]
}

@test "netbox container git identity matches the host user.name and user.email" {
	run run_talkbox "$PROJECT" "$TALKBOX" netbox -c --noninteractive 'git config user.name && git config user.email'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'talkbox-test'* ]]
	[[ "$output" == *'test@example.com'* ]]
}

@test "netbox commits are attributed to the host git identity" {
	run run_talkbox "$PROJECT" "$TALKBOX" netbox -c --noninteractive 'git commit --allow-empty -m identity-commit && git log --format="%an <%ae>" -1'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'talkbox-test <test@example.com>'* ]]
}

@test "offbox container git identity matches the host user.name and user.email" {
	run run_talkbox "$PROJECT" "$TALKBOX" offbox -c --noninteractive 'git config user.name && git config user.email'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'talkbox-test'* ]]
	[[ "$output" == *'test@example.com'* ]]
}

@test "offbox commits are attributed to the host git identity" {
	run run_talkbox "$PROJECT" "$TALKBOX" offbox -c --noninteractive 'git commit --allow-empty -m identity-commit && git log --format="%an <%ae>" -1'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *'talkbox-test <test@example.com>'* ]]
}
