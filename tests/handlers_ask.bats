#!/usr/bin/env bats
#shellcheck shell=bats
# handlers_ask.bats - /ask handler argv shape, KB cfg append, env passthrough.

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

@test "/ask (no arg): usage error" {
  run _sb_cmd_ask
  assert_failure 1
  assert_output --partial "usage: /ask"
}

@test "/ask <text>: assembles claude.agent argv with -T <agent> --model <model>" {
  mock_claude_agent passthrough
  _sb_cmd_ask "hello world" >/dev/null
  # The mock's log captures one line per invocation - the assembled argv.
  run cat "$MOCK_CLAUDE_AGENT_LOG"
  assert_output --partial "-T leet"
  assert_output --partial "--model claude-opus-4-7"
  assert_output --partial "hello world"
}

@test "/ask: appends KB cfg to argv when _SB_KB is set and cfg exists" {
  make_fake_kb kb1
  mock_claude_agent passthrough
  _sb_cmd_kb kb1 >/dev/null
  _sb_cmd_ask "test" >/dev/null
  run cat "$MOCK_CLAUDE_AGENT_LOG"
  assert_output --partial "--append-system-prompt-file"
  assert_output --partial "$VECTORDBS/kb1/kb1.cfg"
}

@test "/ask: warns when _SB_KB set but cfg has been deleted" {
  make_fake_kb kb1
  mock_claude_agent passthrough
  _sb_cmd_kb kb1 >/dev/null
  rm -rf "$VECTORDBS/kb1"
  run _sb_cmd_ask "test"
  assert_success
  assert_output --partial "kb cfg missing"
}

@test "/ask: missing claude.agent reports diagnostic" {
  disable_mocks
  export PATH=/usr/bin:/bin
  run _sb_cmd_ask "anything"
  assert_failure 1
  assert_output --partial "claude.agent not in PATH"
}

@test "/ask: rc=0 adopts newest JSONL UUID when _SB_SESSION_UUID was empty" {
  mock_claude_agent passthrough
  make_fake_session_jsonl abc123 '{"type":"user"}'
  # /ask captures before_ask=$(date +%s.%N) at function entry and
  # _sb_pick_newest_uuid filters JSONLs against it (mt > before_ask) to
  # avoid hijacking a sibling shell's pre-existing file. Forge mtime to
  # ~10 s in the future so the fixture simulates "claude.agent wrote
  # this DURING the call" instead of "this was here before the call".
  local -- jsonl=$SB_CLAUDE_PROJECTS_DIR/${PWD//\//-}/abc123.jsonl
  touch -d "@$(( $(date +%s) + 10 ))" "$jsonl"
  _SB_SESSION_UUID=''
  _sb_cmd_ask 'hello' >/dev/null
  [[ $_SB_SESSION_UUID == abc123 ]]
}

@test "/ask: rc!=0 does NOT adopt newest UUID (race-prevention gate)" {
  mock_claude_agent fail
  make_fake_session_jsonl deadbeef '{"type":"user"}'
  _SB_SESSION_UUID=''
  # Direct call (not via run) so global mutation is observable; the
  # || : keeps bats `set -e` from aborting on the expected non-zero rc.
  _sb_cmd_ask 'hello' 2>/dev/null || :
  [[ -z $_SB_SESSION_UUID ]]
}

@test "/ask: rc=1 emits sibling-shlock hint" {
  mock_claude_agent fail
  run _sb_cmd_ask 'hello'
  assert_failure 1
  assert_output --partial 'claude.agent exited 1'
  assert_output --partial 'sibling slash-bash'
}

#fin
