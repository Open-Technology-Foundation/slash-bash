#!/usr/bin/env bats
#shellcheck shell=bats
# handlers_kb.bats - /kbs and /kb handlers, including KB-name traversal rejection.
# Contracts: REQUIREMENTS NFR-6.3.2 (anchored validation regex)

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
# /kbs - listing
# ----------------------------------------------------------------------------

@test "/kbs: empty kb root reports 'no knowledgebases found'" {
  run _sb_cmd_kbs
  assert_success
  assert_output --partial "no knowledgebases found"
  assert_output --partial "current: <none>"
}

@test "/kbs --list: lists kbs discovered under VECTORDBS" {
  make_fake_kb kb1
  make_fake_kb kb2
  run _sb_cmd_kbs --list
  assert_success
  assert_output --partial "available kbs:"
  assert_line "  - kb1"
  assert_line "  - kb2"
}

@test "/kbs --list: SB_KB_LIST short-circuits glob discovery" {
  make_fake_kb real-kb
  export SB_KB_LIST='curated1 curated2'
  run _sb_cmd_kbs --list
  assert_success
  # Curated entries appear; the real glob result does not (since SB_KB_LIST
  # short-circuits the loader before the glob).
  assert_line "  - curated1"
  assert_line "  - curated2"
  refute_line "  - real-kb"
}

@test "/kbs (no arg, non-TTY, populated): rejects with 'requires interactive terminal'" {
  make_fake_kb kb1
  run _sb_cmd_kbs
  assert_failure 1
  assert_output --partial "requires an interactive terminal"
}

# ----------------------------------------------------------------------------
# /kb - reading current
# ----------------------------------------------------------------------------

@test "/kb (no arg): reports current kb (initially <none>)" {
  run _sb_cmd_kb
  assert_success
  assert_output "current kb: <none>"
}

@test "/kb (no arg) after switch: reports the active kb" {
  make_fake_kb kb1
  _sb_cmd_kb kb1 >/dev/null
  run _sb_cmd_kb
  assert_success
  assert_output "current kb: kb1"
}

# ----------------------------------------------------------------------------
# /kb - reset literals
# ----------------------------------------------------------------------------

@test "/kb off: clears current kb" {
  make_fake_kb kb1
  _sb_cmd_kb kb1 >/dev/null
  # Direct call (not $() or run) so _SB_KB mutation lands in this shell.
  _sb_cmd_kb off > "$TEST_HOME/out"
  grep -q "kb cleared" "$TEST_HOME/out"
  [[ -z $_SB_KB ]]
}

@test "/kb none: also clears" {
  make_fake_kb kb1
  _sb_cmd_kb kb1 >/dev/null
  _sb_cmd_kb none >/dev/null
  [[ -z $_SB_KB ]]
}

@test "/kb clear: also clears" {
  make_fake_kb kb1
  _sb_cmd_kb kb1 >/dev/null
  _sb_cmd_kb clear >/dev/null
  [[ -z $_SB_KB ]]
}

# ----------------------------------------------------------------------------
# /kb - happy path
# ----------------------------------------------------------------------------

@test "/kb <existing>: switches and confirms" {
  make_fake_kb kb1
  run _sb_cmd_kb kb1
  assert_success
  assert_output --partial "kb switched to: kb1"
}

@test "/kb <existing>: state mutates _SB_KB" {
  make_fake_kb kb1
  _sb_cmd_kb kb1 >/dev/null
  [[ $_SB_KB == kb1 ]]
}

@test "/kb <unknown>: rejects with cfg-path diagnostic" {
  run _sb_cmd_kb missing-kb
  assert_failure 1
  assert_output --partial "unknown kb: 'missing-kb'"
}

# ----------------------------------------------------------------------------
# /kb - validation regex (anchored, NFR-6.3.2)
# ----------------------------------------------------------------------------

@test "/kb '..': rejected as invalid name (traversal attempt)" {
  run _sb_cmd_kb '..'
  assert_failure 1
  assert_output --partial "invalid kb name"
}

@test "/kb names with shell metacharacters all rejected" {
  # Each variant trips the anchored ^[A-Za-z0-9_-]+$ regex.
  for bad in '/etc/passwd' 'foo/bar' 'foo bar' 'foo;rm' 'foo\$bar'; do
    run _sb_cmd_kb "$bad"
    assert_failure 1
    assert_output --partial "invalid kb name"
  done
}

#fin
