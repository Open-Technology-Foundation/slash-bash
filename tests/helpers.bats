#!/usr/bin/env bats
#shellcheck shell=bats
# helpers.bats - internal helpers (_sb_iso_now, _sb_spacetime,
# _sb_resolve_agent_name, _sb_agent_key, _sb_ensure_history_dir).

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

@test "iso_now: returns ISO-8601 with timezone" {
  run _sb_iso_now
  assert_success
  # Expect format like 2026-04-27T22:30:00+0700 (GNU date -Iseconds).
  [[ $output =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2} ]]
}

@test "spacetime: returns 'Weekday YYYY-MM-DD HH:00 +ZZZZ <tz>' format" {
  run _sb_spacetime
  assert_success
  # Six tokens separated by whitespace: weekday, date, hour, tzoffset, tzname.
  [[ $output =~ ^[A-Z][a-z]+\ [0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:00\ [+-][0-9]{4}\ .+ ]]
}

@test "spacetime: respects TZ env var when set" {
  TZ=UTC run _sb_spacetime
  assert_success
  # Last token is the tzname; under TZ=UTC it should equal 'UTC'.
  [[ $output == *UTC ]]
}

@test "resolve_agent_name: case-insensitive exact match wins over prefix" {
  mock_claude_agent list-good
  _sb_load_agent_list
  run _sb_resolve_agent_name LEET
  assert_success
  assert_output 'leet'
}

@test "resolve_agent_name: prefix fallback when no exact match" {
  mock_claude_agent list-good
  _sb_load_agent_list
  run _sb_resolve_agent_name op
  assert_success
  assert_output 'opus'
}

@test "agent_key: looks up Agents.json key by short-name (case-insensitive)" {
  run _sb_agent_key haiku
  assert_success
  assert_output --partial 'haiku - poetry assistant'
}

# ----------------------------------------------------------------------------
# _sb_default_agents_json - derives Agents.json path from claude.agent in
# PATH; consumers fall back to it when AGENTS_JSON is unset.
# ----------------------------------------------------------------------------

@test "default_agents_json: derives path from claude.agent in PATH" {
  # enable_mocks puts $MOCK_DIR/claude.agent first in PATH; realpath
  # resolves to the regular file, so the derived path is sibling to it.
  run _sb_default_agents_json
  assert_success
  assert_output "$MOCK_DIR/Agents.json"
}

@test "default_agents_json: empty when claude.agent missing from PATH" {
  disable_mocks
  # Sanitise PATH so the real /usr/local/bin/claude.agent (deployed on
  # this dev host via .symlink) isn't found either - we want the genuine
  # "not in PATH" branch to fire.
  PATH=/usr/bin:/bin run _sb_default_agents_json
  assert_success
  [[ -z $output ]] || { printf 'expected empty, got: %s\n' "$output" >&2; false; }
}

@test "default_agents_json: empty exit 0 (callers chain via :- with no error)" {
  disable_mocks
  PATH=/usr/bin:/bin
  # Idiomatic call site: ${AGENTS_JSON:-$(_sb_default_agents_json)}.
  # Helper must succeed even when it returns nothing, otherwise set -e
  # in callers would explode on the empty default.
  local -- result
  result=$(_sb_default_agents_json)
  (( $? == 0 ))
  [[ -z $result ]]
}

#fin
