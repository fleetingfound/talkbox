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

@test "onbox_container_name returns the project slug with a .onbox suffix" {
	load_lib naming.sh
	[[ "$(onbox_container_name '/tmp/My Project')" == 'my-project.onbox' ]]
}

@test "onbox_container_name derives the container name for an already-slugged path" {
	load_lib naming.sh
	[[ "$(onbox_container_name '/tmp/example-project')" == 'example-project.onbox' ]]
}

@test "netbox_container_name returns the project slug with a .netbox suffix" {
	load_lib naming.sh
	[[ "$(netbox_container_name '/tmp/My Project')" == 'my-project.netbox' ]]
	[[ "$(netbox_container_name '/tmp/example-project')" == 'example-project.netbox' ]]
}

@test "offbox_container_name returns the project slug with a .offbox suffix" {
	load_lib naming.sh
	[[ "$(offbox_container_name '/tmp/My Project')" == 'my-project.offbox' ]]
	[[ "$(offbox_container_name '/tmp/example-project')" == 'example-project.offbox' ]]
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

@test "netbox_worktree_volume names the netbox worktree volume" {
	load_lib naming.sh
	[[ "$(netbox_worktree_volume '/tmp/My Project')" == 'my-project.netbox.worktree' ]]
}

@test "offbox_worktree_volume names the offbox worktree volume" {
	load_lib naming.sh
	[[ "$(offbox_worktree_volume '/tmp/My Project')" == 'my-project.offbox.worktree' ]]
}

@test "netbox_write_volume names the netbox write volume from a dest-slug" {
	load_lib naming.sh
	[[ "$(netbox_write_volume '/tmp/My Project' 'talkbox-wdata')" == 'my-project.netbox.write.talkbox-wdata' ]]
}

@test "offbox_write_volume names the offbox write volume from a dest-slug" {
	load_lib naming.sh
	[[ "$(offbox_write_volume '/tmp/My Project' 'talkbox-wdata')" == 'my-project.offbox.write.talkbox-wdata' ]]
}

@test "netbox_root_image names the netbox root image" {
	load_lib naming.sh
	[[ "$(netbox_root_image '/tmp/My Project')" == 'my-project.netbox.root' ]]
}

@test "offbox_root_image names the offbox root image" {
	load_lib naming.sh
	[[ "$(offbox_root_image '/tmp/My Project')" == 'my-project.offbox.root' ]]
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
