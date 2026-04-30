#!/usr/bin/env bats
#shellcheck shell=bats
# handlers_sessions.bats - /sessions thin wrapper around claude-sessions script.

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

@test "/sessions: missing script reports diagnostic + return 18" {
  # Drive the missing-script error path via the SB_CLAUDE_SESSIONS_BIN
  # override (handlers.d/_sessions.bash). With the registry refactor,
  # BASH_SOURCE[0] inside handler files resolves to the real on-disk
  # path so the prior /dev/fd-quirk no longer naturally triggers the
  # not-found branch.
  SB_CLAUDE_SESSIONS_BIN=/nonexistent/claude-sessions \
    run _sb_cmd_sessions
  assert_failure 18
  assert_output --partial "claude-sessions not found"
}

@test "/sessions: forwards --version to the script" {
  # Override the BASH_SOURCE-derived path by re-defining the wrapper with a
  # known script location.
  _sb_cmd_sessions() {
    local -- script=$PROJECT_DIR/claude-sessions
    if [[ ! -x $script ]]; then
      >&2 printf 'claude-sessions not found or not executable: %s\n' "$script"
      return 18
    fi
    "$script" "$@"
  }
  run _sb_cmd_sessions --version
  assert_success
  assert_output --partial "claude-sessions"
  assert_output --partial "1.0.0"
}

@test "/sessions: missing-dir path returns 3 from the script" {
  # Same redefinition trick as above; this time exercise the no-projects-dir
  # path of claude-sessions itself.
  _sb_cmd_sessions() {
    local -- script=$PROJECT_DIR/claude-sessions
    [[ -x $script ]] || return 18
    "$script" "$@"
  }
  # SB_CLAUDE_PROJECTS_DIR points at $TEST_HOME/projects which does not exist
  # (we never made any session JSONLs).
  run _sb_cmd_sessions
  assert_failure 3
  assert_output --partial "no sessions for"
}

#fin
