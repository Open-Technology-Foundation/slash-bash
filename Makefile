# Makefile - slash-bash dev workflow targets.
#
# Targets:
#   test    Run the bats suite (Phase 1, 266 cases). BATS_E2E=1 also runs
#           the PTY-driven Phase 2 chord-trick verification.
#   lint    shellcheck -x on every bash file in the project + tests/.
#   audit   bcscheck on the library (BCS, LLM-backed, slow).
#   check   lint + test (the default pre-merge gate).
#
# The bash 5+ requirement is enforced by individual .bats files; the suite
# does not require a Makefile-level guard.

.PHONY: test test-e2e lint audit check help
.DEFAULT_GOAL := help

BASH_FILES = slash-bash.bash slash-bash .slash-bash-init claude-sessions \
             tests/test_helper.bash $(wildcard handlers.d/*.bash)

test:
	@bats tests/

test-e2e:
	@BATS_E2E=1 bats tests/e2e_chord.bats

lint:
	@shellcheck -x $(BASH_FILES) tests/mocks/*

audit:
	@bcscheck slash-bash.bash

check: lint test

help:
	@echo 'Targets:'
	@echo '  test      Run bats Phase 1 suite (266 cases)'
	@echo '  test-e2e  Run BATS_E2E=1 Phase 2 PTY chord tests (needs expect)'
	@echo '  lint      shellcheck -x all bash files'
	@echo '  audit     bcscheck slash-bash.bash (slow, LLM-backed)'
	@echo '  check     lint + test'
