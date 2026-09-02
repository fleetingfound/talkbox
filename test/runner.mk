SHELL := bash

GLOBAL_TEST_TIMEOUT ?= 900
INDIVIDUAL_TEST_TIMEOUT ?= 60

export GLOBAL_TEST_TIMEOUT
export INDIVIDUAL_TEST_TIMEOUT

RUNNER := test/run-suite.sh
SHELL_SCRIPTS := test/run-suite.sh test/lib.bash test/unit/helpers.bash test/e2e/helpers.bash test/unit/*.bats test/e2e/*.bats test/canary/*.bats test/timeout/*.bats

.PHONY: help test-unit test-e2e test-canary test-timeout lint format

help:
	@echo 'talkbox test harness'
	@echo
	@echo 'make test-unit     run the unit test suite (test/unit)'
	@echo 'make test-e2e      run the end-to-end test suite (test/e2e)'
	@echo 'make test-canary   run canary tests (expected to fail)'
	@echo 'make test-timeout  run timeout canary tests (expected to fail)'
	@echo 'make lint          check shell scripts with shellcheck'
	@echo 'make format        format shell scripts with shfmt'
	@echo
	@echo 'timeouts (override on the command line, e.g. GLOBAL_TEST_TIMEOUT=1200 INDIVIDUAL_TEST_TIMEOUT=60 make test-unit):'
	@echo '  GLOBAL_TEST_TIMEOUT     suite-level timeout in seconds (default $(GLOBAL_TEST_TIMEOUT))'
	@echo '  INDIVIDUAL_TEST_TIMEOUT per-test timeout in seconds (default $(INDIVIDUAL_TEST_TIMEOUT))'
	@echo 'note: the per-test BATS_TEST_TIMEOUT is set only when tests run via make; direct bats invocation has no per-test timeout'

test-unit: ; @$(RUNNER) test-unit test/unit
test-e2e: ; @$(RUNNER) test-e2e test/e2e
test-canary: ; @$(RUNNER) test-canary test/canary
test-timeout: ; @$(RUNNER) test-timeout test/timeout

lint:
	@shellcheck $(SHELL_SCRIPTS)

format:
	@shfmt -w $(SHELL_SCRIPTS)
