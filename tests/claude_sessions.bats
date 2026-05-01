#!/usr/bin/env bats
#shellcheck shell=bats
# claude_sessions.bats - standalone claude-sessions CLI.
# Output format (TSV: mtime\tuuid\ttitle), exit codes 0/2/3/18/22, title fallback chain.

load test_helper

setup() {
  setup_test_env
}

teardown() {
  teardown_test_env
}

# Helper: invoke claude-sessions with PWD redirected so SB_CLAUDE_PROJECTS_DIR
# decoding aligns with the temp-home harness.
_run_sessions() {
  local -- session_pwd=$TEST_HOME
  cd "$session_pwd"
  "$PROJECT_DIR/claude-sessions" "$@"
}

@test "claude-sessions: --version exits 0" {
  run "$PROJECT_DIR/claude-sessions" --version
  assert_success
  assert_output --partial "claude-sessions"
  assert_output --partial "1.0.0"
}

@test "claude-sessions: --help exits 0" {
  run "$PROJECT_DIR/claude-sessions" --help
  assert_success
  assert_output --partial "TSV"
  assert_output --partial "Exit codes:"
}

@test "claude-sessions: invalid option exits 22" {
  run "$PROJECT_DIR/claude-sessions" --bogus
  assert_failure 22
  assert_output --partial "invalid option"
}

@test "claude-sessions: unexpected argument exits 2" {
  run "$PROJECT_DIR/claude-sessions" extra-arg
  assert_failure 2
  assert_output --partial "unexpected argument"
}

@test "claude-sessions: missing project dir exits 3" {
  cd "$TEST_HOME"
  run "$PROJECT_DIR/claude-sessions"
  assert_failure 3
  assert_output --partial "no sessions for"
}

@test "claude-sessions: missing jq exits 18" {
  hide_jq
  cd "$TEST_HOME"
  # Ensure the project dir exists so we get past the dir-check and hit jq.
  mkdir -p "$SB_CLAUDE_PROJECTS_DIR/${PWD//\//-}"
  printf '{}\n' > "$SB_CLAUDE_PROJECTS_DIR/${PWD//\//-}/00.jsonl"
  run "$PROJECT_DIR/claude-sessions"
  assert_failure 18
  assert_output --partial "jq not in PATH"
}

@test "claude-sessions: TSV row has 3 tab-separated fields with mtime format" {
  cd "$TEST_HOME"
  make_fake_session_jsonl 'aaa-111' \
    '{"type":"user","message":{"content":"hello world"}}'
  run "$PROJECT_DIR/claude-sessions"
  assert_success
  # 1 row, 3 fields.
  [[ $(printf '%s\n' "$output" | awk -F'\t' '{print NF; exit}') -eq 3 ]]
  # mtime field matches YYYY-MM-DD HH:MM:SS.
  [[ $output =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}$'\t' ]]
  # uuid + title visible.
  assert_output --partial $'\taaa-111\t'
  assert_output --partial 'hello world'
}

@test "claude-sessions: title fallback chain (custom-title > user msg > <untitled>)" {
  cd "$TEST_HOME"
  # Session 1: custom-title wins.
  make_fake_session_jsonl 'with-title' \
    '{"type":"user","message":{"content":"early msg"}}'
  make_fake_session_jsonl 'with-title' \
    '{"type":"custom-title","customTitle":"My Title"}'
  # Session 2: no custom-title, user message used.
  make_fake_session_jsonl 'no-title' \
    '{"type":"user","message":{"content":"first user msg"}}'
  # Session 3: empty - fallback to <untitled>.
  make_fake_session_jsonl 'empty-session' '{}'
  run "$PROJECT_DIR/claude-sessions"
  assert_success
  assert_output --partial $'\twith-title\tMy Title'
  assert_output --partial $'\tno-title\tfirst user msg'
  assert_output --partial $'\tempty-session\t<untitled>'
}

#fin
