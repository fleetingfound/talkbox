load helpers

@test "strip_comment removes everything from the first # onwards" {
	load_lib common.sh
	run strip_comment '10.0.0.0/8  # Private-Use RFC 1918'
	[[ "$status" -eq 0 ]]
	[[ "$output" == '10.0.0.0/8  ' ]]
}

@test "strip_comment does not trim leading or trailing whitespace" {
	load_lib common.sh
	run strip_comment '  10.0.0.0/8   # comment   '
	[[ "$output" == '  10.0.0.0/8   ' ]]
}

@test "strip_comment leaves a string without a # unchanged" {
	load_lib common.sh
	run strip_comment '10.0.0.0/8'
	[[ "$output" == '10.0.0.0/8' ]]
}

@test "strip_comment empties a line whose first character is a #" {
	load_lib common.sh
	run strip_comment '# a comment'
	[[ -z "$output" ]]
}
