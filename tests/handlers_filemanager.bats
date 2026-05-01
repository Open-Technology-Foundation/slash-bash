#!/usr/bin/env bats
#shellcheck shell=bats
# handlers_filemanager.bats - /filemanager + /fm: option parsing,
# directory validation, dry-run path, missing-display / missing-xdg-open
# diagnostics, and detached-launch invocation form.

load test_helper

setup() {
  setup_test_env
  enable_mocks
  source_slash_bash
  # Pretend we have a graphical session so the no-display guard does not
  # fire. Individual tests that target the guard will unset these.
  export DISPLAY=':0'
  export MOCK_XDG_OPEN_LOG="$TEST_HOME/xdg-open.log"
  : > "$MOCK_XDG_OPEN_LOG"
}

teardown() {
  disable_mocks
  teardown_test_env
}

# ----------------------------------------------------------------------------
# Help and registration
# ----------------------------------------------------------------------------

@test "/filemanager --help: prints usage and exits 0" {
  run _sb_cmd_filemanager --help
  assert_success
  assert_output --partial '/filemanager'
  assert_output --partial '<dirpath>'
  assert_output --partial '--dry-run'
}

@test "/filemanager -h: same as --help" {
  run _sb_cmd_filemanager -h
  assert_success
  assert_output --partial '<dirpath>'
}

@test "registry: /filemanager and /fm both route to _sb_cmd_filemanager" {
  [[ ${_SB_HANDLERS[/filemanager]} == _sb_cmd_filemanager ]]
  [[ ${_SB_HANDLERS[/fm]}          == _sb_cmd_filemanager ]]
}

@test "registry: _SB_HELP entry only on canonical alias /filemanager" {
  [[ -v _SB_HELP[/filemanager] ]]
  [[ ! -v _SB_HELP[/fm] ]]
}

# ----------------------------------------------------------------------------
# Argument validation
# ----------------------------------------------------------------------------

@test "/filemanager <missing-dir>: rejected with 'not a directory'" {
  run _sb_cmd_filemanager "$TEST_HOME/does-not-exist"
  assert_failure 1
  assert_output --partial 'not a directory'
}

@test "/filemanager --bogus: unknown option rejected with rc=22" {
  run _sb_cmd_filemanager --bogus
  assert_failure 22
  assert_output --partial 'unknown option'
}

# ----------------------------------------------------------------------------
# Environment guards
# ----------------------------------------------------------------------------

@test "/filemanager: no DISPLAY/WAYLAND_DISPLAY -> diagnostic + rc=1" {
  unset DISPLAY WAYLAND_DISPLAY
  run _sb_cmd_filemanager /tmp
  assert_failure 1
  assert_output --partial 'no display detected'
}

@test "/filemanager: WAYLAND_DISPLAY alone is enough to pass the guard" {
  unset DISPLAY
  export WAYLAND_DISPLAY='wayland-0'
  run _sb_cmd_filemanager '-n /tmp'
  assert_success
  assert_output --partial 'would run: xdg-open /tmp'
}

@test "/filemanager: missing xdg-open -> diagnostic + rc=1" {
  # /usr/bin has the real xdg-open on this dev host, so a /usr/bin-only
  # PATH would NOT exercise the missing-xdg-open branch. Point PATH at
  # an empty dir we own; bash builtins (command -v, [[ -d, printf) are
  # in-process and need no PATH entries.
  local -- empty=$TEST_HOME/empty-bin
  mkdir -p "$empty"
  PATH=$empty run _sb_cmd_filemanager /tmp
  assert_failure 1
  assert_output --partial 'xdg-open not in PATH'
}

# ----------------------------------------------------------------------------
# Dry-run path
# ----------------------------------------------------------------------------

@test "/filemanager -n: dry-run defaults to PWD when path omitted" {
  cd "$TEST_HOME"
  run _sb_cmd_filemanager -n
  assert_success
  assert_output --partial "would run: xdg-open $TEST_HOME"
  # Mock log MUST be empty - dry-run does not invoke xdg-open.
  [[ ! -s $MOCK_XDG_OPEN_LOG ]]
}

@test "/filemanager -n <dir>: dry-run honours explicit path" {
  # __sb_dispatch hands the handler a single $1 with the whole arg
  # string; mirror that in tests so option+path parsing matches the
  # real call shape.
  run _sb_cmd_filemanager '-n /tmp'
  assert_success
  assert_output --partial 'would run: xdg-open /tmp'
  [[ ! -s $MOCK_XDG_OPEN_LOG ]]
}

@test "/filemanager --dry-run <dir>: long-form accepted" {
  run _sb_cmd_filemanager '--dry-run /tmp'
  assert_success
  assert_output --partial 'would run: xdg-open /tmp'
}

# ----------------------------------------------------------------------------
# Detached launch (mock-recorded)
# ----------------------------------------------------------------------------

@test "/filemanager <dir>: invokes xdg-open exactly once with the path" {
  run _sb_cmd_filemanager '/tmp'
  assert_success
  assert_output --partial 'launched file manager at: /tmp'
  # Background launch + disown means the mock may write asynchronously;
  # poll briefly for the log entry to land.
  local -i tries=0
  while ((tries < 20)) && [[ ! -s $MOCK_XDG_OPEN_LOG ]]; do
    sleep 0.05
    tries+=1
  done
  [[ -s $MOCK_XDG_OPEN_LOG ]]
  run cat "$MOCK_XDG_OPEN_LOG"
  assert_output '/tmp'
}

@test "/filemanager (no args): defaults to PWD" {
  cd "$TEST_HOME"
  run _sb_cmd_filemanager
  assert_success
  assert_output --partial "launched file manager at: $TEST_HOME"
}

# ----------------------------------------------------------------------------
# Option terminator
# ----------------------------------------------------------------------------

@test "/filemanager --: subsequent args treated as path even if they start with -" {
  # Make a dir whose name starts with a dash to exercise the -- guard.
  mkdir -p "$TEST_HOME/-weirddir"
  cd "$TEST_HOME"
  run _sb_cmd_filemanager '-n -- -weirddir'
  assert_success
  assert_output --partial 'would run: xdg-open'
  assert_output --partial '-weirddir'
}

#fin
