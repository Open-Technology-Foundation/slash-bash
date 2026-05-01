#!/usr/bin/env bats
#shellcheck shell=bats
# handlers_d.bats - Surface invariants for the handlers.d/ registry.
# Every entry in _SB_HANDLERS must resolve to a defined function;
# completions and help entries must stay coherent with the registry;
# the dispatcher must honour the bare-`/' shorthand and reject unknowns.

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
# _SB_HANDLERS surface
# ----------------------------------------------------------------------------

@test "_SB_HANDLERS: every entry resolves to a defined function" {
  local -- cmd fn
  for cmd in "${!_SB_HANDLERS[@]}"; do
    fn=${_SB_HANDLERS[$cmd]}
    declare -F -- "$fn" >/dev/null 2>&1 \
      || { printf 'unresolved: %s -> %s\n' "$cmd" "$fn" >&2; false; }
  done
}

@test "_SB_HANDLERS: 26 entries match prior _SB_SLASH_CMDS invariant" {
  (( ${#_SB_HANDLERS[@]} == 26 ))
}

@test "_SB_HANDLERS: bare '/' is NOT a key (special-cased in dispatcher)" {
  [[ ! -v _SB_HANDLERS['/'] ]]
}

# ----------------------------------------------------------------------------
# Alias parity - aliases route to the same handler as their canonical form.
# ----------------------------------------------------------------------------

@test "distinct handlers: /help (full) and /? (short) route to separate fns" {
  [[ ${_SB_HANDLERS[/help]}   == _sb_cmd_help ]]
  [[ ${_SB_HANDLERS['/?']}    == _sb_cmd_help_short ]]
  [[ ${_SB_HANDLERS[/help]}   != "${_SB_HANDLERS['/?']}" ]]
}

@test "alias parity: /h routes to _sb_cmd_history" {
  [[ ${_SB_HANDLERS[/h]} == "${_SB_HANDLERS[/history]}" ]]
}

@test "alias parity: /knowledgebases routes to _sb_cmd_kbs" {
  [[ ${_SB_HANDLERS[/knowledgebases]} == "${_SB_HANDLERS[/kbs]}" ]]
}

@test "alias parity: /knowledgebase routes to _sb_cmd_kb" {
  [[ ${_SB_HANDLERS[/knowledgebase]} == "${_SB_HANDLERS[/kb]}" ]]
}

@test "alias parity: /bye /quit /q /exit all route to _sb_cmd_exit" {
  local -- canonical=${_SB_HANDLERS[/exit]}
  [[ ${_SB_HANDLERS[/bye]}  == "$canonical" ]]
  [[ ${_SB_HANDLERS[/quit]} == "$canonical" ]]
  [[ ${_SB_HANDLERS[/q]}    == "$canonical" ]]
}

# ----------------------------------------------------------------------------
# _SB_COMPLETE surface
# ----------------------------------------------------------------------------

@test "_SB_COMPLETE: every entry resolves to a defined function" {
  local -- cmd fn
  for cmd in "${!_SB_COMPLETE[@]}"; do
    fn=${_SB_COMPLETE[$cmd]}
    declare -F -- "$fn" >/dev/null 2>&1 \
      || { printf 'unresolved completion: %s -> %s\n' "$cmd" "$fn" >&2; false; }
  done
}

@test "_SB_COMPLETE: every entry's /cmd is also in _SB_HANDLERS" {
  local -- cmd
  for cmd in "${!_SB_COMPLETE[@]}"; do
    [[ -v _SB_HANDLERS[$cmd] ]] \
      || { printf 'orphan completion: %s\n' "$cmd" >&2; false; }
  done
}

@test "_SB_COMPLETE: /systemprompt reuses _sb_complete_agent (cross-file dep)" {
  [[ ${_SB_COMPLETE[/systemprompt]} == _sb_complete_agent ]]
  [[ ${_SB_COMPLETE[/agent]}        == _sb_complete_agent ]]
}

# ----------------------------------------------------------------------------
# _SB_HELP surface
# ----------------------------------------------------------------------------

@test "_SB_HELP: keys are a subset of _SB_HANDLERS keys" {
  local -- cmd
  for cmd in "${!_SB_HELP[@]}"; do
    [[ -v _SB_HANDLERS[$cmd] ]] \
      || { printf 'orphan help: %s\n' "$cmd" >&2; false; }
  done
}

# ----------------------------------------------------------------------------
# Dispatcher behaviour
# ----------------------------------------------------------------------------

@test "__sb_dispatch: bare '/' invokes _sb_cmd_ask" {
  # Stub _sb_cmd_ask so we don't need a real claude.agent run; capture
  # the first arg to verify the dispatcher passed args through.
  local -- captured=''
  _sb_cmd_ask() { captured=$* ; }
  __sb_dispatch '/ hello world'
  [[ $captured == 'hello world' ]]
}

@test "__sb_dispatch: unknown /cmd reports diagnostic + rc=1" {
  run __sb_dispatch '/bogus'
  assert_failure 1
  assert_output --partial "unknown slash command"
  assert_output --partial "/bogus"
}

@test "__sb_dispatch: routes via registry not hardcoded case" {
  # Sanity check: temporarily steal _sb_cmd_help and verify dispatch
  # honours the registry redirection.
  _SB_HANDLERS[/help]=_sb_test_stub
  _sb_test_stub() { printf 'stubbed: %s\n' "$*"; }
  run __sb_dispatch '/help'
  assert_success
  assert_output --partial 'stubbed:'
}

# ----------------------------------------------------------------------------
# First-word completion uses the registry
# ----------------------------------------------------------------------------

@test "_sb_complete_first: '/' offers all 26 registered commands" {
  COMP_WORDS=(/)
  COMP_CWORD=0
  _sb_complete_first
  (( ${#COMPREPLY[@]} == 26 ))
}

@test "_sb_complete_first: '/h' filters to /h, /help, /history" {
  COMP_WORDS=(/h)
  COMP_CWORD=0
  _sb_complete_first
  local -- joined=" ${COMPREPLY[*]} "
  [[ $joined == *' /h '* ]]
  [[ $joined == *' /help '* ]]
  [[ $joined == *' /history '* ]]
}

# ----------------------------------------------------------------------------
# _SB_SLASH_CMDS derivation
# ----------------------------------------------------------------------------

@test "_SB_SLASH_CMDS: length matches _SB_HANDLERS length" {
  (( ${#_SB_SLASH_CMDS[@]} == ${#_SB_HANDLERS[@]} ))
}

@test "_SB_SLASH_CMDS: contents are sorted keys of _SB_HANDLERS" {
  local -a expected
  readarray -t expected < <(printf '%s\n' "${!_SB_HANDLERS[@]}" | sort)
  [[ "${_SB_SLASH_CMDS[*]}" == "${expected[*]}" ]]
}

# ----------------------------------------------------------------------------
# Validation guard
# ----------------------------------------------------------------------------

@test "validation: missing handler function triggers _warn diagnostic" {
  # Re-run the validation block manually with an injected bogus entry
  # to verify the warn path. Cannot test by re-sourcing the lib (the
  # bats subshell already has it loaded with a clean registry).
  _SB_HANDLERS[/_test_bogus]=_sb_cmd_does_not_exist
  local -- output=''
  output=$(
    for _sb_cmd in "${!_SB_HANDLERS[@]}"; do
      _sb_fn=${_SB_HANDLERS[$_sb_cmd]}
      declare -F -- "$_sb_fn" >/dev/null 2>&1 \
        || _warn "internal: ${_sb_cmd} -> ${_sb_fn@Q} not defined"
    done 2>&1
  )
  [[ $output == *'_test_bogus'* ]]
  [[ $output == *'_sb_cmd_does_not_exist'* ]]
  [[ $output == *'not defined'* ]]
}

# ----------------------------------------------------------------------------
# Source-glob safety
# ----------------------------------------------------------------------------

@test "source-glob: nullglob makes empty handlers.d/ a no-op" {
  # Verify the loop pattern itself is safe with nullglob and an empty dir;
  # this is a behavioural check on the construct (the harness pre-sourced
  # real handlers separately).
  local -- empty_dir="$TEST_HOME/empty_handlers"
  mkdir -p "$empty_dir"
  local -i count=0
  shopt -s nullglob
  local -- f
  for f in "$empty_dir"/*.bash; do
    (( count++ ))
  done
  shopt -u nullglob
  (( count == 0 ))
}

#fin
