#!/usr/bin/bash
#shellcheck shell=bash disable=SC2034
# handlers.d/_models.bash - /models [--select|--list]
# _SB_MODEL_LIST is initialised at library-source time from SB_MODEL_LIST
# env var; no lazy load needed.

_sb_cmd_models() {
  local -- mode=${1:-}
  [[ $mode == *' '* ]] && { _error "unexpected arguments: ${mode#* }"; return 1; }
  ((${#_SB_MODEL_LIST[@]})) || { _error 'no models configured'; return 1; }
  case $mode in
    ''|--select) _sb_select_from_list model _SB_MODEL "${_SB_MODEL_LIST[@]}" ;;
    --list)      _sb_print_list       model _SB_MODEL "${_SB_MODEL_LIST[@]}" ;;
    *)           _error "unknown option: ${mode@Q} (expected --select or --list)"; return 1 ;;
  esac
}

_SB_HANDLERS[/models]=_sb_cmd_models
_SB_HELP[/models]='list / select a model (--select default, --list prints)'

#fin
