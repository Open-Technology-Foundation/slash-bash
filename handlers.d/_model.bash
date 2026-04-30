#!/usr/bin/bash
#shellcheck shell=bash disable=SC2034
# handlers.d/_model.bash - /model [<name>] + colocated _sb_complete_model.

_sb_cmd_model() {
  local -- name=$*
  if [[ -z $name ]]; then
    printf 'current model: %s\n' "$_SB_MODEL"
    return 0
  fi
  _SB_MODEL=$name
  printf 'model set to: %s\n' "$_SB_MODEL"
}

_sb_complete_model() {
  local -- cur=${COMP_WORDS[COMP_CWORD]}
  COMPREPLY=()
  readarray -t COMPREPLY < <(compgen -W "${_SB_MODEL_LIST[*]}" -- "$cur")
}

_SB_HANDLERS[/model]=_sb_cmd_model
_SB_HELP[/model]='show or set the current model'
_SB_COMPLETE[/model]=_sb_complete_model

#fin
