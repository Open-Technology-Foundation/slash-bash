#!/usr/bin/env bats
#shellcheck shell=bats
# handlers_ollama.bats - /ollama handler regex + state.
# Validation regex: ^[A-Za-z0-9._:/-]+$ (slash-bash.bash:300)

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

@test "/ollama (no arg): turns on with default model" {
  _sb_cmd_ollama >"$TEST_HOME/out"
  [[ $_SB_OLLAMA == 1 ]]
  grep -q "ollama: on" "$TEST_HOME/out"
}

@test "/ollama off: disables" {
  _SB_OLLAMA=1
  _sb_cmd_ollama off >"$TEST_HOME/out"
  [[ $_SB_OLLAMA == 0 ]]
  grep -q "ollama: off" "$TEST_HOME/out"
}

@test "/ollama 0: also disables (alias)" {
  _SB_OLLAMA=1
  _sb_cmd_ollama 0 >/dev/null
  [[ $_SB_OLLAMA == 0 ]]
}

@test "/ollama false: also disables (alias)" {
  _SB_OLLAMA=1
  _sb_cmd_ollama false >/dev/null
  [[ $_SB_OLLAMA == 0 ]]
}

@test "/ollama llama3.1:8b: accepts colon+digit model name" {
  _sb_cmd_ollama 'llama3.1:8b' >"$TEST_HOME/out"
  [[ $_SB_OLLAMA == 1 ]]
  [[ $OLLAMA_MODEL == 'llama3.1:8b' ]]
  grep -q "model=llama3.1:8b" "$TEST_HOME/out"
}

@test "/ollama gpt-oss:20b: accepts hyphen+colon" {
  _sb_cmd_ollama 'gpt-oss:20b' >/dev/null
  [[ $OLLAMA_MODEL == 'gpt-oss:20b' ]]
}

@test "/ollama 'bad name': rejects whitespace" {
  run _sb_cmd_ollama 'bad name'
  assert_failure 1
  assert_output --partial "invalid model name"
}

@test "/ollama 'foo;rm': rejects shell metacharacter" {
  run _sb_cmd_ollama 'foo;rm'
  assert_failure 1
  assert_output --partial "invalid model name"
}

#fin
