load helpers

@test "project_base returns the basename of the project path" {
	load_lib naming.sh
	[[ "$(project_base '/tmp/some/dir/example-project')" == 'example-project' ]]
}

@test "project_base strips a trailing slash from the project path" {
	load_lib naming.sh
	[[ "$(project_base '/tmp/example-project/')" == 'example-project' ]]
}

@test "project_slug lowercases the project base" {
	load_lib naming.sh
	[[ "$(project_slug '/tmp/MyProject')" == 'myproject' ]]
}

@test "project_slug converts non-alphanumeric characters to single hyphens" {
	load_lib naming.sh
	[[ "$(project_slug '/tmp/My Project_v2')" == 'my-project-v2' ]]
}

@test "project_slug collapses runs of non-alphanumeric characters into one hyphen" {
	load_lib naming.sh
	[[ "$(project_slug '/tmp/a  b')" == 'a-b' ]]
}

@test "project_slug leaves an already-slugged base unchanged" {
	load_lib naming.sh
	[[ "$(project_slug '/tmp/my-project-v2')" == 'my-project-v2' ]]
}

@test "base_image_name prints the shared base image name talkbox/base:latest" {
	load_lib naming.sh
	[[ "$(base_image_name)" == 'talkbox/base:latest' ]]
}

@test "base_image_name honours the TALKBOX_BASE_IMAGE override and the default when unset" {
	load_lib naming.sh
	# shellcheck disable=SC2034 # TALKBOX_BASE_IMAGE is read by the sourced base_image_name
	TALKBOX_BASE_IMAGE='custom/base:v9'
	[[ "$(base_image_name)" == 'custom/base:v9' ]]
	unset TALKBOX_BASE_IMAGE
	[[ "$(base_image_name)" == 'talkbox/base:latest' ]]
}

@test "container_name_of names each container <project-slug>.<container>" {
	load_container_libs
	local c
	for c in onbox netbox offbox; do
		[[ "$(container_name_of "$c" '/tmp/My Project')" == "my-project.$c" ]]
		[[ "$(container_name_of "$c" '/tmp/example-project')" == "example-project.$c" ]]
	done
}

@test "dest_slug lowercases and hyphenates a dest path" {
	load_lib naming.sh
	[[ "$(dest_slug '/home/dev/My Data')" == 'home-dev-my-data' ]]
	[[ "$(dest_slug '/talkbox/wdata')" == 'talkbox-wdata' ]]
}

@test "dest_slug strips leading and trailing slashes" {
	load_lib naming.sh
	[[ "$(dest_slug '/a/b/c/')" == 'a-b-c' ]]
	[[ "$(dest_slug '/')" == '' ]]
}

@test "project_slug strips leading and trailing hyphens produced by normalisation" {
	load_lib naming.sh
	[[ "$(project_slug '/tmp/!!My Project!!')" == 'my-project' ]]
}

@test "project_slug returns empty for a base with no alphanumeric characters" {
	load_lib naming.sh
	[[ "$(project_slug '/tmp/!!!')" == '' ]]
}

@test "dest_slug collapses runs of non-alphanumeric characters into one hyphen" {
	load_lib naming.sh
	[[ "$(dest_slug '/a  b//c')" == 'a-b-c' ]]
}

@test "dest_slug strips leading and trailing hyphens produced by normalisation" {
	load_lib naming.sh
	[[ "$(dest_slug '/tmp/!')" == 'tmp' ]]
	[[ "$(dest_slug '!project!')" == 'project' ]]
}

@test "dest_slug returns empty when normalisation erases every character" {
	load_lib naming.sh
	[[ "$(dest_slug '/!')" == '' ]]
}

@test "dest_slug normalises identically to project_slug for the same string" {
	load_lib naming.sh
	[[ "$(dest_slug 'My  Project_v2!')" == "$(project_slug '/tmp/My  Project_v2!')" ]]
	[[ "$(dest_slug 'My  Project_v2!')" == 'my-project-v2' ]]
}

@test "worktree_volume_of names the netbox and offbox worktree volumes" {
	load_container_libs
	[[ "$(worktree_volume_of netbox '/tmp/My Project')" == 'my-project.netbox.worktree' ]]
	[[ "$(worktree_volume_of offbox '/tmp/My Project')" == 'my-project.offbox.worktree' ]]
}

@test "worktree_volume_of maps the onbox worktree to the host project path" {
	load_container_libs
	[[ "$(worktree_volume_of onbox '/tmp/My Project')" == '/tmp/My Project' ]]
}

@test "write_volume_of names the netbox and offbox write volumes from a dest-slug" {
	load_container_libs
	[[ "$(write_volume_of netbox '/tmp/My Project' 'talkbox-wdata')" == 'my-project.netbox.write.talkbox-wdata' ]]
	[[ "$(write_volume_of offbox '/tmp/My Project' 'talkbox-wdata')" == 'my-project.offbox.write.talkbox-wdata' ]]
}

@test "root_image_of names the netbox and offbox root images" {
	load_container_libs
	[[ "$(root_image_of netbox '/tmp/My Project')" == 'my-project.netbox.root' ]]
	[[ "$(root_image_of offbox '/tmp/My Project')" == 'my-project.offbox.root' ]]
}

@test "gitdir_volume names the onbox gitdir volume" {
	load_lib naming.sh
	[[ "$(gitdir_volume '/tmp/My Project' onbox)" == 'my-project.onbox.gitdir' ]]
}

@test "gitdir_volume names the netbox and offbox gitdir volumes" {
	load_lib naming.sh
	[[ "$(gitdir_volume '/tmp/example-project' netbox)" == 'example-project.netbox.gitdir' ]]
	[[ "$(gitdir_volume '/tmp/example-project' offbox)" == 'example-project.offbox.gitdir' ]]
}
