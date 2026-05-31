#!/usr/bin/env bats
#shellcheck shell=bats
# e2e_chord.bats - Phase 2 PTY-driven verification of the chord trick.
#
# The chord-trick keybindings (slash-bash.bash "Key bindings" section) require a real TTY
# - `bind -x` cannot fire and `bind '"\C-m":...'` is rejected when stdin is
# not a terminal. Phase 1 covers the rewriting / dispatching logic via
# direct function calls; Phase 2 covers the actual readline path end-to-end.
#
# Gated behind BATS_E2E=1. Skips by default so CI doesn't burn cycles on
# expect spawns. Requires `expect` from package `expect` (Ubuntu).

load test_helper

setup() {
  setup_test_env
  [[ ${BATS_E2E:-0} == 1 ]] || skip 'set BATS_E2E=1 to run PTY-driven E2E suite'
  command -v expect >/dev/null || skip 'expect(1) not in PATH'
}

teardown() {
  teardown_test_env
}

@test "e2e: /help via real readline emits dispatcher output" {
  # expect script: spawn slash-bash, send '/help\r', look for the help banner,
  # send '/exit\r'. Use a 5s overall timeout.
  run expect -c "
    set timeout 5
    log_user 0
    spawn -noecho \"$PROJECT_DIR/slash-bash\"
    expect -re {\\\$ \$}
    send {/help}
    send \"\r\"
    expect {
      -re {Available slash commands} { exit 0 }
      timeout                        { exit 10 }
      eof                            { exit 11 }
    }
  "
  assert_success
}

@test "e2e: unknown /foo bubbles up named diagnostic, no execve attempt" {
  run expect -c "
    set timeout 5
    log_user 0
    spawn -noecho \"$PROJECT_DIR/slash-bash\"
    expect -re {\\\$ \$}
    send {/no-such-cmd}
    send \"\r\"
    expect {
      -re {unknown slash command: '/no-such-cmd'} { exit 0 }
      -re {No such file or directory}             { exit 12 }
      timeout                                     { exit 10 }
      eof                                         { exit 11 }
    }
  "
  assert_success
}

# ---------------------------------------------------------------------------
# Quote-aware split (__sb_split_redirect) under real readline. Phase 1 covers
# the splitter as a unit; these tests prove the chord-trick + split combine
# correctly so bash parses redirection / pipe in the rewritten line.
# ---------------------------------------------------------------------------

@test "e2e: /help > FILE redirects via bash, file gets help banner" {
  local tmpfile=$BATS_TEST_TMPDIR/help.out
  run expect -c "
    set timeout 5
    log_user 0
    spawn -noecho \"$PROJECT_DIR/slash-bash\"
    expect -re {\\\$ \$}
    send {/help > $tmpfile}
    send \"\r\"
    expect {
      -re {\\\$ \$} {}
      timeout      { exit 10 }
      eof          { exit 11 }
    }
    send {/exit}
    send \"\r\"
    expect eof
  "
  assert_success
  [[ -s $tmpfile ]]
  grep -q 'Available slash commands' "$tmpfile"
}

@test "e2e: /help | wc -l routes pipe through bash; help suppressed on tty" {
  # If the pipe were swallowed by @Q (i.e. split helper failed), bash would
  # run __sb_dispatch with the literal '/help | wc -l' arg - the '/help'
  # branch matches a prefix and the full help would dump. Pattern-match on
  # 'Available slash commands' to detect that breakage; on '[0-9]+' (the wc
  # output) to confirm the pipe ran. Help output contains no digits before
  # 'Available' on line 1, so the regression case fires first.
  run expect -c "
    set timeout 5
    log_user 0
    spawn -noecho \"$PROJECT_DIR/slash-bash\"
    expect -re {\\\$ \$}
    send {/help | wc -l}
    send \"\r\"
    expect {
      -re {Available slash commands} { exit 12 }
      -re {[0-9]+}                   {}
      timeout                        { exit 10 }
      eof                            { exit 11 }
    }
    expect -re {\\\$ \$}
    send {/exit}
    send \"\r\"
    expect eof
  "
  assert_success
}

#fin
