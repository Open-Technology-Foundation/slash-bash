#!/usr/bin/env bats
#shellcheck shell=bats
# handlers_extras.bats - coverage gaps surfaced by the comprehensive
# suite refresh. Targets:
#   - _sb_complete_rebase                       (was untested post-/rebase)
#   - /rebase via __sb_dispatch                 (dispatcher routing)
#   - /status conditional emission              (SB_KB_LIST, OLLAMA_MODEL)
#   - /status round-trip via `eval`             (real subshell export)
#   - /help mentions /rebase                    (FR-5.1.1 step-3 omission check)
#   - _msg sigil prefix format                  (BCS messaging contract)
#   - _SB_SLASH_CMDS contents                   (master list invariant)
#   - dispatcher unknown-cmd rc + diagnostic    (NFR-6.3.3 @Q output)

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
# _sb_complete_rebase
# ----------------------------------------------------------------------------

@test "complete_rebase: empty cur offers --force" {
  COMP_WORDS=('/rebase' '')
  COMP_CWORD=1
  COMPREPLY=()
  _sb_complete_rebase
  (( ${#COMPREPLY[@]} == 1 ))
  [[ ${COMPREPLY[0]} == --force ]]
}

@test "complete_rebase: '--f' prefix offers --force" {
  COMP_WORDS=('/rebase' '--f')
  COMP_CWORD=1
  COMPREPLY=()
  _sb_complete_rebase
  (( ${#COMPREPLY[@]} == 1 ))
  [[ ${COMPREPLY[0]} == --force ]]
}

@test "complete_rebase: '--bogus' returns empty" {
  COMP_WORDS=('/rebase' '--bogus')
  COMP_CWORD=1
  COMPREPLY=()
  _sb_complete_rebase
  (( ${#COMPREPLY[@]} == 0 ))
}

# ----------------------------------------------------------------------------
# /rebase routes through __sb_dispatch
# ----------------------------------------------------------------------------

@test "dispatch '/rebase --bogus': routes to handler and returns 1" {
  run __sb_dispatch '/rebase --bogus'
  assert_failure 1
  assert_output --partial "usage: /rebase"
}

@test "dispatch '/rebase' (same cwd): no-op already-bound" {
  _SB_SESSION_CWD=$PWD
  run __sb_dispatch '/rebase'
  assert_success
  assert_output --partial "already bound to"
}

# ----------------------------------------------------------------------------
# /status conditional emission
# ----------------------------------------------------------------------------

@test "/status: SB_KB_LIST line emitted only when set" {
  run _sb_cmd_status
  refute_output --partial "SB_KB_LIST"
  export SB_KB_LIST='kb1 kb2'
  run _sb_cmd_status
  assert_output --partial "export SB_KB_LIST='kb1 kb2'"
}

@test "/status: OLLAMA_MODEL omitted unless ollama configured with model" {
  run _sb_cmd_status
  refute_output --partial "OLLAMA_MODEL"
  _sb_cmd_ollama 'tinyllama' >/dev/null
  run _sb_cmd_status
  assert_output --partial "export OLLAMA_MODEL='tinyllama'"
}

@test "/status: empty SB_SESSION_UUID emits as empty quoted string" {
  run _sb_cmd_status
  assert_output --partial "export SB_SESSION_UUID=''"
}

# ----------------------------------------------------------------------------
# /status round-trip exports into a fresh subshell
# ----------------------------------------------------------------------------

@test "/status: exported SB_AGENT visible to a child process after eval" {
  mock_claude_agent list-good
  _sb_cmd_agent haiku >/dev/null
  local -- captured
  captured=$(_sb_cmd_status)
  # `export` must persist into a child shell, not just the eval-ing shell.
  local -- got
  got=$(eval "$captured"; bash -c 'printf %s "$SB_AGENT"')
  [[ $got == haiku ]]
}

# ----------------------------------------------------------------------------
# /help: mentions /rebase (FR-5.1.1 "step 3 most common omission" guard)
# ----------------------------------------------------------------------------

@test "/help: mentions /rebase command" {
  run _sb_cmd_help
  assert_success
  assert_output --partial "/rebase"
  assert_output --partial "--force"
}

@test "/help: mentions /sessions command" {
  run _sb_cmd_help
  assert_success
  assert_output --partial "/sessions"
}

# ----------------------------------------------------------------------------
# _SB_SLASH_CMDS master-list invariants
# ----------------------------------------------------------------------------

@test "_SB_SLASH_CMDS: contains all dispatched commands" {
  local -a expect=(/help /agents /agent /models /model /kbs /kb /maxtokens \
                   /ollama /ask /systemprompt /history /status /sessions \
                   /rebase /exit)
  local -- cmd
  for cmd in "${expect[@]}"; do
    [[ " ${_SB_SLASH_CMDS[*]} " == *" $cmd "* ]] || \
      { printf 'missing from _SB_SLASH_CMDS: %s\n' "$cmd" >&2; false; }
  done
}

@test "_SB_SLASH_CMDS: 26 entries (post-/rebase)" {
  (( ${#_SB_SLASH_CMDS[@]} == 26 ))
}

# ----------------------------------------------------------------------------
# Messaging primitives: __msg / _error / _warn sigils
# ----------------------------------------------------------------------------

@test "_error: emits agent prefix + ✗ sigil to stderr" {
  run _error 'boom'
  assert_success
  assert_output --partial "leet:"
  assert_output --partial "✗"
  assert_output --partial "boom"
}

@test "_warn: emits agent prefix + ▲ sigil" {
  run _warn 'careful'
  assert_output --partial "▲"
  assert_output --partial "careful"
}

@test "_info: silent unless _VERBOSE=1" {
  _VERBOSE=0
  run _info 'hidden'
  refute_output --partial "hidden"
  _VERBOSE=1
  run _info 'shown'
  assert_output --partial "◉"
  assert_output --partial "shown"
}

@test "_debug: silent unless _DEBUG=1" {
  _DEBUG=0
  run _debug 'silent'
  refute_output --partial "silent"
  _DEBUG=1
  run _debug 'visible'
  assert_output --partial "⦿"
  assert_output --partial "visible"
}

@test "_die: emits message and returns the requested code" {
  run _die 7 'doomsday'
  [[ $status -eq 7 ]]
  assert_output --partial "doomsday"
}

@test "_die N: returns N with no message when only code given" {
  run _die 3
  [[ $status -eq 3 ]]
  [[ -z $output ]]
}

# ----------------------------------------------------------------------------
# Dispatcher edge cases
# ----------------------------------------------------------------------------

@test "dispatch: unknown slash command rc=1, name @Q-quoted in diagnostic" {
  run __sb_dispatch '/zorpius'
  assert_failure 1
  assert_output --partial "unknown slash command: '/zorpius'"
}

@test "dispatch: leading whitespace stripped before routing" {
  run __sb_dispatch '   /help'
  assert_success
  assert_output --partial "Available slash commands"
}

@test "dispatch: aliases /q /quit /bye /exit all route to exit handler" {
  # Shadow _sb_cmd_exit with a probe so we don't actually exit the shell.
  _sb_cmd_exit() { _SB_EXIT_CALLED=1; return 0; }
  local -- alias
  for alias in /q /quit /bye /exit; do
    _SB_EXIT_CALLED=0
    __sb_dispatch "$alias"
    (( _SB_EXIT_CALLED == 1 )) || \
      { printf 'alias %s did not route to _sb_cmd_exit\n' "$alias" >&2; false; }
  done
}

# ----------------------------------------------------------------------------
# /maxtokens edge: very-large value still accepted
# ----------------------------------------------------------------------------

@test "/maxtokens: 7-digit value accepted (regex permits)" {
  run _sb_cmd_maxtokens 1000000
  assert_success
  assert_output --partial "maxtokens set to: 1000000"
}

# ----------------------------------------------------------------------------
# /ollama edge: invalid model name with shell metachars rejected
# ----------------------------------------------------------------------------

@test "/ollama 'evil;rm -rf': rejected as invalid model name" {
  run _sb_cmd_ollama 'evil;rm -rf'
  assert_failure 1
  assert_output --partial "invalid model name"
}

#fin
