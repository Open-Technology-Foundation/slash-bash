#!/usr/bin/bash
#shellcheck shell=bash disable=SC2034
# handlers.d/_kbs.bash - /kbs and /knowledgebases [--select|--list]
# Lazy-loads _SB_KB_LIST from $_SB_KB_ROOT (default /var/lib/vectordbs)
# or SB_KB_LIST env var. Empty list is informational, not an error.

_sb_cmd_kbs() {
  local -- mode=${1:-}
  [[ $mode == *' '* ]] && { _error "unexpected arguments: ${mode#* }"; return 1; }
  _sb_load_kb_list
  if ((${#_SB_KB_LIST[@]} == 0)); then
    printf 'no knowledgebases found under %s\n' "$_SB_KB_ROOT"
    printf 'current: %s\n' "${_SB_KB:-<none>}"
    return 0
  fi
  case $mode in
    ''|--select) _sb_select_from_list kb _SB_KB "${_SB_KB_LIST[@]}" ;;
    --list)      _sb_print_list       kb _SB_KB "${_SB_KB_LIST[@]}" ;;
    *)           _error "unknown option: ${mode@Q} (expected --select or --list)"; return 1 ;;
  esac
}

_SB_HANDLERS[/kbs]=_sb_cmd_kbs
_SB_HANDLERS[/knowledgebases]=_sb_cmd_kbs
_SB_HELP[/kbs]='list / select a knowledgebase'

#fin
