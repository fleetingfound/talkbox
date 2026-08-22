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

@test "base_image_name returns a non-empty stable name" {
	load_lib naming.sh
	local first second
	first="$(base_image_name)"
	second="$(base_image_name)"
	[[ -n "$first" ]]
	[[ "$first" == "$second" ]]
}
