#!/usr/bin/env bats
#shellcheck shell=bats
# intercept_dispatch.bats - __sb_intercept rewriting + __sb_dispatch routing.
#
# The chord-trick keybindings can't fire without a TTY (E2E suite), but we
# CAN test the rewriting logic by setting READLINE_LINE manually and
# invoking __sb_intercept; and the dispatch routing by calling
# __sb_dispatch with crafted strings.

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
# __sb_intercept - rewrites READLINE_LINE
# ----------------------------------------------------------------------------

@test "intercept: '/foo bar' is rewritten to dispatcher call with @Q quoting" {
  READLINE_LINE='/foo bar'
  __sb_intercept
  [[ $READLINE_LINE == "__sb_dispatch '/foo bar'" ]]
  [[ ${#READLINE_LINE} == "$READLINE_POINT" ]]
}

@test "intercept: '/help' rewrite preserves quoting and updates point" {
  READLINE_LINE='/help'
  __sb_intercept
  [[ $READLINE_LINE == "__sb_dispatch '/help'" ]]
  # POINT is set to ${#READLINE_LINE} so cursor ends at end of rewrite.
  [[ $READLINE_POINT == ${#READLINE_LINE} ]]
}

@test "intercept: leading whitespace '  /agents' still triggered" {
  READLINE_LINE='  /agents'
  __sb_intercept
  [[ $READLINE_LINE == "__sb_dispatch '  /agents'" ]]
}

@test "intercept: non-slash line passed through unchanged" {
  READLINE_LINE='echo hello'
  __sb_intercept
  [[ $READLINE_LINE == 'echo hello' ]]
}

@test "intercept: empty line passed through unchanged" {
  READLINE_LINE=''
  __sb_intercept
  [[ $READLINE_LINE == '' ]]
}

@test "intercept: backtick injection avoided via @Q single-quote form" {
  # NFR-6.3.3 - @Q renders single-quoted with escaped quote. The substring
  # captured below is what the dispatcher will see; the backticks must NOT
  # be evaluated when the rewritten line is later parsed as a function call.
  READLINE_LINE='/ask `whoami`'
  __sb_intercept
  # The rewrite is a single-quoted token: the outer dispatcher will read it
  # as the literal string '/ask `whoami`' (no command substitution).
  [[ $READLINE_LINE == "__sb_dispatch '/ask \`whoami\`'" ]]
}

@test "intercept: lines with embedded single-quote use @Q's '\\'' escape" {
  READLINE_LINE="/ask don't"
  __sb_intercept
  # @Q form for "don't" is 'don'\''t'.
  [[ $READLINE_LINE == "__sb_dispatch '/ask don'\\''t'" ]]
}

@test "intercept: _SB_LAST_ORIGINAL captures the original pre-rewrite form" {
  _SB_LAST_ORIGINAL=''
  READLINE_LINE='/agents'
  __sb_intercept
  [[ $_SB_LAST_ORIGINAL == '/agents' ]]
}

# ----------------------------------------------------------------------------
# __sb_dispatch - routing
# ----------------------------------------------------------------------------

@test "dispatch '/help': routes to _sb_cmd_help" {
  run __sb_dispatch '/help'
  assert_success
  assert_output --partial 'Available slash commands'
}

@test "dispatch '/foo': unknown command returns 1 with quoted name" {
  run __sb_dispatch '/foo'
  assert_failure 1
  assert_output --partial "unknown slash command: '/foo'"
}

@test "dispatch '/agent haiku': splits args correctly" {
  mock_claude_agent list-good
  run __sb_dispatch '/agent haiku'
  assert_success
  assert_output --partial 'agent set to: haiku'
}

@test "dispatch '/ <text>': '/ask' shortcut form routes to _sb_cmd_ask" {
  mock_claude_agent passthrough
  __sb_dispatch '/ a question' >/dev/null
  run cat "$MOCK_CLAUDE_AGENT_LOG"
  assert_output --partial 'a question'
}

# ----------------------------------------------------------------------------
# __sb_split_redirect - quote-aware split at first unquoted shell metachar
# ----------------------------------------------------------------------------

@test "split: bare line yields whole CMD and empty TAIL" {
  _SB_SPLIT_CMD=''; _SB_SPLIT_TAIL=''
  __sb_split_redirect '/help'
  [[ $_SB_SPLIT_CMD == '/help' ]]
  [[ $_SB_SPLIT_TAIL == '' ]]
}

@test "split: trailing whitespace before metachar stripped from CMD" {
  _SB_SPLIT_CMD=''; _SB_SPLIT_TAIL=''
  __sb_split_redirect '/status   >foo'
  [[ $_SB_SPLIT_CMD == '/status' ]]
  [[ $_SB_SPLIT_TAIL == '>foo' ]]
}

@test "split: ignores metachars inside double quotes" {
  _SB_SPLIT_CMD=''; _SB_SPLIT_TAIL=''
  __sb_split_redirect '/ask "what is > here?"'
  [[ $_SB_SPLIT_CMD == '/ask "what is > here?"' ]]
  [[ $_SB_SPLIT_TAIL == '' ]]
}

@test "split: ignores metachars inside single quotes" {
  _SB_SPLIT_CMD=''; _SB_SPLIT_TAIL=''
  __sb_split_redirect "/ask 'a > b'"
  [[ $_SB_SPLIT_CMD == "/ask 'a > b'" ]]
  [[ $_SB_SPLIT_TAIL == '' ]]
}

@test "split: backslash inside double quotes escapes following char" {
  _SB_SPLIT_CMD=''; _SB_SPLIT_TAIL=''
  __sb_split_redirect '/ask "a\">b"'
  # backslash escapes the next " inside double-quote state - still in dquote
  # at the >, so > is NOT a split point.
  [[ $_SB_SPLIT_CMD == '/ask "a\">b"' ]]
  [[ $_SB_SPLIT_TAIL == '' ]]
}

# ----------------------------------------------------------------------------
# __sb_split_redirect - malformed input (defensive coverage)
# Loop ends with an open quote / pending escape: the function falls through
# to the "no split" branch and the whole line lands in CMD. Bash's own
# parser will then complain about the unclosed quote when the rewrite is
# evaluated - which is the correct location for that diagnostic.
# ----------------------------------------------------------------------------

@test "split: unclosed double quote stays in dquote, no split" {
  _SB_SPLIT_CMD=''; _SB_SPLIT_TAIL=''
  __sb_split_redirect '/ask "unclosed'
  [[ $_SB_SPLIT_CMD == '/ask "unclosed' ]]
  [[ $_SB_SPLIT_TAIL == '' ]]
}

@test "split: unclosed single quote stays in squote, no split" {
  _SB_SPLIT_CMD=''; _SB_SPLIT_TAIL=''
  __sb_split_redirect "/ask 'unclosed"
  [[ $_SB_SPLIT_CMD == "/ask 'unclosed" ]]
  [[ $_SB_SPLIT_TAIL == '' ]]
}

@test "split: trailing backslash leaves escape pending, no split" {
  _SB_SPLIT_CMD=''; _SB_SPLIT_TAIL=''
  __sb_split_redirect '/ask foo\'
  [[ $_SB_SPLIT_CMD == '/ask foo\' ]]
  [[ $_SB_SPLIT_TAIL == '' ]]
}

@test "split: only first unquoted metachar splits; rest go to TAIL verbatim" {
  _SB_SPLIT_CMD=''; _SB_SPLIT_TAIL=''
  __sb_split_redirect '/ask >a\|b\;c'
  [[ $_SB_SPLIT_CMD == '/ask' ]]
  [[ $_SB_SPLIT_TAIL == '>a\|b\;c' ]]
}

# ----------------------------------------------------------------------------
# __sb_intercept - redirection / pipe / sequence support
# ----------------------------------------------------------------------------

@test "intercept: '/status > /tmp/foo' splits redirection out of the @Q quote" {
  READLINE_LINE='/status > /tmp/foo'
  __sb_intercept
  [[ $READLINE_LINE == "__sb_dispatch '/status' > /tmp/foo" ]]
}

@test "intercept: '/status >/tmp/foo' (no space) still splits correctly" {
  READLINE_LINE='/status >/tmp/foo'
  __sb_intercept
  [[ $READLINE_LINE == "__sb_dispatch '/status' >/tmp/foo" ]]
}

@test "intercept: '/status >> /tmp/log' (append) splits correctly" {
  READLINE_LINE='/status >> /tmp/log'
  __sb_intercept
  [[ $READLINE_LINE == "__sb_dispatch '/status' >> /tmp/log" ]]
}

@test "intercept: '/ask hi | tee log' splits at pipe" {
  READLINE_LINE='/ask hi | tee log'
  __sb_intercept
  [[ $READLINE_LINE == "__sb_dispatch '/ask hi' | tee log" ]]
}

@test "intercept: '/exit; ls' splits at sequence" {
  READLINE_LINE='/exit; ls'
  __sb_intercept
  [[ $READLINE_LINE == "__sb_dispatch '/exit' ; ls" ]]
}

@test "intercept: redirection inside double quotes does NOT trigger split" {
  READLINE_LINE='/ask "what is > here?"'
  __sb_intercept
  # Whole line stays inside @Q because the > is quoted.
  [[ $READLINE_LINE == "__sb_dispatch '/ask \"what is > here?\"'" ]]
}

@test "intercept: redirection inside single quotes does NOT trigger split" {
  READLINE_LINE="/ask 'a > b'"
  __sb_intercept
  # @Q form for "/ask 'a > b'" wraps the ' as '\''.
  [[ $READLINE_LINE == "__sb_dispatch '/ask '\\''a > b'\\'''" ]]
}

@test "intercept: unclosed double quote suppresses split (whole line in @Q)" {
  # split bails out (still in dquote at end of input), so the no-tail branch
  # runs: the > is captured inside the @Q single-quoted form rather than
  # being parsed by bash. Bash's parser will diagnose the unclosed " when
  # the rewrite is evaluated - which is the correct layer for that error.
  READLINE_LINE='/ask "unclosed > here'
  __sb_intercept
  [[ $READLINE_LINE == "__sb_dispatch '/ask \"unclosed > here'" ]]
}

@test "intercept: '/ask foo > bar 2>&1' captures stderr-merge in tail" {
  READLINE_LINE='/ask foo > bar 2>&1'
  __sb_intercept
  [[ $READLINE_LINE == "__sb_dispatch '/ask foo' > bar 2>&1" ]]
}

@test "intercept: '/ask hi & ' (trailing background) splits at &" {
  READLINE_LINE='/ask hi & '
  __sb_intercept
  [[ $READLINE_LINE == "__sb_dispatch '/ask hi' & " ]]
}

@test "intercept: redirection round-trip through eval writes to file" {
  # E2E: rewriting must produce a line bash actually parses with the
  # redirection applied. Mock _sb_cmd_status to print a known marker, then
  # eval the rewritten READLINE_LINE and assert the file got the marker.
  local -- marker='SLASH-CMD-REDIR-MARKER-9182734'
  local -- out="$BATS_TEST_TMPDIR/redir_out"
  _sb_cmd_status() { printf '%s\n' "$marker"; }
  READLINE_LINE="/status > $out"
  __sb_intercept
  eval "$READLINE_LINE"
  run cat "$out"
  assert_success
  assert_output "$marker"
}

#fin
