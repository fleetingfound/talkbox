#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
	printf 'usage: %s <target> <test-dir> [record-path]\n' "$0" >&2
	exit 2
fi
target="$1"
suite_dir="$2"
record_path="${3:-}"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

source "$PROJECT_ROOT/test/lib.bash"

GLOBAL_TEST_TIMEOUT="${GLOBAL_TEST_TIMEOUT:-900}"
INDIVIDUAL_TEST_TIMEOUT="${INDIVIDUAL_TEST_TIMEOUT:-60}"

if [[ ! -d "$suite_dir" ]]; then
	printf 'error: test directory not found: %s\n' "$suite_dir" >&2
	exit 1
fi

mapfile -t files < <(find "$suite_dir" -name '*.bats' -type f | sort)
if [[ ${#files[@]} -eq 0 ]]; then
	printf 'error: no .bats test files found in %s\n' "$suite_dir" >&2
	exit 1
fi

printf '== %s ==\n' "$target"
printf 'global test timeout   : %ss\n' "$GLOBAL_TEST_TIMEOUT"
printf 'individual test timeout: %ss\n' "$INDIVIDUAL_TEST_TIMEOUT"
printf 'test files            : %d\n' "${#files[@]}"

started="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/talkbox-run.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
tap_file="$tmp/tap.log"
svc_err="$tmp/svc.err"
sd_err="$tmp/systemd.err"

timed_out=no
rc=0

run_with_timeout() {
	set +e
	BATS_TEST_TIMEOUT="$INDIVIDUAL_TEST_TIMEOUT" \
		timeout "$GLOBAL_TEST_TIMEOUT" bash -c 'exec bats --tap "$@"' -- "${files[@]}" \
		>"$tap_file" 2>"$svc_err"
	rc=$?
	set -e
	if [[ $rc -eq 124 ]]; then
		timed_out=yes
	fi
}

run_with_systemd() {
	set +e
	systemd-run --user --wait --collect \
		-p "RuntimeMaxSec=$GLOBAL_TEST_TIMEOUT" \
		-p KillMode=control-group \
		-p "WorkingDirectory=$PROJECT_ROOT" \
		-p "StandardOutput=file:$tap_file" \
		-p "StandardError=file:$svc_err" \
		-E "PATH=$PATH" \
		-E "GLOBAL_TEST_TIMEOUT=$GLOBAL_TEST_TIMEOUT" \
		-E "INDIVIDUAL_TEST_TIMEOUT=$INDIVIDUAL_TEST_TIMEOUT" \
		-E "BATS_TEST_TIMEOUT=$INDIVIDUAL_TEST_TIMEOUT" \
		-- bash -c 'exec bats --tap "$@"' -- "${files[@]}" \
		>/dev/null 2>"$sd_err"
	rc=$?
	set -e
	if grep -q 'Finished with result: timeout' "$sd_err"; then
		timed_out=yes
	fi
}

if command -v systemd-run >/dev/null 2>&1; then
	run_with_systemd
	if [[ $rc -ne 0 && ! -s "$tap_file" && "$timed_out" == no ]]; then
		printf 'warning: systemd-run did not run the suite; using timeout(1) fallback\n' >&2
		run_with_timeout
	fi
else
	run_with_timeout
fi

if [[ -f "$tap_file" ]]; then
	parse_tap "$tap_file"
fi

if [[ "$timed_out" == yes ]]; then
	exit_field="timeout"
	cmd_status=1
else
	exit_field="$rc"
	cmd_status="$rc"
fi

if [[ -n "$record_path" ]]; then
	write_record "$target" "$record_path" "$started" "$exit_field"
else
	write_record "$target" "$PROJECT_ROOT/.llm/gen/runs/$target.gen.yaml" "$started" "$exit_field"
fi

printf '\n--- suite output ---\n'
if [[ -f "$tap_file" ]]; then
	cat "$tap_file"
fi
if [[ -s "$svc_err" ]]; then
	cat "$svc_err" >&2
fi
printf -- '--------------------\n'

if [[ "$timed_out" == yes ]]; then
	printf 'suite timed out after %ss\n' "$GLOBAL_TEST_TIMEOUT" >&2
fi

if [[ -n "$record_path" ]]; then
	printf 'run record: %s\n' "${record_path#"$PROJECT_ROOT"/}"
else
	printf 'run record: %s\n' ".llm/gen/runs/$target.gen.yaml"
fi
printf 'total=%s pass=%s fail=%s skip=%s exit=%s\n' "$TOTAL" "$PASS" "$FAIL" "$SKIP" "$exit_field"

exit "$cmd_status"
