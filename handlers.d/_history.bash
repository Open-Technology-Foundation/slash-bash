#!/usr/bin/bash
#shellcheck shell=bash disable=SC2034
# handlers.d/_history.bash - /history and /h [<n>]
# Tails the last n lines of $_SB_HISTORY_FILE (default 20).

_sb_cmd_history() {
  local -i n=20
  local -- arg=$*
  if [[ -n $arg ]]; then
    if [[ ! $arg =~ ^[0-9]+$ ]]; then
      _error 'usage: /history [n]'
      return 1
    fi
    n=$arg
  fi
  if [[ -s $_SB_HISTORY_FILE ]]; then
    tail -n "$n" -- "$_SB_HISTORY_FILE"
  else
    printf 'no slash history yet\n'
  fi
}

_SB_HANDLERS[/history]=_sb_cmd_history
_SB_HANDLERS[/h]=_sb_cmd_history
_SB_HELP[/history]='show last n slash invocations (default 20)'

#fin
