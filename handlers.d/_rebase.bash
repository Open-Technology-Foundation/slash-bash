#!/usr/bin/bash
#shellcheck shell=bash disable=SC2034
# handlers.d/_rebase.bash - /rebase [--force] + colocated
# _sb_complete_rebase. Binds the active conversation to $PWD's
# most-recent JSONL (auto-pick, no menu). Prompts before discarding a
# binding with recent /ask activity (within _SB_DIRTY_WINDOW seconds);
# --force or non-TTY caller skips the prompt.

_sb_cmd_rebase() {
  local -- arg=${1:-}
  local -i force=0
  case $arg in
    '') ;;
    --force) force=1 ;;
    *) _error "usage: /rebase [--force]"; return 1 ;;
  esac
  local -- new_cwd=$PWD
  if [[ $new_cwd == "$_SB_SESSION_CWD" ]]; then
    printf 'already bound to: %s\n' "$_SB_SESSION_CWD"
    printf 'session uuid:    %s\n' "${_SB_SESSION_UUID:-<fresh>}"
    return 0
  fi
  if ((!force)) && [[ -n $_SB_SESSION_UUID ]]; then
    local -i now=${EPOCHSECONDS:-$(date +%s)}
    local -i delta=$(( now - _SB_SESSION_LAST_ASK ))
    if (( _SB_SESSION_LAST_ASK > 0 && delta < _SB_DIRTY_WINDOW )); then
      _warn "current conversation active ${delta}s ago (cwd=${_SB_SESSION_CWD})"
      [[ -t 0 ]] || { _error 'non-interactive; pass --force to proceed'; return 1; }
      local -- yn=''
      read -r -p 'rebase anyway? [y/N] ' yn </dev/tty || return 1
      case ${yn,,} in
        y|yes) ;;
        *) printf 'cancelled\n'; return 1 ;;
      esac
    fi
  fi
  local -- newest=''
  _sb_pick_newest_uuid newest "$new_cwd"
  _SB_SESSION_CWD=$new_cwd
  _SB_SESSION_UUID=$newest
  _SB_SESSION_LAST_ASK=0
  printf 'rebased to: %s\n' "$_SB_SESSION_CWD"
  if [[ -n $_SB_SESSION_UUID ]]; then
    printf 'resuming:   %s\n' "$_SB_SESSION_UUID"
  else
    printf 'no prior conversation; next /ask starts fresh\n'
  fi
}

_sb_complete_rebase() {
  local -- cur=${COMP_WORDS[COMP_CWORD]}
  COMPREPLY=()
  readarray -t COMPREPLY < <(compgen -W '--force' -- "$cur")
}

_SB_HANDLERS[/rebase]=_sb_cmd_rebase
# shellcheck disable=SC2016
_SB_HELP[/rebase]='bind conversation to $PWD most-recent JSONL (--force to skip dirty prompt)'
_SB_COMPLETE[/rebase]=_sb_complete_rebase

#fin
