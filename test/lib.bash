#!/usr/bin/env bash

parse_tap() {
	local tap_file="$1"
	TOTAL=0
	PASS=0
	FAIL=0
	SKIP=0
	FAIL_NAMES=()
	local pending=""
	while IFS= read -r line || [[ -n "$line" ]]; do
		case "$line" in
		'ok '*)
			TOTAL=$((TOTAL + 1))
			if [[ "$line" == *' # skip'* ]]; then
				SKIP=$((SKIP + 1))
			else
				PASS=$((PASS + 1))
			fi
			;;
		'not ok '*)
			TOTAL=$((TOTAL + 1))
			FAIL=$((FAIL + 1))
			local desc="${line#not ok }"
			desc="${desc#* }"
			desc="${desc% # *}"
			pending="$desc"
			;;
		'# (in test file '*)
			if [[ -n "$pending" ]]; then
				local src="${line#\# (in test file }"
				src="${src%%, line *}"
				src="${src#"$PROJECT_ROOT"/}"
				FAIL_NAMES+=("$src :: $pending")
				pending=""
			fi
			;;
		esac
	done <"$tap_file"
	if [[ -n "$pending" ]]; then
		FAIL_NAMES+=("(unknown) :: $pending")
	fi
}

yaml_quote() {
	printf '%s' "$1" | sed "s/'/''/g"
}

write_record() {
	local target="$1"
	local record="$2"
	local started="$3"
	local exit_field="$4"
	local name
	mkdir -p "$(dirname "$record")"
	{
		printf 'target: %s\n' "$target"
		printf "started: '%s'\n" "$started"
		printf 'exit: %s\n' "$exit_field"
		printf 'totals: { total: %s, pass: %s, fail: %s, skip: %s }\n' \
			"$TOTAL" "$PASS" "$FAIL" "$SKIP"
		printf 'fail:\n'
		for name in "${FAIL_NAMES[@]+"${FAIL_NAMES[@]}"}"; do
			printf " - '%s'\n" "$(yaml_quote "$name")"
		done
	} >"$record"
}
