#!/usr/bin/env bats
#shellcheck shell=bats
# source_invariants.bats - source-time contracts.
#
# Contracts covered (REQUIREMENTS.md / AUDIT-BASH.md):
#   AI-3.3 - source-time purity (no fs writes)
#   AI-3.4 - source-detection guard (BCS0407)
#   FR-2.2.1 - default-value preservation when no env vars set
#   Lines 30-40 - missing bash-preexec.sh produces named diagnostic
#   Interactive guard at line 23 - non-interactive sourcing is a no-op

load test_helper

setup() {
  setup_test_env
}

teardown() {
  teardown_test_env
}

# ----------------------------------------------------------------------------
# AI-3.4 - source-detection guard
# ----------------------------------------------------------------------------

@test "source-detection: bash slash-bash.bash exits 1 with diagnostic" {
  run bash "$PROJECT_DIR/slash-bash.bash"
  assert_failure 1
  assert_output --partial "must be sourced, not executed"
}

# ----------------------------------------------------------------------------
# Interactive guard - non-interactive source is a no-op
# ----------------------------------------------------------------------------

@test "interactive guard: non-interactive source defines no _sb_cmd_*" {
  # Use the *unmodified* library here (not source_slash_bash) so the guard
  # actually fires. A clean non-interactive bash -c source must succeed but
  # install no handlers - so `type -t _sb_cmd_help` exits 1 with empty output.
  run bash -c "source '$PROJECT_DIR/slash-bash.bash' && type -t _sb_cmd_help 2>/dev/null"
  assert_failure 1
  assert_output ''
}

@test "interactive guard: non-interactive source returns 0 quietly" {
  run bash -c "source '$PROJECT_DIR/slash-bash.bash'"
  assert_success
  refute_output --partial "must be sourced"
}

# ----------------------------------------------------------------------------
# Lines 30-40 - missing bash-preexec.sh
# ----------------------------------------------------------------------------

@test "missing bash-preexec: named diagnostic + return 1" {
  # Copy the lib to a temp dir without bash-preexec.sh, so the existence
  # check fails and the diagnostic prints.
  cp "$PROJECT_DIR/slash-bash.bash" "$TEST_HOME/lib.bash"
  # Source with -i flag spoofed by removing the interactive guard line in a
  # subshell-friendly way. The cleanest path is to flip the guard manually.
  sed -i '/\[\[ \$- == \*i\* \]\] || return 0/d' "$TEST_HOME/lib.bash"
  run bash -c "source '$TEST_HOME/lib.bash'"
  assert_failure 1
  assert_output --partial "missing dependency"
  assert_output --partial "bash-preexec.sh"
}

# ----------------------------------------------------------------------------
# AI-3.3 - source-time purity (no fs writes)
# ----------------------------------------------------------------------------

@test "source-time purity: TEST_HOME unchanged after source" {
  # Snapshot HOME, source the lib via the harness shim, then verify no new
  # files were created. The shim mirrors what an interactive source would do
  # (minus the chord-trick keybindings, which can't take effect in non-TTY).
  source_slash_bash
  local -i count
  count=$(find "$TEST_HOME" -type f 2>/dev/null | wc -l)
  [[ $count -eq 0 ]]
}

@test "source-time purity: history dir not created until first log write" {
  source_slash_bash
  [[ ! -d "$TEST_HOME/.cache/slash-bash" ]]
  # Now trigger a log write and verify the dir gets created lazily.
  _SB_LAST_ORIGINAL='/help'
  _sb_log_dispatch '__sb_dispatch /help'
  [[ -d "$TEST_HOME/.cache/slash-bash" ]]
  [[ -f "$_SB_HISTORY_FILE" ]]
}

# ----------------------------------------------------------------------------
# FR-2.2.1 - default values when no env vars set
# ----------------------------------------------------------------------------

@test "defaults: _SB_AGENT == 'leet' when SB_AGENT unset" {
  source_slash_bash
  [[ $_SB_AGENT == 'leet' ]]
}

@test "defaults: _SB_MODEL == 'claude-opus-4-7' when SB_MODEL unset" {
  source_slash_bash
  [[ $_SB_MODEL == 'claude-opus-4-7' ]]
}

@test "defaults: _SB_MAX_TOKENS == 32000, _SB_OLLAMA == 0" {
  source_slash_bash
  [[ $_SB_MAX_TOKENS == 32000 ]]
  [[ $_SB_OLLAMA == 0 ]]
}

@test "defaults: _SB_KB_ROOT respects VECTORDBS env var" {
  source_slash_bash
  [[ $_SB_KB_ROOT == "$VECTORDBS" ]]
}

# ----------------------------------------------------------------------------
# FR-2.2.1 - SESSION env-var seeds (round-trip restore from /status dump)
# ----------------------------------------------------------------------------

@test "defaults: _SB_SESSION_CWD respects SB_SESSION_CWD env var" {
  export SB_SESSION_CWD=/tmp/round-trip-cwd
  source_slash_bash
  [[ $_SB_SESSION_CWD == /tmp/round-trip-cwd ]]
}

@test "defaults: _SB_SESSION_UUID respects SB_SESSION_UUID env var" {
  export SB_SESSION_UUID='abc-123-uuid'
  source_slash_bash
  [[ $_SB_SESSION_UUID == 'abc-123-uuid' ]]
}

@test "defaults: _SB_SESSION_LAST_ASK respects SB_SESSION_LAST_ASK env var" {
  export SB_SESSION_LAST_ASK=12345
  source_slash_bash
  (( _SB_SESSION_LAST_ASK == 12345 ))
}

@test "defaults: _SB_SESSION_LAST_ASK non-integer coerces to 0 via -ig" {
  # The -i attribute parses the assignment as an arithmetic expression. A
  # hostile non-numeric string evaluates to 0 (unset names = 0 in arithmetic),
  # never as shell eval. Verifies the trust-but-verify model on this env var.
  export SB_SESSION_LAST_ASK='not-a-number'
  source_slash_bash
  (( _SB_SESSION_LAST_ASK == 0 ))
}

@test "round-trip: /status dump replays _SB_SESSION_* via env vars" {
  source_slash_bash
  _SB_SESSION_CWD='/tmp/round-trip-test'
  _SB_SESSION_UUID='aaaa-bbbb-cccc-dddd'
  _SB_SESSION_LAST_ASK=99999
  _SB_DIRTY_WINDOW=600
  local -- captured
  captured=$(_sb_cmd_status)
  # Confirm dump contains the four expected lines. Values are @Q-quoted
  # by _sb_cmd_status, so integers appear as '99999' / '600'.
  [[ $captured == *"export SB_SESSION_CWD='/tmp/round-trip-test'"* ]]
  [[ $captured == *"export SB_SESSION_UUID='aaaa-bbbb-cccc-dddd'"* ]]
  [[ $captured == *"export SB_SESSION_LAST_ASK='99999'"* ]]
  [[ $captured == *"export SB_DIRTY_WINDOW='600'"* ]]
  # Replay in a fresh bash -c (mirrors `source save.sh; slash-bash`). Cannot
  # re-source in the current shell - the lib's `declare -gr _RED=...` etc.
  # would conflict with the readonly globals from the first source.
  run bash -c '
    eval "$1"
    # shellcheck source=/dev/null
    source "$2/bash-preexec.sh" 2>/dev/null
    # shellcheck source=/dev/null
    source <(awk "
      /^\[\[ \\\$- == \\*i\\* \]\] \|\| return 0/ { next }
      /^# Vendor: bash-preexec.sh in the same/, /^unset -v _sb_preexec/ { next }
      { print }
    " "$2/slash-bash.bash") 2>/dev/null
    printf "%s|%s|%s|%s\n" \
      "$_SB_SESSION_CWD" "$_SB_SESSION_UUID" \
      "$_SB_SESSION_LAST_ASK" "$_SB_DIRTY_WINDOW"
  ' _ "$captured" "$PROJECT_DIR"
  assert_output --partial '/tmp/round-trip-test|aaaa-bbbb-cccc-dddd|99999|600'
}

# ----------------------------------------------------------------------------
# AI-3.2 - dual-keymap binding (emacs + vi-insert) MUST NOT be collapsed.
# ----------------------------------------------------------------------------

@test "dual-keymap: lib registers chord on both emacs and vi-insert" {
  # The chord trick requires a real TTY to take effect (E2E suite covers
  # runtime), but the source must contain both bindings or vi-mode users
  # break. Static check.
  run grep -E "^bind -m emacs +-x +'\"\\\\C-xs\":" "$PROJECT_DIR/slash-bash.bash"
  assert_success
  run grep -E "^bind -m vi-insert +-x +'\"\\\\C-xs\":" "$PROJECT_DIR/slash-bash.bash"
  assert_success
  run grep -E "^bind -m emacs +'\"\\\\C-m\":" "$PROJECT_DIR/slash-bash.bash"
  assert_success
  run grep -E "^bind -m vi-insert +'\"\\\\C-m\":" "$PROJECT_DIR/slash-bash.bash"
  assert_success
}

#fin
