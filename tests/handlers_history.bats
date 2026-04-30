#!/usr/bin/env bats
#shellcheck shell=bats
# handlers_history.bats - /history handler + lazy dir creation contract.

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

@test "/history (no arg, no file): reports 'no slash history yet'" {
  run _sb_cmd_history
  assert_success
  assert_output "no slash history yet"
}

@test "/history n: reads last n lines from history file" {
  mkdir -p "${_SB_HISTORY_FILE%/*}"
  printf 'A\nB\nC\nD\nE\n' > "$_SB_HISTORY_FILE"
  run _sb_cmd_history 3
  assert_success
  assert_output 'C
D
E'
}

@test "/history: rejects non-integer arg" {
  run _sb_cmd_history abc
  assert_failure 1
  assert_output --partial "usage: /history"
}

@test "/history: regex permits 0 (current behaviour: ^[0-9]+$)" {
  # Slash-shell's /history regex is ^[0-9]+$ - more permissive than
  # /maxtokens' ^[1-9][0-9]*$. 0 is therefore accepted (tail -n 0 is a no-op).
  mkdir -p "${_SB_HISTORY_FILE%/*}"
  echo 'one' > "$_SB_HISTORY_FILE"
  run _sb_cmd_history 0
  assert_success
}

@test "lazy dir: _sb_log_dispatch creates history dir on first call" {
  [[ ! -d "${_SB_HISTORY_FILE%/*}" ]]
  _SB_LAST_ORIGINAL='/agents'
  _sb_log_dispatch '__sb_dispatch /agents'
  [[ -d "${_SB_HISTORY_FILE%/*}" ]]
  [[ -s "$_SB_HISTORY_FILE" ]]
  # Logged line must contain the ORIGINAL form, not the dispatcher form.
  grep -q '/agents' "$_SB_HISTORY_FILE"
  ! grep -q '__sb_dispatch' "$_SB_HISTORY_FILE"
}

#fin
