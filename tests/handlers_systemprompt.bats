#!/usr/bin/env bats
#shellcheck shell=bats
# handlers_systemprompt.bats - /systemprompt handler.
# Covers: jq presence, agent resolution chain, {{spacetime}} substitution,
# AGENTS_JSON env override, missing-systemprompt edge case.

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

@test "/systemprompt: missing jq reports diagnostic" {
  mock_claude_agent list-good
  hide_jq
  run _sb_cmd_systemprompt leet
  assert_failure 1
  assert_output --partial "jq not in PATH"
}

@test "/systemprompt: missing claude.agent reports diagnostic" {
  disable_mocks
  export PATH=/usr/bin:/bin
  run _sb_cmd_systemprompt leet
  assert_failure 1
  assert_output --partial "claude.agent not in PATH"
}

@test "/systemprompt leet: resolves and prints prompt" {
  mock_claude_agent list-good
  run _sb_cmd_systemprompt leet
  assert_success
  assert_output --partial "# agent: leet -"
  assert_output --partial "# spacetime:"
  assert_output --partial "You are leet"
}

@test "/systemprompt: substitutes {{spacetime}} marker" {
  mock_claude_agent list-good
  run _sb_cmd_systemprompt leet
  assert_success
  # Source template has 'Today is {{spacetime}}.' - after substitution the
  # marker must be gone and replaced with a date-format header.
  refute_output --partial "{{spacetime}}"
  assert_output --partial "Today is "
}

@test "/systemprompt (no arg): defaults to current _SB_AGENT" {
  mock_claude_agent list-good
  _SB_AGENT=haiku
  run _sb_cmd_systemprompt
  assert_success
  assert_output --partial "# agent: haiku"
  assert_output --partial "haiku at"
}

@test "/systemprompt: unknown agent rejected with quoted diagnostic" {
  mock_claude_agent list-good
  run _sb_cmd_systemprompt nosuch
  assert_failure 1
  assert_output --partial "unknown agent: 'nosuch'"
}

@test "/systemprompt: agent without systemprompt key reported" {
  # Override AGENTS_JSON with one that has the agent in agents-list but no
  # systemprompt field. The mock returns 'leet/haiku/opus' but Agents.json
  # only has leet/haiku/noprompt. To trigger the no-systemprompt path we
  # bypass agent-list resolution by adding 'noprompt' to the live list.
  mock_claude_agent list-good
  _SB_AGENT_LIST+=(noprompt)
  run _sb_cmd_systemprompt noprompt
  assert_failure 1
  assert_output --partial "agent has no systemprompt"
}

@test "/systemprompt: AGENTS_JSON unset falls through to claude.agent-derived path" {
  # Verifies the AGENTS_JSON->_sb_default_agents_json fallback chain.
  # Mock claude.agent is in PATH (so _sb_load_agent_list succeeds), but
  # _sb_default_agents_json resolves to $MOCK_DIR/Agents.json - which
  # does not exist. _sb_agent_key returns 1, key stays empty, and the
  # caller emits the canonical "agent not found in Agents.json" error.
  # If the fallback regressed (e.g. helper returned wrong path or
  # non-empty when claude.agent missing), this test would either crash
  # or surface a different error.
  unset AGENTS_JSON
  mock_claude_agent list-good
  _sb_load_agent_list
  run _sb_cmd_systemprompt leet
  assert_failure 1
  assert_output --partial "agent not found in Agents.json: 'leet'"
}

#fin
