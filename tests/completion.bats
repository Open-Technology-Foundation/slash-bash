#!/usr/bin/env bats
#shellcheck shell=bats
# completion.bats - tab-completion handler logic.
#
# Tests _sb_complete_first / _sb_complete_agent / _sb_complete_model /
# _sb_complete_kb / _sb_complete_ollama by invoking them directly with a
# spoofed COMP_WORDS array, then asserting on COMPREPLY.

load test_helper

setup() {
  setup_test_env
  enable_mocks
  source_slash_bash
  (( BASH_VERSINFO[0] >= 5 )) || skip 'completion suite needs bash 5+ (complete -I)'
}

teardown() {
  disable_mocks
  teardown_test_env
}

# Helper: run a completion fn with a single word at COMP_CWORD=0.
_compfire() {
  local -- fn=$1 cur=$2
  COMP_WORDS=("$cur")
  COMP_CWORD=0
  COMPREPLY=()
  "$fn"
}

# ----------------------------------------------------------------------------
# _sb_complete_first - first-word completion
# ----------------------------------------------------------------------------

@test "complete_first: empty cur returns no completion (PATH falls through)" {
  _compfire _sb_complete_first ''
  # Empty string is not /-prefixed, so we fall through to compgen -c which
  # returns a large list - we just check the function didn't crash and the
  # array exists.
  [[ -v COMPREPLY ]]
}

@test "complete_first: '/' returns all slash commands" {
  _compfire _sb_complete_first '/'
  (( ${#COMPREPLY[@]} > 5 ))
  printf '%s\n' "${COMPREPLY[@]}" | grep -qx '/help'
  printf '%s\n' "${COMPREPLY[@]}" | grep -qx '/agents'
  printf '%s\n' "${COMPREPLY[@]}" | grep -qx '/status'
}

@test "complete_first: '/h' returns /h, /help, /history" {
  _compfire _sb_complete_first '/h'
  printf '%s\n' "${COMPREPLY[@]}" | grep -qx '/help'
  printf '%s\n' "${COMPREPLY[@]}" | grep -qx '/h'
  printf '%s\n' "${COMPREPLY[@]}" | grep -qx '/history'
  # Should NOT contain non-h-prefixed cmds.
  ! printf '%s\n' "${COMPREPLY[@]}" | grep -qx '/agents'
}

@test "complete_first: '/zzz' returns empty" {
  _compfire _sb_complete_first '/zzz'
  (( ${#COMPREPLY[@]} == 0 ))
}

@test "complete_first: non-/ word falls through to compgen -c" {
  _compfire _sb_complete_first 'ec'
  # Real shell utilities starting with 'ec' (echo, ed-like commands) should
  # appear. We just assert the array is non-empty (PATH lookup).
  (( ${#COMPREPLY[@]} > 0 ))
}

# ----------------------------------------------------------------------------
# _sb_complete_agent
# ----------------------------------------------------------------------------

@test "complete_agent: lazy-loads agent list and offers prefix matches" {
  mock_claude_agent list-good
  _compfire _sb_complete_agent 'h'
  printf '%s\n' "${COMPREPLY[@]}" | grep -qx 'haiku'
  ! printf '%s\n' "${COMPREPLY[@]}" | grep -qx 'leet'
}

@test "complete_agent: empty cur returns full list" {
  mock_claude_agent list-good
  _compfire _sb_complete_agent ''
  (( ${#COMPREPLY[@]} == 3 ))
}

@test "complete_agent: missing claude.agent returns empty silently" {
  disable_mocks
  export PATH=/usr/bin:/bin
  _compfire _sb_complete_agent ''
  (( ${#COMPREPLY[@]} == 0 ))
}

# ----------------------------------------------------------------------------
# _sb_complete_model
# ----------------------------------------------------------------------------

@test "complete_model: returns built-in model list" {
  _compfire _sb_complete_model ''
  printf '%s\n' "${COMPREPLY[@]}" | grep -qx 'claude-opus-4-7'
  printf '%s\n' "${COMPREPLY[@]}" | grep -qx 'claude-sonnet-4-6'
}

# ----------------------------------------------------------------------------
# _sb_complete_kb
# ----------------------------------------------------------------------------

@test "complete_kb: includes kb names + reset literals (off, none, clear)" {
  make_fake_kb foo
  make_fake_kb bar
  _compfire _sb_complete_kb ''
  printf '%s\n' "${COMPREPLY[@]}" | grep -qx 'foo'
  printf '%s\n' "${COMPREPLY[@]}" | grep -qx 'bar'
  printf '%s\n' "${COMPREPLY[@]}" | grep -qx 'off'
  printf '%s\n' "${COMPREPLY[@]}" | grep -qx 'none'
  printf '%s\n' "${COMPREPLY[@]}" | grep -qx 'clear'
}

# ----------------------------------------------------------------------------
# _sb_complete_ollama
# ----------------------------------------------------------------------------

@test "complete_ollama: returns off/0/false" {
  _compfire _sb_complete_ollama ''
  (( ${#COMPREPLY[@]} == 3 ))
  printf '%s\n' "${COMPREPLY[@]}" | grep -qx 'off'
  printf '%s\n' "${COMPREPLY[@]}" | grep -qx '0'
  printf '%s\n' "${COMPREPLY[@]}" | grep -qx 'false'
}

@test "complete_ollama: prefix 'o' filters to 'off'" {
  _compfire _sb_complete_ollama 'o'
  (( ${#COMPREPLY[@]} == 1 ))
  [[ ${COMPREPLY[0]} == 'off' ]]
}

#fin
