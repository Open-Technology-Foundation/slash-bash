#!/usr/bin/bash
#shellcheck shell=bash disable=SC2034
# handlers.d/_ollama.bash - /ollama [model|off] + colocated
# _sb_complete_ollama. Empty arg enables with default model;
# off/0/false disables; named model exports OLLAMA_MODEL.

_sb_cmd_ollama() {
  local -- arg=$*
  case $arg in
    off|0|false) _SB_OLLAMA=0 ;;
    '')          _SB_OLLAMA=1 ;;
    *)
      if [[ ! $arg =~ ^[A-Za-z0-9._:/-]+$ ]]; then
        _error "invalid model name: ${arg@Q}"
        return 1
      fi
      _SB_OLLAMA=1
      export OLLAMA_MODEL=$arg
      ;;
  esac
  if ((_SB_OLLAMA)); then
    printf 'ollama: on (model=%s)\n' "${OLLAMA_MODEL:-<default>}"
  else
    printf 'ollama: off\n'
  fi
}

_sb_complete_ollama() {
  local -- cur=${COMP_WORDS[COMP_CWORD]}
  COMPREPLY=()
  readarray -t COMPREPLY < <(compgen -W 'off 0 false' -- "$cur")
}

_SB_HANDLERS[/ollama]=_sb_cmd_ollama
_SB_HELP[/ollama]='toggle ollama backend (model name | off | empty)'
_SB_COMPLETE[/ollama]=_sb_complete_ollama

#fin
