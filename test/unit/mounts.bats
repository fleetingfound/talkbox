load helpers

setup() {
	PROJECT="$BATS_TEST_TMPDIR/talkbox-proj"
	HOME_FAKE="$BATS_TEST_TMPDIR/home"
	mkdir -p "$PROJECT" "$HOME_FAKE"
	ABSENT="$BATS_TEST_TMPDIR/absent.read.mounts"
}

@test "mount_args derives a read default dest from the source basename" {
	load_lib mounts.sh
	local out=()
	mount_args out read "$ABSENT" "$PROJECT" "$HOME_FAKE" '/some/dir/notes.txt'
	[[ "${out[*]}" == "-v /some/dir/notes.txt:/host/read/notes.txt:ro" ]]
}

@test "mount_args derives a write default dest from the source basename" {
	load_lib mounts.sh
	local out=()
	mount_args out write "$ABSENT" "$PROJECT" "$HOME_FAKE" '/some/dir/data'
	[[ "${out[*]}" == "-v /some/dir/data:/host/write/data" ]]
}

@test "mount_args parses a source:dest pair without spaces" {
	load_lib mounts.sh
	local out=()
	mount_args out read "$ABSENT" "$PROJECT" "$HOME_FAKE" '/src:/a/b'
	[[ "${out[*]}" == "-v /src:/a/b:ro" ]]
}

@test "mount_args parses a source : dest pair with spaces" {
	load_lib mounts.sh
	local out=()
	mount_args out read "$ABSENT" "$PROJECT" "$HOME_FAKE" '/src : /a/b'
	[[ "${out[*]}" == "-v /src:/a/b:ro" ]]
}

@test "mount_args ignores blank lines and comment lines" {
	load_lib mounts.sh
	local file="$BATS_TEST_TMPDIR/read.mounts"
	printf '# a comment\n\n  # indented\n/a\n' >"$file"
	local out=()
	mount_args out read "$file" "$PROJECT" "$HOME_FAKE"
	[[ "${out[*]}" == "-v /a:/host/read/a:ro" ]]
}

@test "mount_entries strips an inline comment from a file line and parses the source spec" {
	load_lib mounts.sh
	local file="$BATS_TEST_TMPDIR/read.mounts"
	printf '/a  # a comment\n' >"$file"
	local out=()
	mount_args out read "$file" "$PROJECT" "$HOME_FAKE"
	[[ "${out[*]}" == "-v /a:/host/read/a:ro" ]]
}

@test "mount_entries strips an inline comment from a file line and parses the source : dest spec" {
	load_lib mounts.sh
	local file="$BATS_TEST_TMPDIR/read.mounts"
	printf '/src : /a/b  # a comment\n' >"$file"
	local out=()
	mount_args out read "$file" "$PROJECT" "$HOME_FAKE"
	[[ "${out[*]}" == "-v /src:/a/b:ro" ]]
}

@test "mount_entries strips an inline comment from CLI --read and --write specs" {
	load_lib mounts.sh
	local r=() w=()
	mount_args r read "$ABSENT" "$PROJECT" "$HOME_FAKE" '/a  # a comment'
	mount_args w write "$ABSENT" "$PROJECT" "$HOME_FAKE" '/a  # a comment'
	[[ "${r[*]}" == "-v /a:/host/read/a:ro" ]]
	[[ "${w[*]}" == "-v /a:/host/write/a" ]]
}

@test "mount_args yields no mounts when the defaults file is absent" {
	load_lib mounts.sh
	local out=()
	mount_args out read "$ABSENT" "$PROJECT" "$HOME_FAKE"
	[[ ${#out[@]} -eq 0 ]]
}

@test "mount_args yields no mounts when the defaults file is empty" {
	load_lib mounts.sh
	local file="$BATS_TEST_TMPDIR/read.mounts"
	: >"$file"
	local out=()
	mount_args out read "$file" "$PROJECT" "$HOME_FAKE"
	[[ ${#out[@]} -eq 0 ]]
}

@test "mount_args expands ~ in the source and dest" {
	load_lib mounts.sh
	local out=()
	# shellcheck disable=SC2088 # a literal ~ placeholder is passed for expansion
	mount_args out read "$ABSENT" "$PROJECT" "$HOME_FAKE" '~/cfg:~/dest'
	[[ "${out[*]}" == "-v $HOME_FAKE/cfg:$HOME_FAKE/dest:ro" ]]
}

@test "mount_args expands \$HOME in the source and dest" {
	load_lib mounts.sh
	local out=()
	# shellcheck disable=SC2016 # a literal $HOME placeholder is passed for expansion
	mount_args out read "$ABSENT" "$PROJECT" "$HOME_FAKE" '$HOME/cfg:$HOME/dest'
	[[ "${out[*]}" == "-v $HOME_FAKE/cfg:$HOME_FAKE/dest:ro" ]]
}

@test "mount_args expands \$PROJECT in the dest" {
	load_lib mounts.sh
	local out=()
	# shellcheck disable=SC2016 # a literal $PROJECT placeholder is passed for expansion
	mount_args out read "$ABSENT" "$PROJECT" "$HOME_FAKE" "/host/x:\$PROJECT/cfg"
	[[ "${out[*]}" == "-v /host/x:/working/talkbox-proj/cfg:ro" ]]
}

@test "mount_args unions defaults-file and CLI mounts" {
	load_lib mounts.sh
	local file="$BATS_TEST_TMPDIR/read.mounts"
	printf '/def\n' >"$file"
	local out=()
	mount_args out read "$file" "$PROJECT" "$HOME_FAKE" '/cli'
	[[ "${out[*]}" == "-v /def:/host/read/def:ro -v /cli:/host/read/cli:ro" ]]
}

@test "mount_args collapses identical dests keeping the last source" {
	load_lib mounts.sh
	local out=()
	mount_args out read "$ABSENT" "$PROJECT" "$HOME_FAKE" '/first:/x' '/second:/x'
	[[ "${out[*]}" == "-v /second:/x:ro" ]]
}

@test "mount_args orders nested dests shallow-to-deep" {
	load_lib mounts.sh
	local out=()
	mount_args out read "$ABSENT" "$PROJECT" "$HOME_FAKE" '/d:/a/b/c' '/b:/a/b' '/a:/a'
	[[ "${out[*]}" == "-v /a:/a:ro -v /b:/a/b:ro -v /d:/a/b/c:ro" ]]
}

@test "mount_args treats read and write modes independently" {
	load_lib mounts.sh
	local r=() w=()
	mount_args r read "$ABSENT" "$PROJECT" "$HOME_FAKE" '/src:/home/dev/data'
	mount_args w write "$ABSENT" "$PROJECT" "$HOME_FAKE" '/src:/home/dev/data'
	[[ "${r[*]}" == "-v /src:/home/dev/data:ro" ]]
	[[ "${w[*]}" == "-v /src:/home/dev/data" ]]
}

@test "mount_volume_args emits netbox write mounts as volumes named <slug>.netbox.write.<dest-slug>" {
	load_lib mounts.sh
	local out=()
	mount_volume_args out netbox "$ABSENT" "$PROJECT" "$HOME_FAKE" '/host/data:/talkbox/wdata'
	[[ "${out[*]}" == "-v talkbox-proj.netbox.write.talkbox-wdata:/talkbox/wdata" ]]
}

@test "mount_volume_args emits offbox write mounts as volumes named <slug>.offbox.write.<dest-slug>" {
	load_lib mounts.sh
	local out=()
	mount_volume_args out offbox "$ABSENT" "$PROJECT" "$HOME_FAKE" '/host/data:/talkbox/wdata'
	[[ "${out[*]}" == "-v talkbox-proj.offbox.write.talkbox-wdata:/talkbox/wdata" ]]
}

@test "mount_volume_args derives the dest-slug from the dest basename path" {
	load_lib mounts.sh
	local out=()
	mount_volume_args out netbox "$ABSENT" "$PROJECT" "$HOME_FAKE" '/host/data:/a/b/c'
	[[ "${out[*]}" == "-v talkbox-proj.netbox.write.a-b-c:/a/b/c" ]]
}

@test "mount_volume_args merges defaults-file and CLI write specs" {
	load_lib mounts.sh
	local file="$BATS_TEST_TMPDIR/write.mounts"
	printf '/def:/x\n' >"$file"
	local out=()
	mount_volume_args out netbox "$file" "$PROJECT" "$HOME_FAKE" '/cli:/y'
	[[ "${out[*]}" == "-v talkbox-proj.netbox.write.x:/x -v talkbox-proj.netbox.write.y:/y" ]]
}
