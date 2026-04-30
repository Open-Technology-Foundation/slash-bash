#!/usr/bin/env bats
#shellcheck shell=bats
# lazy_loaders.bats - _sb_load_agent_list / _sb_load_kb_list contracts.
# Idempotency, env override, ANSI-strip + sort -u for noisy claude.agent output.

load test_helper

setup() {
  setup_test_env
  enable_mocks
  source_slash_bash
}

teardown() {
  disable_mocks
  teardown_test_env
}

# ----------------------------------------------------------------------------
# _sb_load_agent_list
# ----------------------------------------------------------------------------

@test "load_agent_list: populates _SB_AGENT_LIST from --list" {
  mock_claude_agent list-good
  _sb_load_agent_list
  (( ${#_SB_AGENT_LIST[@]} == 3 ))
  [[ ${_SB_AGENT_LIST[*]} == *leet* ]]
}

@test "load_agent_list: idempotent on repeat call" {
  mock_claude_agent list-good
  _sb_load_agent_list
  local -i first=${#_SB_AGENT_LIST[@]}
  # Wipe the mock so a second --list would return empty - but the loader
  # short-circuits on non-empty list, so length must be unchanged.
  mock_claude_agent list-empty
  _sb_load_agent_list
  (( ${#_SB_AGENT_LIST[@]} == first ))
}

@test "load_agent_list: ANSI escapes stripped and duplicates de-duped" {
  mock_claude_agent list-noisy
  _sb_load_agent_list
  # The noisy mock emits coloured 'leet' twice + 'haiku' once -> after
  # sed-strip + sort -u we expect exactly 2 unique entries.
  (( ${#_SB_AGENT_LIST[@]} == 2 ))
  [[ ${_SB_AGENT_LIST[*]} == *leet* ]]
  [[ ${_SB_AGENT_LIST[*]} == *haiku* ]]
}

@test "load_agent_list: missing claude.agent returns 1, list stays empty" {
  disable_mocks
  export PATH=/usr/bin:/bin
  run _sb_load_agent_list
  assert_failure 1
  (( ${#_SB_AGENT_LIST[@]} == 0 ))
}

# ----------------------------------------------------------------------------
# _sb_load_kb_list
# ----------------------------------------------------------------------------

@test "load_kb_list: populates from glob under VECTORDBS" {
  make_fake_kb alpha
  make_fake_kb beta
  _sb_load_kb_list
  (( ${#_SB_KB_LIST[@]} == 2 ))
  [[ ${_SB_KB_LIST[*]} == *alpha* ]]
  [[ ${_SB_KB_LIST[*]} == *beta* ]]
}

@test "load_kb_list: SB_KB_LIST short-circuits glob with curated menu" {
  make_fake_kb real
  export SB_KB_LIST='one two three'
  _sb_load_kb_list
  (( ${#_SB_KB_LIST[@]} == 3 ))
  [[ ${_SB_KB_LIST[*]} == 'one two three' ]]
}

@test "load_kb_list: missing VECTORDBS dir returns 0 with empty list" {
  rm -rf "$VECTORDBS"
  run _sb_load_kb_list
  assert_success
  (( ${#_SB_KB_LIST[@]} == 0 ))
}

@test "load_kb_list: idempotent" {
  make_fake_kb x
  _sb_load_kb_list
  local -i first=${#_SB_KB_LIST[@]}
  make_fake_kb y
  _sb_load_kb_list
  # Loader is idempotent; second call keeps original list.
  (( ${#_SB_KB_LIST[@]} == first ))
}

# ----------------------------------------------------------------------------
# __sb_lazy_complete - default compspec for lazy bash_completion loading.
# Returns 124 to signal "compspec changed, retry" - the contract that drives
# the bash_completion source on the first TAB after an external command.
# Tests shadow `source` as a no-op to avoid the ~586 ms cost of actually
# sourcing /usr/share/bash-completion/bash_completion in the test shell.
# ----------------------------------------------------------------------------

@test "lazy_complete: returns 124 (compspec-changed signal)" {
  source() { return 0; }
  run __sb_lazy_complete
  ((status == 124))
}

@test "lazy_complete: removes self after first call" {
  source() { return 0; }
  __sb_lazy_complete || true
  ! declare -F __sb_lazy_complete >/dev/null
}

@test "lazy_complete: unsets BASH_COMPLETION_VERSINFO suppression marker" {
  source() { return 0; }
  export BASH_COMPLETION_VERSINFO=1
  __sb_lazy_complete || true
  ! [[ -v BASH_COMPLETION_VERSINFO ]]
}

#fin
