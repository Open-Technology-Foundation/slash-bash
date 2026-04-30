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

#fin
