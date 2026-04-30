#!/usr/bin/env bats
#shellcheck shell=bats
# security.bats - security contracts.
#
# Covers: ${var@Q} quoting (NFR-6.3.3), traversal rejection (NFR-6.3.2),
# integer-regex anchoring, HISTIGNORE patching.

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
# NFR-6.3.3 - ${var@Q} for diagnostic output
# ----------------------------------------------------------------------------

@test "@Q quoting: invalid kb name printed as single-quoted token" {
  run _sb_cmd_kb 'foo$bar'
  assert_failure 1
  # @Q form for foo$bar is 'foo$bar' (single-quoted, $ stays literal).
  assert_output --partial "invalid kb name: 'foo\$bar'"
}

@test "@Q quoting: __sb_intercept rewrites with @Q form (no dollar-string)" {
  READLINE_LINE='/ask $(whoami)'
  __sb_intercept
  # @Q produces single-quoted form; dollar-paren must NOT be evaluated when
  # the rewritten line is read by bash's parser.
  [[ $READLINE_LINE == "__sb_dispatch '/ask \$(whoami)'" ]]
}

# ----------------------------------------------------------------------------
# NFR-6.3.2 - anchored validation regex (kb names)
# ----------------------------------------------------------------------------

@test "anchored regex: kb '../etc/passwd' rejected (no traversal)" {
  run _sb_cmd_kb '../etc/passwd'
  assert_failure 1
  assert_output --partial "invalid kb name"
}

# ----------------------------------------------------------------------------
# integer regex anchoring (maxtokens)
# ----------------------------------------------------------------------------

@test "anchored regex: maxtokens '1.5' rejected (decimal)" {
  run _sb_cmd_maxtokens '1.5'
  assert_failure 1
}

@test "anchored regex: maxtokens '10abc' rejected (suffix non-digit)" {
  run _sb_cmd_maxtokens '10abc'
  assert_failure 1
}

# ----------------------------------------------------------------------------
# FR-1.3.3 - HISTIGNORE patching
# ----------------------------------------------------------------------------

@test "HISTIGNORE: contains __sb_dispatch pattern under default DEBUG=unset" {
  # source_slash_bash ran with DEBUG unset (set in setup_test_env), so
  # the conditional patch should have appended the pattern.
  case ":${HISTIGNORE:-}:" in
    *":__sb_dispatch *:"*) ;;
    *) return 1 ;;
  esac
}

#fin
