@test "canary: an assertion which is intentionally false" {
	[[ 1 -eq 2 ]]
}

@test "canary: a command which exits nonzero" {
	false
}
