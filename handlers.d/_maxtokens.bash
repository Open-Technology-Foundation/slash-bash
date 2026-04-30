#!/usr/bin/bash
#shellcheck shell=bash disable=SC2034
# handlers.d/_maxtokens.bash - /maxtokens [<n>]
# Empty arg prints current; non-empty must be a positive integer.

_sb_cmd_maxtokens() {
  local -- arg=$*
  if [[ -z $arg ]]; then
    printf 'maxtokens: %d\n' "$_SB_MAX_TOKENS"
    return 0
  fi
  if [[ ! $arg =~ ^[1-9][0-9]*$ ]]; then
    _error 'usage: /maxtokens <positive-integer>'
    return 1
  fi
  _SB_MAX_TOKENS=$arg
  printf 'maxtokens set to: %d\n' "$_SB_MAX_TOKENS"
}

_SB_HANDLERS[/maxtokens]=_sb_cmd_maxtokens
_SB_HELP[/maxtokens]='set max output tokens (positive integer)'

#fin
