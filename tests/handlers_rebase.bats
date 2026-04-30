#!/usr/bin/env bats
#shellcheck shell=bats
# handlers_rebase.bats - /rebase handler + _sb_pick_newest_uuid coverage.
#
# Mirrors handlers_ask.bats conventions: setup_test_env, enable_mocks,
# source_slash_bash, mock_claude_agent passthrough, make_fake_session_jsonl.

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
# _sb_pick_newest_uuid: pure helper, no slash-command machinery
# ----------------------------------------------------------------------------

@test "_sb_pick_newest_uuid: bad target var rejected" {
  run _sb_pick_newest_uuid '1bad' /tmp
  assert_failure 2
  assert_output --partial "internal: bad target var"
}

@test "_sb_pick_newest_uuid: missing dir leaves out var empty" {
  local out=initial
  _sb_pick_newest_uuid out "$TEST_HOME/does-not-exist"
  [[ -z $out ]]
}

@test "_sb_pick_newest_uuid: empty encoded-cwd dir leaves out var empty" {
  local enc_dir=$SB_CLAUDE_PROJECTS_DIR/${PWD//\//-}
  mkdir -p "$enc_dir"
  local out=initial
  _sb_pick_newest_uuid out "$PWD"
  [[ -z $out ]]
}

@test "_sb_pick_newest_uuid: picks newest JSONL by mtime" {
  make_fake_session_jsonl old-uuid '{"k":1}'
  sleep 1
  make_fake_session_jsonl new-uuid '{"k":2}'
  local out=''
  _sb_pick_newest_uuid out "$PWD"
  [[ $out == new-uuid ]]
}

@test "_sb_pick_newest_uuid: nullglob state preserved" {
  make_fake_session_jsonl u1 '{}'
  shopt -u nullglob
  local out=''
  _sb_pick_newest_uuid out "$PWD"
  ! shopt -q nullglob
  shopt -s nullglob
  _sb_pick_newest_uuid out "$PWD"
  shopt -q nullglob
}

# ----------------------------------------------------------------------------
# Documented limitation: cwd-encoding ambiguity
# The /->- encoding (slash-bash.bash:603, claude-sessions:53) loses
# information - '/foo/bar' and '/foo-bar' both encode to the same dir.
# These tests lock the current collision behaviour as a regression detector;
# they do NOT fix the ambiguity. Per slash-bash.bash header note, fixing it
# would require coordinating with Claude Code's own on-disk scheme.
# ----------------------------------------------------------------------------

@test "cwd-encoding: '/foo/bar' and '/foo-bar' collide under /->- replacement" {
  local a='/foo/bar' b='/foo-bar'
  [[ ${a//\//-} == "${b//\//-}" ]]
}

@test "_sb_pick_newest_uuid: collision case yields same UUID for both forms (known limitation)" {
  # Both '/foo/bar' and '/foo-bar' resolve to the same encoded dir, so a
  # JSONL written under one logical cwd is visible to the other. The picker
  # has no way to disambiguate - it picks newest by mtime regardless of
  # which logical cwd "owned" the file. This locks current behaviour as a
  # regression detector, not as the desired contract.
  local shared_dir=$SB_CLAUDE_PROJECTS_DIR/-foo-bar
  mkdir -p "$shared_dir"
  printf '%s\n' '{}' > "$shared_dir/older-uuid.jsonl"
  sleep 1
  printf '%s\n' '{}' > "$shared_dir/newer-uuid.jsonl"
  local out_a='' out_b=''
  _sb_pick_newest_uuid out_a /foo/bar
  _sb_pick_newest_uuid out_b /foo-bar
  [[ $out_a == newer-uuid ]]
  [[ $out_b == newer-uuid ]]
  [[ $out_a == "$out_b" ]]
}

# ----------------------------------------------------------------------------
# /rebase: handler-level coverage
# ----------------------------------------------------------------------------

@test "/rebase --bogus: usage error" {
  run _sb_cmd_rebase --bogus
  assert_failure 1
  assert_output --partial "usage: /rebase"
}

@test "/rebase: same cwd as binding -> already-bound no-op" {
  _SB_SESSION_CWD=$PWD
  run _sb_cmd_rebase
  assert_success
  assert_output --partial "already bound to"
}

@test "/rebase: fresh cwd, no prior JSONL -> empty UUID, 'starts fresh'" {
  local fresh=$TEST_HOME/fresh
  mkdir -p "$fresh"
  _SB_SESSION_CWD=$TEST_HOME    # different from $fresh
  cd "$fresh"
  run _sb_cmd_rebase
  assert_success
  assert_output --partial "starts fresh"
}

@test "/rebase: fresh cwd with prior JSONL -> adopts that UUID" {
  local fresh=$TEST_HOME/with-prior
  mkdir -p "$fresh"
  _SB_SESSION_CWD=$TEST_HOME
  cd "$fresh"
  # Build a JSONL under the *new* cwd's encoded dir.
  local enc_dir=$SB_CLAUDE_PROJECTS_DIR/${PWD//\//-}
  mkdir -p "$enc_dir"
  printf '%s\n' '{}' > "$enc_dir/abcd-1234.jsonl"
  _sb_cmd_rebase
  [[ $_SB_SESSION_UUID == abcd-1234 ]]
  [[ $_SB_SESSION_CWD == "$fresh" ]]
}

@test "/rebase: recent /ask, non-TTY -> rc=1 with --force hint" {
  _SB_SESSION_CWD=$TEST_HOME    # different from $PWD
  _SB_SESSION_UUID=existing-uuid
  _SB_SESSION_LAST_ASK=${EPOCHSECONDS:-$(date +%s)}
  run _sb_cmd_rebase
  assert_failure 1
  assert_output --partial "non-interactive"
  assert_output --partial "--force"
}

@test "/rebase --force: recent /ask is bypassed" {
  local fresh=$TEST_HOME/forced
  mkdir -p "$fresh"
  _SB_SESSION_CWD=$TEST_HOME
  _SB_SESSION_UUID=existing-uuid
  _SB_SESSION_LAST_ASK=${EPOCHSECONDS:-$(date +%s)}
  cd "$fresh"
  run _sb_cmd_rebase --force
  assert_success
  assert_output --partial "rebased to"
  # state mutation is not visible through `run`; verify directly:
  _sb_cmd_rebase --force >/dev/null
  [[ $_SB_SESSION_CWD == "$fresh" ]]
  [[ $_SB_SESSION_LAST_ASK -eq 0 ]]
}

@test "/ask after /rebase: argv contains --resume <uuid>; first /ask post-rebase adopts new JSONL" {
  mock_claude_agent passthrough
  local fresh=$TEST_HOME/post-rebase
  mkdir -p "$fresh"
  _SB_SESSION_CWD=$TEST_HOME
  cd "$fresh"
  # Pre-stage a JSONL under the new cwd so /rebase adopts it.
  local enc_dir=$SB_CLAUDE_PROJECTS_DIR/${PWD//\//-}
  mkdir -p "$enc_dir"
  printf '%s\n' '{}' > "$enc_dir/resume-uuid.jsonl"
  _sb_cmd_rebase --force >/dev/null
  [[ $_SB_SESSION_UUID == resume-uuid ]]
  _sb_cmd_ask "post-rebase ping" >/dev/null
  run cat "$MOCK_CLAUDE_AGENT_LOG"
  assert_output --partial "--resume resume-uuid"
}

#fin
