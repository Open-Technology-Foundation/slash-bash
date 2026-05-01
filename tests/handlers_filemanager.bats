#!/usr/bin/env bats
#shellcheck shell=bats
# handlers_filemanager.bats - /filemanager + /fm: option parsing,
# directory validation, mode auto-detection (GUI vs TUI), explicit
# mode flags, environment-driven candidate override, dry-run, and
# launch invocation forms.

load test_helper

setup() {
  setup_test_env
  enable_mocks
  source_slash_bash
  # Default: pretend we have a graphical session so auto-detect picks
  # GUI mode. Tests that target TUI fallback unset these.
  export DISPLAY=':0'
  export MOCK_XDG_OPEN_LOG="$TEST_HOME/xdg-open.log"
  export MOCK_MC_LOG="$TEST_HOME/mc.log"
  : > "$MOCK_XDG_OPEN_LOG"
  : > "$MOCK_MC_LOG"
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
  assert_output --partial '--gui'
  assert_output --partial '--tui'
  assert_output --partial 'SB_FILEMANAGER'
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

@test "/filemanager -g -t: mutually exclusive flags rejected with rc=22" {
  run _sb_cmd_filemanager '-g -t'
  assert_failure 22
  assert_output --partial 'mutually exclusive'
}

# ----------------------------------------------------------------------------
# Mode auto-detection
# ----------------------------------------------------------------------------

@test "auto-detect: DISPLAY set -> GUI mode (xdg-open)" {
  run _sb_cmd_filemanager '-n /tmp'
  assert_success
  assert_output --partial 'mode=gui'
  assert_output --partial 'xdg-open'
}

@test "auto-detect: WAYLAND_DISPLAY alone -> GUI mode" {
  unset DISPLAY
  export WAYLAND_DISPLAY='wayland-0'
  run _sb_cmd_filemanager '-n /tmp'
  assert_success
  assert_output --partial 'mode=gui'
}

@test "auto-detect: no display -> TUI mode falls back to mc" {
  unset DISPLAY WAYLAND_DISPLAY
  run _sb_cmd_filemanager '-n /tmp'
  assert_success
  assert_output --partial 'mode=tui'
  assert_output --partial 'mc'
}

# ----------------------------------------------------------------------------
# Explicit mode flags
# ----------------------------------------------------------------------------

@test "-t/--tui: forces TUI even when DISPLAY is set" {
  # DISPLAY=:0 from setup; auto-detect would pick GUI.
  run _sb_cmd_filemanager '-t -n /tmp'
  assert_success
  assert_output --partial 'mode=tui'
  assert_output --partial 'mc'
}

@test "-g/--gui: forces GUI even when display is absent" {
  unset DISPLAY WAYLAND_DISPLAY
  run _sb_cmd_filemanager '-g -n /tmp'
  assert_success
  assert_output --partial 'mode=gui'
  assert_output --partial 'xdg-open'
}

# ----------------------------------------------------------------------------
# Mode resolution failures
# ----------------------------------------------------------------------------

@test "GUI mode failure: missing xdg-open -> 'GUI file manager unavailable'" {
  # Empty PATH so neither xdg-open nor mc resolve.
  local -- empty=$TEST_HOME/empty-bin
  mkdir -p "$empty"
  PATH=$empty run _sb_cmd_filemanager /tmp
  assert_failure 1
  assert_output --partial 'GUI file manager unavailable'
}

@test "TUI mode failure: no candidates found -> diagnostic enumerates probe list" {
  unset DISPLAY WAYLAND_DISPLAY SB_FILEMANAGER
  local -- empty=$TEST_HOME/empty-bin
  mkdir -p "$empty"
  PATH=$empty run _sb_cmd_filemanager /tmp
  assert_failure 1
  assert_output --partial 'no TUI file manager found'
  # Diagnostic must list what was searched so users can install one.
  assert_output --partial 'mc'
  assert_output --partial 'ranger'
}

# ----------------------------------------------------------------------------
# SB_FILEMANAGER env override
# ----------------------------------------------------------------------------

@test "SB_FILEMANAGER: explicit env preempts the default candidate order" {
  unset DISPLAY WAYLAND_DISPLAY
  # Set SB_FILEMANAGER to a non-existent binary; helper should skip it
  # (command -v fails) and continue with mc. This exercises the loop's
  # "empty / not-in-PATH skip" path.
  export SB_FILEMANAGER=zz-nonexistent-fm
  run _sb_cmd_filemanager '-n /tmp'
  assert_success
  assert_output --partial 'mode=tui'
  # Falls through to mc.
  assert_output --partial 'mc'
}

@test "SB_FILEMANAGER: when present in PATH, wins over default order" {
  unset DISPLAY WAYLAND_DISPLAY
  # Drop a stub binary in $TEST_HOME/bin and point SB_FILEMANAGER at it.
  # Add the dir to PATH so command -v resolves it.
  mkdir -p "$TEST_HOME/bin"
  cat > "$TEST_HOME/bin/myfm" <<'STUB'
#!/usr/bin/bash
exit 0
STUB
  chmod +x "$TEST_HOME/bin/myfm"
  export SB_FILEMANAGER=myfm
  PATH="$TEST_HOME/bin:$PATH" run _sb_cmd_filemanager '-n /tmp'
  assert_success
  assert_output --partial 'myfm'
  refute_output --partial 'mc'
}

# ----------------------------------------------------------------------------
# Dry-run output shape
# ----------------------------------------------------------------------------

@test "dry-run: defaults to PWD when path omitted" {
  cd "$TEST_HOME"
  run _sb_cmd_filemanager -n
  assert_success
  assert_output --partial "would run: xdg-open"
  assert_output --partial "$TEST_HOME"
  [[ ! -s $MOCK_XDG_OPEN_LOG ]]
}

@test "dry-run: shows mode= tag for diagnostics" {
  run _sb_cmd_filemanager '-n /tmp'
  assert_success
  assert_output --partial 'mode=gui'
}

@test "dry-run: --dry-run long-form accepted" {
  run _sb_cmd_filemanager '--dry-run /tmp'
  assert_success
  assert_output --partial 'would run:'
}

# ----------------------------------------------------------------------------
# Real launch (mock-recorded)
# ----------------------------------------------------------------------------

@test "GUI launch: invokes xdg-open exactly once with the path" {
  run _sb_cmd_filemanager '/tmp'
  assert_success
  assert_output --partial 'launched xdg-open at: /tmp'
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

@test "TUI launch: invokes mc foreground with the path (no 'launched ...' line)" {
  unset DISPLAY WAYLAND_DISPLAY
  run _sb_cmd_filemanager '/tmp'
  assert_success
  # TUI is foreground - no 'launched' postfix from the handler; mc owns
  # the terminal and slash-bash returns when it exits.
  refute_output --partial 'launched'
  # Mock invocation is synchronous; log is written before _sb_cmd_filemanager
  # returns. No async poll needed.
  run cat "$MOCK_MC_LOG"
  assert_output '/tmp'
}

@test "no-args: defaults to PWD" {
  cd "$TEST_HOME"
  run _sb_cmd_filemanager
  assert_success
  assert_output --partial "launched xdg-open at: $TEST_HOME"
}

# ----------------------------------------------------------------------------
# Option terminator
# ----------------------------------------------------------------------------

@test "--: subsequent args treated as path even if they start with -" {
  mkdir -p "$TEST_HOME/-weirddir"
  cd "$TEST_HOME"
  run _sb_cmd_filemanager '-n -- -weirddir'
  assert_success
  assert_output --partial 'would run:'
  assert_output --partial '-weirddir'
}

# ----------------------------------------------------------------------------
# _sb_resolve_filemanager helper (direct)
# ----------------------------------------------------------------------------

@test "_sb_resolve_filemanager gui: returns 'xdg-open' when in PATH" {
  run _sb_resolve_filemanager gui
  assert_success
  assert_output 'xdg-open'
}

@test "_sb_resolve_filemanager gui: empty + rc=1 when xdg-open missing" {
  local -- empty=$TEST_HOME/empty-bin
  mkdir -p "$empty"
  PATH=$empty run _sb_resolve_filemanager gui
  assert_failure
  [[ -z $output ]]
}

@test "_sb_resolve_filemanager tui: probes mc first when SB_FILEMANAGER unset" {
  unset SB_FILEMANAGER
  run _sb_resolve_filemanager tui
  assert_success
  assert_output 'mc'
}

#fin
