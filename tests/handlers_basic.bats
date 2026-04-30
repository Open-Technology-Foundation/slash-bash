#!/usr/bin/env bats
#shellcheck shell=bats
# handlers_basic.bats - core handler logic.
#
# Covers: /help /agents /agent /models /model /maxtokens
# (kb, ollama, ask, systemprompt, history, sessions live in dedicated files.)

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
# /help and /?
# ----------------------------------------------------------------------------

@test "/help: prints command list" {
  run _sb_cmd_help
  assert_success
  assert_output --partial "Available slash commands"
  assert_output --partial "/agents"
  assert_output --partial "/ask"
  assert_output --partial "/status"
}

@test "/help: dispatched via /?" {
  run __sb_dispatch '/?'
  assert_success
  assert_output --partial "Available slash commands"
}

# ----------------------------------------------------------------------------
# /agents
# ----------------------------------------------------------------------------

@test "/agents --list: lists agents from claude.agent --list" {
  mock_claude_agent list-good
  run _sb_cmd_agents --list
  assert_success
  assert_output --partial "available agents:"
  assert_line "  - leet"
  assert_line "  - haiku"
  assert_line "  - opus"
  assert_output --partial "current: leet"
}

@test "/agents (no arg, non-TTY): rejects with 'requires interactive terminal'" {
  mock_claude_agent list-good
  run _sb_cmd_agents
  assert_failure 1
  assert_output --partial "requires an interactive terminal"
}

@test "/agents: missing claude.agent reports diagnostic" {
  disable_mocks
  # Hide claude.agent from PATH entirely.
  export PATH=/usr/bin:/bin
  run _sb_cmd_agents
  assert_failure 1
  assert_output --partial "claude.agent not in PATH"
}

@test "/agents: empty agent list reports 'no agents found'" {
  mock_claude_agent list-empty
  run _sb_cmd_agents
  assert_failure 1
  assert_output --partial "no agents found"
}

# ----------------------------------------------------------------------------
# /agent
# ----------------------------------------------------------------------------

@test "/agent (no arg): shows current agent" {
  run _sb_cmd_agent
  assert_success
  assert_output "current agent: leet"
}

@test "/agent <name>: case-insensitive exact match" {
  mock_claude_agent list-good
  run _sb_cmd_agent HAIKU
  assert_success
  assert_output --partial "agent set to: haiku"
}

@test "/agent <prefix>: prefix match resolves" {
  mock_claude_agent list-good
  run _sb_cmd_agent op
  assert_success
  assert_output --partial "agent set to: opus"
}

@test "/agent <unknown>: rejects with quoted diagnostic" {
  mock_claude_agent list-good
  run _sb_cmd_agent zorpius
  assert_failure 1
  assert_output --partial "unknown agent: 'zorpius'"
}

@test "/agent: state mutates _SB_AGENT" {
  mock_claude_agent list-good
  _sb_cmd_agent haiku >/dev/null
  [[ $_SB_AGENT == 'haiku' ]]
}

# ----------------------------------------------------------------------------
# /models
# ----------------------------------------------------------------------------

@test "/models --list: lists default model list" {
  run _sb_cmd_models --list
  assert_success
  assert_output --partial "available models:"
  assert_line "  - claude-opus-4-7"
  assert_line "  - claude-haiku-4-6"
  assert_output --partial "current: claude-opus-4-7"
}

@test "/models (no arg, non-TTY): rejects with 'requires interactive terminal'" {
  run _sb_cmd_models
  assert_failure 1
  assert_output --partial "requires an interactive terminal"
}

# ----------------------------------------------------------------------------
# /model
# ----------------------------------------------------------------------------

@test "/model (no arg): shows current model" {
  run _sb_cmd_model
  assert_success
  assert_output "current model: claude-opus-4-7"
}

@test "/model <name>: sets model (no validation - free-form)" {
  run _sb_cmd_model claude-sonnet-4-6
  assert_success
  assert_output --partial "model set to: claude-sonnet-4-6"
}

@test "/model: state mutates _SB_MODEL" {
  _sb_cmd_model haiku-test >/dev/null
  [[ $_SB_MODEL == 'haiku-test' ]]
}

# ----------------------------------------------------------------------------
# /maxtokens
# ----------------------------------------------------------------------------

@test "/maxtokens (no arg): prints current value" {
  run _sb_cmd_maxtokens
  assert_success
  assert_output "maxtokens: 32000"
}

@test "/maxtokens <positive int>: sets value" {
  run _sb_cmd_maxtokens 8192
  assert_success
  assert_output --partial "maxtokens set to: 8192"
}

@test "/maxtokens: rejects 0 (regex demands [1-9][0-9]*)" {
  run _sb_cmd_maxtokens 0
  assert_failure 1
  assert_output --partial "usage: /maxtokens"
}

@test "/maxtokens: rejects negative" {
  run _sb_cmd_maxtokens -5
  assert_failure 1
  assert_output --partial "usage: /maxtokens"
}

@test "/maxtokens: rejects non-integer" {
  run _sb_cmd_maxtokens abc
  assert_failure 1
  assert_output --partial "usage: /maxtokens"
}

@test "/maxtokens: state mutates _SB_MAX_TOKENS" {
  _sb_cmd_maxtokens 16384 >/dev/null
  [[ $_SB_MAX_TOKENS -eq 16384 ]]
}

#fin
